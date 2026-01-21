#!/usr/bin/env python3
"""
Template Validator
Validates DocX Templater syntax before uploading to ScopeStack
"""

import re
import zipfile
from typing import Dict, List, Tuple
from pathlib import Path


class TemplateValidator:
    """
    Validates DocX Templater templates for common syntax errors
    """

    def __init__(self):
        self.errors = []
        self.warnings = []
        self.info = []

    def validate_template(self, docx_path: str) -> Dict:
        """
        Validate a DocX Templater template

        Returns:
            dict with validation results
        """
        self.errors = []
        self.warnings = []
        self.info = []

        try:
            with zipfile.ZipFile(docx_path, 'r') as zip_ref:
                xml_content = zip_ref.read('word/document.xml').decode('utf-8')
        except Exception as e:
            self.errors.append(f"Failed to read template: {e}")
            return self._build_result()

        # Run validation checks
        self._check_tag_balance(xml_content)
        self._check_loop_matching(xml_content)
        self._check_invalid_characters(xml_content)
        self._check_unclosed_tags(xml_content)
        self._check_common_mistakes(xml_content)
        self._check_field_paths(xml_content)
        self._check_sablon_markers(xml_content)  # CRITICAL: Check for unconverted Sablon

        return self._build_result()

    def _build_result(self) -> Dict:
        """Build validation result dictionary"""
        is_valid = len(self.errors) == 0

        return {
            'valid': is_valid,
            'errors': self.errors,
            'warnings': self.warnings,
            'info': self.info,
            'error_count': len(self.errors),
            'warning_count': len(self.warnings)
        }

    def _check_tag_balance(self, xml_content: str):
        """Check that all {{ and }} are balanced"""
        open_count = xml_content.count('{{')
        close_count = xml_content.count('}}')

        if open_count != close_count:
            self.errors.append(
                f"Unbalanced template tags: {open_count} opening '{{{{' but {close_count} closing '}}}}'"
            )

    def _check_loop_matching(self, xml_content: str):
        """Check that all loops have matching opening and closing tags"""
        # Find all loop tags
        loop_opens = re.findall(r'\{\{#([^\}]+)\}\}', xml_content)
        loop_closes = re.findall(r'\{\{/([^\}]+)\}\}', xml_content)

        # Track open loops
        open_loops = {}
        for loop in loop_opens:
            loop_name = loop.strip()
            open_loops[loop_name] = open_loops.get(loop_name, 0) + 1

        # Match with closes
        for loop in loop_closes:
            loop_name = loop.strip()
            if loop_name in open_loops:
                open_loops[loop_name] -= 1
                if open_loops[loop_name] == 0:
                    del open_loops[loop_name]
            else:
                self.errors.append(
                    f"Loop closing tag without opening: {{{{/{loop_name}}}}}"
                )

        # Report unclosed loops
        for loop_name, count in open_loops.items():
            self.errors.append(
                f"Unclosed loop: {{{{#{loop_name}}}}} appears {count} more time(s) than {{{{/{loop_name}}}}}"
            )

    def _check_unclosed_tags(self, xml_content: str):
        """Check for incomplete template tags"""
        # Find tags that start with {{ but don't close properly
        incomplete_opens = re.findall(r'\{\{[^\}]*$', xml_content, re.MULTILINE)
        if incomplete_opens:
            self.errors.append(
                f"Found {len(incomplete_opens)} incomplete opening tags '{{{{''"
            )

        # Find tags that end with }} but don't open properly
        incomplete_closes = re.findall(r'^[^\{]*\}\}', xml_content, re.MULTILINE)
        if incomplete_closes:
            self.errors.append(
                f"Found {len(incomplete_closes)} incomplete closing tags '}}}}'"
            )

    def _check_invalid_characters(self, xml_content: str):
        """Check for invalid characters in template tags"""
        # Find all template tags
        tags = re.findall(r'\{\{([^\}]+)\}\}', xml_content)

        for tag in tags:
            tag_content = tag.strip()

            # Skip empty tags
            if not tag_content:
                self.errors.append("Found empty template tag: {{}}")
                continue

            # Check for spaces in field names (usually invalid)
            if tag_content[0] not in '#/^@' and ' ' in tag_content:
                self.warnings.append(
                    f"Field name contains spaces: '{tag_content}' - may cause issues"
                )

            # Check for invalid special characters
            if tag_content[0] not in '#/^@':
                # Regular field - check for invalid chars
                invalid_chars = ['[', ']', '<', '>', '"', "'"]
                for char in invalid_chars:
                    if char in tag_content:
                        self.warnings.append(
                            f"Field contains potentially invalid character '{char}': {tag_content}"
                        )

    def _check_common_mistakes(self, xml_content: str):
        """Check for common DocX Templater mistakes"""
        # Check for mismatched loop tags
        loop_tags = re.findall(r'\{\{#([^\}]+)\}\}.*?\{\{/([^\}]+)\}\}', xml_content, re.DOTALL)

        for open_tag, close_tag in loop_tags:
            open_name = open_tag.strip()
            close_name = close_tag.strip()

            if open_name != close_name:
                self.errors.append(
                    f"Mismatched loop tags: {{{{#{open_name}}}}} closed with {{{{/{close_name}}}}}"
                )

        # Check for old MERGEFIELD syntax that wasn't converted
        if 'MERGEFIELD' in xml_content:
            count = xml_content.count('MERGEFIELD')
            self.errors.append(
                f"Found {count} unconverted MERGEFIELD references - conversion incomplete"
            )

        # Check for field result placeholders
        if '«' in xml_content or '»' in xml_content:
            self.warnings.append(
                "Found old field placeholder markers (« ») - these should be removed"
            )

        # Check for double braces inside tags (common copy-paste error)
        if re.search(r'\{\{\{+', xml_content) or re.search(r'\}+\}\}', xml_content):
            self.errors.append(
                "Found triple or more braces - likely a syntax error"
            )

    def _check_field_paths(self, xml_content: str):
        """Check field path syntax"""
        # Find all regular field tags (not loops, conditions, etc.)
        field_tags = re.findall(r'\{\{([^#/\^@][^\}]*)\}\}', xml_content)

        for field in field_tags:
            field_name = field.strip()

            # Check for consecutive dots
            if '..' in field_name:
                self.errors.append(
                    f"Invalid field path (consecutive dots): {field_name}"
                )

            # Check for leading/trailing dots
            if field_name.startswith('.') or field_name.endswith('.'):
                self.errors.append(
                    f"Invalid field path (leading/trailing dot): {field_name}"
                )

            # Check for paths that are too deep (might be a mistake)
            depth = field_name.count('.')
            if depth > 5:
                self.warnings.append(
                    f"Very deep field path ({depth} levels): {field_name} - verify this is correct"
                )

    def _check_sablon_markers(self, xml_content: str):
        """
        Check for leftover Sablon control flow markers.
        These should have been removed during conversion.
        Result must ONLY have {} style tags.
        """
        sablon_patterns = [
            (r':each\([^)]*\)', 'Unconverted Sablon :each marker'),
            (r':endEach', 'Unconverted Sablon :endEach marker'),
            (r':if\([^)]*\)', 'Unconverted Sablon :if marker'),
            (r':endIf', 'Unconverted Sablon :endIf marker'),
            (r':else(?![a-zA-Z])', 'Unconverted Sablon :else marker'),  # Avoid matching :elsewhere
        ]

        for pattern, error_msg in sablon_patterns:
            matches = re.findall(pattern, xml_content)
            if matches:
                # Limit to 5 examples to avoid overwhelming output
                for match in matches[:5]:
                    self.errors.append(
                        f"{error_msg}: '{match}'. "
                        "Result must only have {{}} style tags. "
                        "Template needs reconversion with fixed converter."
                    )

                # If there are more than 5, add summary
                if len(matches) > 5:
                    self.errors.append(
                        f"... and {len(matches) - 5} more {error_msg.lower()}s"
                    )

    def get_summary(self) -> str:
        """Get a human-readable summary of validation results"""
        lines = []

        if len(self.errors) == 0 and len(self.warnings) == 0:
            lines.append("✅ Template validation passed!")
            if self.info:
                lines.append("\nℹ️  Information:")
                for info in self.info:
                    lines.append(f"  • {info}")
            return '\n'.join(lines)

        if self.errors:
            lines.append(f"❌ Validation failed with {len(self.errors)} error(s):")
            for error in self.errors:
                lines.append(f"  • {error}")

        if self.warnings:
            lines.append(f"\n⚠️  {len(self.warnings)} warning(s):")
            for warning in self.warnings:
                lines.append(f"  • {warning}")

        if self.info:
            lines.append("\nℹ️  Information:")
            for info in self.info:
                lines.append(f"  • {info}")

        return '\n'.join(lines)


def validate_template(docx_path: str) -> Tuple[bool, str]:
    """
    Validate a template and return result

    Args:
        docx_path: Path to the .docx template

    Returns:
        Tuple of (is_valid, summary_message)
    """
    validator = TemplateValidator()
    result = validator.validate_template(docx_path)

    return result['valid'], validator.get_summary()


def main():
    """CLI entry point"""
    import sys

    if len(sys.argv) < 2:
        print("Template Validator")
        print("\nUsage:")
        print("  python template_validator.py <template.docx>")
        print("\nExample:")
        print("  python template_validator.py converted_template.docx")
        sys.exit(1)

    docx_path = sys.argv[1]

    if not Path(docx_path).exists():
        print(f"❌ Error: File not found: {docx_path}")
        sys.exit(1)

    is_valid, summary = validate_template(docx_path)

    print(f"\n{'='*70}")
    print(f"Validation Report: {Path(docx_path).name}")
    print(f"{'='*70}\n")
    print(summary)
    print(f"\n{'='*70}\n")

    sys.exit(0 if is_valid else 1)


if __name__ == '__main__':
    main()
