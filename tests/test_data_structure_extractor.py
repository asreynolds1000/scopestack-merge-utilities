"""
Tests for DataStructureExtractor - ensures array handling works correctly.

These tests verify the extractor properly reports array_count for arrays,
which the frontend relies on to generate paths for all array items
(since only [0] is extracted as a template).
"""

import pytest
from data_structure_extractor import DataStructureExtractor


class TestArrayExtraction:
    """Test array handling in the data structure extractor."""

    def test_array_count_is_preserved(self):
        """Verify that array_count accurately reflects the number of items."""
        extractor = DataStructureExtractor()
        data = {
            "locations": [
                {"name": "Location 1", "city": "NYC"},
                {"name": "Location 2", "city": "LA"},
                {"name": "Location 3", "city": "Chicago"},
                {"name": "Location 4", "city": "Seattle"},
                {"name": "Location 5", "city": "Boston"},
            ]
        }

        structure = extractor.extract_structure(data, strip_prefix="")

        # The locations field should exist and be an array
        assert "locations" in structure
        assert structure["locations"]["is_array"] is True
        assert structure["locations"]["array_count"] == 5

    def test_array_children_only_has_first_item(self):
        """Verify that only [0] is extracted as a template (by design)."""
        extractor = DataStructureExtractor()
        data = {
            "items": [
                {"id": 1, "value": "first"},
                {"id": 2, "value": "second"},
                {"id": 3, "value": "third"},
            ]
        }

        structure = extractor.extract_structure(data, strip_prefix="")

        # Only items[0] should exist in children, not items[1] or items[2]
        children_paths = list(structure["items"]["children"].keys())
        assert any("[0]" in path for path in children_paths)
        assert not any("[1]" in path for path in children_paths)
        assert not any("[2]" in path for path in children_paths)

    def test_nested_array_count(self):
        """Verify array_count works for nested arrays."""
        extractor = DataStructureExtractor()
        data = {
            "project": {
                "sections": [
                    {"name": "Section 1", "items": [{"a": 1}, {"a": 2}]},
                    {"name": "Section 2", "items": [{"a": 3}]},
                ]
            }
        }

        structure = extractor.extract_structure(data, strip_prefix="")

        # Check outer array
        assert "project.sections" in structure
        assert structure["project.sections"]["array_count"] == 2

        # Check nested array (from first item only)
        nested_path = "project.sections[0].items"
        assert nested_path in structure
        assert structure[nested_path]["array_count"] == 2  # From first section

    def test_empty_array(self):
        """Verify empty arrays have array_count of 0."""
        extractor = DataStructureExtractor()
        data = {"empty_list": []}

        structure = extractor.extract_structure(data, strip_prefix="")

        assert "empty_list" in structure
        assert structure["empty_list"]["is_array"] is True
        assert structure["empty_list"]["array_count"] == 0

    def test_primitive_array(self):
        """Verify arrays of primitives have correct array_count."""
        extractor = DataStructureExtractor()
        data = {"tags": ["tag1", "tag2", "tag3", "tag4"]}

        structure = extractor.extract_structure(data, strip_prefix="")

        assert "tags" in structure
        assert structure["tags"]["is_array"] is True
        assert structure["tags"]["array_count"] == 4
        assert structure["tags"]["item_type"] == "string"

    def test_array_of_arrays(self):
        """Verify arrays of arrays are extracted with nested array info."""
        extractor = DataStructureExtractor()
        data = {
            "sentences": [
                ["word1", "word2"],
                ["word3", "word4", "word5"],
                ["word6"]
            ]
        }

        structure = extractor.extract_structure(data, strip_prefix="")

        # Top-level array should show count
        assert "sentences" in structure
        assert structure["sentences"]["is_array"] is True
        assert structure["sentences"]["array_count"] == 3
        assert structure["sentences"]["item_type"] == "array"

        # The template item [0] should be in children and be an array itself
        assert "sentences[0]" in structure["sentences"]["children"]
        nested = structure["sentences"]["children"]["sentences[0]"]
        assert nested["is_array"] is True
        assert nested["array_count"] == 2  # From first sentence
        assert nested["item_type"] == "string"


class TestTypeInference:
    """Test type inference for various data types."""

    def test_string_type(self):
        """Verify string type inference."""
        extractor = DataStructureExtractor()
        data = {"name": "Test String"}
        structure = extractor.extract_structure(data, strip_prefix="")
        assert structure["name"]["type"] == "string"

    def test_number_types(self):
        """Verify number type inference for int and float."""
        extractor = DataStructureExtractor()
        data = {"count": 42, "price": 19.99}
        structure = extractor.extract_structure(data, strip_prefix="")
        assert structure["count"]["type"] == "number"
        assert structure["price"]["type"] == "number"

    def test_boolean_type(self):
        """Verify boolean type inference."""
        extractor = DataStructureExtractor()
        data = {"active": True, "deleted": False}
        structure = extractor.extract_structure(data, strip_prefix="")
        assert structure["active"]["type"] == "boolean"
        assert structure["deleted"]["type"] == "boolean"

    def test_null_type(self):
        """Verify null type inference."""
        extractor = DataStructureExtractor()
        data = {"empty_field": None}
        structure = extractor.extract_structure(data, strip_prefix="")
        assert structure["empty_field"]["type"] == "null"

    def test_object_type(self):
        """Verify object type inference."""
        extractor = DataStructureExtractor()
        data = {"nested": {"key": "value"}}
        structure = extractor.extract_structure(data, strip_prefix="")
        assert structure["nested"]["type"] == "object"


class TestSampleValues:
    """Test sample value extraction."""

    def test_string_sample_truncation(self):
        """Verify long strings are truncated in sample values."""
        extractor = DataStructureExtractor()
        long_string = "A" * 100
        data = {"description": long_string}
        structure = extractor.extract_structure(data, strip_prefix="")

        # Should be truncated to 50 chars + "..."
        assert len(structure["description"]["sample_value"]) == 53
        assert structure["description"]["sample_value"].endswith("...")

    def test_array_sample_shows_count(self):
        """Verify array sample values show count."""
        extractor = DataStructureExtractor()
        data = {"items": [1, 2, 3, 4, 5]}
        structure = extractor.extract_structure(data, strip_prefix="")
        assert structure["items"]["sample_value"] == "[5 items]"

    def test_object_sample_shows_field_count(self):
        """Verify object sample values show field count."""
        extractor = DataStructureExtractor()
        data = {"config": {"a": 1, "b": 2, "c": 3}}
        structure = extractor.extract_structure(data, strip_prefix="")
        assert structure["config"]["sample_value"] == "{3 fields}"


class TestPrefixStripping:
    """Test prefix stripping functionality."""

    def test_strip_prefix_removes_prefix(self):
        """Verify prefix is correctly stripped from paths."""
        extractor = DataStructureExtractor()
        data = {"data": {"attributes": {"content": {"name": "Test"}}}}
        structure = extractor.extract_structure(
            data, strip_prefix="data.attributes.content."
        )

        # Should have just "name", not the full path
        assert "name" in structure
        assert "data.attributes.content.name" not in structure

    def test_strip_prefix_preserves_unmatched(self):
        """Verify paths not matching prefix are excluded."""
        extractor = DataStructureExtractor()
        data = {"other": "value", "data": {"attributes": {"content": {"name": "Test"}}}}
        structure = extractor.extract_structure(
            data, strip_prefix="data.attributes.content."
        )

        # "other" doesn't start with the prefix, so should be excluded
        assert "other" not in structure
        assert "name" in structure
