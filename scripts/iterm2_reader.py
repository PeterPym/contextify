#!/usr/bin/env python3
"""
iTerm2 Python API content reader.

Connects to iTerm2's Python API and extracts the current session's
terminal content (visible screen + scrollback buffer).

Returns JSON:
{
    "success": true,
    "content": "full terminal text...",
    "line_count": 123
}

Or on error:
{
    "success": false,
    "error": "error_type",
    "details": "human readable message"
}
"""

import sys
import os

# Add bundled Python packages to path if they exist
# When run from app bundle: /path/to/App.app/Contents/Resources/iterm2_reader.py
# Bundled packages at: /path/to/App.app/Contents/Resources/Python/lib/python/site-packages
script_dir = os.path.dirname(os.path.abspath(__file__))
bundled_packages = os.path.join(script_dir, "Python", "lib", "python", "site-packages")

# Also try project structure for dev mode
if not os.path.exists(bundled_packages):
    project_root = os.path.dirname(script_dir)  # Up from scripts/
    bundled_packages = os.path.join(project_root, "Resources", "Python", "lib", "python", "site-packages")

if os.path.exists(bundled_packages):
    sys.path.insert(0, bundled_packages)

import iterm2
import asyncio
import json


async def get_session_content():
    """Extract content from the current iTerm2 session."""
    try:
        # Connect to iTerm2
        connection = await iterm2.Connection.async_create()
        app = await iterm2.async_get_app(connection)

        # Get current window
        window = app.current_terminal_window
        if not window:
            return {
                "success": False,
                "error": "no_active_window",
                "details": "No active iTerm2 window found"
            }

        # Get current session
        tab = window.current_tab
        if not tab:
            return {
                "success": False,
                "error": "no_active_tab",
                "details": "No active tab in current window"
            }

        session = tab.current_session
        if not session:
            return {
                "success": False,
                "error": "no_active_session",
                "details": "No active session in current tab"
            }

        # Try to get selection first (captures active input buffer)
        try:
            selection = await session.async_get_selection()
            selected_text = await session.async_get_selection_text()

            if selected_text and selected_text.strip():
                return {
                    "success": True,
                    "content": selected_text,
                    "line_count": selected_text.count('\n') + 1,
                    "session_name": session.name if hasattr(session, 'name') else None,
                    "source": "selection"
                }
        except (AttributeError, TypeError):
            # Selection API not available or no selection
            pass

        # Fallback: Get screen contents (visible + scrollback)
        screen = await session.async_get_screen_contents()

        # Extract all lines
        lines = []
        for i in range(screen.number_of_lines):
            line = screen.line(i)
            lines.append(line.string)

        content = "\n".join(lines)

        return {
            "success": True,
            "content": content,
            "line_count": len(lines),
            "session_name": session.name if hasattr(session, 'name') else None,
            "source": "screen_contents"
        }

    except ConnectionRefusedError as e:
        return {
            "success": False,
            "error": "connection_refused",
            "details": f"Could not connect to iTerm2: {e}. Is iTerm2 running?"
        }
    except Exception as e:
        return {
            "success": False,
            "error": "unexpected_error",
            "details": str(e),
            "exception_type": type(e).__name__
        }


def main():
    """Main entry point."""
    try:
        result = asyncio.run(get_session_content())
        print(json.dumps(result, indent=2))

        # Exit with appropriate code
        sys.exit(0 if result.get("success") else 1)

    except KeyboardInterrupt:
        print(json.dumps({
            "success": False,
            "error": "interrupted",
            "details": "Script interrupted by user"
        }), file=sys.stderr)
        sys.exit(130)
    except Exception as e:
        print(json.dumps({
            "success": False,
            "error": "fatal_error",
            "details": str(e),
            "exception_type": type(e).__name__
        }), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
