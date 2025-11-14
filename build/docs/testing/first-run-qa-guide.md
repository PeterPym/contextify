# First-Run QA Testing Guide

This guide describes the CLI-only QA toolkit for testing Contextify's first-run onboarding flow across both distribution models (DMG and App Store).

## ⚠️ IMPORTANT: seed-demo Currently Disabled

**The `seed-demo` command is temporarily disabled** due to interference with active Claude Code usage:
- It replaces real `~/.claude/projects` and `~/.codex/sessions` with symlinks to `/tmp`
- Active Claude Code sessions write to temp storage, causing data loss on reboot
- No automatic restoration mechanism exists

**Re-enable for final QA testing only.** Until then, use your real transcripts for testing.

## Overview

The QA toolkit provides command-line controls to:

- **Reset app state** (database, preferences, security-scoped bookmarks)
- **Reset macOS privacy permissions** (TCC entries)
- ~~**Seed deterministic demo fixtures** for reproducible testing~~ (DISABLED - see warning above)
- **Select distribution mode** (DMG unsandboxed vs App Store sandboxed)
- **Stream app logs** in real-time during onboarding

**No in-app developer code is required** - all operations are external CLI commands.

## Quick Reference

```bash
# DMG first-run (unsandboxed, fast path)
./scripts/xc.sh --dist=dmg Debug cleanrun

# App Store first-run (sandboxed, permissions required)
./scripts/xc.sh --dist=appstore Debug cleanrun

# Reset only permissions (keep DB/state)
./scripts/xc.sh reset-perms

# Reset only state (keep TCC permissions)
./scripts/xc.sh reset-state

# Reset everything (permissions + state)
./scripts/xc.sh reset-all

# Stream logs in real-time
./scripts/xc.sh logs
```

## Distribution Modes

### DMG (Unsandboxed) - Default

```bash
./scripts/xc.sh --dist=dmg Debug cleanrun
```

**Characteristics:**
- No sandbox (`com.apple.security.app-sandbox = false`)
- Can read most of `$HOME` by default
- TCC still gates specific locations:
  - Desktop (`SystemPolicyDesktopFolder`)
  - Documents (`SystemPolicyDocumentsFolder`)
  - Downloads (`SystemPolicyDownloadsFolder`)
  - Network volumes (`SystemPolicyNetworkVolumes`)
  - Removable volumes (`SystemPolicyRemovableVolumes`)

**Expected behavior:**
- Fast path: No permission prompts if transcripts are in `~/.claude/` or `~/.codex/`
- Gated path: Permission prompt if transcripts are in Desktop/Documents/Downloads
- Indexing should start immediately after discovery

### App Store (Sandboxed)

```bash
./scripts/xc.sh --dist=appstore Debug cleanrun
```

**Characteristics:**
- Sandbox enabled (`com.apple.security.app-sandbox = true`)
- Cannot access arbitrary files
- Access granted via:
  - User-selected directories from `NSOpenPanel`
  - Security-scoped bookmarks (SSBs) persisted by app

**Expected behavior:**
- **Always** shows Permissions step until at least one folder is chosen
- Bookmarks persist across relaunch without additional prompts
- Requires user interaction to authorize transcript locations

## Testing Workflows

### 1. DMG Fast Path (No Prompts)

**Setup:**
```bash
./scripts/xc.sh seed-demo  # Creates fixtures in ~/.claude/ and ~/.codex/
./scripts/xc.sh --dist=dmg Debug cleanrun
```

**Expected flow:**
1. **Discovery** phase starts immediately (no permission prompts)
2. **Indexing** begins within ~10 seconds
3. Progress indicators show transcript processing
4. Timeline populates with demo entries
5. Welcome modal auto-dismisses when indexing completes

**Validation:**
- No TCC permission dialogs
- Discovery → Indexing transition < 10s
- All demo transcripts appear in timeline

### 2. DMG with Gated Location

**Setup:**
```bash
# Move fixtures to gated location
mkdir -p ~/Documents/test-transcripts/claude/projects
mkdir -p ~/Documents/test-transcripts/codex/sessions
cp Fixtures/transcripts/claude/projects/*.jsonl ~/Documents/test-transcripts/claude/projects/
cp Fixtures/transcripts/codex/sessions/*.jsonl ~/Documents/test-transcripts/codex/sessions/

# Update symlinks
rm ~/.claude/projects ~/.codex/sessions
ln -s ~/Documents/test-transcripts/claude/projects ~/.claude/projects
ln -s ~/Documents/test-transcripts/codex/sessions ~/.codex/sessions

./scripts/xc.sh --dist=dmg Debug cleanrun
```

**Expected flow:**
1. App attempts to discover transcripts
2. macOS shows TCC permission dialog for Documents folder
3. After granting permission, discovery proceeds
4. Indexing begins

**Validation:**
- TCC dialog appears for Documents folder
- Granting permission allows discovery to proceed
- Denying permission shows "No projects found" state

