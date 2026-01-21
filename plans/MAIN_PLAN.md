# Plan: Build Foundation for Data-Driven Template Conversion

## 📋 Implementation Summary

This plan addresses 4 key improvements to the Merge Data Viewer:

1. ✅ **Fix Learn Mapping UX** (15 min) - DONE - Removed page reload when saving mappings
2. ✅ **Fix Nested Array Navigation** (30 min) - DONE - Arrays of arrays now properly extract all children with indices
3. ✅ **Unified Settings Panel** (2-3 hours) - DONE - Shared header with auth/settings modal across both pages
4. ✅ **Structural Array Mapping** (3-4 hours) - DONE - Map entire arrays as structures, not individual items

**Total estimated time**: ~6-8 hours over 1-2 days

**Critical files to modify**:
- `data_structure_extractor.py` - Fix nested array extraction (lines 111-114)
- `templates/merge_data_viewer.html` - ✅ Fixed reload issue (lines 1028-1038)
- `templates/_header.html` - NEW shared header component
- `templates/index.html` - Integrate shared header
- `app.py` - Add auth endpoints, persist AI settings to file
- `learn_mappings.py` - Add structural array matching logic
- `mapping_database.py` - Store array-level mappings

---

## 🎯 Current State (Updated 2025-01-20 - Evening)

**Phase 1 Progress**: Merge Data Viewer is ~95% complete!

**What's Working** ✅:
- UI built with Miller Columns view showing V1/V2 side-by-side
- Click-to-match functionality with confidence scoring
- Manual mapping save/load with database persistence
- Search, scrolling, and syntax examples
- ✅ **FIXED**: Arrays now show all items with display names
- ✅ **FIXED**: Backend extracts all array items, not just [0]

**New Issues Identified** 🔍:
1. ✅ **Too many low-quality matches** - FIXED: Changed threshold from 50 → 80
2. ✅ **Boolean sample values** - Already working correctly (displays true/false when present)
3. **Individual item matching vs structural matching** - Currently learns `language_fields[0]` → `v2[0]` instead of `language_fields[]` → `v2.language_fields[]`
4. **Learn mapping button clears view** - When saving a mapping, entire view disappears and reloads
5. **Auth management between pages** - Need unified settings/auth UI across both pages

**Critical User Insights** (Major Direction Change):

### Issue #1: Match Quality Filtering
> "Right now displaying very long list of potential matches, way too many. The right one is 100%, so really the rest is noise."

**Solution**: Only show matches above a threshold (e.g., 80%), prioritize 100% matches

### Issue #2: Structural Array Mapping (MOST IMPORTANT)
> "If you encounter v1 merge data looping through array items in language_fields, instead of remembering array index 0 matches to v2 array index 0, it's more important to learn that the whole array structure is found in this place in v1 vs v2"

**Current Problem**: We match individual array items
- ❌ `language_fields[0].name` → `v2.language_fields[0].name`
- ❌ `language_fields[1].name` → `v2.language_fields[1].name`

**What We Should Learn**: Array structure itself
- ✅ `language_fields[]` → `v2.language_fields[]` (the array path)
- Learn: "This array in V1 corresponds to this array in V2"

### Issue #3: Filter/Conditional Conversion Pattern
> "Interested in knowing how to make structure conversion rather than single value replacement"

**V1 Sablon Structure:**
```
language_fields:each(language)
  language.out?:if
    =language.name
  language.out?:endIf
language_fields:endEach
```

**V2 DocX Templater Structure:**
```
{#language_fields}
  {#slug=="out"}
    {name}
  {/slug=="out"}
{/language_fields}
```

**What to Learn**:
- Not just: `language.name` → `{name}`
- But also: `language.out?:if` → `{#slug=="out"}`
- Pattern: V1 boolean conditional syntax → V2 equality check syntax

### Issue #4: Learn Mapping Button Clears View
> "When I hit the 'learn mapping' button after I've made two selections, the merge data structure view goes away and I just see loading again. I would prefer it not clear out that view during that process."

**Current Problem**: Clicking "Learn this mapping" causes full page reload
- User loses context, has to wait for data to reload
- Disruptive to workflow

**Solution**: Save mapping via AJAX without reloading page
- Just update the UI to show "Saved!" feedback
- Keep the structure view intact
- Optionally add visual indicator that mapping was saved

### Issue #5: Auth Management Between Pages
> "We need to figure out how this page and the other one will relate to one another. Currently they are two different pages and that can be OK, but we probably need a settings panel as well then that's common between the two to manage auth?"

**Current State**:
- **Main page** (`index.html`): Full conversion workflow with AI settings (OpenAI/Anthropic API keys stored in Flask session)
- **Merge Data Viewer** (`merge_data_viewer.html`): Standalone data comparison page
- **ScopeStack auth**: Managed by `AuthManager` class, tokens saved to `~/.scopestack/tokens.json`
- **AI API keys**: Managed per-session via Flask session storage

