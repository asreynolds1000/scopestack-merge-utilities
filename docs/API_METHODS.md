# ScopeStack API Methods

This document describes the programmatic API methods available in the ScopeStack Template Converter for fetching data from the ScopeStack API.

## Overview

The `MergeDataFetcher` class now includes methods to:
- Get account information
- Fetch clients by ID, name, or domain
- Fetch v1 merge data programmatically
- Fetch v2 merge data (existing functionality)

All methods use OAuth2 authentication via the `AuthManager`.

## Authentication

All API methods require authentication. Use the `AuthManager` to login first:

```python
from auth_manager import AuthManager

auth = AuthManager()
auth.login(email="your@email.com", password="your_password")

# Get access token
token = auth.get_access_token()
```

Or login via CLI:

```bash
python3 auth_manager.py login
```

## API Methods

### 1. Get Account Information

Retrieves your account slug and account ID.

**Method**: `get_account_info()`

**Example**:
```python
from merge_data_fetcher import MergeDataFetcher

fetcher = MergeDataFetcher()
fetcher.authenticate(token=token)

account_info = fetcher.get_account_info()
print(f"Account Slug: {account_info['account_slug']}")
print(f"Account ID: {account_info['account_id']}")
```

**Returns**:
```json
{
  "account_slug": "your-account-slug",
  "account_id": 12345
}
```

**API Endpoint**: `https://api.scopestack.io/v1/me`

---

### 2. Get Client

Fetch a client by ID, name, or domain.

**Method**: `get_client(client_id=None, client_name=None, domain=None)`

**Parameters**:
- `client_id` (str, optional): The unique identifier of the client (takes precedence)
- `client_name` (str, optional): The name of the client to find
- `domain` (str, optional): The domain associated with the client

**Example - By ID**:
```python
client = fetcher.get_client(client_id="12345")
```

**Example - By Name**:
```python
client = fetcher.get_client(client_name="Acme Corporation")
```

**Example - By Domain**:
```python
client = fetcher.get_client(domain="acme.com")
```

**Returns**:
```json
{
  "id": "12345",
  "type": "clients",
  "attributes": {
    "name": "Acme Corporation",
    "domain": "acme.com",
    "active": true,
    "msa_date": "2024-01-01",
    "user-defined-fields": [...]
  },
  "relationships": {...},
  "links": {...}
}
```

**API Endpoints**:
- By ID: `https://api.scopestack.io/{account_slug}/v1/clients/{client_id}`
- By filters: `https://api.scopestack.io/{account_slug}/v1/clients?filter[name]=...`

---

### 3. Fetch v1 Merge Data

Fetch v1 merge data for a project using the API endpoint.

**Method**: `fetch_v1_merge_data(project_id)`

**Parameters**:
- `project_id` (str): The project ID

**Example**:
```python
v1_data = fetcher.fetch_v1_merge_data("{project_id}")

# Save to file
import json
with open('v1_merge_data.json', 'w') as f:
    json.dump(v1_data, f, indent=2)
```

**Returns**: Full v1 merge data structure (JSON)

**API Endpoint**: `https://api.scopestack.io/{account_slug}/v1/projects/{project_id}/merge-data`

---

### 4. Fetch Merge Data (v1 or v2)

Unified method to fetch merge data for either version.

**Method**: `fetch_merge_data(project_id, version=2)`

**Parameters**:
- `project_id` (str): The project ID
- `version` (int): 1 or 2 (default: 2)

**Example - v1**:
```python
v1_data = fetcher.fetch_merge_data("{project_id}", version=1)
```

**Example - v2**:
```python
v2_data = fetcher.fetch_merge_data("{project_id}", version=2)
```

**API Endpoints**:
- v1: `https://api.scopestack.io/{account_slug}/v1/projects/{project_id}/merge-data`
- v2: `https://app.scopestack.io/projects/{project_id}/merge_data_visualization?version=2`

---

## Complete Example

