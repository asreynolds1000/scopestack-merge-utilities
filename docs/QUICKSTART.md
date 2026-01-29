# Quick Start Guide

## Installation

No installation required! Just Python 3 with the `requests` library:

```bash
pip3 install requests
```

## Your First Conversion

### 1. Test with the sample template

```bash
python3 scopestack_converter.py analyze "sample old merge template.docx"
```

This shows you what fields exist in the old template.

### 2. Convert it

```bash
python3 scopestack_converter.py convert "sample old merge template.docx" -o "my_converted_template.docx"
```

Done! You now have a converted template.

### 3. Upload and test in ScopeStack

1. Go to ScopeStack web app
2. Upload `my_converted_template.docx`
3. Generate a document from a test project
4. Verify all fields render correctly

## Authentication Setup (for validation)

If you want to validate templates against live project data:

### Option 1: Using your credentials (recommended)

```bash
export SCOPESTACK_EMAIL="your.email@company.com"
export SCOPESTACK_PASSWORD="your_password"
```

### Option 2: Using a bearer token

1. Log into ScopeStack web app
2. Open browser dev tools (F12)
3. Go to Network tab
4. Look for API requests to `api.scopestack.io`
5. Copy the `Authorization: Bearer ...` token value

```bash
export SCOPESTACK_TOKEN="your_token_here"
```

## Validate a Template

Once authenticated:

```bash
python3 scopestack_converter.py validate "sample old merge template.docx" --project {project_id}
```

Replace `{project_id}` with your actual project ID.

## Interactive Mode

For a guided experience:

```bash
python3 scopestack_converter.py
```

## Common Tasks

### Convert a new template from a client

```bash
# 1. Analyze what's in it
python3 scopestack_converter.py analyze "client_template.docx"

# 2. Convert it
python3 scopestack_converter.py convert "client_template.docx" -o "client_template_converted.docx"

# 3. Validate against a project (optional)
python3 scopestack_converter.py validate "client_template_converted.docx" --project YOUR_PROJECT_ID
```

### Fetch merge data for reference

```bash
# Get merge data for project {project_id}
python3 merge_data_fetcher.py {project_id} 2 merge_data.json

# View available fields
cat merge_data.json | grep '"' | head -50
```

### See what fields are available for a project

```bash
python3 merge_data_fetcher.py YOUR_PROJECT_ID 2 project_fields.json
less project_fields.json
```

## Tips

1. **Always validate after conversion** - Use a test project to check all fields work
2. **Check warnings** - The converter will warn about unmapped fields
3. **Start with examples** - Look at `Example Tag template.docx` to see proper formatting
4. **Test iteratively** - Convert, upload, test, fix, repeat

## Troubleshooting

### "No mapping found for field: X"

The field isn't in the conversion table. You can:
- Add it to `template_converter.py` (see README)
- Manually fix it in the output .docx

### Authentication fails

Double-check your credentials:
```bash
echo $SCOPESTACK_EMAIL
echo $SCOPESTACK_PASSWORD
```

### Fields not rendering

- Check field names match merge data exactly (case-sensitive)
- Verify loops are closed: `{#field}` needs `{/field}`
- Look for typos

## Next Steps

- Read the full [README.md](README.md) for detailed documentation
- Review conversion patterns in [README.md](README.md#common-conversion-patterns)
- Check [merge data URL patterns](README.md#merge-data-fetcher.py) for API access
