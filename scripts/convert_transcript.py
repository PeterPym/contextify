#!/usr/bin/env python3
"""
Transcript format converter: Claude Code ↔ Codex CLI

Converts between Claude Code and Codex CLI JSONL transcript formats to enable
conversation continuity across tools.

Usage:
  convert_transcript.py --from claude-code --to codex input.jsonl output.jsonl
  convert_transcript.py --from codex --to claude-code input.jsonl output.jsonl

Examples:
  # Claude Code → Codex CLI
  ./convert_transcript.py \\
    --from claude-code \\
    --to codex \\
    ~/.claude/projects/-Users-rob-code-project/session-uuid.jsonl \\
    ~/codex-output/converted-session.jsonl

  # Codex CLI → Claude Code
  ./convert_transcript.py \\
    --from codex \\
    --to claude-code \\
    ~/codex-sessions/session-123.jsonl \\
    ~/.claude/projects/-Users-rob-code-project/imported-session.jsonl
"""

import json
import argparse
import sys
import os
from datetime import datetime
from uuid import uuid4


class TranscriptConverter:
    """Bidirectional transcript converter"""

    def __init__(self, verbose=False):
        self.verbose = verbose
        self.stats = {
            'total_lines': 0,
            'converted': 0,
            'skipped': 0,
            'errors': 0
        }
        self.project_dir = None  # Extracted from transcript
        self.session_id = None   # For resume instructions
        self.suggested_codex_path = None  # Proper Codex session path

    def log(self, message):
        """Print verbose logging"""
        if self.verbose:
            print(f"[DEBUG] {message}", file=sys.stderr)

    def claude_to_codex(self, input_path, output_path):
        """Convert Claude Code JSONL to Codex CLI format"""
        session_id = str(uuid4())
        self.session_id = session_id
        first_message = True

        # ALWAYS ensure output path is correct for Codex
        # Check if filename has proper format: rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl
        import re
        basename = os.path.basename(output_path)
        uuid_pattern = r'rollout-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$'
        match = re.match(uuid_pattern, basename)

        if not match:
            # User provided incorrect filename - generate correct one
            now = datetime.now()
            codex_sessions_dir = os.path.expanduser(f'~/.codex/sessions/{now.year}/{now.month:02d}/{now.day:02d}')
            os.makedirs(codex_sessions_dir, exist_ok=True)

            timestamp = now.strftime('%Y-%m-%dT%H-%M-%S')
            codex_filename = f"rollout-{timestamp}-{session_id}.jsonl"
            corrected_path = os.path.join(codex_sessions_dir, codex_filename)

            self.log(f"Warning: Output filename doesn't match Codex format")
            self.log(f"User provided: {output_path}")
            self.log(f"Using instead: {corrected_path}")

            output_path = corrected_path
            self.suggested_codex_path = None  # Already corrected
        else:
            # Filename is correct format - extract UUID and use it
            filename_uuid = match.group(1)
            session_id = filename_uuid
            self.session_id = session_id
            self.log(f"Using UUID from filename: {session_id}")

        self.log(f"Converting Claude Code → Codex CLI")
        self.log(f"Input: {input_path}")
        self.log(f"Output: {output_path}")

        with open(input_path) as infile, open(output_path, 'w') as outfile:
            for line_num, line in enumerate(infile, 1):
                self.stats['total_lines'] += 1

                try:
                    record = json.loads(line)
                except json.JSONDecodeError as e:
                    self.log(f"Line {line_num}: JSON parse error: {e}")
                    self.stats['errors'] += 1
                    continue

                # Skip non-message records
                record_type = record.get('type')
                if record_type not in ['user', 'assistant']:
                    self.log(f"Line {line_num}: Skipping type={record_type}")
                    self.stats['skipped'] += 1
                    continue

                # Skip meta/sidechain
                if record.get('isMeta') or record.get('isSidechain'):
                    self.log(f"Line {line_num}: Skipping meta/sidechain")
                    self.stats['skipped'] += 1
                    continue

                # Validate required fields
                if 'timestamp' not in record:
                    self.log(f"Line {line_num}: Missing required field 'timestamp'")
                    self.stats['errors'] += 1
                    continue

                # Generate session_meta from first message
                if first_message:
                    cwd = record.get('cwd', '/')
                    self.project_dir = cwd  # Store for resume instructions

                    session_meta = {
                        "timestamp": record['timestamp'],
                        "type": "session_meta",
                        "payload": {
                            "id": session_id,
                            "timestamp": record['timestamp'],
                            "cwd": cwd,
                            "originator": "claude_code_converter",
                            "cli_version": "converted-1.0.0",
                            "instructions": None,
                            "source": "cli"  # REQUIRED: Must be "cli" or "vscode" to appear in picker
                        }
                    }
                    outfile.write(json.dumps(session_meta, separators=(',', ':')) + '\n')
                    self.log(f"Generated session_meta (session_id={session_id})")
                    first_message = False

                # Convert message
                message = record.get('message', {})
                content = message.get('content', '')

                # Normalize content to array format
                # Use "input_text" for user, "output_text" for assistant
                content_type = "input_text" if record_type == "user" else "output_text"

                if isinstance(content, str):
                    content_array = [{"type": content_type, "text": content}]
                    text_for_event = content
                elif isinstance(content, list):
                    # Already array, normalize type field
                    content_array = []
                    text_parts = []
                    for block in content:
                        if isinstance(block, dict) and block.get('text'):
                            content_array.append({
                                "type": content_type,
                                "text": block['text']
                            })
                            text_parts.append(block['text'])
                    text_for_event = '\n'.join(text_parts)
                else:
                    self.log(f"Line {line_num}: Unknown content format: {type(content)}")
                    self.stats['errors'] += 1
                    continue

                # Skip if no content
                if not content_array:
                    self.log(f"Line {line_num}: No extractable content")
                    self.stats['skipped'] += 1
                    continue

                codex_message = {
                    "timestamp": record['timestamp'],
                    "type": "response_item",
                    "payload": {
                        "type": "message",
                        "role": record_type,
                        "content": content_array
                    }
                }

                outfile.write(json.dumps(codex_message, separators=(',', ':')) + '\n')

                # REQUIRED: Add event_msg for user messages (needed for picker to show session)
                if record_type == "user":
                    event_msg = {
                        "timestamp": record['timestamp'],
                        "type": "event_msg",
                        "payload": {
                            "type": "user_message",
                            "message": text_for_event,
                            "kind": "plain"
                        }
                    }
                    outfile.write(json.dumps(event_msg, separators=(',', ':')) + '\n')

                self.stats['converted'] += 1
                self.log(f"Line {line_num}: Converted {record_type} message")

        return self.stats

    def codex_to_claude(self, input_path, output_path):
        """Convert Codex CLI JSONL to Claude Code format"""
        session_id = None
        git_context = {}

        self.log(f"Converting Codex CLI → Claude Code")
        self.log(f"Input: {input_path}")
        self.log(f"Output: {output_path}")

        # Extract session ID from output path for resume instructions
        import os
        basename = os.path.basename(output_path)
        if basename.endswith('.jsonl'):
            self.session_id = basename[:-6]  # Remove .jsonl extension

        with open(input_path) as infile, open(output_path, 'w') as outfile:
            for line_num, line in enumerate(infile, 1):
                self.stats['total_lines'] += 1

                try:
                    record = json.loads(line)
                except json.JSONDecodeError as e:
                    self.log(f"Line {line_num}: JSON parse error: {e}")
                    self.stats['errors'] += 1
                    continue

                record_type = record.get('type')

                # Extract session metadata
                if record_type == 'session_meta':
                    payload = record.get('payload', {})
                    session_id = payload.get('id')
                    git_info = payload.get('git', {})
                    cwd = payload.get('cwd')
                    self.project_dir = cwd  # Store for resume instructions
                    git_context = {
                        'cwd': cwd,
                        'gitBranch': git_info.get('branch'),
                        'gitCommit': git_info.get('commit_hash')
                    }
                    self.log(f"Line {line_num}: Extracted session_meta (session_id={session_id})")
                    self.stats['skipped'] += 1
                    continue

                # Convert messages only
                if record_type != 'response_item':
                    self.log(f"Line {line_num}: Skipping type={record_type}")
                    self.stats['skipped'] += 1
                    continue

                payload = record.get('payload', {})
                if payload.get('type') != 'message':
                    self.log(f"Line {line_num}: Skipping non-message response_item")
                    self.stats['skipped'] += 1
                    continue

                # Validate required fields
                if 'timestamp' not in record:
                    self.log(f"Line {line_num}: Missing required field 'timestamp'")
                    self.stats['errors'] += 1
                    continue

                # Extract content from array format
                content_blocks = payload.get('content', [])
                content_parts = []
                for block in content_blocks:
                    if isinstance(block, dict):
                        text = block.get('text', '')
                        if text:
                            content_parts.append(text)

                content = '\n'.join(content_parts)

                if not content:
                    self.log(f"Line {line_num}: No extractable content")
                    self.stats['skipped'] += 1
                    continue

                # Generate UUID
                message_uuid = str(uuid4())

                role = payload.get('role', 'assistant')

                claude_message = {
                    "uuid": message_uuid,
                    "type": role,
                    "timestamp": record.get('timestamp'),
                    "message": {
                        "role": role,
                        "content": content
                    },
                    "sessionId": session_id or 'converted',
                    "parentUuid": None,  # No threading in Codex
                    **{k: v for k, v in git_context.items() if v is not None}
                }

                outfile.write(json.dumps(claude_message) + '\n')
                self.stats['converted'] += 1
                self.log(f"Line {line_num}: Converted {role} message")

        return self.stats