```python
#!/usr/bin/env python3
from merge_data_fetcher import MergeDataFetcher
from auth_manager import AuthManager
import json

# Authenticate
auth = AuthManager()
if not auth.is_authenticated():
    auth.login()

token = auth.get_access_token()

# Create fetcher
fetcher = MergeDataFetcher()
fetcher.authenticate(token=token)

# Get account info
account_info = fetcher.get_account_info()
print(f"Account: {account_info['account_slug']}")

# Get a client
client = fetcher.get_client(client_name="Acme Corporation")
if client:
    print(f"Client: {client['attributes']['name']}")

# Fetch v1 merge data
project_id = "{project_id}"
v1_data = fetcher.fetch_v1_merge_data(project_id)

if v1_data:
    # Save to file
    with open(f'v1_merge_{project_id}.json', 'w') as f:
        json.dump(v1_data, f, indent=2)
    print(f"✓ Saved v1 merge data")

# Compare with v2
v2_data = fetcher.fetch_merge_data(project_id, version=2)

if v2_data:
    with open(f'v2_merge_{project_id}.json', 'w') as f:
        json.dump(v2_data, f, indent=2)
    print(f"✓ Saved v2 merge data")
```

## Test Scripts

### Interactive Test Script

Test all API methods interactively:

```bash
python3 test_api_methods.py
```

This script allows you to:
1. View account information
2. Search for clients by ID/name/domain
3. Fetch v1 merge data for a project
4. Compare v1 vs v2 merge data

### Simple v1 Test

Quick test of v1 merge data fetching:

```bash
python3 test_v1_merge.py
```

## Error Handling

All methods include error handling and will return `None` on failure. Check for `None` before using results:

```python
client = fetcher.get_client(client_id="12345")
if client:
    # Success - use client data
    print(client['attributes']['name'])
else:
    # Failed - client not found or error occurred
    print("Client not found")
```

Error messages are printed to stdout for debugging.

## API Response Formats

### Account Info Response

From `/v1/me`:

```json
{
  "data": {
    "id": "12345",
    "type": "users",
    "attributes": {
      "account-slug": "your-account",
      "account-id": 12345,
      "email": "your@email.com",
      ...
    }
  }
}
```

### Client Response

From `/{account_slug}/v1/clients/{id}`:

```json
{
  "data": {
    "id": "123",
    "type": "clients",
    "attributes": {
      "name": "Client Name",
      "domain": "example.com",
      "active": true,
      "msa_date": "2024-01-01",
      "user-defined-fields": [
        {
          "name": "field_name",
          "label": "Field Label",
          "variable_type": "text",
          "value": "field value",
          ...
        }
      ]
    },
    "relationships": {
      "account": {...},
      "rate_table": {...},
      "contacts": {...}
    },
    "links": {
      "self": "https://api.scopestack.io/..."
    }
  }
}
```

### v1 Merge Data Response

From `/{account_slug}/v1/projects/{project_id}/merge-data`:

Structure varies based on project configuration. Typically includes:
- Project details
- Client information
- Contacts
- Phases
- Services
- Resources
- Pricing
- Custom fields

### v2 Merge Data Response

From `/projects/{project_id}/merge_data_visualization?version=2`:

HTML page with embedded data structure, or JSON response depending on endpoint configuration.

## Authentication Headers

All API requests use these headers:

```python
headers = {
    'Authorization': f'Bearer {access_token}',
    'Accept': 'application/vnd.api+json'
}
```

## Rate Limiting

Be mindful of API rate limits. The methods include basic error handling for common HTTP status codes:

- `400`: Invalid parameters
- `401`: Authentication failed
- `403`: Forbidden
- `404`: Not found
- `429`: Rate limit exceeded

## Integration with Workato Connector

These methods are based on the Workato connector patterns and use the same API endpoints. This ensures compatibility and consistency across different integration methods.

## Future Enhancements

Potential additions:
- List all clients with pagination
- Get projects by client
- Get contacts for a client
- Update client information
- Create new projects
- Get project details
- List all projects

## Summary

The API methods provide programmatic access to ScopeStack data:

✅ **Account Info** - Get your account slug and ID
✅ **Get Client** - Find clients by ID, name, or domain
✅ **v1 Merge Data** - Fetch v1 merge data via API endpoint
✅ **v2 Merge Data** - Fetch v2 merge data (existing)
✅ **OAuth2 Auth** - Secure authentication with token refresh

All methods are production-ready and follow ScopeStack API best practices!
