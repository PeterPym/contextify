# Contextify E2E Test Suite

Automated end-to-end (E2E) test suite for validating Contextify user flows before releases.

## Overview

This test suite validates critical user flows through:
- Log analysis (OSLog capture)
- Database queries (SQLite)
- Filesystem verification
- UI automation (AppleScript/System Events)

## Quick Start

```bash
# Run all tests
./scripts/qa/run-all-tests.sh

# Run with options
./scripts/qa/run-all-tests.sh --skip-appstore    # Skip App Store build tests
./scripts/qa/run-all-tests.sh --skip-cli         # Skip tests requiring CLI tools
./scripts/qa/run-all-tests.sh --only QA-03       # Run only QA-03

# List available tests
./scripts/qa/run-all-tests.sh --list
```

## Prerequisites

### Required
- **macOS** with Xcode Command Line Tools
- **sqlite3** (built into macOS)
- **DMG build**: `.derived-dmg/Build/Products/Debug/Contextify.app`
  - Build with: `bash scripts/xc.sh --dist=dmg build`

### For App Store Tests (QA-01c/d/e)
- **App Store build**: `.derived-appstore/Build/Products/Debug/Contextify.app`
  - Build with: `bash scripts/xc.sh --dist=appstore Debug build`
- **Terminal Accessibility Permission** (one-time setup):
  - System Settings → Privacy & Security → Accessibility → Terminal ✓

### For CLI Tests (QA-03/04/05)
- **Codex CLI** installed and authenticated
- **Claude Code** installed and authenticated

## Test Suite

| Test | Description | Requirements |
|------|-------------|--------------|
| QA-01a | DMG Build - First Run | DMG build |
| QA-01b | DMG Build - Existing DB | DMG build, existing database |
| QA-01c | App Store - Grant Permissions | App Store build, Accessibility |
| QA-01d | App Store - Existing Bookmarks | App Store build |
| QA-01e | App Store - Skip Permissions | App Store build, Accessibility |
| QA-02 | Project Switching | Running app, 2+ projects |
| QA-03 | Codex Discovery | Running app, Codex CLI (or fixture mode) |
| QA-04 | Claude Discovery | Running app, Claude Code (or fixture mode) |
| QA-05 | Real-time Updates | Running app, Codex CLI |
| QA-06 | Watcher Recovery | Running app |
| QA-07 | Transcript Window | Running app |
| QA-08 | Projects Window | Running app |
| QA-09 | DB Migration & Integrity | DMG build, DB fixtures |
| QA-10 | Quick Search | DMG build, searchable content |
| QA-11 | Deep Search Window | DMG build |

## Test Output

Each run creates a timestamped log directory:

```
/tmp/qa-run-YYYYMMDD-HHMMSS/
├── SUMMARY.md              # Human-readable summary
├── QA-01a-launch-dmg-clean.sh.log
├── QA-01b-launch-dmg-existing.sh.log
├── ...
```

## Directory Structure

```
scripts/qa/
├── run-all-tests.sh        # Main test orchestrator
├── README.md               # This file
├── lib/
│   ├── common.sh           # Shared utilities
│   └── assertions.sh       # Test assertions
├── fixtures/
│   ├── transcripts/
│   │   ├── codex/          # Codex transcript fixtures
│   │   └── claude/         # Claude transcript fixtures
│   └── db/                 # Database fixtures for migration tests
└── tests/
    ├── QA-01a-launch-dmg-clean.sh
    ├── QA-01b-launch-dmg-existing.sh
    ├── QA-01c-launch-appstore-clean.sh
    ├── QA-01d-launch-appstore-existing.sh
    ├── QA-01e-launch-appstore-skip.sh
    ├── QA-02-project-switching.sh
    ├── QA-03-codex-discovery.sh
    ├── QA-04-claude-discovery.sh
    ├── QA-05-realtime-updates.sh
    ├── QA-06-watcher-recovery.sh
    ├── QA-07-transcript-window.sh
    ├── QA-08-projects-window.sh
    ├── QA-09-db-migration.sh
    ├── QA-10-quick-search.sh
    └── QA-11-deep-search.sh
```

## Running Individual Tests

