# Complete Template Migration Workflow

## Overview

This system now supports a **complete end-to-end workflow** for migrating v1 Mail Merge templates to v2 DocX Templater format, including:

1. **Browse** templates from ScopeStack platform
2. **Download** v1 templates directly from the API
3. **Learn** field mappings from live project data
4. **Convert** templates automatically using learned mappings
5. **Upload** converted v2 templates back to the platform
6. **Test** the new templates on real projects

This creates a full feedback loop for validating converted templates in production!

## Architecture

### API Endpoints

#### Template Management
- `GET /api/templates/list` - List all document templates
- `POST /api/templates/<id>/download` - Download a template file
- `POST /api/templates/create-and-upload` - Create metadata and upload file
- `POST /api/templates/convert-and-upload` - **Complete workflow endpoint**

#### Learning & Conversion
- `POST /api/learn-mappings` - Learn from API project data
- `POST /api/upload-for-learning` - Learn from documents + API data
- `POST /api/convert` - Convert v1 template to v2

### Python Modules

#### `template_manager.py` (NEW)
Manages templates via ScopeStack API:
```python
class TemplateManager:
    def list_templates() -> Dict
    def get_template_details(template_id) -> Dict
    def download_template(template_id, output_path) -> str
    def create_template(...) -> Dict
    def upload_template_file(template_id, file_path) -> Dict
```

#### `document_analyzer.py`
Extracts fields and values from documents:
```python
class DocumentAnalyzer:
    def extract_v1_fields(docx_path) -> List[str]
    def extract_text_values(docx_path) -> Set
    def match_fields_to_values(...) -> List[Dict]
```

#### `learn_mappings.py`
Value-matching for mapping discovery:
```python
class MappingLearner:
    def learn_mappings(project_id) -> Dict
    def suggest_mappings(matches) -> List[Dict]
```

#### `mapping_database.py`
Persistent storage for learned mappings:
```python
class MappingDatabase:
    def add_mapping(v1_field, v2_field, ...)
    def import_mappings(mappings, project_id)
    def get_high_confidence_mappings(min_score)
```

## Complete Workflow

### Step 1: Load Templates from Platform

**UI**: Click "📋 Load Templates" button

**What happens**:
- Fetches all document templates from `https://api.scopestack.io/{account}/v1/document-templates`
- Filters for v1 templates only (`template-format: "v1"`)
- Displays in dropdown with template name and ID

**API Call**:
```http
GET /api/templates/list?active_only=false
Authorization: Bearer {token}
Accept: application/vnd.api+json
```

### Step 2: Select Template and Configure

**UI**:
- Select a v1 template from the dropdown
- View template details (ID, format, filename)
- Enter a project ID for learning mappings
- Enter a name for the new v2 template

### Step 3: Run Complete Workflow

**UI**: Click "🚀 Run Complete Workflow"

**What happens** (all automatic):

#### 3.1 Download v1 Template
```python
# Downloads template file from platform
manager.download_template(v1_template_id, local_path)
```

API call: `GET /v1/document-templates/{id}/download`

#### 3.2 Learn Mappings from Project
```python
# Fetches v1 and v2 merge data
v1_data = fetcher.fetch_v1_merge_data(project_id)
v2_data = fetcher.fetch_v2_merge_data(project_id)

# Learns mappings by value matching
learner = MappingLearner(fetcher)
results = learner.learn_mappings(project_id)

# Saves to persistent database
mapping_db.import_mappings(results['suggested_mappings'], project_id)
```

#### 3.3 Convert Template to v2
```python
# Converts using learned mappings + existing knowledge
converter = TemplateConverter(v1_template_path)
converter.extract_fields()
converter.convert_template(v2_output_path)
```

Conversions applied:
- Simple fields: `=project_name` → `{project.project_name}`
- Loops: `resources:each(resource)` → `{#resources}...{/resources}`
- Conditionals: `field:if` → `{#field}...{/field}`

#### 3.4 Upload v2 Template to Platform
```python
# Step 1: Create template metadata
create_result = manager.create_template(
    name=new_template_name,
    filename=v2_filename,
    template_format='v2',
    format_type='tag_template',
    active=False  # Starts inactive for testing
)

# Step 2: Upload the file
template_id = create_result['data']['id']
manager.upload_template_file(template_id, v2_file_path)
```

API calls:
```http
POST /v1/document-templates
Content-Type: application/vnd.api+json
{
  "data": {
    "type": "document-templates",
    "attributes": { ... }
  }
}

POST /v1/document-templates/{id}/upload
Content-Type: multipart/form-data
document_template[merge_template]: {file}
```

### Step 4: Test in ScopeStack

After workflow completes:

1. **Find Template**: Go to ScopeStack, navigate to Document Templates, find the new template by ID
2. **Review**: Check the template looks correct (download and review if needed)
3. **Activate**: If it looks good, mark the template as active
4. **Test**: Generate a document for a project
5. **Compare**: Compare the v2 output with the original v1 output
6. **Iterate**: If there are issues, fix mappings and re-run workflow

## UI Features

### Template Workflow Section

Located after "Learn Field Mappings" section in the web interface.

**Components**:
- Template browser (dropdown with v1 templates)
- Template details panel (shows ID, format, filename)
- Project ID input (for learning)
- New template name input
- Run workflow button
- Debug console (shows real-time progress)
- Results panel (shows IDs, mappings learned, next steps)

