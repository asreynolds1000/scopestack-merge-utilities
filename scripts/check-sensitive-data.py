#!/usr/bin/env python3
"""
Pre-commit hook to detect sensitive data before commits.
Checks for real project IDs, API keys, secrets, and other sensitive patterns.

Usage:
    python scripts/check-sensitive-data.py [--staged-only]

Exit codes:
    0 - No sensitive data found
    1 - Sensitive data detected
"""

import subprocess
import sys
import re
from pathlib import Path

# Patterns that indicate sensitive data
SENSITIVE_PATTERNS = [
    # Real ScopeStack project IDs (6 digits starting with 10)
    # Allow 123456 as the example placeholder
    (r'\b10[0-9]{4}\b', 'Real project ID', ['123456', '{project_id}']),

    # API keys
    (r'sk-[a-zA-Z0-9]{20,}', 'OpenAI API key', []),
    (r'sk-ant-[a-zA-Z0-9-]{20,}', 'Anthropic API key', []),

    # Generic secrets in assignments
    (r'(api_key|apikey|secret|password|token)\s*=\s*["\'][a-zA-Z0-9]{16,}["\']', 'Hardcoded secret', []),

    # ScopeStack account slugs (except obvious test/demo ones)
    (r'api\.scopestack\.io/(?!v1|docs|#{|\{)[a-z0-9-]{5,}', 'Real account slug', ['scopestack-demo', 'zz-workato-testing-account']),
]

# Files/paths to skip
SKIP_PATTERNS = [
    r'\.git/',
    r'node_modules/',
    r'__pycache__/',
    r'\.pyc$',
    r'venv/',
    r'\.env\.example$',
    r'check-sensitive-data\.py$',  # Don't check this file itself
    r'learned_mappings_db\.json$',  # Gitignored anyway
    r'CLAUDE\.local\.md$',  # Gitignored
]

# File extensions to check
CHECK_EXTENSIONS = {'.py', '.js', '.ts', '.html', '.md', '.json', '.yml', '.yaml', '.txt', '.rb', '.sh'}


def should_skip_file(filepath: str) -> bool:
    """Check if file should be skipped."""
    for pattern in SKIP_PATTERNS:
        if re.search(pattern, filepath):
            return True

    path = Path(filepath)
    if path.suffix and path.suffix not in CHECK_EXTENSIONS:
        return True

    return False


def check_line(line: str, pattern: str, allowed: list) -> bool:
    """Check if line matches pattern but isn't in allowed list."""
    matches = re.findall(pattern, line, re.IGNORECASE)
    for match in matches:
        match_str = match if isinstance(match, str) else match[0]
        if match_str not in allowed and not any(a in line for a in allowed):
            return True
    return False


def get_files_to_check(staged_only: bool) -> list:
    """Get list of files to check."""
    if staged_only:
        result = subprocess.run(
            ['git', 'diff', '--cached', '--name-only', '--diff-filter=ACM'],
            capture_output=True, text=True
        )
        files = result.stdout.strip().split('\n')
        return [f for f in files if f and not should_skip_file(f)]
    else:
        result = subprocess.run(
            ['git', 'ls-files'],
            capture_output=True, text=True
        )
        files = result.stdout.strip().split('\n')
        return [f for f in files if f and not should_skip_file(f)]


def check_file(filepath: str) -> list:
    """Check a file for sensitive data. Returns list of (line_num, pattern_name, line) tuples."""
    issues = []

    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                for pattern, name, allowed in SENSITIVE_PATTERNS:
                    if check_line(line, pattern, allowed):
                        issues.append((line_num, name, line.strip()[:100]))
    except Exception as e:
        print(f"Warning: Could not read {filepath}: {e}", file=sys.stderr)

    return issues


def main():
    staged_only = '--staged-only' in sys.argv
    files = get_files_to_check(staged_only)

    all_issues = []

    for filepath in files:
        if Path(filepath).exists():
            issues = check_file(filepath)
            if issues:
                all_issues.append((filepath, issues))

    if all_issues:
        print("=" * 60)
        print("SENSITIVE DATA DETECTED - Commit blocked")
        print("=" * 60)
        print()

        for filepath, issues in all_issues:
            print(f"File: {filepath}")
            for line_num, pattern_name, line in issues:
                print(f"  Line {line_num}: {pattern_name}")
                print(f"    {line}")
            print()

        print("Please remove or replace sensitive data before committing.")
        print("Use placeholder values like '123456' for project IDs.")
        return 1

    print("No sensitive data detected.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
