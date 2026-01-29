#!/usr/bin/env python3
"""
Learn Field Mappings Tool
==========================

Automatically discover v2 field mappings by comparing values in v1 and v2 merge data.

This tool:
1. Fetches v1 merge data for a project
2. Fetches v2 merge data for the same project
3. Finds matching values between the two
4. Suggests v2 field paths for v1 fields
5. Generates mapping rules for template_converter.py

Usage:
    python3 learn_mappings.py --project 123456
"""

from merge_data_fetcher import MergeDataFetcher
from auth_manager import AuthManager
import json
import sys
import zipfile
import re
from typing import Dict, List, Tuple, Any


class MappingLearner:
    """Learn field mappings by comparing v1 and v2 merge data values"""

    def __init__(self, fetcher: MergeDataFetcher):
        self.fetcher = fetcher
        self.v1_value_map = {}  # value -> list of v1 paths
        self.v2_value_map = {}  # value -> list of v2 paths

    def extract_values_with_paths(self, data: Dict, prefix: str = "", strip_prefix: str = None) -> Dict[Any, List[str]]:
        """
        Extract all values from nested data structure along with their paths
        Returns: {value: [list of paths where this value appears]}

        Args:
            data: The data structure to extract from
            prefix: Starting prefix for paths
            strip_prefix: Optional prefix to strip from paths (e.g., "data.attributes.content.")
        """
        value_map = {}

        def extract(obj, path=""):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    current_path = f"{path}.{key}" if path else key

                    # Store the value and its path (only for leaf values)
                    if not isinstance(value, (dict, list)):
                        if value not in value_map:
                            value_map[value] = []

                        # Strip the wrapper prefix if specified
                        final_path = current_path
                        if strip_prefix and current_path.startswith(strip_prefix):
                            final_path = current_path[len(strip_prefix):]

                        value_map[value].append(final_path)

                    # Recurse for nested structures
                    if isinstance(value, (dict, list)):
                        extract(value, current_path)

            elif isinstance(obj, list):
                for idx, item in enumerate(obj):
                    # For arrays, we use [0] notation for the first item
                    if isinstance(item, (dict, list)):
                        extract(item, path)

        extract(data, prefix)
        return value_map

    def find_matching_values(self) -> Dict[str, Dict]:
        """
        Find values that appear in both v1 and v2 data
        Returns: {value: {'v1_paths': [...], 'v2_paths': [...]}}
        """
        matches = {}

        # Find values that exist in both v1 and v2
        common_values = set(self.v1_value_map.keys()) & set(self.v2_value_map.keys())

        # Filter out None, empty strings, and very common values
        filtered_values = [
            v for v in common_values
            if v is not None
            and v != ''
            and not isinstance(v, bool)  # Booleans are too common
            and (isinstance(v, str) and len(v) > 2 or isinstance(v, (int, float)))  # Meaningful values
        ]

        for value in filtered_values:
            matches[value] = {
                'v1_paths': self.v1_value_map[value],
                'v2_paths': self.v2_value_map[value],
                'v1_count': len(self.v1_value_map[value]),
                'v2_count': len(self.v2_value_map[value])
            }

        return matches

    def learn_mappings(self, project_id: str, template_path: str = None) -> Dict:
        """
        Learn mappings for a specific project

        Args:
            project_id: The ScopeStack project ID
            template_path: Optional path to template file for loop structure detection

        Returns dict with discovered mappings including loop structures
        """
        print(f"\n📚 Learning field mappings for project {project_id}...")
        print("=" * 80)

        # Fetch both versions of merge data
        print("\n1️⃣  Fetching v1 merge data...")
        v1_data = self.fetcher.fetch_v1_merge_data(project_id)
        if not v1_data:
            print("❌ Failed to fetch v1 merge data")
            print("   This project may not have valid v1 merge data or there's a server-side error.")
            print("   Try a different project ID or check the project configuration in ScopeStack.")
            return {}

        print("\n2️⃣  Fetching v2 merge data...")
        v2_data = self.fetcher.fetch_v2_merge_data(project_id)
        if not v2_data:
            print("❌ Failed to fetch v2 merge data")
            print("   This project may not have valid v2 merge data or there's a server-side error.")
            print("   Try a different project ID or check the project configuration in ScopeStack.")
            return {}

        # Extract values and paths from both datasets
        # The merge data has a wrapper structure: data.attributes.content
        # We need to strip this prefix to get the actual field paths
        print("\n3️⃣  Extracting values from v1 data...")
        self.v1_value_map = self.extract_values_with_paths(v1_data, strip_prefix="data.attributes.content.")
        print(f"   Found {len(self.v1_value_map)} unique values")

        print("\n4️⃣  Extracting values from v2 data...")
        self.v2_value_map = self.extract_values_with_paths(v2_data, strip_prefix="data.attributes.content.")
        print(f"   Found {len(self.v2_value_map)} unique values")

        # Find matching values
        print("\n5️⃣  Finding matching values...")
        matches = self.find_matching_values()
        print(f"   Found {len(matches)} matching values")

        # Suggest mappings
        print("\n6️⃣  Generating suggested mappings...")
        suggested_mappings = self.suggest_mappings(matches)

        # NEW: Detect and learn loop structures if template provided
        loop_mappings = {}
        if template_path:
            print("\n7️⃣  Detecting loop structures in template...")
            loops = self.detect_loop_structures(template_path)
            print(f"   Found {len(loops)} Sablon loop markers")

            if loops:
                print("\n8️⃣  Learning loop-to-array mappings...")
                loop_mappings = self.learn_loop_mappings(loops, v2_data)

                # Add loop mappings to suggested_mappings
                for sablon_var, v2_path in loop_mappings.items():
                    if not sablon_var.endswith('_confidence'):
                        suggested_mappings.append({
                            'v1_field': f'{sablon_var}:each',
                            'v2_field': v2_path,
                            'mapping_type': 'loop',
                            'confidence': loop_mappings.get(f'{sablon_var}_confidence', 0.7),
                            'match_reason': 'learned_loop_structure'
                        })

        return {
            'project_id': project_id,
            'total_matches': len(matches),
            'suggested_mappings': suggested_mappings,
            'loop_mappings': loop_mappings,
            'all_matches': matches
        }

    def suggest_mappings(self, matches: Dict) -> List[Dict]:
        """
        Suggest field mappings based on value matches
        Prioritizes high-confidence mappings (1-to-1 matches)
        """
        suggestions = []

        for value, paths in matches.items():
            # Calculate confidence score
            # High confidence: single v1 path maps to single v2 path
            # Medium confidence: single v1 path maps to multiple v2 paths (pick shortest)
            # Low confidence: multiple v1 paths or complex patterns

            v1_paths = paths['v1_paths']
            v2_paths = paths['v2_paths']

            if len(v1_paths) == 1 and len(v2_paths) == 1:
                confidence = 'high'
                v1_field = v1_paths[0]
                v2_field = v2_paths[0]
            elif len(v1_paths) == 1:
                confidence = 'medium'
                v1_field = v1_paths[0]
                # Pick shortest v2 path (likely most direct)
                v2_field = min(v2_paths, key=len)
            else:
                confidence = 'low'
                # Pick most common pattern
                v1_field = min(v1_paths, key=len)
                v2_field = min(v2_paths, key=len)

            suggestions.append({
                'v1_field': v1_field,
                'v2_field': v2_field,
                'value': value,
                'confidence': confidence,
                'v1_paths': v1_paths,
                'v2_paths': v2_paths
            })

        # Sort by confidence (high first) and then by v1 field name
        confidence_order = {'high': 0, 'medium': 1, 'low': 2}
        suggestions.sort(key=lambda x: (confidence_order[x['confidence']], x['v1_field']))

        return suggestions

    def detect_loop_structures(self, template_path: str) -> List[Dict]:
        """
        Detect Sablon loop markers in template and identify loop variables.

        Returns:
        [
            {
                'sablon_var': 'location',
                'sablon_marker': ':each(location)',
                'nested_fields': ['location.name', 'location.address'],
                'xml_location': '<context>...',
            },
            ...
        ]
        """
        loops = []

        try:
            with zipfile.ZipFile(template_path, 'r') as zip_ref:
                xml_content = zip_ref.read('word/document.xml').decode('utf-8')
        except Exception as e:
            print(f"⚠️  Could not read template for loop detection: {e}")
            return loops

        # Find all :each markers
        each_pattern = r':each\((\w+)\)'
        for match in re.finditer(each_pattern, xml_content):
            loop_var = match.group(1)

            # Find fields referencing this loop variable
            nested_fields = self._find_fields_in_loop(xml_content, match.start(), loop_var)

            loops.append({
                'sablon_var': loop_var,
                'sablon_marker': f':each({loop_var})',
                'nested_fields': nested_fields,
                'xml_location': xml_content[max(0, match.start()-200):match.end()+200]
            })

        return loops

    def _find_fields_in_loop(self, xml_content: str, loop_start_pos: int, loop_var: str) -> List[str]:
        """
        Find all fields that reference the given loop variable.
        Looks for patterns like =location.name where loop_var is 'location'
        """
        fields = []

        # Find the end of this loop (look for :endEach)
        end_pattern = r':endEach'
        end_match = re.search(end_pattern, xml_content[loop_start_pos:])

        if end_match:
            loop_end_pos = loop_start_pos + end_match.end()
            loop_content = xml_content[loop_start_pos:loop_end_pos]

            # Find all field references within the loop
            # Pattern: =loop_var.field_name
            field_pattern = rf'={loop_var}\.(\w+)'
            for field_match in re.finditer(field_pattern, loop_content):
                field_name = f"{loop_var}.{field_match.group(1)}"
                if field_name not in fields:
                    fields.append(field_name)

        return fields

    def _find_matching_array(self, nested_fields: List[str], v2_merge_data: Dict) -> Dict:
        """
        Find v2 array that best matches the nested fields from a Sablon loop.

        Example:
        nested_fields: ['location.name', 'location.address']
           → Look for v2 arrays containing fields like 'location_name', 'location_address'

        Returns: {'v2_path': 'project.project_locations', 'confidence': 0.85}
        """
        best_match = None
        best_score = 0

        # Extract field names without the loop variable prefix
        field_names = [f.split('.', 1)[1] if '.' in f else f for f in nested_fields]

        # Search for arrays in v2 data
        def find_arrays(obj, path=""):
            nonlocal best_match, best_score

            if isinstance(obj, dict):
                for key, value in obj.items():
                    current_path = f"{path}.{key}" if path else key

                    # Check if this is an array
                    if isinstance(value, list) and len(value) > 0 and isinstance(value[0], dict):
                        # This is an array of objects - check if it matches our fields
                        score = self._calculate_array_match_score(field_names, value[0])

                        if score > best_score:
                            best_score = score
                            best_match = current_path

                    # Recurse
                    if isinstance(value, (dict, list)):
                        find_arrays(value, current_path)

            elif isinstance(obj, list):
                for item in obj:
                    if isinstance(item, (dict, list)):
                        find_arrays(item, path)

        # Strip the wrapper prefix if it exists
        data_content = v2_merge_data
        if 'data' in v2_merge_data and 'attributes' in v2_merge_data['data']:
            if 'content' in v2_merge_data['data']['attributes']:
                data_content = v2_merge_data['data']['attributes']['content']

        find_arrays(data_content)

        if best_match and best_match.startswith('data.attributes.content.'):
            best_match = best_match[len('data.attributes.content.'):]

        if best_match:
            return {'v2_path': best_match, 'confidence': best_score}
        else:
            return None

    def _calculate_array_match_score(self, field_names: List[str], array_item: Dict) -> float:
        """
        Calculate how well an array item matches the expected field names.

        Returns a score from 0 to 1 based on field name similarity.
        """
        if not field_names or not array_item:
            return 0.0

        array_keys = set(array_item.keys())
        matched = 0

        for field_name in field_names:
            # Direct match
            if field_name in array_keys:
                matched += 1
                continue

            # Check with underscores (location_name)
            underscore_name = field_name.replace('.', '_')
            if underscore_name in array_keys:
                matched += 1
                continue

            # Fuzzy matching - check if field name is contained in any key
            for key in array_keys:
                if field_name.lower() in key.lower() or key.lower() in field_name.lower():
                    matched += 0.5
                    break

        return matched / len(field_names)

    def learn_loop_mappings(self, loops: List[Dict], v2_merge_data: Dict) -> Dict[str, str]:
        """
        Map Sablon loop variables to v2 array paths.

        Example:
        Sablon: :each(location) with fields [location.name, location.address]
           ↓
        V2: project.project_locations with fields [location_name, location_address]

        Returns: {'location': 'project.project_locations', 'location_confidence': 0.85}
        """
        loop_mappings = {}

        for loop_info in loops:
            sablon_var = loop_info['sablon_var']
            nested_fields = loop_info['nested_fields']

            # Find v2 arrays that contain similar field names
            best_match = self._find_matching_array(nested_fields, v2_merge_data)

            if best_match:
                loop_mappings[sablon_var] = best_match['v2_path']
                loop_mappings[f'{sablon_var}_confidence'] = best_match['confidence']
                print(f"   ✓ {sablon_var} → {best_match['v2_path']} (confidence: {best_match['confidence']:.2f})")
            else:
                print(f"   ⚠️  No v2 array found for loop variable '{sablon_var}'")

        return loop_mappings


