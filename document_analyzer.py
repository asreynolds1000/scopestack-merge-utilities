#!/usr/bin/env python3
"""
Document Analyzer for Learning Mappings
========================================

Extracts field names from v1 templates and actual values from output documents.
Combines with API merge data to discover accurate v2 field mappings.
"""

import zipfile
import re
import xml.etree.ElementTree as ET
from typing import Dict, List, Set, Tuple
from pathlib import Path


class DocumentAnalyzer:
    """Extract fields and values from Word documents for mapping learning"""

    def __init__(self):
        self.namespace = {
            'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
        }

    def extract_v1_fields(self, docx_path: str) -> List[str]:
        """
        Extract all v1 Mail Merge field names from a v1 template

        Returns:
            List of field names (e.g., ['project_name', 'customer_name', ...])
        """
        fields = []

        try:
            with zipfile.ZipFile(docx_path, 'r') as zip_ref:
                xml_content = zip_ref.read('word/document.xml').decode('utf-8')

            # Find all MERGEFIELD entries
            raw_fields = re.findall(r'MERGEFIELD\s+([^\s\\]+)', xml_content)

            # Extract clean field names
            for field in raw_fields:
                clean_name = self._clean_v1_field(field)
                if clean_name:
                    fields.append(clean_name)

        except Exception as e:
            print(f"Error extracting v1 fields: {e}")

        return list(set(fields))  # Remove duplicates

    def _clean_v1_field(self, field: str) -> str:
        """
        Clean a v1 field name to extract the base field

        Examples:
            '=project_name' -> 'project_name'
            'customer:if' -> 'customer'
            'resources:each(resource)' -> 'resources'
        """
        # Remove leading =
        if field.startswith('='):
            field = field[1:]

        # Handle conditionals
        if ':if' in field:
            field = field.split(':if')[0]

        # Handle loops
        if ':each' in field:
            field = field.split(':each')[0]

        # Remove :end and :else markers
        if ':end' in field or ':else' in field:
            return None

        return field.strip()

    def extract_text_values(self, docx_path: str, min_length: int = 3) -> Set[str]:
        """
        Extract all text content from an output document

        Args:
            docx_path: Path to the output document
            min_length: Minimum string length to consider (avoid single chars)

        Returns:
            Set of unique text values found in the document
        """
        values = set()

        try:
            with zipfile.ZipFile(docx_path, 'r') as zip_ref:
                xml_content = zip_ref.read('word/document.xml')

            # Parse XML
            root = ET.fromstring(xml_content)

            # Find all text elements
            for text_elem in root.iter('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}t'):
                if text_elem.text:
                    text = text_elem.text.strip()

                    # Filter out very short strings and common formatting
                    if len(text) >= min_length and not self._is_formatting_text(text):
                        values.add(text)

                        # Also extract numbers if present
                        numbers = re.findall(r'\d+\.?\d*', text)
                        for num in numbers:
                            if len(num) >= 2:  # Avoid single digits
                                try:
                                    # Try to convert to appropriate type
                                    if '.' in num:
                                        values.add(float(num))
                                    else:
                                        values.add(int(num))
                                except ValueError:
                                    pass

        except Exception as e:
            print(f"Error extracting text values: {e}")

        return values

    def _is_formatting_text(self, text: str) -> bool:
        """
        Check if text is likely formatting/boilerplate rather than data

        Common patterns to exclude:
        - Page numbers alone
        - Single punctuation
        - Very common words
        """
        if not text:
            return True

        # Just numbers (page numbers)
        if text.isdigit() and len(text) <= 3:
            return True

        # Just punctuation
        if all(c in '.,;:!?-—–' for c in text):
            return True

        # Very common short words (these won't help with mapping)
        common_words = {'the', 'and', 'or', 'for', 'to', 'of', 'in', 'on', 'at', 'by'}
        if text.lower() in common_words:
            return True

        return False

    def match_fields_to_values(
        self,
        v1_fields: List[str],
        output_values: Set,
        v1_merge_data: Dict,
        v2_merge_data: Dict
    ) -> List[Dict]:
        """
        Match v1 template fields to actual values in output, then find v2 paths

        This is the core integration logic:
        1. For each v1 field, find its value in v1 merge data
        2. Check if that value appears in the output document
        3. Find where that value appears in v2 merge data
        4. Return the mapping: v1_field -> value -> v2_path

        Args:
            v1_fields: List of field names from v1 template
            output_values: Set of values extracted from output document
            v1_merge_data: v1 API merge data
            v2_merge_data: v2 API merge data

        Returns:
            List of mappings with confidence scores
        """
        mappings = []

        # Extract paths and values from both merge data versions
        from learn_mappings import MappingLearner
        learner = MappingLearner(fetcher=None)

        v1_value_map = learner.extract_values_with_paths(
            v1_merge_data,
            strip_prefix="data.attributes.content."
        )

        v2_value_map = learner.extract_values_with_paths(
            v2_merge_data,
            strip_prefix="data.attributes.content."
        )

        # For each v1 field
        for v1_field in v1_fields:
            # Find values for this field in v1 merge data
            v1_paths_for_field = [path for path in v1_value_map.values() if v1_field in path]

            # Check if any of those paths have values that appear in output
            for value, v1_paths in v1_value_map.items():
                # Skip if this value isn't in output document
                if value not in output_values:
                    continue

                # Check if any of these paths match our field
                matching_paths = [p for p in v1_paths if p == v1_field or p.endswith(f'.{v1_field}')]

                if not matching_paths:
                    continue

                # This value matches! Now find it in v2 merge data
                if value in v2_value_map:
                    v2_paths = v2_value_map[value]

                    # Calculate confidence
                    confidence = 'high' if len(v2_paths) == 1 else 'medium'

                    # Pick best v2 path (shortest is usually most direct)
                    v2_path = min(v2_paths, key=len)

                    mappings.append({
                        'v1_field': v1_field,
                        'v2_field': v2_path,
                        'value': value,
                        'confidence': confidence,
                        'confirmed_in_output': True,  # Key indicator!
                        'v1_paths': matching_paths,
                        'v2_paths': v2_paths
                    })

        return mappings


if __name__ == "__main__":
    # Test the analyzer
    import sys

    if len(sys.argv) < 2:
        print("Usage: python3 document_analyzer.py <path-to-docx>")
        sys.exit(1)

    docx_path = sys.argv[1]
    analyzer = DocumentAnalyzer()

    # Try to extract fields (if it's a v1 template)
    print("Extracting v1 fields...")
    fields = analyzer.extract_v1_fields(docx_path)
    print(f"Found {len(fields)} unique fields:")
    for field in sorted(fields)[:10]:
        print(f"  - {field}")

    # Try to extract values (if it's an output document)
    print("\nExtracting text values...")
    values = analyzer.extract_text_values(docx_path)
    print(f"Found {len(values)} unique values")
    print(f"Sample values: {list(values)[:10]}")
