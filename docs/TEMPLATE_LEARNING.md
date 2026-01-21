# Template Learning Workflow

## Overview

This document describes an advanced technique for **learning** field mappings by comparing generated documents with merge data. Instead of manually mapping fields, we can observe how ScopeStack actually uses the fields when generating documents.

## The Concept

### Traditional Approach (Manual)
1. Look at old template fields
2. Look at v2 merge data structure
3. Manually map each field
4. Hope the mapping is correct

### Learning Approach (Automated)
1. Generate a document with v1 template
2. Download the generated document
3. Compare document content with v1 merge data
4. Find the same patterns in v2 merge data
5. Automatically build v2 mappings

## Why This Works

When ScopeStack generates a document:
- It takes merge data (v1 or v2)
- It populates template fields with actual values
- The **generated output** shows us exactly what data was used

By comparing:
- **What we asked for** (template fields)
- **What we got** (generated content)
- **Where it came from** (merge data)

We can **reverse engineer** the correct field mappings!

## The Workflow

### Step 1: Get Document Template

```python
from merge_data_fetcher import MergeDataFetcher
from auth_manager import AuthManager

# Authenticate
auth = AuthManager()
token = auth.get_access_token()

# Create fetcher
fetcher = MergeDataFetcher()
fetcher.authenticate(token=token)

# Get template by name
template = fetcher.get_document_template("PS+MS Template")
template_id = template['id']
```

### Step 2: Generate Document

```python
# Generate document for a project
document = fetcher.generate_project_document(
    project_id="103063",
    template_id=template_id,
    document_type='sow',
    generate_pdf=False,  # We want Word format to analyze
    force_regeneration=True,
    wait_for_completion=True
)

# Get download URL
document_url = document['attributes']['document-url']
print(f"Download from: {document_url}")
```

### Step 3: Fetch Both Merge Data Versions

```python
# Fetch v1 merge data
v1_data = fetcher.fetch_v1_merge_data("103063")

# Fetch v2 merge data
v2_data = fetcher.fetch_v2_merge_data("103063")

# Save for analysis
import json
with open('v1_merge.json', 'w') as f:
    json.dump(v1_data, f, indent=2)
with open('v2_merge.json', 'w') as f:
    json.dump(v2_data, f, indent=2)
```

### Step 4: Analyze the Generated Document

Download the generated document and open it in Word. You'll see:
- Client name: "Acme Corp"
- Project name: "Website Redesign"
- Phases listed with descriptions
- Resources with rates
- Etc.

### Step 5: Find Patterns

**In the document**, you see:
```
Client Name: Acme Corp
```

**In v1 merge data**, you find:
```json
{
  "client_name": "Acme Corp"
}
```

**In v2 merge data**, you find:
```json
{
  "project": {
    "client_name": "Acme Corp"
  }
}
```

**Mapping discovered**: `=client_name` → `{project.client_name}`

### Step 6: Build Mappings Automatically

With enough examples, you can:
1. Extract all values from generated document
2. Search for those values in both merge data versions
3. Map the field paths automatically
4. Generate conversion rules

## Automated Script

Use the provided workflow script:

```bash
python3 template_learning_workflow.py
```

This script will:
1. Prompt for project ID and template name
2. Generate a document
3. Fetch both v1 and v2 merge data
4. Save everything to JSON files
5. Show a quick comparison

### Output Files

- `template_{id}.json` - Template definition
- `generated_document_{project}.json` - Document generation info
- `v1_merge_data_{project}.json` - v1 merge data
- `v2_merge_data_{project}.json` - v2 merge data

## Analysis Examples

### Example 1: Simple Field Mapping

**v1 template**: `=project_name`
**Generated output**: "Website Redesign"
**v1 merge data path**: `project_name`
**v2 merge data path**: `project.project_name`
**Conversion rule**: `=project_name` → `{project.project_name}`

### Example 2: Loop Mapping

**v1 template**:
```
locations:each(location)
  =location.name
  =location.address
locations:endEach
```

**Generated output**:
```
New York Office
123 Main St

London Office
456 High St
```

