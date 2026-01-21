# Web Interface Guide

## Starting the Web Server

1. **Install dependencies:**
   ```bash
   pip3 install -r requirements.txt
   ```

2. **Start the server:**
   ```bash
   python3 app.py
   ```

3. **Open your browser:**
   Navigate to: `http://localhost:5000`

## Using the Web Interface

### Step 1: Upload Your Template

1. Drag and drop your `.docx` file onto the upload area, or click to browse
2. Wait for the file to upload and be analyzed (usually takes 1-2 seconds)
3. Review the analysis results showing:
   - Total fields found
   - Simple fields count
   - Loop fields count
   - Conditional fields count

### Step 2: Review Field Details

Click through the tabs to see:
- **Simple Fields**: Basic merge fields like `=client_name`
- **Loops**: Iteration structures like `locations:each(location)`
- **Conditionals**: Logic fields like `executive_summary:if(any?)`

### Step 3: Convert or Validate

**Option A: Convert Immediately**
- Click "Convert Template" to convert right away
- Wait for conversion to complete (1-2 seconds)
- Download your converted template

**Option B: Validate First (Optional)**
1. Click "Validate Against Project"
2. Enter your ScopeStack project ID
3. Enter your email and password
4. Click "Run Validation"
5. Review the coverage results:
   - Green bar shows % of fields that exist in project
   - See which fields are valid
   - See which fields are missing (need to be added or remapped)
6. After validation, click "Convert Template"

### Step 4: Download

1. Click "Download Converted Template"
2. Save the file to your computer
3. Upload to ScopeStack and test
4. Click "Convert Another Template" to start over

## Features

### 🎨 Beautiful Modern UI
- Clean, gradient design
- Drag-and-drop file upload
- Responsive layout
- Real-time progress indicators

### 📊 Detailed Analysis
- Statistics dashboard
- Field categorization
- Browse all detected fields
- Easy-to-read display

### ✅ Live Validation
- Validate against actual projects
- OAuth2 authentication
- See coverage percentage
- Identify missing fields

### ⚠️ Warning Display
- Shows unmapped fields
- Clear warning messages
- Easy to identify what needs attention

### 🔄 Easy Workflow
- Step-by-step process
- Progress tracking
- One-click conversion
- Instant download

## Security Notes

- Your credentials are only used for API authentication
- No data is stored permanently on the server
- Files are automatically cleaned up
- All communication uses secure sessions

## Troubleshooting

### Port Already in Use

If port 5000 is already taken:
```bash
# Edit app.py and change the port on the last line:
app.run(debug=True, host='0.0.0.0', port=5001)
```

### Upload Fails

- Make sure the file is a valid `.docx` file
- Check file size is under 16MB
- Ensure file isn't password protected

### Validation Fails

- Verify your email and password are correct
- Check the project ID exists and you have access
- Make sure you have an internet connection
- Try authenticating directly in ScopeStack webapp first

### Conversion Warnings

Warnings indicate fields that couldn't be automatically mapped:
- Review the list in the download section
- Add mappings to `template_converter.py` if needed
- Or manually fix in the output document

## Tips

1. **Start with a small test file** to get familiar with the interface
2. **Use validation** before converting to catch issues early
3. **Review warnings carefully** - they indicate fields that may need manual attention
4. **Keep the browser tab open** while converting (don't navigate away)
5. **Download immediately** after conversion - files are cleaned up after some time

## Comparison: CLI vs Web Interface

| Feature | CLI | Web Interface |
|---------|-----|---------------|
| Ease of use | Command line knowledge needed | Point and click |
| File upload | Manual path specification | Drag and drop |
| Analysis view | Text output | Visual dashboard |
| Progress tracking | Command output | Progress bars |
| Validation | Command line flags | Form-based |
| Download | Automatic save | Download button |
| Best for | Automation, scripts, power users | One-off conversions, visual feedback |

## API Endpoints

The web interface uses these endpoints (for advanced users):

- `POST /api/upload` - Upload and analyze template
- `POST /api/convert` - Convert uploaded template
- `GET /api/download` - Download converted file
- `POST /api/validate` - Validate against project
- `POST /api/fetch-merge-data` - Fetch merge data
- `POST /api/cleanup` - Clean up temporary files

## Running in Production

For production deployment:

1. **Set a secure secret key:**
   ```bash
   export SECRET_KEY='your-random-secret-key-here'
   ```

2. **Use a production WSGI server:**
   ```bash
   pip3 install gunicorn
   gunicorn -w 4 -b 0.0.0.0:5000 app:app
   ```

3. **Add HTTPS** using nginx or Apache as a reverse proxy

4. **Set up file cleanup** to remove old temporary files regularly

## Screenshots

### Main Interface
Beautiful gradient design with drag-and-drop upload area

### Analysis Dashboard
Visual statistics showing field counts and types

### Field Browser
Tabbed interface to browse all detected fields

### Validation Results
Green progress bar showing coverage percentage

### Download Section
One-click download with warning display

## Next Steps

- Try converting your first template
- Experiment with validation
- Review the warnings and add custom mappings
- Share the URL with your team members

Enjoy the streamlined conversion experience! 🎉
