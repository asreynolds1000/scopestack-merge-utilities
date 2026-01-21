#!/usr/bin/env python3
"""
Path Coherence Scoring Algorithm
==================================

Scores v2 mapping suggestions based on structural coherence.
When multiple v2 paths could match a v1 field, prefer paths that:
1. Stay within the same structural block (loop context)
2. Maintain parallel path structure
3. Keep related fields together

Example:
    v1 block (coherent structure):
        phases_with_tasks:each(phase)
            phase.tasks:each(task)
                =task.name

    Should map to parallel v2 block:
        {#project_pricing.professional_services.phases}
            {#services}
                {name}

    NOT to unrelated paths like:
        {#some_other_array}
            {#different_services}
                {name}
"""

from typing import List, Dict, Set, Tuple
import re


class PathCoherenceScorer:
    """Score mapping suggestions based on structural coherence"""

    def __init__(self):
        self.v1_context_stack = []  # Track current loop context in v1
        self.v2_context_stack = []  # Track suggested v2 context

    def parse_v1_structure(self, fields: List[str]) -> Dict[str, Dict]:
        """
        Parse v1 fields to understand loop structure and context

        Returns:
            Dict mapping each field to its context info:
            {
                'field_name': {
                    'type': 'simple' | 'loop' | 'conditional',
                    'context_path': ['parent_loop', 'child_loop'],
                    'depth': 2,
                    'siblings': ['other', 'fields', 'at', 'same', 'level']
                }
            }
        """
        structure = {}
        context_stack = []
        current_siblings = {}  # Track fields at each depth level

        for field in fields:
            field_info = self._analyze_v1_field(field)

            if field_info['type'] == 'loop_start':
                # Entering a loop
                loop_var = field_info['loop_variable']
                context_stack.append(loop_var)

                # Initialize sibling tracking for this depth
                depth = len(context_stack)
                if depth not in current_siblings:
                    current_siblings[depth] = []

            elif field_info['type'] == 'loop_end':
                # Exiting a loop
                if context_stack:
                    context_stack.pop()

            else:
                # Regular field (simple or conditional)
                depth = len(context_stack)
                context_path = list(context_stack)

                # Track this field
                structure[field] = {
                    'type': field_info['type'],
                    'context_path': context_path,
                    'depth': depth,
                    'siblings': current_siblings.get(depth, []).copy()
                }

                # Add to siblings list
                if depth not in current_siblings:
                    current_siblings[depth] = []
                current_siblings[depth].append(field)

        return structure

    def _analyze_v1_field(self, field: str) -> Dict:
        """Analyze a single v1 field to determine its type"""
        if ':each' in field:
            # Extract loop variable: "resources:each(resource)" -> "resource"
            match = re.search(r':each\((\w+)\)', field)
            loop_var = match.group(1) if match else field.split(':each')[0]
            return {
                'type': 'loop_start',
                'loop_variable': loop_var,
                'array_field': field.split(':each')[0]
            }
        elif ':end' in field:
            return {'type': 'loop_end'}
        elif ':if' in field:
            return {'type': 'conditional', 'field': field.split(':if')[0]}
        elif field.startswith('='):
            return {'type': 'simple', 'field': field[1:]}
        else:
            return {'type': 'simple', 'field': field}

    def score_v2_candidate(
        self,
        v1_field: str,
        v2_candidate: str,
        v1_structure: Dict,
        current_v2_context: List[str],
        other_v2_candidates: List[str]
    ) -> float:
        """
        Score a v2 path candidate based on coherence

        Args:
            v1_field: The v1 field being mapped
            v2_candidate: The v2 path being considered
            v1_structure: Parsed v1 structure from parse_v1_structure()
            current_v2_context: Current v2 loop context we're in
            other_v2_candidates: Other possible v2 paths for comparison

        Returns:
            Score from 0.0 to 1.0, where higher = more coherent
        """
        score = 0.0

        # Get v1 field context
        v1_info = v1_structure.get(v1_field, {})
        v1_context_path = v1_info.get('context_path', [])
        v1_depth = v1_info.get('depth', 0)

        # Parse v2 path to understand its structure
        v2_parts = self._parse_v2_path(v2_candidate)
        v2_depth = len([p for p in v2_parts if p['type'] == 'array'])

        # RULE 1: Depth Matching (30% weight)
        # Prefer v2 paths with similar nesting depth
        if v1_depth == v2_depth:
            score += 0.3
        elif abs(v1_depth - v2_depth) == 1:
            score += 0.15
        # else: 0 points for depth

        # RULE 2: Context Path Coherence (40% weight)
        # If we're inside v2 loops, prefer paths that stay within those loops
        if current_v2_context:
            v2_part_names = [p['name'] for p in v2_parts[:len(current_v2_context)]]
            v2_candidate_prefix = '.'.join(v2_part_names)
            expected_prefix = '.'.join(current_v2_context)

            if v2_candidate_prefix == expected_prefix or v2_candidate.startswith(expected_prefix):
                score += 0.4  # Stays within current context
            elif self._shares_common_prefix(v2_candidate, expected_prefix):
                score += 0.2  # Partial match
            # else: 0 points

        # RULE 3: Sibling Coherence (30% weight)
        # If siblings have been mapped to a certain v2 prefix, prefer same prefix
        if v1_info.get('siblings'):
            sibling_v2_paths = self._get_sibling_v2_paths(
                v1_info['siblings'],
                other_v2_candidates
            )

            if sibling_v2_paths:
                # Calculate most common prefix among siblings
                common_prefix = self._find_common_prefix(sibling_v2_paths)

                if v2_candidate.startswith(common_prefix):
                    coherence_ratio = len(common_prefix) / len(v2_candidate)
                    score += 0.3 * coherence_ratio

        return min(score, 1.0)  # Cap at 1.0

    def _parse_v2_path(self, v2_path: str) -> List[Dict]:
        """
        Parse a v2 path into components

        Example:
            "project.pricing.phases[].services[].name"
            -> [
                {'type': 'object', 'name': 'project'},
                {'type': 'object', 'name': 'pricing'},
                {'type': 'array', 'name': 'phases'},
                {'type': 'array', 'name': 'services'},
                {'type': 'field', 'name': 'name'}
            ]
        """
        parts = []
        segments = v2_path.split('.')

        for segment in segments:
            if '[]' in segment or '#' in segment:
                # Array indicator
                clean_name = segment.replace('[]', '').replace('#', '').replace('{', '').replace('}', '')
                parts.append({'type': 'array', 'name': clean_name})
            else:
                # Object or field
                clean_name = segment.replace('{', '').replace('}', '')
                parts.append({'type': 'object', 'name': clean_name})

        # Last one is usually a field
        if parts and parts[-1]['type'] == 'object':
            parts[-1]['type'] = 'field'

        return parts

    def _shares_common_prefix(self, path1: str, path2: str) -> bool:
        """Check if two paths share a meaningful common prefix"""
        parts1 = path1.split('.')
        parts2 = path2.split('.')

        common_length = 0
        for p1, p2 in zip(parts1, parts2):
            if p1 == p2:
                common_length += 1
            else:
                break

        return common_length >= 2  # At least 2 levels in common

    def _get_sibling_v2_paths(
        self,
        sibling_v1_fields: List[str],
        v2_candidates: List[str]
    ) -> List[str]:
        """
        Get v2 paths that siblings have been mapped to

        This is a simplified version - in reality you'd look up
        actual mappings from the database or current session
        """
        # Placeholder: would query mapping database for sibling mappings
        return []

    def _find_common_prefix(self, paths: List[str]) -> str:
        """Find the longest common prefix among a list of paths"""
        if not paths:
            return ""

        # Split all paths
        split_paths = [p.split('.') for p in paths]

        # Find common prefix
        common = []
        for parts in zip(*split_paths):
            if len(set(parts)) == 1:  # All the same
                common.append(parts[0])
            else:
                break

        return '.'.join(common)

    def rank_v2_candidates(
        self,
        v1_field: str,
        v2_candidates: List[Tuple[str, str]],  # [(v2_path, match_reason), ...]
        v1_structure: Dict,
        current_v2_context: List[str] = None
    ) -> List[Dict]:
        """
        Rank all v2 candidates for a v1 field by coherence score

        Returns:
            List of ranked candidates with scores:
            [
                {
                    'v2_path': 'project.pricing.phases[].services[].name',
                    'match_reason': 'value_match',
                    'coherence_score': 0.85,
                    'confidence': 'high'
                },
                ...
            ]
        """
        if current_v2_context is None:
            current_v2_context = []

        ranked = []
        v2_paths = [c[0] for c in v2_candidates]

        for v2_path, match_reason in v2_candidates:
            coherence_score = self.score_v2_candidate(
                v1_field=v1_field,
                v2_candidate=v2_path,
                v1_structure=v1_structure,
                current_v2_context=current_v2_context,
                other_v2_candidates=v2_paths
            )

            # Determine confidence based on score
            if coherence_score >= 0.7:
                confidence = 'high'
            elif coherence_score >= 0.4:
                confidence = 'medium'
            else:
                confidence = 'low'

            ranked.append({
                'v2_path': v2_path,
                'match_reason': match_reason,
                'coherence_score': coherence_score,
                'confidence': confidence
            })

        # Sort by coherence score (highest first)
        ranked.sort(key=lambda x: x['coherence_score'], reverse=True)

        return ranked


