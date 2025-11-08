# Transcript Converter QA Test Plan

**Feature:** Cross-CLI Transcript Converter (Claude Code ↔ Codex CLI)
**Script:** `scripts/convert_transcript.py`
**QA Directory:** `build/qa/transcript-converter/`
**Status:** Phase 1 - User/Assistant Message Conversion

---

## Test Environment Setup

### Prerequisites
- Claude Code CLI installed (`claude --version`)
- Codex CLI installed (`codex --version`)
- Python 3.x with standard library
- Project directory: `/Users/rob/code/projects/contextify`

### Directory Structure
```
build/qa/transcript-converter/
├── fixtures/           # Generated test transcripts
├── outputs/            # Conversion outputs
├── generate_test_transcript.py  # Test transcript generator
├── TEST-PLAN.md       # This file
└── RESULTS.md         # Test execution results
```

---

## Test Categories

### Category 1: Format Validation

**Purpose:** Ensure generated transcripts match actual CLI formats exactly.

#### Test 1.1: Claude Code Format Validation
**Steps:**
1. Generate test transcript:
   ```bash
   ./build/qa/transcript-converter/generate_test_transcript.py \
     --format claude-code \
     --output build/qa/transcript-converter/fixtures/test-claude-$(date +%Y%m%d-%H%M%S).jsonl
   ```
2. Verify file structure:
   ```bash
   head -1 build/qa/transcript-converter/fixtures/test-claude-*.jsonl | python3 -m json.tool
   ```
3. Check required fields match spec (see `build/docs/specifications/claude-code-format.md`):
   - User message: `type`, `uuid`, `timestamp`, `parentUuid`, `sessionId`, `version`, `userType`, `cwd`, `gitBranch`, `isSidechain`, `isMeta`, `message`
   - Assistant message: `type`, `uuid`, `timestamp`, `parentUuid`, `sessionId`, `version`, `userType`, `cwd`, `gitBranch`, `isSidechain`, `requestId`, `message` (with `id`, `type`, `role`, `model`, `content[]`, `stop_reason`, `stop_sequence`, `usage`)

**Expected:** All required fields present with correct types and structure.

#### Test 1.2: Codex Format Validation
**Steps:**
1. Generate test transcript:
   ```bash
   ./build/qa/transcript-converter/generate_test_transcript.py \
     --format codex \
     --output build/qa/transcript-converter/fixtures/test-codex-$(date +%Y%m%d-%H%M%S).jsonl
   ```
2. Verify first line is `session_meta`:
   ```bash
   head -1 build/qa/transcript-converter/fixtures/test-codex-*.jsonl | python3 -m json.tool
   ```
3. Check message format (see `build/notes/archive/technical-briefing-local-history-claude-code-codex.md`):
   - `type: "response_item"`
   - `payload.type: "message"`
   - `payload.content[]` with `type: "input_text"` or `type: "output_text"`

**Expected:** session_meta first, then response_item messages with correct content block types.

---

### Category 2: CLI Resumption Tests

**Purpose:** Verify both CLIs can actually resume converted sessions.

#### Test 2.1: Resume Generated Claude Code Transcript
**Steps:**
1. Generate and copy transcript (done automatically by generator)
2. Note the session ID from output
3. Resume in Claude Code:
   ```bash
   cd /Users/rob/code/projects/contextify && claude --resume <session-id>
   ```
4. Verify you can see:
   - "This is a test conversation created at [timestamp] PST"
   - "Test session ID: [session-id]"
   - Conversation history is accessible

**Expected:** ✅ Claude Code loads conversation successfully.

#### Test 2.2: Resume Generated Codex Transcript
**Steps:**
1. Generate Codex transcript
2. Copy to proper Codex location:
   ```bash
   SESSION_ID=$(grep -o '"session_id": "[^"]*"' fixtures/test-codex-*.jsonl | cut -d'"' -f4 | head -1)
   mkdir -p ~/.codex/sessions/$(date +%Y/%m/%d)
   cp fixtures/test-codex-*.jsonl ~/.codex/sessions/$(date +%Y/%m/%d)/rollout-$(date +%Y-%m-%dT%H-%M-%S)-${SESSION_ID}.jsonl
   ```
3. Resume in Codex:
   ```bash
   cd /Users/rob/code/projects/contextify && codex resume ${SESSION_ID}
   ```
4. Verify conversation history is visible

**Expected:** ✅ Codex CLI loads conversation successfully.

---

### Category 3: Conversion Tests (Claude Code → Codex)

**Purpose:** Test conversion from Claude Code to Codex format.

