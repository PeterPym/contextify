# Next Steps: Tool Call Conversion Implementation

**Branch:** `feature/tool-call-conversion`
**Status:** Ready for Phase 2a integration
**Date:** 2025-10-24

---

## Current Status ✅

### Completed
1. **Phase 1: Discovery & Documentation** - Complete
   - 7,601 Claude Code tool calls analyzed
   - 35 Codex function calls analyzed
   - 3-tier conversion strategy documented
   - All files organized in `build/notes/archive/implementation-docs/transcript-tool-conversion/`

2. **Tier 1 Helper Functions** - Complete
   - `tool_use_id_to_call_id()` / `call_id_to_tool_use_id()`
   - `bash_to_shell()` with command wrapping & exit code mapping
   - `shell_to_bash()` with command unwrapping
   - Committed in: `scripts/transcripts/convert_transcript.py` lines 55-231

---

## Test Transcripts Identified

### Claude Code Transcripts with Bash Calls

**Shortest (best for initial testing):**
```
~/.claude/projects/-Users-rob-code-projects-contextify/c118da1a-84e7-49b6-b631-967f48bae4bc.jsonl
- 47 lines
- 7 Bash calls
- Good mix of tool use + text messages
```

**Alternatives:**
```
ceae11b7-71f8-4e67-ae07-11df55d542b6.jsonl - 71 lines, 12 Bash calls
996d5218-4232-4489-b162-a0baa941bd5c.jsonl - 80 lines, 12 Bash calls
```

### Codex Transcripts with shell Calls

**Found (from Oct 19):**
```
~/.codex/sessions/2025/10/19/rollout-2025-10-19T13-34-08-0199fe2d-f20c-7c20-86f1-97dc9f502de4.jsonl
- 76KB
- Contains shell function calls
- Good for testing Codex → Claude Code conversion
```

**Note:** If existing Codex transcripts don't have enough tool calls, create new one with:
```bash
cd ~/code/projects/contextify
codex
# Then execute a few simple commands like:
# - ls -la
# - git status
# - echo "test"
```

---

## Phase 2a: Integration (Next Task)

### Approach: Two-Pass Processing

**Rationale:**
- Simpler logic (can look ahead/behind)
- Easier to debug
- Clean pairing of tool calls with results
- Memory overhead acceptable for typical transcripts (<1MB)

### Implementation Plan

**Step 1: Refactor `claude_to_codex()` for two-pass**
```python
def claude_to_codex(self, input_path, output_path):
    # Pass 1: Load all records
    records = []
    with open(input_path) as f:
        for line in f:
            records.append(json.loads(line))

    # Pass 2: Convert with full context
    with open(output_path, 'w') as outfile:
        for i, record in enumerate(records):
            # Can look ahead for tool_result matching tool_use
            next_record = records[i+1] if i+1 < len(records) else None
            # ... conversion logic
```

**Step 2: Process tool_use blocks in assistant messages**
```python
# When processing assistant message content:
for block in content:
    if block['type'] == 'tool_use' and block['name'] == 'Bash':
        # Find matching tool_result in next user message
        tool_result = find_tool_result(next_record, block['id'])
        # Convert using bash_to_shell()
        func_call, func_output = self.bash_to_shell(block, tool_result, timestamp)
        # Write to output
```

**Step 3: Test with real transcript**
```bash
# Test Claude Code → Codex
./scripts/transcripts/convert_transcript.py \
  --from claude-code \
  --to codex \
  -v \
  ~/.claude/projects/-Users-rob-code-projects-contextify/c118da1a-84e7-49b6-b631-967f48bae4bc.jsonl \
  /tmp/test-converted.jsonl

# Verify function_call records appear
grep '"type":"function_call"' /tmp/test-converted.jsonl | wc -l
# Should show: 7 (matching the 7 Bash calls)
```

**Step 4: Refactor `codex_to_claude()` for two-pass**
Similar approach, but converting function_call → tool_use

**Step 5: Test round-trip**
```bash
# Claude Code → Codex → Claude Code
./scripts/transcripts/convert_transcript.py --from claude-code --to codex input.jsonl temp.jsonl
./scripts/transcripts/convert_transcript.py --from codex --to claude-code temp.jsonl output.jsonl

# Verify Bash tool calls preserved
diff <(grep '"name":"Bash"' input.jsonl | wc -l) \
     <(grep '"name":"Bash"' output.jsonl | wc -l)
```

---

## Estimated Effort

**Two-pass integration:** 2-3 hours
- Refactor claude_to_codex: 1 hour
- Refactor codex_to_claude: 1 hour
- Testing with real transcripts: 30-60 min

**Acceptance Criteria:**
- ✅ Bash tool calls appear as shell function_call in converted Codex transcript
- ✅ shell function calls appear as Bash tool_use in converted Claude Code transcript
- ✅ Round-trip conversion preserves all Bash/shell calls
- ✅ Exit codes correctly mapped
- ✅ Commands correctly wrapped/unwrapped
- ✅ Stats show tool_calls_direct count

---

## After Phase 2a

### Optional: Create formal test fixtures
```
build/qa/transcript-converter/fixtures/
├── cc-with-bash-tools.jsonl       # Claude Code with Bash
├── codex-with-shell-tools.jsonl   # Codex with shell
└── expected-outputs/
    ├── cc-to-codex.jsonl
    └── codex-to-cc.jsonl
```

### Phase 2b: Tier 2 Implementation (Lossy Summarization)
- Edit → "I edited `file.py`..."
- Read → "I read `file.py` (N lines)"
- Grep → "I searched for `pattern`..."
- Write → "I created `file.py`..."
- Glob → "I found N files matching `pattern`"

**Estimated:** 3-4 hours

### Phase 2c: Testing & Documentation
- Comprehensive unit tests
- Update converter README
- Document known limitations
- Add conversion report to output

**Estimated:** 2-3 hours

---

## Total Timeline

- ✅ Phase 1: Discovery - Complete (1 hour)
- ✅ Tier 1 Helpers - Complete (1 hour)
- 🔄 Phase 2a: Integration - Next (2-3 hours)
- ⏸️ Phase 2b: Tier 2 - Pending (3-4 hours)
- ⏸️ Phase 2c: Testing - Pending (2-3 hours)

**Total remaining:** 7-10 hours to complete full tool conversion feature

---

## Quick Start for Next Session

```bash
# Ensure on correct branch
git checkout feature/tool-call-conversion

# Verify helper functions are there
grep -A5 "def bash_to_shell" scripts/transcripts/convert_transcript.py

# Copy test transcript to working location
cp ~/.claude/projects/-Users-rob-code-projects-contextify/c118da1a-84e7-49b6-b631-967f48bae4bc.jsonl \
   /tmp/test-cc-source.jsonl

# Ready to start Phase 2a integration
```

---

## Questions for User

1. **Test transcript approval:** Is `c118da1a-84e7-49b6-b631-967f48bae4bc.jsonl` (47 lines, 7 Bash calls) good for testing? Or would you prefer to create a fresh minimal example?

2. **Codex test:** Should I create a new minimal Codex conversation with 2-3 shell calls, or use the existing 76KB one?

3. **Integration timing:** Proceed with Phase 2a integration now, or wait for different session?

4. **Commit frequency:** Should I commit after Phase 2a (integration), or wait until all of Tier 1 is complete and tested?
