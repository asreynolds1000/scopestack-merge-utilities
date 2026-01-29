# Integrated Document + API Learning System

## Overview

The learning system now uses an **integrated approach** that combines document analysis with API data fetching to discover the most accurate v2 field mappings.

## How It Works

### The Problem
Previously, we had two separate systems:
1. **Document Upload**: Upload v1 template and output (but couldn't find v2 paths)
2. **API Learning**: Fetch merge data (but couldn't verify actual values in output)

This separation was ineffective because:
- Documents alone don't tell us v2 paths
- API data alone doesn't confirm what actually rendered in the output

### The Solution: Integrated Workflow

The new system combines both approaches in a single unified workflow:

```
v1 Template + Output Document + Project ID (API) = Complete Mapping
```

#### Step-by-Step Process

1. **Extract v1 Fields from Template**
   - Parse the uploaded v1 template
   - Extract all field names (e.g., `project_name`, `customer_name`)
   - Handle all v1 formats: `=field`, `field:if`, `field:each`

2. **Extract Actual Values from Output Document**
   - Parse the generated output document
   - Extract all text content and values
   - These are the ACTUAL values that were rendered
   - Filter out common words and formatting

3. **Fetch v1 Merge Data from API**
   - Use project ID to fetch v1 merge data
   - Extract all values and their paths
   - Map: `value → v1 field path`

4. **Fetch v2 Merge Data from API**
   - Use same project ID to fetch v2 merge data
   - Extract all values and their paths
   - Map: `value → v2 field path`

5. **Match Everything Together**
   - For each v1 field in template:
     - Find its value in v1 merge data
     - Check if that value appears in output document ✓ (confirmation!)
     - Find where that value appears in v2 merge data
     - Create mapping: `v1_field → value → v2_field`

6. **Save to Persistent Database**
   - Store all discovered mappings
   - Mark confirmed ones (verified in output)
   - Increase confidence scores
   - Build knowledge over time

## Key Advantages

### 1. Verification Through Output
By checking that values actually appear in the output document, we confirm:
- The v1 field was actually used
- The value was actually rendered
- This is a real mapping (not a coincidence)

### 2. Accurate v2 Paths
By fetching v2 merge data from the API, we get:
- The exact v2 field path structure
- Correct nesting and array references
- Real data from the same project

### 3. Complete Traceability
Every mapping has full provenance:
```
v1_field: "project_name"
↓
value: "Acme Corp Implementation" (found in output document ✓)
↓
v2_field: "project.project_name"
```

### 4. Persistent Learning
- Each project analyzed adds to the database
- Confidence scores increase with repeated confirmations
- High-confidence mappings can be exported for template_converter.py

## API Response Structure

When you upload documents, the API returns:

```json
{
  "success": true,
  "project_id": "123456",
  "mappings_discovered": 25,
  "confirmed_mappings": 18,       // From document analysis
  "supplemental_mappings": 7,     // From pure value matching
  "database_stats": {
    "total_mappings": 42,
    "high_confidence": 30,
    "very_high_confidence": 15,
    "projects_analyzed": 3
  },
  "sample_mappings": [
    {
      "v1_field": "project_name",
      "v2_field": "project.project_name",
      "value": "Acme Corp Implementation",
      "confidence": "high",
      "confirmed_in_output": true  // Key indicator!
    }
  ]
}
```

## UI Features

### Integrated Learning Tab
- Upload v1 template (.docx)
- Upload generated output document (.docx)
- Enter project ID for API data
- Optionally upload v2 template (for future enhancements)

### Debug Console
Shows detailed progress:
```
1️⃣ Extracting v1 fields from template...
   Found 35 unique v1 fields
2️⃣ Extracting values from output document...
   Found 142 unique values
3️⃣ Fetching v1 merge data from API...
   ✓ v1 merge data received
4️⃣ Fetching v2 merge data from API...
   ✓ v2 merge data received
5️⃣ Matching fields → values → v2 paths...
   ✓ Found 18 confirmed mappings
6️⃣ Running supplemental value-matching analysis...
   ✓ Found 7 supplemental mappings
✅ Total unique mappings: 25
```

### Results Display
- Total mappings discovered
- Breakdown: confirmed vs supplemental
- Sample mappings with confidence indicators:
  - ✓ 🟢 = High confidence, confirmed in output
  - • 🟡 = Medium confidence, value match only
- Database statistics

## Technical Implementation

### Files Created/Modified

**New Files:**
- `document_analyzer.py` - Document parsing and field/value extraction
- `INTEGRATED_LEARNING.md` - This documentation

**Modified Files:**
- `app.py` - Updated `/api/upload-for-learning` endpoint
- `templates/index.html` - Enhanced UI with workflow explanation
- `mapping_database.py` - Already existed for persistence
- `learn_mappings.py` - Already existed for value matching

### Key Classes

#### DocumentAnalyzer
```python
class DocumentAnalyzer:
    def extract_v1_fields(docx_path) -> List[str]
        """Extract field names from v1 template"""

    def extract_text_values(docx_path) -> Set
        """Extract actual values from output document"""

    def match_fields_to_values(v1_fields, output_values,
                               v1_merge_data, v2_merge_data) -> List[Dict]
        """Core integration logic - match everything together"""
```

#### MappingDatabase
```python
class MappingDatabase:
    def add_mapping(v1_field, v2_field, value, project_id, confidence)
        """Add or update a mapping, increase confidence score"""

    def import_mappings(mappings, project_id)
        """Import multiple mappings at once"""

    def get_high_confidence_mappings(min_score)
        """Get verified mappings for export"""
```

## Usage Example

1. Navigate to http://127.0.0.1:5001
2. Login with ScopeStack credentials
3. Go to "Learn Field Mappings" section
4. Click "From Documents" tab
5. Enter project ID (e.g., 123456)
6. Upload v1 template that has Mail Merge fields
7. Upload the output document generated from that template
8. Click "Upload & Learn Mappings"
9. Watch the debug console show progress
10. See confirmed mappings with ✓ indicators
11. Database grows with each project analyzed

## Future Enhancements

1. **v2 Template Analysis**: Use uploaded v2 template to validate discovered mappings
2. **Loop Detection**: Better handling of array fields and iterations
3. **Conditional Logic**: Map v1 conditionals to v2 conditionals
4. **Export to Code**: Generate template_converter.py mappings automatically
5. **Visual Mapping Editor**: UI to review and edit discovered mappings
6. **Conflict Resolution**: Handle cases where same v1 field maps to different v2 paths

## Database Growth

As you analyze more projects:
- Confidence scores increase for confirmed mappings
- Conflicting mappings are tracked as "alternatives"
- High-confidence mappings (seen 2+ times) can be trusted
- Very-high-confidence mappings (seen 5+ times) are virtually certain

## Export Mappings

Once you have high-confidence mappings, export them:

```bash
python3 mapping_database.py
```

This generates `discovered_mappings.py` with format:
```python
DISCOVERED_SIMPLE_FIELDS = {
    '=project_name': '{project.project_name}',  # Confidence: 5
    '=customer_name': '{project.customer_name}',  # Confidence: 4
    # ...
}
```

Copy these into `template_converter.py` to use them for automatic conversions.
