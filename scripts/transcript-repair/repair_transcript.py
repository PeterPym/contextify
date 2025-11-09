#!/usr/bin/env python3
"""
Repair corrupted Claude Code transcript files.

This utility detects and fixes common corruption patterns from Claude Code Web
"teleport" feature that can leave transcripts in unrecoverable states.

Supported repairs:
1. Orphaned tool_result blocks (user message with tool_result but no preceding tool_use)
2. stop_reason mismatch (assistant with stop_reason="tool_use" but no tool_use blocks)
3. Broken parent chains (messages referencing deleted UUIDs)

Usage:
    # Analyze without modifying
    python3 repair_transcript.py <transcript_file> --dry-run

    # Repair in place (creates .backup)
    python3 repair_transcript.py <transcript_file>

    # Repair to new file
    python3 repair_transcript.py <transcript_file> -o <output_file>
"""

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Set


@dataclass
class CorruptionIssue:
    """Detected corruption issue"""
    line_number: int
    uuid: str
    type: str
    details: str
    recoverable: bool


@dataclass
class RepairAction:
    """Action to repair corruption"""
    line_number: int
    action: str  # "skip", "modify", "update_parent"
    details: str
    original_uuid: Optional[str] = None
    new_parent_uuid: Optional[str] = None


class TranscriptAnalyzer:
    """Analyze Claude Code transcripts for corruption patterns"""

    def __init__(self):
        self.issues: List[CorruptionIssue] = []
        self.tool_use_ids: Set[str] = set()  # Track tool_use IDs from assistant messages
        self.last_assistant_uuid: Optional[str] = None
        self.all_uuids: Set[str] = set()

    def analyze_file(self, path: Path) -> List[CorruptionIssue]:
        """Analyze transcript file and return detected issues"""
        self.issues = []
        self.tool_use_ids = set()
        self.last_assistant_uuid = None
        self.all_uuids = set()

        with open(path, 'r') as f:
            for line_num, line in enumerate(f, 1):
                try:
                    record = json.loads(line)
                    self._analyze_record(record, line_num)
                except json.JSONDecodeError as e:
                    # Check if this is concatenated JSON (common corruption pattern)
                    if self._try_split_concatenated_json(line, line_num):
                        continue

                    self.issues.append(CorruptionIssue(
                        line_number=line_num,
                        uuid="unknown",
                        type="invalid_json",
                        details=f"JSON parse error: {e}",
                        recoverable=False
                    ))

        return self.issues

    def _try_split_concatenated_json(self, line: str, line_num: int) -> bool:
        """
        Try to split concatenated JSON records on a single line.
        Returns True if successfully split and analyzed, False otherwise.
        """
        # Try to find where the first JSON object ends
        decoder = json.JSONDecoder()
        records = []
        pos = 0

        while pos < len(line):
            try:
                record, idx = decoder.raw_decode(line, pos)
                records.append(record)
                pos = idx
                # Skip whitespace
                while pos < len(line) and line[pos].isspace():
                    pos += 1
            except json.JSONDecodeError:
                return False  # Can't split this line

        if len(records) > 1:
            # Successfully split concatenated JSON
            self.issues.append(CorruptionIssue(
                line_number=line_num,
                uuid="unknown",
                type="concatenated_json",
                details=f"Found {len(records)} JSON records on one line (teleport corruption)",
                recoverable=True
            ))

            # Analyze each record
            for record in records:
                self._analyze_record(record, line_num)

            return True

        return False

    def _analyze_record(self, record: Dict[str, Any], line_num: int):
        """Analyze a single record"""
        uuid = record.get('uuid', 'unknown')
        self.all_uuids.add(uuid)
        msg_type = record.get('type')

        # Check for missing parent
        if parent_uuid := record.get('parentUuid'):
            if parent_uuid not in self.all_uuids:
                # Parent will be validated at end of analysis
                pass

        if msg_type == 'assistant':
            self.last_assistant_uuid = uuid
            self._check_assistant_message(record, line_num)
        elif msg_type == 'user':
            self._check_user_message(record, line_num)

    def _check_assistant_message(self, record: Dict[str, Any], line_num: int):
        """Check assistant message for corruption"""
        uuid = record['uuid']
        message = record.get('message', {})
        content = message.get('content', [])

        if not isinstance(content, list):
            return

        # Track tool_use IDs
        tool_use_ids = []
        has_tool_use = False
        has_only_thinking = True
        content_types = []

        for block in content:
            block_type = block.get('type')
            content_types.append(block_type)

            if block_type == 'tool_use':
                has_tool_use = True
                has_only_thinking = False
                if tool_id := block.get('id'):
                    tool_use_ids.append(tool_id)
                    self.tool_use_ids.add(tool_id)
            elif block_type == 'text':
                has_only_thinking = False
            elif block_type == 'thinking':
                pass  # thinking doesn't count as displayable content
            else:
                has_only_thinking = False

        # Check stop_reason mismatch
        stop_reason = message.get('stop_reason')
        if stop_reason == 'tool_use' and not has_tool_use:
            self.issues.append(CorruptionIssue(
                line_number=line_num,
                uuid=uuid,
                type="stop_reason_mismatch",
                details=f"Assistant has stop_reason='tool_use' but content=[{', '.join(content_types)}]",
                recoverable=True
            ))

    def _check_user_message(self, record: Dict[str, Any], line_num: int):
        """Check user message for corruption"""
        uuid = record['uuid']
        message = record.get('message', {})
        content = message.get('content', [])

        if not isinstance(content, list):
            return

        # Check for orphaned tool_result
        for block in content:
            if block.get('type') == 'tool_result':
                tool_use_id = block.get('tool_use_id')
                if tool_use_id and tool_use_id not in self.tool_use_ids:
                    self.issues.append(CorruptionIssue(
                        line_number=line_num,
                        uuid=uuid,
                        type="orphaned_tool_result",
                        details=f"tool_result references tool_use_id='{tool_use_id}' which doesn't exist",
                        recoverable=True
                    ))