def main():
    """Test the path coherence scorer"""
    scorer = PathCoherenceScorer()

    # Example v1 template structure
    v1_fields = [
        'phases_with_tasks:each(phase)',
        '=phase.name',
        'phase.tasks:each(task)',
        '=task.name',
        '=task.description',
        'phase.tasks:end',
        'phases_with_tasks:end'
    ]

    # Parse structure
    structure = scorer.parse_v1_structure(v1_fields)
    print("Parsed v1 structure:")
    for field, info in structure.items():
        print(f"  {field}: depth={info['depth']}, context={info['context_path']}")

    # Test scoring
    v2_candidates = [
        ('project.pricing.phases[].services[].name', 'value_match'),
        ('some_other_array[].random_field[].name', 'value_match'),
        ('project.tasks[].name', 'value_match')
    ]

    current_context = ['project', 'pricing', 'phases']
    ranked = scorer.rank_v2_candidates(
        v1_field='=task.name',
        v2_candidates=v2_candidates,
        v1_structure=structure,
        current_v2_context=current_context
    )

    print("\nRanked v2 candidates for '=task.name':")
    for candidate in ranked:
        print(f"  {candidate['v2_path']}")
        print(f"    Score: {candidate['coherence_score']:.2f} ({candidate['confidence']})")
        print(f"    Reason: {candidate['match_reason']}")


if __name__ == '__main__':
    main()
