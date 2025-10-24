#!/usr/bin/env python3
"""
Generate valid test transcripts for Claude Code and Codex CLI formats.

Usage:
    # Claude Code format
    ./generate_test_transcript.py --format claude-code --output fixtures/test-claude.jsonl

    # Codex format
    ./generate_test_transcript.py --format codex --output fixtures/test-codex.jsonl

    # Custom project directory
    ./generate_test_transcript.py --format claude-code --project-dir /path/to/project
"""

import argparse
import json
import uuid
from datetime import datetime, timezone, timedelta
import os


class TranscriptGenerator:
    """Generates valid test transcripts in Claude Code or Codex format."""

    def __init__(self, project_dir=None, git_branch="feature/swift-cli-converter", git_commit="c78e2dd"):
        self.project_dir = project_dir or "/Users/rob/code/projects/contextify"
        self.git_branch = git_branch
        self.git_commit = git_commit
        self.session_id = str(uuid.uuid4())

    def generate_claude_code(self, output_path, num_exchanges=2, scenario="basic"):
        """Generate a valid Claude Code transcript.

        Args:
            output_path: Where to write the transcript
            num_exchanges: Number of conversation exchanges (default 2, realistic 4-6)
            scenario: Conversation type - "basic", "realistic", "continuity-test"
        """

        timestamp = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        creation_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S PST')

        messages = []
        parent_uuid = None

        if scenario == "basic":
            # Original simple test conversation
            # Exchange 1: User asks about converter
            user_uuid = str(uuid.uuid4())
            messages.append({
                "type": "user",
                "uuid": user_uuid,
                "timestamp": timestamp,
                "parentUuid": parent_uuid,
                "sessionId": self.session_id,
                "version": "2.0.22",
                "userType": "external",
                "cwd": self.project_dir,
                "gitBranch": self.git_branch,
                "isSidechain": False,
                "isMeta": False,
                "message": {
                    "role": "user",
                    "content": f"This is a test conversation created at {creation_time} to verify the transcript converter."
                }
            })

            assistant_uuid = str(uuid.uuid4())
            messages.append({
                "type": "assistant",
                "uuid": assistant_uuid,
                "timestamp": timestamp,
                "parentUuid": user_uuid,
                "sessionId": self.session_id,
                "version": "2.0.22",
                "userType": "external",
                "cwd": self.project_dir,
                "gitBranch": self.git_branch,
                "isSidechain": False,
                "requestId": f"req_{str(uuid.uuid4()).replace('-', '')}",
                "message": {
                    "id": f"msg_{str(uuid.uuid4()).replace('-', '')}",
                    "type": "message",
                    "role": "assistant",
                    "model": "claude-sonnet-4-5-20250929",
                    "content": [
                        {
                            "type": "text",
                            "text": "I understand. This test conversation will be used to validate the transcript converter works correctly."
                        }
                    ],
                    "stop_reason": None,
                    "stop_sequence": None,
                    "usage": {
                        "input_tokens": 150,
                        "output_tokens": 25,
                        "cache_creation_input_tokens": 0,
                        "cache_read_input_tokens": 0,
                        "cache_creation": {
                            "ephemeral_5m_input_tokens": 0,
                            "ephemeral_1h_input_tokens": 0
                        },
                        "service_tier": "standard"
                    }
                }
            })
            parent_uuid = assistant_uuid

            # Exchange 2: Verification details
            if num_exchanges >= 2:
                user_uuid = str(uuid.uuid4())
            messages.append({
                "type": "user",
                "uuid": user_uuid,
                "timestamp": timestamp,
                "parentUuid": parent_uuid,
                "sessionId": self.session_id,
                "version": "2.0.22",
                "userType": "external",
                "cwd": self.project_dir,
                "gitBranch": self.git_branch,
                "isSidechain": False,
                "isMeta": False,
                "message": {
                    "role": "user",
                    "content": f"Perfect! Test session ID: {self.session_id}"
                }
            })

            assistant_uuid = str(uuid.uuid4())
            messages.append({
                "type": "assistant",
                "uuid": assistant_uuid,
                "timestamp": timestamp,
                "parentUuid": user_uuid,
                "sessionId": self.session_id,
                "version": "2.0.22",
                "userType": "external",
                "cwd": self.project_dir,
                "gitBranch": self.git_branch,
                "isSidechain": False,
                "requestId": f"req_{str(uuid.uuid4()).replace('-', '')}",
                "message": {
                    "id": f"msg_{str(uuid.uuid4()).replace('-', '')}",
                    "type": "message",
                    "role": "assistant",
                    "model": "claude-sonnet-4-5-20250929",
                    "content": [
                        {
                            "type": "text",
                            "text": f"Acknowledged! This test will validate:\n1. Claude Code can resume this session\n2. Converter transforms to Codex format\n3. Codex CLI can resume the converted session\n\nCreation time: {creation_time}"
                        }
                    ],
                    "stop_reason": None,
                    "stop_sequence": None,
                    "usage": {
                        "input_tokens": 175,
                        "output_tokens": 45,
                        "cache_creation_input_tokens": 0,
                        "cache_read_input_tokens": 0,
                        "cache_creation": {
                            "ephemeral_5m_input_tokens": 0,
                            "ephemeral_1h_input_tokens": 0
                        },
                        "service_tier": "standard"
                    }
                }
            })

        elif scenario == "realistic":
            # Multi-exchange conversation with varied content for realistic testing
            exchanges = [
                # Exchange 1: Initial request about a feature
                {
                    "user": f"Test conversation created at {creation_time}. Let's implement a new feature: add a 'Copy Session ID' button to the transcript inventory view.",
                    "assistant": "I'll help you add a 'Copy Session ID' button to the transcript inventory view. Let me first search for the TranscriptInventoryView to understand its current structure."
                },
                # Exchange 2: Follow-up with implementation details
                {
                    "user": "The TranscriptInventoryView is in Contextify/Contextify/TranscriptInventoryView.swift. Can you add the button next to each transcript row?",
                    "assistant": "Perfect! I'll add a copy button to each transcript row. The button will:\n1. Use SF Symbol 'doc.on.doc' icon\n2. Copy the transcript's session ID to clipboard\n3. Show a brief toast notification on success\n4. Use `.foregroundStyle(.secondary)` for subtle appearance\n\nI'll add this in the row's trailing content, alongside any existing actions."
                },
                # Exchange 3: Code review / refinement
                {
                    "user": "Good plan. Also make sure it works with keyboard navigation - should be activatable with Enter key.",
                    "assistant": "Absolutely! I'll ensure full keyboard accessibility:\n- Button will be keyboard-focusable by default (SwiftUI Button behavior)\n- Enter/Space keys will activate it\n- Add `.keyboardShortcut(.defaultAction)` for the primary copy action\n- Include `.accessibilityLabel(\"Copy session ID\")` for VoiceOver\n\nThis follows macOS HIG for keyboard navigation in list views."
                },
                # Exchange 4: Testing verification
                {
                    "user": "Perfect. After you implement it, remind me to test:\n1. Click the button copies ID\n2. Keyboard navigation works\n3. Toast appears\n4. Works with multiple transcripts",
                    "assistant": f"Excellent test plan! I've noted these verification steps for after implementation:\n\n**Copy Session ID Button - Test Checklist:**\n1. ✓ Mouse click copies session ID to clipboard\n2. ✓ Keyboard navigation: Tab to button, Enter/Space activates\n3. ✓ Toast notification shows \"Session ID copied\"\n4. ✓ Works correctly for all transcripts in list\n5. ✓ VoiceOver announces button purpose\n\n**Session context:** Test created {creation_time}\n**Session ID:** {self.session_id}\n\nYou can verify this context is preserved by asking: 'What feature were we implementing?' or 'What are the test steps?'"
                }
            ]

            for i, exchange in enumerate(exchanges[:num_exchanges] if num_exchanges < len(exchanges) else exchanges):
                # User message
                user_uuid = str(uuid.uuid4())
                messages.append({
                    "type": "user",
                    "uuid": user_uuid,
                    "timestamp": timestamp,
                    "parentUuid": parent_uuid,
                    "sessionId": self.session_id,
                    "version": "2.0.22",
                    "userType": "external",
                    "cwd": self.project_dir,
                    "gitBranch": self.git_branch,
                    "isSidechain": False,
                    "isMeta": False,
                    "message": {
                        "role": "user",
                        "content": exchange["user"]
                    }
                })

                # Assistant message
                assistant_uuid = str(uuid.uuid4())
                messages.append({
                    "type": "assistant",
                    "uuid": assistant_uuid,
                    "timestamp": timestamp,
                    "parentUuid": user_uuid,
                    "sessionId": self.session_id,
                    "version": "2.0.22",
                    "userType": "external",
                    "cwd": self.project_dir,
                    "gitBranch": self.git_branch,
                    "isSidechain": False,
                    "requestId": f"req_{str(uuid.uuid4()).replace('-', '')}",
                    "message": {
                        "id": f"msg_{str(uuid.uuid4()).replace('-', '')}",
                        "type": "message",
                        "role": "assistant",
                        "model": "claude-sonnet-4-5-20250929",
                        "content": [
                            {
                                "type": "text",
                                "text": exchange["assistant"]
                            }
                        ],
                        "stop_reason": None,
                        "stop_sequence": None,
                        "usage": {
                            "input_tokens": 200 + (i * 50),
                            "output_tokens": 80 + (i * 20),
                            "cache_creation_input_tokens": 0,
                            "cache_read_input_tokens": 150 if i > 0 else 0,
                            "cache_creation": {
                                "ephemeral_5m_input_tokens": 0,
                                "ephemeral_1h_input_tokens": 0
                            },
                            "service_tier": "standard"
                        }
                    }
                })
                parent_uuid = assistant_uuid

        elif scenario == "continuity-test":
            # Conversation specifically designed to test context continuity
            exchanges = [
                {
                    "user": f"Test session created {creation_time}. I need you to remember three things:\n1. The SECRET_CODE is: ALPHA-7-BRAVO\n2. My preferred color scheme is: dark mode with blue accents\n3. The test file path is: /tmp/converter-test-{self.session_id}.txt",
                    "assistant": "I've recorded your three items:\n\n1. **SECRET_CODE:** ALPHA-7-BRAVO\n2. **Color scheme:** Dark mode with blue accents\n3. **Test file path:** `/tmp/converter-test-{self.session_id}.txt`\n\nI'll remember these throughout our conversation."
                },
                {
                    "user": "Now, can you tell me the fibonacci sequence up to 8 numbers?",
                    "assistant": "Here's the Fibonacci sequence (first 8 numbers):\n\n0, 1, 1, 2, 3, 5, 8, 13\n\nEach number is the sum of the previous two:\n- 0 + 1 = 1\n- 1 + 1 = 2\n- 1 + 2 = 3\n- 2 + 3 = 5\n- 3 + 5 = 8\n- 5 + 8 = 13"
                },
                {
                    "user": "Good. Now tell me: what was the SECRET_CODE I asked you to remember?",
                    "assistant": "The SECRET_CODE you asked me to remember is: **ALPHA-7-BRAVO**"
                },
                {
                    "user": "Perfect! And what color scheme did I mention?",
                    "assistant": "You mentioned your preferred color scheme is: **Dark mode with blue accents**"
                },
                {
                    "user": "Excellent. For the final continuity test: if I resume this conversation later and ask you to repeat the 6th fibonacci number and the test file path, what would you say?",
                    "assistant": f"When you resume this conversation and ask me those questions, I would say:\n\n**6th Fibonacci number:** 5 (from the sequence: 0, 1, 1, 2, 3, 5, 8, 13)\n\n**Test file path:** `/tmp/converter-test-{self.session_id}.txt`\n\n**Continuity verification items:**\n- SECRET_CODE: ALPHA-7-BRAVO\n- Color scheme: Dark mode with blue accents\n- Session created: {creation_time}\n- Session ID: {self.session_id}\n\nTo verify context preservation after conversion, try asking:\n- 'What's the SECRET_CODE?'\n- 'What's the 6th fibonacci number?'\n- 'What's my test file path?'\n- 'What color scheme do I prefer?'"
                }
            ]

            for i, exchange in enumerate(exchanges[:num_exchanges] if num_exchanges < len(exchanges) else exchanges):
                # User message
                user_uuid = str(uuid.uuid4())
                messages.append({
                    "type": "user",
                    "uuid": user_uuid,
                    "timestamp": timestamp,
                    "parentUuid": parent_uuid,
                    "sessionId": self.session_id,
                    "version": "2.0.22",
                    "userType": "external",
                    "cwd": self.project_dir,
                    "gitBranch": self.git_branch,
                    "isSidechain": False,
                    "isMeta": False,
                    "message": {
                        "role": "user",
                        "content": exchange["user"]
                    }
                })

                # Assistant message
                assistant_uuid = str(uuid.uuid4())
                messages.append({
                    "type": "assistant",
                    "uuid": assistant_uuid,
                    "timestamp": timestamp,
                    "parentUuid": user_uuid,
                    "sessionId": self.session_id,
                    "version": "2.0.22",
                    "userType": "external",
                    "cwd": self.project_dir,
                    "gitBranch": self.git_branch,
                    "isSidechain": False,
                    "requestId": f"req_{str(uuid.uuid4()).replace('-', '')}",
                    "message": {
                        "id": f"msg_{str(uuid.uuid4()).replace('-', '')}",
                        "type": "message",
                        "role": "assistant",
                        "model": "claude-sonnet-4-5-20250929",
                        "content": [
                            {
                                "type": "text",
                                "text": exchange["assistant"]
                            }
                        ],
                        "stop_reason": None,
                        "stop_sequence": None,
                        "usage": {
                            "input_tokens": 180 + (i * 40),
                            "output_tokens": 70 + (i * 15),
                            "cache_creation_input_tokens": 0,
                            "cache_read_input_tokens": 200 if i > 0 else 0,
                            "cache_creation": {
                                "ephemeral_5m_input_tokens": 0,
                                "ephemeral_1h_input_tokens": 0
                            },
                            "service_tier": "standard"
                        }
                    }
                })
                parent_uuid = assistant_uuid

        # Write to file
        os.makedirs(os.path.dirname(output_path) if os.path.dirname(output_path) else '.', exist_ok=True)
        with open(output_path, 'w') as f:
            for msg in messages:
                f.write(json.dumps(msg) + '\n')

        return {
            'session_id': self.session_id,
            'output_path': output_path,
            'message_count': len(messages),
            'creation_time': creation_time
        }

    def generate_codex(self, output_path, num_exchanges=2):
        """Generate a valid Codex CLI transcript."""

        timestamp = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
        creation_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S PST')

        records = []

        # Session metadata (must be first)
        records.append({
            "timestamp": timestamp,
            "type": "session_meta",
            "payload": {
                "projectPath": self.project_dir,
                "gitInfo": {
                    "branch": self.git_branch,
                    "commit_hash": self.git_commit
                }
            }
        })

        # Exchange 1: User message
        records.append({
            "timestamp": timestamp,
            "type": "response_item",
            "payload": {
                "type": "message",
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": f"This is a test conversation created at {creation_time} to verify the transcript converter."
                    }
                ]
            }
        })

        # Exchange 1: Assistant response
        records.append({
            "timestamp": timestamp,
            "type": "response_item",
            "payload": {
                "type": "message",
                "role": "assistant",
                "content": [
                    {
                        "type": "output_text",
                        "text": "I understand. This test conversation will be used to validate the transcript converter works correctly."
                    }
                ]
            }
        })

        # Exchange 2: More verification
        if num_exchanges >= 2:
            records.append({
                "timestamp": timestamp,
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": f"Perfect! Test session ID: {self.session_id}"
                        }
                    ]
                }
            })

            records.append({
                "timestamp": timestamp,
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        {
                            "type": "output_text",
                            "text": f"Acknowledged! This test will validate:\n1. Codex CLI can resume this session\n2. Converter transforms to Claude Code format\n3. Claude Code can resume the converted session\n\nCreation time: {creation_time}"
                        }
                    ]
                }
            })

        # Write to file
        os.makedirs(os.path.dirname(output_path) if os.path.dirname(output_path) else '.', exist_ok=True)
        with open(output_path, 'w') as f:
            for record in records:
                f.write(json.dumps(record) + '\n')

        return {
            'session_id': self.session_id,
            'output_path': output_path,
            'record_count': len(records),
            'creation_time': creation_time
        }


