"""
Unit tests for template_converter.py

Tests the core conversion logic including:
- FIELD_MAPPINGS dict lookups
- LOOP_CONVERSIONS patterns
- CONDITIONAL_CONVERSIONS patterns
- XML field replacement functions
"""

import pytest
import zipfile

from template_converter import (
    FIELD_MAPPINGS,
    LOOP_CONVERSIONS,
    CONDITIONAL_CONVERSIONS,
    MailMergeParser,
    TemplateConverter,
)


class TestFieldMappings:
    """Test the FIELD_MAPPINGS dictionary."""

    def test_simple_field_mappings_exist(self):
        """Verify essential simple field mappings are defined."""
        assert '=client_name' in FIELD_MAPPINGS
        assert '=project_name' in FIELD_MAPPINGS
        assert '=account_name' in FIELD_MAPPINGS

    def test_simple_field_mapping_format(self):
        """Verify simple field mappings convert to project. prefix format."""
        assert FIELD_MAPPINGS['=client_name'] == '{project.client_name}'
        assert FIELD_MAPPINGS['=project_name'] == '{project.project_name}'

    def test_location_field_mappings(self):
        """Verify location fields map to context-relative format (no prefix)."""
        assert FIELD_MAPPINGS['=location.name'] == '{name}'
        assert FIELD_MAPPINGS['=location.address'] == '{address}'

    def test_pricing_field_mappings(self):
        """Verify pricing fields map to context-relative format."""
        assert FIELD_MAPPINGS['=pricing.resource_name'] == '{resource_name}'
        assert FIELD_MAPPINGS['=pricing.hourly_rate'] == '{hourly_rate}'

    def test_special_field_mappings(self):
        """Verify special fields like sentence use correct syntax."""
        assert FIELD_MAPPINGS['=sentence'] == '{.}'


class TestLoopConversions:
    """Test the LOOP_CONVERSIONS dictionary."""

    def test_loop_conversions_exist(self):
        """Verify essential loop conversions are defined."""
        assert 'locations:each(location)' in LOOP_CONVERSIONS
        assert 'executive_summary:each(sentence)' in LOOP_CONVERSIONS

    def test_loop_conversion_structure(self):
        """Verify loop conversions return (start_tag, end_tag, adjustments) tuple."""
        start, end, adjustments = LOOP_CONVERSIONS['locations:each(location)']
        assert start == '{#locations}'
        assert end == '{/locations}'
        assert isinstance(adjustments, dict)

    def test_nested_loop_conversions(self):
        """Verify nested loop patterns are defined."""
        assert 'location.lines_of_business:each(lob)' in LOOP_CONVERSIONS
        assert 'lob.tasks:each(task)' in LOOP_CONVERSIONS
        assert 'task.features:each(subtask)' in LOOP_CONVERSIONS


class TestConditionalConversions:
    """Test the CONDITIONAL_CONVERSIONS dictionary."""

    def test_conditional_conversions_exist(self):
        """Verify essential conditional conversions are defined."""
        assert 'locations:if(any?)' in CONDITIONAL_CONVERSIONS
        assert 'executive_summary:if(any?)' in CONDITIONAL_CONVERSIONS

    def test_conditional_conversion_structure(self):
        """Verify conditional conversions return (start_tag, end_tag) tuple."""
        start, end = CONDITIONAL_CONVERSIONS['locations:if(any?)']
        assert start == '{#locations}'
        assert end == '{/locations}'

    def test_blank_conditional_uses_caret(self):
        """Verify :if(blank?) conditionals use ^ (inverted) syntax."""
        start, end = CONDITIONAL_CONVERSIONS['payment_terms.include_expenses:if(blank?)']
        assert start.startswith('{^')

    def test_present_conditional_uses_hash(self):
        """Verify :if(present?) conditionals use # syntax."""
        start, end = CONDITIONAL_CONVERSIONS['client_responsibilities:if(present?)']
        assert start.startswith('{#')


class TestMailMergeParser:
    """Test the MailMergeParser class."""

    def test_extract_fields(self, temp_docx, sample_xml_with_merge_fields):
        """Test extraction of merge fields from docx."""
        docx_path = temp_docx(sample_xml_with_merge_fields)
        parser = MailMergeParser(docx_path)
        fields = parser.extract_fields()

        assert '=client_name' in fields
        assert '=project_name' in fields

    def test_get_field_structure_simple(self, temp_docx, sample_xml_with_merge_fields):
        """Test categorization of simple fields."""
        docx_path = temp_docx(sample_xml_with_merge_fields)
        parser = MailMergeParser(docx_path)
        parser.extract_fields()
        structure = parser.get_field_structure()

        assert '=client_name' in structure['simple']
        assert '=project_name' in structure['simple']

    def test_get_field_structure_loops(self, temp_docx, sample_xml_with_loops):
        """Test categorization of loop fields."""
        docx_path = temp_docx(sample_xml_with_loops)
        parser = MailMergeParser(docx_path)
        parser.extract_fields()
        structure = parser.get_field_structure()

        assert any(':each' in f for f in structure['loops'])

    def test_get_field_structure_conditionals(self, temp_docx, sample_xml_with_conditionals):
        """Test categorization of conditional fields."""
        docx_path = temp_docx(sample_xml_with_conditionals)
        parser = MailMergeParser(docx_path)
        parser.extract_fields()
        structure = parser.get_field_structure()

        assert any(':if' in f for f in structure['conditionals'])


