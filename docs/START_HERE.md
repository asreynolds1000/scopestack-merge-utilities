# 🚀 START HERE

Welcome to the ScopeStack Template Converter! This tool automates the conversion of Microsoft Word Mail Merge templates to ScopeStack's DocX Templater format.

## ⚡ Quick Start (Choose Your Path)

### Option 1: Web Interface (Recommended) 🌐

**Best for:** Most users, visual interface, drag-and-drop

```bash
# 1. Install dependencies
pip3 install -r requirements.txt

# 2. Start the web server
python3 app.py

# 3. Open your browser
# Navigate to: http://localhost:5001

# 4. Drag and drop your .docx file
# 5. Click "Convert Template"
# 6. Download your converted file
```

**That's it!** See [WEB_INTERFACE.md](WEB_INTERFACE.md) for detailed guide.

---

### Option 2: Command Line 💻

**Best for:** Automation, scripting, batch processing

```bash
# 1. Install dependencies
pip3 install -r requirements.txt

# 2. Convert a template
python3 scopestack_converter.py convert "your_template.docx"

# Done! Converted file is created automatically
```

See [QUICKSTART.md](QUICKSTART.md) for detailed CLI guide.

---

## 📁 What's in This Project?

### Main Tools

| File | What It Does | When to Use |
|------|--------------|-------------|
| `app.py` | Web interface | Most conversions, visual feedback |
| `scopestack_converter.py` | CLI tool | Automation, scripting |
| `template_converter.py` | Conversion engine | Used by both above |
| `merge_data_fetcher.py` | API client | Validation against projects |

### Documentation

| File | What's Inside |
|------|--------------|
| **START_HERE.md** | This file - your starting point |
| **WEB_INTERFACE.md** | Complete web interface guide |
| **QUICKSTART.md** | Quick CLI tutorial |
| **README.md** | Full technical documentation |
| **PROJECT_SUMMARY.md** | Technical architecture overview |
| **WEB_INTERFACE_SUMMARY.md** | Web interface technical details |

### Example Files

| File | Purpose |
|------|---------|
| `sample old merge template.docx` | Example old Mail Merge format |
| `Example Tag template.docx` | Example new DocX Templater format |
| `Example merge data v2.htm` | Sample merge data structure |
| `converted_output.docx` | Example conversion result |

---

## 🎯 Which Tool Should I Use?

### Use Web Interface When:
- ✅ You want visual feedback
- ✅ You're converting one template at a time
- ✅ You prefer drag-and-drop
- ✅ You want to see statistics and analysis
- ✅ You're not comfortable with command line
- ✅ You want to share with team members

### Use CLI Tool When:
- ✅ You're automating conversions
- ✅ You're processing multiple files
- ✅ You're scripting the conversion
- ✅ You prefer command line workflows
- ✅ You're integrating with other tools
- ✅ You don't need a visual interface

**Both use the same conversion engine, so results are identical!**

---

## 🔑 Authentication Setup

Both tools support validation against ScopeStack projects. Set up authentication:

### Option 1: Email/Password
```bash
export SCOPESTACK_EMAIL="your.email@company.com"
export SCOPESTACK_PASSWORD="your_password"
```

### Option 2: Bearer Token
```bash
export SCOPESTACK_TOKEN="your_token_here"
```

---

## 📖 Complete Learning Path

### Beginner Path (30 minutes)

1. **Start with Web Interface** (5 min)
   - Read: [WEB_INTERFACE.md](WEB_INTERFACE.md)
   - Try: Convert `sample old merge template.docx`

2. **Try the CLI** (5 min)
   - Read: [QUICKSTART.md](QUICKSTART.md)
   - Try: `python3 scopestack_converter.py analyze "sample old merge template.docx"`

3. **Set Up Authentication** (10 min)
   - Get your credentials
   - Set environment variables
   - Try validation feature

4. **Convert Your First Real Template** (10 min)
   - Upload your template
   - Review analysis
   - Convert and download
   - Test in ScopeStack

### Advanced Path (1 hour)

