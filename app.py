#!/usr/bin/env python3
"""
ScopeStack Template Converter - Web Interface
Flask-based web UI for easy template conversion
"""

from flask import Flask, render_template, request, send_file, jsonify, session, Response
from werkzeug.utils import secure_filename
from typing import Dict, List, Optional
from functools import wraps
import os
import tempfile
import json
import requests
from pathlib import Path
from datetime import datetime

from template_converter import TemplateConverter, MailMergeParser
from merge_data_fetcher import MergeDataFetcher
from auth_manager import AuthManager
from mapping_database import MappingDatabase
from template_manager import TemplateManager
from session_manager import SessionManager
from template_validator import TemplateValidator

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB max file size
app.config['UPLOAD_FOLDER'] = tempfile.gettempdir()

ALLOWED_EXTENSIONS = {'docx'}

# Basic Authentication
def check_auth(username, password):
    """Check if username/password combination is valid"""
    app_password = os.environ.get('APP_PASSWORD')
    if not app_password:
        # No password set = no auth required (local development)
        return True
    return username == 'admin' and password == app_password

def authenticate():
    """Send a 401 response that enables basic auth"""
    return Response(
        'Login required. Please authenticate.', 401,
        {'WWW-Authenticate': 'Basic realm="ScopeStack Template Converter"'}
    )

@app.before_request
def require_auth():
    """Require authentication for all requests if APP_PASSWORD is set"""
    if not os.environ.get('APP_PASSWORD'):
        return  # No auth required in development
    auth = request.authorization
    if not auth or not check_auth(auth.username, auth.password):
        return authenticate()

# Global instances
auth_manager = AuthManager()
mapping_db = MappingDatabase()
session_manager = SessionManager()

# API Debug Logger
class APIDebugLogger:
    """Captures all API calls for debugging"""
    def __init__(self, max_logs=100):
        self.logs = []
        self.max_logs = max_logs

    def log(self, method, url, headers=None, payload=None, response_status=None, response_body=None, error=None):
        """Add a log entry"""
        from datetime import datetime

        log_entry = {
            'timestamp': datetime.now().isoformat(),
            'method': method,
            'url': url,
            'headers': self._sanitize_headers(headers) if headers else {},
            'payload': payload,
            'response_status': response_status,
            'response_body': response_body,
            'error': str(error) if error else None
        }

        self.logs.insert(0, log_entry)  # Most recent first

        # Keep only max_logs entries
        if len(self.logs) > self.max_logs:
            self.logs = self.logs[:self.max_logs]

    def _sanitize_headers(self, headers):
        """Remove sensitive data from headers"""
        if not headers:
            return {}

        sanitized = dict(headers)

        # Mask authorization tokens
        if 'Authorization' in sanitized:
            auth = sanitized['Authorization']
            if 'Bearer' in auth:
                sanitized['Authorization'] = 'Bearer [REDACTED]'

        return sanitized

    def get_logs(self, limit=None):
        """Get recent logs"""
        if limit:
            return self.logs[:limit]
        return self.logs

    def clear(self):
        """Clear all logs"""
        self.logs = []

api_logger = APIDebugLogger(max_logs=100)


def allowed_file(filename):
    """Check if file extension is allowed"""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


@app.route('/debug-env')
def debug_env():
    """Debug endpoint to check environment variables"""
    app_pass = os.environ.get('APP_PASSWORD')
    return jsonify({
        'APP_PASSWORD_SET': app_pass is not None and len(app_pass) > 0,
        'APP_PASSWORD_LENGTH': len(app_pass) if app_pass else 0,
        'APP_PASSWORD_FIRST_CHAR': app_pass[0] if app_pass else None
    })

@app.route('/')
def index():
    """Main page"""
    # Check auth status to show in UI
    auth_status = {
        'authenticated': auth_manager.is_authenticated(),
        'account_info': auth_manager.get_account_info() if auth_manager.is_authenticated() else None
    }
    return render_template('index.html', auth=auth_status)


@app.route('/merge-data-viewer')
def merge_data_viewer():
    """Merge Data Viewer page"""
    return render_template('merge_data_viewer.html')


@app.route('/api/auth/status')
def auth_status():
    """Get authentication status"""
    if auth_manager.is_authenticated():
        return jsonify({
            'authenticated': True,
            'account': auth_manager.get_account_info()
        })
    else:
        return jsonify({'authenticated': False})


@app.route('/api/auth/login', methods=['POST'])
def login():
    """Login with email/password"""
    data = request.get_json()
    email = data.get('email')
    password = data.get('password')

    if not email or not password:
        return jsonify({'error': 'Email and password required'}), 400

    if auth_manager.login(email, password):
        return jsonify({
            'success': True,
            'account': auth_manager.get_account_info()
        })
    else:
        return jsonify({'error': 'Authentication failed'}), 401


@app.route('/api/auth/logout', methods=['POST'])
def logout():
    """Logout and clear tokens"""
    auth_manager.logout()
    return jsonify({'success': True})


@app.route('/api/accounts', methods=['GET'])
def get_accounts():
    """Get all saved accounts"""
    try:
        accounts = auth_manager.get_all_accounts()
        return jsonify({
            'success': True,
            'accounts': accounts
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/accounts', methods=['POST'])
def add_account():
    """Add a new ScopeStack account"""
    try:
        data = request.get_json()
        email = data.get('email')
        password = data.get('password')

        if not email or not password:
            return jsonify({'error': 'Email and password required'}), 400

        result = auth_manager.add_account(email, password)

        if result.get('success'):
            return jsonify(result)
        else:
            return jsonify(result), 401

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/accounts/switch', methods=['POST'])
def switch_account():
    """Switch to a different saved account"""
    try:
        data = request.get_json()
        email = data.get('email')

        if not email:
            return jsonify({'error': 'Email required'}), 400

        result = auth_manager.switch_account(email)

        if result.get('success'):
            return jsonify(result)
        else:
            return jsonify(result), 400

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/accounts/<email>', methods=['DELETE'])
def remove_account(email):
    """Remove a saved account"""
    try:
        result = auth_manager.remove_account(email)
        return jsonify(result)
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/settings/ai', methods=['POST'])
def save_ai_settings():
    """Save AI provider settings"""
    try:
        data = request.get_json()

        # Validate settings
        enabled = data.get('enabled', False)
        provider = data.get('provider', 'openai')
        api_key = data.get('apiKey', '')
        max_iterations = data.get('maxIterations', 4)

        if provider not in ['openai', 'anthropic']:
            return jsonify({'error': 'Invalid provider'}), 400

        if not (1 <= max_iterations <= 10):
            return jsonify({'error': 'Max iterations must be between 1 and 10'}), 400

        # Save API key to secure storage if provided
        if api_key and api_key != '***saved***':
            auth_manager.save_ai_api_key(provider, api_key)

        # Store settings to file (persists across sessions)
        ai_settings = {
            'enabled': enabled,
            'provider': provider,
            'max_iterations': max_iterations
        }
        auth_manager.save_ai_settings(ai_settings)

        return jsonify({'success': True})

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/settings/ai', methods=['GET'])
def get_ai_settings():
    """Get current AI settings"""
    # Load settings from file (persists across sessions)
    settings = auth_manager.load_ai_settings()

    provider = settings.get('provider', 'openai')

    # Check if API key exists in secure storage
    has_api_key = auth_manager.has_ai_api_key(provider)

    # Don't send the API key back to client for security
    return jsonify({
        'enabled': settings.get('enabled', False),
        'provider': provider,
        'has_api_key': has_api_key,
        'max_iterations': settings.get('max_iterations', 4)
    })


@app.route('/api/settings/ai/validate', methods=['POST'])
def validate_ai_key():
    """Validate AI API key with lightweight heartbeat check"""
    try:
        data = request.get_json()
        provider = data.get('provider', 'openai')
        api_key = data.get('api_key', '')

        if not api_key:
            return jsonify({'valid': False, 'error': 'API key required'}), 400

        # Lightweight validation using HTTP requests (no SDK needed)
        import requests

        if provider == 'openai':
            # Use OpenAI's models endpoint (lightweight, just lists available models)
            response = requests.get(
                'https://api.openai.com/v1/models',
                headers={'Authorization': f'Bearer {api_key}'},
                timeout=10
            )

            if response.status_code == 200:
                return jsonify({
                    'valid': True,
                    'provider': 'openai',
                    'message': 'OpenAI API key validated successfully'
                })
            elif response.status_code == 401:
                return jsonify({
                    'valid': False,
                    'error': 'Invalid OpenAI API key'
                }), 401
            else:
                return jsonify({
                    'valid': False,
                    'error': f'OpenAI API error: {response.status_code}'
                }), 400

        elif provider == 'anthropic':
            # Use a minimal messages endpoint call (costs ~0.001 cents)
            response = requests.post(
                'https://api.anthropic.com/v1/messages',
                headers={
                    'x-api-key': api_key,
                    'anthropic-version': '2023-06-01',
                    'content-type': 'application/json'
                },
                json={
                    'model': 'claude-3-haiku-20240307',
                    'max_tokens': 1,
                    'messages': [{'role': 'user', 'content': 'hi'}]
                },
                timeout=10
            )

            if response.status_code == 200:
                return jsonify({
                    'valid': True,
                    'provider': 'anthropic',
                    'message': 'Anthropic API key validated successfully'
                })
            elif response.status_code == 401:
                return jsonify({
                    'valid': False,
                    'error': 'Invalid Anthropic API key'
                }), 401
            else:
                return jsonify({
                    'valid': False,
                    'error': f'Anthropic API error: {response.status_code}'
                }), 400

        else:
            return jsonify({'valid': False, 'error': 'Unknown provider'}), 400

    except requests.exceptions.Timeout:
        return jsonify({'valid': False, 'error': 'Request timeout - please try again'}), 408
    except Exception as e:
        return jsonify({'valid': False, 'error': f'Validation error: {str(e)}'}), 500


@app.route('/api/upload', methods=['POST'])
def upload_file():
    """Handle file upload and analysis"""
    if 'file' not in request.files:
        return jsonify({'error': 'No file provided'}), 400

    file = request.files['file']

    if file.filename == '':
        return jsonify({'error': 'No file selected'}), 400

    if not allowed_file(file.filename):
        return jsonify({'error': 'Only .docx files are allowed'}), 400

    try:
        # Save uploaded file
        filename = secure_filename(file.filename)
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        temp_filename = f"{timestamp}_{filename}"
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], temp_filename)
        file.save(filepath)

        # Analyze the template
        parser = MailMergeParser(filepath)
        fields = parser.extract_fields()
        structure = parser.get_field_structure()

        # Store filepath in session
        session['uploaded_file'] = filepath
        session['original_filename'] = filename

        return jsonify({
            'success': True,
            'filename': filename,
            'analysis': {
                'total_fields': len(fields),
                'unique_fields': len(set(fields)),
                'simple_fields': len(structure['simple']),
                'loop_fields': len(structure['loops']),
                'conditional_fields': len(structure['conditionals']),
                'simple_fields_list': sorted(structure['simple'])[:20],
                'loop_fields_list': sorted(structure['loops']),
                'conditional_fields_list': sorted(structure['conditionals'])[:20]
            }
        })

    except Exception as e:
        return jsonify({'error': f'Error analyzing file: {str(e)}'}), 500


@app.route('/api/convert', methods=['POST'])
def convert_file():
    """Convert the uploaded file"""
    if 'uploaded_file' not in session:
        return jsonify({'error': 'No file uploaded'}), 400

    input_file = session.get('uploaded_file')
    original_filename = session.get('original_filename', 'template.docx')

    if not os.path.exists(input_file):
        return jsonify({'error': 'Uploaded file not found'}), 400

    try:
        # Generate output filename
        base_name = Path(original_filename).stem
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        output_filename = f"{base_name}_converted_{timestamp}.docx"
        output_filepath = os.path.join(app.config['UPLOAD_FOLDER'], output_filename)

        # Perform conversion
        converter = TemplateConverter(input_file, output_filepath)
        success = converter.convert()

        if not success:
            return jsonify({'error': 'Conversion failed'}), 500

        # Validate the converted template
        validator = TemplateValidator()
        validation_result = validator.validate_template(output_filepath)

        # Store output file in session
        session['converted_file'] = output_filepath
        session['converted_filename'] = output_filename

        return jsonify({
            'success': True,
            'filename': output_filename,
            'warnings': converter.warnings,
            'validation': {
                'valid': validation_result['valid'],
                'errors': validation_result['errors'],
                'warnings': validation_result['warnings'],
                'error_count': validation_result['error_count'],
                'warning_count': validation_result['warning_count']
            }
        })

    except Exception as e:
        return jsonify({'error': f'Error converting file: {str(e)}'}), 500


