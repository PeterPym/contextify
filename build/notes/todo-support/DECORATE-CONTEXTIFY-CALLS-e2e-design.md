# E2E Test Design: Contextify Call Decoration

**Feature:** DECORATE-CONTEXTIFY-CALLS
**Date:** 2025-12-22
**Status:** Design

---

## Overview

End-to-end tests to verify that Contextify skill and agent invocations are correctly:
1. Ingested into `tool_invocations` table with `is_contextify = 1`
2. Decorated in the timeline UI with the infinity logomark

## Test Strategy

### Test Levels

| Level | What it Tests | Complexity | Reliability |
|-------|---------------|------------|-------------|
| Database | `is_contextify` flag set correctly | Low | High |
| CLI | `contextify-query` returns decoration data | Low | High |
| UI | Logomark visible in timeline | High | Medium |

**Recommendation:** Implement database + CLI tests first (high reliability), defer UI test.

---

## Test QA-16: Contextify Skill Decoration (Fixture)

### Purpose
Verify that a transcript containing a `query:contextify-reinject` skill invocation is ingested with `is_contextify = 1`.

### Test Contract
```yaml
isolation:
  transcripts: fixture (creates new project)
  database: preserve
database:
  location: default
  start:
    exists: true
  mutations:
    - "Ingests fixture transcript with Skill tool_use block"
    - "Creates tool_invocations row with is_contextify = 1"
  end:
    exists: true
dependencies:
  cli_tools: []
  notes: "Fixture-based test, no CLI tools required"
```

### Fixture: `scripts/qa/fixtures/transcripts/claude/contextify-skill.jsonl`

Minimal JSONL with:
1. User message (to establish session)
2. Assistant message with `tool_use` block: `name: "Skill"`, `input.skill: "query:contextify-reinject"`
3. User message with `tool_result` block

```jsonl
{"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"__TEST_PROJECT__","sessionId":"e2e-skill-test-001","version":"2.0.65","gitBranch":"main","type":"user","message":{"role":"user","content":"Search conversation history for test"},"uuid":"user-001","timestamp":"2025-12-22T00:01:00.000Z"}
{"parentUuid":"user-001","isSidechain":false,"userType":"external","cwd":"__TEST_PROJECT__","sessionId":"e2e-skill-test-001","version":"2.0.65","gitBranch":"main","message":{"model":"claude-sonnet-4-5-20250929","id":"msg_skill_test","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_skill_001","name":"Skill","input":{"skill":"query:contextify-reinject","args":"test search term"}}],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":100,"output_tokens":50}},"requestId":"req_skill_001","type":"assistant","uuid":"assistant-001","timestamp":"2025-12-22T00:01:01.000Z"}
{"parentUuid":"assistant-001","isSidechain":false,"userType":"external","cwd":"__TEST_PROJECT__","sessionId":"e2e-skill-test-001","version":"2.0.65","gitBranch":"main","type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_skill_001","content":"Launching skill: query:contextify-reinject","is_error":false,"toolUseResult":{"commandName":"query:contextify-reinject"}}]},"uuid":"user-002","timestamp":"2025-12-22T00:01:02.000Z"}
```

### Test Steps

```bash
# 1. Setup: Install fixture transcript
install_fixture "claude/contextify-skill.jsonl" "$TEST_PROJECT"

# 2. Wait for ingestion (app must be running)
wait_for_ingestion 10

# 3. Assert: tool_invocations has is_contextify = 1
assert_db_count \
  "SELECT COUNT(*) FROM tool_invocations WHERE tool_key = 'query:contextify-reinject' AND is_contextify = 1" \
  1 \
  "Skill invocation marked as Contextify"

# 4. Assert: entry_id is populated
assert_db_row_exists \
  "SELECT entry_id FROM tool_invocations WHERE tool_key = 'query:contextify-reinject' AND entry_id IS NOT NULL" \
  "Skill invocation has entry_id"
```

---

## Test QA-17: Contextify Agent Decoration (Fixture)

### Purpose
Verify that a transcript containing a `query:contextify-researcher` agent invocation (Task tool) is ingested with `is_contextify = 1`.

### Test Contract
```yaml
isolation:
  transcripts: fixture (creates new project)
  database: preserve
database:
  location: default
  start:
    exists: true
  mutations:
    - "Ingests fixture transcript with Task tool_use block"
    - "Creates tool_invocations row with is_contextify = 1"
  end:
    exists: true
dependencies:
  cli_tools: []
  notes: "Fixture-based test, no CLI tools required"
```

### Fixture: `scripts/qa/fixtures/transcripts/claude/contextify-agent.jsonl`

Minimal JSONL with:
1. User message
2. Assistant message with `tool_use` block: `name: "Task"`, `input.subagent_type: "query:contextify-researcher"`
3. User message with `tool_result` block (includes `agentId`)
4. Sidechain transcript: `agent-e2eagent.jsonl`