def print_results(results: Dict):
    """Pretty print the learning results"""
    print("\n" + "=" * 80)
    print("📊 MAPPING DISCOVERY RESULTS")
    print("=" * 80)

    print(f"\nProject ID: {results['project_id']}")
    print(f"Total value matches found: {results['total_matches']}")
    print(f"Suggested mappings: {len(results['suggested_mappings'])}")

    # Group by confidence
    high_conf = [s for s in results['suggested_mappings'] if s['confidence'] == 'high']
    medium_conf = [s for s in results['suggested_mappings'] if s['confidence'] == 'medium']
    low_conf = [s for s in results['suggested_mappings'] if s['confidence'] == 'low']

    print(f"\n✅ High confidence: {len(high_conf)}")
    print(f"⚠️  Medium confidence: {len(medium_conf)}")
    print(f"❓ Low confidence: {len(low_conf)}")

    # Show high confidence mappings
    if high_conf:
        print("\n" + "=" * 80)
        print("HIGH CONFIDENCE MAPPINGS (1-to-1 matches)")
        print("=" * 80)

        for i, mapping in enumerate(high_conf[:20], 1):
            v1 = mapping['v1_field']
            v2 = mapping['v2_field']
            val = mapping['value']

            # Truncate long values
            if isinstance(val, str) and len(val) > 50:
                val = val[:47] + "..."

            print(f"\n{i}. {v1} → {v2}")
            print(f"   Value: {val}")

    # Show medium confidence
    if medium_conf and len(high_conf) < 10:
        print("\n" + "=" * 80)
        print("MEDIUM CONFIDENCE MAPPINGS")
        print("=" * 80)

        for i, mapping in enumerate(medium_conf[:10], 1):
            v1 = mapping['v1_field']
            v2 = mapping['v2_field']
            print(f"\n{i}. {v1} → {v2}")
            print(f"   Alternative v2 paths: {len(mapping['v2_paths'])}")


