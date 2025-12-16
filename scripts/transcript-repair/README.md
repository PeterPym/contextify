# Transcript Repair Utility - Quick Reference

## Overview

The `repair_transcript.py` script detects and fixes Claude Code Web corruption in transcript files.

**Common use case:** Claude Code Web "teleport" feature creates corrupted transcripts that cause API 400 errors.

## Quick Start

```bash
# Analyze a transcript (no changes)
python3 scripts/repair_transcript.py ~/.claude/projects/<project-key>/<session-uuid>.jsonl --dry-run

# Repair a transcript (creates .backup)
python3 scripts/repair_transcript.py ~/.claude/projects/<project-key>/<session-uuid>.jsonl

# Repair to new file
python3 scripts/repair_transcript.py input.jsonl -o output.jsonl
```

## Command Line Options

```
Usage: repair_transcript.py [-h] [-o OUTPUT] [-n] [-v] transcript

Arguments:
  transcript          Transcript file to repair

Options:
  -h, --help          Show help message
  -o OUTPUT           Output file (default: repair in place)
  -n, --dry-run       Analyze without modifying
  -v, --verbose       Verbose output
```

## What It Detects

1. **Orphaned tool_result** - User messages with tool_result but no preceding tool_use
2. **stop_reason mismatch** - Assistant messages with stop_reason="tool_use" but no tool_use blocks
3. **Invalid content blocks** - Malformed content block structures

## What It Repairs

1. **Removes** orphaned tool_result messages
2. **Modifies** stop_reason from "tool_use" to "end_turn"
3. **Updates** parent references for messages following deletions
4. **Preserves** all valid messages

## Example Output

### Dry Run (Analysis)
```
🔍 Analyzing transcript.jsonl...

⚠️  Found 2 corruption issue(s):

1. Line 1746 (stop_reason_mismatch) - ✅ Recoverable
   UUID: 51c03686-7e13-45fb-9d28-38d9ffbfb65d
   Details: Assistant has stop_reason='tool_use' but content=[thinking]

2. Line 1747 (orphaned_tool_result) - ✅ Recoverable
   UUID: d793b3f1-97d1-4f5e-b160-922054b2521b
   Details: tool_result references tool_use_id='toolu_018qN95...' which doesn't exist

🔍 DRY RUN - Planned repairs (2 actions):

1. Line 1746: MODIFY
   Change stop_reason from 'tool_use' to 'end_turn'

2. Line 1747: SKIP
   Remove orphaned tool_result

💡 Run without --dry-run to apply these repairs.
```

### Actual Repair
```
🔍 Analyzing transcript.jsonl...

⚠️  Found 2 corruption issue(s):
[... same as above ...]

📦 Backup created: transcript.jsonl.backup

Line 1746: Changed stop_reason from 'tool_use' to 'end_turn'
Line 1747: Skipping d793b3f1-97d1-4f5e-b160-922054b2521b
Line 1748: Updating parentUuid from d793b3f1... to 51c03686...

✅ Repair complete:
   Lines kept: 1898
   Lines removed: 1
   Lines modified: 2
   Output: transcript.jsonl
```

## Safety Features

- **Automatic backup** - Creates `.backup` file before modifying original
- **Dry-run mode** - Preview changes without modifying files
- **JSON validation** - Ensures output is valid JSON
- **Parent chain repair** - Automatically fixes broken references

## Workflow

### Option 1: In-Place Repair (Recommended)
```bash
# Analyze first
python3 scripts/repair_transcript.py transcript.jsonl --dry-run

# Review output, then repair
python3 scripts/repair_transcript.py transcript.jsonl

# Backup is at transcript.jsonl.backup
```

### Option 2: Repair to New File
```bash
# Keep original untouched
python3 scripts/repair_transcript.py transcript.jsonl -o transcript-repaired.jsonl

# Test repaired version
# If good, replace original:
mv transcript-repaired.jsonl transcript.jsonl
```

## Finding Corrupted Transcripts

### Check if a transcript is corrupted
```bash
# Try to continue session in Claude Code
# If you get API 400 error, transcript is likely corrupt

# Or analyze with repair script
python3 scripts/repair_transcript.py <transcript> --dry-run
```

### Find transcript location
```bash
# Claude Code transcripts are stored at:
~/.claude/projects/<project-key>/<session-uuid>.jsonl

# Example:
~/.claude/projects/-Users-rob-code-projects-contextify/42d110d2-9011-4dc3-85ff-a86a26ae0b82.jsonl
```

### Batch check multiple transcripts
```bash
# Check all transcripts in a project
for f in ~/.claude/projects/<project-key>/*.jsonl; do
  echo "Checking $f..."
  python3 scripts/repair_transcript.py "$f" --dry-run | grep -q "Found 0" || echo "  ⚠️  CORRUPT"
done
```

## Troubleshooting

### "File not found"
- Check transcript path is absolute, not relative
- Verify file exists: `ls -l <path>`

### "JSON parse error"
- File may be severely corrupted
- Try manual inspection: `tail -10 <transcript> | jq .`
- Check for truncated lines: `wc -l <transcript>`

### "No corruption detected" but session still fails
- Corruption may be in earlier messages (not last few lines)
- Try full session validation in Claude Code
- Check API error message for specific line/message number

### Repair script errors
- Ensure Python 3.8+ installed: `python3 --version`
- Check file permissions: `ls -l <transcript>`
- Try verbose mode: `--verbose`

## Advanced Usage

### Repair multiple transcripts
```bash
# Repair all corrupted transcripts in a project
for f in ~/.claude/projects/<project-key>/*.jsonl; do
  if python3 scripts/repair_transcript.py "$f" --dry-run | grep -q "corruption"; then
    echo "Repairing $f..."
    python3 scripts/repair_transcript.py "$f"
  fi
done
```

### Check repair statistics
```bash
# Get count of issues
python3 scripts/repair_transcript.py transcript.jsonl --dry-run | grep "Found.*corruption"

# Get line count before/after
wc -l transcript.jsonl.backup transcript.jsonl
```

## Integration with Contextify

Contextify automatically detects corruption during transcript ingestion but **does not auto-repair**.

To repair and re-ingest:
```bash
# 1. Repair the transcript
python3 scripts/repair_transcript.py <transcript>

# 2. Re-ingest in Contextify
./scripts/db_manager.sh reingest <transcript-id>
```

## When to Use This Tool

**✅ Use when:**
- Claude Code session fails with API 400 error
- "unexpected tool_use_id found in tool_result blocks" error
- Session worked in web but fails in CLI after teleport
- Contextify reports corruption during ingestion

**❌ Don't use when:**
- Session works fine in Claude Code
- Error is not related to transcripts (network, auth, etc.)
- Transcript is intentionally incomplete (ongoing session)

## Related Documentation

- **Full guide:** `build/docs/operations/transcript-corruption-detection.md`
- **Transcript format:** `build/docs/specifications/claude-code-transcript-format.md`
- **Classification:** `scripts/transcripts/classify_transcript.sh`
- **Database repair:** `scripts/db_manager.sh`

## Support

If repair script doesn't fix your issue:
1. Check full documentation in `build/docs/operations/transcript-corruption-detection.md`
2. Examine backup file to understand what was changed
3. File issue with transcript sample (redact sensitive content)
