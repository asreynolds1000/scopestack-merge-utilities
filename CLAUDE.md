# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ScopeStack Template Converter: Converts Microsoft Word Mail Merge templates to ScopeStack's DocX Templater format. Provides both a Flask web interface and CLI tool.

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

## Deployment (Railway/Render)

The app is configured for deployment with:
- `Procfile` - Runs gunicorn on the `$PORT` environment variable
- `runtime.txt` - Specifies Python 3.11.7

### Required Environment Variables
```bash
SCOPESTACK_CLIENT_ID=your_client_id
SCOPESTACK_CLIENT_SECRET=your_client_secret
SECRET_KEY=random_secret_for_flask_sessions
APP_PASSWORD=password_for_basic_auth  # Username is "admin"
```

### Basic Auth
When `APP_PASSWORD` is set, all routes require HTTP Basic Auth:
- Username: `admin`
- Password: value of `APP_PASSWORD`

If `APP_PASSWORD` is not set, no authentication is required (local development mode).
