#!/usr/bin/env python3
"""
ScopeStack Template Converter
Converts Word Mail Merge templates to DocX Templater format
"""

import zipfile
import re
import sys
import os
from typing import List, Dict, Tuple
from xml.etree import ElementTree as ET

# Mapping from old Mail Merge format to new DocX Templater format
# Based on examples/converted_template-example.docx which uses project. prefix
FIELD_MAPPINGS = {
    # Simple field conversions
    '=client_name': '{project.client_name}',
    '=project_name': '{project.project_name}',
    '=account_name': '{project.account_name}',
    '=printed_on': '{project.printed_on}',
    '=current_version.name': '{project.current_version.name}',
    '=sales_executive.name': '{project.sales_executive.name}',
    '=presales_engineer.name': '{project.presales_engineer.name}',
    '=primary_contact.name': '{project.primary_contact.name}',
    '=primary_contact.email': '{project.primary_contact.email}',
    '=client_responsibilities': '{project.client_responsibilities}',
    '=language': '{language}',

    # Location fields (within location loop)
    '=location.name': '{name}',
    '=location.address': '{address}',

    # Pricing fields (within pricing loop)
    '=pricing.resource_name': '{resource_name}',
    '=pricing.hourly_rate': '{hourly_rate}',
    '=pricing.quantity': '{quantity}',
    '=pricing.total': '{total}',
    '=pricing.expense_revenue': '{expense_revenue}',
    '=pricing.material_revenue': '{material_revenue}',

    # Payment terms fields
    '=term.description': '{description}',
    '=term.amount_due': '{amount_due}',
    '=term.formatted_content': '{~~formatted_content}',

    # Project pricing fields
    '=project_pricing.professional_services.adjustment': '{project_pricing.professional_services.adjustment}',
    '=project_pricing.professional_services.net_revenue': '{project_pricing.professional_services.net_revenue}',

    # Task fields
    '=task.name': '{name}',
    '=subtask.name': '{name}',
    '=subtask.quantity': '{quantity}',

    # Generic sentence field (within various loops)
    '=sentence': '{.}',
    '=price': '{price}',
}

# Loop conversions: old_loop_name -> (start_tag, end_tag, inner_field_adjustments)
LOOP_CONVERSIONS = {
    'locations:each(location)': ('{#locations}', '{/locations}', {}),
    'executive_summary:each(sentence)': ('{#project.formatted_executive_summary}', '{/project.formatted_executive_summary}', {}),
    'solution_summary:each(sentence)': ('{#project.formatted_solution_summary}', '{/project.formatted_solution_summary}', {}),
    'our_responsibilities:each(sentence)': ('{#project.formatted_our_responsibilities}', '{/project.formatted_our_responsibilities}', {}),
    'out_of_scope:each(sentence)': ('{#project.formatted_out_of_scope}', '{/project.formatted_out_of_scope}', {}),
    'language_fields:each(language)': ('{#language_fields}', '{/language_fields}', {}),
    'language.phases:each(phase)': ('{#phases}', '{/phases}', {}),
    'phase.sentences:each(sentence)': ('{#sentences}', '{/sentences}', {}),
    'resource_pricing:each(pricing)': ('{#project_pricing.resources}', '{/project_pricing.resources}', {}),
    'payment_terms.schedule:each(term)': ('{#project_payments.schedule}', '{/project_payments.schedule}', {}),
    'location.lines_of_business:each(lob)': ('{#lines_of_business}', '{/lines_of_business}', {}),
    'lob.tasks:each(task)': ('{#tasks}', '{/tasks}', {}),
    'task.features:each(subtask)': ('{#features}', '{/features}', {}),
    'task.assumptions:each(language)': ('{#assumptions}', '{/assumptions}', {}),
    'task.customer:each(language)': ('{#customer_responsibilities}', '{/customer_responsibilities}', {}),
    'task.out:each(language)': ('{#out_of_scope}', '{/out_of_scope}', {}),
    'subtask.assumptions:each(language)': ('{#assumptions}', '{/assumptions}', {}),
    'subtask.customer:each(language)': ('{#customer_responsibilities}', '{/customer_responsibilities}', {}),
    'subtask.out:each(language)': ('{#out_of_scope}', '{/out_of_scope}', {}),
    'phases_with_tasks:each(phase)': ('{#project_pricing.professional_services.phases}', '{/project_pricing.professional_services.phases}', {}),
    'project_pricing.resources:each(pricing)': ('{#project_pricing.resources}', '{/project_pricing.resources}', {}),
    'terms_and_conditions:each(term)': ('{#project.terms_and_conditions}', '{/project.terms_and_conditions}', {}),
}