#### Test 3.1: Convert Fresh Test Transcript
**Steps:**
1. Generate Claude Code test transcript (saved to fixtures)
2. Convert to Codex:
   ```bash
   ./scripts/convert_transcript.py \
     --from claude-code \
     --to codex \
     build/qa/transcript-converter/fixtures/test-claude-YYYYMMDD-HHMMSS.jsonl \
     build/qa/transcript-converter/outputs/converted-to-codex.jsonl
   ```
3. Check conversion statistics (should show 4 messages converted)
4. Verify output has session_meta + response_items
5. Copy to Codex sessions directory (follow resume instructions from converter)
6. Resume in Codex CLI

**Expected:**
- ✅ Conversion completes with 0 errors
- ✅ Output has correct Codex format
- ✅ Codex CLI can resume the session
- ✅ Conversation content matches original

#### Test 3.2: Convert Real Claude Code Session
**Steps:**
1. Pick a real Claude Code session from `~/.claude/projects/-Users-rob-code-projects-contextify/`
2. Convert to Codex:
   ```bash
   ./scripts/convert_transcript.py \
     --from claude-code \
     --to codex \
     ~/.claude/projects/-Users-rob-code-projects-contextify/<session-id>.jsonl \
     build/qa/transcript-converter/outputs/real-converted-to-codex.jsonl
   ```
3. Note conversion statistics (converted vs skipped counts)
4. Copy to Codex sessions directory
5. Resume in Codex CLI
6. Verify conversation matches original Claude Code session

**Expected:**
- ✅ Conversion handles real-world data
- ✅ Codex CLI resumes successfully
- ✅ Message content preserved

---

### Category 4: Conversion Tests (Codex → Claude Code)

**Purpose:** Test conversion from Codex to Claude Code format with UUID auto-correction.

#### Test 4.1: Convert Fresh Test Transcript
**Steps:**
1. Generate Codex test transcript (saved to fixtures)
2. Convert to Claude Code with arbitrary filename:
   ```bash
   ./scripts/convert_transcript.py \
     --from codex \
     --to claude-code \
     build/qa/transcript-converter/fixtures/test-codex-YYYYMMDD-HHMMSS.jsonl \
     build/qa/transcript-converter/outputs/arbitrary-name.jsonl
   ```
3. **Check for UUID auto-correction:**
   - Converter should detect non-UUID filename
   - Extract session_id from Codex session_meta
   - Auto-rename to `<session_id>.jsonl`
   - Show corrected filename in output
4. Verify converter output shows actual UUID filename
5. Copy to Claude Code sessions (if not auto-copied)
6. Resume in Claude Code CLI

**Expected:**
- ✅ Converter auto-corrects to UUID.jsonl format
- ✅ Shows warning about non-UUID filename
- ✅ Final path shows UUID filename
- ✅ Claude Code can resume the session
- ✅ Conversation content matches original

#### Test 4.2: Convert Real Codex Session
**Steps:**
1. Pick a real Codex session from `~/.codex/sessions/YYYY/MM/DD/`
2. Convert to Claude Code:
   ```bash
   ./scripts/convert_transcript.py \
     --from codex \
     --to claude-code \
     ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl \
     build/qa/transcript-converter/outputs/converted-real.jsonl
   ```
3. Verify UUID auto-correction happens
4. Copy to Claude Code sessions (use UUID filename from output)
5. Resume in Claude Code CLI
6. Verify conversation matches original

**Expected:**
- ✅ Auto-correction works on real data
- ✅ Claude Code resumes successfully
- ✅ Content preserved

---

### Category 5: Round-Trip Conversion

**Purpose:** Ensure data fidelity through bidirectional conversion.

#### Test 5.1: Claude Code → Codex → Claude Code
**Steps:**
1. Start with fresh Claude Code test transcript
2. Convert to Codex:
   ```bash
   ./scripts/convert_transcript.py \
     --from claude-code --to codex \
     build/qa/transcript-converter/fixtures/test-claude-ORIGINAL.jsonl \
     build/qa/transcript-converter/outputs/roundtrip-codex.jsonl
   ```
3. Convert back to Claude Code:
   ```bash
   ./scripts/convert_transcript.py \
     --from codex --to claude-code \
     build/qa/transcript-converter/outputs/roundtrip-codex.jsonl \
     build/qa/transcript-converter/outputs/roundtrip-claude-final.jsonl
   ```
4. Compare message counts: original vs final
5. Verify conversation content preserved (user/assistant messages)
6. Resume final version in Claude Code

**Expected:**
- ✅ All user/assistant messages preserved
- ✅ Message content identical
- ✅ Conversation resumable in Claude Code
- ✅ Metadata may differ (timestamps, UUIDs) but content matches

#### Test 5.2: Codex → Claude Code → Codex
**Steps:**
1. Start with fresh Codex test transcript
2. Convert to Claude Code
3. Convert back to Codex
4. Compare message counts
5. Resume final version in Codex