**Problems**:
1. No way to manage ScopeStack credentials from UI (only from command line)
2. AI settings are session-specific (lost on page reload)
3. Merge Data Viewer has no settings UI at all
4. Two separate pages with no unified navigation or settings

**Chosen Solution**: ✅ Shared Header with Settings Modal

**Decision**: User selected Option A - shared header with settings modal
- Add common header/navigation to both pages
- Settings gear icon opens modal with tabs:
  - **ScopeStack Auth**: Login, logout, show current user
  - **AI Settings**: API keys for OpenAI/Anthropic (optional for conversion)
- Settings stored server-side (AuthManager for ScopeStack, file-based for AI keys)
- Both pages can access same settings
- Clean and non-disruptive to existing workflow

---

## Executive Summary

**Core Problem**: Architectural disconnection - learning and conversion don't integrate.

**New Direction**: Build the foundation properly:
1. **Merge Data Viewer** - Visualize v1/v2 data structures side-by-side (Mac column view style) ← **IN PROGRESS**
2. **Wire Learning to Conversion** - Make converter actually use learned mappings ← **DONE**
3. **Semantic Structure Models** - Build proper data structure and template structure models ← **NEXT**
4. **Validation Framework** - Compare actual output, not just text similarity ← **FUTURE**

## User's Core Goal

> "Convert a document template from v1 to v2 merge data, upload to ScopeStack, test output, compare outputs, make changes."

The key requirements:
- Understand how Sablon (v1) and DocX Templater (v2) work differently
- Model and compare merge data structures between v1 and v2
- Build Word documents correctly with proper loop/field structures
- Test by generating actual documents and comparing them

## Architectural Analysis Summary

### What's Working ✅
- Merge data fetching from API (solid)
- Value extraction with path tracking (reliable)
- Loop detection in templates (functional)
- Mapping database storage (persistent)
- XML manipulation basics (works)

### What's Broken ❌
- **Converter ignores learned mappings** - Uses 44 hardcoded fields + 18 hardcoded loops
- **Surface-level matching** - "Do field names look similar?" instead of semantic understanding
- **No validation against actual output** - Text similarity doesn't mean structural correctness
- **No data structure models** - We match values, not structures

### The Fundamental Issue

```
Learning System                    Converter
     │                                 │
     ├─ Learns mappings ────X         │
     ├─ Stores in DB        ✗         │
     └─ Ready to help...    ✗         ├─ Uses FIELD_MAPPINGS[44]
                                      ├─ Uses LOOP_CONVERSIONS[18]
                                      └─ Ignores learned mappings
```

We built a recommendation engine that recommends to nobody.

## Proposed Solution: Foundation-First Approach

### Phase 1: Merge Data Viewer (Foundation) - **BUILD THIS FIRST**

**Why first?**
- Forces us to properly model data structures
- Makes it obvious when mappings are wrong
- Provides ground truth for semantic matching
- Shows exactly what changed between v1 and v2

**What it looks like:**
```
┌─────────────────────────────────────────────────────────────┐
│  Merge Data Comparison                                       │
├─────────────────┬─────────────────┬─────────────────────────┤
│  V1 Structure   │  Common Values  │  V2 Structure           │
├─────────────────┼─────────────────┼─────────────────────────┤
│  ▼ locations[3] │                 │  ▼ project              │
│    • name       │  ───────────►   │    ▼ locations[3]       │
│    • address    │  ───────────►   │      • location_name    │
│    • type       │                 │      • location_address │
│                 │                 │      • office_type      │
├─────────────────┼─────────────────┼─────────────────────────┤
│  ▼ pricing[5]   │                 │  ▼ project              │
│    • name       │  ───────────►   │    ▼ project_pricing    │
│    • rate       │  ───────────►   │      ▼ resources[5]     │
│    • hours      │                 │        • resource_name  │
│                 │                 │        • hourly_rate    │
│                 │                 │        • quantity       │
└─────────────────┴─────────────────┴─────────────────────────┘
```

**Features:**
- Mac-style column view (3 columns)
- Left: V1 data structure (expandable tree)
- Middle: Visual connections showing matched fields
- Right: V2 data structure (expandable tree)
- Click on v1 field → highlights all possible v2 matches
- Manual mapping UI - drag to create mappings
- Color coding: green (matched), yellow (uncertain), red (unmatched)

**Benefits:**
- Visual debugging of data structure differences
- Easy to spot incorrect mappings
- Foundation for building semantic matcher
- User can provide ground truth mappings

### Phase 2: Wire Learning to Conversion

**Current Problem:**
```python
# template_converter.py line 290
def _convert_fields(self, xml_content: str) -> str:
    # Only uses hardcoded FIELD_MAPPINGS
    for v1_field, v2_field in FIELD_MAPPINGS.items():
        xml_content = replace_field(v1_field, v2_field)
```

