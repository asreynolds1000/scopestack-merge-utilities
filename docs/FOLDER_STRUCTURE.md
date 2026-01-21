# 📁 Folder Structure Guide

## Overview

```
ScopeStack-doc-converter/
├── 📄 Core Files (in root)
├── 📂 docs/         - All documentation
├── 📂 examples/     - Sample templates and outputs
├── 📂 templates/    - Web UI HTML templates
└── 📂 temp/         - Temporary/extracted files
```

## 📄 Root Files

### Main Applications
- **`app.py`** - Web server (run this for web interface)
- **`scopestack_converter.py`** - CLI tool (run this for command line)

### Core Modules
- **`template_converter.py`** - Conversion engine (used by both apps)
- **`merge_data_fetcher.py`** - API client for ScopeStack

### Configuration
- **`requirements.txt`** - Python dependencies
- **`README.md`** - Quick reference guide
- **`.gitignore`** - Git ignore rules

## 📂 docs/

All documentation organized in one place:

| File | Purpose | When to Read |
|------|---------|--------------|
| **START_HERE.md** | Entry point, quickstart guide | First time using |
| **WEB_INTERFACE.md** | Complete web UI guide | Using web interface |
| **QUICKSTART.md** | CLI quick tutorial | Using command line |
| **FEATURES_OVERVIEW.md** | All features explained | Want to see capabilities |
| **PROJECT_SUMMARY.md** | Technical architecture | Understanding internals |
| **WEB_INTERFACE_SUMMARY.md** | Web UI technical details | Building/extending UI |
| **FOLDER_STRUCTURE.md** | This file | Understanding organization |

### Reading Order

**For New Users:**
1. START_HERE.md (5 min)
2. WEB_INTERFACE.md or QUICKSTART.md (10 min)
3. FEATURES_OVERVIEW.md (optional, 15 min)

**For Developers:**
1. PROJECT_SUMMARY.md (20 min)
2. WEB_INTERFACE_SUMMARY.md (15 min)
3. Source code files

## 📂 examples/

Sample files to help you understand the conversion:

### Templates
- **`sample old merge template.docx`** - Example old Mail Merge format
- **`Example Tag template.docx`** - Example new DocX Templater format
- **`converted_output.docx`** - Example conversion result

### Merge Data
- **`Example merge data v2.htm`** - Saved merge data from project
- **`Example merge data v2_files/`** - Assets for the HTML
- **`Example merge data v1.htm`** - Old version (for reference)
- **`Example merge data v1_files/`** - Assets for v1

### Usage
Use these files to:
- Test the converter with known inputs
- Compare before/after formats
- Learn the field mappings
- Validate your setup

## 📂 templates/

Flask web interface HTML templates:

- **`index.html`** - Main web interface (500+ lines)

This is where the beautiful purple gradient UI lives!

**Modify this file if you want to:**
- Change the UI design
- Add new features to web interface
- Customize colors/layout
- Add new sections

## 📂 temp/

Temporary and extracted files:

- **`old_template_extracted/`** - Extracted XML from old templates
- **`new_template_extracted/`** - Extracted XML from new templates
- **`.gitkeep`** - Keeps folder in git

**Note:** These folders are created during analysis. You can safely delete them - they'll be recreated as needed.

The web interface also creates temporary files here during upload/conversion.

## 🗂️ File Organization Benefits

### Before Organization
```
❌ 25+ files in root folder
❌ Hard to find documentation
❌ Examples mixed with source code
❌ Temp files cluttering view
```

### After Organization
```
✅ 8 files in root (core files only)
✅ All docs in docs/ folder
✅ All examples in examples/ folder
✅ Clean, professional structure
✅ Easy to navigate
```

## 📍 Where to Find Things

### "Where do I start?"
→ `README.md` (root) or `docs/START_HERE.md`

### "How do I use the web interface?"
→ `docs/WEB_INTERFACE.md`

### "How do I use command line?"
→ `docs/QUICKSTART.md`

### "What can this tool do?"
→ `docs/FEATURES_OVERVIEW.md`

### "How does it work internally?"
→ `docs/PROJECT_SUMMARY.md`

### "Where are example files?"
→ `examples/` folder

### "Where's the source code?"
→ Root folder: `app.py`, `template_converter.py`, etc.

### "Where's the web UI code?"
→ `templates/index.html`

## 🔄 Workflow: Where Files Are Used

### Web Interface Workflow
```
User browser
    ↓
templates/index.html (UI)
    ↓
app.py (server)
    ↓
template_converter.py (conversion)
    ↓
merge_data_fetcher.py (validation)
    ↓
temp/ (temporary files)
    ↓
Download to user
```

### CLI Workflow
```
Terminal
    ↓
scopestack_converter.py (CLI)
    ↓
template_converter.py (conversion)
    ↓
merge_data_fetcher.py (validation)
    ↓
Output file created
```

## 🧹 Maintenance

### Safe to Delete
- `temp/` contents (will be recreated)
- Any `*.docx.tmp` files
- `__pycache__/` folders

### Don't Delete
- Any `.py` files in root
- `templates/` folder
- `requirements.txt`
- `docs/` folder (unless you have them elsewhere)
- `examples/` folder (unless you don't need them)

### Clean Up Command
```bash
cd /path/to/ScopeStack-doc-converter
rm -rf temp/* __pycache__ *.tmp .DS_Store
```

## 📦 For Version Control (Git)

The `.gitignore` file is configured to:
- ✅ Include all source code
- ✅ Include all documentation
- ✅ Include example files
- ❌ Exclude temporary files
- ❌ Exclude Python cache
- ❌ Exclude OS files (.DS_Store)

## 🎯 Quick Reference

| Need | Location |
|------|----------|
| Start web server | Run `app.py` in root |
| Start CLI tool | Run `scopestack_converter.py` in root |
| Read docs | `docs/START_HERE.md` |
| See examples | `examples/` folder |
| Modify UI | `templates/index.html` |
| Add field mappings | `template_converter.py` |
| Change port | Edit `app.py` line 272 |

## 🎉 Summary

Your project is now organized into a clean, professional structure:

- **Root folder** = Essential files only
- **docs/** = All documentation in one place
- **examples/** = Sample files for testing
- **templates/** = Web UI code
- **temp/** = Temporary working files

This makes it easy to:
- Find what you need quickly
- Share with team members
- Maintain and extend
- Deploy to production
- Version control with git

Enjoy your organized project! 🚀