**Expected:**
- ✅ All messages preserved
- ✅ Content identical
- ✅ Resumable in Codex

---

### Category 6: Edge Cases & Error Handling

**Purpose:** Test converter robustness with malformed/edge-case inputs.

#### Test 6.1: Empty Files
**Steps:**
1. Create empty file: `touch build/qa/transcript-converter/fixtures/empty.jsonl`
2. Try converting: `./scripts/convert_transcript.py --from claude-code --to codex fixtures/empty.jsonl outputs/empty-out.jsonl`

**Expected:** ✅ Completes with 0 converted, 0 errors

#### Test 6.2: Malformed JSON
**Steps:**
1. Create file with invalid JSON:
   ```bash
   echo '{"type": "user", invalid json here' > build/qa/transcript-converter/fixtures/malformed.jsonl
   ```
2. Try converting

**Expected:** ✅ Logs error, continues processing, shows error count > 0

#### Test 6.3: Missing Required Fields
**Steps:**
1. Create record without `timestamp`:
   ```bash
   echo '{"type":"user","uuid":"abc","message":{"role":"user","content":"test"}}' > build/qa/transcript-converter/fixtures/missing-timestamp.jsonl
   ```
2. Convert

**Expected:** ✅ Logs validation error, continues, increments error count

#### Test 6.4: Non-UUID Filename (Codex → Claude Code)
**Already covered in Test 4.1**

**Expected:** ✅ Auto-correction works

#### Test 6.5: Paths with Spaces
**Steps:**
1. Create directory: `mkdir -p "build/qa/transcript-converter/fixtures/path with spaces"`
2. Generate transcript to that path
3. Convert

**Expected:** ✅ Handles paths with spaces correctly

---

### Category 7: Directory Sensitivity

**Purpose:** Verify resume commands require correct project directory.

#### Test 7.1: Resume from Wrong Directory (Claude Code)
**Steps:**
1. Generate test transcript (session in correct project)
2. Try resuming from /tmp:
   ```bash
   cd /tmp && claude --resume <session-id>
   ```

**Expected:** ❌ "No conversation found with session ID"

#### Test 7.2: Resume from Correct Directory (Claude Code)
**Steps:**
1. Resume from project directory:
   ```bash
   cd /Users/rob/code/projects/contextify && claude --resume <session-id>
   ```

**Expected:** ✅ Session loads successfully

#### Test 7.3: Resume Instructions Include `cd &&` Syntax
**Steps:**
1. Run any conversion
2. Check resume instructions in output

**Expected:** ✅ Shows `cd <project-dir> && <cli> resume <session-id>`

---

## Test Execution Checklist

Before claiming QA complete, verify:

- [ ] All Category 1 tests pass (format validation)
- [ ] All Category 2 tests pass (CLI resumption)
- [ ] All Category 3 tests pass (Claude Code → Codex)
- [ ] All Category 4 tests pass (Codex → Claude Code)
- [ ] All Category 5 tests pass (round-trip)
- [ ] All Category 6 tests pass (edge cases)
- [ ] All Category 7 tests pass (directory sensitivity)
- [ ] Test generator creates valid transcripts for both formats
- [ ] UUID auto-correction works in all cases
- [ ] Resume instructions are accurate and complete
- [ ] Documentation updated (RESULTS.md)

---

## Documentation Requirements

After testing, update:
1. **`RESULTS.md`** - Test execution results with pass/fail for each test
2. **`scripts/TRANSCRIPT_CONVERTER_README.md`** - Update with any findings
3. **`build/docs/guides/transcript-resumption.md`** - Clarify any resume issues discovered
4. **Commit all findings to feature branch**

---

## Known Limitations (Phase 1)

The following are **expected** and **not bugs**:

1. **Tool calls not converted** - `tool_use` and `tool_result` blocks are skipped
2. **Threading simplified** - `parentUuid` chains may not preserve complex branching
3. **File snapshots dropped** - Claude Code `file-history-snapshot` records not converted
4. **Metadata differences** - UUIDs, timestamps regenerated during conversion
5. **Sidechain messages skipped** - `isSidechain: true` messages not included
6. **Encrypted reasoning dropped** - Codex reasoning not converted to Claude Code

These are planned for **Phase 2**.

---

## Success Criteria

✅ **Phase 1 Complete** when:
- All test categories pass
- Both CLIs can resume converted sessions
- UUID auto-correction works reliably
- Round-trip conversion preserves conversation content
- Edge cases handled gracefully
- Documentation complete

---

## Automation Opportunities (Future)

- Script to run all tests and generate RESULTS.md automatically
- CI integration to run tests on every commit
- Automated comparison of original vs converted message content
- Performance benchmarks (conversion speed, file size)
