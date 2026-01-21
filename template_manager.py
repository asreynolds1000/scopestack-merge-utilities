#!/usr/bin/env python3
"""
ScopeStack Template Manager
============================

Manages document templates via ScopeStack API:
- List templates
- Download templates
- Upload new templates
- Generate documents from templates
"""

import requests
import json
from typing import Dict, List, Optional
from pathlib import Path
import os


class TemplateManager:
    """Manage document templates via ScopeStack API"""

    def __init__(self, base_url: str = "https://api.scopestack.io"):
        self.base_url = base_url
        self.session = requests.Session()
        self.auth_token = None
        self.account_slug = None

    def authenticate(self, token: str, account_slug: str = "scopestack-demo"):
        """
        Authenticate with ScopeStack API

        Args:
            token: OAuth2 access token
            account_slug: Account slug (default: scopestack-demo)
        """
        self.auth_token = token
        self.account_slug = account_slug
        self.session.headers.update({
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.api+json'
        })

    def list_templates(self, page: int = 1, page_size: int = 100,
                      active_only: bool = False) -> Dict:
        """
        List document templates

        Args:
            page: Page number
            page_size: Number of results per page
            active_only: If True, only show active templates

        Returns:
            API response with templates list
        """
        url = f"{self.base_url}/{self.account_slug}/v1/document-templates"

        params = {
            'page[number]': page,
            'page[size]': page_size
        }

        if active_only:
            params['filter[active]'] = 'true'
        else:
            params['filter[active]'] = 'true,false'

        print(f"Fetching templates from: {url}")
        response = self.session.get(url, params=params)
        response.raise_for_status()

        return response.json()

    def get_template_details(self, template_id: str) -> Dict:
        """
        Get detailed information about a specific template

        Args:
            template_id: Template ID

        Returns:
            API response with template details
        """
        url = f"{self.base_url}/{self.account_slug}/v1/document-templates/{template_id}"

        print(f"Fetching template details: {url}")
        response = self.session.get(url)
        response.raise_for_status()

        return response.json()

    def download_template(self, template_id: str, output_path: str) -> str:
        """
        Download a template file

        Args:
            template_id: Template ID
            output_path: Path to save the downloaded template

        Returns:
            Path to downloaded file
        """
        url = f"{self.base_url}/{self.account_slug}/v1/document-templates/{template_id}/download"

        print(f"Downloading template from: {url}")
        response = self.session.get(url)
        response.raise_for_status()

        # Save to file
        with open(output_path, 'wb') as f:
            f.write(response.content)

        print(f"✓ Template downloaded to: {output_path}")
        return output_path

    def create_template(
        self,
        name: str,
        filename: str,
        template_format: str = "v2",
        format_type: str = "tag_template",
        filename_format: List[str] = None,
        include_formatting: bool = True,
        active: bool = True,
        teams: List = None
    ) -> Dict:
        """
        Create a new document template (metadata only)

        Args:
            name: Template name
            filename: Template filename
            template_format: "v1" or "v2"
            format_type: "word_template" or "tag_template"
            filename_format: List of filename format fields
            include_formatting: Whether to include formatting
            active: Whether template is active
            teams: List of team IDs

        Returns:
            API response with created template info
        """
        url = f"{self.base_url}/{self.account_slug}/v1/document-templates"

        if filename_format is None:
            filename_format = ["project_name", "template_name", "current_date"]

        if teams is None:
            teams = []

        payload = {
            "data": {
                "type": "document-templates",
                "attributes": {
                    "name": name,
                    "format": format_type,
                    "filename-format": filename_format,
                    "merge-template-filename": filename,
                    "template-format": template_format,
                    "include-formatting": include_formatting,
                    "active": active,
                    "teams": teams
                },
                "relationships": {
                    "account": {
                        "data": {
                            "type": "accounts",
                            "id": 1  # Default account ID
                        }
                    }
                }
            }
        }

        print(f"Creating template: {name}")
        print(f"Debug - Payload: {json.dumps(payload, indent=2)}")
        self.session.headers.update({'Content-Type': 'application/vnd.api+json'})

        response = self.session.post(url, json=payload)

        # Debug: print response if error
        if response.status_code != 200 and response.status_code != 201:
            print(f"❌ API Error {response.status_code}: {response.text}")

        response.raise_for_status()

        # Reset content type
        self.session.headers.pop('Content-Type', None)

        result = response.json()
        template_id = result['data']['id']
        print(f"✓ Template created with ID: {template_id}")

        return result

    def upload_template_file(self, template_id: str, file_path: str) -> Dict:
        """
        Upload the actual template file to an existing template

        Args:
            template_id: Template ID (from create_template)
            file_path: Path to the .docx file to upload

        Returns:
            API response
        """
        url = f"{self.base_url}/{self.account_slug}/v1/document-templates/{template_id}/upload"

        print(f"Uploading template file: {file_path}")

        # Remove JSON content type for file upload
        headers = dict(self.session.headers)
        headers.pop('Content-Type', None)
        headers.pop('Accept', None)

        with open(file_path, 'rb') as f:
            files = {
                'document_template[merge_template]': (
                    os.path.basename(file_path),
                    f,
                    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
                )
            }

            response = requests.post(url, headers=headers, files=files)
            response.raise_for_status()

        print(f"✓ Template file uploaded successfully")
        return response.json() if response.content else {}

    def update_template(self, template_id: str, template_format: str = None,
                       format_type: str = None, name: str = None) -> Dict:
        """
        Update template metadata (format, type, name)

        Args:
            template_id: Template ID to update
            template_format: Template format ("v1" or "v2")
            format_type: Format type (e.g., "tag_template", "mail_merge")
            name: Optional new name

        Returns:
            API response
        """
        url = f"{self.base_url}/{self.account_slug}/v1/document-templates/{template_id}"

        attributes = {}
        if template_format is not None:
            attributes["template-format"] = template_format
        if format_type is not None:
            attributes["format"] = format_type
        if name is not None:
            attributes["name"] = name

        payload = {
            "data": {
                "type": "document-templates",
                "id": str(template_id),
                "attributes": attributes
            }
        }

        print(f"Updating template {template_id}: {attributes}")
        self.session.headers.update({'Content-Type': 'application/vnd.api+json'})

        response = self.session.patch(url, json=payload)
        response.raise_for_status()

        # Reset content type
        self.session.headers.pop('Content-Type', None)

        print(f"✓ Template updated successfully")
        return response.json()

    def generate_converted_template_name(self, v1_template_name: str,
                                        check_collision: bool = True) -> str:
        """
        Generate smart name for converted template with collision detection

        Args:
            v1_template_name: Original V1 template name
            check_collision: If True, check for existing templates and enumerate

        Returns:
            Available template name in format: "{base} - Converted - {date}"
            or "{base} - Converted - {date} - {N}" if collision exists
        """
        from datetime import date

        # Strip V1/v1 suffix if present
        base = v1_template_name.replace(' V1', '').replace(' v1', '')
        base = base.strip()

        # Generate proposed name
        today = date.today().strftime('%Y-%m-%d')
        proposed_name = f"{base} - Converted - {today}"

        if not check_collision:
            return proposed_name

        # Check for collisions
        try:
            templates = self.list_templates(page_size=1000)
            existing_names = [t['attributes']['name'] for t in templates['data']]

            # No collision - use proposed name
            if proposed_name not in existing_names:
                return proposed_name

            # Collision exists - enumerate
            counter = 2
            while True:
                enum_name = f"{proposed_name} - {counter}"
                if enum_name not in existing_names:
                    return enum_name
                counter += 1

        except Exception as e:
            print(f"⚠️  Could not check for name collisions: {e}")
            # Return proposed name without collision checking
            return proposed_name

    def check_template_health(self, template_id: str) -> Dict:
        """
        Download and check if template is corrupted

        Args:
            template_id: Template ID to check

        Returns:
            {
                'is_healthy': bool,
                'issue': str or None,
                'can_auto_recover': bool,
                'template_id': str
            }
        """
        import tempfile
        import zipfile

        try:
            # Download template to temp file
            with tempfile.NamedTemporaryFile(suffix='.docx', delete=False) as tmp:
                temp_path = tmp.name

            self.download_template(template_id, temp_path)

            # Check 1: Can we open as zip?
            try:
                with zipfile.ZipFile(temp_path, 'r') as zip_ref:
                    # Check 2: Does it have document.xml?
                    if 'word/document.xml' not in zip_ref.namelist():
                        os.unlink(temp_path)
                        return {
                            'is_healthy': False,
                            'issue': 'Missing word/document.xml',
                            'can_auto_recover': True,
                            'template_id': template_id
                        }

                    # Check 3: Can we read document.xml?
                    xml_content = zip_ref.read('word/document.xml').decode('utf-8')

                    # Check 4: Does XML start properly?
                    xml_start = xml_content[:200].strip()

                    # Corrupted if it starts with <w:t> instead of <?xml or <w:document
                    if xml_start.startswith('<w:t'):
                        os.unlink(temp_path)
                        return {
                            'is_healthy': False,
                            'issue': 'Template XML is corrupted (starts with <w:t> tag)',
                            'can_auto_recover': True,
                            'template_id': template_id
                        }

                    # Check 5: Does it have required elements?
                    if '<w:body>' not in xml_content:
                        os.unlink(temp_path)
                        return {
                            'is_healthy': False,
                            'issue': 'Template missing <w:body> element',
                            'can_auto_recover': True,
                            'template_id': template_id
                        }

                    # All checks passed
                    os.unlink(temp_path)
                    return {
                        'is_healthy': True,
                        'issue': None,
                        'can_auto_recover': False,
                        'template_id': template_id
                    }

            except zipfile.BadZipFile:
                os.unlink(temp_path)
                return {
                    'is_healthy': False,
                    'issue': 'File is not a valid .docx (zip) file',
                    'can_auto_recover': True,
                    'template_id': template_id
                }

        except Exception as e:
            return {
                'is_healthy': False,
                'issue': f'Health check failed: {str(e)}',
                'can_auto_recover': False,
                'template_id': template_id
            }

    def generate_document(self, template_id: str, project_id: str,
                         output_path: str = None) -> str:
        """
        Generate a document from a template for a specific project

        Args:
            template_id: Template ID
            project_id: Project ID
            output_path: Optional path to save generated document

        Returns:
            Path to generated document
        """
        # This would use the Workato connector or direct API if available
        # For now, this is a placeholder showing the intended workflow
        raise NotImplementedError(
            "Document generation requires Workato connector or additional API endpoint"
        )


