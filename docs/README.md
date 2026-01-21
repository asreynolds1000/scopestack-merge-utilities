# ScopeStack Document Template Converter

Automates the conversion of document templates from Microsoft Word Mail Merge format to ScopeStack's DocX Templater tag format.

## Overview

This tool helps you convert legacy Word templates with Mail Merge fields into ScopeStack's v2 merge data format. It handles:

- Simple field conversions (e.g., `=client_name` → `{project.client_name}`)
- Loop structures (e.g., `locations:each(location)` → `{#locations}...{/locations}`)
- Conditional logic (e.g., `executive_summary:if(any?)` → `{#project.formatted_executive_summary}`)
- Validation against live project merge data
- Interactive conversion workflow

## Quick Start

### 1. Interactive Mode (Recommended for first-time use)

```bash
python scopestack_converter.py
```

This will guide you through:
1. Analyzing your template
2. Optionally validating against a project
3. Converting to the new format

### 2. Command-Line Mode

#### Analyze a template
```bash
python scopestack_converter.py analyze "sample old merge template.docx"
```

#### Convert a template
```bash
python scopestack_converter.py convert "sample old merge template.docx" -o "new_template.docx"
```

#### Validate and convert
```bash
python scopestack_converter.py convert "sample old merge template.docx" --project 101735
```

## Format Conversion Reference

### Simple Fields

| Old Format (Mail Merge) | New Format (DocX Templater) |
|-------------------------|----------------------------|
| `=client_name` | `{project.client_name}` |
| `=project_name` | `{project.project_name}` |
| `=printed_on` | `{project.printed_on}` |
| `=sales_executive.name` | `{project.sales_executive.name}` |
| `=location.name` | `{name}` (within location loop) |

### Loop Structures

| Old Format | New Format |
|-----------|-----------|
| `locations:each(location)` ... `locations:endEach` | `{#locations}` ... `{/locations}` |
| `executive_summary:each(sentence)` ... `executive_summary:endEach` | `{#project.formatted_executive_summary}` ... `{/project.formatted_executive_summary}` |
| `resource_pricing:each(pricing)` ... `resource_pricing:endEach` | `{#project_pricing.resources}` ... `{/project_pricing.resources}` |

### Conditionals

| Old Format | New Format |
|-----------|-----------|
| `locations:if(any?)` ... `locations:endIf` | `{#locations}` ... `{/locations}` |
| `executive_summary:if(any?)` ... `executive_summary:endIf` | `{#project.formatted_executive_summary}` ... `{/project.formatted_executive_summary}` |
| `payment_terms.include_expenses.present?:if` | `{#include_expenses}` ... `{/include_expenses}` |
| `payment_terms.include_hardware:if(blank?)` | `{^include_hardware}` ... `{/include_hardware}` |

### Special Cases

- **Sentence loops**: `=sentence` → `{.}` (represents current item in iteration)
- **Else clauses**: `executive_summary:else` → `{:else}`
- **Filters**: Some templates use `{~~formatted_field}` for HTML rendering

## Module Documentation

### `template_converter.py`

Core conversion engine that:
- Extracts Mail Merge fields from .docx files
- Applies conversion rules from FIELD_MAPPINGS
- Handles nested loops and conditionals
- Generates converted .docx output

**Usage:**
```bash
python template_converter.py input.docx [output.docx]
```

### `merge_data_fetcher.py`

Fetches merge data from ScopeStack API to:
- Validate template fields exist in merge data
- Discover available fields for a project
- Generate field mapping suggestions

**Usage:**
```bash
# Set authentication token
export SCOPESTACK_TOKEN='your_token_here'

# Fetch merge data for a project
python merge_data_fetcher.py 101735 2 output.json
```

**Merge Data URL Pattern:**
```
https://app.scopestack.io/projects/{project_id}/merge_data_visualization?version={version}
```

### `scopestack_converter.py`

Main CLI that combines all functionality:
- Interactive guided workflow
- Template analysis
- Validation against projects
- One-command conversion

## Authentication

To validate templates against live projects, you need to authenticate:

```bash
# Set your ScopeStack authentication token
export SCOPESTACK_TOKEN='your_token_here'

# Or add to your shell profile
echo 'export SCOPESTACK_TOKEN="your_token_here"' >> ~/.zshrc
source ~/.zshrc
```

To get your token:
1. Log into ScopeStack web app
2. Open browser dev tools (F12)
3. Look for Authorization header in network requests
4. Copy the Bearer token value

## Workflow

### Converting an Existing Template

1. **Analyze the source template**
   ```bash
   python scopestack_converter.py analyze "old_template.docx"
   ```
   This shows you what fields exist and their types.

2. **Validate against a project** (optional but recommended)
   ```bash
   python scopestack_converter.py validate "old_template.docx" --project 101735
   ```
   This checks if all fields exist in the project's merge data.

