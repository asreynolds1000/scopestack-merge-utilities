#!/usr/bin/env python3
"""
Conversion Learning Cache
Stores successful conversion patterns to improve future conversions
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional


class ConversionLearner:
    """
    Stores and retrieves learned patterns from successful conversions
    """

    def __init__(self, cache_dir=None):
        """
        Initialize the conversion learner

        Args:
            cache_dir: Directory to store learning cache (default: ~/.scopestack/learning)
        """
        if cache_dir is None:
            cache_dir = Path.home() / '.scopestack' / 'learning'

        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)

        self.patterns_file = self.cache_dir / 'successful_patterns.json'
        self.syntax_fixes_file = self.cache_dir / 'syntax_fixes.json'
        self.field_mappings_file = self.cache_dir / 'field_mappings.json'

        self.patterns = self._load_json(self.patterns_file, default=[])
        self.syntax_fixes = self._load_json(self.syntax_fixes_file, default=[])
        self.field_mappings = self._load_json(self.field_mappings_file, default={})

    def _load_json(self, file_path: Path, default=None):
        """Load JSON file or return default"""
        if file_path.exists():
            try:
                with open(file_path, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"⚠️  Could not load {file_path}: {e}")
        return default if default is not None else {}

    def _save_json(self, file_path: Path, data):
        """Save data to JSON file"""
        try:
            with open(file_path, 'w') as f:
                json.dump(data, f, indent=2)
            print(f"✓ Saved learning data to {file_path}")
        except Exception as e:
            print(f"⚠️  Could not save {file_path}: {e}")

    def record_successful_conversion(
        self,
        v1_field_pattern: str,
        v2_field: str,
        context: Optional[Dict] = None
    ):
        """
        Record a successful field mapping for future use

        Args:
            v1_field_pattern: The V1 field name or pattern
            v2_field: The successful V2 field mapping
            context: Optional context (field type, section, etc.)
        """
        # Update field mappings with frequency tracking
        if v1_field_pattern not in self.field_mappings:
            self.field_mappings[v1_field_pattern] = {}

        if v2_field not in self.field_mappings[v1_field_pattern]:
            self.field_mappings[v1_field_pattern][v2_field] = {
                'count': 0,
                'first_seen': datetime.now().isoformat(),
                'context': context or {}
            }

        # Increment count
        self.field_mappings[v1_field_pattern][v2_field]['count'] += 1
        self.field_mappings[v1_field_pattern][v2_field]['last_seen'] = datetime.now().isoformat()

        self._save_json(self.field_mappings_file, self.field_mappings)

    def get_suggested_mapping(self, v1_field: str) -> Optional[str]:
        """
        Get the most likely V2 mapping for a V1 field based on past successes

        Args:
            v1_field: The V1 field to map

        Returns:
            Suggested V2 field or None
        """
        if v1_field in self.field_mappings:
            # Return the mapping with highest count
            mappings = self.field_mappings[v1_field]
            best_mapping = max(mappings.items(), key=lambda x: x[1]['count'])
            return best_mapping[0]

        # Try partial matches (e.g., "customer_name" matches "name")
        v1_lower = v1_field.lower()
        for pattern, mappings in self.field_mappings.items():
            pattern_lower = pattern.lower()
            if pattern_lower in v1_lower or v1_lower in pattern_lower:
                best_mapping = max(mappings.items(), key=lambda x: x[1]['count'])
                return best_mapping[0]

        return None

    def record_syntax_fix(
        self,
        error_pattern: str,
        fix_pattern: str,
        search_regex: str,
        replacement: str
    ):
        """
        Record a successful syntax error fix

        Args:
            error_pattern: The error message pattern
            fix_pattern: Description of the fix
            search_regex: Regex pattern used to find the error
            replacement: Replacement pattern that fixed it
        """
        fix_record = {
            'error_pattern': error_pattern,
            'fix_pattern': fix_pattern,
            'search_regex': search_regex,
            'replacement': replacement,
            'count': 1,
            'first_seen': datetime.now().isoformat(),
            'last_seen': datetime.now().isoformat()
        }

        # Check if we already have this pattern
        for existing_fix in self.syntax_fixes:
            if (existing_fix['error_pattern'] == error_pattern and
                existing_fix['search_regex'] == search_regex):
                # Update existing record
                existing_fix['count'] += 1
                existing_fix['last_seen'] = datetime.now().isoformat()
                self._save_json(self.syntax_fixes_file, self.syntax_fixes)
                return

        # Add new fix
        self.syntax_fixes.append(fix_record)
        self._save_json(self.syntax_fixes_file, self.syntax_fixes)

    def get_known_syntax_fixes(self, error_text: str) -> List[Dict]:
        """
        Get known fixes for a syntax error

        Args:
            error_text: The error message

        Returns:
            List of known fixes that might apply
        """
        relevant_fixes = []

        error_lower = error_text.lower()
        for fix in self.syntax_fixes:
            if fix['error_pattern'].lower() in error_lower:
                relevant_fixes.append({
                    'fix_pattern': fix['fix_pattern'],
                    'search_regex': fix['search_regex'],
                    'replacement': fix['replacement'],
                    'confidence': min(fix['count'] / 10.0, 1.0)  # Max confidence at 10 uses
                })

        # Sort by confidence (usage count)
        relevant_fixes.sort(key=lambda x: x['confidence'], reverse=True)
        return relevant_fixes

    def record_successful_iteration(
        self,
        iteration_data: Dict
    ):
        """
        Record a full successful iteration for pattern analysis

        Args:
            iteration_data: Dict with iteration details
        """
        pattern_record = {
            'timestamp': datetime.now().isoformat(),
            'similarity_improvement': iteration_data.get('similarity_improvement', 0),
            'fixes_applied': iteration_data.get('fixes_applied', []),
            'mappings_changed': iteration_data.get('mappings_changed', []),
            'final_similarity': iteration_data.get('final_similarity', 0)
        }

        self.patterns.append(pattern_record)

        # Keep only last 100 patterns to prevent file bloat
        if len(self.patterns) > 100:
            self.patterns = self.patterns[-100:]

        self._save_json(self.patterns_file, self.patterns)

    def get_statistics(self) -> Dict:
        """Get learning statistics"""
        return {
            'total_field_mappings': len(self.field_mappings),
            'total_syntax_fixes': len(self.syntax_fixes),
            'total_iterations_recorded': len(self.patterns),
            'most_common_mappings': self._get_top_mappings(10),
            'most_common_fixes': self._get_top_fixes(10)
        }

    def _get_top_mappings(self, n: int) -> List[Dict]:
        """Get top N most common field mappings"""
        all_mappings = []
        for v1_field, v2_mappings in self.field_mappings.items():
            for v2_field, data in v2_mappings.items():
                all_mappings.append({
                    'v1_field': v1_field,
                    'v2_field': v2_field,
                    'count': data['count']
                })

        all_mappings.sort(key=lambda x: x['count'], reverse=True)
        return all_mappings[:n]

    def _get_top_fixes(self, n: int) -> List[Dict]:
        """Get top N most common syntax fixes"""
        sorted_fixes = sorted(
            self.syntax_fixes,
            key=lambda x: x['count'],
            reverse=True
        )
        return sorted_fixes[:n]

    def clear_cache(self):
        """Clear all learning cache"""
        self.patterns = []
        self.syntax_fixes = []
        self.field_mappings = {}

        self._save_json(self.patterns_file, self.patterns)
        self._save_json(self.syntax_fixes_file, self.syntax_fixes)
        self._save_json(self.field_mappings_file, self.field_mappings)

        print("✓ Learning cache cleared")


def main():
    """CLI for conversion learner"""
    import sys

    learner = ConversionLearner()

    if len(sys.argv) < 2:
        print("Conversion Learning Cache")
        print("\nCommands:")
        print("  stats  - Show learning statistics")
        print("  clear  - Clear all learning cache")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == 'stats':
        stats = learner.get_statistics()
        print("\n📊 Learning Statistics:")
        print(f"  Field mappings learned: {stats['total_field_mappings']}")
        print(f"  Syntax fixes learned: {stats['total_syntax_fixes']}")
        print(f"  Iterations recorded: {stats['total_iterations_recorded']}")

        if stats['most_common_mappings']:
            print("\n🔝 Top Field Mappings:")
            for mapping in stats['most_common_mappings']:
                print(f"  {mapping['v1_field']} → {mapping['v2_field']} ({mapping['count']} times)")

        if stats['most_common_fixes']:
            print("\n🔧 Top Syntax Fixes:")
            for fix in stats['most_common_fixes']:
                print(f"  {fix['error_pattern'][:50]} ({fix['count']} times)")

    elif command == 'clear':
        confirm = input("Are you sure you want to clear all learning cache? (yes/no): ")
        if confirm.lower() == 'yes':
            learner.clear_cache()
        else:
            print("Cancelled")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()
