---
todo_id: P3-PYTHON-CLI-REFACTOR
title: Refactor release workflow to Python CLI with thin Bash wrappers
type: reference
date: 2025-11-28
status: active
description: Architecture recommendation for consolidating embedded Python into a proper CLI tool
---

# Release Workflow Python CLI Refactor

## Problem Statement

The release workflow scripts (`scripts/release/*.sh`) have grown beyond "a couple of shell scripts" into a small application with:

- A state machine with multiple files (`manifest.json`, `release.json`)
- Non-trivial transitions (pending -> built -> submitted -> approved/rejected/skipped)
- Guard logic, consistency checks, reset semantics
- Embedded Python everywhere for JSON reads/writes

The core operation is: **Read JSON -> apply state transition -> write JSON -> print guidance**

This is exactly what Python excels at and what Bash is awkward for. Structurally, we're already "Python-based," just without the benefits of having it be a clear, testable Python program.

## Recommended Architecture

### Python CLI as Single Source of Truth

One entrypoint: `tools/release_cli.py` (or package `contextify_release/cli.py`)

**Subcommands:**
- `init` - Initialize a new release
- `build` - Record build completion
- `status` - Show release status
- `mark-submitted` - Record App Store submission
- `mark-rejected` - Record App Store rejection
- `mark-shipped` - Record shipping (DMG or App Store)
- `check-consistency` - Validate state files
- `normalize-statuses` - Migrate legacy status values

All JSON I/O, guards, and state transitions live in Python.

### Thin Bash Wrappers (Optional)

Keep `scripts/release/*.sh` as 5-10 line shims that call the Python CLI:

```bash
#!/bin/bash
# scripts/release/mark-shipped.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
exec python3 "$ROOT_DIR/tools/release_cli.py" mark-shipped "$@"
```

This preserves existing muscle memory (`./scripts/release/mark-shipped.sh 1.0.0 --dmg`) while making logic testable and centralized.

## Benefits

1. **One language for all state/logic** - No more shell/Python hybrid
2. **Real unit tests with pytest** - Test state machine transitions
3. **Cleaner error handling** - Proper try/except, atomic writes
4. **Atomic file writes** - Write to temp file then `os.replace()`
5. **Type hints** - Better IDE support and self-documentation

## Migration Strategy

**Don't rewrite everything at once.** Incremental approach:

### Phase 1: Create Python Core
Implement minimal commands needed for next release cycle:
- `status`, `init`, `build`, `mark-submitted`, `mark-shipped`, `mark-rejected`, `check-consistency`

### Phase 2: Port Logic Incrementally
Move the bodies of `get_channel_status`, `check_can_*`, and embedded Python `EOF` blocks into Python functions. Have Bash scripts call into those functions via the CLI.

### Phase 3: Stabilize and Test
Once Python CLI is stable and tested:
- Either keep Bash wrappers forever (they're tiny)
- Or deprecate them and call `python3 tools/release_cli.py` directly

## Example Usage

```bash
python3 tools/release_cli.py init 1.1.0
python3 tools/release_cli.py build 1.1.0 --skip-appstore
python3 tools/release_cli.py mark-submitted 1.1.0 --build 9
python3 tools/release_cli.py mark-rejected 1.1.0 --guideline 2.1 --reason "Needs demo video"
python3 tools/release_cli.py status 1.1.0
python3 tools/release_cli.py check-consistency
```

## Why Not Pure Bash?

For stateful release workflows:
- You care about not corrupting JSON
- You care about keeping two files in sync
- You already depend on `python3`

Using pure Bash + `grep`/`sed` on JSON is fragile. Using `jq` is better but you still end up writing a mini DSL of jq invocations spread across many scripts.

**Summary:**
- Bash-only -> **No** (too fragile for this complexity)
- Bash+Python hybrid (current) -> OK but messy
- Python core + thin Bash wrappers -> **Best** balance for solo dev

## Related

- Current guard implementation: `scripts/release/lib/guards.sh`
- State files: `releases/manifest.json`, `releases/v*/release.json`
- Status vocabulary: `releases/STATUS-VALUES.md`
