# UI Organization - Reorganized Workflows

## Problem Statement

The previous UI had become cluttered with three overlapping sections that weren't clearly differentiated:

1. **"Step 1: Upload Template"** - Upload local file → convert → download
2. **"Learn Field Mappings"** - Two tabs for learning (confusing purpose)
3. **"🔄 Complete Template Workflow"** - Full platform integration

**Issues**:
- Not clear which workflow to use for which purpose
- Redundancy between sections
- Confusing which features did what
- Too much visible at once

## New Organization

### Workflow Selector (Always Visible)

A prominent card at the top with three clear workflow options:

```
┌─────────────────────────────────────────────────────────────┐
│              Choose Your Workflow                            │
├──────────────────┬──────────────────┬────────────────────────┤
│ 🔄 Quick         │ 🚀 Production    │ 🎓 Learn Mappings     │
│ Conversion       │ Migration        │                        │
│                  │                  │                        │
│ Upload a local   │ Migrate template │ Discover mappings     │
│ v1 template and  │ from platform:   │ from projects to      │
│ convert to v2    │ download → learn │ improve conversion    │
│                  │ → convert →      │                        │
│                  │ upload           │                        │
└──────────────────┴──────────────────┴────────────────────────┘
```

### Three Distinct Workflows

Only ONE workflow is visible at a time. User clicks a card to show that workflow.

---

## Workflow 1: 🔄 Quick Conversion

**Purpose**: Simple, fast conversion of a local v1 template

**Use Case**:
- You have a v1 template file on your computer
- You want to convert it to v2 format quickly
- You don't need platform integration

**Process**:
1. Upload .docx file (drag & drop or browse)
2. System analyzes and shows field structure
3. Optional: Validate against a project
4. Click "Convert Template"
5. Download converted v2 template

**When to use**:
- Quick local testing
- Converting templates not yet on the platform
- Experimentation with field mappings
- When you just need the converted file

**Features**:
- Drag & drop upload
- Field analysis preview
- Optional validation
- Immediate download

---

## Workflow 2: 🚀 Production Migration

**Purpose**: Complete end-to-end migration from platform

**Use Case**:
- You have a v1 template already on ScopeStack
- You want to migrate it to v2 on the platform
- You want automatic learning and upload

**Process**:
1. Click "Load Templates" to fetch from platform
2. Select a v1 template from dropdown
3. Enter project ID for learning mappings
4. Enter name for new v2 template
5. Click "Run Complete Workflow"
6. System automatically:
   - Downloads v1 template
   - Learns mappings from project
   - Converts to v2
   - Uploads back to platform
7. Get new template ID to test

**When to use**:
- Migrating production templates
- Need automated learning from real data
- Want to test on platform immediately
- Full deployment workflow

**Features**:
- Template browser (loads from platform)
- Automatic mapping learning
- One-click complete workflow
- Returns template ID for testing
- Real-time progress console
- Template starts as inactive (safe)

---

## Workflow 3: 🎓 Learn Mappings

**Purpose**: Discover and improve field mappings

**Use Case**:
- You want to discover how v1 fields map to v2 fields
- You want to improve the mapping database
- You're analyzing templates before conversion

**Process**:

**Option A: From Project Data**
1. Enter project ID
2. Click "Discover Mappings"
3. System fetches v1 and v2 merge data
4. Matches values to discover mappings
5. Saves to database

**Option B: From Documents**
1. Upload v1 template
2. Upload generated output document
3. Enter project ID
4. Click "Upload & Learn"
5. System:
   - Extracts fields from template
   - Extracts values from output
   - Fetches merge data from API
   - Matches everything together
6. Saves confirmed mappings to database

**When to use**:
- Building mapping knowledge
- Analyzing complex templates
- Improving conversion quality
- Contributing to mapping database

**Features**:
- Two learning approaches (API vs Documents)
- Persistent database with confidence scores
- Shows high/medium/low confidence mappings
- Export capability
- Statistics tracking

---

## Comparison Table