# Conditional conversions
CONDITIONAL_CONVERSIONS = {
    'locations:if(any?)': ('{#locations}', '{/locations}'),
    'executive_summary:if(any?)': ('{#project.formatted_executive_summary}', '{/project.formatted_executive_summary}'),
    'solution_summary:if(any?)': ('{#project.formatted_solution_summary}', '{/project.formatted_solution_summary}'),
    'our_responsibilities:if(any?)': ('{#project.formatted_our_responsibilities}', '{/project.formatted_our_responsibilities}'),
    'out_of_scope:if(any?)': ('{#project.formatted_out_of_scope}', '{/project.formatted_out_of_scope}'),
    'client_responsibilities:if(present?)': ('{#project.client_responsibilities}', '{/project.client_responsibilities}'),
    'payment_terms.include_expenses:if(blank?)': ('{^include_expenses}', '{/include_expenses}'),
    'payment_terms.include_hardware:if(blank?)': ('{^include_hardware}', '{/include_hardware}'),
    'payment_terms.include_expenses.present?:if': ('{#include_expenses}', '{/include_expenses}'),
    'payment_terms.include_hardware.present?:if': ('{#include_hardware}', '{/include_hardware}'),
    'payment_terms.other?:if': ('{#project_payments.pricing_model=="other"}', '{/project_payments.pricing_model=="other"}'),
    'payment_terms.schedule:if(any?)': ('{#project_payments.schedule}', '{/project_payments.schedule}'),
    'lob.tasks:if(present?)': ('{#tasks}', '{/tasks}'),
    'task.assumptions:if(any?)': ('{#assumptions}', '{/assumptions}'),
    'task.customer:if(any?)': ('{#customer_responsibilities}', '{/customer_responsibilities}'),
    'task.out:if(any?)': ('{#out_of_scope}', '{/out_of_scope}'),
    'subtask.assumptions:if(any?)': ('{#assumptions}', '{/assumptions}'),
    'subtask.customer:if(any?)': ('{#customer_responsibilities}', '{/customer_responsibilities}'),
    'subtask.out:if(any?)': ('{#out_of_scope}', '{/out_of_scope}'),
    # Phase-specific conditionals (using slug comparisons)
    'language.tech_solution?:if(present?)': ('{#slug=="tech_solution"}', '{/slug=="tech_solution"}'),
    'phase.inhouse_prep_language?:if': ('{#slug=="inhouse_prep_language"}', '{/slug=="inhouse_prep_language"}'),
    'phase.onsite_implement_language?:if': ('{#slug=="onsite_implement_language"}', '{/slug=="onsite_implement_language"}'),
    'phase.remote_implement_language?:if': ('{#slug=="remote_implement_language"}', '{/slug=="remote_implement_language"}'),
    'phase.post_support_langauge?:if': ('{#slug=="post_support_langauge"}', '{/slug=="post_support_langauge"}'),
    'phase.inhouse?:if': ('{#slug=="inhouse"}', '{/slug=="inhouse"}'),
    # Pricing conditionals
    'pricing.total_row?.blank?:if': ('{^resource_slug=="project_total"}', '{/resource_slug=="project_total"}'),
    'pricing.total_row?.present?:if': ('{#resource_slug=="project_total"}', '{/resource_slug=="project_total"}'),

    # Additional conditionals from PS Gold template
    'customer_responsibilities:if(any?)': ('{#project.formatted_customer_responsibilities}', '{/project.formatted_customer_responsibilities}'),
    'phase.sentences:if(present?)': ('{#sentences}', '{/sentences}'),
    'phase.deliverables:if(present?)': ('{#deliverables}', '{/deliverables}'),
    'project_pricing.professional_services.any?:if': ('{#project_pricing.professional_services.phases.length>0}', '{/project_pricing.professional_services.phases.length>0}'),
    'project_pricing.professional_services.any?:if(blank?)': ('{#project_pricing.professional_services.phases.length==0}', '{/project_pricing.professional_services.phases.length==0}'),
    'payment_terms.fixed_fee?:if': ('{#project_payments.pricing_model=="fixed_fee"}', '{/project_payments.pricing_model=="fixed_fee"}'),
    'payment_terms.time_and_materials?:if': ('{#project_payments.pricing_model=="time_and_materials"}', '{/project_payments.pricing_model=="time_and_materials"}'),
    'payment_terms.present?:if(blank?)': ('{^project_payments.payment_terms}', '{/project_payments.payment_terms}'),
    'payment_terms.schedule:if(present?)': ('{#project_payments.payment_terms}', '{/project_payments.payment_terms}'),
    'term.payment_date:if(blank?)': ('{^payment_date}', '{/payment_date}'),
    'terms_and_conditions:if(any?)': ('{#project.terms_and_conditions.length>0}', '{/project.terms_and_conditions.length>0}'),
    'project_pricing.professional_services.discounted?:if': ('{#project_pricing.professional_services.adjustment!=0}', '{/project_pricing.professional_services.adjustment!=0}'),
}