**Solution:**
```python
def _convert_fields(self, xml_content: str, learned_mappings: Dict = None) -> str:
    # Priority: learned > hardcoded > unknown
    all_mappings = {}

    # Start with hardcoded as fallback
    all_mappings.update(FIELD_MAPPINGS)

    # Override with learned mappings (higher confidence)
    if learned_mappings:
        for mapping in learned_mappings:
            if mapping['confidence'] > 0.7:
                all_mappings[mapping['v1_field']] = mapping['v2_field']

    # Perform conversion
    for v1_field, v2_field in all_mappings.items():
        xml_content = replace_field(v1_field, v2_field)
```

**Changes needed:**
1. Modify `_convert_fields()` to accept learned mappings
2. Modify `convert()` to pass learned mappings to `_convert_fields()`
3. Update `/api/analyze-for-review` endpoint to pass learned mappings through conversion
4. Add confidence threshold checking

### Phase 3: Build Semantic Structure Models

**Template Structure Model:**
```python
@dataclass
class Field:
    name: str
    v1_path: str
    expected_type: str  # 'string', 'number', 'date', 'array'
    context: str  # 'root', 'loop', 'conditional'

@dataclass
class Loop:
    var_name: str  # 'location' from :each(location)
    array_name: str  # 'locations' from locations:each
    nested_fields: List[Field]
    nested_loops: List['Loop']  # For nested structures

@dataclass
class TemplateStructure:
    simple_fields: List[Field]
    loops: List[Loop]
    conditionals: List[Conditional]
```

**Merge Data Schema Model:**
```python
@dataclass
class ArrayField:
    path: str  # 'project.locations'
    item_fields: Dict[str, str]  # {'name': 'string', 'address': 'string'}
    count: int  # Number of items in sample data

@dataclass
class MergeDataSchema:
    root_fields: Dict[str, str]  # {field_name: field_type}
    arrays: List[ArrayField]
    nested_objects: Dict[str, 'MergeDataSchema']
```

**Semantic Matcher:**
```python
class SemanticMatcher:
    def match_loop_to_array(self, loop: Loop, schema: MergeDataSchema) -> Optional[LoopMapping]:
        """
        Match a Sablon loop to a V2 array based on:
        1. Field names present in both
        2. Field types match
        3. Cardinality (single vs multiple)
        4. Structural position in hierarchy
        """
        candidates = []
        for array in schema.arrays:
            score = self._calculate_structural_match(loop, array)
            if score > 0.7:
                candidates.append((array, score))

        # Return best match or None if ambiguous
        return self._select_best_match(candidates)
```

### Phase 4: Validation Framework

**Current Problem:** Similarity is measured by comparing text from generated documents, which doesn't catch:
- Incorrect loop structures (still generates text, just wrong structure)
- Missing fields (0% match but maybe only one field wrong)
- Wrong data used in fields

**Solution:** Structure-aware comparison
```python
class DocumentComparator:
    def compare_structure(self, v1_doc: Document, v2_doc: Document) -> ComparisonResult:
        """
        Compare:
        1. Same sections present? (headings, tables, lists)
        2. Same number of loop iterations? (3 locations → 3 locations)
        3. Same field values in corresponding positions?
        4. Same document flow/order?
        """

    def compare_by_section(self, v1_doc: Document, v2_doc: Document) -> Dict[str, float]:
        """
        Return per-section similarity:
        {
            'header': 1.0,
            'locations_table': 0.85,
            'pricing_section': 0.0,  # ← clearly shows where the problem is
            'footer': 1.0
        }
        """
```

## Implementation Order

### Stage 1: Foundation (Week 1)
**Goal:** Build merge data viewer and fix converter integration

#### Task 1.1: Data Structure Extractor (Day 1) - ✅ DONE (with bug)
**File**: `data_structure_extractor.py` (lines 25-129)

**Status**: EXISTS but has critical bug

**Current Implementation**:
```python
class DataStructureExtractor:
    def extract_structure(self, merge_data: dict, prefix: str = "") -> dict:
        # Returns structure with paths like 'language_fields[0].name'
        # BUG: Only extracts first array item [0], not all items
```

**The Bug** (line 106):
```python
if isinstance(value, list):
    info['array_count'] = len(value)
    if len(value) > 0:
        first_item = value[0]  # ← Only processes first item!
        info['children'] = self.extract_structure(
            first_item,
            f"{path}[0]",  # ← Only creates [0] paths
            strip_prefix=""
        )
```

**Impact**:
- Array with 4 items only creates children for `[0]`
- UI can only display one array item instead of all 4
- Console shows: "Array indices found: [0]" instead of [0, 1, 2, 3]

**Fix Required**:
```python
if isinstance(value, list):
    info['array_count'] = len(value)
    if len(value) > 0:
        all_children = {}
        for index, item in enumerate(value):
            item_children = self.extract_structure(item, f"{path}[{index}]", strip_prefix="")
            all_children.update(item_children)
        info['children'] = all_children
```

#### Task 1.2: Merge Data Viewer Backend (Day 1-2)
**File**: Modify `app.py`

**Add endpoints**:
```python
@app.route('/api/merge-data-structure/<project_id>')
def get_merge_data_structure(project_id):
    """
    Returns:
    {
        'v1_structure': {...},
        'v2_structure': {...},
        'suggested_mappings': [...],  # From existing learner
        'manual_mappings': [...]      # From database
    }
    """
```

