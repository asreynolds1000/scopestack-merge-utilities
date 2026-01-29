# Authentication Guide

## Overview

The ScopeStack Template Converter now supports persistent authentication using OAuth2 with refresh tokens. This means you can login once and stay authenticated across sessions, making it easier to validate templates against live ScopeStack project data.

## Features

✅ **Persistent Sessions** - Login once, stay authenticated
✅ **Automatic Token Refresh** - Tokens are automatically refreshed when they expire
✅ **Secure Storage** - Tokens stored securely in `~/.scopestack/tokens.json` with 600 permissions
✅ **Web UI Integration** - Beautiful login modal in the web interface
✅ **CLI Support** - Command-line authentication for advanced users

## Web Interface Authentication

### How to Login

1. **Open the web interface** at http://127.0.0.1:5001
2. **Look for the authentication bar** at the top of the page
3. **Click the "Login" button** to open the login modal
4. **Enter your credentials**:
   - ScopeStack email address
   - ScopeStack password
5. **Click "Login"** to authenticate

### Authentication Status

The authentication bar shows your current status:

- **Red indicator** = Not authenticated
- **Green indicator** = Authenticated
- **Email display** = Shows your logged-in email

### Using Validation with Authentication

Once authenticated:

1. Upload your template as usual
2. Click **"Validate Against Project"**
3. Enter only the **Project ID** (no need for email/password anymore!)
4. Click **"Run Validation"**

The system will automatically use your stored authentication token.

### Logout

Click the **"Logout"** button in the authentication bar to:
- Clear your stored tokens
- Remove authentication from the web interface
- Require re-authentication for validation features

## CLI Authentication

### Login via CLI

```bash
cd /path/to/ScopeStack-doc-converter
python3 auth_manager.py login
```

You'll be prompted for:
- ScopeStack Email
- ScopeStack Password

### Check Authentication Status

```bash
python3 auth_manager.py status
```

Shows:
- Authentication status
- Email address
- Account slug and ID
- Token expiration time
- Token file location

### Refresh Token

```bash
python3 auth_manager.py refresh
```

Manually refresh your access token using the stored refresh token.

### Logout

```bash
python3 auth_manager.py logout
```

Removes stored tokens from disk.

## How Authentication Works

### OAuth2 Password Grant Flow

1. **Initial Login**:
   - User provides email + password
   - App exchanges credentials for access token + refresh token
   - Tokens stored in `~/.scopestack/tokens.json`

2. **Token Expiration**:
   - Access tokens expire after ~2 hours
   - System automatically checks expiration before each use
   - Automatically refreshes using refresh token if needed

3. **Token Refresh**:
   - Refresh token used to get new access token
   - No re-authentication required
   - Happens transparently in the background

4. **Logout**:
   - Deletes token file
   - Clears in-memory tokens
   - Requires fresh login next time

### Token Storage

Tokens are stored in:
```
~/.scopestack/tokens.json
```

This file contains:
- `email` - Your ScopeStack email
- `access_token` - Current access token
- `refresh_token` - Refresh token for getting new access tokens
- `expires_at` - When the access token expires
- `account_slug` - Your account identifier
- `account_id` - Your account ID

**Security**: File permissions are set to `600` (owner read/write only).

## Architecture

### Components

1. **`auth_manager.py`**
   - Handles OAuth2 authentication
   - Manages token storage and refresh
   - Provides CLI interface

2. **`app.py` - Flask Routes**
   - `/api/auth/status` - Check authentication status
   - `/api/auth/login` - Login with credentials
   - `/api/auth/logout` - Logout and clear tokens
   - `/api/validate` - Modified to use stored auth

3. **`templates/index.html`**
   - Authentication status bar
   - Login modal UI
   - JavaScript functions for auth flow

### Class: `AuthManager`

Key methods:

```python
# Initialize (loads saved tokens if they exist)
auth = AuthManager()

# Login with credentials
auth.login(email, password)

# Check if authenticated
if auth.is_authenticated():
    # Do something

# Get valid access token (auto-refreshes if needed)
token = auth.get_access_token()

# Get account information
info = auth.get_account_info()

# Logout
auth.logout()
```