class MailMergeParser:
    """Parses Word Mail Merge fields from a .docx document"""

    def __init__(self, docx_path: str):
        self.docx_path = docx_path
        self.merge_fields = []

    def extract_fields(self) -> List[str]:
        """Extract all MERGEFIELD entries from document.xml"""
        with zipfile.ZipFile(self.docx_path, 'r') as zip_ref:
            xml_content = zip_ref.read('word/document.xml').decode('utf-8')

        # Find all MERGEFIELD entries
        self.merge_fields = re.findall(r'MERGEFIELD\s+([^\s\\]+)', xml_content)
        return self.merge_fields

    def get_field_structure(self) -> Dict[str, List[str]]:
        """Categorize fields by type"""
        structure = {
            'simple': [],
            'loops': [],
            'conditionals': [],
            'end_markers': []
        }

        for field in set(self.merge_fields):
            if field.startswith('='):
                structure['simple'].append(field)
            elif ':each' in field:
                structure['loops'].append(field)
            elif ':if' in field:
                structure['conditionals'].append(field)
            elif ':end' in field or ':else' in field:
                structure['end_markers'].append(field)

        return structure


class TemplateConverter:
    """Converts Word Mail Merge templates to DocX Templater format"""

    def __init__(self, input_docx: str, output_docx: str):
        self.input_docx = input_docx
        self.output_docx = output_docx
        self.warnings = []

    def _escape_xml(self, text: str) -> str:
        """
        Escape special XML characters to prevent malformed XML.
        This is CRITICAL - unescaped < > & characters cause XML parsing errors.
        """
        if not text:
            return text
        # Must escape & first, then < and >
        return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

    def _convert_loop_structures(self, xml_content: str, loop_mappings: Dict) -> str:
        """
        Convert Sablon loop structures to DocX Templater format.
        Must run BEFORE field conversion.

        Example:
        MERGEFIELD locations:each(location) → {#project.locations}
        MERGEFIELD locations:endEach → {/project.locations}

        Args:
            xml_content: The XML content to process
            loop_mappings: Dict mapping Sablon var names to V2 array paths
                          e.g., {'locations': 'project.locations', 'locations_confidence': 0.9}

        Returns:
            Modified XML content with loop structures converted
        """
        if not loop_mappings:
            return xml_content

        loops_converted = 0

        # Process each loop mapping
        for sablon_var, v2_array_path in loop_mappings.items():
            # Skip confidence scores
            if sablon_var.endswith('_confidence'):
                continue

            print(f"   Converting loop: {sablon_var} → {v2_array_path}")

            # Find and convert loop START markers
            # Pattern: MERGEFIELD arrayname:each(varname)
            # This can appear in both w:fldSimple and w:instrText

            # Convert in w:fldSimple
            start_pattern_simple = rf'(<w:fldSimple[^>]*w:instr="[^"]*MERGEFIELD\s+){re.escape(sablon_var)}:each\([^)]*\)'
            # Build replacement string (can't use nested f-strings)
            start_tag = "{#" + v2_array_path + "}"
            start_replacement = r'\1' + self._escape_xml(start_tag)
            xml_content = re.sub(
                start_pattern_simple,
                start_replacement,
                xml_content,
                flags=re.IGNORECASE
            )

            # Convert in w:instrText
            start_pattern_instr = rf'(<w:instrText[^>]*>[^<]*MERGEFIELD\s+){re.escape(sablon_var)}:each\([^)]*\)'
            xml_content = re.sub(
                start_pattern_instr,
                start_replacement,
                xml_content,
                flags=re.IGNORECASE
            )

            # Find and convert loop END markers
            # Pattern: MERGEFIELD arrayname:endEach

            # Convert in w:fldSimple
            end_pattern_simple = rf'(<w:fldSimple[^>]*w:instr="[^"]*MERGEFIELD\s+){re.escape(sablon_var)}:endEach'
            # Build replacement string (can't use nested f-strings)
            end_tag = "{/" + v2_array_path + "}"
            end_replacement = r'\1' + self._escape_xml(end_tag)
            xml_content = re.sub(
                end_pattern_simple,
                end_replacement,
                xml_content,
                flags=re.IGNORECASE
            )

            # Convert in w:instrText
            end_pattern_instr = rf'(<w:instrText[^>]*>[^<]*MERGEFIELD\s+){re.escape(sablon_var)}:endEach'
            xml_content = re.sub(
                end_pattern_instr,
                end_replacement,
                xml_content,
                flags=re.IGNORECASE
            )

            loops_converted += 1

        if loops_converted > 0:
            print(f"   ✓ Converted {loops_converted} loop structures")

        return xml_content

    def _count_content(self, xml_content: str) -> Dict:
        """Count document elements to verify content preservation

        Returns:
            Dict with counts of paragraphs, text runs, tables, and total text length
        """
        return {
            'paragraphs': len(re.findall(r'<w:p[>\s]', xml_content)),
            'text_runs': len(re.findall(r'<w:t[>\s]', xml_content)),
            'tables': len(re.findall(r'<w:tbl[>\s]', xml_content)),
            'total_text_length': sum(len(match.group(1)) for match in re.finditer(r'<w:t[^>]*>([^<]+)</w:t>', xml_content))
        }

    def _merge_mappings(self, learned_mappings: List[Dict] = None) -> Dict:
        """
        Merge hardcoded and learned field mappings with priority for learned mappings.

        Priority: learned (confidence > 0.7) > hardcoded

        Args:
            learned_mappings: List of learned mappings from database
                             [{'v1_field': '=field', 'v2_field': '{field}', 'confidence': 0.95}]

        Returns:
            Dict mapping v1 fields to v2 fields
        """
        # Start with hardcoded mappings as fallback
        result = FIELD_MAPPINGS.copy()

        if not learned_mappings:
            print("\n📚 Using hardcoded field mappings only")
            return result

        # Override with high-confidence learned mappings
        learned_count = 0
        for mapping in learned_mappings:
            confidence = mapping.get('confidence', 0)
            if confidence > 0.7:  # Confidence threshold
                v1_field = mapping['v1_field']
                v2_field = mapping['v2_field']
                result[v1_field] = v2_field
                learned_count += 1

        if learned_count > 0:
            print(f"\n📚 Using {learned_count} learned field mappings (confidence > 0.7)")
            print(f"   Total active mappings: {len(result)}")
        else:
            print("\n📚 No high-confidence learned mappings found, using hardcoded only")

        return result

    def convert(self, loop_mappings: Dict = None, learned_field_mappings: List[Dict] = None) -> bool:
        """Perform the conversion

        Args:
            loop_mappings: Optional dict mapping Sablon loop variables to V2 array paths
                          e.g., {'locations': 'project.locations'}
            learned_field_mappings: Optional list of learned field mappings from mapping database
                                   e.g., [{'v1_field': '=client_name', 'v2_field': '{project.client_name}', 'confidence': 0.95}]
        """
        print(f"Converting: {self.input_docx} -> {self.output_docx}")

        # Build merged mapping dict (learned + hardcoded)
        self.active_field_mappings = self._merge_mappings(learned_field_mappings)

        try:
            # Extract the docx
            with zipfile.ZipFile(self.input_docx, 'r') as zip_ref:
                # Read document.xml
                xml_content = zip_ref.read('word/document.xml').decode('utf-8')

                # Count content BEFORE conversion
                before_stats = self._count_content(xml_content)
                print(f"\n📊 Content before conversion:")
                print(f"   Paragraphs: {before_stats['paragraphs']}")
                print(f"   Text runs: {before_stats['text_runs']}")
                print(f"   Tables: {before_stats['tables']}")
                print(f"   Total text length: {before_stats['total_text_length']} chars")

                # PASS 1: Convert loop structures FIRST (if provided)
                if loop_mappings:
                    print("\n🔄 Converting loop structures...")
                    xml_content = self._convert_loop_structures(xml_content, loop_mappings)

                # PASS 2: Convert fields
                xml_content = self._convert_fields(xml_content)

                # PASS 3: Remove leftover Sablon markers
                # (Result must ONLY have {} style tags)
                xml_content = self._remove_sablon_markers(xml_content)

                # Count content AFTER conversion
                after_stats = self._count_content(xml_content)
                print(f"\n📊 Content after conversion:")
                print(f"   Paragraphs: {after_stats['paragraphs']}")
                print(f"   Text runs: {after_stats['text_runs']}")
                print(f"   Tables: {after_stats['tables']}")
                print(f"   Total text length: {after_stats['total_text_length']} chars")

                # Warn if major content loss detected
                if after_stats['paragraphs'] < before_stats['paragraphs'] * 0.8:
                    lost_paragraphs = before_stats['paragraphs'] - after_stats['paragraphs']
                    print(f"\n⚠️  WARNING: Lost {lost_paragraphs} paragraphs during conversion!")
                    print(f"   Before: {before_stats['paragraphs']}, After: {after_stats['paragraphs']}")

                if after_stats['total_text_length'] < before_stats['total_text_length'] * 0.5:
                    lost_percent = 100 - (after_stats['total_text_length'] / before_stats['total_text_length'] * 100)
                    print(f"\n⚠️  WARNING: Lost {lost_percent:.0f}% of text content!")
                    print(f"   Before: {before_stats['total_text_length']} chars, After: {after_stats['total_text_length']} chars")

                # Create output docx
                with zipfile.ZipFile(self.output_docx, 'w', zipfile.ZIP_DEFLATED) as output_zip:
                    # Copy all files except document.xml
                    for item in zip_ref.namelist():
                        if item != 'word/document.xml':
                            output_zip.writestr(item, zip_ref.read(item))

                    # Write modified document.xml
                    output_zip.writestr('word/document.xml', xml_content.encode('utf-8'))

            print(f"✓ Conversion complete: {self.output_docx}")

            if self.warnings:
                print("\n⚠ Warnings:")
                for warning in self.warnings:
                    print(f"  - {warning}")

            return True

        except Exception as e:
            print(f"✗ Error during conversion: {e}")
            return False

    def _convert_fields(self, xml_content: str) -> str:
        """Convert all merge fields in the XML content using improved multi-strategy approach"""

        # Track conversions
        conversions = []

        # Strategy 1: Replace complete field structures (most reliable)
        # This handles fields that are properly structured with begin/separate/end markers
        def replace_complete_field(match):
            full_match = match.group(0)

            # Extract field name from the instruction text
            instr_match = re.search(r'MERGEFIELD\s+([^\s\\<]+)', full_match, re.IGNORECASE)
            if not instr_match:
                return full_match

            field_name = instr_match.group(1)
            new_field = self._convert_single_field(field_name)

            if new_field:
                conversions.append(f"{field_name} -> {new_field}")
                # Replace entire field structure with just the text tag
                # Don't add <w:r> wrapper - field already has run structure
                return f'<w:t xml:space="preserve">{self._escape_xml(new_field)}</w:t>'
            else:
                self.warnings.append(f"No mapping found for field: {field_name}")
                return full_match

        # Pattern to match complete field from begin to end marker
        # This captures everything between fldCharType="begin" and fldCharType="end"
        complete_field_pattern = r'<w:fldChar\s+w:fldCharType="begin"[^>]*/>.*?<w:fldChar\s+w:fldCharType="end"[^>]*/>'
        xml_content = re.sub(complete_field_pattern, replace_complete_field, xml_content, flags=re.DOTALL)

        # Strategy 2: Replace remaining instrText tags (for incomplete/malformed fields)
        def replace_instr_text(match):
            full_tag = match.group(0)
            field_name = match.group(1)

            new_field = self._convert_single_field(field_name)

            if new_field:
                # Only add to conversions if not already added
                conv_str = f"{field_name} -> {new_field}"
                if conv_str not in conversions:
                    conversions.append(conv_str)
                # Replace the instrText with a simple text tag
                return f'<w:t xml:space="preserve">{self._escape_xml(new_field)}</w:t>'
            else:
                if f"No mapping found for field: {field_name}" not in self.warnings:
                    self.warnings.append(f"No mapping found for field: {field_name}")
                return full_tag

        # Pattern to match <w:instrText>MERGEFIELD fieldname ...</w:instrText>
        instr_pattern = r'<w:instrText[^>]*>\s*MERGEFIELD\s+([^\s\\<]+)[^<]*</w:instrText>'
        xml_content = re.sub(instr_pattern, replace_instr_text, xml_content, flags=re.IGNORECASE)

        # Strategy 3: Clean up remaining field markers
        # Remove any leftover fldChar markers
        xml_content = re.sub(r'<w:fldChar[^>]*/>', '', xml_content)

        # Strategy 4: Remove old field result text
        # Remove « » display placeholders
        xml_content = re.sub(r'<w:t[^>]*>«[^»]*»</w:t>', '', xml_content)

        # Strategy 5: Remove any remaining MERGEFIELD references in text
        xml_content = re.sub(r'<w:t[^>]*>MERGEFIELD[^<]*</w:t>', '', xml_content)

        # Strategy 6: Handle fields split across multiple runs
        # Sometimes Word splits "MERGEFIELD name" across multiple <w:t> tags
        # Pattern: <w:t>MERGE</w:t>...<w:t>FIELD name</w:t>
        # IMPORTANT: Limit match to within same paragraph to avoid deleting content
        def replace_split_mergefield(match):
            """Replace a split MERGEFIELD pattern"""
            full_match = match.group(0)
            field_match = re.search(r'MERGEFIELD\s+([^\s<]+)', full_match, re.IGNORECASE)
            if field_match:
                field_name = field_match.group(1)
                new_field = self._convert_single_field(field_name)
                if new_field:
                    conv_str = f"{field_name} -> {new_field}"
                    if conv_str not in conversions:
                        conversions.append(conv_str)
                    return f'<w:t xml:space="preserve">{self._escape_xml(new_field)}</w:t>'
            return full_match

        # FIXED: Limit split field pattern to match only within ~200 chars
        # Old pattern `MERGE.*?FIELD` could match across ENTIRE document destroying content
        # New pattern uses [^<]{0,50} to limit match to nearby text only
        split_field_pattern = r'MERGE[^<]{0,50}?FIELD\s+([^\s<]+)'
        xml_content = re.sub(split_field_pattern, replace_split_mergefield, xml_content, flags=re.IGNORECASE)

        print(f"\n✓ Converted {len(conversions)} fields:")
        for conv in conversions[:10]:  # Show first 10
            print(f"  {conv}")
        if len(conversions) > 10:
            print(f"  ... and {len(conversions) - 10} more")

        return xml_content

    def _remove_sablon_markers(self, xml_content: str) -> str:
        """
        Remove Sablon control flow markers after field conversion.
        Result should ONLY have {} style tags, no Sablon markers.

        These markers are added by Sablon Ruby library and must be removed
        for valid DocX Templater templates.

        Sablon markers appear in two forms:
        1. Inside MERGEFIELD instructions: MERGEFIELD locations:each(location)
        2. As standalone text: :endEach, :endIf
        """
        print("\n🔧 Removing Sablon control flow markers...")

        # Count markers before removal for logging
        each_count = len(re.findall(r':each\([^)]*\)', xml_content))
        endEach_count = len(re.findall(r':endEach', xml_content))
        if_count = len(re.findall(r':if\([^)]*\)', xml_content))
        endIf_count = len(re.findall(r':endIf', xml_content))
        else_count = len(re.findall(r':else(?![a-zA-Z])', xml_content))

        total_markers = each_count + endEach_count + if_count + endIf_count + else_count

        if total_markers > 0:
            print(f"   Found {total_markers} Sablon markers to remove:")
            if each_count > 0:
                print(f"     • :each() markers: {each_count}")
            if endEach_count > 0:
                print(f"     • :endEach markers: {endEach_count}")
            if if_count > 0:
                print(f"     • :if() markers: {if_count}")
            if endIf_count > 0:
                print(f"     • :endIf markers: {endIf_count}")
            if else_count > 0:
                print(f"     • :else markers: {else_count}")

        # Strategy 1: Remove Sablon markers from MERGEFIELD instructions
        # BUT keep the field structure itself (it may contain converted {fields})
        # Just remove the :each(), :endEach, :if(), :endIf markers from w:instr attributes

        # Remove :each() from MERGEFIELD instructions
        xml_content = re.sub(
            r'(w:instr="[^"]*MERGEFIELD[^"]*):each\([^)]*\)',
            r'\1',
            xml_content
        )

        # Remove :endEach from MERGEFIELD instructions
        xml_content = re.sub(
            r'(w:instr="[^"]*MERGEFIELD[^"]*):endEach',
            r'\1',
            xml_content
        )

        # Remove :if() from MERGEFIELD instructions
        xml_content = re.sub(
            r'(w:instr="[^"]*MERGEFIELD[^"]*):if\([^)]*\)',
            r'\1',
            xml_content
        )

        # Remove :endIf from MERGEFIELD instructions
        xml_content = re.sub(
            r'(w:instr="[^"]*MERGEFIELD[^"]*):endIf',
            r'\1',
            xml_content
        )

        # Remove :else from MERGEFIELD instructions
        xml_content = re.sub(
            r'(w:instr="[^"]*MERGEFIELD[^"]*):else',
            r'\1',
            xml_content
        )

        # Strategy 2: Remove standalone Sablon marker text (in <w:t> tags)
        xml_content = re.sub(
            r'<w:t[^>]*>:each\([^)]*\)</w:t>',
            '',
            xml_content
        )

        xml_content = re.sub(
            r'<w:t[^>]*>:endEach</w:t>',
            '',
            xml_content
        )

        xml_content = re.sub(
            r'<w:t[^>]*>:if\([^)]*\)</w:t>',
            '',
            xml_content
        )

        xml_content = re.sub(
            r'<w:t[^>]*>:endIf</w:t>',
            '',
            xml_content
        )

        xml_content = re.sub(
            r'<w:t[^>]*>:else</w:t>',
            '',
            xml_content
        )

        if total_markers > 0:
            print(f"✓ Removed {total_markers} Sablon markers")
        else:
            print("✓ No Sablon markers found (template may already be clean)")

        return xml_content

    def _convert_single_field(self, field_name: str) -> str:
        """Convert a single field name"""

        # Check active field mappings (merged hardcoded + learned)
        active_mappings = getattr(self, 'active_field_mappings', FIELD_MAPPINGS)
        if field_name in active_mappings:
            return active_mappings[field_name]

        # Check loop conversions
        if field_name in LOOP_CONVERSIONS:
            start_tag, end_tag, _ = LOOP_CONVERSIONS[field_name]
            return start_tag

        # Check if it's an end marker
        if ':endEach' in field_name:
            base_name = field_name.replace(':endEach', ':each')
            # Find the matching loop
            for loop_name, (start, end, _) in LOOP_CONVERSIONS.items():
                if loop_name.startswith(base_name.split(':')[0]):
                    return end

        if ':endIf' in field_name:
            base_name = field_name.replace(':endIf', ':if')
            for cond_name, (start, end) in CONDITIONAL_CONVERSIONS.items():
                if cond_name.startswith(base_name.split(':')[0]):
                    return end

        if ':else' in field_name:
            # Handle else clauses - these might need custom logic
            return '{:else}'

        # Check conditional conversions
        if field_name in CONDITIONAL_CONVERSIONS:
            start_tag, end_tag = CONDITIONAL_CONVERSIONS[field_name]
            return start_tag

        return None

    def _cleanup_field_markers(self, xml_content: str) -> str:
        """Remove Word field character markers that are no longer needed"""
        # Remove fldChar elements that mark field boundaries
        xml_content = re.sub(r'<w:fldChar[^>]*/>', '', xml_content)
        # Remove empty runs
        xml_content = re.sub(r'<w:r[^>]*>\s*<w:rPr[^>]*>[^<]*</w:rPr>\s*</w:r>', '', xml_content)
        return xml_content


def main():
    """CLI entry point"""
    if len(sys.argv) < 2:
        print("ScopeStack Template Converter")
        print("Usage:")
        print("  python template_converter.py <input.docx> [output.docx]")
        print("\nExample:")
        print("  python template_converter.py old_template.docx new_template.docx")
        sys.exit(1)

    input_file = sys.argv[1]

    if not os.path.exists(input_file):
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)

    # Default output name
    if len(sys.argv) >= 3:
        output_file = sys.argv[2]
    else:
        base_name = os.path.splitext(input_file)[0]
        output_file = f"{base_name}_converted.docx"

    # Run conversion
    converter = TemplateConverter(input_file, output_file)
    success = converter.convert()

    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
