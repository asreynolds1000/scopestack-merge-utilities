# Redesigned Unified Conversion Workflow

## Overview

Based on your feedback, we've redesigned the system to have **two clear workflows**:

1. **🔄 Convert Template** - Unified conversion with review/override
2. **🎓 Learn & Improve** - Discover and curate mappings

The key improvements:
- ✅ Workflows 1 & 2 merged into one unified conversion flow
- ✅ Upload local OR select from platform (same workflow)
- ✅ Always learns as you go
- ✅ Review & override mappings before conversion
- ✅ Path coherence scoring for smart suggestions

---

## Workflow 1: Convert Template

### The Unified 4-Step Process

```
Step 1: Choose Input          Step 2: Learn (Optional)
┌────────────────┐            ┌──────────────────────┐
│ Upload Local   │    or      │ Enter Project ID     │
│ Select Platform│  ------>   │ System learns from   │
└────────────────┘            │ real project data    │
                              └──────────────────────┘
        ↓                              ↓
Step 3: Review Mappings       Step 4: Output
┌──────────────────────┐      ┌──────────────────────┐
│ See predictions      │      │ Download file   or   │
│ Override any mapping │----->│ Upload to platform   │
│ Path coherence hints │      └──────────────────────┘
└──────────────────────┘
```

### Step 1: Choose Template Source

**Two input methods** in the same workflow:

#### Option A: Upload Local File
- Click "📤 Upload Local File" card
- Drag & drop or browse for .docx
- System analyzes template

#### Option B: Select from Platform
- Click "☁️ Select from Platform" card
- Click "Load Templates" to fetch from ScopeStack
- Filter to v1 templates only
- Select from dropdown
- System downloads and analyzes

**Both options lead to the same next steps!**

### Step 2: Learn Mappings (Optional)

After getting the template, you're offered to learn:

```
Project ID: [______{project_id}_______]  (optional)

[📚 Learn & Continue]  [Skip Learning →]
```

**If you provide project ID:**
- System fetches v1 and v2 merge data
- Performs value-matching
- Discovers field mappings
- Adds to mapping database

**If you skip:**
- Uses existing mapping knowledge
- Proceeds with current database

### Step 3: Review & Override Mappings

**This is the key new feature** - review before converting!

#### Mapping Review Interface

Each mapping is shown as a card:

```
┌─────────────────────────────────────────────────────┐
│ v1: =project_name                                   │
│  ↓                                                   │
│ v2: {project.project_name}                          │
│                                                      │
│ Confidence: ● High  |  Coherence: 0.85             │
│ Reason: value_match, parallel structure             │
│                                                      │
│ [Override This Mapping]                            │
└─────────────────────────────────────────────────────┘
```

**Color Coding:**
- 🟢 Green border = High confidence
- 🟡 Yellow border = Medium confidence
- 🔴 Red border = Low confidence

**Path Coherence Indicators:**
- Shows coherence score (0.0 - 1.0)
- Highlights mappings that maintain structural blocks
- Warns if breaking out of current loop context

#### Override Functionality

Click "Override This Mapping" on any card:
- Opens input dialog
- Enter custom v2 path
- System validates syntax
- Updates mapping
- Your override is saved to database

#### The Path Coherence Advantage

**Example shown:**
```
┌────────────────────────────────────────────────────┐
│ 📊 Path Coherence:                                 │
│                                                     │
│ Mappings within the same loop structure are        │
│ prioritized to maintain structural consistency.    │
│                                                     │
│ Current context: project.pricing.phases           │
│                                                     │
│ ✓ Coherent:   project.pricing.phases[].services  │
│ ✗ Breaks out: some_other_array[].services        │
└────────────────────────────────────────────────────┘
```

**When you're inside:**
```
v1: phases_with_tasks:each(phase)
      phase.tasks:each(task)
        =task.name
```

**System prefers:**
```
v2: {#project.pricing.phases}
      {#services}
        {name}
```

**Over unrelated:**
```
v2: {#random_array}
      {#different_services}
        {name}
```

### Step 4: Output Options

After conversion, choose how to get your v2 template:

#### Option A: Download
```
┌─────────────────────┐
│  ⬇️  Download File  │
│                     │
│  [Download .docx]   │
└─────────────────────┘
```

#### Option B: Upload to Platform
```
┌─────────────────────────────────┐
│  ☁️  Upload to Platform         │
│                                 │
│  Name: [_______________]        │
│                                 │
│  [Upload to ScopeStack]         │
└─────────────────────────────────┘
```

---

## Path Coherence Scoring Algorithm

### The Problem

When a v1 field value matches multiple v2 paths, which one is correct?

**Example:**
```
v1: =task.name

Could match:
- project.pricing.phases[].services[].name
- project.tasks[].name
- some_array[].items[].name
```

All have a field called `name`, but which is structurally correct?

### The Solution: 3 Scoring Rules

#### Rule 1: Depth Matching (30% weight)

Match the nesting level:

```
v1 context depth: 2
  (inside phases_with_tasks → phase.tasks)

v2 depth matching:
  project.pricing.phases[].services[].name  ← depth 2 ✓
  project.tasks[].name                      ← depth 1
```

Score: 0.3 if match, 0.15 if off-by-one, 0 otherwise

#### Rule 2: Context Path Coherence (40% weight)

Stay within the current loop structure:

```
Current v2 context: project.pricing.phases

Candidates:
  project.pricing.phases[].services[].name  ← starts with context ✓
  project.tasks[].name                      ← different path
```

Score: 0.4 if stays within, 0.2 if partial, 0 otherwise

