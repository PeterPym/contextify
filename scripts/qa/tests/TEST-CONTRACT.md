# QA Test Contract Format

Each QA test script includes a `@test_contract` YAML block that documents:

1. **Isolation requirements** - How transcripts and database are handled
2. **Database state** - Expected state at start, mutations during test, state at end
3. **Dependencies** - Other tests or orchestrator flags required

## Contract Format

```bash
# @test_contract
# isolation:
#   transcripts: none | backup | orchestrator
#   database: preserve | reset | fixture | sandbox
#
# database:
#   location: dmg | appstore
#   start:
#     exists: true | false | either
#     min_projects: N
#     min_transcripts: N
#     min_fts_entries: N
#   mutations:
#     - "description of change"
#   end:
#     exists: true | false
#     projects: same | +N | N
#     transcripts: same | +N | N
#
# dependencies:
#   orchestrator_flags: [--isolate, --skip-appstore, etc.]
#   run_after: [QA-XXX, ...]
#   notes: "additional context"
```

## Field Definitions

### isolation.transcripts

| Value | Description |
|-------|-------------|
| `none` | Test doesn't touch transcript directories |
| `backup` | Test backs up ~/.claude and ~/.codex, restores on cleanup |
| `orchestrator` | Relies on orchestrator's --isolate flag for isolation |

### isolation.database

| Value | Description |
|-------|-------------|
| `preserve` | Uses existing database, doesn't reset |
| `reset` | Deletes database before test (clean install test) |
| `fixture` | Installs a fixture database (migration tests) |
| `sandbox` | Uses App Store sandbox location (inherently isolated) |

### database.location

| Value | Description |
|-------|-------------|
| `dmg` | ~/Library/Application Support/Contextify/contextify.db |
| `appstore` | ~/Library/Containers/sh.contextify.Contextify/Data/Library/Application Support/Contextify/contextify.db |

### database.start

Expected database state when test begins:

- `exists`: Whether database file must exist
- `min_projects`: Minimum project count required
- `min_transcripts`: Minimum transcript count required
- `min_fts_entries`: Minimum FTS5 index entries required

### database.mutations

List of database changes the test makes during execution.

### database.end

Expected database state after test completes (before cleanup):

- `exists`: Whether database should exist
- `projects`: `same` (unchanged), `+N` (added N), or exact count
- `transcripts`: `same`, `+N`, or exact count

### dependencies

- `orchestrator_flags`: Flags that should be passed to run-all-tests.sh
- `run_after`: Tests that must complete before this one (for data dependencies)
- `notes`: Human-readable context

## Test Categories

### Category A: Launch Tests (QA-01x)
Test app startup in various configurations. Mix of reset and preserve modes.

### Category B: Feature Tests (QA-02 through QA-08)
Test specific features. Generally preserve database, may add data.

### Category C: Discovery Tests (QA-03, QA-04)
Create new transcripts. Require transcript isolation to avoid production pollution.

### Category D: Infrastructure Tests (QA-09)
Test migrations. Use fixture databases.

### Category E: Search Tests (QA-10, QA-11)
Test search functionality. Require FTS5 data from discovery tests.

### Category F: CLI Query Tests (CLI-01 through CLI-03)
Read-only CLI tests for contextify-query and skill invocation. Require CLI tools and a populated database.