#### Task 1.3: Merge Data Viewer UI (Day 2-3) - ✅ DONE (mostly working)
**File**: `templates/merge_data_viewer.html`

**Status**: EXISTS and functional, with array display issue

**Current Features**:
- ✅ Mac-style Miller Columns view (side-by-side V1/V2)
- ✅ Click field in V1 → shows matching fields in V2 with match scores
- ✅ "Learn this mapping" button saves to database
- ✅ Collapsible accordion for match results with percentages
- ✅ Search functionality for both V1 and V2 structures
- ✅ Horizontal scrolling for deep nesting
- ✅ Syntax examples shown for selected fields
- ✅ Color-coded match confidence (green/orange/red badges)

**Known Issues**:
1. **Array items not displaying** - Only shows `[0]` item (see Task 1.1 bug)
2. **Manual mappings counter not updating** - Fixed (now reloads data after save)

**Key Lessons Learned**:
> **User insight**: "If it is an array, look for name value and you can use that as the name in the column"

**Enhanced Array Display Strategy**:
Instead of showing generic `[0]`, `[1]`, `[2]`, `[3]`:
- Look for identifying fields like `name`, `title`, `label`
- Show as: "English", "Spanish", "French" (from language_fields[].name)
- Fallback to `[0]`, `[1]` if no name field exists

**Implementation** (lines 589-612):
```javascript
// Create virtual items for each array index
childItems = Array.from(arrayIndices)
    .map(index => {
        const arrayItemPath = `${parentPath}[${index}]`;
        const itemChildren = {...};  // Collect children

        // NEW: Find display name from "name" field
        const nameField = itemChildren[`${arrayItemPath}.name`];
        const displayName = nameField?.sample_value || `[${index}]`;

        return {
            path: arrayItemPath,
            displayName: displayName,  // Use for UI display
            data: {...}
        };
    });
```

#### Task 1.4: Wire Learning to Converter (Day 4)
**File**: Modify `template_converter.py`

**Changes**:
```python
def convert(self, loop_mappings: Dict = None, learned_field_mappings: List[Dict] = None) -> bool:
    # ... existing code ...

    # Build merged mapping dict
    all_field_mappings = self._merge_mappings(learned_field_mappings)

    # Pass to field conversion
    xml_content = self._convert_fields(xml_content, all_field_mappings)

def _merge_mappings(self, learned_mappings: List[Dict]) -> Dict:
    """
    Merge hardcoded and learned mappings.
    Priority: learned (confidence > 0.7) > hardcoded
    """
    result = FIELD_MAPPINGS.copy()  # Start with hardcoded

    if learned_mappings:
        for mapping in learned_mappings:
            if mapping.get('confidence', 0) > 0.7:
                result[mapping['v1_field']] = mapping['v2_field']

    return result

def _convert_fields(self, xml_content: str, field_mappings: Dict) -> str:
    # Use provided mappings instead of hardcoded FIELD_MAPPINGS
    for v1_field, v2_field in field_mappings.items():
        xml_content = self._replace_field(v1_field, v2_field, xml_content)
    return xml_content
```

**File**: Modify `app.py` conversion endpoint

**Changes**:
```python
@app.route('/api/convert-with-ai', methods=['POST'])
def convert_with_ai():
    # ... existing code ...

    # Get learned mappings from database
    from mapping_database import MappingDatabase
    db = MappingDatabase()
    learned_mappings = db.get_mappings_for_project(project_id)

    # Pass to converter
    converter = TemplateConverter(template_path, converted_path)
    converter.convert(
        loop_mappings=loop_mappings,
        learned_field_mappings=learned_mappings
    )
```

### Stage 2: Semantic Models (Week 2)
**Goal:** Build proper structure models and semantic matcher

4. **Template Structure Extractor** (2 days)
   - Parse template to extract `TemplateStructure`
   - Detect all loops, conditionals, nested structures
   - Build field dependency graph

5. **Merge Data Schema Extractor** (1 day)
   - Parse merge data to extract `MergeDataSchema`
   - Identify arrays, nested objects, field types

6. **Semantic Matcher** (2 days)
   - Implement `SemanticMatcher.match_loop_to_array()`
   - Structure-aware field matching
   - Confidence scoring based on structure + values

### Stage 3: Validation (Week 3)
**Goal:** Proper output comparison and iterative improvement

7. **Structure-Aware Comparator** (2 days)
   - Extract document structure (sections, tables, lists)
   - Compare structure, not just text
   - Per-section similarity reporting

8. **Iterative Improvement Loop** (2 days)
   - Generate test docs from both templates
   - Compare structures
   - Identify which mappings are wrong
   - Suggest fixes based on structural differences
   - Re-convert and validate

## Critical Files

### To Create
- `templates/merge_data_viewer.html` - New tab UI
- `data_structure_extractor.py` - Extract structure from merge data
- `template_structure_extractor.py` - Extract structure from templates
- `semantic_matcher.py` - Structure-aware matching
- `document_comparator.py` - Structure-aware comparison

