#!/usr/bin/env python3
"""
Template Version Tracker
Tracks uploaded templates and manages versioning
"""

import json
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional


class TemplateVersionTracker:
    """
    Tracks uploaded template versions and helps manage duplicates
    """

    def __init__(self, cache_dir=None):
        """
        Initialize the version tracker

        Args:
            cache_dir: Directory to store version cache (default: ~/.scopestack/versions)
        """
        if cache_dir is None:
            cache_dir = Path.home() / '.scopestack' / 'versions'

        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)

        self.versions_file = self.cache_dir / 'template_versions.json'
        self.versions = self._load_versions()

    def _load_versions(self) -> Dict:
        """Load version tracking data from disk"""
        if self.versions_file.exists():
            try:
                with open(self.versions_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"⚠️  Could not load version tracking: {e}")
        return {}

    def _save_versions(self):
        """Save version tracking data to disk"""
        try:
            with open(self.versions_file, 'w') as f:
                json.dump(self.versions, f, indent=2)
        except Exception as e:
            print(f"⚠️  Could not save version tracking: {e}")

    def get_template_info(self, template_name: str) -> Optional[Dict]:
        """
        Get information about a template by name

        Args:
            template_name: Base template name (without version suffix)

        Returns:
            Dict with template info or None if not found
        """
        return self.versions.get(template_name)

    def has_template(self, template_name: str) -> bool:
        """Check if a template name already exists"""
        return template_name in self.versions

    def generate_versioned_name(self, base_name: str) -> str:
        """
        Generate a versioned template name with timestamp

        Args:
            base_name: Base template name

        Returns:
            Versioned name like "Template-Name-2026-01-17-14-30-45"
            (sanitized to only include letters, numbers, dashes, and spaces)
        """
        import re

        # Sanitize base_name: only letters, numbers, dashes, and spaces
        # Replace underscores with dashes
        sanitized = base_name.replace('_', '-')
        # Remove parentheses and other invalid characters
        sanitized = re.sub(r'[^a-zA-Z0-9\s-]', '', sanitized)
        # Replace multiple spaces/dashes with single dash
        sanitized = re.sub(r'[\s-]+', '-', sanitized)
        # Remove leading/trailing dashes
        sanitized = sanitized.strip('-')

        timestamp = datetime.now().strftime('%Y-%m-%d-%H-%M-%S')
        return f"{sanitized}-{timestamp}"

    def record_template(
        self,
        template_name: str,
        template_id: str,
        action: str = 'created',
        replaced_id: Optional[str] = None
    ):
        """
        Record a template upload

        Args:
            template_name: Template name
            template_id: Template ID from ScopeStack
            action: 'created' or 'replaced'
            replaced_id: ID of template that was replaced (if action='replaced')
        """
        if template_name not in self.versions:
            self.versions[template_name] = {
                'base_name': template_name,
                'current_id': template_id,
                'created_at': datetime.now().isoformat(),
                'history': []
            }

        # Update current ID
        old_id = self.versions[template_name].get('current_id')
        self.versions[template_name]['current_id'] = template_id
        self.versions[template_name]['updated_at'] = datetime.now().isoformat()

        # Record in history
        history_entry = {
            'template_id': template_id,
            'action': action,
            'timestamp': datetime.now().isoformat()
        }

        if action == 'replaced' and old_id:
            history_entry['replaced_id'] = old_id

        self.versions[template_name]['history'].append(history_entry)

        # Keep only last 10 history entries
        if len(self.versions[template_name]['history']) > 10:
            self.versions[template_name]['history'] = self.versions[template_name]['history'][-10:]

        self._save_versions()

    def get_all_templates(self) -> List[Dict]:
        """Get list of all tracked templates"""
        return [
            {
                'name': name,
                'current_id': info['current_id'],
                'created_at': info.get('created_at'),
                'updated_at': info.get('updated_at'),
                'version_count': len(info.get('history', []))
            }
            for name, info in self.versions.items()
        ]

    def clear_cache(self):
        """Clear all version tracking data"""
        self.versions = {}
        self._save_versions()
        print("✓ Version tracking cleared")


def main():
    """CLI for version tracker"""
    import sys

    tracker = TemplateVersionTracker()

    if len(sys.argv) < 2:
        print("Template Version Tracker")
        print("\nCommands:")
        print("  list   - List all tracked templates")
        print("  clear  - Clear version tracking cache")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == 'list':
        templates = tracker.get_all_templates()
        if templates:
            print("\n📋 Tracked Templates:")
            for tmpl in templates:
                print(f"\n  {tmpl['name']}")
                print(f"    Current ID: {tmpl['current_id']}")
                print(f"    Versions: {tmpl['version_count']}")
                if tmpl.get('updated_at'):
                    print(f"    Last updated: {tmpl['updated_at']}")
        else:
            print("\nNo templates tracked yet")

    elif command == 'clear':
        confirm = input("Are you sure you want to clear all version tracking? (yes/no): ")
        if confirm.lower() == 'yes':
            tracker.clear_cache()
        else:
            print("Cancelled")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()
