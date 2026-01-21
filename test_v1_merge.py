#!/usr/bin/env python3
"""
Test script to fetch v1 merge data from ScopeStack API
"""

from merge_data_fetcher import MergeDataFetcher
from auth_manager import AuthManager
import json

def test_v1_merge_data():
    """Test fetching v1 merge data"""

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

    # Test with a project ID
    project_id = input("Enter project ID (e.g., 103063): ").strip()

    print("\n" + "="*80)
    print("Fetching v1 merge data...")
    print("="*80 + "\n")

    # Fetch v1 merge data
    v1_data = fetcher.fetch_v1_merge_data(project_id)

    if v1_data:
        print("\n✓ Successfully fetched v1 merge data!")
        print(f"\nData structure keys: {list(v1_data.keys())}")

        # Save to file
        output_file = f"v1_merge_data_{project_id}.json"
        with open(output_file, 'w') as f:
            json.dump(v1_data, f, indent=2)

        print(f"\n✓ Saved to: {output_file}")

        # Print a preview
        print("\n" + "="*80)
        print("Preview of v1 merge data:")
        print("="*80)
        print(json.dumps(v1_data, indent=2)[:2000] + "\n... (truncated)")

        return v1_data
    else:
        print("\n❌ Failed to fetch v1 merge data")
        return None

if __name__ == '__main__':
    test_v1_merge_data()
