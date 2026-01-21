#!/usr/bin/env python3
"""
Data Structure Extractor
Extracts hierarchical structure from merge data JSON for visualization and analysis
"""

from typing import Dict, Any, List, Union
import json


class DataStructureExtractor:
    """
    Extracts hierarchical structure from merge data JSON.

    Identifies:
    - Field types (string, number, boolean, array, object)
    - Array counts and item structures
    - Nested object hierarchies
    - Sample values for each field

    Modes:
    - template_only=True: Only extract [0] as a template (faster, smaller payload)
    - template_only=False: Extract all array items (accurate sample values)
    """

    def __init__(self, template_only: bool = True):
        self.structures = {}
        self.template_only = template_only

    def extract_structure(self, merge_data: Dict, prefix: str = "", strip_prefix: str = "data.attributes.content.") -> Dict:
        """
        Extract hierarchical structure from merge data.

        Args:
            merge_data: Dictionary of merge data (nested JSON)
            prefix: Current path prefix (used for recursion)
            strip_prefix: Prefix to strip from final paths

        Returns:
            Dictionary mapping field paths to their metadata:
            {
                'field_path': {
                    'type': 'string' | 'number' | 'boolean' | 'array' | 'object',
                    'sample_value': <first value found>,
                    'is_array': bool,
                    'array_count': int (if array),
                    'children': {...} (if object or array)
                }
            }
        """
        structure = {}

        # Handle None or empty data
        if merge_data is None:
            return structure

        # If merge_data is not a dict, wrap it
        if not isinstance(merge_data, dict):
            return {
                prefix or 'root': {
                    'type': self._infer_type(merge_data),
                    'sample_value': self._get_sample_value(merge_data),
                    'is_array': False
                }
            }

        # Recursively process each key-value pair
        for key, value in merge_data.items():
            # Build the full path
            if prefix:
                path = f"{prefix}.{key}"
            else:
                path = key

            # Extract structure for this field
            field_info = self._extract_field_info(path, value)

            # Add to structure
            structure[path] = field_info

            # If has children, merge them in
            if 'children' in field_info and field_info['children']:
                structure.update(field_info['children'])

        # Strip unwanted prefix if specified
        if strip_prefix:
            structure = self._strip_prefix(structure, strip_prefix)

        return structure

    def _extract_field_info(self, path: str, value: Any) -> Dict:
        """Extract metadata for a single field"""
        info = {
            'path': path,
            'type': self._infer_type(value),
            'sample_value': self._get_sample_value(value),
            'is_array': isinstance(value, list)
        }

        # Handle arrays
        if isinstance(value, list):
            info['array_count'] = len(value)

            if len(value) > 0:
                first_item = value[0]
                info['item_type'] = self._infer_type(first_item) if not isinstance(first_item, (dict, list)) else ('object' if isinstance(first_item, dict) else 'array')

                all_children = {}

                if self.template_only:
                    # Template mode: only extract [0] as a template (faster, smaller payload)
                    item_path = f"{path}[0]"
                    if isinstance(first_item, dict):
                        all_children = self.extract_structure(first_item, item_path, strip_prefix="")
                    elif isinstance(first_item, list):
                        item_info = self._extract_field_info(item_path, first_item)
                        all_children[item_path] = item_info
                        if item_info.get('children'):
                            all_children.update(item_info['children'])
                else:
                    # Full mode: extract ALL items for accurate sample values
                    for index, item in enumerate(value):
                        item_path = f"{path}[{index}]"

                        if isinstance(item, dict):
                            item_children = self.extract_structure(item, item_path, strip_prefix="")
                            all_children.update(item_children)
                        elif isinstance(item, list):
                            item_info = self._extract_field_info(item_path, item)
                            all_children[item_path] = item_info
                            if item_info.get('children'):
                                all_children.update(item_info['children'])

                info['children'] = all_children
            else:
                # Empty array
                info['item_type'] = 'unknown'
                info['children'] = {}

        # Handle objects
        elif isinstance(value, dict):
            # Nested object - extract child structure
            info['children'] = self.extract_structure(value, path, strip_prefix="")

        else:
            # Primitive value
            info['children'] = {}

        return info

    def _infer_type(self, value: Any) -> str:
        """Infer the type of a value"""
        if value is None:
            return 'null'
        elif isinstance(value, bool):
            return 'boolean'
        elif isinstance(value, int):
            return 'number'
        elif isinstance(value, float):
            return 'number'
        elif isinstance(value, str):
            return 'string'
        elif isinstance(value, list):
            return 'array'
        elif isinstance(value, dict):
            return 'object'
        else:
            return 'unknown'

    def _get_sample_value(self, value: Any, max_length: int = 50) -> Any:
        """Get a sample/preview of the value"""
        if value is None:
            return None
        elif isinstance(value, (bool, int, float)):
            return value
        elif isinstance(value, str):
            # Truncate long strings
            if len(value) > max_length:
                return value[:max_length] + '...'
            return value
        elif isinstance(value, list):
            # Show count for arrays
            return f"[{len(value)} items]"
        elif isinstance(value, dict):
            # Show key count for objects
            return f"{{{len(value)} fields}}"
        else:
            return str(value)[:max_length]

    def _strip_prefix(self, structure: Dict, prefix: str) -> Dict:
        """Strip a prefix from all paths in the structure"""
        if not prefix:
            return structure

        result = {}
        for path, info in structure.items():
            # Only keep fields that start with the prefix
            if path.startswith(prefix):
                new_path = path[len(prefix):]
                # Skip if new_path is empty (means it was exactly the prefix)
                if new_path:
                    # Create a copy of info to avoid modifying the original
                    new_info = info.copy()
                    new_info['path'] = new_path

                    # Recursively strip prefix from children
                    if 'children' in new_info and new_info['children']:
                        new_info['children'] = self._strip_prefix(new_info['children'], prefix)

                    result[new_path] = new_info

        return result

    def build_tree(self, structure: Dict) -> Dict:
        """
        Build a hierarchical tree structure from flat field paths.

        Useful for tree UI rendering.

        Returns:
            {
                'name': 'root',
                'type': 'object',
                'children': [
                    {
                        'name': 'project',
                        'path': 'project',
                        'type': 'object',
                        'children': [...]
                    },
                    ...
                ]
            }
        """
        root = {
            'name': 'root',
            'type': 'object',
            'children': []
        }

        # Sort paths to ensure parents come before children
        sorted_paths = sorted(structure.keys(), key=lambda x: (x.count('.'), x))

        for path in sorted_paths:
            info = structure[path]
            self._add_to_tree(root, path, info)

        return root

    def _add_to_tree(self, tree: Dict, path: str, info: Dict):
        """Add a field to the tree structure"""
        parts = path.split('.')
        current = tree

        # Navigate to the correct parent
        for i, part in enumerate(parts[:-1]):
            # Remove array index notation if present
            clean_part = part.split('[')[0]

            # Find or create child
            child = None
            for c in current.get('children', []):
                if c['name'] == clean_part:
                    child = c
                    break

            if child is None:
                # Create intermediate node
                child = {
                    'name': clean_part,
                    'path': '.'.join(parts[:i+1]),
                    'type': 'object',
                    'children': []
                }
                if 'children' not in current:
                    current['children'] = []
                current['children'].append(child)

            current = child

        # Add the final leaf
        leaf_name = parts[-1].split('[')[0]
        leaf = {
            'name': leaf_name,
            'path': info.get('path', path),
            'type': info['type'],
            'sample_value': info.get('sample_value'),
            'is_array': info.get('is_array', False)
        }

        if info.get('array_count'):
            leaf['array_count'] = info['array_count']

        if info.get('children'):
            leaf['children'] = []
            # Add children from structure
            for child_path, child_info in info['children'].items():
                if child_path.startswith(path):
                    child_leaf = {
                        'name': child_path.split('.')[-1].split('[')[0],
                        'path': child_info.get('path', child_path),
                        'type': child_info['type'],
                        'sample_value': child_info.get('sample_value'),
                        'is_array': child_info.get('is_array', False)
                    }
                    leaf['children'].append(child_leaf)

        if 'children' not in current:
            current['children'] = []
        current['children'].append(leaf)


