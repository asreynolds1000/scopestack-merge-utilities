#!/usr/bin/env python3
"""
Semantic Matcher
================

Structure-aware field matching between V1 and V2 merge data schemas.

Unlike value-based matching (which matches fields with identical values),
semantic matching considers:
- Field name similarity (fuzzy matching)
- Structural position (nesting depth, parent context)
- Array composition (fields within arrays)
- Type compatibility

This enables matching even when:
- Field names differ slightly (client_name vs customer_name)
- Values are different between test data
- Arrays have different lengths
"""

from typing import Dict, List, Tuple, Optional, Set
from dataclasses import dataclass
from difflib import SequenceMatcher
import re


@dataclass
class FieldInfo:
    """Metadata about a field in the schema"""
    path: str
    name: str
    type: str
    is_array: bool = False
    array_count: int = 0
    parent_path: Optional[str] = None
    depth: int = 0
    children: List[str] = None

    def __post_init__(self):
        if self.children is None:
            self.children = []


@dataclass
class MatchResult:
    """Result of matching a V1 field to V2 candidates"""
    v1_path: str
    v2_path: str
    confidence: float
    match_type: str  # 'exact', 'name', 'structural', 'fuzzy'
    reasons: List[str]


class SemanticMatcher:
    """
    Matches V1 fields to V2 fields using semantic analysis.

    Strategies (in priority order):
    1. Exact name match at same depth
    2. Fuzzy name match (>80% similar)
    3. Structural match (same position in parent, similar siblings)
    4. Array structure match (arrays with similar field compositions)
    """

    # Common field name synonyms in the ScopeStack domain
    SYNONYMS = {
        'client': {'customer', 'account', 'company'},
        'customer': {'client', 'account', 'company'},
        'location': {'site', 'place', 'address'},
        'site': {'location', 'place'},
        'name': {'title', 'label'},
        'description': {'desc', 'summary', 'details'},
        'amount': {'total', 'sum', 'value', 'price', 'cost'},
        'price': {'cost', 'amount', 'rate', 'fee'},
        'cost': {'price', 'amount', 'expense'},
        'quantity': {'qty', 'count', 'number'},
        'qty': {'quantity', 'count', 'number'},
        'address': {'location', 'street'},
        'phone': {'telephone', 'tel', 'mobile'},
        'email': {'mail'},
        'date': {'datetime', 'timestamp'},
        'id': {'identifier', 'key'},
        'user': {'person', 'contact', 'member'},
        'item': {'product', 'line', 'entry'},
        'task': {'job', 'work', 'activity'},
    }

    def __init__(self,
                 name_similarity_threshold: float = 0.8,
                 structural_threshold: float = 0.7):
        self.name_threshold = name_similarity_threshold
        self.structural_threshold = structural_threshold

    def build_field_index(self, structure: Dict) -> Dict[str, FieldInfo]:
        """
        Build an index of fields from a structure dictionary.

        Args:
            structure: Output from DataStructureExtractor.extract_structure()

        Returns:
            Dict mapping field paths to FieldInfo objects
        """
        index = {}

        for path, info in structure.items():
            # Extract field name (last component, without array index)
            name = self._get_field_name(path)

            # Calculate depth
            depth = path.count('.') + path.count('[')

            # Get parent path
            parent_path = self._get_parent_path(path)

            # Get children
            children = [p for p in structure.keys()
                       if p.startswith(path + '.') or p.startswith(path + '[')]

            field_info = FieldInfo(
                path=path,
                name=name,
                type=info.get('type', 'unknown'),
                is_array=info.get('is_array', False),
                array_count=info.get('array_count', 0),
                parent_path=parent_path,
                depth=depth,
                children=children
            )

            index[path] = field_info

        return index

    def find_matches(self,
                     v1_structure: Dict,
                     v2_structure: Dict,
                     min_confidence: float = 0.5) -> List[MatchResult]:
        """
        Find all matches between V1 and V2 fields.

        Args:
            v1_structure: V1 schema from DataStructureExtractor
            v2_structure: V2 schema from DataStructureExtractor
            min_confidence: Minimum confidence to include in results

        Returns:
            List of MatchResult objects, sorted by confidence (descending)
        """
        v1_index = self.build_field_index(v1_structure)
        v2_index = self.build_field_index(v2_structure)

        matches = []

        for v1_path, v1_info in v1_index.items():
            # Skip array indices - we match array structures, not individual items
            if re.search(r'\[\d+\]', v1_path) and not v1_path.endswith(']'):
                # This is a field inside an array item, still match it
                pass

            candidates = self._find_candidates(v1_info, v2_index)

            for v2_path, confidence, match_type, reasons in candidates:
                if confidence >= min_confidence:
                    matches.append(MatchResult(
                        v1_path=v1_path,
                        v2_path=v2_path,
                        confidence=confidence,
                        match_type=match_type,
                        reasons=reasons
                    ))

        # Sort by confidence (descending)
        matches.sort(key=lambda m: m.confidence, reverse=True)

        return matches

    def find_best_matches(self,
                          v1_structure: Dict,
                          v2_structure: Dict,
                          min_confidence: float = 0.5) -> List[MatchResult]:
        """
        Find the single best V2 match for each V1 field.

        Unlike find_matches() which returns all candidates, this returns
        only the highest-confidence match per V1 field, with ties broken
        by match_type priority (exact > name > structural > fuzzy).

        Args:
            v1_structure: V1 schema from DataStructureExtractor
            v2_structure: V2 schema from DataStructureExtractor
            min_confidence: Minimum confidence to include in results

        Returns:
            List of MatchResult objects (one per V1 field), sorted by confidence
        """
        v1_index = self.build_field_index(v1_structure)
        v2_index = self.build_field_index(v2_structure)

        # Priority order for match types
        type_priority = {'exact': 4, 'name': 3, 'structural': 2, 'fuzzy': 1, 'none': 0}

        best_matches = []

        for v1_path, v1_info in v1_index.items():
            candidates = self._find_candidates(v1_info, v2_index)

            if not candidates:
                continue

            # Sort candidates by confidence (desc), then by match_type priority (desc)
            candidates.sort(
                key=lambda c: (c[1], type_priority.get(c[2], 0)),
                reverse=True
            )

            # Take the best candidate
            best = candidates[0]
            v2_path, confidence, match_type, reasons = best

            if confidence >= min_confidence:
                best_matches.append(MatchResult(
                    v1_path=v1_path,
                    v2_path=v2_path,
                    confidence=confidence,
                    match_type=match_type,
                    reasons=reasons
                ))

        # Sort final results by confidence (descending)
        best_matches.sort(key=lambda m: m.confidence, reverse=True)

        return best_matches

    def _find_candidates(self,
                         v1_info: FieldInfo,
                         v2_index: Dict[str, FieldInfo]) -> List[Tuple[str, float, str, List[str]]]:
        """
        Find V2 candidates for a V1 field.

        Returns list of (v2_path, confidence, match_type, reasons)
        """
        candidates = []

        for v2_path, v2_info in v2_index.items():
            confidence, match_type, reasons = self._calculate_match_score(v1_info, v2_info)

            if confidence > 0:
                candidates.append((v2_path, confidence, match_type, reasons))

        return candidates

    def _calculate_match_score(self,
                               v1: FieldInfo,
                               v2: FieldInfo) -> Tuple[float, str, List[str]]:
        """
        Calculate match score between two fields.

        Returns (confidence, match_type, reasons)

        Scoring philosophy:
        - Name match is the primary signal (worth up to 60% of score)
        - Without name match, max possible score is 40% (requires name_threshold)
        - Type, depth, parent add supporting evidence but can't exceed 40% alone
        """
        reasons = []
        name_score = 0.0
        support_scores = []

        # 1. Name similarity (primary signal - up to 60% of total)
        name_sim = self._name_similarity(v1.name, v2.name)
        if name_sim == 1.0:
            reasons.append(f"Exact name match: '{v1.name}'")
            name_score = 0.6
            match_type = 'exact'
        elif name_sim >= self.name_threshold:
            reasons.append(f"Similar name: '{v1.name}' ~ '{v2.name}' ({name_sim:.0%})")
            name_score = 0.4 + (name_sim - self.name_threshold) * 0.5  # 0.4-0.6
            match_type = 'name'
        elif name_sim >= 0.5:
            reasons.append(f"Partial name match: '{v1.name}' ~ '{v2.name}' ({name_sim:.0%})")
            name_score = name_sim * 0.5  # 0.25-0.4
            match_type = 'name'
        else:
            match_type = 'fuzzy'

        # 2. Type compatibility (supporting - up to 15%)
        if v1.type == v2.type:
            reasons.append(f"Same type: {v1.type}")
            support_scores.append(0.15)
        elif self._types_compatible(v1.type, v2.type):
            reasons.append(f"Compatible types: {v1.type} ~ {v2.type}")
            support_scores.append(0.08)

        # 3. Array structure similarity (supporting - up to 15%)
        if v1.is_array and v2.is_array:
            array_sim = self._array_similarity(v1, v2)
            if array_sim > 0.3:
                reasons.append(f"Similar array structure ({array_sim:.0%})")
                support_scores.append(array_sim * 0.15)
                if match_type == 'fuzzy':
                    match_type = 'structural'

        # 4. Depth similarity (supporting - up to 5%)
        depth_diff = abs(v1.depth - v2.depth)
        if depth_diff == 0:
            reasons.append("Same nesting depth")
            support_scores.append(0.05)
        elif depth_diff == 1:
            support_scores.append(0.02)

        # 5. Parent name similarity (supporting - up to 5%)
        if v1.parent_path and v2.parent_path:
            v1_parent_name = self._get_field_name(v1.parent_path)
            v2_parent_name = self._get_field_name(v2.parent_path)
            parent_sim = self._name_similarity(v1_parent_name, v2_parent_name)
            if parent_sim >= 0.8:
                reasons.append(f"Similar parent: '{v1_parent_name}' ~ '{v2_parent_name}'")
                support_scores.append(parent_sim * 0.05)

        # Calculate final score
        # Name score dominates; support scores add evidence
        support_total = min(sum(support_scores), 0.4)  # Cap supporting evidence at 40%
        final_score = name_score + support_total

        # If no name match at all, cap at 40% regardless of support evidence
        if name_score == 0:
            final_score = min(final_score, 0.4)

        if not reasons:
            return 0.0, 'none', []

        return final_score, match_type, reasons

    def _name_similarity(self, name1: str, name2: str) -> float:
        """Calculate similarity between two field names"""
        if not name1 or not name2:
            return 0.0

        # Exact match
        if name1 == name2:
            return 1.0

        # Normalize names (lowercase, remove underscores/hyphens)
        n1 = self._normalize_name(name1)
        n2 = self._normalize_name(name2)

        if n1 == n2:
            return 0.95  # Almost exact after normalization

        # Check for synonym match (handles compound names with synonyms)
        synonym_score = self._check_synonyms(n1, n2)
        if synonym_score > 0:
            return synonym_score

        # Check if one name is a word component of the other
        # e.g., 'name' is in 'project_name' or 'site_name'
        words1 = self._split_words(n1)
        words2 = self._split_words(n2)

        # If simple name matches exactly as a word in compound name
        if len(words1) == 1 and words1[0] in words2:
            # Score based on how specific the match is
            # 'name' in ['project', 'name'] = 1/2 = 0.5, boosted to 0.75
            return 0.5 + 0.25 * (1 / len(words2))
        if len(words2) == 1 and words2[0] in words1:
            return 0.5 + 0.25 * (1 / len(words1))

        # Use SequenceMatcher for fuzzy matching
        return SequenceMatcher(None, n1, n2).ratio()

    def _check_synonyms(self, n1: str, n2: str) -> float:
        """Check if two names are synonyms. Returns score if match, 0 otherwise."""
        # Split compound names into words (e.g., 'clientname' -> ['client', 'name'])
        words1 = self._split_words(n1)
        words2 = self._split_words(n2)

        # Count exact matches and synonym matches
        exact_matches = 0
        synonym_matches = 0
        total_words = max(len(words1), len(words2))

        matched_words2 = set()

        for w1 in words1:
            # Check for exact match first
            if w1 in words2 and w1 not in matched_words2:
                exact_matches += 1
                matched_words2.add(w1)
                continue

            # Check for synonym match
            synonyms = self.SYNONYMS.get(w1, set())
            for w2 in words2:
                if w2 not in matched_words2 and w2 in synonyms:
                    synonym_matches += 1
                    matched_words2.add(w2)
                    break

        if synonym_matches == 0:
            return 0.0  # No synonym relationship found

        # Calculate score:
        # - Exact word matches contribute 1.0 each
        # - Synonym matches contribute 0.85 each
        # - Score is average of all word scores
        total_score = exact_matches * 1.0 + synonym_matches * 0.85
        return total_score / total_words

    def _split_words(self, name: str) -> List[str]:
        """Split a normalized name into component words."""
        # Already normalized (lowercase, no underscores)
        # Try to split on common word boundaries
        words = []

        # Common suffixes to look for
        suffixes = ['name', 'id', 'date', 'time', 'type', 'code', 'number', 'count',
                    'price', 'cost', 'amount', 'total', 'address', 'phone', 'email']

        remaining = name
        for suffix in suffixes:
            if remaining.endswith(suffix) and len(remaining) > len(suffix):
                prefix = remaining[:-len(suffix)]
                if prefix:  # Don't add empty prefix
                    words.append(self._singularize(prefix))
                words.append(suffix)
                remaining = ''
                break

        if remaining:
            words.append(self._singularize(remaining))

        return words if words else [name]

    def _singularize(self, word: str) -> str:
        """Simple singularization for common plural patterns."""
        if len(word) <= 2:
            return word

        # Common irregular plurals
        irregulars = {
            'addresses': 'address',
            'quantities': 'quantity',
            'activities': 'activity',
            'entries': 'entry',
        }
        if word in irregulars:
            return irregulars[word]

        # Standard plural rules (reverse order)
        if word.endswith('ies') and len(word) > 3:
            return word[:-3] + 'y'
        if word.endswith('es') and len(word) > 2:
            # Only if the base ends in s, x, z, ch, sh
            base = word[:-2]
            if base.endswith(('s', 'x', 'z', 'ch', 'sh')):
                return base
        if word.endswith('s') and not word.endswith('ss'):
            return word[:-1]

        return word

    def _normalize_name(self, name: str) -> str:
        """Normalize a field name for comparison"""
        # Remove array indices
        name = re.sub(r'\[\d+\]', '', name)
        # Convert to lowercase
        name = name.lower()
        # Replace underscores and hyphens with nothing
        name = re.sub(r'[_-]', '', name)
        return name

    def _types_compatible(self, type1: str, type2: str) -> bool:
        """Check if two types are compatible"""
        # Same type
        if type1 == type2:
            return True

        # Number compatibility
        number_types = {'number', 'integer', 'float', 'decimal'}
        if type1 in number_types and type2 in number_types:
            return True

        # String-like types
        string_types = {'string', 'text'}
        if type1 in string_types and type2 in string_types:
            return True

        return False

    def _array_similarity(self, v1: FieldInfo, v2: FieldInfo) -> float:
        """Calculate similarity between two arrays based on their children"""
        if not v1.children or not v2.children:
            return 0.0

        # Get child field names (without array indices)
        v1_child_names = set(self._get_field_name(c) for c in v1.children)
        v2_child_names = set(self._get_field_name(c) for c in v2.children)

        # Calculate Jaccard similarity
        intersection = len(v1_child_names & v2_child_names)
        union = len(v1_child_names | v2_child_names)

        if union == 0:
            return 0.0

        return intersection / union

    def _get_field_name(self, path: str) -> str:
        """Extract the field name from a path"""
        # Remove array indices
        path = re.sub(r'\[\d+\]', '', path)
        # Get last component
        parts = path.split('.')
        return parts[-1] if parts else path

    def _get_parent_path(self, path: str) -> Optional[str]:
        """Get the parent path of a field"""
        # Handle array paths like 'foo[0].bar'
        if '.' in path:
            return path.rsplit('.', 1)[0]
        elif '[' in path:
            return path.rsplit('[', 1)[0]
        return None

    def match_arrays(self,
                     v1_structure: Dict,
                     v2_structure: Dict,
                     min_confidence: float = 0.6) -> List[MatchResult]:
        """
        Find matching array structures between V1 and V2.

        This is specifically for matching entire arrays (like language_fields[])
        rather than individual fields within arrays.

        Returns list of array-level matches.
        """
        v1_index = self.build_field_index(v1_structure)
        v2_index = self.build_field_index(v2_structure)

        # Filter to only arrays
        v1_arrays = {k: v for k, v in v1_index.items() if v.is_array}
        v2_arrays = {k: v for k, v in v2_index.items() if v.is_array}

        matches = []

        for v1_path, v1_info in v1_arrays.items():
            best_match = None
            best_score = 0

            for v2_path, v2_info in v2_arrays.items():
                # Calculate array structure similarity
                score, match_type, reasons = self._calculate_array_match(v1_info, v2_info, v1_structure, v2_structure)

                if score > best_score and score >= min_confidence:
                    best_score = score
                    best_match = (v2_path, score, match_type, reasons)

            if best_match:
                v2_path, confidence, match_type, reasons = best_match
                matches.append(MatchResult(
                    v1_path=v1_path,
                    v2_path=v2_path,
                    confidence=confidence,
                    match_type='array_' + match_type,
                    reasons=reasons
                ))

        return sorted(matches, key=lambda m: m.confidence, reverse=True)

    def _calculate_array_match(self,
                               v1: FieldInfo,
                               v2: FieldInfo,
                               v1_structure: Dict,
                               v2_structure: Dict) -> Tuple[float, str, List[str]]:
        """
        Calculate match score for two arrays based on their internal structure.
        """
        reasons = []
        scores = []

        # 1. Array name similarity
        name_sim = self._name_similarity(v1.name, v2.name)
        if name_sim >= 0.8:
            reasons.append(f"Array name match: '{v1.name}' ~ '{v2.name}'")
            scores.append(name_sim * 0.3)

        # 2. Child field similarity (most important for arrays)
        v1_fields = self._get_array_item_fields(v1.path, v1_structure)
        v2_fields = self._get_array_item_fields(v2.path, v2_structure)

        if v1_fields and v2_fields:
            # Compare field names
            v1_names = set(self._get_field_name(f) for f in v1_fields)
            v2_names = set(self._get_field_name(f) for f in v2_fields)

            common = v1_names & v2_names
            union = v1_names | v2_names

            if union:
                field_sim = len(common) / len(union)
                if field_sim > 0:
                    reasons.append(f"Common fields: {common} ({field_sim:.0%})")
                    scores.append(field_sim * 0.5)

        # 3. Similar item count (weak signal)
        if v1.array_count > 0 and v2.array_count > 0:
            count_ratio = min(v1.array_count, v2.array_count) / max(v1.array_count, v2.array_count)
            if count_ratio > 0.5:
                reasons.append(f"Similar item count: {v1.array_count} vs {v2.array_count}")
                scores.append(count_ratio * 0.1)

        # 4. Parent structure similarity
        if v1.parent_path and v2.parent_path:
            v1_parent = self._get_field_name(v1.parent_path)
            v2_parent = self._get_field_name(v2.parent_path)
            parent_sim = self._name_similarity(v1_parent, v2_parent)
            if parent_sim >= 0.7:
                reasons.append(f"Similar parent: '{v1_parent}' ~ '{v2_parent}'")
                scores.append(parent_sim * 0.1)

        total = sum(scores) if scores else 0
        match_type = 'structural' if total > 0.5 else 'weak'

        return total, match_type, reasons

    def _get_array_item_fields(self, array_path: str, structure: Dict) -> List[str]:
        """Get the fields inside array items (e.g., fields under array[0])"""
        prefix = array_path + '['
        fields = []

        for path in structure.keys():
            if path.startswith(prefix):
                # Get the field part after the array index
                # e.g., 'array[0].name' -> 'name'
                match = re.match(rf'{re.escape(array_path)}\[\d+\]\.(.+)$', path)
                if match:
                    fields.append(match.group(1))

        return list(set(fields))  # Unique field names


