#!/usr/bin/env python3
"""
ScopeStack Merge Data Fetcher
Fetches merge data from ScopeStack API for template validation
"""

import requests
import json
import sys
import os
from typing import Dict, List, Set
from pathlib import Path


class MergeDataFetcher:
    """Fetches and parses merge data from ScopeStack"""

    def __init__(self, base_url: str = "https://app.scopestack.io"):
        self.base_url = base_url
        self.session = requests.Session()
        self.auth_token = None

    def authenticate(self, email: str = None, password: str = None, token: str = None):
        """
        Authenticate with ScopeStack
        Can use either email/password or a bearer token
        """
        if token:
            self.auth_token = token
            self.session.headers.update({
                'Authorization': f'Bearer {token}',
                'Accept': 'application/vnd.api+json'
            })
            return True

        if email and password:
            # OAuth2 password grant flow
            auth_url = f"{self.base_url}/oauth/token"

            client_id = os.environ.get('SCOPESTACK_CLIENT_ID')
            client_secret = os.environ.get('SCOPESTACK_CLIENT_SECRET')

            if not client_id or not client_secret:
                print("✗ SCOPESTACK_CLIENT_ID and SCOPESTACK_CLIENT_SECRET environment variables must be set")
                return False

            payload = {
                'grant_type': 'password',
                'client_id': client_id,
                'client_secret': client_secret,
                'username': email,
                'password': password
            }

            try:
                response = self.session.post(auth_url, data=payload)
                response.raise_for_status()

                auth_data = response.json()
                self.auth_token = auth_data['access_token']

                self.session.headers.update({
                    'Authorization': f'Bearer {self.auth_token}',
                    'Accept': 'application/vnd.api+json'
                })

                print("✓ Successfully authenticated with ScopeStack")
                return True

            except requests.exceptions.RequestException as e:
                print(f"✗ Authentication failed: {e}")
                return False

        raise ValueError("Must provide either token or email/password for authentication")

    def get_account_info(self) -> Dict:
        """
        Get account information from the API to retrieve account slug
        Returns dict with 'account_slug' and 'account_id'
        """
        try:
            response = self.session.get(
                "https://api.scopestack.io/v1/me",
                headers={
                    'Authorization': f'Bearer {self.auth_token}',
                    'Accept': 'application/vnd.api+json'
                }
            )
            response.raise_for_status()

            user_data = response.json()
            return {
                'account_slug': user_data.get('data', {}).get('attributes', {}).get('account-slug'),
                'account_id': user_data.get('data', {}).get('attributes', {}).get('account-id')
            }
        except requests.exceptions.RequestException as e:
            print(f"Error getting account info: {e}")
            return None

    def get_client(self, client_id: str = None, client_name: str = None, domain: str = None) -> Dict:
        """
        Get a client from ScopeStack by ID, name, or domain
        Based on Workato connector pattern

        Args:
            client_id: The unique identifier of the client (takes precedence)
            client_name: The name of the client to find
            domain: The domain associated with the client

        Returns:
            Client data dict or None
        """
        account_info = self.get_account_info()
        if not account_info or not account_info['account_slug']:
            print("Error: Could not get account slug")
            return None

        account_slug = account_info['account_slug']

        try:
            if client_id:
                # Get by ID
                url = f"https://api.scopestack.io/{account_slug}/v1/clients/{client_id}"
                print(f"Fetching client by ID: {client_id}")

                response = self.session.get(
                    url,
                    headers={
                        'Authorization': f'Bearer {self.auth_token}',
                        'Accept': 'application/vnd.api+json'
                    }
                )
                response.raise_for_status()
                data = response.json()
                return data.get('data')

            elif client_name or domain:
                # Search by name or domain
                url = f"https://api.scopestack.io/{account_slug}/v1/clients"
                filter_params = {}

                if client_name:
                    filter_params['name'] = client_name
                if domain:
                    filter_params['domain'] = domain

                print(f"Searching for client with filters: {filter_params}")

                response = self.session.get(
                    url,
                    params={'filter': filter_params},
                    headers={
                        'Authorization': f'Bearer {self.auth_token}',
                        'Accept': 'application/vnd.api+json'
                    }
                )
                response.raise_for_status()
                data = response.json()

                if not data.get('data'):
                    print(f"No client found matching criteria")
                    return None

                # Return first match
                return data['data'][0]
            else:
                print("Error: Must provide client_id, client_name, or domain")
                return None

        except requests.exceptions.RequestException as e:
            print(f"Error fetching client: {e}")
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    print(f"   Error detail: {error_detail}")
                except:
                    print(f"   Status: {e.response.status_code}")
            return None

    def get_document_template(self, template_name: str) -> Dict:
        """
        Get a document template by name

        Args:
            template_name: Exact name of the document template (case-sensitive)

        Returns:
            Document template data or None
        """
        account_info = self.get_account_info()
        if not account_info or not account_info['account_slug']:
            print("Error: Could not get account slug")
            return None

        account_slug = account_info['account_slug']
        url = f"https://api.scopestack.io/{account_slug}/v1/document-templates"

        try:
            response = self.session.get(
                url,
                params={'filter': {'name': template_name}},
                headers={
                    'Authorization': f'Bearer {self.auth_token}',
                    'Accept': 'application/vnd.api+json'
                }
            )
            response.raise_for_status()
            data = response.json()

            if not data.get('data'):
                print(f"No document template found with name: {template_name}")
                return None

            if len(data['data']) > 1:
                print(f"Warning: Multiple templates found with name: {template_name}. Using first one.")

            return data['data'][0]

        except requests.exceptions.RequestException as e:
            print(f"Error fetching document template: {e}")
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    print(f"   Error detail: {error_detail}")
                except:
                    print(f"   Status: {e.response.status_code}")
            return None

    def generate_project_document(self, project_id: str, template_id: str,
                                  document_type: str = 'sow',
                                  generate_pdf: bool = False,
                                  force_regeneration: bool = True,
                                  wait_for_completion: bool = True) -> Dict:
        """
        Generate a document from a template for a project

        Args:
            project_id: The project ID
            template_id: The template ID (or 'pricing'/'breakdown' for those types)
            document_type: Type of document ('sow', 'pricing', 'breakdown')
            generate_pdf: Generate as PDF (True) or original format (False)
            force_regeneration: Force new generation even if exists
            wait_for_completion: Wait for document to finish generating

        Returns:
            Document data with status and download URL
        """
        import time

        account_info = self.get_account_info()
        if not account_info or not account_info['account_slug']:
            print("Error: Could not get account slug")
            return None

        account_slug = account_info['account_slug']

        # Create document payload
        payload = {
            'data': {
                'type': 'project-documents',
                'attributes': {
                    'template-id': template_id,
                    'document-type': document_type,
                    'force-regeneration': force_regeneration,
                    'generate-pdf': generate_pdf
                },
                'relationships': {
                    'project': {
                        'data': {
                            'type': 'projects',
                            'id': project_id
                        }
                    }
                }
            }
        }

        print(f"Generating document for project {project_id} with template {template_id}...")

        try:
            # Create document
            url = f"https://api.scopestack.io/{account_slug}/v1/project-documents"
            response = self.session.post(
                url,
                json=payload,
                headers={
                    'Authorization': f'Bearer {self.auth_token}',
                    'Accept': 'application/vnd.api+json',
                    'Content-Type': 'application/vnd.api+json'
                }
            )
            response.raise_for_status()

            document_data = response.json()
            document_id = document_data['data']['id']

            print(f"✓ Document generation started (ID: {document_id})")

            if not wait_for_completion:
                return document_data['data']

            # Wait for completion
            max_attempts = 60  # 5 minutes with 5 second intervals
            attempts = 0

            print("⏳ Waiting for document generation to complete...")

            while attempts < max_attempts:
                # Check document status
                status_url = f"https://api.scopestack.io/{account_slug}/v1/project-documents/{document_id}"
                status_response = self.session.get(
                    status_url,
                    headers={
                        'Authorization': f'Bearer {self.auth_token}',
                        'Accept': 'application/vnd.api+json'
                    }
                )
                status_response.raise_for_status()

                status_data = status_response.json()
                status = status_data['data']['attributes']['status']

                if status == 'finished':
                    print(f"✓ Document generated successfully!")
                    document_url = status_data['data']['attributes'].get('document-url')
                    if document_url:
                        print(f"  Download URL: {document_url}")
                    return status_data['data']

                elif status == 'error':
                    error_text = status_data['data']['attributes'].get('error-text', 'Unknown error')
                    print(f"✗ Document generation failed: {error_text}")
                    return None

                attempts += 1
                if attempts < max_attempts:
                    time.sleep(5)
                    print(f"  Status: {status} (attempt {attempts}/{max_attempts})")

            print("✗ Document generation timed out after 5 minutes")
            return None

        except requests.exceptions.RequestException as e:
            print(f"Error generating document: {e}")
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    print(f"   Error detail: {error_detail}")
                except:
                    print(f"   Status: {e.response.status_code}")
            return None

    def fetch_v1_merge_data(self, project_id: str) -> Dict:
        """
        Fetch v1 merge data using the API endpoint
        URL pattern: https://api.scopestack.io/{account_slug}/v1/projects/{project_id}/merge-data

        Returns the raw v1 merge data structure
        """
        # Get account slug first
        account_info = self.get_account_info()
        if not account_info or not account_info['account_slug']:
            print("Error: Could not get account slug")
            return None

        account_slug = account_info['account_slug']
        url = f"https://api.scopestack.io/{account_slug}/v1/projects/{project_id}/merge-data"

        print(f"Fetching v1 merge data from: {url}")

        try:
            response = self.session.get(
                url,
                headers={
                    'Authorization': f'Bearer {self.auth_token}',
                    'Accept': 'application/vnd.api+json'
                }
            )
            response.raise_for_status()

            data = response.json()
            print(f"✓ Successfully fetched v1 merge data for project {project_id}")
            return data

        except requests.exceptions.RequestException as e:
            print(f"Error fetching v1 merge data: {e}")
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    print(f"   Error detail: {error_detail}")
                except:
                    print(f"   Status: {e.response.status_code}")
            return None

    def fetch_v2_merge_data(self, project_id: str) -> Dict:
        """
        Fetch v2 merge data using the API endpoint with filter parameter
        URL pattern: https://api.scopestack.io/{account_slug}/v1/projects/{project_id}/merge-data?filter[version]=2

        Returns the raw v2 merge data structure
        """
        # Get account slug first
        account_info = self.get_account_info()
        if not account_info or not account_info['account_slug']:
            print("Error: Could not get account slug")
            return None

        account_slug = account_info['account_slug']
        url = f"https://api.scopestack.io/{account_slug}/v1/projects/{project_id}/merge-data"

        print(f"Fetching v2 merge data from: {url}")

        try:
            response = self.session.get(
                url,
                params={'filter[version]': '2'},
                headers={
                    'Authorization': f'Bearer {self.auth_token}',
                    'Accept': 'application/vnd.api+json'
                }
            )
            response.raise_for_status()

            data = response.json()
            print(f"✓ Successfully fetched v2 merge data for project {project_id}")
            return data

        except requests.exceptions.RequestException as e:
            print(f"Error fetching v2 merge data: {e}")
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    print(f"   Error detail: {error_detail}")
                except:
                    print(f"   Status: {e.response.status_code}")
            return None

    def fetch_merge_data(self, project_id: str, version: int = 2, use_api: bool = True) -> Dict:
        """
        Fetch merge data for a specific project

        For v1: Uses API endpoint /{account_slug}/v1/projects/{project_id}/merge-data
        For v2: Uses API endpoint with filter or visualization endpoint

        Args:
            project_id: The project ID
            version: 1 or 2
            use_api: If True, use API endpoint; if False, use visualization HTML endpoint
        """
        if version == 1:
            return self.fetch_v1_merge_data(project_id)

        if use_api:
            # Use API endpoint for v2
            return self.fetch_v2_merge_data(project_id)

        # Fall back to visualization endpoint (legacy)
        url = f"{self.base_url}/projects/{project_id}/merge_data_visualization?version={version}"

        print(f"Fetching merge data from: {url}")

        try:
            response = self.session.get(url)
            response.raise_for_status()

            # The response might be HTML with embedded JSON or a direct JSON response
            content_type = response.headers.get('Content-Type', '')

            if 'application/json' in content_type:
                return response.json()
            else:
                # Parse HTML to extract data structure
                return self._parse_html_merge_data(response.text)

        except requests.exceptions.RequestException as e:
            print(f"Error fetching merge data: {e}")
            return None

    def _parse_html_merge_data(self, html_content: str) -> Dict:
        """
        Parse HTML merge data visualization to extract field structure
        """
        from html.parser import HTMLParser

        class MergeDataHTMLParser(HTMLParser):
            def __init__(self):
                super().__init__()
                self.fields = []
                self.current_field = None
                self.in_dt = False
                self.in_dd = False

            def handle_starttag(self, tag, attrs):
                if tag == 'dt':
                    self.in_dt = True
                elif tag == 'dd':
                    self.in_dd = True

            def handle_endtag(self, tag):
                if tag == 'dt':
                    self.in_dt = False
                elif tag == 'dd':
                    self.in_dd = False
                    if self.current_field:
                        self.current_field = None

            def handle_data(self, data):
                data = data.strip()
                if self.in_dt and data:
                    self.current_field = data
                    self.fields.append(data)

        parser = MergeDataHTMLParser()
        parser.feed(html_content)

        # Build a structure from the fields
        return {
            'fields': parser.fields,
            'field_count': len(parser.fields),
            'unique_fields': list(set(parser.fields))
        }

    def get_available_fields(self, project_id: str, version: int = 2) -> List[str]:
        """
        Get a list of all available fields for a project
        Extracts field paths from nested v2 merge data structure
        """
        if version == 1:
            data = self.fetch_v1_merge_data(project_id)
        else:
            data = self.fetch_v2_merge_data(project_id)

        if not data:
            return []

        # Extract all field paths from the nested structure
        fields = []

        def extract_paths(obj, prefix=""):
            """Recursively extract all field paths"""
            if isinstance(obj, dict):
                for key, value in obj.items():
                    path = f"{prefix}.{key}" if prefix else key
                    fields.append(path)
                    if isinstance(value, (dict, list)):
                        extract_paths(value, path)
            elif isinstance(obj, list) and obj:
                # For arrays, extract paths from first item
                extract_paths(obj[0], prefix)

        extract_paths(data)
        return sorted(set(fields))

    def validate_template_fields(self, template_fields: List[str], available_fields: List[str]) -> Dict[str, List[str]]:
        """
        Validate that template fields exist in merge data
        Returns dict with 'valid' and 'missing' field lists
        """
        def extract_field_name(tag):
            """Extract field name from both v1 and v2 formats"""
            # v1 format: =field_name, field:if, field:each
            if tag.startswith('='):
                # Simple field: =project_name -> project_name
                return tag[1:]
            elif ':if' in tag or ':each' in tag:
                # Conditional/loop: field:if(any?) -> field
                return tag.split(':')[0]
            elif ':end' in tag or ':else' in tag:
                # End markers - match the opening field
                return tag.split(':')[0]
            else:
                # v2 format: {project.client_name}
                # Remove { } and any prefixes like #, /, ~
                tag = tag.strip('{}#/~^')
                # Remove conditionals like .length>0
                tag = tag.split('.length')[0].split('==')[0].split('!=')[0]
                return tag

        template_field_names = [extract_field_name(f) for f in template_fields]

        # Build available field set (including nested paths)
        available_set = set(available_fields)

        valid = []
        missing = []

        for field in template_field_names:
            # Check if field or any parent path exists
            if field in available_set:
                valid.append(field)
            else:
                # Check for partial matches (parent objects)
                found = False
                for avail_field in available_set:
                    if field.startswith(avail_field + '.') or avail_field.startswith(field + '.'):
                        found = True
                        break
                if found:
                    valid.append(field)
                else:
                    missing.append(field)

        return {
            'valid': valid,
            'missing': missing,
            'coverage': len(valid) / len(template_field_names) if template_field_names else 0
        }