```bash
# Run a single test directly
./scripts/qa/tests/QA-03-codex-discovery.sh

# Run with debug output
QA_DEBUG=1 ./scripts/qa/tests/QA-03-codex-discovery.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `QA_DEBUG` | 0 | Enable debug logging |
| `QA_CLEANUP` | 0 | Clean up test artifacts after run |
| `DB_PATH` | ~/Library/Application Support/Contextify/contextify.db | Database location |
| `DMG_APP_PATH` | .derived-dmg/Build/Products/Debug/Contextify.app | DMG build path |
| `APPSTORE_APP_PATH` | .derived-appstore/Build/Products/Debug/Contextify.app | App Store build path |
| `QA_FIXTURE_MODE` | 0 | Set to 1 to use fixtures instead of live CLIs |
| `QA_FIXTURE_DIR` | $REPO_ROOT/scripts/qa/fixtures | Fixture directory |
| `TEST_PROJECT` | /tmp/contextify-qa-test | Test project path (cwd written into fixtures) |

## Fixture Mode

Set `QA_FIXTURE_MODE=1` to run Codex/Claude tests using local transcript fixtures
instead of invoking live CLIs. This enables deterministic, fast testing without
network dependencies or CLI tool authentication.

### Usage

```bash
# Run with fixtures (no CLI binaries needed)
QA_FIXTURE_MODE=1 ./scripts/qa/run-all-tests.sh --skip-appstore

# Run in CI (fixtures + skip App Store tests)
QA_FIXTURE_MODE=1 TEST_PROJECT=/tmp/contextify-qa-test ./scripts/qa/run-all-tests.sh --skip-appstore
```

### Fixtures

```
scripts/qa/fixtures/
├── transcripts/
│   ├── codex/
│   │   ├── simple-session.jsonl    # Codex fixture with search term
│   │   └── README.md
│   └── claude/
│       ├── simple-session.jsonl    # Claude fixture with search term
│       └── README.md
└── db/
    ├── v16-contextify.db           # Oldest supported schema
    ├── v25-contextify.db           # Pre-FTS5 schema
    └── README.md
```

### Notes

- Fixture mode works with `--skip-cli`; CLI binaries are not required
- The `TEST_PROJECT` path is written into fixture transcripts via sed
- Claude fixtures use a simplified project hash (not Claude's actual algorithm)
- Fixtures include search terms (`QA_FIXTURE_SEARCH_TERM_*`) for search tests

### CI Integration

The GitHub Actions workflow runs the QA suite in fixture mode on every PR:

```yaml
- name: Run QA Suite (fixture mode)
  run: QA_FIXTURE_MODE=1 ./scripts/qa/run-all-tests.sh --skip-appstore
  env:
    TEST_PROJECT: /tmp/contextify-qa-test
```

### Cleanup After Local Runs

When running fixture mode locally, the test suite installs fixtures **alongside** your
real transcripts, not in place of them. The app may auto-select the fixture project
and remember that selection in UserDefaults.

**What fixture mode creates:**
- Transcript fixtures at `~/.claude/projects/-tmp-contextify-qa-test/`
- UserDefaults entry `dev.contextify.projectRoot` pointing to `/tmp/contextify-qa-test`
- UserDefaults entry `dev.contextify.projectRootBookmark` (security-scoped bookmark)

**Symptoms of "stuck" fixture state:**
- App shows empty timeline despite having real transcripts
- Project appears as `/tmp/contextify-qa-test` in the UI
- Real projects not visible in project list

**To restore normal operation:**
```bash
# Clear stuck project selection
defaults delete dev.contextify dev.contextify.projectRoot
defaults delete dev.contextify dev.contextify.projectRootBookmark

# Remove QA fixture transcripts
rm -rf ~/.claude/projects/-tmp-contextify-qa-test

