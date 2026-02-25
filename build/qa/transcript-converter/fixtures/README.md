# Transcript Converter Test Fixtures

**Generated:** 2025-10-24
**Generator Script:** `build/qa/transcript-converter/generate_test_transcript.py` (commit `1fb2f14`)
**Converter Script:** `scripts/transcripts/convert_transcript.py` (commit `21719e5`)

## Fixtures

### 01-generated-claude-code.jsonl

**Format:** Claude Code JSONL
**Scenario:** continuity-test
**Exchanges:** 3
**Records:** 9 (3 × [user, file-history-snapshot, assistant])

**Generation command:**
```bash
python3 build/qa/transcript-converter/generate_test_transcript.py \
  --format claude-code \
  --scenario continuity-test \
  --exchanges 3 \
  --output build/qa/transcript-converter/fixtures/01-generated-claude-code.jsonl
```

**Test command:**
```bash
# Copy to Claude Code sessions directory (UUID from sessionId in file)
SESSION_ID=$(jq -r '.sessionId' build/qa/transcript-converter/fixtures/01-generated-claude-code.jsonl | head -1)
cp build/qa/transcript-converter/fixtures/01-generated-claude-code.jsonl \
  ~/.claude/projects/-Users-rob-code-projects-contextify/${SESSION_ID}.jsonl

# Resume in Claude Code
cd /Users/rob/code/projects/contextify && claude --resume ${SESSION_ID}
```

**Expected result:** All 3 exchanges display correctly with context preserved (SECRET_CODE, fibonacci, test file path)

---

### 02-generated-codex.jsonl

**Format:** Codex CLI JSONL
**Scenario:** basic
**Exchanges:** 2
**Records:** 11 (session_meta + 2 exchanges × 5 records each)
**Session ID:** ba3ce891-008b-424e-9798-12a2f7617566

**Generation command:**
```bash
python3 build/qa/transcript-converter/generate_test_transcript.py \
  --format codex \
  --exchanges 2 \
  --output build/qa/transcript-converter/fixtures/02-generated-codex.jsonl
```

**Test command:**
```bash
# Extract session ID and timestamp from file
SESSION_ID=$(jq -r 'select(.type=="session_meta") | .payload.id' \
  build/qa/transcript-converter/fixtures/02-generated-codex.jsonl)

# Copy to Codex sessions directory with proper filename format
# rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl
TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)
CODEX_DIR=~/.codex/sessions/$(date +%Y/%m/%d)
mkdir -p ${CODEX_DIR}
cp build/qa/transcript-converter/fixtures/02-generated-codex.jsonl \
  ${CODEX_DIR}/rollout-${TIMESTAMP}-${SESSION_ID}.jsonl

# Resume in Codex
cd /Users/rob/code/projects/contextify && codex resume ${SESSION_ID}
```

**Expected result:** All 2 exchanges display correctly

**Record structure:** Each Codex exchange requires 5 records:
1. `response_item` (user)
2. `event_msg` (user_message) - what displays to user
3. `turn_context` - marks turn boundary
4. `event_msg` (agent_message) - what displays to user
5. `response_item` (assistant)

---

### 03-converted-to-codex.jsonl

**Format:** Codex CLI JSONL (converted from Claude Code)
**Source:** 01-generated-claude-code.jsonl
**Records:** 16 (session_meta + 3 exchanges × 5 records each)
**Session ID:** ba3b7687-1f9a-4215-9798-4f24aeb4ab3a (NOTE: Different from fixture 1)

**Conversion command:**
```bash
python3 scripts/transcripts/convert_transcript.py \
  --from claude-code \
  --to codex \
  build/qa/transcript-converter/fixtures/01-generated-claude-code.jsonl \
  build/qa/transcript-converter/fixtures/03-converted-to-codex.jsonl
```

**Note:** The converter automatically places the file in `~/.codex/sessions/YYYY/MM/DD/` with proper filename format and displays the session ID.

**Test command:**
```bash
# The converter shows the session ID and resume command
# Example output:
# ✓ Converted Claude Code → Codex CLI: ~/.codex/sessions/2025/10/24/rollout-2025-10-24T17-48-58-ba3b7687-1f9a-4215-9798-4f24aeb4ab3a.jsonl
# Session ID: ba3b7687-1f9a-4215-9798-4f24aeb4ab3a

# Use the session ID from converter output
cd /Users/rob/code/projects/contextify && codex resume ba3b7687-1f9a-4215-9798-4f24aeb4ab3a
```

**Expected result:** All 3 exchanges from original Claude Code transcript display correctly in Codex

---

## Validation Checklist

Before committing fixtures, validate each one:

- [x] **01-generated-claude-code.jsonl**: Resume in Claude Code shows all 3 exchanges ✓
- [x] **02-generated-codex.jsonl**: Resume in Codex shows all 2 exchanges ✓
- [x] **03-converted-to-codex.jsonl**: Resume in Codex shows all 3 exchanges (converted from Claude Code) ✓

## Validation Status

**All conversion paths verified working (2025-10-24):**

✅ **Claude Code → Codex** - Working
✅ **Codex → Claude Code** - Working (fixed parentUuid threading)
✅ **Round-trip (CC → Codex → CC → Codex)** - Working

**Critical fixes implemented:**
1. Monotonic timestamps (both directions)
2. parentUuid conversation threading (Codex → Claude)
3. Complete Codex record structure (5 records per exchange)
4. file-history-snapshot generation (Codex → Claude)

## File Structure Validation

```bash
# Verify monotonic timestamps
jq -r 'if .timestamp then .timestamp else .snapshot.timestamp end' \
  build/qa/transcript-converter/fixtures/01-generated-claude-code.jsonl | \
  uniq -d
# (empty output = no duplicates = good)

# Check record types in Claude Code file
jq -r '.type' build/qa/transcript-converter/fixtures/01-generated-claude-code.jsonl | \
  sort | uniq -c
# Expected: 3 assistant, 3 file-history-snapshot, 3 user

# Check Codex session structure
jq -r '.type' build/qa/transcript-converter/fixtures/02-generated-codex.jsonl | \
  head -5
# Expected: session_meta, event_msg, response_item, turn_context, event_msg, response_item...
```

## Regeneration

To regenerate these fixtures with updated scripts:

1. Update script commits in this README header
2. Run generation commands above
3. Validate all fixtures
4. Commit updated fixtures with clear commit message noting script changes
