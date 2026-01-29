# ScopeStack Merge Utilities

Official tools for working with ScopeStack merge data and document templates. Developed and maintained by [ScopeStack](https://scopestack.io).

**Features:**
- **Template Converter** - Convert Mail Merge templates to DocX Templater format
- **Merge Data Viewer** - Browse and explore merge data with a Miller Columns UI

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
scopestack-merge-utilities/
├── app.py                      # Web server
├── scopestack_converter.py     # CLI tool
├── template_converter.py       # Conversion engine
├── merge_data_fetcher.py       # API client
├── auth_manager.py             # OAuth2 authentication
├── requirements.txt            # Dependencies
├── templates/                  # Web UI templates
└── docs/                       # Documentation
    ├── START_HERE.md          # 👈 Start here!
    ├── QUICKSTART.md          # CLI guide
    └── AUTHENTICATION.md      # Auth guide
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
python3 scopestack_converter.py validate "template.docx" --project {project_id}
```

## 🔐 Authentication

Uses **ScopeStack SSO** (OAuth2 with PKCE) for secure authentication.

### Web Interface
1. Click **"Login with ScopeStack"**
2. Authenticate via ScopeStack SSO
3. Tokens are stored in your browser session

### CLI Tool
```bash
# Login via OAuth (opens browser)
python3 auth_manager.py login

# Check authentication status
python3 auth_manager.py status

# Logout
python3 auth_manager.py logout
```

### Environment Variables

Required for ScopeStack API access:
```bash
SCOPESTACK_CLIENT_ID=your_client_id
SCOPESTACK_CLIENT_SECRET=your_client_secret
```

For production deployments:
```bash
SECRET_KEY=random_secret_for_flask_sessions
OAUTH_REDIRECT_URI=https://your-domain.com/oauth/callback
```

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

For ScopeStack platform support, contact [support@scopestack.io](mailto:support@scopestack.io).

---

## License

This software is provided by ScopeStack and subject to the [Terms of Service](https://scopestack.io/terms), [Professional Services Agreement](https://scopestack.io/professional-services-agreement), and [Data Processing Addendum](https://scopestack.io/data-processing-addendum).

© 2026 ScopeStack
