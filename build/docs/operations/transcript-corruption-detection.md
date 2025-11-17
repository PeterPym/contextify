# Transcript Corruption Detection & Repair

**Status:** Implemented (2025-11-07)
**Issue:** Claude Code Web "teleport" feature creates corrupted transcripts
**Impact:** High - prevents session continuation with API 400 errors

## Overview

Claude Code Web (new product released 2025) allows "teleporting" conversations from web to CLI via the "Send to CLI" button.

**How Teleport Works:**
1. Web session gets frozen/hung (appears to be doing something but is actually stuck)
2. "Send to CLI" button copies command to clipboard: `claude --teleport session_011C...`
3. Running this command downloads the web transcript to local `~/.claude/projects/` directory
4. CLI opens the conversation, allowing you to continue

**The Problem:**
The teleport process frequently creates corrupted transcript files. The transcript downloads successfully and the CLI opens the session, but attempting to send a new message fails with API 400 error.

**Common Symptoms:**
- Web session was frozen/hung before teleport
- Teleport command runs successfully
- CLI opens conversation without errors
- **First new message fails with API Error 400:** "unexpected `tool_use_id` found in `tool_result` blocks"
- Session cannot be continued without repairing transcript
- Missing tool_use blocks in assistant messages
- Orphaned tool_result blocks in user messages

## Corruption Patterns

### 1. Orphaned tool_result
**Description:** User message contains a `tool_result` block whose `tool_use_id` never appeared anywhere in the transcript.

> **Important:** Claude Code CLI legitimately emits user records containing `tool_result` blocks that reference the prior assistant `tool_use` entry. Those are **not** corruption cases. Treat the record as corrupt only when the referenced `tool_use_id` is missing entirely (common in Claude Code Web teleport dumps).

**Example:**
```jsonl
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"..."}],"stop_reason":"tool_use"}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_ABC","content":"..."}]}}
```

**Cause:** Claude Code Web loses `tool_use` blocks during conversation teleport or manual edits removed the assistant entry.

**Recovery:** Skip the orphaned `tool_result` message entirely and log the missing ID (parser now tracks these as `[PARSER-WARN]` with telemetry counters).

### 2. stop_reason Mismatch
**Description:** Assistant message has `stop_reason="tool_use"` but contains no `tool_use` content blocks.

**Example:**
```jsonl
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"..."}],"stop_reason":"tool_use"}}
```

**Cause:** Tool_use blocks removed/lost during teleport, but stop_reason field not updated.

**Recovery:** Change `stop_reason` to `"end_turn"` or `null`.

### 3. Broken Parent Chain
**Description:** Message references a `parentUuid` that doesn't exist (was removed during repair).

**Example:**
```jsonl
// Line 1746 - kept
{"uuid":"UUID_A","parentUuid":"UUID_B"}
// Line 1747 - deleted (orphaned tool_result)
{"uuid":"UUID_B","parentUuid":"UUID_C"}
// Line 1748 - needs parent update
{"uuid":"UUID_D","parentUuid":"UUID_B"}  // UUID_B was deleted!
```

**Cause:** Secondary effect of removing corrupted messages.

**Recovery:** Update `parentUuid` to point to grandparent (UUID_A in example).

## Detection

### Automatic Detection (Ingestion Time)

Contextify automatically validates transcripts during ingestion via `ClaudeCodeLineParser.validateMessageIntegrity()`. The parser tracks assistant `tool_use` IDs and matches them against user `tool_result` blocks, emitting warnings only when the ID was never seen.

**Location:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift:197-286`

**Behavior:**
- Throws `ParserError.corruptedRecord(.orphanedToolResult, details: "...")` for orphaned tool_results
- Throws `ParserError.corruptedRecord(.stopReasonMismatch, details: "...")` for stop_reason mismatches
- Logs detailed error information for debugging
- **Does NOT automatically repair** - requires manual intervention

**Error Log Example:**
```
ERROR: Corrupted transcript record detected
Type: orphaned_tool_result
Line: 1747
UUID: d793b3f1-97d1-4f5e-b160-922054b2521b
Details: tool_result references tool_use_id='toolu_018qN95...' which doesn't exist
```

### Manual Analysis

Use the `repair_transcript.py` script to analyze any transcript:

```bash
python3 scripts/repair_transcript.py <transcript_file> --dry-run
```

**Output:**
- Lists all detected corruption issues
- Shows line numbers and UUIDs
- Indicates if corruption is recoverable
- Provides repair plan (without modifying file)

## Repair

### Automated Repair Script

**Location:** `scripts/repair_transcript.py`

**Usage:**
```bash
# Analyze without modifying
python3 scripts/repair_transcript.py <transcript> --dry-run

