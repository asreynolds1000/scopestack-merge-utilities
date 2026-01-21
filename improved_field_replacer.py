#!/usr/bin/env python3
"""
Improved MERGEFIELD Replacement
Handles complex Word XML structures where fields are split across multiple runs
"""

import re
import xml.etree.ElementTree as ET
from typing import Dict, List, Tuple


class ImprovedFieldReplacer:
    """
    More robust MERGEFIELD replacement that handles:
    1. Fields split across multiple <w:t> elements
    2. Complex field codes with formatting
    3. Nested field structures
    4. Field results vs field codes
    """

    def __init__(self, field_mappings: Dict[str, str]):
        self.field_mappings = field_mappings
        self.namespace = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
        self.replacements_made = []
        self.fields_not_found = []

    def replace_fields_in_xml(self, xml_content: str) -> Tuple[str, List[str], List[str]]:
        """
        Replace all MERGEFIELDs in XML content

        Returns:
            Tuple of (modified_xml, list_of_replacements, list_of_not_found)
        """
        # Parse XML
        try:
            # Add namespace declaration if not present
            if 'xmlns:w=' not in xml_content[:500]:
                xml_content = xml_content.replace(
                    '<w:document',
                    '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"',
                    1
                )

            root = ET.fromstring(xml_content)
        except ET.ParseError as e:
            print(f"XML Parse error: {e}")
            # Fall back to regex approach
            return self._regex_replacement(xml_content)

        # Process the document body
        body = root.find('.//w:body', self.namespace)
        if body is not None:
            self._process_element(body)

        # Convert back to string
        xml_str = ET.tostring(root, encoding='unicode')

        return xml_str, self.replacements_made, self.fields_not_found

    def _process_element(self, element):
        """Recursively process XML elements to find and replace fields"""
        # Look for field begin markers
        for child in list(element):
            # Check if this is a field begin
            if child.tag.endswith('}fldChar'):
                fld_char_type = child.get('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}fldCharType')
                if fld_char_type == 'begin':
                    # Found a field - process it
                    self._process_field(element, child)

            # Recursively process children
            self._process_element(child)

    def _process_field(self, parent, begin_marker):
        """Process a complete field from begin to end"""
        # Collect all elements in this field
        field_elements = []
        instr_text = []
        result_text_runs = []

        collecting_instr = False
        collecting_result = False

        # Find the field begin in parent's children
        children = list(parent)
        start_idx = children.index(begin_marker.getparent() if hasattr(begin_marker, 'getparent') else begin_marker)

        # Walk through siblings to collect field parts
        for i in range(start_idx, len(children)):
            elem = children[i]

            # Check for fldChar markers
            for fld_char in elem.findall('.//w:fldChar', self.namespace):
                fld_type = fld_char.get('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}fldCharType')

                if fld_type == 'begin':
                    collecting_instr = True
                elif fld_type == 'separate':
                    collecting_instr = False
                    collecting_result = True
                elif fld_type == 'end':
                    collecting_result = False
                    # Process the collected field
                    self._replace_field(parent, field_elements, instr_text, result_text_runs, start_idx, i)
                    return

            field_elements.append(elem)

            # Collect instruction text
            if collecting_instr:
                for instr in elem.findall('.//w:instrText', self.namespace):
                    if instr.text:
                        instr_text.append(instr.text)

            # Collect result runs
            if collecting_result:
                result_text_runs.append(elem)

    def _replace_field(self, parent, field_elements, instr_text, result_runs, start_idx, end_idx):
        """Replace a field with its mapped value"""
        # Combine instruction text
        full_instr = ''.join(instr_text).strip()

        # Extract field name from instruction
        mergefield_match = re.search(r'MERGEFIELD\s+([^\s\\]+)', full_instr, re.IGNORECASE)
        if not mergefield_match:
            return

        field_name = mergefield_match.group(1)

        # Look up mapping
        if field_name in self.field_mappings:
            new_value = self.field_mappings[field_name]
            self.replacements_made.append(f"{field_name} -> {new_value}")

            # Create replacement run with the new value
            replacement_run = self._create_text_run(new_value)

            # Remove all field elements
            children = list(parent)
            for i in range(end_idx, start_idx - 1, -1):
                if i < len(children):
                    parent.remove(children[i])

            # Insert replacement
            parent.insert(start_idx, replacement_run)
        else:
            self.fields_not_found.append(field_name)

    def _create_text_run(self, text: str):
        """Create a new <w:r> element with text"""
        run = ET.Element('{http://schemas.openxmlformats.org/wordprocessingml/2006/main}r')
        t = ET.SubElement(run, '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}t')
        t.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
        t.text = text
        return run

    def _regex_replacement(self, xml_content: str) -> Tuple[str, List[str], List[str]]:
        """
        Fallback regex-based replacement for when XML parsing fails
        More robust than current implementation
        """
        replacements = []
        not_found = []

        # Strategy 1: Replace complete field structures
        # Match: <w:fldChar w:fldCharType="begin"/>...<w:instrText>MERGEFIELD name</w:instrText>...<w:fldChar w:fldCharType="end"/>
        def replace_complete_field(match):
            full_match = match.group(0)

            # Extract field name
            instr_match = re.search(r'MERGEFIELD\s+([^\s\\<]+)', full_match)
            if not instr_match:
                return full_match

            field_name = instr_match.group(1)

            if field_name in self.field_mappings:
                new_value = self.field_mappings[field_name]
                replacements.append(f"{field_name} -> {new_value}")

                # Replace entire field with simple text run
                return f'<w:r><w:t xml:space="preserve">{new_value}</w:t></w:r>'
            else:
                not_found.append(field_name)
                return full_match

        # Pattern to match complete field from begin to end
        pattern = r'<w:fldChar\s+w:fldCharType="begin"[^>]*/>.*?<w:fldChar\s+w:fldCharType="end"[^>]*/>'
        xml_content = re.sub(pattern, replace_complete_field, xml_content, flags=re.DOTALL)

        # Strategy 2: Replace remaining instrText tags
        def replace_instr_text(match):
            full_tag = match.group(0)
            field_name = match.group(1)

            if field_name in self.field_mappings:
                new_value = self.field_mappings[field_name]
                if f"{field_name} -> {new_value}" not in replacements:
                    replacements.append(f"{field_name} -> {new_value}")
                return f'<w:t xml:space="preserve">{new_value}</w:t>'
            else:
                if field_name not in not_found:
                    not_found.append(field_name)
                return full_tag

        pattern = r'<w:instrText[^>]*>\s*MERGEFIELD\s+([^\s\\<]+)[^<]*</w:instrText>'
        xml_content = re.sub(pattern, replace_instr_text, xml_content, flags=re.IGNORECASE)

        # Strategy 3: Clean up remaining field markers
        xml_content = re.sub(r'<w:fldChar[^>]*/>', '', xml_content)

        # Strategy 4: Remove field result placeholders (« » markers)
        xml_content = re.sub(r'<w:t[^>]*>«[^»]*»</w:t>', '', xml_content)

        self.replacements_made = replacements
        self.fields_not_found = not_found

        return xml_content, replacements, not_found