def save_merge_data(project_id: str, version: int = 2, output_file: str = None):
    """Fetch and save merge data to a file"""
    fetcher = MergeDataFetcher()

    # Check for auth token in environment
    token = os.environ.get('SCOPESTACK_TOKEN')
    if token:
        fetcher.authenticate(token=token)

    data = fetcher.fetch_merge_data(project_id, version)

    if data:
        if not output_file:
            output_file = f"merge_data_{project_id}_v{version}.json"

        with open(output_file, 'w') as f:
            json.dump(data, f, indent=2)

        print(f"✓ Merge data saved to: {output_file}")
        print(f"  Fields found: {data.get('field_count', 'unknown')}")
        return True

    return False


def main():
    """CLI entry point"""
    if len(sys.argv) < 2:
        print("ScopeStack Merge Data Fetcher")
        print("\nUsage:")
        print("  python merge_data_fetcher.py <project_id> [version] [output_file]")
        print("\nExample:")
        print("  python merge_data_fetcher.py 101735 2 merge_data.json")
        print("\nAuthentication (choose one method):")
        print("  1. Token: export SCOPESTACK_TOKEN='your_token_here'")
        print("  2. Credentials: export SCOPESTACK_EMAIL='user@example.com'")
        print("                  export SCOPESTACK_PASSWORD='your_password'")
        sys.exit(1)

    project_id = sys.argv[1]
    version = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    output_file = sys.argv[3] if len(sys.argv) > 3 else None

    # Enhanced authentication
    fetcher = MergeDataFetcher()

    # Try token first
    token = os.environ.get('SCOPESTACK_TOKEN')
    if token:
        fetcher.authenticate(token=token)
    else:
        # Try email/password
        email = os.environ.get('SCOPESTACK_EMAIL')
        password = os.environ.get('SCOPESTACK_PASSWORD')
        if email and password:
            fetcher.authenticate(email=email, password=password)
        else:
            print("⚠️  No authentication credentials found")
            print("   Set SCOPESTACK_TOKEN or SCOPESTACK_EMAIL/PASSWORD")
            print("   Attempting unauthenticated access...")

    data = fetcher.fetch_merge_data(project_id, version)

    if data:
        if not output_file:
            output_file = f"merge_data_{project_id}_v{version}.json"

        with open(output_file, 'w') as f:
            json.dump(data, f, indent=2)

        print(f"✓ Merge data saved to: {output_file}")
        print(f"  Fields found: {data.get('field_count', 'unknown')}")
        sys.exit(0)
    else:
        print("✗ Failed to fetch merge data")
        sys.exit(1)


if __name__ == '__main__':
    main()