### Integration with Web UI

The web interface automatically:

1. **Checks auth status on page load**
2. **Updates UI based on authentication state**
3. **Shows login modal if not authenticated and validation is attempted**
4. **Uses stored tokens for validation requests**
5. **Handles token refresh transparently**

## Troubleshooting

### "Authentication failed" on login

- **Check credentials** - Ensure email and password are correct
- **Check network** - Ensure you can reach app.scopestack.io
- **Try CLI login** - Use `python3 auth_manager.py login` to see detailed error messages

### "Authentication token expired" during validation

- **Token refresh failed** - Logout and login again
- **Refresh token expired** - These expire after ~30 days of inactivity
- **Solution**: Just login again via web UI or CLI

### Token file not found

- **First time use** - Normal! Just login to create tokens
- **After logout** - Expected behavior
- **Accidental deletion** - Just login again

### Permissions error on token file

```bash
chmod 600 ~/.scopestack/tokens.json
```

## Security Best Practices

✅ **Don't share token file** - Contains your authentication credentials
✅ **Don't commit to git** - `.gitignore` already excludes it
✅ **Use secure password** - Standard password best practices
✅ **Logout when done** - On shared machines, logout to clear tokens
✅ **Check file permissions** - Should be `600` (owner only)

## API Reference

### POST /api/auth/login

**Request Body**:
```json
{
  "email": "your.email@company.com",
  "password": "your-password"
}
```

**Success Response** (200):
```json
{
  "success": true,
  "account": {
    "email": "your.email@company.com",
    "account_slug": "your-account",
    "account_id": 12345,
    "authenticated_at": "2026-01-16T15:00:00",
    "expires_at": "2026-01-16T17:00:00"
  }
}
```

**Error Response** (401):
```json
{
  "error": "Authentication failed"
}
```

### GET /api/auth/status

**Success Response** (200):
```json
{
  "authenticated": true,
  "account": {
    "email": "your.email@company.com",
    "account_slug": "your-account",
    "account_id": 12345,
    "authenticated_at": "2026-01-16T15:00:00",
    "expires_at": "2026-01-16T17:00:00"
  }
}
```

**Not Authenticated** (200):
```json
{
  "authenticated": false
}
```

### POST /api/auth/logout

**Success Response** (200):
```json
{
  "success": true
}
```

### POST /api/validate (Updated)

Now requires authentication via stored tokens.

**Request Body**:
```json
{
  "project_id": "{project_id}"
}
```

Note: Email and password no longer required - uses stored authentication!

**Error if not authenticated** (401):
```json
{
  "error": "Not authenticated. Please login first."
}
```

## Migration from Old Validation

### Before (Required credentials every time):

```json
{
  "project_id": "{project_id}",
  "email": "your.email@company.com",
  "password": "your-password"
}
```

### After (Login once, use project ID only):

```json
{
  "project_id": "{project_id}"
}
```

## Benefits

1. **Better Security**
   - Passwords not sent with every request
   - Tokens can be revoked
   - Shorter-lived access tokens

2. **Better UX**
   - Login once, use many times
   - No need to re-enter credentials
   - Automatic token refresh

3. **Better Architecture**
   - Centralized auth management
   - Reusable across CLI and web
   - Follows OAuth2 best practices

## Future Enhancements

Potential improvements for later:

- [ ] Remember last used project ID
- [ ] Multi-account support
- [ ] Token expiry warnings
- [ ] SSO/SAML integration
- [ ] API key support (alternative to password)
- [ ] Session management UI (view/revoke tokens)

## Summary

The authentication system provides:

✅ Persistent login across sessions
✅ Automatic token refresh
✅ Secure token storage
✅ Clean web UI integration
✅ CLI support for automation
✅ OAuth2 best practices

Now you can login once and validate templates against live projects without re-entering credentials every time!
