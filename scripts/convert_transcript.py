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
import hashlib


class TranscriptConverter:
    """Bidirectional transcript converter"""

    def __init__(self, verbose=False):
        self.verbose = verbose
        self.stats = {
            'total_lines': 0,
            'converted': 0,
            'skipped': 0,
            'errors': 0,
            'tool_calls_direct': 0,      # Tier 1: Bash ↔ shell
            'tool_calls_summarized': 0,  # Tier 2: Edit, Read, etc.
            'tool_calls_skipped': 0      # Tier 3: TodoWrite, etc.
        }
        self.project_dir = None  # Extracted from transcript
        self.session_id = None   # For resume instructions
        self.suggested_codex_path = None  # Proper Codex session path

    # ============================================================================
    # Tool Conversion Helpers (Tier 1: Bash ↔ shell)
    # ============================================================================

    @staticmethod
    def tool_use_id_to_call_id(tool_id):
        """Convert Claude Code tool_use ID to Codex call_id

        Examples:
          toolu_abc123 → call_abc123
          toolu_01ABC  → call_01ABC
        """
        if tool_id.startswith("toolu_"):
            return "call_" + tool_id[6:]
        return "call_" + tool_id

    @staticmethod
    def call_id_to_tool_use_id(call_id):
        """Convert Codex call_id to Claude Code tool_use ID

        Examples:
          call_abc123 → toolu_abc123
          call_01ABC  → toolu_01ABC
        """
        if call_id.startswith("call_"):
            return "toolu_" + call_id[5:]
        return "toolu_" + call_id

    def bash_to_shell(self, tool_use_block, tool_result_block, timestamp, workdir=None):
        """Convert Claude Code Bash tool to Codex shell function

        Args:
            tool_use_block: Claude Code tool_use content block
            tool_result_block: Claude Code tool_result content block (may be None)
            timestamp: ISO timestamp for function_call
            workdir: Working directory (default: self.project_dir or '/')

        Returns:
            (function_call_record, function_call_output_record) or (function_call_record, None)
        """
        tool_id = tool_use_block.get('id')
        tool_input = tool_use_block.get('input', {})
        command = tool_input.get('command', '')

        if not command:
            self.log(f"Warning: Bash tool has no command, skipping")
            return None, None

        # Use provided workdir or fallback
        work_dir = workdir or self.project_dir or '/'

        # Build Codex shell arguments
        shell_args = {
            "command": ["bash", "-c", command],
            "workdir": work_dir
        }

        # Generate call_id from tool_use ID
        call_id = self.tool_use_id_to_call_id(tool_id)

        # Build function_call record
        function_call = {
            "timestamp": timestamp,
            "type": "response_item",
            "payload": {
                "type": "function_call",
                "name": "shell",
                "arguments": json.dumps(shell_args, separators=(',', ':')),
                "call_id": call_id
            }
        }

        # Build function_call_output if we have a result
        function_output = None
        if tool_result_block:
            content = tool_result_block.get('content', '')
            is_error = tool_result_block.get('is_error', False)
            exit_code = 1 if is_error else 0

            output_data = {
                "output": content,
                "metadata": {
                    "exit_code": exit_code,
                    "duration_seconds": 0.0  # Placeholder (not available in Claude Code)
                }
            }

            # Increment timestamp by 1ms for output
            from datetime import datetime as dt, timedelta, timezone
            ts_obj = dt.fromisoformat(timestamp.replace('Z', '+00:00'))
            output_ts = (ts_obj + timedelta(milliseconds=1)).isoformat().replace('+00:00', 'Z')

            function_output = {
                "timestamp": output_ts,
                "type": "response_item",
                "payload": {
                    "type": "function_call_output",
                    "call_id": call_id,
                    "output": json.dumps(output_data, separators=(',', ':'))
                }
            }

        return function_call, function_output

    def shell_to_bash(self, function_call_payload, function_output_payload, timestamp):
        """Convert Codex shell function to Claude Code Bash tool

        Args:
            function_call_payload: Codex function_call payload
            function_output_payload: Codex function_call_output payload (may be None)
            timestamp: ISO timestamp for tool_use

        Returns:
            (tool_use_block, tool_result_block) or (tool_use_block, None)
        """
        call_id = function_call_payload.get('call_id')
        arguments_str = function_call_payload.get('arguments', '{}')

        try:
            arguments = json.loads(arguments_str)
        except json.JSONDecodeError:
            self.log(f"Warning: Invalid JSON in shell arguments: {arguments_str}")
            return None, None

        # Extract command from ["bash", "-c", "actual_command"] format
        command_array = arguments.get('command', [])
        if not isinstance(command_array, list) or len(command_array) < 3:
            # Fallback: join entire array
            command = ' '.join(command_array) if isinstance(command_array, list) else str(command_array)
        else:
            # Unwrap bash -c wrapper
            if command_array[0] == 'bash' and command_array[1] in ['-c', '-lc']:
                command = command_array[2]
            else:
                command = ' '.join(command_array)

        # Generate tool_use_id from call_id
        tool_use_id = self.call_id_to_tool_use_id(call_id)

        # Build tool_use block
        tool_use = {
            "type": "tool_use",
            "id": tool_use_id,
            "name": "Bash",
            "input": {
                "command": command,
                "description": "Execute shell command"  # Generic description
            }
        }

        # Build tool_result block if we have output
        tool_result = None
        if function_output_payload:
            output_str = function_output_payload.get('output', '{}')
            try:
                output_data = json.loads(output_str)
                content = output_data.get('output', '')
                exit_code = output_data.get('metadata', {}).get('exit_code', 0)
                is_error = (exit_code != 0)

                tool_result = {
                    "type": "tool_result",
                    "tool_use_id": tool_use_id,
                    "content": content,
                    "is_error": is_error
                }
            except json.JSONDecodeError:
                self.log(f"Warning: Invalid JSON in shell output: {output_str}")
                # Create minimal tool_result
                tool_result = {
                    "type": "tool_result",
                    "tool_use_id": tool_use_id,
                    "content": output_str,
                    "is_error": False
                }

        return tool_use, tool_result

    def log(self, message):
        """Print verbose logging"""
        if self.verbose:
            print(f"[DEBUG] {message}", file=sys.stderr)

    def claude_to_codex(self, input_path, output_path):
        """Convert Claude Code JSONL to Codex CLI format

        Returns: (stats dict, actual_output_path)
        """
        session_id = str(uuid4())
        self.session_id = session_id
        first_message = True
        pending_assistant_response = None  # Buffer for assistant messages

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

        # Store the actual output path for caller
        self.actual_output_path = output_path

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

                # CODEX CONVERSATION STRUCTURE:
                # For each user→assistant turn, Codex requires:
                # 1. response_item (user)
                # 2. event_msg (user_message)
                # 3. turn_context (marks turn boundary)
                # 4. event_msg (agent_message) ← CRITICAL: What displays to user
                # 5. response_item (assistant)

                if record_type == "user":
                    # Write user response_item
                    codex_message = {
                        "timestamp": record['timestamp'],
                        "type": "response_item",
                        "payload": {
                            "type": "message",
                            "role": "user",
                            "content": content_array
                        }
                    }
                    outfile.write(json.dumps(codex_message, separators=(',', ':')) + '\n')

                    # Write user_message event
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

                    # Write turn_context (marks conversation turn boundary)
                    turn_context = {
                        "timestamp": record['timestamp'],
                        "type": "turn_context",
                        "payload": {
                            "cwd": record.get('cwd', '/'),
                            "approval_policy": "on-request",
                            "sandbox_policy": {
                                "mode": "workspace-write",
                                "network_access": False,
                                "exclude_tmpdir_env_var": False,
                                "exclude_slash_tmp": False
                            },
                            "model": "gpt-5-codex",
                            "summary": "auto"
                        }
                    }
                    outfile.write(json.dumps(turn_context, separators=(',', ':')) + '\n')

                    self.stats['converted'] += 1
                    self.log(f"Line {line_num}: Converted user message + turn_context")

                elif record_type == "assistant":
                    # Write agent_message event (CRITICAL: This is what displays!)
                    agent_message_event = {
                        "timestamp": record['timestamp'],
                        "type": "event_msg",
                        "payload": {
                            "type": "agent_message",
                            "message": text_for_event
                        }
                    }
                    outfile.write(json.dumps(agent_message_event, separators=(',', ':')) + '\n')

                    # Write assistant response_item (canonical data)
                    codex_message = {
                        "timestamp": record['timestamp'],
                        "type": "response_item",
                        "payload": {
                            "type": "message",
                            "role": "assistant",
                            "content": content_array
                        }
                    }
                    outfile.write(json.dumps(codex_message, separators=(',', ':')) + '\n')

                    self.stats['converted'] += 1
                    self.log(f"Line {line_num}: Converted assistant message (agent_message + response_item)")

        return self.stats

    def codex_to_claude(self, input_path, output_path):
        """Convert Codex CLI JSONL to Claude Code format"""
        session_id = None
        git_context = {}
        previous_uuid = None  # Track previous message UUID for parentUuid linking

        # Monotonic timestamp generator (like in generator script)
        from datetime import datetime, timezone, timedelta
        base_ts = datetime.now(timezone.utc).replace(microsecond=0)
        def next_ts():
            nonlocal base_ts
            base_ts = base_ts + timedelta(milliseconds=1)
            return base_ts.isoformat().replace('+00:00', 'Z')

        self.log(f"Converting Codex CLI → Claude Code")
        self.log(f"Input: {input_path}")
        self.log(f"Output: {output_path}")

        # Claude Code requires UUID.jsonl filenames
        # Extract or validate session ID from output path
        import os
        import re
        basename = os.path.basename(output_path)

        # Check if filename is already a valid UUID
        uuid_pattern = r'^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$'
        uuid_match = re.match(uuid_pattern, basename, re.IGNORECASE)

        if uuid_match:
            # Valid UUID filename - use it
            self.session_id = uuid_match.group(1).lower()
            self.log(f"Using UUID from filename: {self.session_id}")
        else:
            # Not a UUID filename - need to generate one and update path
            # Try to extract session_id from input Codex file first
            self.log(f"Warning: Output filename '{basename}' is not UUID format")
            self.log(f"Claude Code requires <uuid>.jsonl filenames")

            # We'll read the session_id from the Codex file's session_meta
            # and use that as the filename UUID (will be set during parsing)
            # For now, use the provided path but warn the user
            if basename.endswith('.jsonl'):
                self.session_id = basename[:-6]  # Remove .jsonl extension
            else:
                self.session_id = basename

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
                        'gitBranch': git_info.get('branch') or 'main',  # Ensure non-null
                        'gitCommit': git_info.get('commit_hash')
                    }
                    self.log(f"Line {line_num}: Extracted session_meta (session_id={session_id})")

                    # If output filename is not UUID format, auto-correct it using session_id from Codex
                    if not uuid_match and session_id:
                        # Use the Codex session_id as the Claude Code filename
                        dir_path = os.path.dirname(output_path)
                        corrected_filename = f"{session_id}.jsonl"
                        corrected_path = os.path.join(dir_path, corrected_filename)

                        if corrected_path != output_path:
                            self.log(f"Auto-correcting output filename to UUID format:")
                            self.log(f"  User provided: {basename}")
                            self.log(f"  Using instead: {corrected_filename}")

                            # Close current output file and reopen with correct name
                            outfile.close()
                            if os.path.exists(output_path):
                                os.remove(output_path)  # Remove incorrectly named file
                            outfile = open(corrected_path, 'w')
                            output_path = corrected_path
                            self.session_id = session_id

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

                # Build message with proper field order and monotonic timestamp
                user_ts = next_ts() if role == 'user' else None

                if role == 'user':
                    claude_message = {
                        "parentUuid": previous_uuid,  # Link to previous assistant message (or null for first)
                        "isSidechain": False,
                        "userType": "external",
                        "cwd": git_context.get('cwd', '/'),
                        "sessionId": session_id or 'converted',
                        "version": "2.0.26",
                        "gitBranch": git_context.get('gitBranch', 'main'),
                        "type": "user",
                        "message": {
                            "role": "user",
                            "content": content
                        },
                        "uuid": message_uuid,
                        "timestamp": user_ts,
                        "thinkingMetadata": {
                            "level": "none",
                            "disabled": True,
                            "triggers": []
                        }
                    }
                else:  # assistant
                    # Assistant messages need different content format (array)
                    asst_ts = next_ts()
                    claude_message = {
                        "parentUuid": previous_uuid,  # Link to previous user message
                        "isSidechain": False,
                        "userType": "external",
                        "cwd": git_context.get('cwd', '/'),
                        "sessionId": session_id or 'converted',
                        "version": "2.0.26",
                        "gitBranch": git_context.get('gitBranch', 'main'),
                        "message": {
                            "model": "claude-sonnet-4-5-20250929",
                            "id": f"msg_{str(uuid4()).replace('-', '')}",
                            "type": "message",
                            "role": "assistant",
                            "content": [{"type": "text", "text": content}],
                            "stop_reason": None,
                            "stop_sequence": None,
                            "usage": {
                                "input_tokens": 100,
                                "cache_creation_input_tokens": 0,
                                "cache_read_input_tokens": 0,
                                "cache_creation": {
                                    "ephemeral_5m_input_tokens": 0,
                                    "ephemeral_1h_input_tokens": 0
                                },
                                "output_tokens": 50,
                                "service_tier": "standard"
                            }
                        },
                        "requestId": f"req_{str(uuid4()).replace('-', '')}",
                        "type": "assistant",
                        "uuid": message_uuid,
                        "timestamp": asst_ts
                    }

                outfile.write(json.dumps(claude_message, separators=(',', ':')) + '\n')
                self.stats['converted'] += 1
                self.log(f"Line {line_num}: Converted {role} message")

                # Add file-history-snapshot after user messages (required by Claude Code)
                if role == 'user':
                    snapshot_ts = next_ts()

                    snapshot_record = {
                        "type": "file-history-snapshot",
                        "messageId": message_uuid,
                        "snapshot": {
                            "messageId": message_uuid,
                            "trackedFileBackups": {},
                            "timestamp": snapshot_ts
                        },
                        "isSnapshotUpdate": False
                    }
                    outfile.write(json.dumps(snapshot_record, separators=(',', ':')) + '\n')
                    self.log(f"Line {line_num}: Added file-history-snapshot for user message")

                # Update previous_uuid for conversation threading
                previous_uuid = message_uuid

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
            # Use the actual output path (may have been auto-corrected)
            actual_output = converter.actual_output_path
            print(f"✓ Converted Claude Code → Codex CLI: {actual_output}")
        else:  # codex to claude-code
            stats = converter.codex_to_claude(args.input, args.output)
            # For Claude Code, show the actual UUID filename used
            actual_output = args.output
            # Check if converter auto-corrected the filename
            if converter.session_id and not args.output.endswith(f"{converter.session_id}.jsonl"):
                dir_path = os.path.dirname(args.output) or '.'
                actual_output = os.path.join(dir_path, f"{converter.session_id}.jsonl")
            print(f"✓ Converted Codex CLI → Claude Code: {actual_output}")

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
            print(f"\nResume the conversation with Codex CLI:")
            if converter.project_dir and converter.session_id:
                print(f"   cd {converter.project_dir} && codex resume {converter.session_id}")
                print(f"   # OR use the picker:")
                print(f"   cd {converter.project_dir} && codex resume")
            elif converter.session_id:
                print(f"   cd <project-directory> && codex resume {converter.session_id}")
            else:
                print(f"   cd <project-directory> && codex resume")

            print(f"\n📍 Transcript location: {actual_output}")
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
            print(f"\nResume the conversation with Claude Code:")
            if converter.project_dir and converter.session_id:
                print(f"   cd {converter.project_dir} && claude --resume {converter.session_id}")
            elif converter.session_id:
                print(f"   cd <project-directory> && claude --resume {converter.session_id}")
            else:
                print(f"   cd <project-directory> && claude --resume <session-id>")

            print(f"\n📍 Transcript location: {actual_output}")
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
