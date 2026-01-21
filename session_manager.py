#!/usr/bin/env python3
"""
AI Conversion Session Manager
Saves and restores AI improvement sessions for later continuation
"""

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional


class SessionManager:
    """
    Manages AI improvement sessions - save progress and resume later
    """

    def __init__(self, cache_dir=None):
        """
        Initialize the session manager

        Args:
            cache_dir: Directory to store sessions (default: ~/.scopestack/sessions)
        """
        if cache_dir is None:
            cache_dir = Path.home() / '.scopestack' / 'sessions'

        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)

        self.sessions_file = self.cache_dir / 'active_sessions.json'
        self.sessions = self._load_sessions()

    def _load_sessions(self) -> Dict:
        """Load session data from disk"""
        if self.sessions_file.exists():
            try:
                with open(self.sessions_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"⚠️  Could not load sessions: {e}")
        return {}

    def _save_sessions(self):
        """Save session data to disk"""
        try:
            with open(self.sessions_file, 'w') as f:
                json.dump(self.sessions, f, indent=2)
        except Exception as e:
            print(f"⚠️  Could not save sessions: {e}")

    def create_session(
        self,
        v1_template_id: str,
        v2_template_id: str,
        project_id: str,
        session_name: Optional[str] = None
    ) -> str:
        """
        Create a new AI improvement session

        Args:
            v1_template_id: Original V1 template ID
            v2_template_id: Current V2 template ID
            project_id: Project ID
            session_name: Optional custom session name

        Returns:
            session_id: Unique session identifier
        """
        # Generate session ID
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        session_id = f"session_{timestamp}"

        if session_name is None:
            session_name = f"Improvement Session {timestamp}"

        # Create session record
        self.sessions[session_id] = {
            'session_name': session_name,
            'v1_template_id': v1_template_id,
            'v2_template_id': v2_template_id,
            'project_id': project_id,
            'created_at': datetime.now().isoformat(),
            'updated_at': datetime.now().isoformat(),
            'iterations': [],
            'total_iterations': 0,
            'current_similarity': 0.0,
            'status': 'active',
            'user_feedback': []
        }

        self._save_sessions()
        print(f"✓ Created session: {session_id} - {session_name}")
        return session_id

    def update_session(
        self,
        session_id: str,
        iterations: List[Dict],
        final_similarity: float,
        final_template_id: str,
        status: str = 'active'
    ):
        """
        Update session with iteration results

        Args:
            session_id: Session identifier
            iterations: List of iteration results
            final_similarity: Final similarity score
            final_template_id: Latest template ID
            status: Session status (active, completed, paused)
        """
        if session_id not in self.sessions:
            print(f"⚠️  Session not found: {session_id}")
            return

        session = self.sessions[session_id]

        # Append new iterations to existing ones
        session['iterations'].extend(iterations)
        session['total_iterations'] = len(session['iterations'])
        session['current_similarity'] = final_similarity
        session['v2_template_id'] = final_template_id
        session['status'] = status
        session['updated_at'] = datetime.now().isoformat()

        self._save_sessions()
        print(f"✓ Updated session: {session_id}")

    def add_user_feedback(
        self,
        session_id: str,
        feedback: str,
        iteration_context: Optional[int] = None
    ):
        """
        Add user feedback to a session

        Args:
            session_id: Session identifier
            feedback: User's feedback/suggestions
            iteration_context: Which iteration this feedback relates to
        """
        if session_id not in self.sessions:
            print(f"⚠️  Session not found: {session_id}")
            return

        feedback_entry = {
            'feedback': feedback,
            'timestamp': datetime.now().isoformat(),
            'iteration_context': iteration_context or self.sessions[session_id]['total_iterations']
        }

        self.sessions[session_id]['user_feedback'].append(feedback_entry)
        self._save_sessions()

    def get_session(self, session_id: str) -> Optional[Dict]:
        """
        Get session data

        Args:
            session_id: Session identifier

        Returns:
            Session data or None if not found
        """
        return self.sessions.get(session_id)

    def get_active_sessions(self) -> List[Dict]:
        """Get all active sessions"""
        active = []
        for session_id, session_data in self.sessions.items():
            if session_data.get('status') == 'active':
                active.append({
                    'session_id': session_id,
                    'session_name': session_data['session_name'],
                    'created_at': session_data['created_at'],
                    'updated_at': session_data['updated_at'],
                    'total_iterations': session_data['total_iterations'],
                    'current_similarity': session_data['current_similarity'],
                    'v2_template_id': session_data['v2_template_id']
                })

        # Sort by updated_at descending
        active.sort(key=lambda x: x['updated_at'], reverse=True)
        return active

    def get_session_summary(self, session_id: str) -> Optional[str]:
        """
        Get a human-readable summary of a session for AI context

        Args:
            session_id: Session identifier

        Returns:
            Summary text for AI prompt
        """
        session = self.get_session(session_id)
        if not session:
            return None

        summary = f"SESSION HISTORY:\n"
        summary += f"Total iterations completed: {session['total_iterations']}\n"
        summary += f"Current similarity: {session['current_similarity'] * 100:.1f}%\n\n"

        # Add iteration history
        if session['iterations']:
            summary += "Previous iterations:\n"
            for i, iteration in enumerate(session['iterations'][-5:], 1):  # Last 5 iterations
                summary += f"  {i}. Similarity: {iteration.get('similarity', 0) * 100:.1f}%, "
                summary += f"Errors: {iteration.get('syntax_errors', 0)}, "
                summary += f"Fixes: {iteration.get('fixes_applied', 0)}\n"

        # Add user feedback
        if session['user_feedback']:
            summary += "\nUser feedback from previous rounds:\n"
            for fb in session['user_feedback']:
                summary += f"  - (After iteration {fb['iteration_context']}): {fb['feedback']}\n"

        return summary

    def mark_completed(self, session_id: str):
        """Mark a session as completed"""
        if session_id in self.sessions:
            self.sessions[session_id]['status'] = 'completed'
            self.sessions[session_id]['completed_at'] = datetime.now().isoformat()
            self._save_sessions()

    def delete_session(self, session_id: str):
        """Delete a session"""
        if session_id in self.sessions:
            del self.sessions[session_id]
            self._save_sessions()
            print(f"✓ Deleted session: {session_id}")

    def clear_old_sessions(self, days: int = 30):
        """
        Clear sessions older than specified days

        Args:
            days: Delete sessions older than this many days
        """
        from datetime import timedelta
        cutoff = datetime.now() - timedelta(days=days)

        to_delete = []
        for session_id, session_data in self.sessions.items():
            updated_at = datetime.fromisoformat(session_data['updated_at'])
            if updated_at < cutoff:
                to_delete.append(session_id)

        for session_id in to_delete:
            del self.sessions[session_id]

        if to_delete:
            self._save_sessions()
            print(f"✓ Deleted {len(to_delete)} old sessions")

    def update_progress(self, session_id: str, progress_data: Dict):
        """
        Update real-time progress for an async improvement session.
        Used for UI polling during background processing.

        Args:
            session_id: Session ID
            progress_data: Dict with progress info like:
                {
                    'iteration': 1,
                    'status': 'comparing_documents',
                    'similarity': 0.45,
                    'message': 'Comparing documents...',
                    'errors_found': 3
                }
        """
        if session_id not in self.sessions:
            # Create a new progress-only session if needed
            self.sessions[session_id] = {
                'session_name': f'Session {session_id[:8]}',
                'created_at': datetime.now().isoformat(),
                'status': 'in_progress',
                'progress': {}
            }

        # Update progress data
        self.sessions[session_id]['progress'] = {
            **progress_data,
            'timestamp': datetime.now().isoformat()
        }
        self.sessions[session_id]['updated_at'] = datetime.now().isoformat()

        self._save_sessions()

    def get_progress(self, session_id: str) -> Dict:
        """
        Get current progress for a session.
        Used by UI polling endpoint.

        Returns:
            Dict with current progress data or error if not found
        """
        if session_id not in self.sessions:
            return {
                'success': False,
                'error': 'Session not found'
            }

        session = self.sessions[session_id]
        progress = session.get('progress', {})

        return {
            'success': True,
            'session_id': session_id,
            'status': session.get('status', 'unknown'),
            'iteration': progress.get('iteration', 0),
            'current_status': progress.get('status', ''),
            'similarity': progress.get('similarity', 0.0),
            'message': progress.get('message', ''),
            'errors_found': progress.get('errors_found', 0),
            'timestamp': progress.get('timestamp', ''),
            # Include full session data for completeness
            'total_iterations': session.get('total_iterations', 0),
            'current_similarity': session.get('current_similarity', 0.0),
            'iterations': session.get('iterations', [])
        }