#### Rule 3: Sibling Coherence (30% weight)

Keep siblings together:

```
Siblings in v1:
  =task.name
  =task.description
  =task.hours

If task.description → project.pricing.phases[].services[].description
Then task.name should also → project.pricing.phases[].services[].name
```

Score: 0.3 * (common_prefix_ratio)

### Total Score Example

For `=task.name` with context `project.pricing.phases`:

```
Candidate: project.pricing.phases[].services[].name

Rule 1 (depth):     0.30  (depth 2 = depth 2)
Rule 2 (context):   0.40  (starts with project.pricing.phases)
Rule 3 (siblings):  0.00  (no siblings mapped yet)
                    ─────
Total:              0.70  = HIGH confidence
```

```
Candidate: project.tasks[].name

Rule 1 (depth):     0.15  (depth 1 ≈ depth 2)
Rule 2 (context):   0.00  (different path)
Rule 3 (siblings):  0.00  (no siblings)
                    ─────
Total:              0.15  = LOW confidence
```

**Result: First candidate ranked higher!**

---

## Learning as You Go

### Every Conversion Learns

No matter which workflow you use, the system learns:

1. **Explicit learning** (Step 2 with project ID):
   - Fetches merge data
   - Discovers mappings
   - Saves to database

2. **Implicit learning** (any conversion):
   - Your mapping choices are saved
   - Overrides are recorded as high-confidence
   - Future conversions benefit

### Database Growth

```
Initial state:
  - 50 pre-defined mappings
  - Confidence scores: 1-3

After 5 conversions:
  - 150 mappings (discovered)
  - Confidence scores: 1-8
  - High-confidence mappings: 75

After 20 conversions:
  - 300 mappings
  - Confidence scores: 1-15
  - High-confidence mappings: 200
```

**The system gets smarter with every use!**

### Override Priority

```
Mapping sources (priority order):
1. Your manual overrides     (confidence: 10)
2. Confirmed in 5+ projects  (confidence: 8-9)
3. Confirmed in 2-4 projects (confidence: 5-7)
4. Discovered once           (confidence: 2-4)
5. Pre-defined in code       (confidence: 1-3)
```

**Your overrides always win!**

---

## Workflow 2: Learn & Improve

This workflow is unchanged but focused:

### Purpose
- Build mapping knowledge
- Curate the database
- Export high-confidence mappings

### Use Cases
- Analyze multiple projects
- Upload template + output pairs
- Review and clean database
- Export for template_converter.py

---

## Benefits of Redesign

### 1. Unified Experience
- **Before**: "Do I use upload or platform workflow?"
- **After**: "Both are the same workflow, just different input!"

### 2. Always Learning
- **Before**: Learning was separate from conversion
- **After**: Every conversion contributes to knowledge

### 3. Review Before Convert
- **Before**: Convert → See problems → Re-convert
- **After**: Review → Override → Convert once, correctly

### 4. Smart Suggestions
- **Before**: Guess based on field names
- **After**: Use path coherence to suggest structurally correct mappings

### 5. Database Growth
- **Before**: Manual mapping updates
- **After**: Automatic learning with every conversion

---

## Technical Implementation

### New Files

**path_coherence.py**
- `PathCoherenceScorer` class
- Parses v1 structure
- Scores v2 candidates
- Ranks by coherence

### Updated Files

**templates/index.html**
- New unified conversion workflow UI
- 4-step process with proper flow
- Mapping review cards with override buttons
- Input method selection cards

**app.py** (pending)
- New `/api/convert-with-review` endpoint
- Accepts mapping overrides
- Saves all mappings to database

### Workflow State Management

```javascript
// Track conversion state
conversionState = {
  step: 1,  // 1-4
  inputMethod: 'upload' | 'platform',
  templateFile: File | null,
  templateId: string | null,
  projectId: string | null,
  learnedMappings: [],
  suggestedMappings: [],
  overrides: {},
  convertedFile: null
}
```

---

## User Journey Example

**Scenario**: Convert PS Template from platform

1. **Click "🔄 Convert Template"**
   - See Step 1: Choose Template Source

2. **Click "☁️ Select from Platform"**
   - Click "Load Templates"
   - See list of v1 templates
   - Select "Professional Services Template V1 (ID: 1822)"

3. **Proceed to Step 2**
   - Enter project ID: "{project_id}"
   - Click "📚 Learn & Continue"
   - System learns 42 mappings
   - Shows progress

4. **Review in Step 3**
   - See 42 suggested mappings
   - Most are green (high confidence)
   - 5 are yellow (medium)
   - 2 are red (low)

   Click on red mapping:
   ```
   v1: =custom_field_abc
   v2: {data.unknown_field}  ← Low confidence

   [Override] → Enter: {project.custom_fields.abc}
   ```

5. **Convert in Step 4**
   - Click "✨ Convert with These Mappings"
   - System applies 42 mappings (including 1 override)
   - Saves all to database

6. **Choose Output**
   - Enter name: "PS Template V2"
   - Click "Upload to ScopeStack"
   - New template created with ID: 6029

7. **Done!**
   - Template on platform
   - All mappings saved
   - Next conversion will be smarter

---

## Summary

The redesigned workflow addresses all your key points:

✅ **Unified conversion** - Upload OR platform in same flow
✅ **Review & override** - See predictions, customize before converting
✅ **Learn as you go** - Every conversion improves the database
✅ **Path coherence** - Smart suggestions maintain structural blocks
✅ **Better UX** - Clear 4-step process with visual feedback

**Next Steps**: Implement the JavaScript functions and API endpoints to bring this design to life!