3. **Convert the template**
   ```bash
   python scopestack_converter.py convert "old_template.docx" -o "new_template.docx"
   ```

4. **Test the converted template**
   - Upload to ScopeStack
   - Generate a document from a test project
   - Verify all fields render correctly

### Creating a New Template from Scratch

1. **Fetch merge data for a project**
   ```bash
   python merge_data_fetcher.py 101735 2 merge_data.json
   ```

2. **Review available fields**
   Open `merge_data.json` to see all available fields and their structure.

3. **Create your Word document**
   Use the tag format directly: `{project.client_name}`, `{#locations}`, etc.

4. **Validate your template**
   ```bash
   python scopestack_converter.py validate "new_template.docx" --project 101735
   ```

## Common Conversion Patterns

### Project Information
```
Old: =project_name, =client_name, =account_name
New: {project.project_name}, {project.client_name}, {project.account_name}
```

### Contact Information
```
Old: =primary_contact.name, =primary_contact.email
New: {project.primary_contact.name}, {project.primary_contact.email}
```

### Locations Loop
```
Old:
  locations:each(location)
    =location.name
    =location.address
  locations:endEach

New:
  {#locations}
    {name}
    {address}
  {/locations}
```

### Formatted Content Blocks
```
Old:
  executive_summary:if(any?)
    executive_summary:each(sentence)
      =sentence
    executive_summary:endEach
  executive_summary:endIf

New:
  {#project.formatted_executive_summary}
    {.}
  {/project.formatted_executive_summary}
```

Note: In the new format, `formatted_*` fields already include iteration, so you don't need nested loops.

### Pricing Tables
```
Old:
  resource_pricing:each(pricing)
    =pricing.resource_name
    =pricing.hourly_rate
    =pricing.quantity
    =pricing.total
  resource_pricing:endEach

New:
  {#project_pricing.resources}
    {resource_name}
    {hourly_rate}
    {quantity}
    {total}
  {/project_pricing.resources}
```

## Troubleshooting

### "No mapping found for field"

The converter will show warnings for fields it doesn't recognize. You have two options:

1. **Add the mapping** to `template_converter.py` in the `FIELD_MAPPINGS` or `LOOP_CONVERSIONS` dictionaries
2. **Manually fix** in the output document (if it's a rare field)

### "Could not fetch merge data"

Check:
- Your `SCOPESTACK_TOKEN` is set correctly
- The project ID exists
- You have access to the project
- Your network can reach app.scopestack.io

### Fields not rendering in generated documents

After conversion:
- Check the field names match the merge data exactly (case-sensitive)
- Verify loops are properly closed (`{#field}` has matching `{/field}`)
- Look for typos in field paths (e.g., `project.cilent_name` vs `project.client_name`)

## Extending the Converter

### Adding New Field Mappings

Edit `template_converter.py` and add to `FIELD_MAPPINGS`:

```python
FIELD_MAPPINGS = {
    # ... existing mappings ...
    '=your_old_field': '{your.new.field}',
}
```

### Adding New Loop Conversions

Edit `template_converter.py` and add to `LOOP_CONVERSIONS`:

```python
LOOP_CONVERSIONS = {
    # ... existing conversions ...
    'old_loop:each(item)': ('{#new_loop}', '{/new_loop}', {}),
}
```

### Adding New Conditionals

Edit `template_converter.py` and add to `CONDITIONAL_CONVERSIONS`:

```python
CONDITIONAL_CONVERSIONS = {
    # ... existing conversions ...
    'field:if(condition?)': ('{#field}', '{/field}'),
}
```

## Files in This Project

- `scopestack_converter.py` - Main CLI tool
- `template_converter.py` - Core conversion engine
- `merge_data_fetcher.py` - Merge data API client
- `sample old merge template.docx` - Example old format template
- `Example Tag template.docx` - Example new format template
- `Example merge data v2.htm` - Saved merge data visualization
- `converted_output.docx` - Example converted output

## DocX Templater Syntax Reference

### Basic substitution
```
{field_name}
```

### Loops (iteration)
```
{#array_field}
  {item_property}
{/array_field}
```

### Current item in loop
```
{.}
```

### Conditionals (show if truthy)
```
{#field}
  Content shown if field is truthy
{/field}
```

### Inverted conditionals (show if falsy)
```
{^field}
  Content shown if field is falsy
{/field}
```

### Conditional with comparison
```
{#field=="value"}
  Content shown if field equals "value"
{/field}
```

### HTML rendering
```
{~~html_field}
```

Renders HTML content (used for formatted text blocks).

## License

Internal tool for ScopeStack template conversion.

## Support

For questions or issues:
1. Check the troubleshooting section above
2. Review example templates in this directory
3. Consult ScopeStack documentation for merge data structure