def main():
    """CLI for session manager"""
    import sys

    manager = SessionManager()

    if len(sys.argv) < 2:
        print("AI Conversion Session Manager")
        print("\nCommands:")
        print("  list    - List all active sessions")
        print("  view    - View session details (requires session_id)")
        print("  clean   - Clean old sessions")
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == 'list':
        sessions = manager.get_active_sessions()
        if sessions:
            print("\n📋 Active Sessions:")
            for sess in sessions:
                print(f"\n  {sess['session_name']}")
                print(f"    ID: {sess['session_id']}")
                print(f"    Iterations: {sess['total_iterations']}")
                print(f"    Similarity: {sess['current_similarity'] * 100:.1f}%")
                print(f"    Updated: {sess['updated_at']}")
        else:
            print("\nNo active sessions found")

    elif command == 'view':
        if len(sys.argv) < 3:
            print("Usage: python session_manager.py view <session_id>")
            sys.exit(1)

        session_id = sys.argv[2]
        summary = manager.get_session_summary(session_id)
        if summary:
            print(f"\n{summary}")
        else:
            print(f"Session not found: {session_id}")

    elif command == 'clean':
        confirm = input("Delete sessions older than 30 days? (yes/no): ")
        if confirm.lower() == 'yes':
            manager.clear_old_sessions(30)
        else:
            print("Cancelled")

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == '__main__':
    main()