class TranscriptRepairer:
    """Repair corrupted transcripts"""

    def __init__(self, dry_run: bool = False):
        self.dry_run = dry_run
        self.actions: List[RepairAction] = []

    def repair_file(
        self,
        input_path: Path,
        output_path: Optional[Path],
        issues: List[CorruptionIssue]
    ) -> bool:
        """
        Repair transcript file based on detected issues.
        Returns True if repairs were made.
        """
        if not issues:
            print("✅ No corruption detected. File is valid.")
            return False

        # Plan repair actions
        self._plan_repairs(issues)

        if self.dry_run:
            self._print_repair_plan()
            return False

        # Execute repairs
        if output_path is None:
            backup_path = input_path.with_suffix('.jsonl.backup')
            input_path.rename(backup_path)
            output_path = input_path
            input_source = backup_path
            print(f"📦 Backup created: {backup_path}")
        else:
            input_source = input_path

        self._execute_repairs(input_source, output_path)
        return True

    def _plan_repairs(self, issues: List[CorruptionIssue]):
        """Plan repair actions for detected issues"""
        uuids_to_skip = set()
        parent_updates = {}

        for issue in issues:
            if issue.type == "orphaned_tool_result":
                # Skip the entire message
                self.actions.append(RepairAction(
                    line_number=issue.line_number,
                    action="skip",
                    details=f"Remove orphaned tool_result (uuid={issue.uuid})",
                    original_uuid=issue.uuid
                ))
                uuids_to_skip.add(issue.uuid)

            elif issue.type == "stop_reason_mismatch":
                # Modify stop_reason
                self.actions.append(RepairAction(
                    line_number=issue.line_number,
                    action="modify",
                    details=f"Change stop_reason from 'tool_use' to 'end_turn' (uuid={issue.uuid})"
                ))

            elif issue.type == "concatenated_json":
                # Split concatenated records
                self.actions.append(RepairAction(
                    line_number=issue.line_number,
                    action="split",
                    details=issue.details
                ))

        # Build parent update map for skipped messages
        if uuids_to_skip:
            # Need to update parent references
            # For now, collect these separately
            for action in self.actions:
                if action.action == "skip":
                    parent_updates[action.original_uuid] = None  # Will be filled during execution

    def _print_repair_plan(self):
        """Print planned repairs (dry-run mode)"""
        print(f"\n🔍 DRY RUN - Planned repairs ({len(self.actions)} actions):\n")
        for i, action in enumerate(self.actions, 1):
            print(f"{i}. Line {action.line_number}: {action.action.upper()}")
            print(f"   {action.details}")
            print()

    def _execute_repairs(self, input_path: Path, output_path: Path):
        """Execute planned repairs"""
        action_map = {a.line_number: a for a in self.actions}
        uuids_to_skip = {a.original_uuid for a in self.actions if a.action == "skip"}
        uuid_to_parent = {}  # Track parent for each UUID

        lines_kept = 0
        lines_removed = 0
        lines_modified = 0
        lines_split = 0

        with open(input_path, 'r') as fin, open(output_path, 'w') as fout:
            for line_num, line in enumerate(fin, 1):
                action = action_map.get(line_num)

                # Handle concatenated JSON splitting
                if action and action.action == "split":
                    decoder = json.JSONDecoder()
                    records = []
                    pos = 0

                    while pos < len(line):
                        try:
                            record, idx = decoder.raw_decode(line, pos)
                            records.append(record)
                            pos = idx
                            while pos < len(line) and line[pos].isspace():
                                pos += 1
                        except json.JSONDecodeError:
                            break

                    print(f"Line {line_num}: Splitting {len(records)} concatenated records")
                    for record in records:
                        fout.write(json.dumps(record, separators=(',', ':')) + '\n')
                        lines_kept += 1
                    lines_split += 1
                    continue

                try:
                    record = json.loads(line)
                    uuid = record.get('uuid')

                    # Track parent relationships
                    if uuid:
                        uuid_to_parent[uuid] = record.get('parentUuid')

                    if action and action.action == "skip":
                        # Skip this line
                        print(f"Line {line_num}: Skipping {uuid}")
                        lines_removed += 1
                        continue

                    # Check if parent was removed
                    if parent_uuid := record.get('parentUuid'):
                        if parent_uuid in uuids_to_skip:
                            # Find the valid parent (grandparent)
                            new_parent = uuid_to_parent.get(parent_uuid)
                            if new_parent:
                                print(f"Line {line_num}: Updating parentUuid from {parent_uuid} to {new_parent}")
                                record['parentUuid'] = new_parent
                                lines_modified += 1

                    if action and action.action == "modify":
                        # Modify stop_reason
                        if 'message' in record and 'stop_reason' in record['message']:
                            old_value = record['message']['stop_reason']
                            record['message']['stop_reason'] = 'end_turn'
                            print(f"Line {line_num}: Changed stop_reason from '{old_value}' to 'end_turn'")
                            lines_modified += 1

                    # Write (possibly modified) record
                    fout.write(json.dumps(record, separators=(',', ':')) + '\n')
                    lines_kept += 1

                except json.JSONDecodeError as e:
                    print(f"❌ Line {line_num}: JSON parse error: {e}", file=sys.stderr)
                    sys.exit(1)

        print(f"\n✅ Repair complete:")
        print(f"   Lines kept: {lines_kept}")
        print(f"   Lines removed: {lines_removed}")
        print(f"   Lines modified: {lines_modified}")
        print(f"   Lines split: {lines_split}")
        print(f"   Output: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Repair corrupted Claude Code transcript files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument('transcript', type=Path, help='Transcript file to repair')
    parser.add_argument('-o', '--output', type=Path, help='Output file (default: repair in place)')
    parser.add_argument('-n', '--dry-run', action='store_true', help='Analyze without modifying')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')

    args = parser.parse_args()

    if not args.transcript.exists():
        print(f"❌ File not found: {args.transcript}", file=sys.stderr)
        sys.exit(1)

    # Analyze
    print(f"🔍 Analyzing {args.transcript}...")
    analyzer = TranscriptAnalyzer()
    issues = analyzer.analyze_file(args.transcript)

    if issues:
        print(f"\n⚠️  Found {len(issues)} corruption issue(s):\n")
        for i, issue in enumerate(issues, 1):
            status = "✅ Recoverable" if issue.recoverable else "❌ Fatal"
            print(f"{i}. Line {issue.line_number} ({issue.type}) - {status}")
            print(f"   UUID: {issue.uuid}")
            print(f"   Details: {issue.details}")
            print()

    # Repair
    repairer = TranscriptRepairer(dry_run=args.dry_run)
    repaired = repairer.repair_file(args.transcript, args.output, issues)

    if args.dry_run and issues:
        print("\n💡 Run without --dry-run to apply these repairs.")
    elif not repaired and not issues:
        print("✅ No repairs needed.")


if __name__ == '__main__':
    main()