def main():
    """CLI for testing semantic matching"""
    import sys
    from data_structure_extractor import DataStructureExtractor
    from merge_data_fetcher import MergeDataFetcher

    if len(sys.argv) < 2:
        print("Usage: python semantic_matcher.py <project_id>")
        sys.exit(1)

    project_id = sys.argv[1]

    print(f"\n🔍 Semantic Matching for Project {project_id}")
    print("=" * 70)

    # Fetch data
    fetcher = MergeDataFetcher()

    print("\n1️⃣  Fetching merge data...")
    v1_data = fetcher.fetch_v1_merge_data(project_id)
    v2_data = fetcher.fetch_v2_merge_data(project_id)

    if not v1_data or not v2_data:
        print("❌ Failed to fetch merge data")
        sys.exit(1)

    # Extract structures
    print("\n2️⃣  Extracting structures...")
    extractor = DataStructureExtractor(template_only=True)
    v1_structure = extractor.extract_structure(v1_data)
    v2_structure = extractor.extract_structure(v2_data)

    print(f"   V1: {len(v1_structure)} fields")
    print(f"   V2: {len(v2_structure)} fields")

    # Find semantic matches
    print("\n3️⃣  Finding semantic matches...")
    matcher = SemanticMatcher()
    matches = matcher.find_matches(v1_structure, v2_structure, min_confidence=0.6)

    print(f"\n📊 Found {len(matches)} matches with confidence >= 60%")
    print("\n" + "-" * 70)

    # Group by confidence level
    high_conf = [m for m in matches if m.confidence >= 0.9]
    med_conf = [m for m in matches if 0.7 <= m.confidence < 0.9]
    low_conf = [m for m in matches if m.confidence < 0.7]

    if high_conf:
        print(f"\n✅ High Confidence (≥90%): {len(high_conf)} matches")
        for m in high_conf[:10]:
            print(f"   {m.v1_path:40} → {m.v2_path}")
            print(f"      {m.confidence:.0%} [{m.match_type}]: {', '.join(m.reasons[:2])}")

    if med_conf:
        print(f"\n⚠️  Medium Confidence (70-89%): {len(med_conf)} matches")
        for m in med_conf[:10]:
            print(f"   {m.v1_path:40} → {m.v2_path}")
            print(f"      {m.confidence:.0%} [{m.match_type}]: {', '.join(m.reasons[:2])}")

    # Array matches
    print("\n4️⃣  Finding array structure matches...")
    array_matches = matcher.match_arrays(v1_structure, v2_structure)

    if array_matches:
        print(f"\n📦 Array Matches: {len(array_matches)}")
        for m in array_matches:
            print(f"   {m.v1_path:40} → {m.v2_path}")
            print(f"      {m.confidence:.0%}: {', '.join(m.reasons)}")
    else:
        print("\n   No array matches found")


if __name__ == '__main__':
    main()