### To Modify
- `app.py` - Add `/api/merge-data-viewer` endpoint, wire learned mappings to conversion
- `template_converter.py` - Accept learned mappings in `_convert_fields()`
- `templates/index.html` - Add "Merge Data Viewer" tab

### Reference Only (Don't Change Yet)
- `learn_mappings.py` - Working well, will enhance later with semantic matching
- `merge_data_fetcher.py` - Working well, no changes needed
- `mapping_database.py` - Working well, may extend schema later

## Success Criteria

### Phase 1 Success
- [ ] Merge data viewer shows v1 and v2 structures side-by-side
- [ ] Can click on v1 field and see all v2 candidates
- [ ] Visual connections show current mappings
- [ ] Can manually create/override mappings in UI
- [ ] Converter uses learned mappings instead of hardcoded ones

### Phase 2 Success
- [ ] Template structure extractor finds all loops and fields correctly
- [ ] Merge data schema extractor builds complete structure tree
- [ ] Semantic matcher scores loop-to-array matches with confidence
- [ ] Can detect when multiple arrays match and flag ambiguity

### Phase 3 Success
- [ ] Document comparator identifies structural differences (not just text)
- [ ] Per-section similarity shows exactly where problems are
- [ ] Iterative improvement actually fixes structural issues
- [ ] Final converted template generates documents with >90% structural similarity

## Design Decisions ✅

1. **UI Framework**: React or Vue.js
   - Use React for merge data viewer (better for complex tree interactions)
   - Build as separate component, integrate with existing Flask app
   - Serve via CDN to avoid build complexity

2. **Confidence Thresholds**:
   - Use learned mapping over hardcoded: **0.7**
   - Show mapping as "certain" vs "uncertain": **0.8 vs 0.5**
   - Auto-apply vs require user confirmation: **0.9 vs 0.7**

3. **Manual Mapping Storage**: mapping_database.py with confidence=1.0
   - Store manual mappings alongside learned ones
   - Set confidence=1.0 to indicate user-verified
   - Add source='manual' flag to distinguish from learned

4. **Validation Approach**: Word XML structure comparison
   - Extract and compare Word XML structure directly
   - Most accurate for detecting loop/structural issues
   - Can identify specific sections with problems

5. **Array Display & Matching** (NEW - from user feedback):
   - Display array items by their "name" field when available
   - Search for common identifying fields: `name`, `title`, `label`, `code`
   - This makes arrays human-readable: "English", "Spanish" vs `[0]`, `[1]`
   - **Array matching strategy**: Look INSIDE array objects to find structural matches
   - Compare array item structure (field names/types) not just array name
   - Example: V1 `language_fields[]` with `{name, code}` matches V2 `project.languages[]` with `{name, code}`

## Current Status & Immediate Fixes Needed

### What's Working ✅
- Merge Data Viewer UI is built and functional
- API endpoint `/api/merge-data-structure/{project_id}` exists
- Manual mapping save/reload working
- Match scoring and display working
- Search functionality working

### Critical Bug to Fix 🐛
**Problem**: Array items not displaying in viewer (only shows `[0]`)

**Root Cause**: `data_structure_extractor.py` line 106 only processes first array item

**Files to Fix**:
1. **`data_structure_extractor.py`** (line 96-118):
   - Extract ALL array items, not just `[0]`
   - Loop through entire array: `for index, item in enumerate(value)`
   - Build paths: `language_fields[0].name`, `language_fields[1].name`, etc.

2. **`merge_data_viewer.html`** (lines 589-612):
   - Already handles multiple indices correctly
   - Just needs backend to provide all array items
   - Add display name extraction from `.name` field

### Next Implementation Tasks (REVISED - in priority order)

**Task A: Fix Array Extraction** ✅ DONE
- Fixed backend to extract all array items
- Fixed UI to show display names from `.name` field

**Task B: Fix Boolean Sample Values** ✅ DONE
- Code already handles booleans correctly (line 158-159)
- If showing empty, the data value is actually null/None (correct behavior)

**Task C: Filter Low-Quality Matches** ✅ DONE
- Changed threshold from 50 → 80 (line 917 in merge_data_viewer.html)
- Now only shows high-confidence matches

**Task D: Fix Learn Mapping Page Reload** ✅ DONE (15 minutes - QUICK WIN, HIGH IMPACT)
**Problem**: When user clicks "Learn this mapping", page does full reload

**Solution Implemented**:
- Removed `await loadMergeData()` call that was causing full reload
- Instead, update just the manual mappings count in React state
- Success message appears, counter increments, view stays intact
- File: `merge_data_viewer.html` lines 1028-1038

**Task D2: Fix Nested Array Navigation** ✅ DONE (30 minutes)
**Problem**: User navigated to `language_fields[0].phases[1].sentences` (array with 8 items), but cannot navigate into those items to see their contents. Details panel shows "[8 items]" but no next column appears.