1. **Read Technical Docs** (20 min)
   - [README.md](README.md) - Full reference
   - [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) - Architecture

2. **Explore Field Mappings** (20 min)
   - Open `template_converter.py`
   - Review `FIELD_MAPPINGS` dictionary
   - Review `LOOP_CONVERSIONS` dictionary

3. **Add Custom Mappings** (20 min)
   - Identify unmapped fields in your templates
   - Add to conversion dictionaries
   - Test your changes

---

## 🎓 Common Use Cases

### Use Case 1: Convert Client Template
```bash
# Quick way:
python3 scopestack_converter.py convert "client_proposal.docx"

# Or use web interface for visual feedback
```

### Use Case 2: Validate Before Converting
```bash
# CLI:
python3 scopestack_converter.py validate "template.docx" --project 101735

# Web: Use the validation form in the interface
```

### Use Case 3: Batch Convert Multiple Templates
```bash
# Create a simple script:
for file in templates/*.docx; do
    python3 scopestack_converter.py convert "$file"
done
```

### Use Case 4: Check What Fields Are Available
```bash
python3 merge_data_fetcher.py 101735 2 merge_data.json
less merge_data.json
```

---

## ⚠️ Common Issues & Solutions

### "No module named 'flask'" or "No module named 'requests'"
```bash
pip3 install -r requirements.txt
```

### "Port 5000 already in use"
Edit `app.py`, change the last line:
```python
app.run(debug=True, host='0.0.0.0', port=5001)
```

### "No mapping found for field: X"
This is just a warning. You can:
1. Add the mapping to `template_converter.py`
2. Manually fix it in the converted file
3. It might work fine as-is (check in ScopeStack)

### "Authentication failed"
- Check your email and password
- Verify you can log into ScopeStack webapp
- Try using a bearer token instead

---

## 📊 What Gets Converted?

### ✅ Automatically Handled
- Simple fields (26+): `=client_name` → `{project.client_name}`
- Loops (20+): `locations:each(location)` → `{#locations}...{/locations}`
- Conditionals (34+): `field:if(any?)` → `{#field}...{/field}`
- Nested structures
- Complex logic

### ⚠️ May Need Manual Review
- Custom fields specific to your templates
- Very old or unusual Mail Merge patterns
- Fields with special formatting
- Non-standard conditional logic

The tool will warn you about anything it can't automatically convert.

---

## 🎉 Success Checklist

After your first conversion:

- [ ] Uploaded template to ScopeStack
- [ ] Generated a document from a test project
- [ ] Verified all fields render correctly
- [ ] Checked that loops work properly
- [ ] Confirmed conditionals show/hide correctly
- [ ] Reviewed any warnings from converter
- [ ] Added any missing mappings if needed

---

## 🆘 Need Help?

1. **Web Interface Issues**: See [WEB_INTERFACE.md](WEB_INTERFACE.md) → Troubleshooting
2. **CLI Issues**: See [QUICKSTART.md](QUICKSTART.md) → Troubleshooting
3. **Conversion Issues**: See [README.md](README.md) → Common Conversion Patterns
4. **Technical Details**: See [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)

---

## 🎯 Next Steps

1. **Try the Web Interface:**
   ```bash
   python3 app.py
   # Then open http://localhost:5001
   ```

2. **Convert Your First Template:**
   - Use the sample file or your own
   - Review the results
   - Upload to ScopeStack
   - Test with a project

3. **Set Up Authentication:**
   - Export your credentials
   - Try the validation feature
   - See what fields are available

4. **Customize If Needed:**
   - Add your own field mappings
   - Extend the conversion logic
   - Share with your team

---

## 📈 Time Savings

- **Manual conversion**: ~30 minutes per template
- **With this tool**: ~40 seconds per template
- **Savings**: 98% faster! ⚡

---

## 🎊 That's It!

You're ready to start converting templates. Pick your preferred method (web or CLI) and get started!

**Recommended first step:** Start with the web interface - it's the easiest way to see everything in action.

```bash
python3 app.py
```

Then open your browser and start converting! 🚀