def export_mappings(results: Dict, output_file: str):
    """Export mappings to JSON file"""
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"\n💾 Full results exported to: {output_file}")


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description='Learn field mappings from v1 to v2 merge data')
    parser.add_argument('--project', required=True, help='Project ID')
    parser.add_argument('--export', help='Export results to JSON file')

    args = parser.parse_args()

    # Authenticate
    auth = AuthManager()
    if not auth.is_authenticated():
        print("❌ Not authenticated. Please login first:")
        print("   python3 auth_manager.py login")
        sys.exit(1)

    token = auth.get_access_token()
    if not token:
        print("❌ Could not get access token")
        sys.exit(1)

    # Create fetcher
    fetcher = MergeDataFetcher()
    fetcher.authenticate(token=token)

    # Learn mappings
    learner = MappingLearner(fetcher)
    results = learner.learn_mappings(args.project)

    if not results:
        print("\n❌ Failed to learn mappings")
        sys.exit(1)

    # Print results
    print_results(results)

    # Export if requested
    if args.export:
        export_mappings(results, args.export)
    else:
        # Auto-export with project ID in filename
        default_file = f"learned_mappings_{args.project}.json"
        export_mappings(results, default_file)

    print("\n✅ Mapping discovery complete!")
    print("\nNext steps:")
    print("  1. Review the high-confidence mappings above")
    print("  2. Add verified mappings to template_converter.py")
    print("  3. Run this tool on additional projects to validate")


if __name__ == '__main__':
    main()