# Repair in place (creates .backup)
python3 scripts/repair_transcript.py <transcript>

# Repair to new file
python3 scripts/repair_transcript.py <transcript> -o <output>
```

**Actions Performed:**
1. **Remove orphaned tool_results** - Delete user messages with orphaned tool_result blocks
2. **Fix stop_reason** - Change `stop_reason="tool_use"` to `"end_turn"` when no tool_use blocks present
3. **Fix parent chains** - Update parentUuid references for messages following deleted records
4. **Preserve valid messages** - Keep all non-corrupted messages intact

**Safety:**
- Creates `.backup` file before modifying original
- Validates JSON structure after repair
- Reports all changes made

### Manual Repair (Advanced)

For complex corruption or custom requirements:

1. **Backup original:**
   ```bash
   cp transcript.jsonl transcript.jsonl.backup
   ```

2. **Identify corruption:** Use `--dry-run` mode to see issues

3. **Edit JSON manually:**
   - Remove lines with orphaned tool_results
   - Fix stop_reason fields
   - Update parentUuid references
   - Use `jq` for validation: `jq -c '.' < transcript.jsonl > /dev/null`

4. **Test repaired file:** Try continuing session in Claude Code

## Prevention

**Recommendation:** Avoid using Claude Code Web "teleport" feature for critical sessions.

**Alternatives:**
1. Start sessions directly in CLI (no teleport needed)
2. Use Contextify's transcript monitoring to detect corruption early
3. Keep backups of transcript files before teleporting

## Statistics

**Analysis of Real Corruption (Session 42d110d2):**
- Total lines: 1,899
- Corruption issues: 35 (1.8% of records)
  - stop_reason mismatches: 18
  - Orphaned tool_results: 17
- Lines removed after repair: 17
- Lines modified: 18
- Final line count: 1,882 (99.1% preserved)

This data shows Claude Code Web corruption is **widespread and systematic**, not occasional.

## Implementation Details

### Parser Validation

**File:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

**Method:** `ClaudeCodeLineParser.validateMessageIntegrity()`

**Validations:**
1. Check user messages for orphaned tool_result blocks
2. Check assistant messages for stop_reason/content mismatches
3. Validate content block structures
4. Ensure tool_result blocks have required fields

**Error Types:**
- `ParserError.corruptedRecord(.orphanedToolResult, details: String)`
- `ParserError.corruptedRecord(.stopReasonMismatch, details: String)`
- `ParserError.corruptedRecord(.invalidContentBlock, details: String)`

### HooverEngine Integration

The HooverEngine catches `ParserError.corruptedRecord` exceptions during ingestion and:
1. Logs detailed corruption information
2. Skips the corrupted record
3. Continues processing subsequent records
4. Marks transcript status appropriately

This allows partial ingestion of corrupted transcripts while preserving valid content.

## Future Improvements

**Potential enhancements:**
1. **Auto-repair mode** - Optionally repair corruption automatically during ingestion
2. **Corruption metrics** - Track corruption rates by provider/version
3. **UI notifications** - Alert users when corrupted transcripts detected
4. **Repair history** - Track which transcripts have been repaired
5. **Validation API** - Expose corruption detection via REST API for external tools

## References

**Code:**
- Validation: `app/Sources/ContextifyCore/Database/TranscriptParsers.swift:197-286`
- Error types: `app/Sources/ContextifyCore/Database/HooverEngine.swift:619-634`
- Repair script: `scripts/repair_transcript.py`

**Documentation:**
- Claude Code format spec: `build/docs/specifications/claude-code-format.md`
- Transcript classification: `scripts/classify_transcript.sh`

**Real-world example:**
- Session: `42d110d2-9011-4dc3-85ff-a86a26ae0b82`
- Analysis: 35 corruption issues detected and repaired
- Backup: `/Users/rob/.claude/projects/.../42d110d2-9011-4dc3-85ff-a86a26ae0b82.jsonl.backup`
