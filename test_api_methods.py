#!/usr/bin/env python3
"""
Test script for ScopeStack API methods
Demonstrates fetching v1 merge data, clients, and account info
"""

from merge_data_fetcher import MergeDataFetcher
from auth_manager import AuthManager
import json

def main():
    """Test various API methods"""

    print("="*80)
    print("ScopeStack API Methods Test")
    print("="*80 + "\n")

    # Use auth manager to get token
    auth = AuthManager()

    if not auth.is_authenticated():
        print("❌ Not authenticated. Please login first:")
        print("   python3 auth_manager.py login")
        return

    token = auth.get_access_token()
    if not token:
        print("❌ Could not get access token")
        return

    # Create fetcher and authenticate
    fetcher = MergeDataFetcher()
    fetcher.authenticate(token=token)

    # Test 1: Get account info
    print("\n" + "="*80)
    print("Test 1: Get Account Info")
    print("="*80)
    account_info = fetcher.get_account_info()
    if account_info:
        print(f"✓ Account Slug: {account_info['account_slug']}")
        print(f"✓ Account ID: {account_info['account_id']}")
    else:
        print("❌ Failed to get account info")
        return

    # Test 2: Get a client
    print("\n" + "="*80)
    print("Test 2: Get Client")
    print("="*80)
    choice = input("\nHow would you like to search for a client?\n"
                  "  1. By Client ID\n"
                  "  2. By Client Name\n"
                  "  3. By Domain\n"
                  "  4. Skip\n"
                  "Enter choice (1-4): ").strip()

    if choice == '1':
        client_id = input("Enter Client ID: ").strip()
        client = fetcher.get_client(client_id=client_id)
    elif choice == '2':
        client_name = input("Enter Client Name: ").strip()
        client = fetcher.get_client(client_name=client_name)
    elif choice == '3':
        domain = input("Enter Domain: ").strip()
        client = fetcher.get_client(domain=domain)
    else:
        client = None

    if client:
        print(f"\n✓ Found client:")
        print(f"  ID: {client.get('id')}")
        print(f"  Type: {client.get('type')}")
        attributes = client.get('attributes', {})
        print(f"  Name: {attributes.get('name')}")
        print(f"  Domain: {attributes.get('domain')}")
        print(f"  Active: {attributes.get('active')}")

        # Save client data
        with open('client_data.json', 'w') as f:
            json.dump(client, f, indent=2)
        print(f"\n✓ Saved full client data to: client_data.json")

    # Test 3: Get v1 merge data
    print("\n" + "="*80)
    print("Test 3: Get v1 Merge Data")
    print("="*80)
    choice = input("\nFetch v1 merge data for a project? (y/n): ").strip().lower()

    if choice == 'y':
        project_id = input("Enter Project ID: ").strip()

        print(f"\nFetching v1 merge data for project {project_id}...")
        v1_data = fetcher.fetch_v1_merge_data(project_id)

        if v1_data:
            print(f"\n✓ Successfully fetched v1 merge data!")

            # Save to file
            output_file = f"v1_merge_data_{project_id}.json"
            with open(output_file, 'w') as f:
                json.dump(v1_data, f, indent=2)

            print(f"✓ Saved to: {output_file}")

            # Print structure info
            print(f"\nData structure:")
            print(f"  Top-level keys: {list(v1_data.keys())}")

            if isinstance(v1_data, dict):
                for key in v1_data.keys():
                    value = v1_data[key]
                    if isinstance(value, dict):
                        print(f"  {key}: dict with {len(value)} keys")
                    elif isinstance(value, list):
                        print(f"  {key}: list with {len(value)} items")
                    else:
                        print(f"  {key}: {type(value).__name__}")

            # Show a preview
            print("\nPreview (first 1000 chars):")
            print("-" * 80)
            print(json.dumps(v1_data, indent=2)[:1000])
            print("... (truncated)")
        else:
            print("❌ Failed to fetch v1 merge data")

    # Test 4: Compare v1 vs v2 merge data
    print("\n" + "="*80)
    print("Test 4: Compare v1 vs v2 Merge Data")
    print("="*80)
    choice = input("\nCompare v1 and v2 merge data for a project? (y/n): ").strip().lower()

    if choice == 'y':
        project_id = input("Enter Project ID: ").strip()

        print(f"\nFetching both v1 and v2 merge data for project {project_id}...")

        v1_data = fetcher.fetch_merge_data(project_id, version=1)
        v2_data = fetcher.fetch_merge_data(project_id, version=2)

        if v1_data and v2_data:
            print("\n✓ Successfully fetched both versions!")

            # Save both
            with open(f"v1_merge_{project_id}.json", 'w') as f:
                json.dump(v1_data, f, indent=2)
            with open(f"v2_merge_{project_id}.json", 'w') as f:
                json.dump(v2_data, f, indent=2)

            print(f"✓ Saved v1 to: v1_merge_{project_id}.json")
            print(f"✓ Saved v2 to: v2_merge_{project_id}.json")

            print("\nComparison:")
            print(f"  v1 top-level keys: {list(v1_data.keys()) if isinstance(v1_data, dict) else 'N/A'}")
            print(f"  v2 top-level keys: {list(v2_data.keys()) if isinstance(v2_data, dict) else 'N/A'}")
        else:
            print("❌ Failed to fetch merge data")

    print("\n" + "="*80)
    print("Tests Complete!")
    print("="*80)

if __name__ == '__main__':
    main()
