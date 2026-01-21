#!/usr/bin/env python3
"""
ScopeStack Authentication Manager
Handles OAuth2 authentication with refresh token persistence
"""

import requests
import json
import os
import secrets
import hashlib
import base64
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import urlencode
import getpass


class AuthManager:
    """Manages ScopeStack OAuth2 authentication with token persistence"""

    def __init__(self, config_dir=None):
        """
        Initialize the auth manager

        Args:
            config_dir: Directory to store auth tokens (default: ~/.scopestack)
        """
        if config_dir is None:
            config_dir = Path.home() / '.scopestack'

        self.config_dir = Path(config_dir)
        self.config_dir.mkdir(exist_ok=True)

        self.token_file = self.config_dir / 'tokens.json'
        self.base_url = "https://app.scopestack.io"

        # OAuth2 client credentials (from environment variables)
        self.client_id = os.environ.get('SCOPESTACK_CLIENT_ID')
        self.client_secret = os.environ.get('SCOPESTACK_CLIENT_SECRET')

        self.tokens = None
        self.load_tokens()

    def load_tokens(self):
        """Load saved tokens from disk"""
        if self.token_file.exists():
            try:
                with open(self.token_file, 'r') as f:
                    self.tokens = json.load(f)
                    print(f"✓ Loaded saved credentials for {self.tokens.get('email', 'unknown')}")
            except Exception as e:
                print(f"⚠️  Could not load saved tokens: {e}")
                self.tokens = None

    def save_tokens(self):
        """Save tokens to disk"""
        if self.tokens:
            try:
                with open(self.token_file, 'w') as f:
                    json.dump(self.tokens, f, indent=2)
                # Set restrictive permissions
                os.chmod(self.token_file, 0o600)
                print(f"✓ Saved credentials securely to {self.token_file}")
            except Exception as e:
                print(f"⚠️  Could not save tokens: {e}")

    def is_token_expired(self):
        """Check if the access token is expired"""
        if not self.tokens or 'expires_at' not in self.tokens:
            return True

        expires_at = datetime.fromisoformat(self.tokens['expires_at'])
        # Consider expired if less than 5 minutes remaining
        return datetime.now() >= (expires_at - timedelta(minutes=5))

    def login(self, email=None, password=None, force_new=False):
        """
        Login to ScopeStack with email/password

        Args:
            email: User email (will prompt if not provided)
            password: User password (will prompt if not provided)
            force_new: Force new login even if valid tokens exist

        Returns:
            bool: True if login successful
        """
        # Check if we have valid tokens
        if not force_new and self.tokens and not self.is_token_expired():
            print("✓ Already authenticated with valid token")
            return True

        # Try to refresh if we have a refresh token
        if not force_new and self.tokens and 'refresh_token' in self.tokens:
            print("⟳ Attempting to refresh access token...")
            if self.refresh_access_token():
                return True
            print("⚠️  Token refresh failed, need to login again")

        # Need to do full login
        if not self.client_id or not self.client_secret:
            print("✗ SCOPESTACK_CLIENT_ID and SCOPESTACK_CLIENT_SECRET environment variables must be set")
            return False

        if not email:
            email = input("ScopeStack Email: ").strip()

        if not password:
            password = getpass.getpass("ScopeStack Password: ")

        print("🔐 Authenticating...")

        try:
            response = requests.post(
                f"{self.base_url}/oauth/token",
                data={
                    'grant_type': 'password',
                    'client_id': self.client_id,
                    'client_secret': self.client_secret,
                    'username': email,
                    'password': password
                }
            )
            response.raise_for_status()

            auth_data = response.json()

            # Calculate expiration time
            expires_in = auth_data.get('expires_in', 7200)  # Default 2 hours
            expires_at = datetime.now() + timedelta(seconds=expires_in)

            # Get user info
            user_info = self.get_user_info(auth_data['access_token'])

            self.tokens = {
                'auth_type': 'password',
                'email': email,
                'access_token': auth_data['access_token'],
                'refresh_token': auth_data.get('refresh_token'),
                'expires_in': expires_in,
                'expires_at': expires_at.isoformat(),
                'account_slug': user_info.get('account_slug'),
                'account_id': user_info.get('account_id'),
                'authenticated_at': datetime.now().isoformat()
            }

            self.save_tokens()
            print(f"✓ Successfully authenticated as {email}")
            return True

        except requests.exceptions.RequestException as e:
            print(f"✗ Authentication failed: {e}")
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    print(f"   Error: {error_detail}")
                except:
                    print(f"   Status: {e.response.status_code}")
            return False

    def refresh_access_token(self):
        """
        Refresh the access token using refresh token

        Returns:
            bool: True if refresh successful
        """
        if not self.tokens or 'refresh_token' not in self.tokens:
            return False

        if not self.client_id or not self.client_secret:
            return False

        try:
            response = requests.post(
                f"{self.base_url}/oauth/token",
                data={
                    'grant_type': 'refresh_token',
                    'client_id': self.client_id,
                    'client_secret': self.client_secret,
                    'refresh_token': self.tokens['refresh_token']
                }
            )
            response.raise_for_status()

            auth_data = response.json()

            # Update tokens
            expires_in = auth_data.get('expires_in', 7200)
            expires_at = datetime.now() + timedelta(seconds=expires_in)

            self.tokens['access_token'] = auth_data['access_token']
            if 'refresh_token' in auth_data:
                self.tokens['refresh_token'] = auth_data['refresh_token']
            self.tokens['expires_in'] = expires_in
            self.tokens['expires_at'] = expires_at.isoformat()
            self.tokens['refreshed_at'] = datetime.now().isoformat()

            self.save_tokens()
            print("✓ Access token refreshed")
            return True

        except requests.exceptions.RequestException as e:
            print(f"⚠️  Token refresh failed: {e}")
            return False

    def get_user_info(self, access_token):
        """
        Get user information from ScopeStack API

        Args:
            access_token: The access token to use

        Returns:
            dict: User information
        """
        try:
            response = requests.get(
                "https://api.scopestack.io/v1/me",
                headers={
                    'Authorization': f'Bearer {access_token}',
                    'Accept': 'application/vnd.api+json'
                }
            )
            response.raise_for_status()

            user_data = response.json()
            return {
                'account_slug': user_data.get('data', {}).get('attributes', {}).get('account-slug'),
                'account_id': user_data.get('data', {}).get('attributes', {}).get('account-id'),
                'email': user_data.get('data', {}).get('attributes', {}).get('email')
            }
        except:
            return {}

    # ==================== OAuth Authorization Code Flow with PKCE ====================

    def generate_pkce_pair(self) -> tuple:
        """
        Generate PKCE code_verifier and code_challenge

        Returns:
            tuple: (code_verifier, code_challenge)
        """
        code_verifier = secrets.token_urlsafe(32)
        digest = hashlib.sha256(code_verifier.encode()).digest()
        code_challenge = base64.urlsafe_b64encode(digest).rstrip(b'=').decode()
        return code_verifier, code_challenge

    def generate_state(self) -> str:
        """Generate random state for CSRF protection"""
        return secrets.token_urlsafe(32)

    def get_authorization_url(self, redirect_uri: str, state: str, code_challenge: str) -> str:
        """
        Build the ScopeStack authorization URL for OAuth2 Authorization Code Flow

        Args:
            redirect_uri: The callback URL to redirect to after authorization
            state: Random state for CSRF protection
            code_challenge: PKCE code challenge (S256)

        Returns:
            str: The full authorization URL
        """
        params = {
            'client_id': self.client_id,
            'redirect_uri': redirect_uri,
            'response_type': 'code',
            'state': state,
            'code_challenge': code_challenge,
            'code_challenge_method': 'S256',
        }
        return f"{self.base_url}/oauth/authorize?{urlencode(params)}"

    def exchange_code_for_tokens(self, code: str, redirect_uri: str, code_verifier: str) -> dict:
        """
        Exchange authorization code for tokens, then fetch /me for account context

        Args:
            code: The authorization code received from callback
            redirect_uri: The same redirect_uri used in authorization request
            code_verifier: The PKCE code verifier

        Returns:
            dict: {'success': True, 'account': {...}} or {'success': False, 'error': '...'}
        """
        if not self.client_id or not self.client_secret:
            return {'success': False, 'error': 'Client credentials not configured'}

        try:
            # Exchange code for tokens
            response = requests.post(
                f"{self.base_url}/oauth/token",
                data={
                    'grant_type': 'authorization_code',
                    'client_id': self.client_id,
                    'client_secret': self.client_secret,
                    'code': code,
                    'redirect_uri': redirect_uri,
                    'code_verifier': code_verifier
                }
            )
            response.raise_for_status()

            auth_data = response.json()

            # Calculate expiration time
            expires_in = auth_data.get('expires_in', 7200)
            expires_at = datetime.now() + timedelta(seconds=expires_in)

            # Get user info from /v1/me
            user_info = self.get_user_info(auth_data['access_token'])

            self.tokens = {
                'auth_type': 'authorization_code',
                'email': user_info.get('email'),
                'access_token': auth_data['access_token'],
                'refresh_token': auth_data.get('refresh_token'),
                'expires_in': expires_in,
                'expires_at': expires_at.isoformat(),
                'account_slug': user_info.get('account_slug'),
                'account_id': user_info.get('account_id'),
                'authenticated_at': datetime.now().isoformat()
            }

            self.save_tokens()
            return {
                'success': True,
                'account': {
                    'email': user_info.get('email'),
                    'account_slug': user_info.get('account_slug'),
                    'account_id': user_info.get('account_id')
                }
            }

        except requests.exceptions.RequestException as e:
            error_msg = str(e)
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    error_msg = error_detail.get('error_description', error_detail.get('error', str(e)))
                except:
                    error_msg = f"HTTP {e.response.status_code}"
            return {'success': False, 'error': error_msg}

    def get_access_token(self):
        """
        Get a valid access token, refreshing if necessary

        Returns:
            str: Valid access token or None
        """
        if not self.tokens:
            print("⚠️  Not authenticated. Please login first.")
            return None

        # Refresh if expired
        if self.is_token_expired():
            if not self.refresh_access_token():
                print("⚠️  Could not refresh token. Please login again.")
                return None

        return self.tokens.get('access_token')

    def logout(self):
        """Logout and remove saved tokens"""
        if self.token_file.exists():
            self.token_file.unlink()
            print("✓ Logged out successfully")
        self.tokens = None

    def is_authenticated(self):
        """Check if user is authenticated with valid token"""
        if not self.tokens:
            return False

        # Try to get a valid token (will refresh if needed)
        token = self.get_access_token()
        return token is not None

    def get_account_info(self):
        """Get account information"""
        if not self.tokens:
            return None

        return {
            'auth_type': self.tokens.get('auth_type', 'password'),
            'email': self.tokens.get('email'),
            'account_slug': self.tokens.get('account_slug'),
            'account_id': self.tokens.get('account_id'),
            'authenticated_at': self.tokens.get('authenticated_at'),
            'expires_at': self.tokens.get('expires_at')
        }

    def save_ai_api_key(self, provider: str, api_key: str):
        """Save AI provider API key to secure storage"""
        if not self.tokens:
            self.tokens = {}

        # Store AI keys in a separate section
        if 'ai_keys' not in self.tokens:
            self.tokens['ai_keys'] = {}

        self.tokens['ai_keys'][provider] = api_key
        self.save_tokens()
        print(f"✓ Saved {provider} API key securely")

    def get_ai_api_key(self, provider: str) -> str:
        """Get AI provider API key from secure storage"""
        if not self.tokens or 'ai_keys' not in self.tokens:
            return None

        return self.tokens['ai_keys'].get(provider)

    def has_ai_api_key(self, provider: str) -> bool:
        """Check if AI provider API key exists"""
        return self.get_ai_api_key(provider) is not None

    def delete_ai_api_key(self, provider: str):
        """Delete AI provider API key"""
        if self.tokens and 'ai_keys' in self.tokens:
            self.tokens['ai_keys'].pop(provider, None)
            self.save_tokens()
            print(f"✓ Deleted {provider} API key")

    # AI Settings Persistence (separate from tokens for clarity)
    def get_ai_settings_file(self):
        """Get path to AI settings file"""
        return self.config_dir / 'ai_settings.json'

    def save_ai_settings(self, settings: dict):
        """Save AI settings to file"""
        try:
            settings_file = self.get_ai_settings_file()
            with open(settings_file, 'w') as f:
                json.dump(settings, f, indent=2)
            os.chmod(settings_file, 0o600)
            return True
        except Exception as e:
            print(f"⚠️  Could not save AI settings: {e}")
            return False

    def load_ai_settings(self) -> dict:
        """Load AI settings from file"""
        settings_file = self.get_ai_settings_file()
        default_settings = {
            'enabled': False,
            'provider': 'openai',
            'max_iterations': 4
        }

        if not settings_file.exists():
            return default_settings

        try:
            with open(settings_file, 'r') as f:
                settings = json.load(f)
                # Merge with defaults to ensure all keys exist
                return {**default_settings, **settings}
        except Exception as e:
            print(f"⚠️  Could not load AI settings: {e}")
            return default_settings

    # ==================== Multi-Account Management ====================

    def get_accounts_file(self):
        """Get path to accounts file"""
        return self.config_dir / 'accounts.json'

    def load_accounts(self) -> dict:
        """Load all saved accounts"""
        accounts_file = self.get_accounts_file()
        if not accounts_file.exists():
            return {'accounts': [], 'active_account': None}

        try:
            with open(accounts_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"⚠️  Could not load accounts: {e}")
            return {'accounts': [], 'active_account': None}

    def save_accounts(self, accounts_data: dict):
        """Save accounts to file"""
        try:
            accounts_file = self.get_accounts_file()
            with open(accounts_file, 'w') as f:
                json.dump(accounts_data, f, indent=2)
            os.chmod(accounts_file, 0o600)
            return True
        except Exception as e:
            print(f"⚠️  Could not save accounts: {e}")
            return False

    def add_account(self, email: str, password: str) -> dict:
        """
        Add a new account (logs in and saves credentials)

        Returns:
            dict with 'success' and account info or 'error'
        """
        # First, authenticate with the credentials
        try:
            response = requests.post(
                f"{self.base_url}/oauth/token",
                data={
                    'grant_type': 'password',
                    'client_id': self.client_id,
                    'client_secret': self.client_secret,
                    'username': email,
                    'password': password
                }
            )
            response.raise_for_status()

            auth_data = response.json()
            expires_in = auth_data.get('expires_in', 7200)
            expires_at = datetime.now() + timedelta(seconds=expires_in)

            # Get user info
            user_info = self.get_user_info(auth_data['access_token'])

            # Create account entry
            account = {
                'auth_type': 'password',
                'email': email,
                'access_token': auth_data['access_token'],
                'refresh_token': auth_data.get('refresh_token'),
                'expires_in': expires_in,
                'expires_at': expires_at.isoformat(),
                'account_slug': user_info.get('account_slug'),
                'account_id': user_info.get('account_id'),
                'authenticated_at': datetime.now().isoformat()
            }

            # Load existing accounts
            accounts_data = self.load_accounts()

            # Check if account already exists
            existing_idx = None
            for idx, acc in enumerate(accounts_data['accounts']):
                if acc['email'] == email:
                    existing_idx = idx
                    break

            if existing_idx is not None:
                accounts_data['accounts'][existing_idx] = account
            else:
                accounts_data['accounts'].append(account)

            # Set as active account
            accounts_data['active_account'] = email

            # Save accounts
            self.save_accounts(accounts_data)

            # Also update current tokens to use this account
            self.tokens = account
            self.save_tokens()

            return {
                'success': True,
                'account': {
                    'email': email,
                    'account_slug': user_info.get('account_slug'),
                    'account_id': user_info.get('account_id')
                }
            }

        except requests.exceptions.RequestException as e:
            return {'success': False, 'error': f'Authentication failed: {str(e)}'}

    def get_all_accounts(self) -> list:
        """Get list of all saved accounts (without tokens)"""
        accounts_data = self.load_accounts()
        accounts_list = []

        # Check if there's a currently authenticated account from the token file
        # that's not yet in the accounts list
        current_account = None
        if self.is_authenticated():
            current_info = self.get_account_info()
            if current_info:
                current_email = current_info.get('email') or (self.tokens.get('email') if self.tokens else 'Current Account')
                # Check if this account is already in the list
                existing_emails = [acc.get('email') for acc in accounts_data['accounts']]
                if current_email not in existing_emails:
                    current_account = {
                        'email': current_email,
                        'account_slug': current_info.get('account_slug'),
                        'account_id': current_info.get('account_id'),
                        'is_active': True
                    }

        # Build list from saved accounts
        for acc in accounts_data['accounts']:
            accounts_list.append({
                'email': acc['email'],
                'account_slug': acc.get('account_slug'),
                'account_id': acc.get('account_id'),
                'is_active': acc['email'] == accounts_data.get('active_account')
            })

        # Add current account if not in list
        if current_account:
            accounts_list.insert(0, current_account)

        return accounts_list

    def switch_account(self, email: str) -> dict:
        """Switch to a different saved account"""
        accounts_data = self.load_accounts()

        # Find the account
        account = None
        for acc in accounts_data['accounts']:
            if acc['email'] == email:
                account = acc
                break

        if not account:
            return {'success': False, 'error': f'Account {email} not found'}

        # Set as active
        accounts_data['active_account'] = email
        self.save_accounts(accounts_data)

        # Update current tokens
        self.tokens = account
        self.save_tokens()

        # Check if token needs refresh
        if self.is_token_expired():
            if not self.refresh_access_token():
                return {'success': False, 'error': 'Token refresh failed. Please re-authenticate.'}

        return {
            'success': True,
            'account': {
                'email': email,
                'account_slug': account.get('account_slug'),
                'account_id': account.get('account_id')
            }
        }

    def remove_account(self, email: str) -> dict:
        """Remove a saved account"""
        accounts_data = self.load_accounts()

        # Find and remove the account
        accounts_data['accounts'] = [
            acc for acc in accounts_data['accounts']
            if acc['email'] != email
        ]

        # If removing active account, switch to another or clear
        if accounts_data.get('active_account') == email:
            if accounts_data['accounts']:
                accounts_data['active_account'] = accounts_data['accounts'][0]['email']
                # Switch to first remaining account
                self.switch_account(accounts_data['active_account'])
            else:
                accounts_data['active_account'] = None
                self.tokens = None
                if self.token_file.exists():
                    self.token_file.unlink()

        self.save_accounts(accounts_data)
        return {'success': True}


def main():
    """CLI for auth manager"""
    import sys

    auth = AuthManager()

    if len(sys.argv) < 2:
        print("ScopeStack Authentication Manager")
        print("\nCommands:")
        print("  login   - Login with email/password")
        print("  logout  - Logout and clear saved tokens")
        print("  status  - Show authentication status")
        print("  refresh - Refresh access token")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == 'login':
        auth.login()

    elif command == 'logout':
        auth.logout()

    elif command == 'status':
        if auth.is_authenticated():
            info = auth.get_account_info()
            print("✓ Authenticated")
            print(f"  Email: {info['email']}")
            print(f"  Account: {info['account_slug']} (ID: {info['account_id']})")
            print(f"  Authenticated: {info['authenticated_at']}")
            print(f"  Expires: {info['expires_at']}")
            print(f"  Token file: {auth.token_file}")
        else:
            print("✗ Not authenticated")
            print("Run: python auth_manager.py login")

    elif command == 'refresh':
        if auth.refresh_access_token():
            print("✓ Token refreshed successfully")
        else:
            print("✗ Could not refresh token")
            print("Run: python auth_manager.py login")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()
