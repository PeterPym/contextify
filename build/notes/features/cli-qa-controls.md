# CLI QA Controls for First-Run Testing

**Status:** ✅ Implemented
**Branch:** `feature/cli-qa-controls-welcome-flow`
**Date:** 2025-11-11

## Summary

Implemented a comprehensive CLI-only toolkit for QA testing of the first-run welcome/onboarding flow. Supports both DMG (unsandboxed) and App Store (sandboxed) distribution testing without requiring any in-app developer code.

## Features Implemented

### 1. Distribution Mode Selection

```bash
# DMG build (unsandboxed, default)
./scripts/xc.sh --dist=dmg build

# App Store build (sandboxed)
./scripts/xc.sh --dist=appstore build
```

- **Entitlements:**
  - DMG: `Contextify/Contextify.entitlements` (sandbox = false)
  - App Store: `Contextify/Contextify-AppStore.entitlements` (sandbox = true)
- Automatically selects correct entitlements during build
- Both modes build from same codebase (no code duplication)

### 2. State Management Commands

| Command | Description |
|---------|-------------|
| `cleanrun` | Clean DB + reset state + reset TCC + build + launch |
| `reset-perms` | Reset macOS privacy (TCC) permissions only |
| `reset-state` | Reset app state (DB, prefs, bookmarks) only |
| `reset-all` | Reset both permissions and state |

**Examples:**
```bash
# True first-run (resets everything)
./scripts/xc.sh --dist=dmg Debug cleanrun

# Reset just permissions (to test denial/grant flows)
./scripts/xc.sh reset-perms
./scripts/xc.sh build  # Relaunch

# Reset just state (to test with existing TCC grants)
./scripts/xc.sh reset-state
./scripts/xc.sh build  # Relaunch
```

### 3. Demo Fixture Seeding

```bash
# Seed deterministic demo data
./scripts/xc.sh seed-demo
```

**What it does:**
- Creates temp directory with sample transcripts
- Symlinks `~/.claude/projects` and `~/.codex/sessions`
- Backs up existing data
- Provides reproducible test environment

**Fixtures included:**
- `Fixtures/transcripts/claude/projects/demo-project-001.jsonl` (Claude Code format)
- `Fixtures/transcripts/codex/sessions/demo-session-001.jsonl` (Codex CLI format)

### 4. Real-Time Log Streaming

```bash
# Stream app logs during onboarding
./scripts/xc.sh logs
```

Shows:
- Onboarding state transitions
- Transcript discovery progress
- LLM processing activity
- Error conditions
- Performance metrics

## Implementation Details

### Files Added

1. **Entitlements:**
   - `Contextify/Contextify-AppStore.entitlements` (sandboxed variant)

2. **Fixtures:**
   - `Fixtures/transcripts/claude/projects/demo-project-001.jsonl`
   - `Fixtures/transcripts/codex/sessions/demo-session-001.jsonl`
   - `Fixtures/transcripts/README.md`

3. **Documentation:**
   - `build/docs/testing/first-run-qa-guide.md` (comprehensive QA guide)
   - `build/notes/features/cli-qa-controls.md` (this file)

### Files Modified

1. **Build Script:**
   - `scripts/xc.sh` - Added ~200 lines for:
     - Distribution mode selection
     - Helper functions (bundle_id_for_app, reset_state_for_bid, reset_tcc_for_bid)
     - New actions (cleanrun, reset-perms, reset-state, reset-all, seed-demo, logs)
     - Distribution-aware build function

2. **Project Documentation:**
   - `CLAUDE.md` - Added QA toolkit quick reference section

## Testing Workflows

### DMG Fast Path
```bash
./scripts/xc.sh seed-demo
./scripts/xc.sh --dist=dmg Debug cleanrun
# Expected: No permission prompts, direct to Discovery → Indexing
```

### DMG with Gated Location
```bash
# Move fixtures to ~/Documents/test-transcripts
./scripts/xc.sh --dist=dmg Debug cleanrun
# Expected: TCC permission dialog for Documents folder
```

### App Store First Run
```bash
./scripts/xc.sh seed-demo
./scripts/xc.sh --dist=appstore Debug cleanrun
# Expected: Permissions step appears, requires folder selection
```

### Empty State
```bash
rm -rf ~/.claude/projects ~/.codex/sessions
./scripts/xc.sh --dist=dmg Debug cleanrun
# Expected: "No projects found" state
```

## Technical Notes

### TCC Services Covered
- `SystemPolicyDesktopFolder` (Desktop)
- `SystemPolicyDocumentsFolder` (Documents)
- `SystemPolicyDownloadsFolder` (Downloads)
- `SystemPolicyNetworkVolumes` (Network drives)
- `SystemPolicyRemovableVolumes` (External drives)

### Bundle ID Handling
- Extracts bundle ID dynamically from built app
- Supports both standard and container-based locations
- Works with sandboxed and unsandboxed builds

### State Locations Cleared
- Application Support: `~/Library/Application Support/Contextify/`
- Caches: `~/Library/Caches/[bundle-id]/`
- Preferences: `~/Library/Preferences/[bundle-id].plist`
- Container (if sandboxed): `~/Library/Containers/[bundle-id]/`

### Fixture Management
- Temp directory: `$TMPDIR/contextify-demo`
- Automatic backup of existing data (timestamp-based)
- Symlinks enable fast reset/re-seed cycles
- Known content for validation of timeline display

## Acceptance Criteria

✅ **DMG Distribution**
- Cleanrun launches directly into Discovery/Indexing (no prompt)
- Fixtures in `~/.claude/` accessible without TCC
- Fixtures in gated locations prompt for TCC
- `reset-perms` removes TCC grants

✅ **App Store Distribution**
- Cleanrun always shows Permissions step
- Bookmarks persist across relaunch
- Moved sources trigger re-authorization
- `reset-state` removes bookmarks

✅ **Demo Fixtures**
- `seed-demo` creates consistent data
- Symlinks enable sub-10s runs
- Both Claude Code and Codex formats included

✅ **Logging**
- `logs` shows state transitions
- Progress messages at expected intervals
- Clear error logging

## Future Enhancements

- [ ] Automated UI tests using XCUITest
- [ ] Performance benchmarks for large datasets
- [ ] Network volume and removable drive scenarios
- [ ] Multi-machine bookmark sync testing

## References

- **Complete Guide:** `build/docs/testing/first-run-qa-guide.md`
- **Script:** `scripts/xc.sh`
- **Fixtures:** `Fixtures/transcripts/README.md`
- **Entitlements:**
  - DMG: `Contextify/Contextify.entitlements`
  - App Store: `Contextify/Contextify-AppStore.entitlements`