| Feature | Quick Conversion | Production Migration | Learn Mappings |
|---------|------------------|---------------------|----------------|
| **Input** | Local file | Template ID from platform | Project ID or Documents |
| **Output** | Downloaded file | Template on platform | Mapping database |
| **Learning** | Uses existing mappings | Auto-learns from project | Focused on learning |
| **Upload** | No | Yes (automatic) | No |
| **Speed** | ~5 seconds | ~30 seconds | ~10-20 seconds |
| **Auth Required** | No (for basic) | Yes | Yes |
| **Best For** | Quick tests | Production deployment | Research & improvement |

---

## Navigation Flow

```
User visits page
    ↓
Sees "Choose Your Workflow" selector
    ↓
Clicks one of three workflow cards
    ↓
Selected workflow section appears
    ↓
Other workflows hidden
    ↓
User completes their task
    ↓
Can click different workflow card to switch
```

---

## Key Improvements

### 1. Clear Purpose
Each workflow has a distinct, obvious purpose:
- **Convert** = I have a file, make it v2
- **Migrate** = Move my platform template to v2
- **Learn** = Discover/improve mappings

### 2. No Redundancy
- Removed overlap between sections
- Each feature appears in only ONE workflow
- Clear boundaries

### 3. Progressive Disclosure
- Only show what user needs for current task
- Less overwhelming
- Focused experience

### 4. Visual Clarity
- Workflow selector uses gradient background (stands out)
- Each card has icon, title, description
- Hover effects for interactivity
- Smooth transitions when switching

### 5. Appropriate Complexity
- **Quick Conversion**: Simplest (just upload & convert)
- **Production Migration**: Most automated (one-click full workflow)
- **Learn Mappings**: Most detailed (two sub-options for power users)

---

## Technical Implementation

### HTML Structure
```html
<!-- Workflow Selector (always visible) -->
<div class="card" style="background: gradient...">
  <div onclick="showWorkflow('convert')">Quick Conversion</div>
  <div onclick="showWorkflow('migrate')">Production Migration</div>
  <div onclick="showWorkflow('learn')">Learn Mappings</div>
</div>

<!-- Workflow 1: Quick Conversion -->
<div class="workflow-section" id="convertWorkflow">
  <!-- Upload, convert, download -->
</div>

<!-- Workflow 2: Production Migration -->
<div class="workflow-section" id="migrateWorkflow" style="display: none;">
  <!-- Template browser, complete workflow -->
</div>

<!-- Workflow 3: Learn Mappings -->
<div class="workflow-section" id="learnWorkflow" style="display: none;">
  <!-- Learning tabs -->
</div>
```

### JavaScript
```javascript
function showWorkflow(workflow) {
  // Hide all workflows
  document.querySelectorAll('.workflow-section').forEach(section => {
    section.style.display = 'none';
  });

  // Show selected workflow
  document.getElementById(workflowId).style.display = 'block';

  // Smooth scroll to section
  document.getElementById(workflowId).scrollIntoView({
    behavior: 'smooth'
  });
}
```

### CSS
```css
.workflow-section {
  display: none;  /* Hidden by default */
}

.workflow-section.active {
  display: block;  /* Show when active */
}
```

---

## User Experience Benefits

### Before
- User sees three sections, unclear which to use
- "Do I upload or use the template workflow?"
- "What's the difference between the learning tabs?"
- Information overload

### After
- User sees clear workflow selector
- Reads three distinct purposes
- Clicks the one that matches their goal
- Focused interface for that task
- Can easily switch if they change their mind

---

## Migration Guide (for users)

### If you previously used "Step 1: Upload Template"
→ Use **🔄 Quick Conversion** workflow

### If you previously used "Complete Template Workflow"
→ Use **🚀 Production Migration** workflow

### If you previously used "Learn Field Mappings"
→ Use **🎓 Learn Mappings** workflow
- "From Project Data" tab → same as before
- "From Documents" tab → same as before

---

## Default Behavior

When page loads:
1. Workflow selector is visible
2. **Quick Conversion** is shown by default (most common use case)
3. Other workflows are hidden
4. User can switch at any time by clicking selector cards

This gives a clean, focused initial experience while keeping all power features one click away.