**Main transcript:**
```jsonl
{"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"__TEST_PROJECT__","sessionId":"e2e-agent-test-001","version":"2.0.65","gitBranch":"main","type":"user","message":{"role":"user","content":"Search conversation history using the researcher agent"},"uuid":"user-agent-001","timestamp":"2025-12-22T00:02:00.000Z"}
{"parentUuid":"user-agent-001","isSidechain":false,"userType":"external","cwd":"__TEST_PROJECT__","sessionId":"e2e-agent-test-001","version":"2.0.65","gitBranch":"main","message":{"model":"claude-sonnet-4-5-20250929","id":"msg_agent_test","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_agent_001","name":"Task","input":{"subagent_type":"query:contextify-researcher","prompt":"Search for test data","description":"Search history"}}],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":100,"output_tokens":50}},"requestId":"req_agent_001","type":"assistant","uuid":"assistant-agent-001","timestamp":"2025-12-22T00:02:01.000Z"}
{"parentUuid":"assistant-agent-001","isSidechain":false,"userType":"external","cwd":"__TEST_PROJECT__","sessionId":"e2e-agent-test-001","version":"2.0.65","gitBranch":"main","type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_agent_001","content":"Agent completed successfully","is_error":false,"toolUseResult":{"status":"completed","agentId":"e2eagent"}}]},"uuid":"user-agent-002","timestamp":"2025-12-22T00:02:30.000Z"}
```

**Sidechain transcript (`agent-e2eagent.jsonl`):**
```jsonl
{"agentId":"e2eagent","sessionId":"e2e-agent-test-001","isSidechain":true,"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Agent work completed."}]},"uuid":"sidechain-001","timestamp":"2025-12-22T00:02:15.000Z"}
```

### Test Steps

```bash
# 1. Setup: Install fixture transcripts (main + sidechain)
install_fixture "claude/contextify-agent.jsonl" "$TEST_PROJECT"
install_fixture "claude/agent-e2eagent.jsonl" "$TEST_PROJECT"

# 2. Wait for ingestion
wait_for_ingestion 10

# 3. Assert: tool_invocations has is_contextify = 1 for agent call
assert_db_count \
  "SELECT COUNT(*) FROM tool_invocations WHERE tool_key = 'query:contextify-researcher' AND is_contextify = 1" \
  1 \
  "Agent invocation marked as Contextify"

# 4. Assert: sidechain_transcript_id is populated
assert_db_row_exists \
  "SELECT sidechain_transcript_id FROM tool_invocations WHERE tool_key = 'query:contextify-researcher' AND sidechain_transcript_id IS NOT NULL" \
  "Agent invocation has sidechain linkage"
```

---

## Test QA-18: Non-Contextify Tool Not Decorated

### Purpose
Verify that regular tool invocations (e.g., `Bash`, `Read`) do NOT get `is_contextify = 1`.

### Fixture: `scripts/qa/fixtures/transcripts/claude/regular-tools.jsonl`

```jsonl
{"parentUuid":null,"isSidechain":false,"userType":"external","cwd":"__TEST_PROJECT__","sessionId":"e2e-regular-test-001","version":"2.0.65","gitBranch":"main","type":"user","message":{"role":"user","content":"Run ls command"},"uuid":"user-reg-001","timestamp":"2025-12-22T00:03:00.000Z"}
{"parentUuid":"user-reg-001","isSidechain":false,"userType":"external","cwd":"__TEST_PROJECT__","sessionId":"e2e-regular-test-001","version":"2.0.65","gitBranch":"main","message":{"model":"claude-sonnet-4-5-20250929","id":"msg_reg_test","type":"message","role":"assistant","content":[{"type":"tool_use","id":"toolu_bash_001","name":"Bash","input":{"command":"ls -la"}}],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":100,"output_tokens":50}},"requestId":"req_reg_001","type":"assistant","uuid":"assistant-reg-001","timestamp":"2025-12-22T00:03:01.000Z"}
{"parentUuid":"assistant-reg-001","isSidechain":false,"userType":"external","cwd":"__TEST_PROJECT__","sessionId":"e2e-regular-test-001","version":"2.0.65","gitBranch":"main","type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_bash_001","content":"total 0\ndrwxr-xr-x 2 user staff 64 Dec 22 00:00 .","is_error":false}]},"uuid":"user-reg-002","timestamp":"2025-12-22T00:03:02.000Z"}
```

### Test Steps

```bash
# 1. Setup: Install fixture
install_fixture "claude/regular-tools.jsonl" "$TEST_PROJECT"

# 2. Wait for ingestion
wait_for_ingestion 10

# 3. Assert: Bash tool has is_contextify = 0
assert_db_count \
  "SELECT COUNT(*) FROM tool_invocations WHERE tool_name = 'Bash' AND is_contextify = 0" \
  1 \
  "Regular tool NOT marked as Contextify"

# 4. Assert: No Contextify entries for this session
assert_db_count \
  "SELECT COUNT(*) FROM tool_invocations ti JOIN transcripts t ON ti.transcript_id = t.id WHERE t.session_id = 'e2e-regular-test-001' AND ti.is_contextify = 1" \
  0 \
  "Session has no Contextify invocations"
```

---

## Test CLI-04: Contextify Entry IDs Queryable

### Purpose
Verify that `contextify-query` (or a new subcommand) can return Contextify entry IDs for decoration.

