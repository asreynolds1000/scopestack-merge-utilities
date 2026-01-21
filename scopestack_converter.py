#!/usr/bin/env python3
"""
ScopeStack Document Converter - Main CLI
Comprehensive tool for converting document templates to ScopeStack format
"""

import sys
import os
import argparse
from pathlib import Path
from template_converter import TemplateConverter, MailMergeParser
from merge_data_fetcher import MergeDataFetcher


def analyze_template(template_path: str):
    """Analyze a template and show its structure"""
    print(f"\nAnalyzing template: {template_path}")
    print("=" * 80)

    parser = MailMergeParser(template_path)
    fields = parser.extract_fields()
    structure = parser.get_field_structure()

    print(f"\n📊 Template Statistics:")
    print(f"  Total fields: {len(fields)}")
    print(f"  Unique fields: {len(set(fields))}")
    print(f"  Simple fields: {len(structure['simple'])}")
    print(f"  Loop fields: {len(structure['loops'])}")
    print(f"  Conditional fields: {len(structure['conditionals'])}")

    print(f"\n📝 Simple Fields:")
    for field in sorted(structure['simple'])[:10]:
        print(f"    {field}")
    if len(structure['simple']) > 10:
        print(f"    ... and {len(structure['simple']) - 10} more")

    print(f"\n🔄 Loop Fields:")
    for field in sorted(structure['loops']):
        print(f"    {field}")

    print(f"\n❓ Conditional Fields:")
    for field in sorted(structure['conditionals'])[:10]:
        print(f"    {field}")
    if len(structure['conditionals']) > 10:
        print(f"    ... and {len(structure['conditionals']) - 10} more")


def convert_template(input_path: str, output_path: str = None):
    """Convert a template from Mail Merge to DocX Templater format"""
    if not output_path:
        base = Path(input_path).stem
        output_path = f"{base}_converted.docx"

    converter = TemplateConverter(input_path, output_path)
    success = converter.convert()

    if success:
        print(f"\n✅ Conversion successful!")
        print(f"   Output: {output_path}")
        return True
    else:
        print(f"\n❌ Conversion failed!")
        return False


def validate_template(template_path: str, project_id: str):
    """Validate a template against merge data from a project"""
    print(f"\nValidating template against project {project_id}...")
    print("=" * 80)

    # Get template fields
    parser = MailMergeParser(template_path)
    template_fields = parser.extract_fields()

    print(f"\n📝 Template has {len(set(template_fields))} unique fields")

    # Fetch merge data
    fetcher = MergeDataFetcher()

    # Check for auth token
    token = os.environ.get('SCOPESTACK_TOKEN')
    if token:
        fetcher.authenticate(token=token)
        print("🔐 Authenticated with ScopeStack")
    else:
        print("⚠️  No SCOPESTACK_TOKEN found - attempting unauthenticated access")

    available_fields = fetcher.get_available_fields(project_id)

    if not available_fields:
        print("❌ Could not fetch merge data. Check your authentication or project ID.")
        return False

    print(f"📊 Project has {len(available_fields)} available fields")

    # Validate
    validation = fetcher.validate_template_fields(template_fields, available_fields)

    print(f"\n✅ Valid fields: {len(validation['valid'])}")
    print(f"❌ Missing fields: {len(validation['missing'])}")
    print(f"📈 Coverage: {validation['coverage']:.1%}")

    if validation['missing']:
        print(f"\n⚠️  Missing fields:")
        for field in validation['missing'][:20]:
            print(f"    {field}")
        if len(validation['missing']) > 20:
            print(f"    ... and {len(validation['missing']) - 20} more")

    return True


def interactive_mode():
    """Interactive mode for guided conversion"""
    print("\n" + "=" * 80)
    print("   ScopeStack Template Converter - Interactive Mode")
    print("=" * 80)

    # Get template file
    print("\n📄 Step 1: Select template file")
    template_path = input("  Enter path to template (.docx): ").strip()

    if not os.path.exists(template_path):
        print(f"  ❌ File not found: {template_path}")
        return

    # Analyze
    analyze_template(template_path)

    # Ask if user wants to validate
    print("\n🔍 Step 2: Validate against project (optional)")
    validate = input("  Validate against a ScopeStack project? (y/n): ").strip().lower()

    if validate == 'y':
        project_id = input("  Enter project ID: ").strip()
        validate_template(template_path, project_id)

    # Convert
    print("\n🔄 Step 3: Convert template")
    convert = input("  Proceed with conversion? (y/n): ").strip().lower()

    if convert == 'y':
        output_path = input("  Output file name (press Enter for default): ").strip()
        if not output_path:
            output_path = None

        convert_template(template_path, output_path)


def main():
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(
        description='ScopeStack Document Template Converter',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Interactive mode
  python scopestack_converter.py

  # Analyze a template
  python scopestack_converter.py analyze old_template.docx

  # Convert a template
  python scopestack_converter.py convert old_template.docx -o new_template.docx

  # Validate template against project
  python scopestack_converter.py validate old_template.docx --project 101735

  # Full workflow: analyze, validate, and convert
  python scopestack_converter.py convert old_template.docx --project 101735

Authentication:
  Set SCOPESTACK_TOKEN environment variable:
  export SCOPESTACK_TOKEN='your_token_here'
        """
    )

    parser.add_argument(
        'command',
        nargs='?',
        choices=['analyze', 'convert', 'validate'],
        help='Command to run (omit for interactive mode)'
    )

    parser.add_argument(
        'template',
        nargs='?',
        help='Path to template file'
    )

    parser.add_argument(
        '-o', '--output',
        help='Output file path for conversion'
    )

    parser.add_argument(
        '--project',
        help='ScopeStack project ID for validation'
    )

    args = parser.parse_args()

    # No command = interactive mode
    if not args.command:
        interactive_mode()
        return

    # Validate template argument is provided
    if not args.template:
        print("Error: template file required for this command")
        parser.print_help()
        sys.exit(1)

    # Execute command
    if args.command == 'analyze':
        analyze_template(args.template)

    elif args.command == 'validate':
        if not args.project:
            print("Error: --project required for validation")
            sys.exit(1)
        validate_template(args.template, args.project)

    elif args.command == 'convert':
        if args.project:
            # Validate first
            validate_template(args.template, args.project)
            print()

        convert_template(args.template, args.output)


if __name__ == '__main__':
    main()