**Root Cause**: `data_structure_extractor.py` lines 111-114 - array-of-arrays case
```python
elif isinstance(first_item, list):
    info['item_type'] = 'array'
    info['children'] = {}  # ← EMPTY! Never populates children for nested arrays
```

**Solution**: Extract nested array items just like we do for arrays of objects:
```python
elif isinstance(first_item, list):
    # Array of arrays (nested) - extract all items with indices
    all_children = {}
    for index, item in enumerate(value):
        item_path = f"{path}[{index}]"
        item_children = self.extract_structure(item, item_path, strip_prefix="")
        all_children.update(item_children)
    info['item_type'] = 'array'
    info['children'] = all_children  # ← Now populated!
```

**Changes needed**:
1. Modify `data_structure_extractor.py` lines 111-114
2. Apply same index-based extraction logic used for array-of-objects
3. Test with nested arrays: navigate to `sentences` array, should see `sentences[0]`, `sentences[1]`, etc. in next column

**Task E: Unified Settings Panel** (2-3 hours - ARCHITECTURAL)
**Goal**: Shared settings UI for both pages

**Approach: Option A - Shared Header Component**

**Implementation**:
1. **Create shared header partial** (`templates/_header.html`):
   - Logo/title
   - Navigation links (Converter, Merge Data Viewer)
   - Settings gear icon (opens modal)
   - Current user display (from ScopeStack auth)

2. **Create settings modal** (JavaScript component):
   - **Tab 1: ScopeStack Auth**
     - Login form (email/password)
     - Show current user when logged in
     - Logout button
     - Uses `/api/auth/login`, `/api/auth/logout` endpoints

   - **Tab 2: AI Settings** (optional, for conversion features)
     - Provider selection (OpenAI/Anthropic)
     - API key input
     - Enable/disable toggle
     - Uses existing `/api/settings/ai` endpoints

3. **Backend API endpoints** (`app.py`):
   - `POST /api/auth/login` - Accept email/password, call AuthManager.login()
   - `GET /api/auth/status` - Return current user info from AuthManager
   - `POST /api/auth/logout` - Clear tokens
   - Modify AI settings endpoints to persist to file instead of session

4. **Storage changes**:
   - ScopeStack: Already using `~/.scopestack/tokens.json` ✅
   - AI settings: Move from Flask session → `~/.scopestack/ai_settings.json`
   - Both persist across sessions and pages

5. **Include header in both pages**:
   - `index.html`: Add `{% include '_header.html' %}`
   - `merge_data_viewer.html`: Add same include
   - Consistent navigation and settings access

**Benefits**:
- Single source of truth for auth
- Settings persist across sessions
- Both pages have access to same credentials
- User can manage everything from UI (no CLI needed)

**Task F: Structural Array Mapping** (3-4 hours - CRITICAL FEATURE)
This is the paradigm shift for array matching

**Problem**: Currently mapping individual array items
**Goal**: Map arrays as structural units

**Sub-tasks**:
1. **Detect when user is mapping array items** (30 min)
   - When user clicks array item field like `language_fields[0].name`
   - Recognize this is inside an array structure
   - Extract array path: `language_fields` (without index)

2. **Find matching arrays structurally** (2 hours)
   - Compare V1 array fields: `{name, code, out?, enabled}`
   - Find V2 arrays with similar field structure
   - Score by: % of matching field names, matching types
   - Example: V1 `language_fields[]` matches V2 `language_fields[]` (same fields)

3. **Store array-level mappings** (1 hour)
   - Database schema: Store `language_fields[]` → `v2.language_fields[]`
   - Not: `language_fields[0]` → `v2.language_fields[0]`
   - Include field mappings within array structure

4. **UI Changes** (30 min)
   - When clicking array field, show: "Part of array: language_fields"
   - Suggest: "Map entire array structure" button
   - Show array-level match, not individual item matches

**Task E: Conditional Pattern Learning** (4-6 hours - FUTURE/PHASE 2)
This is about learning template conversion patterns, not merge data mappings

**Scope**: Learn syntax transformation patterns
- V1: `field?:if` / `:endIf` → V2: `{#field=="value"}` / `{/field}`
- V1: `array:each(item)` / `:endEach` → V2: `{#array}` / `{/array}`

**This belongs in Phase 2** (Template Structure Models) - not urgent for viewer

## Next Steps (REVISED - 2025-01-20 Evening)

**Already Done ✅:**
1. ✅ **Task A: Array Extraction** - Backend extracts all array items
2. ✅ **Task A: Array Display Names** - Shows names from `.name` field
3. ✅ **Task B: Boolean Sample Values** - Code already correct
4. ✅ **Task C: Filter Low-Quality Matches** - Threshold changed to 80%
5. ✅ **Task D: Fix Learn Mapping Page Reload** - Removed reload, view stays intact

**Immediate:**
6. ✅ **Task D2: Fix Nested Array Navigation** - DONE
   - Fixed `data_structure_extractor.py` lines 111-114
   - Arrays of arrays now properly extract all children with indices
   - Test confirmed: `sentences` array now shows all child items