### 3. App Store First Run (Permissions Required)

**Setup:**
```bash
./scripts/xc.sh seed-demo
./scripts/xc.sh --dist=appstore Debug cleanrun
```

**Expected flow:**
1. Welcome modal shows **Permissions** step
2. "Choose Folder" button allows selecting transcript directories
3. After selecting at least one folder, "Continue" becomes enabled
4. Discovery begins after clicking Continue
5. Indexing follows

**Validation:**
- Permissions step always appears on first run
- Cannot skip without selecting at least one folder
- Bookmarks persist across app restarts (no re-prompt on second launch)

### 4. App Store with Stale Bookmarks

**Setup:**
```bash
# First run with fixtures
./scripts/xc.sh seed-demo
./scripts/xc.sh --dist=appstore Debug cleanrun

# Let indexing complete, quit app

# Move the fixtures to a new location
mv /var/folders/.../contextify-demo /tmp/contextify-demo-moved

# Relaunch
./scripts/xc.sh --dist=appstore Debug build
```

**Expected flow:**
1. App detects stale bookmarks (cannot resolve paths)
2. Shows Permissions step again with warning about moved/deleted sources
3. Allows re-selecting folders

**Validation:**
- App gracefully handles moved directories
- Clear error messages about unresolvable paths
- Can re-authorize without full reset

### 5. Empty State (No Projects Found)

**Setup:**
```bash
# Remove all transcript symlinks
rm -rf ~/.claude/projects ~/.codex/sessions

./scripts/xc.sh --dist=dmg Debug cleanrun
```

**Expected flow:**
1. Discovery phase completes with zero projects
2. Welcome modal shows "No projects found" state
3. Provides guidance on setting up transcripts

**Validation:**
- Clear messaging about zero projects
- No errors or crashes
- Provides actionable next steps

### 6. Viewport-Aware Queueing Verification

**Setup:**
```bash
./scripts/logging/monitor-viewport-queueing.sh
```

**Expected flow:**
1. Script waits 3 seconds, then captures logs for 5 seconds
2. While logging, switch to a different project in Contextify
3. Conversation load defers queueing (`SUMM-LOAD-DEFER`)
4. Viewport tracking initializes (`SUMM-VIEWPORT-INIT`)
5. Visible entries queue once viewport settles (no 12-entry fallback)

**Validation:**
- Script exits 0 (PASS)
- Output shows viewport counts instead of "Queueing 12" fallback
- Timing metric `< 100ms` between load completion and viewport report
- PASS indicates viewport-aware queueing is healthy for project switches

## CLI Command Reference

### Actions

| Command | Description | Use Case |
|---------|-------------|----------|
| `cleanrun` | Clean DB + reset state + reset TCC + build + launch | True first-run testing |
| `reset-perms` | Reset TCC permissions only (keeps DB/state) | Test permission denial/grant flows |
| `reset-state` | Reset app state only (keeps TCC) | Test onboarding with existing permissions |
| `reset-all` | Reset both permissions and state | Full reset without rebuilding |
| `seed-demo` | Seed demo fixtures and symlink defaults | Setup reproducible test data |
| `logs` | Stream app logs in real-time | Monitor onboarding state transitions |

### Options

| Option | Values | Description |
|--------|--------|-------------|
| `--dist` | `dmg`, `appstore` | Select distribution mode (default: `dmg`) |
| `--dev` | (flag) | Enable developer mode (test buttons) |
| `Debug\|Release` | Configuration | Build configuration (default: `Debug`) |

### Examples

```bash
# Full first-run test cycle
./scripts/xc.sh seed-demo                    # Once
./scripts/xc.sh --dist=dmg Debug cleanrun    # Test DMG
./scripts/xc.sh --dist=appstore Debug cleanrun  # Test App Store

# Reset only permissions, keep database
./scripts/xc.sh reset-perms
./scripts/xc.sh build  # Relaunch

# Reset only database/prefs, keep TCC grants
./scripts/xc.sh reset-state
./scripts/xc.sh build  # Relaunch

# Stream logs during onboarding
# (in one terminal)
./scripts/xc.sh logs
# (in another terminal)
./scripts/xc.sh cleanrun
```

## Demo Fixtures

The `seed-demo` command creates deterministic test data:

**Location:** `Fixtures/transcripts/`

**Structure:**
```
Fixtures/transcripts/
├── claude/
│   └── projects/
│       └── demo-project-001.jsonl    # Claude Code format sample
└── codex/
    └── sessions/
        └── demo-session-001.jsonl     # Codex CLI format sample
```

**Usage:**
```bash
./scripts/xc.sh seed-demo
```

**What it does:**
1. Creates temp directory: `/tmp/contextify-demo`
2. Copies fixtures to temp directory
3. Backs up existing `~/.claude/projects` and `~/.codex/sessions`
4. Symlinks `~/.claude/projects` → temp directory
5. Symlinks `~/.codex/sessions` → temp directory