def main():
    parser = argparse.ArgumentParser(
        description='Convert between Claude Code and Codex CLI transcript formats',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('--from', dest='from_format', required=True,
                        choices=['claude-code', 'codex'],
                        help='Source format')
    parser.add_argument('--to', dest='to_format', required=True,
                        choices=['claude-code', 'codex'],
                        help='Target format')
    parser.add_argument('input', help='Input JSONL file')
    parser.add_argument('output', help='Output JSONL file')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Enable verbose logging')

    args = parser.parse_args()

    # Validate formats
    if args.from_format == args.to_format:
        print("Error: Source and target formats must be different", file=sys.stderr)
        return 1

    # Create converter
    converter = TranscriptConverter(verbose=args.verbose)

    try:
        # Convert
        if args.from_format == 'claude-code' and args.to_format == 'codex':
            stats = converter.claude_to_codex(args.input, args.output)
            print(f"✓ Converted Claude Code → Codex CLI: {args.output}")
        else:  # codex to claude-code
            stats = converter.codex_to_claude(args.input, args.output)
            print(f"✓ Converted Codex CLI → Claude Code: {args.output}")

        # Print stats
        print(f"\nStatistics:")
        print(f"  Total lines:     {stats['total_lines']}")
        print(f"  Converted:       {stats['converted']}")
        print(f"  Skipped:         {stats['skipped']}")
        print(f"  Errors:          {stats['errors']}")

        if stats['errors'] > 0:
            print(f"\n⚠️  {stats['errors']} errors occurred (run with -v for details)")
            return 1

        # Print helpful resume instructions
        print(f"\n{'=' * 60}")
        print("📋 How to Resume This Conversation")
        print('=' * 60)

        if args.to_format == 'codex':
            # Converted to Codex format
            print(f"\n1. Navigate to the project directory:")
            if converter.project_dir:
                print(f"   cd {converter.project_dir}")
            else:
                print(f"   cd <project-directory>")

            print(f"\n2. Resume the conversation with Codex CLI:")
            if converter.session_id:
                print(f"   codex resume {converter.session_id}")
                print(f"   # OR use the picker:")
                print(f"   codex resume")
            else:
                print(f"   codex resume")

            print(f"\n📍 Transcript location: {args.output}")
            if converter.session_id:
                print(f"🆔 Session ID: {converter.session_id}")
            if converter.project_dir:
                print(f"📁 Project directory: {converter.project_dir}")

            # Show warning if not in proper Codex location
            if converter.suggested_codex_path:
                print(f"\n⚠️  WARNING: Codex expects sessions in ~/.codex/sessions/YYYY/MM/DD/")
                print(f"   For Codex to find this session, copy it to:")
                print(f"   {converter.suggested_codex_path}")
                print(f"\n   Quick fix:")
                print(f"   mkdir -p {os.path.dirname(converter.suggested_codex_path)}")
                print(f"   cp {args.output} {converter.suggested_codex_path}")

        else:  # Converted to Claude Code format
            # Converted to Claude Code format
            print(f"\n1. Navigate to the project directory:")
            if converter.project_dir:
                print(f"   cd {converter.project_dir}")
            else:
                print(f"   cd <project-directory>")

            print(f"\n2. Resume the conversation with Claude Code:")
            if converter.session_id:
                print(f"   claude-code /resume {converter.session_id}")
            else:
                print(f"   claude-code /resume <session-id>")

            print(f"\n📍 Transcript location: {args.output}")
            if converter.session_id:
                print(f"🆔 Session ID: {converter.session_id}")
            if converter.project_dir:
                print(f"📁 Project directory: {converter.project_dir}")

        print(f"\n💡 Tip: The CLI will load the conversation history and you can")
        print(f"   continue where you left off with the other tool.")
        print('=' * 60)

        return 0

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