**Workflow Progress Display**:
```
🚀 Starting complete workflow...
1️⃣ Downloading v1 template 1822...
   ✓ Downloaded: ScopeStack_PS_Template__23_(2).docx
2️⃣ Learning mappings from project {project_id}...
   ✓ Learned 42 mappings
3️⃣ Converting template to v2 format...
   ✓ Converted to: ScopeStack_PS_Template__23_(2)_v2.docx
4️⃣ Uploading as new template: Professional Services Template V2...
   ✓ Uploaded as template ID: 6029
✅ Complete workflow finished successfully!
```

### Results Display

After successful completion:
```
✅ Workflow Complete!

Original v1 Template ID: 1822
New v2 Template ID: 6029
Template Name: Professional Services Template V2
Mappings Learned: 42

Next Steps:
• Go to ScopeStack and find template ID 6029
• Activate the template if it looks good
• Generate a document for a project to test it
• Compare with the original v1 output
```

## API Response Examples

### List Templates Response
```json
{
  "success": true,
  "templates": [
    {
      "id": "1822",
      "type": "document-templates",
      "attributes": {
        "name": "Professional Services Template V1",
        "template-format": "v1",
        "merge-template-filename": "PS_Template.docx",
        "active": true
      }
    }
  ],
  "meta": {
    "record-count": 30,
    "page-count": 1
  }
}
```

### Complete Workflow Response
```json
{
  "success": true,
  "v1_template_id": "1822",
  "new_template_id": "6029",
  "new_template_name": "Professional Services Template V2",
  "mappings_learned": 42,
  "debug_log": "1️⃣ Downloading v1 template 1822...\n✓ Downloaded..."
}
```

## Error Handling

### Template Not Found
```json
{
  "error": "Failed to download template: 404 Not Found"
}
```

### No Mappings Learned
```json
{
  "error": "Workflow failed: Could not learn mappings from project",
  "traceback": "..."
}
```

### Upload Failed
```json
{
  "error": "Failed to create template: 422 Unprocessable Entity"
}
```

## Benefits of Complete Workflow

### 1. Full Automation
- No manual download/upload steps
- Mappings learned automatically
- Conversion applied automatically
- Ready to test immediately

### 2. Validation Loop
- Download from production
- Learn from real data
- Upload back to production
- Test on real projects
- Iterate if needed

### 3. Persistent Learning
- Mappings saved to database
- Confidence scores increase over time
- Knowledge builds across multiple projects
- High-confidence mappings can be exported

### 4. Production-Ready
- Templates created with correct metadata
- Starts as inactive for safe testing
- Proper filename and format settings
- Ready for activation when validated

## Usage Examples

### Example 1: Migrate PS Template

1. Click "📋 Load Templates"
2. Select "Professional Services Template V1 (ID: 1822)"
3. Enter project ID: "{project_id}"
4. Enter name: "Professional Services Template V2 - Test"
5. Click "🚀 Run Complete Workflow"
6. Wait ~30 seconds for completion
7. Result: New template ID 6029 created
8. Go to ScopeStack → Templates → ID 6029
9. Generate document for project {project_id}
10. Compare with v1 output

### Example 2: Bulk Migration

For multiple templates:
```python
# Using CLI tool
python3 template_manager.py list  # Get all v1 template IDs

# For each v1 template:
curl -X POST http://localhost:5001/api/templates/convert-and-upload \
  -H "Content-Type: application/json" \
  -d '{
    "v1_template_id": "1822",
    "project_id": "{project_id}",
    "new_template_name": "Template V2"
  }'
```

### Example 3: Test and Iterate

1. Run workflow → Get template ID 6029
2. Test in ScopeStack → Find issues with pricing table
3. Fix mappings in `template_converter.py`
4. Run workflow again → Get template ID 6030
5. Test again → Looks good!
6. Activate template 6030
7. Deactivate old templates

## Future Enhancements

### 1. Document Generation API
Currently missing: Generate documents programmatically via API

**Would enable**:
- Automated testing (generate v1 and v2 docs, compare)
- Batch validation across multiple projects
- Visual diff of outputs

### 2. Mapping Diff Viewer
Show what changed between v1 and v2:
```
v1: =project_name
v2: {project.project_name}
Status: ✓ Mapped

v1: pricing.resources:each(resource)
v2: {#pricing.resources}...{/pricing.resources}
Status: ✓ Mapped
```

### 3. Rollback Support
If v2 template has issues:
- Keep v1 template active
- Mark v2 as "testing"
- Easy rollback if needed

### 4. Template Versioning
Track multiple versions of the same template:
- V1 Original
- V2 First Attempt
- V2 Fixed
- V2 Final

## Troubleshooting

### Template List Empty
- Check authentication
- Verify API access
- Try "active only" filter unchecked

### Mapping Learning Fails
- Verify project ID exists
- Check project has valid merge data
- Try different project ID

### Conversion Has Warnings
- Review unmapped fields in debug console
- Add mappings to `template_converter.py`
- Re-run workflow

### Upload Fails
- Check template name is unique
- Verify file format is correct
- Check account permissions

## Summary

This complete workflow transforms the template migration process from manual and error-prone to **automated and validated**:

**Before**: Download → Learn → Convert → Upload → Test (all manual)
**After**: Click button → Wait 30s → Test (fully automated)

The integration with the platform API means you can now:
- ✅ Browse production templates
- ✅ Download automatically
- ✅ Learn from real data
- ✅ Convert with confidence
- ✅ Upload back to platform
- ✅ Test on real projects
- ✅ Iterate quickly

This creates a true **production migration pipeline**!