def improve_field_replacement(xml_content: str, field_mappings: Dict[str, str]) -> Tuple[str, Dict]:
    """
    Main entry point for improved field replacement

    Args:
        xml_content: The document.xml content
        field_mappings: Dictionary of field_name -> new_value

    Returns:
        Tuple of (modified_xml, stats_dict)
    """
    replacer = ImprovedFieldReplacer(field_mappings)

    modified_xml, replacements, not_found = replacer.replace_fields_in_xml(xml_content)

    stats = {
        'replacements_made': len(replacements),
        'fields_not_found': len(not_found),
        'replacement_details': replacements,
        'missing_fields': not_found
    }

    return modified_xml, stats


if __name__ == '__main__':
    # Test example
    test_mappings = {
        'CustomerName': '{{customer.name}}',
        'InvoiceDate': '{{invoice.date}}',
        'TotalAmount': '{{invoice.total}}'
    }

    test_xml = '''<?xml version="1.0"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
            <w:p>
                <w:r>
                    <w:fldChar w:fldCharType="begin"/>
                </w:r>
                <w:r>
                    <w:instrText>MERGEFIELD CustomerName</w:instrText>
                </w:r>
                <w:r>
                    <w:fldChar w:fldCharType="separate"/>
                </w:r>
                <w:r>
                    <w:t>«CustomerName»</w:t>
                </w:r>
                <w:r>
                    <w:fldChar w:fldCharType="end"/>
                </w:r>
            </w:p>
        </w:body>
    </w:document>'''

    result_xml, stats = improve_field_replacement(test_xml, test_mappings)

    print("Replacements made:", stats['replacements_made'])
    print("Details:", stats['replacement_details'])
    print("\nModified XML:")
    print(result_xml[:500])