**v1 merge data**:
```json
{
  "locations": [
    {"name": "New York Office", "address": "123 Main St"},
    {"name": "London Office", "address": "456 High St"}
  ]
}
```

**v2 merge data**:
```json
{
  "project": {
    "locations": [
      {"name": "New York Office", "address": "123 Main St"},
      {"name": "London Office", "address": "456 High St"}
    ]
  }
}
```

**Conversion rules**:
- `locations:each(location)` → `{#project.locations}`
- `=location.name` → `{name}`
- `locations:endEach` → `{/project.locations}`

### Example 3: Conditional Mapping

**v1 template**:
```
executive_summary:if(any?)
  =executive_summary
executive_summary:endIf
```

**Generated output**: Shows executive summary if present, hidden if not
**v2 mapping**: `{#project.formatted_executive_summary}...{/}`

## Advanced: Automated Pattern Detection

Future enhancement - build a tool that:

```python
def learn_field_mappings(template, generated_doc, v1_data, v2_data):
    """
    Automatically learn field mappings by comparing:
    - Template fields (what we asked for)
    - Generated document (what we got)
    - v1 merge data (where it came from)
    - v2 merge data (where we need to map to)

    Returns: Dictionary of conversion rules
    """
    mappings = {}

    # 1. Extract all text values from generated document
    doc_values = extract_all_values(generated_doc)

    # 2. For each value, find it in v1 data
    for value in doc_values:
        v1_path = find_value_path(v1_data, value)
        v2_path = find_value_path(v2_data, value)

        if v1_path and v2_path:
            # Build conversion rule
            old_field = template_field_for_path(template, v1_path)
            new_field = tag_field_for_path(v2_path)
            mappings[old_field] = new_field

    return mappings
```

## API Methods Used

All methods are in `merge_data_fetcher.py`:

### `get_document_template(template_name)`
Find a template by exact name (case-sensitive).

### `generate_project_document(project_id, template_id, ...)`
Generate a document and wait for completion.

### `fetch_v1_merge_data(project_id)`
Fetch v1 merge data via API.

### `fetch_v2_merge_data(project_id)`
Fetch v2 merge data via API.

## Benefits

✅ **Accurate** - Learns from actual document generation
✅ **Complete** - Captures all fields used in practice
✅ **Automated** - Can process many templates
✅ **Verified** - Based on real output, not assumptions

## Use Cases

### 1. Template Migration
- Generate documents with old templates
- Learn all field mappings
- Build new v2 templates automatically

### 2. Template Validation
- Generate with old template
- Generate with new template
- Compare outputs to verify correctness

### 3. Documentation
- Generate examples with known data
- Document what each field does
- Build field reference guide

### 4. Reverse Engineering
- Have generated document but no template?
- Compare with merge data
- Reconstruct template structure

## Workflow Script Usage

```bash
# Authenticate first
python3 auth_manager.py login

# Run the learning workflow
python3 template_learning_workflow.py
```

**Interactive prompts**:
1. Enter Project ID: `103063`
2. Enter Template Name: `PS+MS Template`

**What happens**:
1. Finds the template
2. Generates document (waits ~1-2 minutes)
3. Fetches v1 merge data
4. Fetches v2 merge data
5. Saves all data to JSON files
6. Shows comparison summary

## Next Steps

With the data collected, you can:

1. **Manual Analysis**: Open the JSON files and document in parallel
2. **Build Mappings**: Create conversion rules based on patterns
3. **Validate**: Use the mappings to convert templates
4. **Iterate**: Test with more projects to refine mappings

## Future Enhancements

Potential automation:

- [ ] Automatic document download via API
- [ ] Text extraction from .docx files
- [ ] Value matching between document and merge data
- [ ] Automatic mapping rule generation
- [ ] Confidence scoring for mappings
- [ ] Multiple project comparison for validation

## Summary

The template learning workflow provides a powerful way to:

🎯 **Learn** field mappings from actual document generation
🎯 **Compare** v1 and v2 merge data structures
🎯 **Automate** template conversion with confidence
🎯 **Validate** conversions against real output

By observing how ScopeStack actually uses fields in practice, we can build accurate, verified conversion mappings!