### Test Contract
```yaml
isolation:
  transcripts: fixture
  database: preserve
dependencies:
  cli_tools: [contextify-query, jq]
```

### Test Steps

```bash
# 1. Setup: Install skill fixture
install_fixture "claude/contextify-skill.jsonl" "$TEST_PROJECT"
wait_for_ingestion 10

# 2. Get project ID
PROJECT_ID=$(sqlite3 "$DB_PATH" "SELECT id FROM projects WHERE root_path = '$TEST_PROJECT'")

# 3. Query Contextify entries (new subcommand or SQL)
# Option A: Direct SQL
CONTEXTIFY_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tool_invocations ti JOIN transcripts t ON ti.transcript_id = t.id JOIN projects p ON t.project_id = p.id WHERE p.root_path = '$TEST_PROJECT' AND ti.is_contextify = 1")

assert_equals "$CONTEXTIFY_COUNT" "1" "Contextify entry count via SQL"

# Option B: CLI subcommand (future)
# contextify-query contextify-entries --project "$PROJECT_ID" --json | jq '.count'
```

---

## Live CLI Tests (Non-Fixture)

For testing with actual Claude Code CLI generating real transcripts:

### Test CLI-05: Live Skill Invocation Decoration

**Requires:** Claude Code CLI, authenticated

```bash
# 1. Create test project
TEST_PROJECT="/tmp/contextify-live-skill-test"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# 2. Run Claude in non-interactive mode with skill trigger
echo "/query:contextify-reinject test" | claude -p --output-format json --dangerously-skip-permissions

# 3. Wait for ingestion (with app running)
sleep 15

# 4. Verify in database
assert_db_count \
  "SELECT COUNT(*) FROM tool_invocations WHERE tool_key = 'query:contextify-reinject' AND is_contextify = 1" \
  1 \
  "Live skill invocation decorated"
```

### Test CLI-06: Live Agent Invocation Decoration

**Requires:** Claude Code CLI, authenticated, Task tool enabled

```bash
# 1. Create test project
TEST_PROJECT="/tmp/contextify-live-agent-test"
mkdir -p "$TEST_PROJECT"
cd "$TEST_PROJECT"

# 2. System prompt to trigger agent
SYSTEM_PROMPT="When asked to research, use the Task tool with subagent_type='query:contextify-researcher'"

# 3. Run Claude with agent trigger
echo "Research our conversation history" | claude -p --output-format json --dangerously-skip-permissions --system-prompt "$SYSTEM_PROMPT"

# 4. Wait for ingestion (agent takes longer)
sleep 30

# 5. Verify in database
assert_db_count \
  "SELECT COUNT(*) FROM tool_invocations WHERE tool_key = 'query:contextify-researcher' AND is_contextify = 1" \
  1 \
  "Live agent invocation decorated"
```

---

## Implementation Plan

### Phase 1: Fixtures (Priority)

1. Create fixture files:
   - `scripts/qa/fixtures/transcripts/claude/contextify-skill.jsonl`
   - `scripts/qa/fixtures/transcripts/claude/contextify-agent.jsonl`
   - `scripts/qa/fixtures/transcripts/claude/agent-e2eagent.jsonl`
   - `scripts/qa/fixtures/transcripts/claude/regular-tools.jsonl`

2. Create test script:
   - `scripts/qa/tests/QA-16-contextify-decoration.sh`

3. Add to test runner:
   - Update `run-all-tests.sh` with QA-16

### Phase 2: CLI Tests

1. Create CLI test:
   - `scripts/qa/tests/CLI-04-contextify-entries.sh`

### Phase 3: Live Tests (Optional)

1. Add live tests that require Claude CLI:
   - `scripts/qa/tests/CLI-05-live-skill-decoration.sh`
   - `scripts/qa/tests/CLI-06-live-agent-decoration.sh`

### Phase 4: UI Tests (Deferred)

UI verification via AppleScript/Accessibility is complex and brittle. Defer until database/CLI tests prove stable.

---

## Test Data Requirements

| Fixture | Records | Tool Type | Expected `is_contextify` |
|---------|---------|-----------|--------------------------|
| contextify-skill.jsonl | 3 | Skill (query:contextify-reinject) | 1 |
| contextify-agent.jsonl | 3 | Task (query:contextify-researcher) | 1 |
| agent-e2eagent.jsonl | 1 | (sidechain) | N/A |
| regular-tools.jsonl | 3 | Bash | 0 |

---

## Success Criteria

1. **QA-16 passes**: Skill fixture ingested with `is_contextify = 1`
2. **QA-17 passes**: Agent fixture ingested with `is_contextify = 1`, sidechain linked
3. **QA-18 passes**: Regular tools NOT marked as Contextify
4. **CLI-04 passes**: Entry IDs queryable via SQL/CLI

---

## Notes

- Fixtures use `__TEST_PROJECT__` placeholder, replaced at runtime with `sed`
- Session IDs are deterministic (`e2e-skill-test-001`, etc.) for easy querying
- Tests assume app is running and will ingest transcripts automatically
- Consider adding `contextify-query contextify-entries` subcommand for cleaner CLI testing