**Benefits:**
- Reproducible test data across QA runs
- Fast (<1s) to reset and re-seed
- Isolated from real user data
- Known transcript content for validation

## Log Streaming

Monitor onboarding flow in real-time:

```bash
./scripts/xc.sh logs
```

**What you'll see:**
- Onboarding state transitions (Permissions → Discovery → Indexing)
- Transcript discovery progress
- LLM processing activity
- Error conditions
- Performance metrics

**Key log patterns to watch for:**
- `"Starting discovery..."` - Discovery phase begins
- `"Found N transcripts"` - Discovery results
- `"Starting indexing..."` - Indexing phase begins
- `"Indexed N/M entries"` - Indexing progress
- `"Onboarding complete"` - Auto-dismiss trigger

## Acceptance Criteria

### DMG Distribution

- ✅ **Cleanrun** launches directly into Discovery/Indexing (no permission prompt)
- ✅ Fixtures in `~/.claude/` or `~/.codex/` are immediately accessible
- ✅ Fixtures in gated locations (Desktop/Documents) prompt for TCC approval
- ✅ `reset-perms` removes TCC grants; next access prompts appropriately

### App Store Distribution

- ✅ **Cleanrun** always shows Permissions step until folder selected
- ✅ Bookmarks persist across relaunch without re-prompt
- ✅ Moved/deleted sources trigger re-authorization flow
- ✅ `reset-state` removes bookmarks; next launch requires re-selection

### Demo Fixtures

- ✅ `seed-demo` creates consistent data set
- ✅ Symlinks enable sub-10-second discovery/indexing runs
- ✅ Fixtures include both Claude Code and Codex formats
- ✅ Known content allows validation of timeline display

### Logging

- ✅ `logs` shows onboarding state transitions
- ✅ Progress messages appear at expected intervals
- ✅ Errors are clearly logged with context
- ✅ No extraneous debug noise in info-level logs

## Troubleshooting

### TCC Reset Not Working

**Symptom:** Permissions persist after `reset-perms`

**Solution:**
```bash
# Quit app completely first
pkill -9 Contextify

# Manually reset TCC for bundle ID
tccutil reset All dev.contextify.Contextify

# Verify
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT * FROM access WHERE client='dev.contextify.Contextify';"
# Should return no rows
```

### Fixtures Not Found

**Symptom:** `seed-demo` reports 0 transcripts

**Solution:**
```bash
# Check fixtures exist
ls -la Fixtures/transcripts/claude/projects/
ls -la Fixtures/transcripts/codex/sessions/

# Verify symlinks
ls -la ~/.claude/projects
ls -la ~/.codex/sessions

# Re-seed
./scripts/xc.sh seed-demo
```

### Sandbox Entitlements Not Applied

**Symptom:** App Store build behaves like DMG build

**Solution:**
```bash
# Verify entitlements are embedded
codesign -d --entitlements - .derived/Build/Products/Debug/Contextify.app

# Should show:
# <key>com.apple.security.app-sandbox</key>
# <true/>

# If missing, ensure Xcode project references correct entitlements file
```

### Logs Not Streaming

**Symptom:** `./scripts/xc.sh logs` shows no output

**Solution:**
```bash
# Check if app is running
pgrep -x Contextify

# Verify process name
ps aux | grep Contextify

# Manual log stream (if process name differs)
log stream --style compact --predicate 'process == "Contextify"' --level debug
```

## Integration with Existing Workflows

### Pre-commit Testing

Before submitting PR:

```bash
# Test both distributions
./scripts/xc.sh seed-demo
./scripts/xc.sh --dist=dmg Debug cleanrun
# Verify onboarding completes
./scripts/xc.sh --dist=appstore Debug cleanrun
# Verify permissions step appears
```

### CI/CD Integration

The toolkit is designed for local QA. CI builds use:

```bash
CTX_NO_RUN=1 ./scripts/xc.sh --dist=dmg Debug build  # Build-only, no launch
```

For full CI onboarding tests, consider UI testing with XCUITest (out of scope for this toolkit).

## References

- **Fixtures:** `Fixtures/transcripts/README.md`
- **Script:** `scripts/xc.sh`
- **Entitlements:**
  - DMG: `Contextify/Contextify.entitlements`
  - App Store: `Contextify/Contextify-AppStore.entitlements`
- **Welcome Modal:** `Contextify/Contextify/WelcomeModalView.swift`
- **Transcript Formats:** `build/docs/archive/completed-work/technical-briefing-local-history-claude-code-codex.md`

## Future Enhancements

- [ ] Automated UI tests using XCUITest
- [ ] Performance benchmarks for indexing large datasets
- [ ] Network volume and removable drive test scenarios
- [ ] Multi-machine bookmark sync testing (for App Store builds)