# Relaunch app - it will auto-discover your real projects
```

**Note:** CI runs don't have this issue since they execute in isolated environments.
Local runs require manual cleanup if you want to return to your real transcript data.

## Maintaining E2E Tests

### When to Add New Tests

Add a new E2E test when:
- **New user flow** is introduced (new window, new feature, new interaction pattern)
- **Critical path changes** significantly (search, discovery, project switching)
- **Complex multi-step interaction** is added that unit tests can't cover

### When to Update Existing Tests

Update existing tests when:
- **UI flow changes** (keyboard shortcuts, button behavior, menu items)
- **Log patterns change** (test assertions use `[TAG]` patterns from OSLog)
- **Database schema changes** affect expected counts or queries
- **Timing changes** require adjusted wait times or patterns

### Test Contract Requirements

Every E2E test must have a `@test_contract` YAML header documenting:
- `isolation`: How transcripts/database are isolated
- `database`: Expected start state, mutations, end state
- `dependencies`: Required orchestrator flags and run order

This ensures tests are reproducible and don't interfere with each other.

For the full feature development workflow including when to plan tests, see:
`build/docs/guides/feature-development-workflow.md`

## Writing New Tests

1. Create new file in `tests/` following naming convention: `QA-XX-description.sh`
2. Source common libraries:
   ```bash
   source "$(dirname "$0")/../lib/common.sh"
   source "$(dirname "$0")/../lib/assertions.sh"
   ```
3. Set test metadata:
   ```bash
   TEST_ID="QA-XX"
   TEST_NAME="Description"
   ```
4. Implement standard functions:
   - `check_prerequisites`
   - `setup_test`
   - `run_test_steps`
   - `validate_results`
5. Add to `ALL_TESTS` array in `run-all-tests.sh`

## Assertion Reference

### Assertion Behavior Under `set -e`

Tests run with `set -euo pipefail`. This affects how assertions behave:

**Hard assertions** (`assert_*`) return non-zero on failure. Under `set -e`, a bare hard assertion will **abort the test immediately** on failure. This is the intended behavior for critical checks where continuing would be meaningless.

**Soft assertions** (`soft_assert_*`) always return 0 and **do not modify `TEST_FAILED`**. They are informational only - use them for "nice to know" checks (like "LLM processing detected") where failure is worth logging but shouldn't fail the test.

**Patterns:**
```bash
# Hard assertion - test aborts immediately if app not running
assert_app_running "Contextify"

# Soft assertion - informational, doesn't affect pass/fail
soft_assert_log_contains "LLM" "LLM processing detected"

# Hard assertion in conditional - test continues on failure
if ! assert_log_contains "EXPECTED"; then
  log_warn "Pattern not found, trying fallback..."
fi
```

**Note:** If you want to accumulate hard assertion failures without aborting, wrap them in `if` statements. A bare `assert_*` will exit the test on failure under `set -e`.

### File Assertions
- `assert_file_exists FILE [DESC]`
- `assert_file_not_exists FILE [DESC]`
- `assert_directory_exists DIR [DESC]`

### Process Assertions
- `assert_app_running [APP] [DESC]`
- `assert_app_not_running [APP] [DESC]`
- `assert_command_exists CMD [DESC]`

### Log Assertions
- `assert_log_contains PATTERN [DESC]`
- `assert_log_not_contains PATTERN [DESC]`
- `assert_log_count PATTERN EXPECTED [DESC]`
- `assert_log_count_min PATTERN MIN [DESC]`
- `assert_log_count_max PATTERN MAX [DESC]`

### Database Assertions
- `assert_db_exists [DESC]`
- `assert_db_count QUERY EXPECTED [DESC]`
- `assert_db_count_min QUERY MIN [DESC]`
- `assert_db_row_exists QUERY [DESC]`

### Soft Assertions (warn but don't fail)
- `soft_assert_log_contains PATTERN [DESC]`
- `soft_assert_db_count_min QUERY MIN [DESC]`

## Troubleshooting

### "Permission denied" when clicking buttons
Ensure Terminal has Accessibility permission:
System Settings → Privacy & Security → Accessibility → Terminal ✓

### Tests timing out
- Increase timeout values in test scripts
- Check if app is actually starting/running
- Verify build paths are correct

### "App not found" errors
Build the required app variant:
```bash
# DMG build
bash scripts/xc.sh --dist=dmg build

# App Store build
bash scripts/xc.sh --dist=appstore Debug build
```

### CLI tests skipped
Install and authenticate the required CLI tools:
- Codex CLI: https://openai.com/codex
- Claude Code: https://claude.ai/code

## Nightly Scheduled Runs

The E2E suite can be scheduled to run automatically at 4am daily using macOS launchd.

See `scripts/qa/schedule/README.md` for setup instructions.

**Quick summary:**
- Logs persist in `scripts/qa/schedule/logs/` (gitignored)
- Pass/fail history in `scripts/qa/schedule/history.log`
- Desktop marker file created on failure

## Methodology

For detailed methodology and design decisions, see:
`build/notes/todo-support/P2-AUTOMATED-QA-methodology.md`