**Short-term (Next 2-3 hours):**
7. **Task E: Unified Settings Panel** - 2-3 hours (ARCHITECTURAL)
   - Shared header across both pages
   - Settings modal with ScopeStack auth + AI settings
   - Persist settings to files instead of session
   - User can manage auth from UI

**Medium-term (Next 3-4 hours):**
8. **Task F: Structural Array Mapping** - 3-4 hours (CRITICAL FEATURE)
   - Detect array structures
   - Match arrays by field similarity
   - Store array-level mappings
   - UI suggests "Map entire array"

**Future/Phase 2:**
- **Conditional Pattern Learning** - Template syntax transformation
- Enhanced semantic matching based on array structures
- Loop/conditional conversion patterns

**Priority Order**:
1. ✅ Task D (quick UX win) - DONE
2. ✅ Task D2 (nested array navigation bug) - DONE
3. ✅ Task E (architectural foundation) - DONE
4. ✅ Task F (core feature) - DONE

**Phase 1 Complete!**

**Do NOT:**
- Skip Task E (unified settings) - needed before Task F makes sense
- Build template syntax learning before merge data structure is solid
- Assume auth will always work from command line only

---

## ✅ Verification & Testing

### Task D: Learn Mapping UX Fix ✅
**Status**: COMPLETED
- Page no longer reloads after saving mapping
- Success message appears
- View stays intact
- Manual Mappings counter increments correctly

### Task D2: Nested Array Navigation Fix
**Test**: After implementation
1. Navigate to http://localhost:5000/merge-data-viewer.html?project=103063
2. Drill down to: Root › language_fields › language_fields[0] › phases › phases[1] › sentences
3. Click on `sentences` (array with 8 items)
4. **Verify next column appears** with:
   - [ ] `sentences[0]` as clickable item
   - [ ] `sentences[1]` as clickable item
   - [ ] ... up to `sentences[7]`
5. Click on `sentences[0]`
6. **Verify next column** shows the fields/contents of that sentence item
7. **Backend verification**:
   - Open http://localhost:5000/api/merge-data-structure/103063 in browser
   - Search JSON for `"language_fields[0].phases[1].sentences"`
   - Verify `children` object is NOT empty
   - Should contain keys like `"language_fields[0].phases[1].sentences[0]"`, etc.

### Task E: Unified Settings Panel
**Test**: After implementation
1. Navigate to http://localhost:5000/
2. **Verify header present**:
   - [ ] Logo/title shows
   - [ ] Navigation links: "Converter" and "Merge Data Viewer"
   - [ ] Settings gear icon visible
3. Click settings gear icon
4. **Verify modal opens** with tabs:
   - [ ] Tab 1: ScopeStack Auth (login form or current user if logged in)
   - [ ] Tab 2: AI Settings (provider selection, API key input)
5. **Test ScopeStack login**:
   - Enter email/password
   - Click login
   - [ ] Success message shows
   - [ ] Current user email displays in header
   - [ ] Tokens saved to `~/.scopestack/tokens.json`
6. **Test AI settings**:
   - Select provider (OpenAI/Anthropic)
   - Enter API key
   - Click save
   - [ ] Settings saved to `~/.scopestack/ai_settings.json`
   - [ ] Settings persist after page reload
7. Navigate to http://localhost:5000/merge-data-viewer.html
8. **Verify same header**:
   - [ ] Settings gear icon present
   - [ ] Same user email shows
   - [ ] Can access same settings modal
9. **Test persistence**:
   - Close browser
   - Reopen http://localhost:5000/
   - [ ] Still logged in (user email shows)
   - [ ] AI settings still present

### Task F: Structural Array Mapping
**Test**: After implementation
1. Navigate to http://localhost:5000/merge-data-viewer.html?project=103063
2. Click on an array item field: `language_fields[0].name`
3. **Verify array detection**:
   - [ ] UI shows "Part of array: language_fields"
   - [ ] "Map entire array structure" button appears
4. Click "Map entire array structure" button
5. **Verify array-level matching**:
   - [ ] Shows V2 arrays with similar field structures
   - [ ] Highlights `language_fields[]` (without index) as best match
   - [ ] Shows match score based on field similarity
6. Click the matched V2 array
7. Click "Learn array mapping"
8. **Verify storage**:
   - [ ] Database stores `language_fields[]` → `v2.language_fields[]`
   - [ ] NOT `language_fields[0]` → `v2.language_fields[0]`
9. Open database/check API response
10. **Verify structure**:
    - [ ] Mapping includes array path without index
    - [ ] Includes field-level mappings within array
    - [ ] Can be used by converter to map entire array at once

### End-to-End Test
1. Start Flask app: `python app.py`
2. Open main page: http://localhost:5000/
3. Login via settings modal
4. Upload V1 template
5. Select project
6. Navigate to Merge Data Viewer (via header link)
7. Map several fields including an array
8. Return to main page (via header link)
9. Convert template
10. **Verify**:
    - [ ] Converter uses learned mappings (including array mapping)
    - [ ] Converted template correctly maps array structures
    - [ ] Both pages share same auth/settings state

## Time Estimates

