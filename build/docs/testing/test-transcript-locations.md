# Test Transcript Locations

## Synthetic Test Transcripts for Converter Validation

### Claude Code Format

**Location:** `~/.claude/projects/-tmp-test-project/test-session-12345.jsonl`

**Project path:** `/tmp/test-project`
**Session ID:** `test-session-12345`
**Format:** Claude Code JSONL (11 lines)

**To test:**
```bash
cd /tmp/test-project  # or mkdir -p /tmp/test-project
claude-code /resume test-session-12345
```

**Expected:** Claude Code loads conversation with TEST markers and remembers hello.py script

---

### Codex CLI Format

**Location:** `~/codex-sessions/test-converted-from-claude.jsonl`

**Project path:** `/tmp/test-project` (from session_meta)
**Session ID:** Generated during conversion
**Format:** Codex CLI JSONL (7 lines: 1 session_meta + 6 response_items)

**To test (if Codex CLI installed):**
```bash
cd /tmp/test-project
# Check Codex docs for actual resume syntax:
codex --resume ~/codex-sessions/test-converted-from-claude.jsonl
# OR
codex --session test-converted-from-claude
```

**Expected:** Codex loads conversation with TEST markers and 6 message history

---

## Conversation Summary

**Scenario:** User asks Claude to create and run a hello world Python script

**Message Flow:**
1. User: "Help me write hello world" (TEST TRANSCRIPT)
2. Assistant: "I'll help you" (TEST response)
3. Assistant: [Write hello.py with TEST function]
4. User: [tool result: File created]
5. Assistant: "Perfect! TEST function created"
6. User: "Run this TEST script"
7. Assistant: "I'll run the TEST script"
8. Assistant: [Bash: python hello.py]
9. User: [tool result: Hello World! TEST function]
10. Assistant: "Excellent! TEST script ran successfully"

**Test markers:**
- Every message contains "TEST" or "TEST TRANSCRIPT"
- Function prints "This is a TEST function"
- Clearly identifiable as synthetic test data

---

## Validation Steps

### For Claude Code
1. ✅ Transcript placed in correct location: `~/.claude/projects/-tmp-test-project/`
2. ✅ Filename matches session ID: `test-session-12345.jsonl`
3. ✅ Project key format: `-tmp-test-project` (path with slashes replaced by dashes)
4. ⏳ **Pending:** Test `/resume` command to verify format validity

### For Codex CLI
1. ✅ Converted transcript created: `~/codex-sessions/test-converted-from-claude.jsonl`
2. ✅ Includes session_meta with git/cwd context
3. ✅ 6 response_item messages in correct format
4. ⏳ **Pending:** Test with Codex CLI (requires Codex installation)

---

## Round-Trip Validation

**Test flow:**
1. Start: Claude Code format (11 lines, 6 messages)
2. Convert: → Codex format (7 lines: session_meta + 6 messages)
3. Convert back: → Claude Code format (6 lines)
4. Result: All message content preserved (100% fidelity)

**Information preserved:**
- ✅ All text content (character-for-character)
- ✅ Timestamps
- ✅ User/assistant roles
- ✅ Git context (cwd, branch)

**Information lost:**
- ⚠️  UUIDs (regenerated)
- ⚠️  Threading (parentUuid chains)
- ⚠️  Tool calls (not converted in Phase 1)
- ⚠️  Metadata (model, usage stats)

---

## Files Generated

1. **Converter:** `scripts/transcripts/convert_transcript.py` (executable)
2. **Claude Code test:** `~/.claude/projects/-tmp-test-project/test-session-12345.jsonl`
3. **Codex test:** `~/codex-sessions/test-converted-from-claude.jsonl`
4. **Documentation:**
   - `todos.md` (feature spec)
   - `build/docs/guides/transcript-converter.md` (usage guide)
   - `build/docs/testing/test-transcript-locations.md` (this file)
5. **Analysis:** `/tmp/conversion-analysis.md`, `/tmp/CONVERTER_TEST_RESULTS.md`

---

## Next Actions

1. **User testing:** Try `/resume test-session-12345` in Claude Code
2. **Codex testing:** If Codex installed, test session loading
3. **Iteration:** Based on test results, fix any format issues
4. **Determinism:** Implement hash-based UUID generation for perfect round-trips
5. **Phase 2:** Add tool call conversion support
