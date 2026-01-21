#!/usr/bin/env python3
"""
Smart AI-Driven Template Converter
===================================

Analyzes V1 template structure and merge data, then uses AI to intelligently
map fields to V2 structure before conversion.
"""

import json
import re
import zipfile
from typing import Dict, List, Optional, Tuple
from pathlib import Path


class SmartConverter:
    """
    Intelligent template converter that analyzes structures before converting
    """

    def __init__(self, ai_converter, template_manager):
        """
        Initialize smart converter

        Args:
            ai_converter: AIConverter instance
            template_manager: TemplateManager instance
        """
        self.ai = ai_converter
        self.manager = template_manager

    def extract_v1_template_structure(self, template_path: str) -> Dict:
        """
        Extract all fields, loops, and conditionals from V1 template

        Returns:
            {
                'fields': ['project_name', 'client_name', ...],
                'loops': [
                    {'name': 'locations:each(location)', 'fields': ['location.name', ...]},
                    ...
                ],
                'conditionals': ['sections:if(any?)', ...]
            }
        """
        print(f"\n📋 Analyzing V1 template structure...")

        # Extract XML from docx
        with zipfile.ZipFile(template_path, 'r') as zip_ref:
            xml_content = zip_ref.read('word/document.xml').decode('utf-8')

        structure = {
            'fields': [],
            'loops': [],
            'conditionals': []
        }

        # Find simple fields: =field_name
        simple_fields = re.findall(r'=([a-zA-Z_][a-zA-Z0-9_\.]*)', xml_content)
        structure['fields'] = list(set(simple_fields))

        # Find loops: field:each(var) ... field:endEach
        loop_starts = re.findall(r'([a-zA-Z_][a-zA-Z0-9_\.]*):each\(([a-zA-Z_][a-zA-Z0-9_]*)\)', xml_content)
        for field, var in loop_starts:
            # Find fields within this loop (references to the loop variable)
            loop_fields = [f for f in simple_fields if f.startswith(f"{var}.")]
            structure['loops'].append({
                'name': f"{field}:each({var})",
                'loop_field': field,
                'loop_var': var,
                'fields': list(set(loop_fields))
            })

        # Find conditionals: field:if(condition)
        conditionals = re.findall(r'([a-zA-Z_][a-zA-Z0-9_\.]*):if\(([^)]+)\)', xml_content)
        structure['conditionals'] = [f"{field}:if({cond})" for field, cond in conditionals]

        print(f"✓ Found {len(structure['fields'])} fields, {len(structure['loops'])} loops, {len(structure['conditionals'])} conditionals")

        return structure

    def analyze_merge_data_paths(self, merge_data: Dict, prefix: str = "", max_depth: int = 3) -> List[str]:
        """
        Extract all available paths from merge data structure

        Args:
            merge_data: The merge data dict
            prefix: Current path prefix
            max_depth: Maximum depth to traverse

        Returns:
            List of dot-notation paths like ['project.name', 'project.client.name', ...]
        """
        paths = []

        if max_depth <= 0:
            return paths

        if isinstance(merge_data, dict):
            for key, value in merge_data.items():
                current_path = f"{prefix}.{key}" if prefix else key
                paths.append(current_path)

                # Recurse into nested structures
                if isinstance(value, (dict, list)):
                    paths.extend(self.analyze_merge_data_paths(value, current_path, max_depth - 1))

        elif isinstance(merge_data, list) and merge_data:
            # Analyze first item in array as representative
            paths.extend(self.analyze_merge_data_paths(merge_data[0], prefix, max_depth - 1))

        return paths

    def ai_suggest_field_mappings(
        self,
        v1_structure: Dict,
        v1_merge_paths: List[str],
        v2_merge_paths: List[str]
    ) -> Dict[str, str]:
        """
        Use AI to suggest V1 → V2 field mappings based on semantic understanding

        Returns:
            {
                'v1_field': 'v2_field',
                'locations:each(location)': 'locations',
                'location.name': 'name',
                ...
            }
        """
        print(f"\n🤖 Asking AI to suggest intelligent field mappings...")

        prompt = f"""You are an expert at mapping template fields between different data structures.

TASK: Map V1 template fields to V2 merge data paths based on semantic meaning.

V1 TEMPLATE STRUCTURE:
- Fields: {json.dumps(v1_structure['fields'][:20], indent=2)}
- Loops: {json.dumps(v1_structure['loops'][:10], indent=2)}
- Conditionals: {json.dumps(v1_structure['conditionals'][:10], indent=2)}

V1 MERGE DATA PATHS (what was available in V1):
{chr(10).join(f"  - {path}" for path in v1_merge_paths[:30])}

V2 MERGE DATA PATHS (what's available in V2):
{chr(10).join(f"  - {path}" for path in v2_merge_paths[:30])}

IMPORTANT CONTEXT:
- V1 and V2 have DIFFERENT data structures
- Field names may be completely different but represent the same concept
- Example: V1 "phases" might map to V2 "project_pricing.professional_services.phases"
- Look for semantic matches, not just name matches

For each V1 field/loop/conditional, find the best V2 equivalent based on:
1. Semantic meaning (what data does it represent?)
2. Available paths in V2 merge data
3. Context from surrounding fields

Return JSON with this structure:
{{
    "field_mappings": {{
        "v1_field": {{"v2_path": "v2.path", "confidence": 0.9, "reasoning": "why"}},
        ...
    }},
    "loop_mappings": {{
        "locations:each(location)": {{
            "v2_path": "locations",
            "inner_fields": {{"location.name": "name", "location.city": "city"}},
            "confidence": 0.95,
            "reasoning": "why"
        }},
        ...
    }},
    "conditional_mappings": {{
        "sections:if(any?)": {{"v2_path": "sections", "confidence": 0.8, "reasoning": "why"}},
        ...
    }}
}}

Return ONLY valid JSON, no other text.
"""

        # Call AI
        response = self.ai._call_anthropic(prompt) if self.ai.provider == 'anthropic' else self.ai._call_openai(prompt)

        # Parse mappings
        field_mappings = response.get('field_mappings', {})
        loop_mappings = response.get('loop_mappings', {})
        conditional_mappings = response.get('conditional_mappings', {})

        print(f"✓ AI suggested {len(field_mappings)} field mappings, {len(loop_mappings)} loop mappings")

        # Convert to flat mapping dict for template converter
        flat_mappings = {}

        for v1_field, mapping_info in field_mappings.items():
            if isinstance(mapping_info, dict):
                flat_mappings[v1_field] = mapping_info['v2_path']
            else:
                flat_mappings[v1_field] = mapping_info

        for v1_loop, mapping_info in loop_mappings.items():
            if isinstance(mapping_info, dict):
                flat_mappings[v1_loop] = mapping_info['v2_path']
                # Add inner field mappings
                for inner_v1, inner_v2 in mapping_info.get('inner_fields', {}).items():
                    flat_mappings[inner_v1] = inner_v2
            else:
                flat_mappings[v1_loop] = mapping_info

        for v1_cond, mapping_info in conditional_mappings.items():
            if isinstance(mapping_info, dict):
                flat_mappings[v1_cond] = mapping_info['v2_path']
            else:
                flat_mappings[v1_cond] = mapping_info

        return flat_mappings

    def smart_convert(
        self,
        v1_template_path: str,
        project_id: str,
        output_path: str
    ) -> Tuple[str, Dict]:
        """
        Intelligently convert V1 template to V2 using AI-analyzed mappings

        Args:
            v1_template_path: Path to V1 template
            project_id: Project ID for merge data
            output_path: Where to save converted template

        Returns:
            (output_path, mapping_dict)
        """
        from merge_data_learner import MergeDataLearner

        # Step 1: Analyze V1 template structure
        v1_structure = self.extract_v1_template_structure(v1_template_path)

        # Step 2: Fetch merge data structures
        print(f"\n📊 Fetching merge data for project {project_id}...")
        learner = MergeDataLearner(self.manager)
        v1_data = learner._fetch_merge_data_v1(project_id)
        v2_data = learner._fetch_merge_data_v2(project_id)

        v1_paths = self.analyze_merge_data_paths(v1_data)
        v2_paths = self.analyze_merge_data_paths(v2_data)

        print(f"✓ V1 has {len(v1_paths)} available paths, V2 has {len(v2_paths)} paths")

        # Step 3: Ask AI to suggest intelligent mappings
        ai_mappings = self.ai_suggest_field_mappings(v1_structure, v1_paths, v2_paths)

        # Step 4: Convert template with AI-suggested mappings
        print(f"\n🔄 Converting template with AI-suggested mappings...")
        from template_converter import TemplateConverter
        converter = TemplateConverter(v1_template_path, output_path)

        # Inject AI mappings into converter's mapping database
        for v1_field, v2_field in ai_mappings.items():
            converter.mapping_db.add_mapping(v1_field, v2_field, confidence=0.8, source='ai_analysis')

        # Run conversion
        success = converter.convert()

        if success:
            print(f"✓ Smart conversion complete: {output_path}")
        else:
            print(f"❌ Smart conversion failed")

        return output_path, ai_mappings
