#!/usr/bin/env python3
"""
Template Learning Workflow
===========================

This script demonstrates the complete workflow for learning field mappings:

1. Get a document template from ScopeStack
2. Generate a document for a project using that template
3. Fetch both v1 and v2 merge data
4. Compare the generated output with merge data to learn patterns
5. Build v2 tag template mappings

This is the foundation for automating template conversion by observing
actual document generation patterns.
"""

from merge_data_fetcher import MergeDataFetcher
from auth_manager import AuthManager
import json
from pathlib import Path

def save_json(data, filename):
    """Save data as pretty JSON"""
    with open(filename, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"  ✓ Saved: {filename}")

def main():
    print("="*80)
    print("ScopeStack Template Learning Workflow")
    print("="*80)
    print()
    print("This workflow will:")
    print("  1. Get a document template")
    print("  2. Generate a document from that template")
    print("  3. Fetch v1 and v2 merge data")
    print("  4. Save all data for analysis")
    print()
    print("="*80)
    print()

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

    # Create fetcher
    fetcher = MergeDataFetcher()
    fetcher.authenticate(token=token)

    # Get account info
    print("Step 1: Getting account information...")
    account_info = fetcher.get_account_info()
    if not account_info:
        print("❌ Could not get account info")
        return

    print(f"✓ Account: {account_info['account_slug']}")
    print()

    # Get project ID
    project_id = input("Enter Project ID: ").strip()
    if not project_id:
        print("❌ Project ID required")
        return

    # Get template name
    template_name = input("Enter Document Template Name (or press Enter to skip template generation): ").strip()

    template_id = None
    if template_name:
        # Step 2: Get document template
        print()
        print("Step 2: Finding document template...")
        template = fetcher.get_document_template(template_name)

        if not template:
            print("❌ Template not found")
            print("   Continuing without document generation...")
        else:
            template_id = template['id']
            template_attrs = template['attributes']
            print(f"✓ Found template:")
            print(f"  ID: {template_id}")
            print(f"  Name: {template_attrs['name']}")
            print(f"  Format: {template_attrs.get('template-format', 'unknown')}")
            print(f"  Active: {template_attrs.get('active', False)}")

            # Save template data
            save_json(template, f"template_{template_id}.json")
            print()

            # Step 3: Generate document
            print("Step 3: Generating document...")
            print("   (This may take a minute...)")

            document = fetcher.generate_project_document(
                project_id=project_id,
                template_id=template_id,
                document_type='sow',
                generate_pdf=False,  # Get Word format to analyze
                force_regeneration=True,
                wait_for_completion=True
            )

            if document:
                doc_attrs = document['attributes']
                print(f"✓ Document generated:")
                print(f"  Status: {doc_attrs['status']}")
                print(f"  URL: {doc_attrs.get('document-url', 'N/A')}")

                # Save document data
                save_json(document, f"generated_document_{project_id}.json")
                print()
            else:
                print("❌ Document generation failed")
                print("   Continuing with merge data fetch...")
                print()

    # Step 4: Fetch v1 merge data
    print("Step 4: Fetching v1 merge data...")
    v1_data = fetcher.fetch_v1_merge_data(project_id)

    if v1_data:
        save_json(v1_data, f"v1_merge_data_{project_id}.json")
        print(f"  Keys: {list(v1_data.keys())[:10]}")
        print()
    else:
        print("❌ Failed to fetch v1 merge data")
        print()

    # Step 5: Fetch v2 merge data
    print("Step 5: Fetching v2 merge data...")
    v2_data = fetcher.fetch_v2_merge_data(project_id)

    if v2_data:
        save_json(v2_data, f"v2_merge_data_{project_id}.json")
        print(f"  Keys: {list(v2_data.keys())[:10]}")
        print()
    else:
        print("❌ Failed to fetch v2 merge data")
        print()

    # Step 6: Summary
    print("="*80)
    print("Workflow Complete!")
    print("="*80)
    print()
    print("Files created:")
    if template_id:
        print(f"  • template_{template_id}.json - Template definition")
        print(f"  • generated_document_{project_id}.json - Generated document info")
    print(f"  • v1_merge_data_{project_id}.json - v1 merge data")
    print(f"  • v2_merge_data_{project_id}.json - v2 merge data")
    print()
    print("Next Steps:")
    print("  1. Download the generated document from the URL")
    print("  2. Open it in Word to see what fields were populated")
    print("  3. Compare field values with v1_merge_data")
    print("  4. Find corresponding fields in v2_merge_data")
    print("  5. Build mapping rules for template conversion")
    print()
    print("This data can be used to:")
    print("  • Learn which v1 fields map to which v2 fields")
    print("  • Understand field structure differences")
    print("  • Automatically generate conversion mappings")
    print("  • Build a v2 tag template from observed patterns")
    print()

    # Bonus: Quick comparison
    if v1_data and v2_data:
        print("="*80)
        print("Quick Comparison:")
        print("="*80)

        def count_fields(data, prefix=""):
            """Recursively count fields in nested structure"""
            count = 0
            if isinstance(data, dict):
                for key, value in data.items():
                    count += 1
                    if isinstance(value, (dict, list)):
                        count += count_fields(value, f"{prefix}{key}.")
            elif isinstance(data, list):
                for item in data:
                    if isinstance(item, (dict, list)):
                        count += count_fields(item, prefix)
            return count

        v1_field_count = count_fields(v1_data)
        v2_field_count = count_fields(v2_data)

        print(f"v1 total fields: ~{v1_field_count}")
        print(f"v2 total fields: ~{v2_field_count}")
        print()

        # Show top-level structure
        print("v1 top-level structure:")
        if isinstance(v1_data, dict):
            for key in list(v1_data.keys())[:15]:
                value = v1_data[key]
                type_str = type(value).__name__
                if isinstance(value, (list, dict)):
                    length = len(value)
                    print(f"  • {key}: {type_str} ({length} items)")
                else:
                    print(f"  • {key}: {type_str}")

        print()
        print("v2 top-level structure:")
        if isinstance(v2_data, dict):
            for key in list(v2_data.keys())[:15]:
                value = v2_data[key]
                type_str = type(value).__name__
                if isinstance(value, (list, dict)):
                    length = len(value)
                    print(f"  • {key}: {type_str} ({length} items)")
                else:
                    print(f"  • {key}: {type_str}")

if __name__ == '__main__':
    main()