class TestTemplateConverter:
    """Test the TemplateConverter class."""

    def test_escape_xml_ampersand(self):
        """Test XML escaping of ampersand."""
        converter = TemplateConverter('input.docx', 'output.docx')
        assert converter._escape_xml('A & B') == 'A &amp; B'

    def test_escape_xml_angle_brackets(self):
        """Test XML escaping of angle brackets."""
        converter = TemplateConverter('input.docx', 'output.docx')
        assert converter._escape_xml('a < b > c') == 'a &lt; b &gt; c'

    def test_escape_xml_preserves_normal_text(self):
        """Test that normal text passes through unchanged."""
        converter = TemplateConverter('input.docx', 'output.docx')
        assert converter._escape_xml('Hello World') == 'Hello World'

    def test_escape_xml_handles_empty_string(self):
        """Test that empty string is handled correctly."""
        converter = TemplateConverter('input.docx', 'output.docx')
        assert converter._escape_xml('') == ''

    def test_escape_xml_handles_none(self):
        """Test that None is handled correctly."""
        converter = TemplateConverter('input.docx', 'output.docx')
        assert converter._escape_xml(None) is None

    def test_convert_single_field_simple(self):
        """Test conversion of a simple field."""
        converter = TemplateConverter('input.docx', 'output.docx')
        result = converter._convert_single_field('=client_name')
        assert result == '{project.client_name}'

    def test_convert_single_field_loop_start(self):
        """Test conversion of a loop start marker."""
        converter = TemplateConverter('input.docx', 'output.docx')
        result = converter._convert_single_field('locations:each(location)')
        assert result == '{#locations}'

    def test_convert_single_field_conditional_start(self):
        """Test conversion of a conditional start marker."""
        converter = TemplateConverter('input.docx', 'output.docx')
        result = converter._convert_single_field('locations:if(any?)')
        assert result == '{#locations}'

    def test_convert_single_field_unknown_returns_none(self):
        """Test that unknown fields return None."""
        converter = TemplateConverter('input.docx', 'output.docx')
        result = converter._convert_single_field('=unknown_field_xyz')
        assert result is None

    def test_convert_single_field_else_clause(self):
        """Test conversion of else clause."""
        converter = TemplateConverter('input.docx', 'output.docx')
        result = converter._convert_single_field('something:else')
        assert result == '{:else}'

    def test_merge_mappings_hardcoded_only(self):
        """Test that merge_mappings returns hardcoded mappings when no learned."""
        converter = TemplateConverter('input.docx', 'output.docx')
        result = converter._merge_mappings(None)
        assert result == FIELD_MAPPINGS

    def test_merge_mappings_with_learned(self):
        """Test that high-confidence learned mappings override hardcoded."""
        converter = TemplateConverter('input.docx', 'output.docx')
        learned = [
            {'v1_field': '=custom_field', 'v2_field': '{custom.field}', 'confidence': 0.95}
        ]
        result = converter._merge_mappings(learned)
        assert result['=custom_field'] == '{custom.field}'

    def test_merge_mappings_ignores_low_confidence(self):
        """Test that low-confidence learned mappings are ignored."""
        converter = TemplateConverter('input.docx', 'output.docx')
        learned = [
            {'v1_field': '=low_conf_field', 'v2_field': '{wrong.field}', 'confidence': 0.3}
        ]
        result = converter._merge_mappings(learned)
        assert '=low_conf_field' not in result

    def test_full_conversion(self, temp_docx, temp_output_path, sample_xml_with_merge_fields):
        """Test full conversion of a docx file."""
        docx_path = temp_docx(sample_xml_with_merge_fields)
        converter = TemplateConverter(docx_path, temp_output_path)
        success = converter.convert()

        assert success is True

        # Verify output file was created
        import os
        assert os.path.exists(temp_output_path)

        # Verify converted content
        with zipfile.ZipFile(temp_output_path, 'r') as zf:
            content = zf.read('word/document.xml').decode('utf-8')
            assert '{project.client_name}' in content

    def test_count_content(self):
        """Test the content counting function."""
        converter = TemplateConverter('input.docx', 'output.docx')
        xml = '<w:p><w:t>Hello</w:t></w:p><w:p><w:t>World</w:t></w:p><w:tbl></w:tbl>'
        counts = converter._count_content(xml)

        assert counts['paragraphs'] == 2
        assert counts['text_runs'] == 2
        assert counts['tables'] == 1
        assert counts['total_text_length'] == 10  # "Hello" + "World"


class TestRemoveSablonMarkers:
    """Test the _remove_sablon_markers method."""

    def test_removes_each_markers_from_instr(self):
        """Test removal of :each() from MERGEFIELD instructions."""
        converter = TemplateConverter('input.docx', 'output.docx')
        xml = 'w:instr="MERGEFIELD locations:each(location)"'
        result = converter._remove_sablon_markers(xml)
        assert ':each' not in result

    def test_removes_endif_markers_from_instr(self):
        """Test removal of :endIf from MERGEFIELD instructions."""
        converter = TemplateConverter('input.docx', 'output.docx')
        xml = 'w:instr="MERGEFIELD locations:endIf"'
        result = converter._remove_sablon_markers(xml)
        assert ':endIf' not in result

    def test_removes_standalone_endeach_text(self):
        """Test removal of standalone :endEach text tags."""
        converter = TemplateConverter('input.docx', 'output.docx')
        xml = '<w:t>:endEach</w:t>'
        result = converter._remove_sablon_markers(xml)
        assert ':endEach' not in result
