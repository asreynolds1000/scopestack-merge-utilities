# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**ScopeStack Merge Data and Document Utility**: Tools for working with ScopeStack merge data and document templates. Provides a Flask web interface with multiple tools and a CLI.

| | |
|---|---|
| **GitHub** | `asreynolds1000/scopestack-merge-utilities` (private) |
| **Deploy** | Railway (auto-deploys on push to main) |

## URL Structure

| Route | Page | Description |
|-------|------|-------------|
| `/` | Homepage | Tool cards linking to Converter and Data Viewer |
| `/converter` | Template Converter | Convert v1 templates to v2, AI improvements, learn mappings |
| `/data-viewer` | Merge Data Viewer | Browse v1/v2 merge data with Miller Columns UI |
| `/merge-data-viewer` | Redirect (301) | Backwards compatibility redirect to `/data-viewer` |
| `/login` | Login Page | ScopeStack SSO login (shown when unauthenticated) |

## Commands

```bash
# Install dependencies
pip3 install -r requirements.txt

# Run web interface (opens at http://127.0.0.1:5001)
python3 app.py

# CLI: Convert a template
python3 scopestack_converter.py convert "template.docx" -o "output.docx"

# CLI: Analyze template structure
python3 scopestack_converter.py analyze "template.docx"

# CLI: Validate against live project
python3 scopestack_converter.py validate "template.docx" --project 101735

# Authentication management
python3 auth_manager.py login    # Store credentials
python3 auth_manager.py status   # Check auth state
python3 auth_manager.py logout   # Clear tokens
```

## Architecture

### Entry Points
- **`app.py`** - Flask web server with drag-and-drop UI, validation, and learning features
- **`scopestack_converter.py`** - CLI tool for command-line automation

### Core Conversion Engine
- **`template_converter.py`** - Main conversion logic with `FIELD_MAPPINGS`, `LOOP_CONVERSIONS`, and `CONDITIONAL_CONVERSIONS` dicts. Parses .docx XML and replaces Mail Merge fields with DocX Templater syntax.

### ScopeStack Integration
- **`merge_data_fetcher.py`** - API client that authenticates with ScopeStack OAuth2 and fetches merge data for validation
- **`auth_manager.py`** - OAuth2 token management with persistent storage in `~/.scopestack/tokens.json`

### Learning System
- **`mapping_database.py`** - Stores learned field mappings in `learned_mappings_db.json`
- **`learn_mappings.py`** - Learns new mappings by comparing templates with live project data
- **`conversion_learner.py`** - Tracks conversion improvements across sessions

### Supporting Modules
- **`template_validator.py`** - Validates converted templates against live project data
- **`session_manager.py`** - Tracks conversion sessions in `~/.scopestack/sessions/`
- **`data_structure_extractor.py`** - Extracts field structure from merge data JSON
- **`smart_converter.py`** - AI-driven smart conversion (used by `/api/smart-convert`)
- **`path_coherence.py`** - Path scoring for field mapping suggestions

### CLI Utilities
- **`diagnose_mergefields.py`** - Standalone diagnostic tool for inspecting Mail Merge fields in .docx files

## Key Patterns

### Field Conversion Format
```python
# Simple fields
'=client_name' → '{project.client_name}'

# Within loops (context-relative)
'=location.name' → '{name}'

# Loops
'locations:each(location)' → '{#locations}...{/locations}'

# Conditionals
'field:if(any?)' → '{#field}...{/field}'
'field:if(blank?)' → '{^field}...{/field}'
```

### Adding New Mappings
Edit `template_converter.py` and add to the appropriate dict:
- `FIELD_MAPPINGS` for simple field replacements
- `LOOP_CONVERSIONS` for loop structures
- `CONDITIONAL_CONVERSIONS` for conditional blocks

## Environment Variables

Required for ScopeStack API authentication:
```bash
SCOPESTACK_CLIENT_ID=your_client_id
SCOPESTACK_CLIENT_SECRET=your_client_secret
```

Optional:
```bash
SECRET_KEY=your_flask_secret_key  # For production Flask sessions
```

## Data Storage

- **Auth tokens**: `~/.scopestack/tokens.json`
- **Learned mappings**: `./learned_mappings_db.json`
- **Session cache**: `./document_cache/`
- **Temp files**: `./temp/`

## Deployment (Railway)

The app is configured for Railway deployment with:
- `Procfile` - Runs gunicorn on the `$PORT` environment variable
- `runtime.txt` - Specifies Python 3.11.7

### Railway CLI Commands
```bash
# Check deployment status
railway status

# View deployment logs
railway logs

# Deploy manually (auto-deploys on git push)
railway up

# Set environment variables
railway variables set KEY=value

# Open deployed app
railway open
```

