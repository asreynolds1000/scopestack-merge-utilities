#!/usr/bin/env python3
"""
Persistent Mapping Database
============================

Stores and manages learned field mappings across multiple projects.
Each time a mapping is discovered, it's saved and its confidence score increases.
"""

import json
import os
from datetime import datetime
from typing import Dict, List, Optional
from pathlib import Path


class MappingDatabase:
    """Persistent storage for learned field mappings"""

    def __init__(self, db_path: str = "learned_mappings_db.json"):
        self.db_path = db_path
        self.data = self._load_database()

    def _load_database(self) -> Dict:
        """Load the database from disk"""
        if os.path.exists(self.db_path):
            with open(self.db_path, 'r') as f:
                data = json.load(f)
                # Ensure array_mappings section exists (for backwards compatibility)
                if "array_mappings" not in data:
                    data["array_mappings"] = {}
                return data
        else:
            return {
                "mappings": {},
                "array_mappings": {},  # New: stores array-level mappings
                "metadata": {
                    "version": "1.1",
                    "last_updated": None,
                    "total_projects_analyzed": 0
                }
            }

    def _save_database(self):
        """Save the database to disk"""
        self.data["metadata"]["last_updated"] = datetime.now().isoformat()
        with open(self.db_path, 'w') as f:
            json.dump(self.data, f, indent=2)

    def add_mapping(self, v1_field: str, v2_field: str, value: str = None,
                   project_id: str = None, confidence: str = "high"):
        """
        Add or update a mapping in the database

        Args:
            v1_field: The v1 field name (e.g., "project_name")
            v2_field: The v2 field path (e.g., "project.project_name")
            value: Sample value that matched (optional)
            project_id: Project ID where this mapping was discovered
            confidence: Initial confidence level ("high", "medium", "low", "manual")
        """
        # Create mapping key
        key = v1_field

        # Determine source and confidence score based on confidence parameter
        if confidence == "manual":
            source = "manual"
            initial_score = 10  # Manual mappings get highest score
        else:
            source = "learned"
            initial_score = 1

        if key not in self.data["mappings"]:
            self.data["mappings"][key] = {
                "v1_field": v1_field,
                "v2_field": v2_field,
                "confidence_score": initial_score,
                "times_seen": 1,
                "sample_values": [],
                "projects": [],
                "first_seen": datetime.now().isoformat(),
                "last_seen": datetime.now().isoformat(),
                "initial_confidence": confidence,
                "source": source
            }
        else:
            # Update existing mapping
            existing = self.data["mappings"][key]

            # If v2 field matches, increase confidence
            if existing["v2_field"] == v2_field:
                # If this is a manual confirmation, upgrade to manual source
                if confidence == "manual":
                    existing["source"] = "manual"
                    existing["confidence_score"] = 10  # Manual always gets highest score
                else:
                    existing["confidence_score"] += 1
                existing["times_seen"] += 1
            else:
                # Different v2 field for same v1 field - possible conflict
                # Store as alternative
                if "alternatives" not in existing:
                    existing["alternatives"] = []

                # Check if this alternative already exists
                alt_exists = False
                for alt in existing["alternatives"]:
                    if alt["v2_field"] == v2_field:
                        alt["times_seen"] += 1
                        alt_exists = True
                        break

                if not alt_exists:
                    existing["alternatives"].append({
                        "v2_field": v2_field,
                        "times_seen": 1,
                        "projects": []
                    })

            existing["last_seen"] = datetime.now().isoformat()

        # Add sample value if provided
        if value and value not in self.data["mappings"][key]["sample_values"]:
            self.data["mappings"][key]["sample_values"].append(value)
            # Keep only last 5 sample values
            self.data["mappings"][key]["sample_values"] = \
                self.data["mappings"][key]["sample_values"][-5:]

        # Add project ID if provided
        if project_id and project_id not in self.data["mappings"][key]["projects"]:
            self.data["mappings"][key]["projects"].append(project_id)

        self._save_database()

    def get_mapping(self, v1_field: str) -> Optional[Dict]:
        """Get the best mapping for a v1 field"""
        return self.data["mappings"].get(v1_field)

    def get_all_mappings(self) -> Dict:
        """Get all stored mappings"""
        return self.data["mappings"]

    def get_high_confidence_mappings(self, min_score: int = 2) -> Dict:
        """Get mappings that have been confirmed multiple times"""
        return {
            k: v for k, v in self.data["mappings"].items()
            if v["confidence_score"] >= min_score
        }

    def import_mappings(self, mappings: List[Dict], project_id: str = None):
        """
        Import multiple mappings at once

        Args:
            mappings: List of mapping dicts with v1_field, v2_field, value, confidence
            project_id: Project ID where these mappings came from
        """
        for mapping in mappings:
            self.add_mapping(
                v1_field=mapping.get("v1_field"),
                v2_field=mapping.get("v2_field"),
                value=mapping.get("value"),
                project_id=project_id,
                confidence=mapping.get("confidence", "high")
            )

        # Update metadata
        self.data["metadata"]["total_projects_analyzed"] += 1
        self._save_database()

    def export_for_template_converter(self, output_file: str = "discovered_mappings.py"):
        """
        Export high-confidence mappings in the format needed for template_converter.py
        """
        high_conf = self.get_high_confidence_mappings(min_score=2)

        lines = [
            "# Auto-discovered field mappings",
            "# Generated from persistent mapping database",
            f"# Last updated: {datetime.now().isoformat()}",
            f"# Total mappings: {len(high_conf)}",
            "",
            "DISCOVERED_SIMPLE_FIELDS = {",
        ]

        for v1_field, data in sorted(high_conf.items()):
            v2_field = data["v2_field"]
            score = data["confidence_score"]
            lines.append(f"    '={v1_field}': '{{{v2_field}}}',  # Confidence: {score}")

        lines.append("}")

        with open(output_file, 'w') as f:
            f.write('\n'.join(lines))

        return output_file

    def get_statistics(self) -> Dict:
        """Get database statistics"""
        total = len(self.data["mappings"])
        high_conf = len(self.get_high_confidence_mappings(min_score=2))
        very_high_conf = len(self.get_high_confidence_mappings(min_score=5))
        array_mappings = len(self.data.get("array_mappings", {}))

        return {
            "total_mappings": total,
            "high_confidence": high_conf,
            "very_high_confidence": very_high_conf,
            "array_mappings": array_mappings,
            "projects_analyzed": self.data["metadata"]["total_projects_analyzed"],
            "last_updated": self.data["metadata"]["last_updated"]
        }

    # ==================== Array Mapping Methods ====================

    @staticmethod
    def extract_array_path(field_path: str) -> Optional[str]:
        """
        Extract the array root path from a field path.

        Examples:
            'language_fields[0].name' -> 'language_fields[]'
            'project.locations[2].address' -> 'project.locations[]'
            'simple_field' -> None (not in an array)
        """
        import re
        # Find the last array index pattern and extract up to it
        match = re.search(r'^(.+?)\[\d+\]', field_path)
        if match:
            return match.group(1) + '[]'
        return None

    @staticmethod
    def get_array_item_fields(field_path: str) -> Optional[str]:
        """
        Get the field name within an array item.

        Examples:
            'language_fields[0].name' -> 'name'
            'project.locations[2].address.city' -> 'address.city'
            'simple_field' -> None
        """
        import re
        match = re.search(r'\[\d+\]\.(.+)$', field_path)
        if match:
            return match.group(1)
        return None

    def add_array_mapping(self, v1_array: str, v2_array: str,
                          field_mappings: List[Dict] = None,
                          project_id: str = None):
        """
        Add or update an array-level mapping.

        Args:
            v1_array: The v1 array path (e.g., 'language_fields[]')
            v2_array: The v2 array path (e.g., 'v2.language_fields[]')
            field_mappings: List of field mappings within the array
                            [{'v1': 'name', 'v2': 'name'}, {'v1': 'code', 'v2': 'language_code'}]
            project_id: Project ID where this mapping was discovered
        """
        # Normalize array paths to use [] notation
        if not v1_array.endswith('[]'):
            v1_array = v1_array + '[]'
        if not v2_array.endswith('[]'):
            v2_array = v2_array + '[]'

        key = v1_array

        if key not in self.data["array_mappings"]:
            self.data["array_mappings"][key] = {
                "v1_array": v1_array,
                "v2_array": v2_array,
                "field_mappings": field_mappings or [],
                "confidence_score": 10,  # Manual mappings get high score
                "times_seen": 1,
                "projects": [],
                "first_seen": datetime.now().isoformat(),
                "last_seen": datetime.now().isoformat(),
                "source": "manual"
            }
        else:
            existing = self.data["array_mappings"][key]
            if existing["v2_array"] == v2_array:
                existing["confidence_score"] += 1
                existing["times_seen"] += 1
                # Merge field mappings if provided
                if field_mappings:
                    existing_fields = {(fm.get('v1'), fm.get('v2')) for fm in existing["field_mappings"]}
                    for fm in field_mappings:
                        if (fm.get('v1'), fm.get('v2')) not in existing_fields:
                            existing["field_mappings"].append(fm)
            existing["last_seen"] = datetime.now().isoformat()

        if project_id and project_id not in self.data["array_mappings"][key]["projects"]:
            self.data["array_mappings"][key]["projects"].append(project_id)

        self._save_database()
        return self.data["array_mappings"][key]

    def get_array_mapping(self, v1_array: str) -> Optional[Dict]:
        """Get the mapping for a v1 array"""
        if not v1_array.endswith('[]'):
            v1_array = v1_array + '[]'
        return self.data.get("array_mappings", {}).get(v1_array)

    def get_all_array_mappings(self) -> Dict:
        """Get all stored array mappings"""
        return self.data.get("array_mappings", {})

    def delete_mapping(self, v1_field: str) -> bool:
        """
        Delete a mapping from the database

        Args:
            v1_field: The v1 field name to delete

        Returns:
            bool: True if mapping was deleted, False if not found
        """
        if v1_field in self.data["mappings"]:
            del self.data["mappings"][v1_field]
            self._save_database()
            return True
        return False

    def delete_array_mapping(self, v1_array: str) -> bool:
        """
        Delete an array mapping from the database

        Args:
            v1_array: The v1 array path to delete

        Returns:
            bool: True if mapping was deleted, False if not found
        """
        if not v1_array.endswith('[]'):
            v1_array = v1_array + '[]'

        if v1_array in self.data.get("array_mappings", {}):
            del self.data["array_mappings"][v1_array]
            self._save_database()
            return True
        return False


if __name__ == "__main__":
    # Test the database
    db = MappingDatabase()

    print("Mapping Database Statistics:")
    print("=" * 60)
    stats = db.get_statistics()
    for key, value in stats.items():
        print(f"{key}: {value}")