def main():
    """Test the template manager"""
    import argparse
    from auth_manager import AuthManager

    parser = argparse.ArgumentParser(description='Manage ScopeStack document templates')
    parser.add_argument('command', choices=['list', 'download', 'create', 'upload'],
                       help='Command to execute')
    parser.add_argument('--template-id', help='Template ID')
    parser.add_argument('--output', help='Output file path')
    parser.add_argument('--file', help='File to upload')
    parser.add_argument('--name', help='Template name')
    parser.add_argument('--format', choices=['v1', 'v2'], default='v2',
                       help='Template format')

    args = parser.parse_args()

    # Authenticate
    auth = AuthManager()
    if not auth.is_authenticated():
        print("❌ Not authenticated. Please login first:")
        print("   python3 auth_manager.py login")
        return

    token = auth.get_access_token()
    if not token:
        print("❌ Could not get access token")
        return

    # Create manager
    manager = TemplateManager()
    manager.authenticate(token=token)

    # Execute command
    if args.command == 'list':
        result = manager.list_templates()
        print(f"\nFound {result['meta']['record-count']} templates:")
        print("=" * 80)
        for template in result['data']:
            attrs = template['attributes']
            print(f"ID: {template['id']}")
            print(f"  Name: {attrs['name']}")
            print(f"  Format: {attrs['template-format']}")
            print(f"  Active: {attrs['active']}")
            print(f"  File: {attrs['merge-template-filename']}")
            print()

    elif args.command == 'download':
        if not args.template_id or not args.output:
            print("❌ --template-id and --output are required")
            return

        manager.download_template(args.template_id, args.output)

    elif args.command == 'create':
        if not args.name or not args.file:
            print("❌ --name and --file are required")
            return

        result = manager.create_template(
            name=args.name,
            filename=os.path.basename(args.file),
            template_format=args.format
        )
        print(f"\n✓ Template created: {result['data']['id']}")

    elif args.command == 'upload':
        if not args.template_id or not args.file:
            print("❌ --template-id and --file are required")
            return

        manager.upload_template_file(args.template_id, args.file)


if __name__ == '__main__':
    main()