### Required Environment Variables
```bash
SCOPESTACK_CLIENT_ID=your_client_id
SCOPESTACK_CLIENT_SECRET=your_client_secret
SECRET_KEY=random_secret_for_flask_sessions
OAUTH_REDIRECT_URI=https://your-domain.com/oauth/callback  # Required for production
```

### Authentication
All routes require ScopeStack SSO authentication except:
- `/login` - Login page shown to unauthenticated users
- `/oauth/authorize` - Initiates OAuth flow
- `/oauth/callback` - OAuth callback handler
- `/api/auth/status` - Auth status check for frontend

Unauthenticated users are automatically redirected to `/login`, then back to their original destination after successful OAuth.

## Testing

```bash
# Install dev dependencies
pip3 install -r requirements-dev.txt

# Run tests
pytest

# Run tests with coverage
pytest --cov=. --cov-report=term-missing

# Run E2E tests (requires app running)
RUN_E2E_TESTS=1 pytest tests/test_e2e_data_viewer.py -v
```

## Template Architecture

Uses Jinja2 template inheritance with shared components:

```
templates/
├── base.html                    # Base template with common CSS/JS, auth
├── login.html                   # Standalone login page (SSO only)
├── components/
│   ├── auth_bar.html           # Nav links, auth status, settings button
│   ├── login_modal.html        # SSO login modal
│   └── settings_modal.html     # Auth + AI config + Debug console
├── home.html                   # Homepage with tool cards
├── converter.html              # Template Converter (extends base)
├── data_viewer.html            # Merge Data Viewer (extends base)
└── oauth_error.html            # OAuth error page
```

**Template inheritance pattern:**
```jinja2
{% extends 'base.html' %}
{% block title %}Page Title{% endblock %}
{% block extra_styles %}/* page CSS */{% endblock %}
{% block content %}<!-- page HTML -->{% endblock %}
{% block scripts %}<!-- page JS -->{% endblock %}
```

**Active page indicator:** Pass `active_page` to templates:
```python
render_template('converter.html', active_page='converter')
```

## Data Viewer Patterns

The Merge Data Viewer (`/data-viewer`) uses React (via CDN) with a Miller Columns UI.

### Array Handling
- `DataStructureExtractor` only extracts `[0]` as a template for arrays
- `array_count` field tells the frontend how many items actually exist
- Frontend dynamically generates paths for items `[1]`, `[2]`, etc. using `array_count`
- **Critical**: When selecting dynamically generated items, store `selectedData` in React state instead of deriving it from `structure[path]` (since paths like `[5]` don't exist in structure)

### Collapsible Detail Panel
- Detail panel is a floating overlay that slides in from the right
- Opens automatically when clicking any item
- Close with X button; stays open while navigating until explicitly closed
- State: `detailPanelOpen` controls visibility, `selectedData` stores item data

### OAuth SSO
- Uses Authorization Code Flow with PKCE
- `OAUTH_REDIRECT_URI` must be explicitly set in production (Railway terminates SSL, so auto-detection gets `http://`)
- `SECRET_KEY` required for Flask sessions to persist PKCE state across redirect

## Recent Learnings

### State Management in Data Viewer (2026-01-21)
When clicking on dynamically generated array items (index > 0), the detail pane didn't appear because `selectedData` was derived from `structure[selectedPath]`, but only `[0]` entries exist in the structure. Fixed by storing `selectedData` directly in state when items are clicked.

### OAuth Redirect URI (2026-01-21)
Railway terminates SSL at the load balancer, so `request.host_url` returns `http://` instead of `https://`. Always set `OAUTH_REDIRECT_URI` explicitly with the `https://` scheme for production deployments.

### App Restructuring (2026-01-21)
Restructured app with new homepage and template inheritance:
- Homepage at `/` with tool cards for Converter and Data Viewer
- Converter moved to `/converter`, Data Viewer to `/data-viewer`
- Shared components extracted: auth_bar, login_modal, settings_modal
- Base template (`base.html`) with common CSS, JS, and auth handling
- 301 redirect from `/merge-data-viewer` to `/data-viewer` for backwards compatibility

### Codebase Cleanup (2026-01-21)
- Archived old planning docs to `docs/archive/` (MAIN_PLAN.md, COMPLETE_WORKFLOW.md, etc.)
- Removed unused experimental files (improved_field_replacer.py, template_learning_workflow.py)
- Fixed port references in docs (5000 → 5001)

### Auth Simplification (2026-01-22)
- Removed dual auth (Basic Auth + OAuth) in favor of ScopeStack SSO only
- Unauthenticated users see `/login` page, then redirect to destination after OAuth
- Removed email/password login option - SSO is the only auth method
- Replaced "Full Data" checkbox with dropdown select for better UX (page reload is more expected)