def main():
    parser = argparse.ArgumentParser(description='Generate test transcripts for converter validation')
    parser.add_argument('--format', required=True, choices=['claude-code', 'codex'],
                        help='Transcript format to generate')
    parser.add_argument('--output', required=True,
                        help='Output file path')
    parser.add_argument('--project-dir', default='/Users/rob/code/projects/contextify',
                        help='Project directory path')
    parser.add_argument('--git-branch', default='feature/swift-cli-converter',
                        help='Git branch name')
    parser.add_argument('--git-commit', default='c78e2dd',
                        help='Git commit hash')
    parser.add_argument('--exchanges', type=int, default=2,
                        help='Number of conversation exchanges')
    parser.add_argument('--scenario', choices=['basic', 'realistic', 'continuity-test'], default='basic',
                        help='Conversation scenario type (basic=simple test, realistic=feature implementation, continuity-test=context verification)')

    args = parser.parse_args()

    generator = TranscriptGenerator(
        project_dir=args.project_dir,
        git_branch=args.git_branch,
        git_commit=args.git_commit
    )

    if args.format == 'claude-code':
        result = generator.generate_claude_code(args.output, args.exchanges, args.scenario)

        # Determine project key from project_dir
        project_key = args.project_dir.replace('/', '-')
        claude_session_path = os.path.expanduser(f"~/.claude/projects/{project_key}/{result['session_id']}.jsonl")

        # Copy to Claude Code sessions directory if output was to fixtures
        if not args.output.startswith(os.path.expanduser('~/.claude/')):
            import shutil
            os.makedirs(os.path.dirname(claude_session_path), exist_ok=True)
            shutil.copy(result['output_path'], claude_session_path)
            print(f"✓ Generated and copied Claude Code transcript")
            print(f"  Fixture: {result['output_path']}")
            print(f"  Session: {claude_session_path}")
        else:
            print(f"✓ Generated Claude Code transcript")
            print(f"  File: {result['output_path']}")

        print(f"  Session ID: {result['session_id']}")
        print(f"  Messages: {result['message_count']}")
        print(f"  Created: {result['creation_time']}")
        print(f"\nResume command:")
        print(f"  cd {args.project_dir} && claude --resume {result['session_id']}")
    else:
        result = generator.generate_codex(args.output, args.exchanges)
        print(f"✓ Generated Codex CLI transcript")
        print(f"  Session ID: {result['session_id']}")
        print(f"  Records: {result['record_count']}")
        print(f"  Created: {result['creation_time']}")
        print(f"  File: {result['output_path']}")
        print(f"\nTo use this transcript:")
        print(f"  1. Copy to Codex sessions (with proper filename):")
        # Generate proper Codex filename
        from datetime import datetime
        now = datetime.now().strftime('%Y-%m-%dT%H-%M-%S')
        codex_filename = f"rollout-{now}-{result['session_id']}.jsonl"
        print(f"     cp {result['output_path']} ~/.codex/sessions/$(date +%Y/%m/%d)/{codex_filename}")
        print(f"  2. Resume:")
        print(f"     cd {args.project_dir} && codex resume {result['session_id']}")


if __name__ == '__main__':
    main()