- **Merge Data Viewer**: 2-3 days (UI + data extraction)
- **Wire Learning to Conversion**: 1 day (straightforward integration)
- **Semantic Models**: 3-4 days (structure extraction + matching)
- **Validation Framework**: 3-4 days (comparison + improvement loop)

**Total**: ~2-3 weeks for complete foundation

## Risk Mitigation

**Risk**: Merge data structures vary significantly between projects
**Mitigation**: Build viewer first to visualize differences, use it to understand patterns

**Risk**: Semantic matching may still be unreliable
**Mitigation**: Manual mapping UI provides fallback, store ground truth to improve algorithm

**Risk**: Structure-aware comparison may be complex
**Mitigation**: Start with simple section-based comparison, iterate to more sophisticated

**Risk**: 2-3 weeks feels long
**Mitigation**: Each phase provides immediate value independently, can stop after Phase 1 and still have useful tool

## Testing & Verification

### Phase 1 Testing

**Data Structure Extractor** (Task A verification):
```bash
# Test with project 103063 (has language_fields array with 4 items)
curl http://localhost:5000/api/merge-data-structure/103063 | jq '.v2_structure.language_fields'

# Should show:
# - "array_count": 4 (not 1)
# - children with paths for [0], [1], [2], [3]:
#   "language_fields[0].name"
#   "language_fields[1].name"
#   "language_fields[2].name"
#   "language_fields[3].name"
```

**Merge Data Viewer** (Task B verification):
1. Navigate to http://localhost:5000/merge-data-viewer.html?project=103063
2. Click on "language_fields" in V2 structure
3. Open browser console and verify:
   - [ ] Console shows: "Array indices found: [0, 1, 2, 3]" (not just [0])
   - [ ] Next column displays 4 items (not 1)
4. UI verification:
   - [ ] Array items show meaningful names like "English", "Spanish" (not "[0]", "[1]")
   - [ ] Click on array item shows fields inside (conclusion, introduction, etc.)
   - [ ] All 4 array items are clickable and navigable
5. General tests:
   - [ ] V1 structure displays in left column with expandable tree
   - [ ] V2 structure displays in right column with expandable tree
   - [ ] Click on v1 field highlights matching v2 fields
   - [ ] Match accordion shows with percentages
   - [ ] Search works in both V1 and V2
   - [ ] Manual mappings persist after page refresh
   - [ ] Sample values show on hover

**Converter Integration**:
1. Convert a template with learned mappings
2. Check console output:
   - [ ] Shows "Using X learned mappings (confidence > 0.7)"
   - [ ] Lists which mappings are learned vs hardcoded
3. Open converted template:
   - [ ] Fields that were learned should be converted
   - [ ] Fields not in learned set should use hardcoded fallbacks
4. Upload and test:
   - [ ] Generate document from converted template
   - [ ] Verify learned field mappings produced correct output

### Phase 2 Testing

**Template Structure Extractor**:
```bash
python3 template_structure_extractor.py template.docx
# Should output: fields, loops, conditionals with nesting
```

**Semantic Matcher**:
```python
from semantic_matcher import SemanticMatcher
matcher = SemanticMatcher()
result = matcher.match_loop_to_array(loop, v2_schema)
# Should return: array path, confidence, or None if ambiguous
```

Verify:
- [ ] Correctly matches loops to arrays by field similarity
- [ ] Detects ambiguous matches (multiple arrays score >0.7)
- [ ] Considers structural position (nested loops)
- [ ] Confidence scores correlate with actual correctness

### Phase 3 Testing

**Structure-Aware Comparator**:
```python
from document_comparator import DocumentComparator
comparator = DocumentComparator()
result = comparator.compare_structure(v1_doc, v2_doc)
# Should return per-section similarity scores
```

Verify:
- [ ] Identifies sections correctly (headings, tables, lists)
- [ ] Counts loop iterations correctly (3 locations in both)
- [ ] Detects missing sections
- [ ] Detects incorrect field values in correct structure
- [ ] Overall score reflects structural similarity, not just text

**End-to-End**:
1. Upload v1 template
2. Select project
3. Review in merge data viewer
4. Make manual adjustments if needed
5. Convert template
6. Verify console shows:
   - [ ] Using learned mappings
   - [ ] Loop structures matched with confidence scores
   - [ ] Content preservation stats (before/after counts)
7. Generate test documents from v1 and v2 templates
8. Run structure comparison
9. Verify:
   - [ ] Per-section similarity shows specific problem areas
   - [ ] Overall structural similarity >80%
   - [ ] Improvement suggestions are actionable

## Rollback Plan

If Stage 1 doesn't provide value:
- Keep merge data viewer as standalone debugging tool
- Revert converter changes
- Return to hardcoded mappings with manual overrides

If Stage 2 has issues:
- Use simple field name matching instead of semantic matching
- Manual mapping via viewer becomes primary method
- Defer full semantic models to later

If Stage 3 too complex:
- Fall back to existing text similarity comparison
- Use manual review via document viewer
- Focus on making Stages 1-2 excellent