@app.route('/api/download')
def download_file():
    """Download the converted file"""
    if 'converted_file' not in session:
        return jsonify({'error': 'No converted file available'}), 400

    filepath = session.get('converted_file')
    filename = session.get('converted_filename', 'converted_template.docx')

    if not os.path.exists(filepath):
        return jsonify({'error': 'Converted file not found'}), 400

    return send_file(
        filepath,
        as_attachment=True,
        download_name=filename,
        mimetype='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    )


@app.route('/api/validate', methods=['POST'])
def validate_template():
    """Validate template against project merge data"""
    if 'uploaded_file' not in session:
        return jsonify({'error': 'No file uploaded'}), 400

    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated. Please login first.'}), 401

    data = request.get_json()
    project_id = data.get('project_id')

    if not project_id:
        return jsonify({'error': 'Project ID required'}), 400

    try:
        # Parse template fields
        input_file = session.get('uploaded_file')
        parser = MailMergeParser(input_file)
        template_fields = parser.extract_fields()

        # Detect template type
        # v1 templates have Mail Merge fields like =field_name, field:if, field:each
        # v2 templates have tag fields like {field}, {#field}, {/field}
        is_v1_template = any(
            field.startswith('=') or ':if' in field or ':each' in field or ':end' in field
            for field in template_fields
        )

        template_type = 'v1' if is_v1_template else 'v2'

        # Use stored authentication token
        fetcher = MergeDataFetcher()
        token = auth_manager.get_access_token()

        if not token:
            return jsonify({'error': 'Authentication token expired. Please login again.'}), 401

        fetcher.authenticate(token=token)

        # Fetch merge data for the correct version
        merge_version = 1 if is_v1_template else 2
        available_fields = fetcher.get_available_fields(project_id, version=merge_version)

        if not available_fields:
            return jsonify({'error': 'Could not fetch merge data from project'}), 500

        # Validate
        validation = fetcher.validate_template_fields(template_fields, available_fields)

        return jsonify({
            'success': True,
            'template_type': template_type,
            'merge_version': merge_version,
            'validation': {
                'valid_count': len(validation['valid']),
                'missing_count': len(validation['missing']),
                'coverage': round(validation['coverage'] * 100, 1),
                'missing_fields': validation['missing'][:50]  # Limit to 50
            }
        })

    except Exception as e:
        return jsonify({'error': f'Validation error: {str(e)}'}), 500


@app.route('/api/fetch-merge-data', methods=['POST'])
def fetch_merge_data():
    """Fetch merge data for a project"""
    data = request.get_json()
    project_id = data.get('project_id')
    email = data.get('email')
    password = data.get('password')
    token = data.get('token')

    if not project_id:
        return jsonify({'error': 'Project ID required'}), 400

    try:
        fetcher = MergeDataFetcher()

        if token:
            fetcher.authenticate(token=token)
        elif email and password:
            if not fetcher.authenticate(email=email, password=password):
                return jsonify({'error': 'Authentication failed'}), 401
        else:
            return jsonify({'error': 'Authentication credentials required'}), 400

        merge_data = fetcher.fetch_merge_data(project_id)

        if not merge_data:
            return jsonify({'error': 'Could not fetch merge data'}), 500

        return jsonify({
            'success': True,
            'merge_data': merge_data
        })

    except Exception as e:
        return jsonify({'error': f'Error fetching merge data: {str(e)}'}), 500


@app.route('/api/test-project', methods=['POST'])
def test_project():
    """Test if a project's merge data is accessible"""
    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated. Please login first.'}), 401

    data = request.get_json()
    project_id = data.get('project_id')

    if not project_id:
        return jsonify({'error': 'Project ID required'}), 400

    try:
        fetcher = MergeDataFetcher()
        token = auth_manager.get_access_token()

        if not token:
            return jsonify({'error': 'Authentication token expired. Please login again.'}), 401

        fetcher.authenticate(token=token)

        # Test v1 merge data
        v1_status = 'unknown'
        v1_error = None
        try:
            v1_data = fetcher.fetch_v1_merge_data(project_id)
            if v1_data:
                v1_status = 'success'
            else:
                v1_status = 'failed'
                v1_error = 'No data returned'
        except Exception as e:
            v1_status = 'failed'
            v1_error = str(e)

        # Test v2 merge data
        v2_status = 'unknown'
        v2_error = None
        try:
            v2_data = fetcher.fetch_v2_merge_data(project_id)
            if v2_data:
                v2_status = 'success'
            else:
                v2_status = 'failed'
                v2_error = 'No data returned'
        except Exception as e:
            v2_status = 'failed'
            v2_error = str(e)

        return jsonify({
            'success': True,
            'project_id': project_id,
            'v1_status': v1_status,
            'v1_error': v1_error,
            'v2_status': v2_status,
            'v2_error': v2_error,
            'ready': v1_status == 'success' and v2_status == 'success'
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Test error: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/learn-mappings', methods=['POST'])
def learn_mappings():
    """Learn field mappings by comparing v1 and v2 merge data values"""
    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated. Please login first.'}), 401

    data = request.get_json()
    project_id = data.get('project_id')

    if not project_id:
        return jsonify({'error': 'Project ID required'}), 400

    try:
        # Import MappingLearner
        from learn_mappings import MappingLearner

        # Create fetcher with authentication
        fetcher = MergeDataFetcher()
        token = auth_manager.get_access_token()

        if not token:
            return jsonify({'error': 'Authentication token expired. Please login again.'}), 401

        fetcher.authenticate(token=token)

        # Learn mappings (suppress print output for web UI)
        import io
        import sys
        old_stdout = sys.stdout
        sys.stdout = log_capture = io.StringIO()

        try:
            learner = MappingLearner(fetcher)
            results = learner.learn_mappings(project_id)
        finally:
            sys.stdout = old_stdout
            log_output = log_capture.getvalue()

        if not results or not results.get('suggested_mappings'):
            return jsonify({
                'error': 'Could not learn mappings or no mappings found',
                'debug_log': log_output
            }), 500

        # Group by confidence for easier display
        high_conf = [s for s in results['suggested_mappings'] if s['confidence'] == 'high']
        medium_conf = [s for s in results['suggested_mappings'] if s['confidence'] == 'medium']
        low_conf = [s for s in results['suggested_mappings'] if s['confidence'] == 'low']

        # Limit results to avoid large responses
        return jsonify({
            'success': True,
            'project_id': project_id,
            'stats': {
                'total_matches': results['total_matches'],
                'total_mappings': len(results['suggested_mappings']),
                'high_confidence': len(high_conf),
                'medium_confidence': len(medium_conf),
                'low_confidence': len(low_conf)
            },
            'mappings': {
                'high': high_conf[:50],  # Top 50 high confidence
                'medium': medium_conf[:30],  # Top 30 medium confidence
                'low': low_conf[:20]  # Top 20 low confidence
            },
            'debug_log': log_output
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Learning error: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/upload-for-learning', methods=['POST'])
def upload_for_learning():
    """
    Upload documents and learn mappings using integrated approach:
    1. Extract v1 fields from template
    2. Extract actual values from output document
    3. Fetch v1 and v2 merge data from API
    4. Match: v1 field -> value (in output) -> v2 path
    """
    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated. Please login first.'}), 401

    try:
        project_id = request.form.get('project_id')
        if not project_id:
            return jsonify({'error': 'Project ID is required'}), 400

        # Get uploaded files
        v1_template = request.files.get('v1_template')
        output_doc = request.files.get('output_doc')
        v2_template = request.files.get('v2_template')  # Optional

        if not v1_template or not output_doc:
            return jsonify({'error': 'Both v1 template and output document are required'}), 400

        # Save files temporarily
        v1_path = os.path.join(app.config['UPLOAD_FOLDER'], secure_filename(v1_template.filename))
        output_path = os.path.join(app.config['UPLOAD_FOLDER'], secure_filename(output_doc.filename))

        v1_template.save(v1_path)
        output_doc.save(output_path)

        v2_path = None
        if v2_template:
            v2_path = os.path.join(app.config['UPLOAD_FOLDER'], secure_filename(v2_template.filename))
            v2_template.save(v2_path)

        # Import modules
        from learn_mappings import MappingLearner
        from document_analyzer import DocumentAnalyzer

        # Authenticate and create fetcher
        fetcher = MergeDataFetcher()
        token = auth_manager.get_access_token()
        fetcher.authenticate(token=token)

        # Capture debug output
        import io
        import sys
        old_stdout = sys.stdout
        sys.stdout = log_capture = io.StringIO()

        try:
            print(f"🔍 Analyzing documents for project {project_id}...")
            print("=" * 60)

            # Step 1: Extract v1 fields from template
            print("\n1️⃣ Extracting v1 fields from template...")
            analyzer = DocumentAnalyzer()
            v1_fields = analyzer.extract_v1_fields(v1_path)
            print(f"   Found {len(v1_fields)} unique v1 fields")

            # Step 2: Extract values from output document
            print("\n2️⃣ Extracting values from output document...")
            output_values = analyzer.extract_text_values(output_path)
            print(f"   Found {len(output_values)} unique values")

            # Step 3: Fetch merge data from API
            print("\n3️⃣ Fetching v1 merge data from API...")
            v1_merge_data = fetcher.fetch_v1_merge_data(project_id)
            if not v1_merge_data:
                raise Exception("Failed to fetch v1 merge data")
            print("   ✓ v1 merge data received")

            print("\n4️⃣ Fetching v2 merge data from API...")
            v2_merge_data = fetcher.fetch_v2_merge_data(project_id)
            if not v2_merge_data:
                raise Exception("Failed to fetch v2 merge data")
            print("   ✓ v2 merge data received")

            # Step 4: Match everything together
            print("\n5️⃣ Matching fields -> values -> v2 paths...")
            confirmed_mappings = analyzer.match_fields_to_values(
                v1_fields=v1_fields,
                output_values=output_values,
                v1_merge_data=v1_merge_data,
                v2_merge_data=v2_merge_data
            )
            print(f"   ✓ Found {len(confirmed_mappings)} confirmed mappings")

            # Also run standard value-matching as a supplement
            print("\n6️⃣ Running supplemental value-matching analysis...")
            learner = MappingLearner(fetcher)
            learner.v1_value_map = learner.extract_values_with_paths(
                v1_merge_data,
                strip_prefix="data.attributes.content."
            )
            learner.v2_value_map = learner.extract_values_with_paths(
                v2_merge_data,
                strip_prefix="data.attributes.content."
            )
            matches = learner.find_matching_values()
            supplemental_mappings = learner.suggest_mappings(matches)
            print(f"   ✓ Found {len(supplemental_mappings)} supplemental mappings")

            # Combine mappings (prioritize confirmed ones)
            all_mappings = confirmed_mappings + supplemental_mappings

            # Remove duplicates (keep confirmed versions)
            seen = set()
            unique_mappings = []
            for mapping in all_mappings:
                key = (mapping['v1_field'], mapping['v2_field'])
                if key not in seen:
                    seen.add(key)
                    unique_mappings.append(mapping)

            print(f"\n✅ Total unique mappings: {len(unique_mappings)}")

        finally:
            sys.stdout = old_stdout
            log_output = log_capture.getvalue()

        if not unique_mappings:
            return jsonify({
                'error': 'Could not discover any mappings',
                'debug_log': log_output
            }), 500

        # Save discovered mappings to persistent database
        print("\n7️⃣ Saving to persistent database...")
        mapping_db.import_mappings(
            mappings=unique_mappings,
            project_id=project_id
        )

        # Get statistics
        stats = mapping_db.get_statistics()

        # Cleanup
        os.remove(v1_path)
        os.remove(output_path)
        if v2_path:
            os.remove(v2_path)

        return jsonify({
            'success': True,
            'project_id': project_id,
            'mappings_discovered': len(unique_mappings),
            'confirmed_mappings': len(confirmed_mappings),
            'supplemental_mappings': len(supplemental_mappings),
            'database_stats': stats,
            'debug_log': log_output,
            'sample_mappings': unique_mappings[:5]  # Show first 5
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Learning error: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/mapping-database/stats', methods=['GET'])
def get_database_stats():
    """Get mapping database statistics"""
    try:
        stats = mapping_db.get_statistics()
        all_mappings = mapping_db.get_all_mappings()

        return jsonify({
            'success': True,
            'stats': stats,
            'sample_mappings': list(all_mappings.items())[:10]  # First 10 for preview
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/templates/list', methods=['GET'])
def list_templates():
    """List all document templates from ScopeStack"""
    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated'}), 401

    try:
        token = auth_manager.get_access_token()
        manager = TemplateManager()
        manager.authenticate(token=token)

        active_only = request.args.get('active_only', 'false').lower() == 'true'
        result = manager.list_templates(active_only=active_only)

        return jsonify({
            'success': True,
            'templates': result['data'],
            'meta': result['meta']
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to list templates: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/templates/<template_id>/download-for-conversion', methods=['POST'])
def download_template_for_conversion(template_id):
    """
    Download a template to local storage for conversion.
    Returns JSON with path instead of sending file directly.
    """
    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated'}), 401

    try:
        token = auth_manager.get_access_token()
        manager = TemplateManager()
        manager.authenticate(token=token)

        # Get template details first
        details = manager.get_template_details(template_id)
        filename = details['data']['attributes']['merge-template-filename']
        template_format = details['data']['attributes']['template-format']

        # Download to upload folder (not temp) so it persists for conversion
        output_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        manager.download_template(template_id, output_path)

        return jsonify({
            'success': True,
            'path': output_path,
            'filename': filename,
            'template_id': template_id,
            'template_format': template_format
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to download template: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/templates/<template_id>/download', methods=['POST'])
def download_template_api(template_id):
    """Download a template from ScopeStack (sends file to user)"""
    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated'}), 401

    try:
        token = auth_manager.get_access_token()
        manager = TemplateManager()
        manager.authenticate(token=token)

        # Get template details first
        details = manager.get_template_details(template_id)
        filename = details['data']['attributes']['merge-template-filename']

        # Download to temp file
        import tempfile
        temp_dir = tempfile.gettempdir()
        output_path = os.path.join(temp_dir, filename)
        manager.download_template(template_id, output_path)

        # Send the file for download
        from flask import send_file
        return send_file(
            output_path,
            as_attachment=True,
            download_name=filename,
            mimetype='application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        )

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to download template: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/conversion-report/<session_id>', methods=['GET'])
def get_conversion_report(session_id):
    """
    Generate a detailed conversion report showing:
    - V1 fields and structure
    - V1 merge data (sample)
    - Learned mappings
    - V2 fields generated
    - V2 merge data (sample)
    - Loop structures detected
    """
    from session_manager import SessionManager

    session_mgr = SessionManager()
    session = session_mgr.get_session(session_id)

    if not session:
        return jsonify({'error': 'Session not found'}), 404

    # Get template IDs from session
    v1_template_id = session.get('v1_template_id')
    v2_template_id = session.get('v2_template_id')
    project_id = session.get('project_id')

    if not all([v1_template_id, v2_template_id, project_id]):
        return jsonify({'error': 'Incomplete session data'}), 400

    try:
        token = auth_manager.get_access_token()
        fetcher = MergeDataFetcher()
        fetcher.authenticate(token=token)

        # Fetch merge data
        v1_merge_data = fetcher.fetch_v1_merge_data(project_id)
        v2_merge_data = fetcher.fetch_v2_merge_data(project_id)

        # Get V1 template structure
        v1_template_path = session.get('v1_template_path')
        if v1_template_path and os.path.exists(v1_template_path):
            from template_analyzer import TemplateAnalyzer
            analyzer = TemplateAnalyzer(v1_template_path)
            v1_fields = analyzer.extract_fields()
            v1_structure = analyzer.get_field_structure()
        else:
            v1_fields = []
            v1_structure = {}

        # Get V2 template structure (download if needed)
        manager = TemplateManager()
        manager.authenticate(token=token)

        v2_template_path = os.path.join(app.config['UPLOAD_FOLDER'], f'v2_diagnostic_{v2_template_id}.docx')
        manager.download_template(v2_template_id, v2_template_path)

        import zipfile
        import re
        with zipfile.ZipFile(v2_template_path, 'r') as zip_ref:
            xml_content = zip_ref.read('word/document.xml').decode('utf-8')
            # Extract all {field} patterns
            v2_fields = re.findall(r'\{[^}]+\}', xml_content)

        # Build report
        report = {
            'session_id': session_id,
            'v1_template_id': v1_template_id,
            'v2_template_id': v2_template_id,
            'project_id': project_id,

            'v1_info': {
                'total_fields': len(v1_fields),
                'fields': v1_fields[:20],  # First 20
                'structure': v1_structure,
                'merge_data_sample': str(v1_merge_data)[:500] if v1_merge_data else None
            },

            'v2_info': {
                'total_fields': len(v2_fields),
                'fields': v2_fields[:20],  # First 20
                'unique_fields': list(set(v2_fields))[:20],
                'merge_data_sample': str(v2_merge_data)[:500] if v2_merge_data else None
            },

            'learned_mappings': session.get('learned_mappings', [])[:20],
            'loop_mappings': session.get('loop_mappings', {}),

            'iterations': session.get('iterations', []),
            'current_similarity': session.get('current_similarity', 0.0)
        }

        return jsonify(report)

    except Exception as e:
        import traceback
        return jsonify({
            'error': str(e),
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/templates/create-or-update', methods=['POST'])
def create_or_update_template():
    """
    Create or update a template slot, then upload file
    Matches ScopeStack webapp workflow:
    1. Check if template with same name exists
    2. If exists: PATCH to update, else POST to create
    3. POST to /upload endpoint with file
    """
    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated'}), 401

    try:
        # Get form data
        template_name = request.form.get('name')
        template_file = request.files.get('template_file')

        if not template_name:
            return jsonify({'error': 'Template name is required'}), 400

        if not template_file:
            return jsonify({'error': 'Template file is required'}), 400

        # Save file temporarily
        filename = secure_filename(template_file.filename) or 'converted_template.docx'
        temp_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        template_file.save(temp_path)

        # Get auth info
        token = auth_manager.get_access_token()
        account_info = auth_manager.get_account_info()
        account_slug = account_info.get('account_slug')
        account_id = account_info.get('account_id')

        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.api+json',
            'Content-Type': 'application/vnd.api+json'
        }

        # Step 1: Check if template with this name already exists
        list_url = f'https://api.scopestack.io/{account_slug}/v1/document-templates'
        list_response = requests.get(list_url, headers=headers)

        # Log the GET request
        api_logger.log(
            method='GET',
            url=list_url,
            headers=headers,
            response_status=list_response.status_code,
            response_body=list_response.text[:1000] if list_response.status_code == 200 else list_response.text
        )

        existing_template_id = None
        if list_response.status_code == 200:
            templates = list_response.json().get('data', [])
            for template in templates:
                if template.get('attributes', {}).get('name') == template_name:
                    existing_template_id = template.get('id')
                    print(f"Found existing template: {template_name} (ID: {existing_template_id})")
                    break

        # Step 2: Create or update template metadata
        template_payload = {
            'data': {
                'type': 'document-templates',
                'attributes': {
                    'name': template_name,
                    'format': 'tag_template',
                    'filename-format': ['template_name', 'project_name', 'current_date'],
                    'merge-template-filename': filename,
                    'template-format': 'v2',
                    'include-formatting': True,
                    'teams': []
                },
                'relationships': {
                    'account': {
                        'data': {
                            'type': 'accounts',
                            'id': account_id
                        }
                    }
                }
            }
        }

        if existing_template_id:
            # PATCH existing template
            template_payload['data']['id'] = str(existing_template_id)
            template_url = f'{list_url}/{existing_template_id}'
            template_response = requests.patch(template_url, json=template_payload, headers=headers)
            print(f"Updating existing template {existing_template_id}")

            # Log the PATCH request
            api_logger.log(
                method='PATCH',
                url=template_url,
                headers=headers,
                payload=template_payload,
                response_status=template_response.status_code,
                response_body=template_response.text
            )
        else:
            # POST new template
            template_response = requests.post(list_url, json=template_payload, headers=headers)
            print(f"Creating new template")

            # Log the POST request
            api_logger.log(
                method='POST',
                url=list_url,
                headers=headers,
                payload=template_payload,
                response_status=template_response.status_code,
                response_body=template_response.text
            )

        if template_response.status_code not in [200, 201]:
            return jsonify({
                'error': f'Failed to create/update template: {template_response.status_code}',
                'details': template_response.text
            }), template_response.status_code

        template_data = template_response.json()
        template_id = template_data['data']['id']

        # Step 3: Upload file to template
        upload_url = f'{list_url}/{template_id}/upload'

        with open(temp_path, 'rb') as f:
            files = {
                'document_template[merge_template]': (filename, f, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')
            }
            upload_headers = {
                'Authorization': f'Bearer {token}',
                'Accept': 'application/vnd.api+json'
            }
            upload_response = requests.post(upload_url, files=files, headers=upload_headers)

            # Log the upload request
            api_logger.log(
                method='POST',
                url=upload_url,
                headers=upload_headers,
                payload=f'<file upload: {filename}>',
                response_status=upload_response.status_code,
                response_body=upload_response.text
            )

        # Cleanup
        os.remove(temp_path)

        if upload_response.status_code not in [200, 201]:
            return jsonify({
                'error': f'Template created but upload failed: {upload_response.status_code}',
                'details': upload_response.text,
                'template_id': template_id
            }), upload_response.status_code

        # Step 4: Check template health after upload
        manager = TemplateManager()
        manager.authenticate(token=token, account_slug=account_slug)
        health_check = manager.check_template_health(template_id)

        # Step 5: Handle corruption with auto-recovery
        if not health_check['is_healthy']:
            print(f"⚠️  Template {template_id} is corrupted: {health_check['issue']}")

            # Check if we have V1 template info for recovery
            v1_template_id = request.form.get('v1_template_id')
            v1_template_name = request.form.get('v1_template_name')

            if v1_template_id and health_check['can_auto_recover']:
                print(f"🔧 Attempting auto-recovery from V1 template {v1_template_id}")

                try:
                    # Download fresh V1 template
                    v1_download_path = os.path.join(
                        app.config['UPLOAD_FOLDER'],
                        f'v1_recovery_{template_id}.docx'
                    )
                    manager.download_template(v1_template_id, v1_download_path)

                    # Reconvert with fixed converter
                    from template_converter import TemplateConverter
                    reconverted_path = os.path.join(
                        app.config['UPLOAD_FOLDER'],
                        f'v2_recovered_{template_id}.docx'
                    )
                    converter = TemplateConverter(v1_download_path, reconverted_path)

                    if converter.convert():
                        print(f"✓ Reconversion successful")

                        # Re-upload recovered template
                        with open(reconverted_path, 'rb') as f:
                            files = {
                                'document_template[merge_template]': (
                                    os.path.basename(reconverted_path),
                                    f,
                                    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
                                )
                            }
                            upload_headers = {
                                'Authorization': f'Bearer {token}',
                                'Accept': 'application/vnd.api+json'
                            }
                            re_upload_response = requests.post(upload_url, files=files, headers=upload_headers)

                        # Cleanup recovery files
                        os.remove(v1_download_path)
                        os.remove(reconverted_path)

                        if re_upload_response.status_code in [200, 201]:
                            print(f"✓ Recovered template uploaded successfully")

                            return jsonify({
                                'success': True,
                                'template_id': template_id,
                                'name': template_name,
                                'action': 'recovered',
                                'message': f'Template "{template_name}" was corrupted and has been automatically recovered',
                                'recovery_performed': True,
                                'original_issue': health_check['issue']
                            })
                        else:
                            print(f"❌ Re-upload after recovery failed: {re_upload_response.status_code}")

                    else:
                        print(f"❌ Reconversion failed")

                except Exception as recovery_error:
                    print(f"❌ Auto-recovery failed: {recovery_error}")
                    # Continue to return corrupted template info below

            # If auto-recovery not possible or failed, return warning
            return jsonify({
                'success': True,
                'template_id': template_id,
                'name': template_name,
                'action': 'updated' if existing_template_id else 'created',
                'warning': 'Template uploaded but appears to be corrupted',
                'health': health_check,
                'message': f'Template "{template_name}" {"updated" if existing_template_id else "created"} but may be corrupted: {health_check["issue"]}'
            })

        # Step 6: Verify with GET
        verify_response = requests.get(f'{list_url}/{template_id}', headers=headers)

        return jsonify({
            'success': True,
            'template_id': template_id,
            'name': template_name,
            'action': 'updated' if existing_template_id else 'created',
            'message': f'Template "{template_name}" {"updated" if existing_template_id else "created"} successfully',
            'health': health_check
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to create/update template: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/templates/check-name', methods=['POST'])
def check_template_name():
    """
    Check if a template name is available (not already in use)
    Returns suggested name if collision exists
    """
    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated'}), 401

    try:
        data = request.json
        v1_template_name = data.get('v1_template_name')

        if not v1_template_name:
            return jsonify({'error': 'v1_template_name is required'}), 400

        token = auth_manager.get_access_token()
        manager = TemplateManager()
        manager.authenticate(token=token)

        # Generate smart name with collision detection
        suggested_name = manager.generate_converted_template_name(
            v1_template_name,
            check_collision=True
        )

        # Check if suggested name differs from base name (indicating collision)
        from datetime import date
        today = date.today().strftime('%Y-%m-%d')
        base_name = v1_template_name.replace(' V1', '').replace(' v1', '').strip()
        base_proposed = f"{base_name} - Converted - {today}"

        has_collision = suggested_name != base_proposed

        return jsonify({
            'success': True,
            'suggested_name': suggested_name,
            'has_collision': has_collision,
            'is_available': not has_collision
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to check template name: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/templates/v2-list', methods=['GET'])
def list_v2_templates_with_health():
    """
    List V2 templates with health status
    Returns templates filtered to V2 format with health check info
    """
    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated'}), 401

    try:
        token = auth_manager.get_access_token()
        manager = TemplateManager()
        manager.authenticate(token=token)

        # Get all templates
        active_only = request.args.get('active_only', 'false').lower() == 'true'
        result = manager.list_templates(active_only=active_only)

        # Filter to V2 templates only
        v2_templates = [
            t for t in result['data']
            if t['attributes'].get('template-format') == 'v2'
        ]

        # Optionally check health for each template
        check_health = request.args.get('check_health', 'false').lower() == 'true'

        if check_health:
            for template in v2_templates:
                template_id = template['id']
                health_info = manager.check_template_health(template_id)
                template['health'] = health_info

        return jsonify({
            'success': True,
            'templates': v2_templates,
            'count': len(v2_templates)
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to list V2 templates: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/templates/convert-and-upload', methods=['POST'])
def convert_and_upload_workflow():
    """
    Complete workflow: Download v1 template, learn mappings, convert, upload as v2

    This implements the full cycle:
    1. Download v1 template from platform
    2. Learn mappings using project data
    3. Convert to v2 format
    4. Upload as new v2 template
    """
    if not auth_manager.is_authenticated():
        return jsonify({'error': 'Not authenticated'}), 401

    try:
        data = request.json
        v1_template_id = data.get('v1_template_id')
        project_id = data.get('project_id')
        new_template_name = data.get('new_template_name')

        if not all([v1_template_id, project_id, new_template_name]):
            return jsonify({
                'error': 'v1_template_id, project_id, and new_template_name are required'
            }), 400

        token = auth_manager.get_access_token()

        # Import required modules
        from learn_mappings import MappingLearner
        from document_analyzer import DocumentAnalyzer

        # Capture output
        import io
        import sys
        old_stdout = sys.stdout
        sys.stdout = log_capture = io.StringIO()

        try:
            # Step 1: Download v1 template
            print(f"1️⃣ Downloading v1 template {v1_template_id}...")
            manager = TemplateManager()
            manager.authenticate(token=token)

            details = manager.get_template_details(v1_template_id)
            v1_filename = details['data']['attributes']['merge-template-filename']
            v1_path = os.path.join(app.config['UPLOAD_FOLDER'], f"v1_{v1_filename}")
            manager.download_template(v1_template_id, v1_path)
            print(f"   ✓ Downloaded: {v1_filename}")

            # Step 2: Learn mappings
            print(f"\n2️⃣ Learning mappings from project {project_id}...")
            fetcher = MergeDataFetcher()
            fetcher.authenticate(token=token)
            learner = MappingLearner(fetcher)
            results = learner.learn_mappings(project_id)

            if not results or not results.get('suggested_mappings'):
                raise Exception("Could not learn mappings from project")

            print(f"   ✓ Learned {len(results['suggested_mappings'])} mappings")

            # Save to database
            mapping_db.import_mappings(
                mappings=results['suggested_mappings'],
                project_id=project_id
            )

            # Step 3: Convert template
            print(f"\n3️⃣ Converting template to v2 format...")
            converted_filename = v1_filename.replace('.docx', '_v2.docx')
            converted_path = os.path.join(app.config['UPLOAD_FOLDER'], converted_filename)

            converter = TemplateConverter(v1_path, converted_path)
            converter.convert()
            print(f"   ✓ Converted to: {converted_filename}")

            # Step 4: Create and upload new template
            print(f"\n4️⃣ Uploading as new template: {new_template_name}...")
            create_result = manager.create_template(
                name=new_template_name,
                filename=converted_filename,
                template_format='v2',
                format_type='tag_template',
                include_formatting=True,
                active=False  # Start as inactive for testing
            )

            new_template_id = create_result['data']['id']
            manager.upload_template_file(new_template_id, converted_path)
            print(f"   ✓ Uploaded as template ID: {new_template_id}")

            # Cleanup
            os.remove(v1_path)
            os.remove(converted_path)

            print("\n✅ Complete workflow finished successfully!")

        finally:
            sys.stdout = old_stdout
            log_output = log_capture.getvalue()

        return jsonify({
            'success': True,
            'v1_template_id': v1_template_id,
            'new_template_id': new_template_id,
            'new_template_name': new_template_name,
            'mappings_learned': len(results['suggested_mappings']),
            'debug_log': log_output
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Workflow failed: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/analyze-for-review', methods=['POST'])
def analyze_for_review():
    """
    Analyze template and suggest mappings with path coherence scoring
    Used in Step 2-3 of unified conversion workflow
    """
    try:
        data = request.json
        template_path = data.get('template_path')
        project_id = data.get('project_id')  # Optional

        if not template_path or not os.path.exists(template_path):
            return jsonify({'error': 'Template path required'}), 400

        # Import required modules
        from path_coherence import PathCoherenceScorer
        from learn_mappings import MappingLearner

        # Extract fields from template
        parser = MailMergeParser(template_path)
        parser.extract_fields()
        field_structure = parser.get_field_structure()

        # Parse v1 structure for coherence scoring
        scorer = PathCoherenceScorer()
        all_fields = (field_structure['simple'] +
                     field_structure['loops'] +
                     field_structure['conditionals'])
        v1_structure = scorer.parse_v1_structure(all_fields)

        # Learn mappings if project ID provided
        suggested_mappings = []

        if project_id and auth_manager.is_authenticated():
            token = auth_manager.get_access_token()
            fetcher = MergeDataFetcher()
            fetcher.authenticate(token=token)

            learner = MappingLearner(fetcher)
            results = learner.learn_mappings(project_id, template_path)  # Pass template_path for loop detection

            if results and results.get('suggested_mappings'):
                # Apply path coherence scoring to learned mappings
                for mapping in results['suggested_mappings']:
                    v1_field = mapping['v1_field']

                    # Get all possible v2 candidates for this field
                    candidates = [(mapping['v2_field'], 'value_match')]

                    # Score with coherence
                    ranked = scorer.rank_v2_candidates(
                        v1_field=v1_field,
                        v2_candidates=candidates,
                        v1_structure=v1_structure,
                        current_v2_context=[]
                    )

                    # Determine coherence score and confidence
                    if ranked:
                        best = ranked[0]
                        coherence_score = best['coherence_score']
                    else:
                        coherence_score = 0.3  # Default minimum

                    # Map learning confidence to numeric score
                    learning_confidence = mapping.get('confidence', 'medium')
                    if learning_confidence == 'high':
                        base_score = 0.9
                    elif learning_confidence == 'medium':
                        base_score = 0.7
                    else:  # low
                        base_score = 0.5

                    # Combine learning confidence with coherence (weighted average)
                    # 60% learning confidence, 40% structural coherence
                    final_score = (base_score * 0.6) + (coherence_score * 0.4)

                    # Determine final confidence level
                    if final_score >= 0.8:
                        final_confidence = 'high'
                    elif final_score >= 0.6:
                        final_confidence = 'medium'
                    else:
                        final_confidence = 'low'

                    suggested_mappings.append({
                        'v1_field': v1_field,
                        'v2_field': mapping['v2_field'],
                        'confidence': final_confidence,
                        'coherence_score': final_score,
                        'match_reason': 'learned_from_data',
                        'original_value': mapping.get('value')
                    })

        # Use existing mappings from database for fields not learned
        db_mappings = mapping_db.get_all_mappings()

        for field in field_structure['simple']:
            # Check if we already have a suggestion
            if any(m['v1_field'] == field for m in suggested_mappings):
                continue

            # Look up in database
            if field in db_mappings:
                v2_field = db_mappings[field]['v2_field']
                confidence_score = db_mappings[field].get('confidence_score', 1)

                # Determine confidence level and coherence score from DB
                if confidence_score >= 5:
                    confidence = 'high'
                    coherence_score = 0.75  # High confidence from repeated usage
                elif confidence_score >= 2:
                    confidence = 'medium'
                    coherence_score = 0.6  # Medium confidence
                else:
                    confidence = 'low'
                    coherence_score = 0.4  # Lower confidence

                # Apply structural coherence scoring for DB mappings too
                candidates = [(v2_field, 'database')]
                ranked = scorer.rank_v2_candidates(
                    v1_field=field,
                    v2_candidates=candidates,
                    v1_structure=v1_structure,
                    current_v2_context=[]
                )

                if ranked and ranked[0]['coherence_score'] > coherence_score:
                    # Use higher score if structural analysis is better
                    coherence_score = (coherence_score + ranked[0]['coherence_score']) / 2

                suggested_mappings.append({
                    'v1_field': field,
                    'v2_field': v2_field,
                    'confidence': confidence,
                    'coherence_score': coherence_score,
                    'match_reason': 'database',
                    'original_value': None
                })

        # Get merge data if project ID was provided
        v1_merge_data = None
        v2_merge_data = None
        if project_id and auth_manager.is_authenticated():
            try:
                token = auth_manager.get_access_token()
                fetcher = MergeDataFetcher()
                fetcher.authenticate(token=token)
                v1_merge_data = fetcher.fetch_v1_merge_data(project_id)
                v2_merge_data = fetcher.fetch_v2_merge_data(project_id)
            except Exception as e:
                print(f"Warning: Could not fetch merge data: {e}")

        return jsonify({
            'success': True,
            'field_structure': field_structure,
            'suggested_mappings': suggested_mappings,
            'v1_structure': v1_structure,
            'v1_merge_data': v1_merge_data,
            'v2_merge_data': v2_merge_data,
            'total_fields': len(all_fields)
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Analysis failed: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/learn-and-improve', methods=['POST'])
def learn_and_improve():
    """
    Integrated endpoint: Learn → Convert → Improve
    Automatically performs the full workflow and returns session_id for progress polling.

    This replaces the manual 3-step process with an automated flow.
    """
    import threading
    import uuid
    from learn_mappings import MappingLearner
    from template_converter import TemplateConverter
    from template_version_tracker import TemplateVersionTracker

    try:
        data = request.json
        template_path = data.get('template_path')
        project_id = data.get('project_id')
        v1_template_id = data.get('v1_template_id')  # Optional - if cloud template selected

        if not template_path or not os.path.exists(template_path):
            return jsonify({'error': 'Template path required'}), 400

        if not project_id:
            return jsonify({'error': 'Project ID required for learning'}), 400

        # 1. Learn mappings (including loop structures)
        print(f"\n🎓 Starting integrated learn-and-improve workflow...")
        print(f"   Template: {template_path}")
        print(f"   Project: {project_id}")

        token = auth_manager.get_access_token()
        fetcher = MergeDataFetcher()
        fetcher.authenticate(token=token)

        learner = MappingLearner(fetcher)
        learning_results = learner.learn_mappings(project_id, template_path)

        if not learning_results:
            return jsonify({'error': 'Failed to learn mappings'}), 500

        suggested_mappings = learning_results.get('suggested_mappings', [])
        loop_mappings = learning_results.get('loop_mappings', {})

        print(f"   ✓ Learned {len(suggested_mappings)} field mappings")
        print(f"   ✓ Learned {len([k for k in loop_mappings.keys() if not k.endswith('_confidence')])} loop mappings")

        # 2. Convert template with learned mappings
        print(f"\n🔄 Converting template...")

        # Create converter and apply learned mappings
        # For now, use the existing conversion logic
        # TODO: Enhance converter to use loop mappings

        converted_filename = f'v2_converted_{os.path.basename(template_path)}'
        converted_path = os.path.join(app.config['UPLOAD_FOLDER'], converted_filename)

        converter = TemplateConverter(template_path, converted_path)

        # Convert suggested_mappings to learned_field_mappings format
        # Filter out loop mappings, only include field mappings
        learned_field_mappings = []
        for mapping in suggested_mappings:
            if mapping.get('mapping_type') != 'loop':
                # Map confidence string to numeric score
                confidence_str = mapping.get('confidence', 'medium')
                if confidence_str == 'high':
                    confidence_score = 0.9
                elif confidence_str == 'medium':
                    confidence_score = 0.7
                else:  # low
                    confidence_score = 0.5

                learned_field_mappings.append({
                    'v1_field': mapping['v1_field'],
                    'v2_field': mapping['v2_field'],
                    'confidence': confidence_score,
                    'source': 'learned'
                })

        # Pass loop mappings AND learned field mappings to converter
        if not converter.convert(loop_mappings=loop_mappings, learned_field_mappings=learned_field_mappings):
            return jsonify({'error': 'Template conversion failed'}), 500

        print(f"   ✓ Template converted: {converted_path}")

        # Validate the converted template
        from template_validator import TemplateValidator
        validator = TemplateValidator()
        validation_result = validator.validate_template(converted_path)

        if validation_result['error_count'] > 0:
            print(f"\n⚠️  Converted template has {validation_result['error_count']} validation errors:")
            for err in validation_result['errors'][:10]:
                print(f"   • {err}")
            print(f"\n   Continuing anyway - AI improvement will attempt to fix these...")

        # 3. Upload converted template to ScopeStack
        print(f"\n☁️  Uploading to ScopeStack...")

        version_tracker = TemplateVersionTracker()
        versioned_name = version_tracker.generate_versioned_name(
            f"V2_AutoConverted_{os.path.splitext(os.path.basename(template_path))[0]}"
        )

        manager = TemplateManager()
        manager.authenticate(token=token)

        create_result = manager.create_template(
            name=versioned_name,
            filename=os.path.basename(converted_path),
            template_format="v2",
            format_type="tag_template",
            include_formatting=True
        )

        if not create_result.get('data'):
            return jsonify({'error': 'Failed to create v2 template - no data in response'}), 500

        v2_template_id = create_result['data']['id']
        manager.upload_template_file(v2_template_id, converted_path)

        print(f"   ✓ Uploaded as template ID: {v2_template_id}")

        # 4. Start recursive improvement in background
        session_id = str(uuid.uuid4())

        print(f"\n🚀 Starting recursive improvement (session: {session_id[:8]}...)...")

        # Create session with full metadata BEFORE starting background thread
        from session_manager import SessionManager
        session_mgr = SessionManager()
        session_mgr.create_session(
            v1_template_id=v1_template_id_local,
            v2_template_id=v2_template_id,
            project_id=project_id,
            session_name=f"Conversion_{versioned_name}"
        )

        # Store learned mappings and loop mappings in session
        session_data = session_mgr.get_session(session_id)
        if session_data:
            session_data['learned_mappings'] = suggested_mappings[:50]  # Store first 50
            session_data['loop_mappings'] = loop_mappings
            session_data['v1_template_path'] = template_path
            session_data['v2_template_path'] = converted_path
            session_data['v1_template_id'] = v1_template_id_local
            session_mgr._save_sessions()

        def run_improvement_async():
            """Background thread for recursive improvement"""
            try:
                from ai_converter import AIConverter
                from pathlib import Path

                # Get session manager instance
                session_mgr = SessionManager()

                # Update progress: starting
                session_mgr.update_progress(session_id, {
                    'iteration': 0,
                    'status': 'initializing',
                    'similarity': 0.0,
                    'message': 'Initializing recursive improvement...'
                })

                # Initialize AI converter
                api_key = auth_manager.get_ai_api_key('openai')
                if not api_key:
                    raise Exception('No OpenAI API key configured')

                ai_converter = AIConverter(provider='openai', api_key=api_key)

                # Create document cache directory
                cache_dir = Path(__file__).parent / 'document_cache' / session_id
                cache_dir.mkdir(parents=True, exist_ok=True)

                # Get template path from converted file
                # We need the v1 template for comparison
                # For now, we'll create a v1 template ID by uploading the original

                session_mgr.update_progress(session_id, {
                    'iteration': 0,
                    'status': 'generating_baseline',
                    'similarity': 0.0,
                    'message': 'Generating V1 baseline document...'
                })

                # Get V1 template ID
                # If cloud template was selected, we already have the ID
                # If new template was uploaded, we need to create a V1 template
                v1_template_id_local = v1_template_id  # Use the one passed to endpoint

                if not v1_template_id_local:
                    # New template upload - need to create V1 template for baseline
                    print("   Creating V1 template for baseline comparison...")
                    from template_version_tracker import TemplateVersionTracker
                    version_tracker = TemplateVersionTracker()

                    v1_upload_name = version_tracker.generate_versioned_name(
                        f"V1_Original_{os.path.splitext(os.path.basename(template_path))[0]}"
                    )

                    v1_create_result = manager.create_template(
                        name=v1_upload_name,
                        filename=os.path.basename(template_path),
                        template_format="v1",
                        format_type="word_template",
                        include_formatting=True
                    )

                    if not v1_create_result.get('data'):
                        raise Exception('Failed to create V1 template for comparison - no data in response')

                    v1_template_id_local = v1_create_result['data']['id']
                    manager.upload_template_file(v1_template_id_local, template_path)
                    print(f"   ✓ Created V1 template ID: {v1_template_id_local}")
                else:
                    print(f"   Using existing cloud template ID: {v1_template_id_local}")

                # Generate V1 baseline document
                v1_doc_result = _generate_document_direct(v1_template_id_local, project_id)
                if v1_doc_result.get('error'):
                    raise Exception(f"Failed to generate V1 baseline: {v1_doc_result['error']}")

                v1_doc_path = os.path.join(app.config['UPLOAD_FOLDER'], f'V1_Baseline_{session_id}.docx')
                doc_content = requests.get(v1_doc_result['download_url']).content
                with open(v1_doc_path, 'wb') as f:
                    f.write(doc_content)

                session_mgr.update_progress(session_id, {
                    'iteration': 0,
                    'status': 'baseline_ready',
                    'similarity': 0.0,
                    'message': 'V1 baseline generated. Starting iterations...'
                })

                # Run improvement iterations
                max_iterations = 4
                current_v2_id = v2_template_id
                iteration_history = []

                for iteration in range(1, max_iterations + 1):
                    session_mgr.update_progress(session_id, {
                        'iteration': iteration,
                        'status': 'generating_v2',
                        'similarity': 0.0,
                        'message': f'Iteration {iteration}: Generating V2 document...'
                    })

                    # Generate V2 document
                    v2_doc_result = _generate_document_direct(current_v2_id, project_id)
                    if v2_doc_result.get('error'):
                        session_mgr.update_progress(session_id, {
                            'iteration': iteration,
                            'status': 'failed',
                            'similarity': 0.0,
                            'message': f'Failed to generate V2 document: {v2_doc_result["error"]}'
                        })
                        break

                    v2_doc_path = os.path.join(app.config['UPLOAD_FOLDER'], f'V2_Iter{iteration}_{session_id}.docx')
                    doc_content = requests.get(v2_doc_result['download_url']).content
                    with open(v2_doc_path, 'wb') as f:
                        f.write(doc_content)

                    # Compare documents
                    session_mgr.update_progress(session_id, {
                        'iteration': iteration,
                        'status': 'comparing',
                        'similarity': 0.0,
                        'message': f'Iteration {iteration}: Comparing documents...'
                    })

                    comparison = ai_converter.compare_documents(v1_doc_path, v2_doc_path)
                    similarity = comparison['similarity_ratio']
                    syntax_errors = comparison.get('v2_template_errors', [])

                    print(f"\n📊 Iteration {iteration} Results:")
                    print(f"   Similarity: {similarity*100:.1f}%")
                    print(f"   Syntax Errors: {len(syntax_errors)}")
                    if len(syntax_errors) > 0:
                        print(f"   First few errors:")
                        for err in syntax_errors[:3]:
                            print(f"     • {err.get('error_text', str(err))[:80]}")

                    # Store iteration in history
                    iteration_history.append({
                        'iteration': iteration,
                        'similarity': similarity,
                        'syntax_errors': len(syntax_errors),
                        'status': 'completed',
                        'template_id': current_v2_id
                    })

                    session_mgr.update_progress(session_id, {
                        'iteration': iteration,
                        'status': 'compared',
                        'similarity': similarity,
                        'message': f'Iteration {iteration}: Similarity {similarity*100:.1f}%, {len(syntax_errors)} errors',
                        'errors_found': len(syntax_errors)
                    })

                    # Check if we're done
                    if similarity >= 0.95:
                        session_mgr.update_progress(session_id, {
                            'iteration': iteration,
                            'status': 'complete',
                            'similarity': similarity,
                            'message': f'Success! Achieved {similarity*100:.1f}% similarity'
                        })
                        session_mgr.sessions[session_id]['status'] = 'complete'
                        session_mgr.sessions[session_id]['current_similarity'] = similarity
                        session_mgr.sessions[session_id]['total_iterations'] = iteration
                        session_mgr.sessions[session_id]['iterations'] = iteration_history
                        session_mgr._save_sessions()
                        break

                    # Apply AI fixes if there are errors
                    if len(syntax_errors) > 0:
                        session_mgr.update_progress(session_id, {
                            'iteration': iteration,
                            'status': 'fixing_errors',
                            'similarity': similarity,
                            'message': f'Iteration {iteration}: Fixing {len(syntax_errors)} errors with AI...'
                        })

                        print(f"\n🤖 Asking AI to fix {len(syntax_errors)} syntax errors...")

                        # Get template XML for AI analysis
                        v2_template_path = os.path.join(app.config['UPLOAD_FOLDER'], f'v2_template_iter{iteration}.docx')
                        manager.download_template(current_v2_id, v2_template_path)

                        v2_xml = ai_converter.analyze_template_xml(v2_template_path)

                        # Get merge data context for AI
                        try:
                            from merge_data_fetcher import MergeDataFetcher
                            fetcher = MergeDataFetcher()
                            token = auth_manager.get_access_token()
                            fetcher.authenticate(token=token)

                            v1_data = fetcher.fetch_merge_data(project_id, v1_template_id_local)
                            v2_data = fetcher.fetch_merge_data(project_id, current_v2_id)

                            merge_data_context = {
                                'v1_structure': str(v1_data)[:500],
                                'v2_structure': str(v2_data)[:500]
                            }
                        except Exception as e:
                            print(f"⚠️  Could not fetch merge data: {e}")
                            merge_data_context = {}

                        # Ask AI to fix errors
                        fix_result = ai_converter.fix_syntax_errors(v2_xml, syntax_errors, {}, merge_data_context)
                        fixes_applied = len(fix_result.get('fixes_applied', []))

                        print(f"✓ AI suggested {fixes_applied} fixes")

                        if fixes_applied > 0:
                            # Apply fixes to template
                            import zipfile
                            fixed_template_path = os.path.join(
                                app.config['UPLOAD_FOLDER'],
                                f'v2_fixed_iter{iteration}.docx'
                            )

                            with zipfile.ZipFile(v2_template_path, 'r') as zip_in:
                                with zipfile.ZipFile(fixed_template_path, 'w') as zip_out:
                                    for item in zip_in.infolist():
                                        data = zip_in.read(item.filename)
                                        if item.filename == 'word/document.xml':
                                            data = fix_result['fixed_xml'].encode('utf-8')
                                        zip_out.writestr(item, data)

                            # Upload fixed template (working slot pattern)
                            print(f"📤 Updating template {current_v2_id} with fixes...")
                            manager.upload_template_file(current_v2_id, fixed_template_path)
                            print(f"✓ Template updated with AI fixes")

                            iteration_history[-1]['fixes_applied'] = fixes_applied
                            iteration_history[-1]['status'] = 'fixed'
                        else:
                            print(f"⚠️  AI could not suggest fixes")
                            iteration_history[-1]['status'] = 'no_fixes_possible'

                    if iteration == max_iterations:
                        # Final iteration reached
                        session_mgr.update_progress(session_id, {
                            'iteration': iteration,
                            'status': 'complete',
                            'similarity': similarity,
                            'message': f'Completed {iteration} iterations. Final similarity: {similarity*100:.1f}%. Note: AI improvement not yet fully integrated.'
                        })
                        session_mgr.sessions[session_id]['status'] = 'complete'
                        session_mgr.sessions[session_id]['current_similarity'] = similarity
                        session_mgr.sessions[session_id]['total_iterations'] = iteration
                        session_mgr.sessions[session_id]['iterations'] = iteration_history
                        session_mgr._save_sessions()

            except Exception as e:
                print(f"❌ Background improvement failed: {e}")
                import traceback
                traceback.print_exc()

                from session_manager import SessionManager
                session_mgr = SessionManager()
                session_mgr.update_progress(session_id, {
                    'iteration': 0,
                    'status': 'failed',
                    'similarity': 0.0,
                    'message': f'Error: {str(e)}'
                })
                session_mgr.sessions[session_id]['status'] = 'failed'
                session_mgr._save_sessions()

        # Start background thread
        thread = threading.Thread(target=run_improvement_async, daemon=True)
        thread.start()

        return jsonify({
            'success': True,
            'session_id': session_id,
            'v2_template_id': v2_template_id,
            'learned_mappings': suggested_mappings,
            'loop_mappings': loop_mappings,
            'message': 'Improvement process started in background'
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Learn-and-improve workflow failed: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/improvement-progress/<session_id>', methods=['GET'])
def get_improvement_progress(session_id):
    """
    Get current progress for an improvement session.
    UI polls this endpoint every 2 seconds to show real-time progress.
    """
    try:
        from session_manager import SessionManager
        session_mgr = SessionManager()

        progress = session_mgr.get_progress(session_id)
        return jsonify(progress)

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@app.route('/api/convert-with-overrides', methods=['POST'])
def convert_with_overrides():
    """
    Convert template with user-reviewed mappings and overrides
    Saves all mappings (including overrides) to database

    REQUIRED: project_id must be provided for merge data comparison
    """
    try:
        data = request.json
        template_path = data.get('template_path')
        overrides = data.get('overrides', {})  # {v1_field: v2_field}
        project_id = data.get('project_id')

        if not template_path or not os.path.exists(template_path):
            return jsonify({'error': 'Template path required'}), 400

        if not project_id:
            return jsonify({'error': 'Project ID is required for template conversion'}), 400

        # Create output path
        output_filename = os.path.basename(template_path).replace('.docx', '_v2.docx')
        output_path = os.path.join(app.config['UPLOAD_FOLDER'], output_filename)

        # Apply overrides to global mapping dictionaries (temporarily)
        from template_converter import FIELD_MAPPINGS, LOOP_CONVERSIONS, CONDITIONAL_CONVERSIONS
        original_mappings = {}

        if overrides:
            for v1_field, v2_field in overrides.items():
                # Save original value (if any)
                if v1_field in FIELD_MAPPINGS:
                    original_mappings[v1_field] = FIELD_MAPPINGS[v1_field]
                # Apply override
                FIELD_MAPPINGS[v1_field] = v2_field

        # Perform conversion
        converter = TemplateConverter(template_path, output_path)
        converter.convert()

        # Restore original mappings
        if overrides:
            for v1_field in overrides.keys():
                if v1_field in original_mappings:
                    FIELD_MAPPINGS[v1_field] = original_mappings[v1_field]
                else:
                    FIELD_MAPPINGS.pop(v1_field, None)

        # Save all mappings to database (including overrides)
        all_mappings = []

        # Get fields from template and their mappings
        parser = MailMergeParser(template_path)
        parser.extract_fields()
        field_structure = parser.get_field_structure()

        # Save simple field mappings
        for v1_field in field_structure['simple']:
            if v1_field in FIELD_MAPPINGS:
                is_override = v1_field in overrides
                all_mappings.append({
                    'v1_field': v1_field,
                    'v2_field': FIELD_MAPPINGS[v1_field],
                    'confidence': 'high' if is_override else 'medium',
                    'is_override': is_override
                })

        # Save to database
        if all_mappings:
            mapping_db.import_mappings(
                mappings=all_mappings,
                project_id=project_id
            )

        # Store in session for download
        session['converted_file'] = output_path
        session['original_file'] = template_path

        return jsonify({
            'success': True,
            'output_path': output_path,
            'output_filename': output_filename,
            'mappings_saved': len(all_mappings),
            'overrides_applied': len(overrides)
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Conversion failed: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/generate-document', methods=['POST'])
def generate_document():
    """
    Generate a document from a template using ScopeStack API
    Used for before/after comparison of v1 and v2 templates
    """
    try:
        data = request.json
        template_id = data.get('template_id')
        project_id = data.get('project_id')
        document_name = data.get('document_name', 'Test Document')
        generate_pdf = data.get('generate_pdf', False)

        if not template_id or not project_id:
            return jsonify({'error': 'Template ID and Project ID required'}), 400

        if not auth_manager.is_authenticated():
            return jsonify({'error': 'Not authenticated'}), 401

        # Get account slug
        token = auth_manager.get_access_token()
        account_info = auth_manager.get_account_info()
        account_slug = account_info.get('account_slug') if account_info else None

        # Create document payload
        payload = {
            'data': {
                'type': 'project-documents',
                'attributes': {
                    'template-id': str(template_id),
                    'document-type': 'sow',
                    'force-regeneration': True,
                    'generate-pdf': generate_pdf
                },
                'relationships': {
                    'project': {
                        'data': {
                            'type': 'projects',
                            'id': str(project_id)
                        }
                    }
                }
            }
        }

        # Create document
        api_url = f'https://api.scopestack.io/{account_slug}/v1/project-documents'
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.api+json',
            'Content-Type': 'application/vnd.api+json'
        }

        response = requests.post(api_url, json=payload, headers=headers)

        # Log the document creation request
        api_logger.log(
            method='POST',
            url=api_url,
            headers=headers,
            payload=payload,
            response_status=response.status_code,
            response_body=response.text[:500] if response.status_code in [200, 201] else response.text
        )

        if response.status_code not in [200, 201]:
            error_detail = response.text
            print(f"❌ Document creation failed: {response.status_code}")
            print(f"   Response: {error_detail[:1000]}")
            return jsonify({
                'error': f'Failed to create document: {response.status_code}',
                'details': error_detail,
                'api_url': api_url,
                'template_id': template_id,
                'project_id': project_id
            }), response.status_code

        document_data = response.json()
        document_id = document_data['data']['id']
        print(f"📄 Created document {document_id}, waiting for generation...")

        # Wait for document generation (with timeout)
        import time
        max_attempts = 60  # 5 minutes
        attempts = 0

        while attempts < max_attempts:
            # Check document status
            status_url = f'{api_url}/{document_id}'
            status_response = requests.get(status_url, headers=headers)

            if status_response.status_code == 200:
                status_data = status_response.json()
                status = status_data['data']['attributes'].get('status')

                print(f"  Poll attempt {attempts + 1}/{max_attempts}: status = {status}")

                if status == 'finished':
                    # Get document URL
                    document_url = status_data['data']['attributes'].get('document-url')

                    if document_url:
                        print(f"  Downloading from: {document_url}")

                        # Download the document
                        # Try without auth headers first (might be a presigned URL)
                        doc_response = requests.get(document_url)

                        # Log the download request (without auth headers for presigned URLs)
                        api_logger.log(
                            method='GET',
                            url=document_url,
                            headers={},
                            response_status=doc_response.status_code,
                            response_body=doc_response.text[:500] if doc_response.status_code != 200 else f'<binary content: {len(doc_response.content)} bytes>'
                        )

                        if doc_response.status_code == 200:
                            # Save to temp file
                            extension = '.pdf' if generate_pdf else '.docx'
                            filename = f'{document_name}_{template_id}{extension}'
                            filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)

                            with open(filepath, 'wb') as f:
                                f.write(doc_response.content)

                            print(f"✓ Document saved: {filename} ({len(doc_response.content)} bytes)")

                            return jsonify({
                                'success': True,
                                'document_id': document_id,
                                'document_url': document_url,
                                'filepath': filepath,
                                'filename': filename,
                                'status': 'finished'
                            })
                        else:
                            error_detail = doc_response.text[:500] if doc_response.text else 'No error details'
                            print(f"⚠️  Failed to download document from URL: {doc_response.status_code}")
                            print(f"    URL: {document_url}")
                            print(f"    Response: {error_detail}")
                            return jsonify({
                                'error': f'Failed to download document: {doc_response.status_code}',
                                'status': 'error',
                                'details': error_detail,
                                'url': document_url
                            }), 500
                    else:
                        print(f"⚠️  Document finished but no download URL in response")
                        return jsonify({
                            'error': 'Document generated but no download URL available',
                            'status': 'error',
                            'details': 'The API returned a finished status but did not provide a document-url attribute'
                        }), 500

                elif status == 'error':
                    error_text = status_data['data']['attributes'].get('error-text', 'Unknown error')
                    return jsonify({
                        'error': f'Document generation failed: {error_text}',
                        'status': 'error'
                    }), 500

            # Wait before next check
            time.sleep(5)
            attempts += 1

        # Timeout
        return jsonify({
            'error': 'Document generation timed out',
            'document_id': document_id,
            'status': 'timeout'
        }), 408

    except Exception as e:
        import traceback
        error_trace = traceback.format_exc()
        print(f"❌ Document generation exception:")
        print(error_trace)
        return jsonify({
            'error': f'Document generation error: {str(e)}',
            'traceback': error_trace
        }), 500


@app.route('/api/download-generated/<filename>')
def download_generated(filename):
    """
    Download a generated document from the temp folder
    Used for before/after comparison documents
    """
    try:
        # Security: only allow filenames, not paths
        if '/' in filename or '\\' in filename or '..' in filename:
            return jsonify({'error': 'Invalid filename'}), 400

        filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)

        if not os.path.exists(filepath):
            return jsonify({'error': 'File not found'}), 404

        # Determine mimetype based on extension
        if filename.endswith('.pdf'):
            mimetype = 'application/pdf'
        elif filename.endswith('.docx'):
            mimetype = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        else:
            mimetype = 'application/octet-stream'

        return send_file(
            filepath,
            as_attachment=True,
            download_name=filename,
            mimetype=mimetype
        )

    except Exception as e:
        import traceback
        print(f"Download error for {filename}: {str(e)}")
        print(traceback.format_exc())
        return jsonify({'error': f'Download error: {str(e)}'}), 500


@app.route('/api/cleanup', methods=['POST'])
def cleanup_files():
    """Clean up temporary files"""
    try:
        if 'uploaded_file' in session:
            filepath = session.get('uploaded_file')
            if os.path.exists(filepath):
                os.remove(filepath)

        if 'converted_file' in session:
            filepath = session.get('converted_file')
            if os.path.exists(filepath):
                os.remove(filepath)

        session.clear()
        return jsonify({'success': True})

    except Exception as e:
        return jsonify({'error': f'Cleanup error: {str(e)}'}), 500


@app.route('/api/debug/logs', methods=['GET'])
def get_debug_logs():
    """Get API debug logs for troubleshooting"""
    try:
        limit = request.args.get('limit', type=int)
        logs = api_logger.get_logs(limit=limit)
        return jsonify({
            'success': True,
            'logs': logs,
            'total_count': len(api_logger.logs)
        })
    except Exception as e:
        return jsonify({'error': f'Error getting logs: {str(e)}'}), 500


@app.route('/api/debug/logs/clear', methods=['POST'])
def clear_debug_logs():
    """Clear all API debug logs"""
    try:
        api_logger.clear()
        return jsonify({'success': True, 'message': 'Logs cleared'})
    except Exception as e:
        return jsonify({'error': f'Error clearing logs: {str(e)}'}), 500


@app.route('/api/ai-improve-conversion', methods=['POST'])
def ai_improve_conversion():
    """
    Use AI to iteratively improve template conversion
    Compares V1 and V2 documents and suggests mapping improvements
    """
    try:
        data = request.json
        v1_template_id = data.get('v1_template_id')
        v2_template_id = data.get('v2_template_id')
        project_id = data.get('project_id')
        v1_doc_path = data.get('v1_document_path')
        v2_doc_path = data.get('v2_document_path')
        provider = data.get('ai_provider', 'openai')
        max_iterations = data.get('max_iterations', 4)

        if not all([v1_template_id, v2_template_id, project_id, v1_doc_path, v2_doc_path]):
            return jsonify({'error': 'Missing required parameters'}), 400

        # Check if AI is enabled and we have an API key
        api_key = auth_manager.get_ai_api_key(provider)
        if not api_key:
            return jsonify({'error': f'No {provider} API key configured'}), 400

        # Import AI converter
        from ai_converter import AIConverter

        # Initialize AI converter
        ai_converter = AIConverter(provider=provider, api_key=api_key)

        # Get template paths (download if needed)
        from template_manager import TemplateManager
        token = auth_manager.get_access_token()
        manager = TemplateManager()
        manager.authenticate(token=token)

        # Download templates
        v1_template_path = os.path.join(app.config['UPLOAD_FOLDER'], f'v1_template_{v1_template_id}.docx')
        v2_template_path = os.path.join(app.config['UPLOAD_FOLDER'], f'v2_template_{v2_template_id}.docx')

        if not os.path.exists(v1_template_path):
            manager.download_template(v1_template_id, v1_template_path)

        if not os.path.exists(v2_template_path):
            manager.download_template(v2_template_id, v2_template_path)

        # Get initial mappings from database
        from mapping_database import MappingDatabase
        mapping_db = MappingDatabase()
        db_mappings_dict = mapping_db.get_all_mappings()

        # Convert dict format to list format for AI converter
        initial_mappings = []
        for v1_field, mapping_data in db_mappings_dict.items():
            v2_field = mapping_data.get('v2_field', '')
            confidence_score = mapping_data.get('confidence_score', 0)

            # Convert numeric confidence to text
            if confidence_score >= 3:
                confidence = 'high'
            elif confidence_score >= 2:
                confidence = 'medium'
            else:
                confidence = 'low'

            initial_mappings.append({
                'v1_field': v1_field,
                'v2_field': v2_field,
                'confidence': confidence
            })

        # Run iterative improvement
        print(f"\n🤖 Starting AI-powered iterative conversion...")
        print(f"   Provider: {provider}")
        print(f"   Max iterations: {max_iterations}")

        result = ai_converter.iterative_convert(
            v1_template_path=v1_template_path,
            v2_template_path=v2_template_path,
            v1_document_path=v1_doc_path,
            v2_document_path=v2_doc_path,
            initial_mappings=initial_mappings,
            max_iterations=max_iterations,
            target_similarity=0.95
        )

        # Extract template errors from the last iteration's comparison
        template_errors = []
        if result['iterations']:
            last_iter = result['iterations'][-1]
            # The errors would be in the comparison data if we stored it
            # For now, let's extract them directly
            v2_errors = ai_converter.extract_docx_templater_errors(v2_doc_path)
            template_errors = v2_errors

        return jsonify({
            'success': True,
            'iterations': result['iterations'],
            'final_similarity': result['final_similarity'],
            'final_mappings': result['final_mappings'],
            'template_errors': template_errors
        })

    except Exception as e:
        import traceback
        error_trace = traceback.format_exc()
        print(f"❌ AI conversion error:")
        print(error_trace)
        return jsonify({
            'error': f'AI conversion error: {str(e)}',
            'traceback': error_trace
        }), 500


def _generate_document_direct(template_id: str, project_id: str) -> Dict:
    """
    Generate a document directly using ScopeStack API (no Workato)

    Returns:
        dict with download_url or error
    """
    token = auth_manager.get_access_token()
    account_info = auth_manager.get_account_info()
    account_slug = account_info.get('account_slug') if account_info else None

    if not account_slug:
        return {'error': 'No account slug available'}

    # Create document payload
    payload = {
        'data': {
            'type': 'project-documents',
            'attributes': {
                'template-id': str(template_id),
                'document-type': 'sow',
                'force-regeneration': True,
                'generate-pdf': False
            },
            'relationships': {
                'project': {
                    'data': {
                        'type': 'projects',
                        'id': str(project_id)
                    }
                }
            }
        }
    }

    # Create document
    api_url = f'https://api.scopestack.io/{account_slug}/v1/project-documents'
    headers = {
        'Authorization': f'Bearer {token}',
        'Accept': 'application/vnd.api+json',
        'Content-Type': 'application/vnd.api+json'
    }

    response = requests.post(api_url, json=payload, headers=headers)

    if response.status_code != 201:
        error_detail = response.text
        print(f"❌ Document creation failed: {response.status_code}")
        print(f"   API URL: {api_url}")
        print(f"   Template ID: {template_id}")
        print(f"   Project ID: {project_id}")
        print(f"   Response: {error_detail[:1000]}")
        return {
            'error': f'Failed to create document: {response.status_code}',
            'details': error_detail,
            'template_id': template_id,
            'project_id': project_id
        }

    doc_data = response.json()
    doc_id = doc_data.get('data', {}).get('id')

    if not doc_id:
        return {'error': 'No document ID in response'}

    print(f"📄 Created document {doc_id}, waiting for generation...")

    # Poll for document generation (with timeout)
    import time
    max_attempts = 60  # 5 minutes
    attempts = 0

    doc_url = f'https://api.scopestack.io/{account_slug}/v1/project-documents/{doc_id}'

    while attempts < max_attempts:
        time.sleep(5)  # Wait 5 seconds between polls
        attempts += 1

        doc_response = requests.get(doc_url, headers=headers)

        if doc_response.status_code != 200:
            continue

        doc_details = doc_response.json()
        status = doc_details.get('data', {}).get('attributes', {}).get('status')

        print(f"  Poll attempt {attempts}/{max_attempts}: status = {status}")

        if status == 'finished':
            # Document is ready, get download URL
            download_url = doc_details.get('data', {}).get('attributes', {}).get('document-url')

            if not download_url:
                return {'error': 'Document finished but no download URL in response'}

            print(f"✓ Document ready, URL: {download_url[:50]}...")
            return {'download_url': download_url}

        elif status == 'error':
            return {'error': f'Document generation failed with status: error'}

    return {'error': 'Document generation timed out after 5 minutes'}


@app.route('/api/ai-smart-convert', methods=['POST'])
def ai_smart_convert():
    """
    Intelligent AI-driven conversion flow:
    1. Analyze V1 template structure (fields, loops, conditionals)
    2. Fetch V1 and V2 merge data structures
    3. Use AI to suggest semantic field mappings
    4. Convert template with AI-suggested mappings
    5. Generate and compare documents
    6. Iteratively refine until high similarity

    Returns before/after comparison with all artifacts cached.
    """
    try:
        data = request.json
        v1_template_id = data.get('v1_template_id')
        project_id = data.get('project_id')
        provider = data.get('ai_provider', 'openai')
        max_iterations = data.get('max_iterations', 4)

        if not all([v1_template_id, project_id]):
            return jsonify({'error': 'Missing required parameters (v1_template_id, project_id)'}), 400

        # Check AI key
        api_key = auth_manager.get_ai_api_key(provider)
        if not api_key:
            return jsonify({'error': f'No {provider} API key configured'}), 400

        # Initialize components
        from ai_converter import AIConverter
        from template_manager import TemplateManager
        from smart_converter import SmartConverter
        import uuid

        ai_converter = AIConverter(provider=provider, api_key=api_key)
        token = auth_manager.get_access_token()
        manager = TemplateManager()
        manager.authenticate(token=token)

        smart_converter = SmartConverter(ai_converter, manager)

        # Create session for this conversion
        session_id = f"smart_convert_{uuid.uuid4().hex[:8]}"
        cache_dir = Path(__file__).parent / 'document_cache' / session_id
        cache_dir.mkdir(parents=True, exist_ok=True)

        print(f"\n{'='*70}")
        print(f"🚀 SMART AI-DRIVEN CONVERSION")
        print(f"{'='*70}")
        print(f"📁 Session: {session_id}")
        print(f"📁 Cache: {cache_dir}")

        # Step 1: Download V1 template
        print(f"\n1️⃣ Downloading V1 template {v1_template_id}...")
        v1_template_path = os.path.join(app.config['UPLOAD_FOLDER'], f'v1_template_{v1_template_id}.docx')
        manager.download_template(v1_template_id, v1_template_path)

        # Step 2: Smart conversion with AI analysis
        print(f"\n2️⃣ Running smart conversion with AI analysis...")
        v2_template_path = os.path.join(app.config['UPLOAD_FOLDER'], f'v2_smart_{session_id}.docx')
        v2_template_path, ai_mappings = smart_converter.smart_convert(
            v1_template_path,
            project_id,
            v2_template_path
        )

        # Step 3: Upload V2 template
        print(f"\n3️⃣ Uploading converted V2 template...")
        from template_version_tracker import TemplateVersionTracker
        version_tracker = TemplateVersionTracker()
        v2_name = version_tracker.generate_versioned_name(f"V2_SmartConvert_{project_id}")

        create_result = manager.create_template(
            name=v2_name,
            filename=f"smart_convert_{project_id}.docx",
            template_format="v2",
            format_type="tag_template"
        )
        v2_template_id = create_result['data']['id']
        manager.upload_template_file(v2_template_id, v2_template_path)
        print(f"✓ V2 template uploaded: ID {v2_template_id}")

        # Step 4: Generate V1 baseline document
        print(f"\n4️⃣ Generating V1 baseline document...")
        v1_doc_result = _generate_document_direct(v1_template_id, project_id)
        if v1_doc_result.get('error'):
            return jsonify({'error': f"V1 generation failed: {v1_doc_result['error']}"}), 500

        v1_doc_path = cache_dir / f'V1_Baseline_Template{v1_template_id}.docx'
        doc_content = requests.get(v1_doc_result['download_url']).content
        with open(v1_doc_path, 'wb') as f:
            f.write(doc_content)
        print(f"✓ V1 document saved: {v1_doc_path}")

        # Step 5: Generate V2 document
        print(f"\n5️⃣ Generating V2 document...")
        v2_doc_result = _generate_document_direct(v2_template_id, project_id)
        if v2_doc_result.get('error'):
            return jsonify({'error': f"V2 generation failed: {v2_doc_result['error']}"}), 500

        v2_doc_path = cache_dir / f'V2_Converted_Template{v2_template_id}.docx'
        doc_content = requests.get(v2_doc_result['download_url']).content
        with open(v2_doc_path, 'wb') as f:
            f.write(doc_content)
        print(f"✓ V2 document saved: {v2_doc_path}")

        # Step 6: Compare documents
        print(f"\n6️⃣ Comparing documents...")
        from document_comparator import DocumentComparator
        comparator = DocumentComparator()
        comparison = comparator.compare_documents(str(v1_doc_path), str(v2_doc_path))

        similarity = comparison.get('similarity_ratio', 0.0)
        print(f"✓ Initial similarity: {similarity*100:.1f}%")

        # Step 7: Iterative refinement if needed
        iteration_history = []
        current_v2_template_id = v2_template_id

        if similarity < 0.95:
            print(f"\n7️⃣ Similarity below 95%, starting iterative refinement...")
            # TODO: Implement iterative refinement with AI feedback
            # For now, just record the initial result
            iteration_history.append({
                'iteration': 1,
                'similarity': similarity,
                'status': 'needs_refinement',
                'template_id': current_v2_template_id
            })
        else:
            print(f"\n✅ Conversion successful! Similarity: {similarity*100:.1f}%")
            iteration_history.append({
                'iteration': 1,
                'similarity': similarity,
                'status': 'success',
                'template_id': current_v2_template_id
            })

        # Return results
        return jsonify({
            'success': True,
            'session_id': session_id,
            'v2_template_id': current_v2_template_id,
            'v2_template_name': v2_name,
            'initial_similarity': similarity,
            'ai_mappings': ai_mappings,
            'iteration_history': iteration_history,
            'cache_dir': str(cache_dir),
            'artifacts': {
                'v1_template': str(v1_template_path),
                'v2_template': str(v2_template_path),
                'v1_document': str(v1_doc_path),
                'v2_document': str(v2_doc_path)
            }
        })

    except Exception as e:
        import traceback
        error_trace = traceback.format_exc()
        print(f"❌ Smart conversion error:")
        print(error_trace)
        return jsonify({
            'error': f'Smart conversion error: {str(e)}',
            'traceback': error_trace
        }), 500


@app.route('/api/ai-recursive-improve', methods=['POST'])
def ai_recursive_improve():
    """
    Recursively improve template conversion:
    1. Detect syntax errors
    2. Fix errors with AI
    3. Re-upload fixed template
    4. Re-generate document
    5. Compare results
    6. Repeat until no errors or max iterations

    Supports sessions for continuation.
    """
    try:
        data = request.json
        v1_template_id = data.get('v1_template_id')
        v2_template_id = data.get('v2_template_id')
        project_id = data.get('project_id')
        provider = data.get('ai_provider', 'openai')
        max_iterations = data.get('max_iterations', 4)
        session_id = data.get('session_id')  # Optional: resume existing session
        session_name = data.get('session_name')  # Optional: name for new session

        if not all([v1_template_id, v2_template_id, project_id]):
            return jsonify({'error': 'Missing required parameters'}), 400

        # Check AI key
        api_key = auth_manager.get_ai_api_key(provider)
        if not api_key:
            return jsonify({'error': f'No {provider} API key configured'}), 400

        # Initialize components
        from ai_converter import AIConverter
        from template_manager import TemplateManager
        from template_converter import TemplateConverter
        from mapping_database import MappingDatabase

        ai_converter = AIConverter(provider=provider, api_key=api_key)
        token = auth_manager.get_access_token()
        manager = TemplateManager()
        manager.authenticate(token=token)
        mapping_db = MappingDatabase()

        # Session handling
        previous_iterations_count = 0
        if session_id:
            # Resume existing session
            session_data = session_manager.get_session(session_id)
            if not session_data:
                return jsonify({'error': f'Session not found: {session_id}'}), 404

            iteration_history = session_data.get('iterations', []).copy()
            previous_iterations_count = len(iteration_history)
            current_v2_template_id = session_data.get('v2_template_id', v2_template_id)
            print(f"📂 Resuming session: {session_id}")
            print(f"   Previous iterations: {previous_iterations_count}")
            print(f"   Current similarity: {session_data.get('current_similarity', 0)*100:.1f}%")

            # Include user feedback in AI context
            session_summary = session_manager.get_session_summary(session_id)
            if session_summary:
                print(f"\n📋 Session Context for AI:")
                print(session_summary[:500])
        else:
            # Create new session
            iteration_history = []

            # Use the existing V2 template as our "In Progress" template
            # We'll update it in place throughout iterations
            current_v2_template_id = v2_template_id
            print(f"\n🔧 Using template {v2_template_id} as working template (will update in place)")

            session_id = session_manager.create_session(
                v1_template_id=v1_template_id,
                v2_template_id=v2_template_id,
                project_id=project_id,
                session_name=session_name
            )
            print(f"📂 Created new session: {session_id}")

        # Get V1 template and generate document once
        v1_template_path = os.path.join(app.config['UPLOAD_FOLDER'], f'v1_template_{v1_template_id}.docx')
        if not os.path.exists(v1_template_path):
            manager.download_template(v1_template_id, v1_template_path)

        # Create document cache directory for this session
        cache_dir = Path(__file__).parent / 'document_cache' / session_id
        cache_dir.mkdir(parents=True, exist_ok=True)
        print(f"\n📁 Document cache: {cache_dir}")

        # Generate V1 document once (for comparison baseline)
        print(f"\n📄 Generating V1 baseline document...")
        v1_doc_result = _generate_document_direct(v1_template_id, project_id)

        if v1_doc_result.get('error'):
            return jsonify({'error': f"Failed to generate V1 baseline: {v1_doc_result['error']}"}), 500

        # Save to both temp and cache
        v1_doc_path = os.path.join(app.config['UPLOAD_FOLDER'], f'V1_Baseline_{project_id}.docx')
        v1_doc_cached = cache_dir / f'V1_Baseline_Template{v1_template_id}.docx'

        doc_content = requests.get(v1_doc_result['download_url']).content
        with open(v1_doc_path, 'wb') as f:
            f.write(doc_content)
        with open(v1_doc_cached, 'wb') as f:
            f.write(doc_content)

        print(f"✓ V1 baseline saved: {v1_doc_path}")
        print(f"✓ V1 cached: {v1_doc_cached}")

        for iteration in range(1, max_iterations + 1):
            print(f"\n{'='*70}")
            print(f"🔄 RECURSIVE ITERATION {iteration}/{max_iterations}")
            print(f"{'='*70}")

            # Download current V2 template
            v2_template_path = os.path.join(
                app.config['UPLOAD_FOLDER'],
                f'v2_template_iter{iteration}_{current_v2_template_id}.docx'
            )
            manager.download_template(current_v2_template_id, v2_template_path)

            # Generate V2 document
            print(f"\n📄 Generating V2 document (iteration {iteration})...")
            v2_doc_result = _generate_document_direct(current_v2_template_id, project_id)

            if v2_doc_result.get('error'):
                print(f"❌ Failed to generate V2 document: {v2_doc_result['error']}")
                iteration_history.append({
                    'iteration': iteration,
                    'similarity': 0.0,
                    'syntax_errors': 0,
                    'fixes_applied': 0,
                    'status': 'generation_failed',
                    'error': v2_doc_result['error'],
                    'template_id': current_v2_template_id
                })
                break

            v2_doc_path = os.path.join(
                app.config['UPLOAD_FOLDER'],
                f'V2_Iter{iteration}_{project_id}.docx'
            )
            v2_doc_cached = cache_dir / f'V2_Iter{iteration}_Template{current_v2_template_id}.docx'

            doc_content = requests.get(v2_doc_result['download_url']).content
            with open(v2_doc_path, 'wb') as f:
                f.write(doc_content)
            with open(v2_doc_cached, 'wb') as f:
                f.write(doc_content)

            print(f"✓ V2 document saved: {v2_doc_path}")
            print(f"✓ V2 cached: {v2_doc_cached}")

            # Compare documents and check for errors
            comparison = ai_converter.compare_documents(v1_doc_path, v2_doc_path)
            syntax_errors = comparison.get('v2_template_errors', [])

            print(f"\n📊 Comparison Results:")
            print(f"   Similarity: {comparison['similarity_ratio']*100:.1f}%")
            print(f"   Syntax Errors: {len(syntax_errors)}")

            # Check if we're done
            if not syntax_errors and comparison['similarity_ratio'] >= 0.95:
                print(f"\n✅ SUCCESS! No errors and high similarity reached.")
                iteration_history.append({
                    'iteration': iteration,
                    'similarity': comparison['similarity_ratio'],
                    'syntax_errors': 0,
                    'fixes_applied': 0,
                    'status': 'success',
                    'template_id': current_v2_template_id
                })
                break

            if not syntax_errors:
                # LOW SIMILARITY but NO SYNTAX ERRORS - check for Sablon markers
                print(f"\n🔍 Low similarity ({comparison['similarity_ratio']*100:.1f}%) - checking for Sablon markers")

                # Re-validate to check for unconverted Sablon markers
                validator = TemplateValidator()
                validation_result = validator.validate_template(v2_template_path)

                # Check for Sablon-related errors
                sablon_errors = [e for e in validation_result.get('errors', [])
                               if 'Sablon' in e or ':each' in e or ':if' in e]

                if sablon_errors:
                    # FOUND UNCONVERTED SABLON MARKERS
                    print(f"⚠️  Found {len(sablon_errors)} unconverted Sablon markers:")
                    for err in sablon_errors[:3]:
                        print(f"   • {err}")

                    print(f"\n🔧 Re-converting template with fixed converter...")

                    # Download V1 template for reconversion
                    v1_for_reconvert = os.path.join(
                        app.config['UPLOAD_FOLDER'],
                        f'v1_reconvert_iter{iteration}.docx'
                    )
                    manager.download_template(v1_template_id, v1_for_reconvert)

                    # Re-convert with fixed converter (now removes Sablon markers)
                    reconverted_path = os.path.join(
                        app.config['UPLOAD_FOLDER'],
                        f'v2_reconverted_iter{iteration+1}.docx'
                    )

                    converter = TemplateConverter(v1_for_reconvert, reconverted_path)
                    if not converter.convert():
                        print("❌ Reconversion failed")
                        iteration_history.append({
                            'iteration': iteration,
                            'similarity': comparison['similarity_ratio'],
                            'status': 'reconversion_failed',
                            'template_id': current_v2_template_id
                        })
                        break

                    # Re-validate after reconversion
                    revalidation = validator.validate_template(reconverted_path)
                    if revalidation['error_count'] > 0:
                        print(f"⚠️  Still has {revalidation['error_count']} errors after reconversion")
                        for err in revalidation['errors'][:3]:
                            print(f"   • {err}")

                    # Update the In Progress template (working slot pattern)
                    print(f"\n📤 Updating In Progress template {current_v2_template_id}...")

                    try:
                        # Upload reconverted file to EXISTING template (working slot pattern)
                        # This replaces the file without creating a new template version
                        manager.upload_template_file(current_v2_template_id, reconverted_path)
                        print(f"✓ In Progress template updated with reconverted file")

                        iteration_history.append({
                            'iteration': iteration,
                            'similarity': comparison['similarity_ratio'],
                            'syntax_errors': 0,
                            'sablon_markers_removed': len(sablon_errors),
                            'status': 'reconverted_sablon_markers_removed',
                            'template_id': current_v2_template_id  # SAME template ID
                        })

                        # Continue to next iteration with updated template
                        continue

                    except Exception as e:
                        print(f"❌ Failed to update template: {e}")
                        import traceback
                        traceback.print_exc()
                        iteration_history.append({
                            'iteration': iteration,
                            'similarity': comparison['similarity_ratio'],
                            'status': 'upload_failed',
                            'error': str(e),
                            'template_id': current_v2_template_id
                        })
                        break

                else:
                    # No Sablon markers but still low similarity
                    # Likely needs field mapping adjustments (future enhancement)
                    print("\n💭 No Sablon markers found - may need field mapping adjustments (future feature)")

                    iteration_history.append({
                        'iteration': iteration,
                        'similarity': comparison['similarity_ratio'],
                        'syntax_errors': 0,
                        'status': 'no_errors_low_similarity_needs_mapping_improvement',
                        'template_id': current_v2_template_id
                    })
                    break

            # Get current mappings
            db_mappings_dict = mapping_db.get_all_mappings()
            current_mappings = []
            for v1_field, mapping_data in db_mappings_dict.items():
                current_mappings.append({
                    'v1_field': v1_field,
                    'v2_field': mapping_data.get('v2_field', ''),
                    'confidence': 'medium'
                })

            # Fetch merge data for AI context
            print(f"\n📊 Fetching merge data structures for AI context...")
            merge_data_context = None
            try:
                from merge_data_learner import MergeDataLearner
                learner = MergeDataLearner(manager)
                v1_data = learner._fetch_merge_data_v1(project_id)
                v2_data = learner._fetch_merge_data_v2(project_id)

                # Create structure samples (first 2 levels only for context)
                import json
                def get_structure_sample(data, max_depth=2):
                    """Extract structure sample showing available fields"""
                    if isinstance(data, dict):
                        if max_depth <= 0:
                            return "{...}"
                        result = {}
                        for key in list(data.keys())[:10]:  # Limit to 10 keys per level
                            if isinstance(data[key], (dict, list)):
                                result[key] = get_structure_sample(data[key], max_depth - 1)
                            else:
                                result[key] = f"<{type(data[key]).__name__}>"
                        return result
                    elif isinstance(data, list) and data:
                        if max_depth <= 0:
                            return "[...]"
                        return [get_structure_sample(data[0], max_depth - 1)]
                    else:
                        return f"<{type(data).__name__}>"

                merge_data_context = {
                    'v1_structure_sample': json.dumps(get_structure_sample(v1_data, 2), indent=2),
                    'v2_structure_sample': json.dumps(get_structure_sample(v2_data, 2), indent=2)
                }
                print(f"✓ Fetched merge data structures for AI context")
            except Exception as e:
                print(f"⚠️  Could not fetch merge data: {e}")

            # Fix syntax errors using AI
            print(f"\n🤖 Asking AI to fix {len(syntax_errors)} syntax errors...")
            print(f"   Errors to fix:")
            for i, err in enumerate(syntax_errors[:3], 1):
                print(f"     {i}. {err['error_text'][:80]}...")

            v2_xml = ai_converter.analyze_template_xml(v2_template_path)
            fix_result = ai_converter.fix_syntax_errors(v2_xml, syntax_errors, current_mappings, merge_data_context)

            fixes_applied = len(fix_result.get('fixes_applied', []))
            ai_reasoning = fix_result.get('reasoning', 'N/A')
            ai_confidence = fix_result.get('confidence', 0.0)

            print(f"\n✓ AI Response:")
            print(f"   Fixes applied: {fixes_applied}")
            print(f"   Confidence: {ai_confidence*100:.0f}%")
            print(f"   Reasoning: {ai_reasoning[:300]}")

            if fix_result.get('fixes_applied'):
                print(f"\n   Specific fixes:")
                for i, fix in enumerate(fix_result['fixes_applied'][:5], 1):
                    print(f"     {i}. {fix.get('error', 'Unknown')[:60]}...")
                    print(f"        Fix: {fix.get('fix', 'Unknown')[:60]}...")

            if fixes_applied == 0:
                print(f"\n⚠️  AI could not suggest fixes. Stopping.")
                iteration_history.append({
                    'iteration': iteration,
                    'similarity': comparison['similarity_ratio'],
                    'syntax_errors': len(syntax_errors),
                    'fixes_applied': 0,
                    'ai_reasoning': ai_reasoning,
                    'ai_confidence': ai_confidence,
                    'status': 'no_fixes_possible',
                    'template_id': current_v2_template_id
                })
                break

            # Write fixed XML back to template
            import zipfile
            import tempfile

            fixed_template_path = os.path.join(
                app.config['UPLOAD_FOLDER'],
                f'v2_fixed_iter{iteration+1}.docx'
            )

            with zipfile.ZipFile(v2_template_path, 'r') as zip_in:
                with zipfile.ZipFile(fixed_template_path, 'w') as zip_out:
                    for item in zip_in.infolist():
                        data = zip_in.read(item.filename)
                        if item.filename == 'word/document.xml':
                            data = fix_result['fixed_xml'].encode('utf-8')
                        zip_out.writestr(item, data)

            print(f"✓ Fixed template saved: {fixed_template_path}")

            # Validate the fixed template
            print(f"\n✅ Validating fixed template...")
            validator = TemplateValidator()
            validation_result = validator.validate_template(fixed_template_path)

            if validation_result['error_count'] > 0:
                print(f"⚠️  Validation found {validation_result['error_count']} errors:")
                for err in validation_result['errors'][:3]:
                    print(f"   • {err}")

                # Record this iteration with validation failures
                iteration_history.append({
                    'iteration': len(iteration_history) + 1,
                    'similarity': comparison['similarity_ratio'],
                    'syntax_errors': len(syntax_errors),
                    'fixes_applied': fixes_applied,
                    'validation_errors': validation_result['error_count'],
                    'validation_details': validation_result['errors'],
                    'ai_reasoning': ai_reasoning,
                    'ai_confidence': ai_confidence,
                    'status': 'validation_failed',
                    'template_id': current_v2_template_id
                })

                # Continue to next iteration to try to fix validation errors
                print(f"   Continuing to next iteration to fix validation errors...")
                continue
            else:
                print(f"✓ Validation passed!")
                if validation_result['warning_count'] > 0:
                    print(f"   ({validation_result['warning_count']} warnings)")

            # Update In Progress template with fixes (instead of creating new version)
            print(f"\n📤 Updating In Progress template {current_v2_template_id} with fixes...")

            try:
                # Upload the fixed template file to the existing In Progress template
                manager.upload_template_file(current_v2_template_id, fixed_template_path)

                print(f"✓ In Progress template updated with AI fixes")

            except Exception as e:
                print(f"❌ Upload failed: {e}")
                iteration_history.append({
                    'iteration': len(iteration_history) + 1,
                    'similarity': comparison['similarity_ratio'],
                    'syntax_errors': len(syntax_errors),
                    'fixes_applied': fixes_applied,
                    'ai_reasoning': ai_reasoning,
                    'ai_confidence': ai_confidence,
                    'status': 'upload_failed',
                    'error': str(e),
                    'template_id': current_v2_template_id
                })
                break

            # Template ID stays the same (In Progress template updated, not replaced)

            iter_record = {
                'iteration': len(iteration_history) + 1,  # Use total count for resumed sessions
                'similarity': comparison['similarity_ratio'],
                'syntax_errors': len(syntax_errors),
                'fixes_applied': fixes_applied,
                'fixes_detail': fix_result.get('fixes_applied', []),
                'ai_reasoning': ai_reasoning,
                'ai_confidence': ai_confidence,
                'status': 'continued',
                'template_id': current_v2_template_id
            }

            iteration_history.append(iter_record)

            # Record successful iteration in learning cache
            if fixes_applied > 0:
                ai_converter.learner.record_successful_iteration({
                    'similarity_improvement': iter_record['similarity'],
                    'fixes_applied': iter_record['fixes_detail'],
                    'final_similarity': iter_record['similarity']
                })

        # Final result
        final_iteration = iteration_history[-1] if iteration_history else {}
        final_similarity = final_iteration.get('similarity', 0.0)
        final_status = final_iteration.get('status', 'unknown')

        # Update session with results (only new iterations since resume)
        new_iterations = iteration_history[previous_iterations_count:]
        session_manager.update_session(
            session_id=session_id,
            iterations=new_iterations,
            final_similarity=final_similarity,
            final_template_id=current_v2_template_id,
            status='completed' if final_status == 'success' else 'active'
        )

        return jsonify({
            'success': True,
            'session_id': session_id,
            'iterations': iteration_history,
            'final_template_id': current_v2_template_id,
            'final_similarity': final_similarity,
            'final_status': final_status,
            'can_continue': final_status not in ['success']  # Can continue if not success
        })

    except Exception as e:
        import traceback
        error_trace = traceback.format_exc()
        print(f"❌ Recursive improvement error:")
        print(error_trace)
        return jsonify({
            'error': f'Recursive improvement error: {str(e)}',
            'traceback': error_trace
        }), 500


@app.route('/api/ai-continue-improvement', methods=['POST'])
def ai_continue_improvement():
    """
    Continue an existing AI improvement session with user feedback
    """
    try:
        data = request.json
        session_id = data.get('session_id')
        user_feedback = data.get('user_feedback', '')
        additional_iterations = data.get('additional_iterations', 4)

        if not session_id:
            return jsonify({'error': 'session_id is required'}), 400

        # Get session
        session_data = session_manager.get_session(session_id)
        if not session_data:
            return jsonify({'error': f'Session not found: {session_id}'}), 404

        # Add user feedback to session
        if user_feedback:
            session_manager.add_user_feedback(
                session_id=session_id,
                feedback=user_feedback
            )
            print(f"\n💬 User Feedback Added:")
            print(f"   {user_feedback[:200]}")

        # Extract session data
        v1_template_id = session_data['v1_template_id']
        v2_template_id = session_data['v2_template_id']
        project_id = session_data['project_id']

        # Get AI settings from existing session or defaults
        ai_settings_response = get_ai_settings()
        ai_settings = ai_settings_response.get_json()
        provider = ai_settings.get('provider', 'openai')

        # Check AI key
        api_key = auth_manager.get_ai_api_key(provider)
        if not api_key:
            return jsonify({'error': f'No {provider} API key configured'}), 400

        # Initialize components
        from ai_converter import AIConverter
        from template_manager import TemplateManager
        from template_converter import TemplateConverter
        from mapping_database import MappingDatabase

        ai_converter = AIConverter(provider=provider, api_key=api_key)
        token = auth_manager.get_access_token()
        manager = TemplateManager()
        manager.authenticate(token=token)
        mapping_db = MappingDatabase()

        # Resume existing session
        iteration_history = session_data.get('iterations', []).copy()
        previous_iterations_count = len(iteration_history)
        current_v2_template_id = session_data.get('v2_template_id', v2_template_id)

        print(f"📂 Resuming session: {session_id}")
        print(f"   Previous iterations: {previous_iterations_count}")
        print(f"   Current similarity: {session_data.get('current_similarity', 0)*100:.1f}%")

        # Include user feedback in AI context
        session_summary = session_manager.get_session_summary(session_id)
        if session_summary:
            print(f"\n📋 Session Context for AI:")
            print(session_summary[:500])

        # Get V1 template and generate document once
        v1_template_path = os.path.join(app.config['UPLOAD_FOLDER'], f'v1_template_{v1_template_id}.docx')
        if not os.path.exists(v1_template_path):
            manager.download_template(v1_template_id, v1_template_path)

        # Create document cache directory for this session
        cache_dir = Path(__file__).parent / 'document_cache' / session_id
        cache_dir.mkdir(parents=True, exist_ok=True)
        print(f"\n📁 Document cache: {cache_dir}")

        # Generate V1 document once (for comparison baseline)
        print(f"\n📄 Generating V1 baseline document...")
        v1_doc_result = _generate_document_direct(v1_template_id, project_id)

        if v1_doc_result.get('error'):
            return jsonify({'error': f"Failed to generate V1 baseline: {v1_doc_result['error']}"}), 500

        # Save to both temp and cache
        v1_doc_path = os.path.join(app.config['UPLOAD_FOLDER'], f'V1_Baseline_{project_id}.docx')
        v1_doc_cached = cache_dir / f'V1_Baseline_Template{v1_template_id}.docx'

        doc_content = requests.get(v1_doc_result['download_url']).content
        with open(v1_doc_path, 'wb') as f:
            f.write(doc_content)
        with open(v1_doc_cached, 'wb') as f:
            f.write(doc_content)

        print(f"✓ V1 baseline saved: {v1_doc_path}")
        print(f"✓ V1 cached: {v1_doc_cached}")

        # Run additional iterations
        for iteration in range(1, additional_iterations + 1):
            print(f"\n{'='*70}")
            print(f"🔄 CONTINUATION ITERATION {iteration}/{additional_iterations}")
            print(f"   (Total: {previous_iterations_count + iteration})")
            print(f"{'='*70}")

            # Download current V2 template
            v2_template_path = os.path.join(
                app.config['UPLOAD_FOLDER'],
                f'v2_template_cont{iteration}_{current_v2_template_id}.docx'
            )
            manager.download_template(current_v2_template_id, v2_template_path)

            # Generate V2 document
            print(f"\n📄 Generating V2 document (continuation iteration {iteration})...")
            v2_doc_result = _generate_document_direct(current_v2_template_id, project_id)

            if v2_doc_result.get('error'):
                print(f"❌ Failed to generate V2 document: {v2_doc_result['error']}")
                iteration_history.append({
                    'iteration': previous_iterations_count + iteration,
                    'similarity': 0.0,
                    'syntax_errors': 0,
                    'fixes_applied': 0,
                    'status': 'generation_failed',
                    'error': v2_doc_result['error'],
                    'template_id': current_v2_template_id
                })
                break

            v2_doc_path = os.path.join(
                app.config['UPLOAD_FOLDER'],
                f'V2_Cont{iteration}_{project_id}.docx'
            )

            with open(v2_doc_path, 'wb') as f:
                f.write(requests.get(v2_doc_result['download_url']).content)

            print(f"✓ V2 document saved: {v2_doc_path}")

            # Compare documents and check for errors
            comparison = ai_converter.compare_documents(v1_doc_path, v2_doc_path)
            syntax_errors = comparison.get('v2_template_errors', [])

            print(f"\n📊 Comparison Results:")
            print(f"   Similarity: {comparison['similarity_ratio']*100:.1f}%")
            print(f"   Syntax Errors: {len(syntax_errors)}")

            # Check if we're done
            if not syntax_errors and comparison['similarity_ratio'] >= 0.95:
                print(f"\n✅ SUCCESS! No errors and high similarity reached.")
                iteration_history.append({
                    'iteration': previous_iterations_count + iteration,
                    'similarity': comparison['similarity_ratio'],
                    'syntax_errors': 0,
                    'fixes_applied': 0,
                    'status': 'success',
                    'template_id': current_v2_template_id
                })
                break

            if not syntax_errors:
                print(f"\n✓ No syntax errors, but similarity only {comparison['similarity_ratio']*100:.1f}%")
                iteration_history.append({
                    'iteration': previous_iterations_count + iteration,
                    'similarity': comparison['similarity_ratio'],
                    'syntax_errors': 0,
                    'fixes_applied': 0,
                    'status': 'no_errors_low_similarity',
                    'template_id': current_v2_template_id
                })
                continue

            # Get current mappings
            db_mappings_dict = mapping_db.get_all_mappings()
            current_mappings = []
            for v1_field, mapping_data in db_mappings_dict.items():
                current_mappings.append({
                    'v1_field': v1_field,
                    'v2_field': mapping_data.get('v2_field', ''),
                    'confidence': 'medium'
                })

            # Fetch merge data for AI context
            print(f"\n📊 Fetching merge data structures for AI context...")
            merge_data_context = None
            try:
                from merge_data_learner import MergeDataLearner
                learner = MergeDataLearner(manager)
                v1_data = learner._fetch_merge_data_v1(project_id)
                v2_data = learner._fetch_merge_data_v2(project_id)

                # Create structure samples (first 2 levels only for context)
                import json
                def get_structure_sample(data, max_depth=2):
                    """Extract structure sample showing available fields"""
                    if isinstance(data, dict):
                        if max_depth <= 0:
                            return "{...}"
                        result = {}
                        for key in list(data.keys())[:10]:  # Limit to 10 keys per level
                            if isinstance(data[key], (dict, list)):
                                result[key] = get_structure_sample(data[key], max_depth - 1)
                            else:
                                result[key] = f"<{type(data[key]).__name__}>"
                        return result
                    elif isinstance(data, list) and data:
                        if max_depth <= 0:
                            return "[...]"
                        return [get_structure_sample(data[0], max_depth - 1)]
                    else:
                        return f"<{type(data).__name__}>"

                merge_data_context = {
                    'v1_structure_sample': json.dumps(get_structure_sample(v1_data, 2), indent=2),
                    'v2_structure_sample': json.dumps(get_structure_sample(v2_data, 2), indent=2)
                }
                print(f"✓ Fetched merge data structures for AI context")
            except Exception as e:
                print(f"⚠️  Could not fetch merge data: {e}")

            # Fix syntax errors using AI
            print(f"\n🤖 Asking AI to fix {len(syntax_errors)} syntax errors...")
            print(f"   Errors to fix:")
            for i, err in enumerate(syntax_errors[:3], 1):
                print(f"     {i}. {err['error_text'][:80]}...")

            v2_xml = ai_converter.analyze_template_xml(v2_template_path)
            fix_result = ai_converter.fix_syntax_errors(v2_xml, syntax_errors, current_mappings, merge_data_context)

            fixes_applied = len(fix_result.get('fixes_applied', []))
            ai_reasoning = fix_result.get('reasoning', 'N/A')
            ai_confidence = fix_result.get('confidence', 0.0)

            print(f"\n✓ AI Response:")
            print(f"   Fixes applied: {fixes_applied}")
            print(f"   Confidence: {ai_confidence*100:.0f}%")
            print(f"   Reasoning: {ai_reasoning[:300]}")

            if fix_result.get('fixes_applied'):
                print(f"\n   Specific fixes:")
                for i, fix in enumerate(fix_result['fixes_applied'][:5], 1):
                    print(f"     {i}. {fix.get('error', 'Unknown')[:60]}...")
                    print(f"        Fix: {fix.get('fix', 'Unknown')[:60]}...")

            if fixes_applied == 0:
                print(f"\n⚠️  AI could not suggest fixes. Stopping.")
                iteration_history.append({
                    'iteration': previous_iterations_count + iteration,
                    'similarity': comparison['similarity_ratio'],
                    'syntax_errors': len(syntax_errors),
                    'fixes_applied': 0,
                    'ai_reasoning': ai_reasoning,
                    'ai_confidence': ai_confidence,
                    'status': 'no_fixes_possible',
                    'template_id': current_v2_template_id
                })
                break

            # Write fixed XML back to template
            import zipfile
            import tempfile

            fixed_template_path = os.path.join(
                app.config['UPLOAD_FOLDER'],
                f'v2_fixed_cont{iteration+1}.docx'
            )

            with zipfile.ZipFile(v2_template_path, 'r') as zip_in:
                with zipfile.ZipFile(fixed_template_path, 'w') as zip_out:
                    for item in zip_in.infolist():
                        data = zip_in.read(item.filename)
                        if item.filename == 'word/document.xml':
                            data = fix_result['fixed_xml'].encode('utf-8')
                        zip_out.writestr(item, data)

            print(f"✓ Fixed template saved: {fixed_template_path}")

            # Validate the fixed template
            print(f"\n✅ Validating fixed template...")
            validator = TemplateValidator()
            validation_result = validator.validate_template(fixed_template_path)

            if validation_result['error_count'] > 0:
                print(f"⚠️  Validation found {validation_result['error_count']} errors:")
                for err in validation_result['errors'][:3]:
                    print(f"   • {err}")

                # Record this iteration with validation failures
                iteration_history.append({
                    'iteration': previous_iterations_count + iteration,
                    'similarity': comparison['similarity_ratio'],
                    'syntax_errors': len(syntax_errors),
                    'fixes_applied': fixes_applied,
                    'validation_errors': validation_result['error_count'],
                    'validation_details': validation_result['errors'],
                    'ai_reasoning': ai_reasoning,
                    'ai_confidence': ai_confidence,
                    'status': 'validation_failed',
                    'template_id': current_v2_template_id
                })

                # Continue to next iteration to try to fix validation errors
                print(f"   Continuing to next iteration to fix validation errors...")
                continue
            else:
                print(f"✓ Validation passed!")
                if validation_result['warning_count'] > 0:
                    print(f"   ({validation_result['warning_count']} warnings)")

            # Update In Progress template with fixes (instead of creating new version)
            print(f"\n📤 Updating In Progress template {current_v2_template_id} with fixes...")

            try:
                # Upload the fixed template file to the existing In Progress template
                manager.upload_template_file(current_v2_template_id, fixed_template_path)

                print(f"✓ In Progress template updated with AI fixes")

            except Exception as e:
                print(f"❌ Upload failed: {e}")
                iteration_history.append({
                    'iteration': previous_iterations_count + iteration,
                    'similarity': comparison['similarity_ratio'],
                    'syntax_errors': len(syntax_errors),
                    'fixes_applied': fixes_applied,
                    'ai_reasoning': ai_reasoning,
                    'ai_confidence': ai_confidence,
                    'status': 'upload_failed',
                    'error': str(e),
                    'template_id': current_v2_template_id
                })
                break

            # Template ID stays the same (In Progress template updated, not replaced)

            iter_record = {
                'iteration': previous_iterations_count + iteration,
                'similarity': comparison['similarity_ratio'],
                'syntax_errors': len(syntax_errors),
                'fixes_applied': fixes_applied,
                'fixes_detail': fix_result.get('fixes_applied', []),
                'ai_reasoning': ai_reasoning,
                'ai_confidence': ai_confidence,
                'status': 'continued',
                'template_id': current_v2_template_id
            }

            iteration_history.append(iter_record)

            # Record successful iteration in learning cache
            if fixes_applied > 0:
                ai_converter.learner.record_successful_iteration({
                    'similarity_improvement': iter_record['similarity'],
                    'fixes_applied': iter_record['fixes_detail'],
                    'final_similarity': iter_record['similarity']
                })

        # Final result
        final_iteration = iteration_history[-1] if iteration_history else {}
        final_similarity = final_iteration.get('similarity', 0.0)
        final_status = final_iteration.get('status', 'unknown')

        # Update session with results (only new iterations since resume)
        new_iterations = iteration_history[previous_iterations_count:]
        session_manager.update_session(
            session_id=session_id,
            iterations=new_iterations,
            final_similarity=final_similarity,
            final_template_id=current_v2_template_id,
            status='completed' if final_status == 'success' else 'active'
        )

        return jsonify({
            'success': True,
            'session_id': session_id,
            'iterations': iteration_history,
            'final_template_id': current_v2_template_id,
            'final_similarity': final_similarity,
            'final_status': final_status,
            'can_continue': final_status not in ['success']
        })

    except Exception as e:
        import traceback
        error_trace = traceback.format_exc()
        print(f"❌ Continue improvement error:")
        print(error_trace)
        return jsonify({
            'error': f'Continue improvement error: {str(e)}',
            'traceback': error_trace
        }), 500


@app.route('/api/sessions', methods=['GET'])
def get_sessions():
    """Get all active sessions"""
    try:
        sessions = session_manager.get_active_sessions()
        return jsonify({
            'success': True,
            'sessions': sessions
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/sessions/<session_id>', methods=['GET'])
def get_session(session_id):
    """Get details of a specific session"""
    try:
        session_data = session_manager.get_session(session_id)
        if not session_data:
            return jsonify({'error': 'Session not found'}), 404

        return jsonify({
            'success': True,
            'session': session_data
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/sessions/<session_id>', methods=['DELETE'])
def delete_session(session_id):
    """Delete a session"""
    try:
        session_manager.delete_session(session_id)
        return jsonify({
            'success': True,
            'message': f'Session {session_id} deleted'
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/learning-stats', methods=['GET'])
def get_learning_stats():
    """Get statistics from the learning cache"""
    try:
        from conversion_learner import ConversionLearner
        learner = ConversionLearner()
        stats = learner.get_statistics()

        return jsonify({
            'success': True,
            'stats': stats
        })

    except Exception as e:
        return jsonify({
            'error': f'Failed to get learning stats: {str(e)}'
        }), 500


@app.route('/api/check-template-name', methods=['POST'])
def check_template_name_exists():
    """
    Check if a template name already exists

    Returns whether to prompt user for replace vs create new
    """
    try:
        data = request.json
        template_name = data.get('template_name')

        if not template_name:
            return jsonify({'error': 'Template name required'}), 400

        from template_version_tracker import TemplateVersionTracker
        tracker = TemplateVersionTracker()

        exists = tracker.has_template(template_name)
        info = tracker.get_template_info(template_name) if exists else None

        return jsonify({
            'exists': exists,
            'template_info': info,
            'suggested_versioned_name': tracker.generate_versioned_name(template_name)
        })

    except Exception as e:
        return jsonify({
            'error': f'Failed to check template name: {str(e)}'
        }), 500


@app.route('/api/upload-with-versioning', methods=['POST'])
def upload_with_versioning():
    """
    Upload a template with version tracking

    Handles replace vs create new based on user choice
    """
    try:
        # This endpoint expects the template file and metadata
        if 'template' not in request.files:
            return jsonify({'error': 'No template file provided'}), 400

        file = request.files['template']
        template_name = request.form.get('template_name')
        action = request.form.get('action', 'create_new')  # 'replace' or 'create_new'

        if not template_name:
            return jsonify({'error': 'Template name required'}), 400

        from template_version_tracker import TemplateVersionTracker
        from template_manager import TemplateManager

        tracker = TemplateVersionTracker()
        manager = TemplateManager()

        token = auth_manager.get_access_token()
        manager.authenticate(token=token)

        # Determine final template name
        if action == 'create_new':
            final_name = tracker.generate_versioned_name(template_name)
        else:
            final_name = template_name

        # Save file temporarily
        temp_path = os.path.join(app.config['UPLOAD_FOLDER'], secure_filename(file.filename))
        file.save(temp_path)

        # Validate template before uploading
        validator = TemplateValidator()
        validation_result = validator.validate_template(temp_path)

        if not validation_result['valid']:
            # Template has errors - return them to user
            os.unlink(temp_path)
            return jsonify({
                'error': 'Template validation failed',
                'validation_errors': validation_result['errors'],
                'validation_warnings': validation_result['warnings'],
                'summary': validator.get_summary()
            }), 400

        # Upload to ScopeStack
        try:
            # Create template metadata
            create_result = manager.create_template(
                name=final_name,
                filename=os.path.basename(temp_path),
                template_format="v2",
                format_type="tag_template"
            )

            template_id = create_result['data']['id']

            # Upload the template file
            manager.upload_template_file(template_id, temp_path)

        except Exception as e:
            return jsonify({'error': f'Upload failed: {str(e)}'}), 500

        # Record in version tracker
        old_info = tracker.get_template_info(template_name)
        tracker.record_template(
            template_name=final_name,
            template_id=template_id,
            action='replaced' if action == 'replace' else 'created',
            replaced_id=old_info.get('current_id') if old_info and action == 'replace' else None
        )

        # Clean up temp file
        if os.path.exists(temp_path):
            os.unlink(temp_path)

        return jsonify({
            'success': True,
            'template_id': template_id,
            'template_name': final_name,
            'action': action
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Upload failed: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/merge-data-structure/<project_id>')
def get_merge_data_structure(project_id):
    """
    Get hierarchical structure of v1 and v2 merge data for visualization.

    Query params:
        view: 'v1', 'v2', or 'both' (default: 'both')

    Returns:
        {
            'success': true,
            'v1_structure': {...},  # Hierarchical field structure (if view includes v1)
            'v2_structure': {...},  # Hierarchical field structure (if view includes v2)
            'suggested_mappings': [...],  # From learning system
            'manual_mappings': [...]  # User-created mappings
        }
    """
    try:
        # Import the data structure extractor
        from data_structure_extractor import DataStructureExtractor

        # Get view parameter (v1, v2, or both)
        view = request.args.get('view', 'both').lower()
        if view not in ['v1', 'v2', 'both']:
            view = 'both'

        # Check authentication
        if not auth_manager.is_authenticated():
            return jsonify({'error': 'Not authenticated'}), 401

        # Fetch merge data from API
        token = auth_manager.get_access_token()
        fetcher = MergeDataFetcher()
        fetcher.authenticate(token=token)

        extractor = DataStructureExtractor()
        v1_structure = None
        v2_structure = None

        # Only fetch V1 if needed
        if view in ['v1', 'both']:
            try:
                v1_data = fetcher.fetch_v1_merge_data(project_id)
                v1_structure = extractor.extract_structure(
                    v1_data,
                    strip_prefix="data.attributes.content."
                )
            except Exception as e:
                return jsonify({'error': f'Failed to fetch v1 merge data: {str(e)}'}), 500

        # Only fetch V2 if needed
        if view in ['v2', 'both']:
            try:
                v2_data = fetcher.fetch_v2_merge_data(project_id)
                v2_structure = extractor.extract_structure(
                    v2_data,
                    strip_prefix="data.attributes.content."
                )
            except Exception as e:
                return jsonify({'error': f'Failed to fetch v2 merge data: {str(e)}'}), 500

        # Get all mappings from learning system database
        all_db_mappings = mapping_db.get_all_mappings()

        # Convert database format to list format for frontend
        suggested_mappings = []
        for v1_field, mapping_info in all_db_mappings.items():
            suggested_mappings.append({
                'v1_field': v1_field,
                'v2_field': mapping_info['v2_field'],
                'confidence': mapping_info.get('confidence_score', 1) / 10.0,  # Convert score to 0-1 range
                'source': mapping_info.get('source', 'database')
            })

        # Filter for manual mappings (confidence = 1.0, source = 'manual')
        manual_mappings = [
            m for m in suggested_mappings
            if m.get('source') == 'manual' or m.get('confidence') >= 1.0
        ]

        # Separate learned mappings (exclude manual ones)
        learned_mappings = [
            m for m in suggested_mappings
            if m.get('source') != 'manual' and m.get('confidence') < 1.0
        ]

        response = {
            'success': True,
            'project_id': project_id,
            'view': view,
            'suggested_mappings': learned_mappings,
            'manual_mappings': manual_mappings
        }

        if v1_structure is not None:
            response['v1_structure'] = v1_structure
            response['v1_field_count'] = len(v1_structure)

        if v2_structure is not None:
            response['v2_structure'] = v2_structure
            response['v2_field_count'] = len(v2_structure)

        return jsonify(response)

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to extract merge data structure: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/save-manual-mapping', methods=['POST'])
def save_manual_mapping():
    """
    Save a manually created field mapping from the merge data viewer.

    Request body:
        {
            'v1_field': 'project.name',
            'v2_field': 'project.project_name',
            'project_id': '12345',
            'sample_value': 'Test Project' (optional)
        }

    Returns:
        {
            'success': true,
            'message': 'Mapping saved successfully',
            'mapping': {...}
        }
    """
    try:
        # Check authentication
        if not auth_manager.is_authenticated():
            return jsonify({'error': 'Not authenticated'}), 401

        # Get request data
        data = request.get_json()

        if not data:
            return jsonify({'error': 'No data provided'}), 400

        v1_field = data.get('v1_field')
        v2_field = data.get('v2_field')
        project_id = data.get('project_id')
        sample_value = data.get('sample_value')

        # Validate required fields
        if not v1_field or not v2_field:
            return jsonify({'error': 'Both v1_field and v2_field are required'}), 400

        # Save to mapping database with manual source and high confidence
        mapping_db.add_mapping(
            v1_field=v1_field,
            v2_field=v2_field,
            value=sample_value,
            project_id=project_id,
            confidence="manual"  # Mark as manual to distinguish from learned
        )

        # Get the saved mapping back
        saved_mapping = mapping_db.get_mapping(v1_field)

        return jsonify({
            'success': True,
            'message': f'Mapping saved: {v1_field} → {v2_field}',
            'mapping': {
                'v1_field': v1_field,
                'v2_field': v2_field,
                'confidence': 1.0,
                'source': 'manual',
                'project_id': project_id,
                'times_seen': saved_mapping.get('times_seen', 1) if saved_mapping else 1
            }
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to save mapping: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/save-array-mapping', methods=['POST'])
def save_array_mapping():
    """
    Save an array-level mapping from the merge data viewer.

    Request body:
        {
            'v1_array': 'language_fields[]',
            'v2_array': 'language_fields[]',
            'project_id': '12345',
            'field_mappings': [
                {'v1': 'name', 'v2': 'name'},
                {'v1': 'code', 'v2': 'language_code'}
            ] (optional)
        }

    Returns:
        {
            'success': true,
            'message': 'Array mapping saved successfully',
            'mapping': {...}
        }
    """
    try:
        # Check authentication
        if not auth_manager.is_authenticated():
            return jsonify({'error': 'Not authenticated'}), 401

        # Get request data
        data = request.get_json()

        if not data:
            return jsonify({'error': 'No data provided'}), 400

        v1_array = data.get('v1_array')
        v2_array = data.get('v2_array')
        project_id = data.get('project_id')
        field_mappings = data.get('field_mappings', [])

        # Validate required fields
        if not v1_array or not v2_array:
            return jsonify({'error': 'Both v1_array and v2_array are required'}), 400

        # Save to mapping database
        saved_mapping = mapping_db.add_array_mapping(
            v1_array=v1_array,
            v2_array=v2_array,
            field_mappings=field_mappings,
            project_id=project_id
        )

        return jsonify({
            'success': True,
            'message': f'Array mapping saved: {v1_array} → {v2_array}',
            'mapping': saved_mapping
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to save array mapping: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/get-array-mappings', methods=['GET'])
def get_array_mappings():
    """Get all stored array mappings"""
    try:
        mappings = mapping_db.get_all_array_mappings()
        return jsonify({
            'success': True,
            'array_mappings': mappings,
            'count': len(mappings)
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/mapping/<path:v1_field>', methods=['DELETE'])
def delete_mapping(v1_field):
    """
    Delete a field mapping from the database.

    Returns:
        {
            'success': true,
            'message': 'Mapping deleted successfully'
        }
    """
    try:
        # Check authentication
        if not auth_manager.is_authenticated():
            return jsonify({'error': 'Not authenticated'}), 401

        # Delete the mapping
        deleted = mapping_db.delete_mapping(v1_field)

        if deleted:
            return jsonify({
                'success': True,
                'message': f'Mapping for "{v1_field}" deleted successfully'
            })
        else:
            return jsonify({
                'success': False,
                'error': f'No mapping found for "{v1_field}"'
            }), 404

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to delete mapping: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/projects/recent', methods=['GET'])
def get_recent_projects():
    """
    Get 50 most recent projects from ScopeStack.

    Returns:
        {
            'success': true,
            'projects': [
                {
                    'id': '8252',
                    'name': 'Website Redesign',
                    'client_name': 'Acme Corp',
                    'created_at': '2026-01-15',
                    'display': 'Acme Corp - Website Redesign - 01/15/26 - 8252'
                },
                ...
            ]
        }
    """
    try:
        # Check authentication
        if not auth_manager.is_authenticated():
            return jsonify({'error': 'Not authenticated'}), 401

        token = auth_manager.get_access_token()
        account_info = auth_manager.get_account_info()
        account_slug = account_info.get('account_slug')

        if not account_slug:
            return jsonify({'error': 'Account slug not found'}), 400

        # Fetch recent projects from ScopeStack API
        url = f"https://api.scopestack.io/{account_slug}/v1/projects"
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.api+json'
        }
        params = {
            'page[size]': 50,
            'sort': '-created-at'  # Most recent first
        }

        response = requests.get(url, headers=headers, params=params, timeout=30)
        response.raise_for_status()

        data = response.json()
        projects = []

        for item in data.get('data', []):
            attrs = item.get('attributes', {})
            project_id = item.get('id')
            name = attrs.get('name', 'Unnamed Project')
            client_name = attrs.get('client-name', 'Unknown Client')
            # Try created-at, fall back to updated-at
            created_at = attrs.get('created-at', '') or attrs.get('updated-at', '')

            # Get revenue (try multiple possible field names)
            revenue = (attrs.get('total-contract-value') or
                      attrs.get('total-revenue') or
                      attrs.get('project-total-revenue') or
                      0)
            if isinstance(revenue, str):
                try:
                    revenue = float(revenue)
                except (ValueError, TypeError):
                    revenue = 0

            # Format date
            date_str = ''
            if created_at:
                try:
                    from datetime import datetime
                    dt = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                    date_str = dt.strftime('%m/%d/%y')
                except:
                    date_str = created_at[:10] if len(created_at) >= 10 else ''

            # Format revenue for display
            revenue_str = f"${revenue:,.0f}" if revenue else ''
            display_parts = [client_name, name]
            if revenue_str:
                display_parts.append(revenue_str)
            if date_str:
                display_parts.append(date_str)
            display_parts.append(f"ID:{project_id}")

            projects.append({
                'id': project_id,
                'name': name,
                'client_name': client_name,
                'created_at': created_at,
                'revenue': revenue,
                'date_formatted': date_str,
                'display': ' - '.join(display_parts)
            })

        return jsonify({
            'success': True,
            'projects': projects
        })

    except requests.exceptions.RequestException as e:
        return jsonify({'error': f'API error: {str(e)}'}), 500
    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to get projects: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/projects/search', methods=['GET'])
def search_projects():
    """
    Search projects by name or client name.

    Query params:
        q: Search term

    Returns similar format to get_recent_projects
    """
    try:
        # Check authentication
        if not auth_manager.is_authenticated():
            return jsonify({'error': 'Not authenticated'}), 401

        query = request.args.get('q', '').strip()
        if not query:
            return jsonify({'success': True, 'projects': []})

        token = auth_manager.get_access_token()
        account_info = auth_manager.get_account_info()
        account_slug = account_info.get('account_slug')

        if not account_slug:
            return jsonify({'error': 'Account slug not found'}), 400

        # Fetch projects with search filter from ScopeStack API
        url = f"https://api.scopestack.io/{account_slug}/v1/projects"
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.api+json'
        }
        params = {
            'page[size]': 50,
            'sort': '-created-at',
            'filter[search]': query
        }

        response = requests.get(url, headers=headers, params=params, timeout=30)
        response.raise_for_status()

        data = response.json()
        projects = []

        for item in data.get('data', []):
            attrs = item.get('attributes', {})
            project_id = item.get('id')
            name = attrs.get('name', 'Unnamed Project')
            client_name = attrs.get('client-name', 'Unknown Client')
            # Try created-at, fall back to updated-at
            created_at = attrs.get('created-at', '') or attrs.get('updated-at', '')

            # Get revenue (try multiple possible field names)
            revenue = (attrs.get('total-contract-value') or
                      attrs.get('total-revenue') or
                      attrs.get('project-total-revenue') or
                      0)
            if isinstance(revenue, str):
                try:
                    revenue = float(revenue)
                except (ValueError, TypeError):
                    revenue = 0

            # Format date
            date_str = ''
            if created_at:
                try:
                    from datetime import datetime
                    dt = datetime.fromisoformat(created_at.replace('Z', '+00:00'))
                    date_str = dt.strftime('%m/%d/%y')
                except:
                    date_str = created_at[:10] if len(created_at) >= 10 else ''

            # Format revenue for display
            revenue_str = f"${revenue:,.0f}" if revenue else ''
            display_parts = [client_name, name]
            if revenue_str:
                display_parts.append(revenue_str)
            if date_str:
                display_parts.append(date_str)
            display_parts.append(f"ID:{project_id}")

            projects.append({
                'id': project_id,
                'name': name,
                'client_name': client_name,
                'created_at': created_at,
                'revenue': revenue,
                'date_formatted': date_str,
                'display': ' - '.join(display_parts)
            })

        return jsonify({
            'success': True,
            'projects': projects
        })

    except requests.exceptions.RequestException as e:
        return jsonify({'error': f'API error: {str(e)}'}), 500
    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to search projects: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/mappings/export', methods=['GET'])
def export_mappings():
    """
    Export all mappings as a JSON file download.
    """
    try:
        # Get all field mappings
        all_mappings = mapping_db.get_all_mappings()

        # Get all array mappings
        array_mappings = mapping_db.get_all_array_mappings()

        export_data = {
            'version': '1.0',
            'exported_at': datetime.now().isoformat(),
            'mappings': all_mappings,
            'array_mappings': array_mappings
        }

        # Return as downloadable JSON
        return jsonify(export_data), 200, {
            'Content-Disposition': 'attachment; filename=learned_mappings_export.json'
        }

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to export mappings: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/mappings/import', methods=['POST'])
def import_mappings():
    """
    Import mappings from a JSON file.

    Query param:
        mode: 'merge' (default) or 'replace'
    """
    try:
        mode = request.args.get('mode', 'merge')

        # Get JSON data from request
        data = request.get_json()

        if not data:
            return jsonify({'error': 'No data provided'}), 400

        mappings = data.get('mappings', {})
        array_mappings = data.get('array_mappings', {})

        imported_count = 0
        skipped_count = 0

        # If replace mode, clear existing mappings first
        if mode == 'replace':
            # Clear existing mappings by loading and replacing
            mapping_db.data['mappings'] = {}
            mapping_db.data['array_mappings'] = {}

        # Import field mappings
        for v1_field, mapping_info in mappings.items():
            existing = mapping_db.get_mapping(v1_field)

            if existing and mode == 'merge':
                # Skip if already exists in merge mode
                skipped_count += 1
                continue

            # Add mapping directly to database
            mapping_db.data['mappings'][v1_field] = mapping_info
            imported_count += 1

        # Import array mappings
        for v1_array, mapping_info in array_mappings.items():
            existing = mapping_db.get_array_mapping(v1_array)

            if existing and mode == 'merge':
                skipped_count += 1
                continue

            if 'array_mappings' not in mapping_db.data:
                mapping_db.data['array_mappings'] = {}
            mapping_db.data['array_mappings'][v1_array] = mapping_info
            imported_count += 1

        # Save database
        mapping_db._save_database()

        return jsonify({
            'success': True,
            'message': f'Imported {imported_count} mappings, skipped {skipped_count} existing',
            'imported': imported_count,
            'skipped': skipped_count
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to import mappings: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


@app.route('/api/mappings', methods=['GET'])
def get_all_mappings():
    """
    Get all stored mappings for the mappings modal.

    Returns:
        {
            'success': true,
            'mappings': [...],
            'array_mappings': [...],
            'count': total
        }
    """
    try:
        # Get all field mappings
        all_mappings = mapping_db.get_all_mappings()
        mappings_list = []
        for v1_field, mapping_info in all_mappings.items():
            mappings_list.append({
                'v1_field': v1_field,
                'v2_field': mapping_info['v2_field'],
                'confidence': mapping_info.get('confidence_score', 1) / 10.0,
                'source': mapping_info.get('source', 'learned'),
                'times_seen': mapping_info.get('times_seen', 1),
                'first_seen': mapping_info.get('first_seen'),
                'last_seen': mapping_info.get('last_seen')
            })

        # Get all array mappings
        array_mappings = mapping_db.get_all_array_mappings()
        array_mappings_list = []
        for v1_array, mapping_info in array_mappings.items():
            array_mappings_list.append({
                'v1_array': v1_array,
                'v2_array': mapping_info['v2_array'],
                'confidence': mapping_info.get('confidence_score', 1) / 10.0,
                'source': mapping_info.get('source', 'manual'),
                'times_seen': mapping_info.get('times_seen', 1)
            })

        return jsonify({
            'success': True,
            'mappings': mappings_list,
            'array_mappings': array_mappings_list,
            'count': len(mappings_list) + len(array_mappings_list)
        })

    except Exception as e:
        import traceback
        return jsonify({
            'error': f'Failed to get mappings: {str(e)}',
            'traceback': traceback.format_exc()
        }), 500


if __name__ == '__main__':
    print("=" * 80)
    print("ScopeStack Template Converter - Web Interface")
    print("=" * 80)
    print("\n🌐 Starting server at http://localhost:5001")
    print("\n📝 Features:")
    print("  - Upload and analyze templates")
    print("  - Convert Mail Merge to DocX Templater format")
    print("  - Validate against live project data")
    print("  - Learn field mappings from project data")
    print("  - Download converted templates")
    print("\n⚠️  Press Ctrl+C to stop the server\n")

    app.run(debug=True, host='127.0.0.1', port=5001)
