# ScopeStack Template Converter

Automates the conversion of Microsoft Word Mail Merge templates to ScopeStack's DocX Templater format.

## 🚀 Quick Start

### Web Interface (Recommended)
```bash
python3 app.py
```
Then open: **http://127.0.0.1:5001**

### Command Line
```bash
python3 scopestack_converter.py convert "your_template.docx"
```

## 📁 Project Structure

```
ScopeStack-doc-converter/
├── app.py                      # Web server
├── scopestack_converter.py     # CLI tool
├── template_converter.py       # Conversion engine
├── merge_data_fetcher.py       # API client
├── auth_manager.py             # OAuth2 authentication
├── requirements.txt            # Dependencies
├── templates/                  # Web UI templates
│   └── index.html
├── docs/                       # Documentation
│   ├── START_HERE.md          # 👈 Start here!
│   ├── WEB_INTERFACE.md       # Web guide
│   ├── QUICKSTART.md          # CLI guide
│   ├── AUTHENTICATION.md      # Auth guide
│   ├── FEATURES_OVERVIEW.md   # Complete features
│   ├── PROJECT_SUMMARY.md     # Architecture
│   └── WEB_INTERFACE_SUMMARY.md
├── examples/                   # Example files
│   ├── sample old merge template.docx
│   ├── Example Tag template.docx
│   ├── converted_output.docx
│   └── Example merge data v2.htm
└── temp/                       # Temporary files
```

## 📖 Documentation

**New to the project?** Read [docs/START_HERE.md](docs/START_HERE.md)

**Using web interface?** See [docs/WEB_INTERFACE.md](docs/WEB_INTERFACE.md)

**Using command line?** See [docs/QUICKSTART.md](docs/QUICKSTART.md)

**Authentication setup?** See [docs/AUTHENTICATION.md](docs/AUTHENTICATION.md)

**Want full details?** See [docs/FEATURES_OVERVIEW.md](docs/FEATURES_OVERVIEW.md)

## ⚡ Features

- ✅ **Web Interface** - Beautiful drag-and-drop UI
- ✅ **CLI Tool** - Command-line automation
- ✅ **Fast Conversion** - 40 seconds vs 30 minutes manually
- ✅ **Live Validation** - Check against ScopeStack projects
- ✅ **Persistent Auth** - Login once, stay authenticated with OAuth2
- ✅ **Auto Token Refresh** - Seamless authentication across sessions
- ✅ **127+ Field Mappings** - Comprehensive automatic conversion

## 🔧 Installation

```bash
pip3 install -r requirements.txt
```

## 🎯 Usage Examples

### Web Interface
```bash
python3 app.py
# Open http://127.0.0.1:5001
# Drag & drop file → Convert → Download
```

### Analyze Template
```bash
python3 scopestack_converter.py analyze "examples/sample old merge template.docx"
```

### Convert Template
```bash
python3 scopestack_converter.py convert "examples/sample old merge template.docx"
```

### Validate Against Project
```bash
export SCOPESTACK_EMAIL="your@email.com"
export SCOPESTACK_PASSWORD="password"
python3 scopestack_converter.py validate "template.docx" --project 101735
```

## 🔐 Authentication

**New! Persistent Authentication** - Login once and stay authenticated across sessions.

### Web Interface
1. Click **"Login"** in the authentication bar
2. Enter your ScopeStack email and password
3. Tokens are automatically stored and refreshed

### CLI Tool
```bash
# Login (stores tokens in ~/.scopestack/tokens.json)
python3 auth_manager.py login

# Check authentication status
python3 auth_manager.py status

# Logout
python3 auth_manager.py logout
```

**Benefits:**
- No need to re-enter credentials for each validation
- Automatic token refresh
- Secure OAuth2 implementation

See [docs/AUTHENTICATION.md](docs/AUTHENTICATION.md) for complete guide.

## 📊 Conversion Examples

**Simple fields:**
```
=client_name  →  {project.client_name}
```

**Loops:**
```
locations:each(location)  →  {#locations}
  =location.name             {name}
locations:endEach          →  {/locations}
```

**Conditionals:**
```
field:if(any?)  →  {#field}
field:endIf     →  {/field}
```

## 🆘 Troubleshooting

**Port 5000 already in use?**
- App now uses port 5001 (already configured)
- Open: http://127.0.0.1:5001

**Connection refused?**
- Make sure server is running: `python3 app.py`
- Check terminal for errors

**Module not found?**
- Install dependencies: `pip3 install -r requirements.txt`

## 📞 Support

See the [docs/](docs/) folder for comprehensive guides on every aspect of the tool.

---

Built with ❤️ for easier ScopeStack template management