def main():
    """CLI for testing data structure extraction"""
    import sys

    if len(sys.argv) < 2:
        print("Usage: python data_structure_extractor.py <json_file>")
        print("   or: python data_structure_extractor.py <project_id>")
        sys.exit(1)

    arg = sys.argv[1]

    # Check if it's a file or project ID
    if arg.endswith('.json'):
        # Load from file
        with open(arg, 'r') as f:
            data = json.load(f)
    else:
        # Fetch from API
        print(f"Fetching merge data for project: {arg}")
        from merge_data_fetcher import MergeDataFetcher

        fetcher = MergeDataFetcher()

        # Fetch v1 and v2 data
        v1_data = fetcher.fetch_v1_merge_data(arg)
        v2_data = fetcher.fetch_v2_merge_data(arg)

        print("\n" + "="*60)
        print("V1 Merge Data Structure")
        print("="*60)

        extractor = DataStructureExtractor()
        v1_structure = extractor.extract_structure(v1_data)

        print(f"\nFound {len(v1_structure)} fields in V1 data:\n")
        for path, info in sorted(v1_structure.items())[:20]:  # Show first 20
            type_info = info['type']
            if info.get('is_array'):
                type_info += f" [{info.get('array_count', 0)} items]"
            sample = info.get('sample_value', '')
            print(f"  {path:40} {type_info:15} = {sample}")

        if len(v1_structure) > 20:
            print(f"\n  ... and {len(v1_structure) - 20} more fields")

        print("\n" + "="*60)
        print("V2 Merge Data Structure")
        print("="*60)

        v2_structure = extractor.extract_structure(v2_data)

        print(f"\nFound {len(v2_structure)} fields in V2 data:\n")
        for path, info in sorted(v2_structure.items())[:20]:  # Show first 20
            type_info = info['type']
            if info.get('is_array'):
                type_info += f" [{info.get('array_count', 0)} items]"
            sample = info.get('sample_value', '')
            print(f"  {path:40} {type_info:15} = {sample}")

        if len(v2_structure) > 20:
            print(f"\n  ... and {len(v2_structure) - 20} more fields")

        print("\n" + "="*60)
        print("Structure Comparison")
        print("="*60)

        # Find common field names (ignoring path differences)
        v1_names = {path.split('.')[-1]: path for path in v1_structure.keys()}
        v2_names = {path.split('.')[-1]: path for path in v2_structure.keys()}

        common_names = set(v1_names.keys()) & set(v2_names.keys())
        print(f"\nCommon field names: {len(common_names)}")
        print(f"V1 only: {len(v1_names) - len(common_names)}")
        print(f"V2 only: {len(v2_names) - len(common_names)}")

        return

    # Extract structure
    extractor = DataStructureExtractor()
    structure = extractor.extract_structure(data)

    print(json.dumps(structure, indent=2))


if __name__ == '__main__':
    main()
