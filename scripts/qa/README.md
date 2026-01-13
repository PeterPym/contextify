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

# Run CLI query tests only
./scripts/qa/run-cli-tests.sh

# Run with options
./scripts/qa/run-all-tests.sh --skip-appstore    # Skip App Store build tests
./scripts/qa/run-all-tests.sh --skip-cli         # Skip tests requiring CLI tools
./scripts/qa/run-all-tests.sh --only QA-03       # Run only QA-03

# List available tests
./scripts/qa/run-all-tests.sh --list
```

## Utility Scripts

### Clean Install Reset

Reset all Contextify and CLI state for fresh install testing:

```bash
./scripts/qa/reset-for-clean-install.sh
```

This script:
- Quits Claude Code
- Uninstalls Homebrew contextify-query (if present)
- Clears Contextify app state (DB, prefs, CLI, bookmarks)
- Clears Claude Code plugin cache
- Clears user skills (total-recall and legacy locations)
- Verifies clean state

Use this before testing DMG installation, CLI installation, or skill activation.

---

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

### For CLI Query Tests (CLI-01/02/03)
- **contextify-query** installed and authenticated
- **jq** installed
- **Claude Code** installed and authenticated (CLI-03 only)

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
| CLI-01 | Query Baseline | contextify-query, jq |
| CLI-02 | Query Issues (red) | contextify-query, jq |
| CLI-03 | Skill Invocation | contextify-query, jq, Claude Code |
| CLI-04 | Worktree Query | contextify-query, jq, git |
| **Lite Mode** | macOS 15 VM testing | See `build/docs/testing/lite-mode-qa-checklist.md` |
| QA-13 | CLI Install/Repair/Uninstall (DMG) | DMG build, Accessibility |
| QA-15 | contextify-query bundle integrity | DMG build (App Store optional) |
| QA-16 | Agent Decoration | DMG build |
| QA-17 | Status Bar Permissions | DMG build |

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
├── run-all-tests.sh            # Main test orchestrator
├── run-cli-tests.sh            # CLI query test runner
├── reset-for-clean-install.sh  # Reset state for clean install testing
├── README.md                   # This file
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
    ├── CLI-01-query-baseline.sh
    ├── CLI-02-query-issues.sh
    ├── CLI-03-skill-invocation.sh
    └── CLI-04-worktree-query.sh
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

### QA-only UserDefaults overrides

Some E2E tests use narrowly-scoped UserDefaults overrides to avoid brittle UI traversal and privileged filesystem writes:

- `dev.contextify Contextify.QueryCLI.DMGInstallDirOverride` → forces DMG CLI shim install into a deterministic directory (e.g. `/tmp/contextify-qa-bin`) for unattended tests.
- `dev.contextify Contextify.Settings.SelectedTabOverride` → forces Settings to open on a specific tab (e.g. `cli`) for unattended tests.

### Troubleshooting

- Prefer `/usr/bin/log` instead of `log` in scripts/notes (some shells define `log` as a builtin).
- If a PATH shim runs the “wrong” installed app on a dev machine with multiple builds, prefer forcing the target bundle with `CONTEXTIFY_QUERY_APP_PATH=/path/to/Contextify.app` for diagnosis.

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

---

## macOS 15 (Lite Mode) Testing

The automated QA suite runs on macOS 26 only. For macOS 15 validation, use manual testing:

### When to Run Lite Mode Tests

- Before any release that touches LLM features
- After changes to `LLMAvailability.swift` or availability detection
- When updating `#available(macOS 26, *)` guarded code

### Testing Resources

| Resource | Location | Purpose |
|----------|----------|---------|
| **QA Checklist** | `build/docs/testing/lite-mode-qa-checklist.md` | 24-point manual validation |
| **VM Setup** | `build/docs/testing/macos-vm-setup.md` | UTM VM configuration guide |
| **Bootstrap Script** | `scripts/qa/vm-bootstrap.sh` | Seed test transcripts in VM |

### Quick Validation (macOS 26)

For development iteration without a VM:
```bash
# Simulate Lite Mode on macOS 26
./Contextify.app/Contents/MacOS/Contextify -simulate-legacy-macos
```

This tests Lite Mode code paths but is not a substitute for full VM testing before releases.

---

## Linux QA (Docker)

Local Linux testing validates that the CLI tools build and function correctly on Linux, without needing to push to CI.

### Prerequisites

- **Docker** installed and running (via Colima on macOS: `brew install colima && colima start`)
- Internet connection (downloads Swift toolchain image and SQLite source)

### Quick Start

```bash
# Basic build - validates compilation on Linux
bash scripts/docker-linux-build.sh

# Build + E2E test - validates binary works and can ingest transcripts
bash scripts/docker-linux-build.sh --e2e

# Build + install test - validates tarball extraction, PATH install, skill installation
bash scripts/docker-linux-build.sh --install-test
```

### What Each Test Validates

| Test | Command | Validates |
|------|---------|-----------|
| **Basic build** | `docker-linux-build.sh` | Swift 6 compiles on Linux, SQLite with ENABLE_SNAPSHOT links correctly |
| **E2E test** | `docker-linux-build.sh --e2e` | Binary executes, parses Claude Code transcripts, writes to SQLite database |
| **Install test** | `docker-linux-build.sh --install-test` | Tarball extracts cleanly, `install.sh` works, skill manifest validates |

### Technical Details

The Docker build:
1. Uses `swift:6.0-noble` (Ubuntu 24.04) image
2. Builds SQLite from source with `SQLITE_ENABLE_SNAPSHOT` (required by GRDB)
3. Compiles to `.build-linux/` (separate from macOS `.build/`)
4. Runs entirely containerized - no host system pollution

### When to Run

- Before merging Linux-related changes
- After modifying `Package.swift` dependencies
- When updating install scripts or skill manifests
- As a quick sanity check before triggering GitHub Actions CI

### Relationship to CI

This is a **local** pre-flight check. The GitHub Actions workflow (`.github/workflows/linux-release.yml`) runs the same validation on every push/PR. Use local Docker testing to catch issues before pushing.

For remote CI documentation, see `build/docs/guides/linux-ci-builds.md`.
