# Contextify QA Test Suite

Automated QA suite for validating Contextify functionality before releases.

## Overview

This test suite validates 6 critical user flows through:
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
| QA-03 | Codex Discovery | Running app, Codex CLI |
| QA-04 | Claude Discovery | Running app, Claude Code |
| QA-05 | Real-time Updates | Running app, Codex CLI |
| QA-06 | Watcher Recovery | Running app |
| QA-07 | Transcript Window | Running app |
| QA-08 | Projects Window | Running app |

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
    └── QA-08-projects-window.sh
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

## Methodology

For detailed methodology and design decisions, see:
`build/notes/todo-support/P2-AUTOMATED-QA-methodology.md`
