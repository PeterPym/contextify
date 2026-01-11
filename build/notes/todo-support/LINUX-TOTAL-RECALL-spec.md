---
todo_id: LINUX-TOTAL-RECALL
title: CLI Installation Health Check - Technical Specification
type: spec
date: 2026-01-10
status: active
description: Unified approach to verifying CLI tool and skill installation across platforms
---

# CLI Installation Health Check - Technical Specification

## Executive Summary

During validation of Codex skill support, we discovered that Contextify lacks a unified method for verifying that all CLI components are properly installed. The app and CLI have divergent, incomplete health checks, leading to situations where the UI shows "Enabled" but the actual functionality is broken.

This specification proposes a unified `contextify-query doctor` command that provides comprehensive installation health checking, usable by both the CLI (for user debugging) and the app (for accurate UI state).

---

## Problem Statement

### Gap Discovered

While testing the Settings > CLI tab Enable/Disable toggle, we found:

1. **App state detection is incomplete**: `CLICoordinator.computeState()` checks only:
   - Shim exists at known paths
   - Plugin manifest entry exists

2. **Skill files are not checked**: The app shows "Enabled" even if:
   - `~/.claude/skills/total-recall/SKILL.md` is missing
   - `~/.codex/skills/total-recall/SKILL.md` is missing
   - Plugin cache directory is missing
   - Agent file is missing

3. **CLI status command is database-only**: `contextify-query status` shows:
   - Database path and schema version
   - Project/transcript/entry counts
   - Does NOT check installation health

4. **No repair mechanism**: If installation is partial, user has no way to detect or fix it.

### Real-World Failure Scenarios

| Shim | Manifest | Plugin Cache | Claude Skill | Codex Skill | App Shows | Actual State |
|------|----------|--------------|--------------|-------------|-----------|--------------|
| ✓ | ✓ | ✓ | ✗ | ✗ | Enabled | **Broken** - /total-recall won't work |
| ✓ | ✓ | ✓ | ✓ | ✗ | Enabled | **Partial** - Claude works, Codex doesn't |
| ✓ | ✗ | ✗ | ✓ | ✓ | Disabled | **Works** - skills function, UI wrong |
| ✗ | ✓ | ✓ | ✓ | ✓ | Disabled | **Partial** - skills exist but CLI not on PATH |

### Linux Gap

The problem is compounded on Linux:

- `contextify-query` is not built for Linux (macOS-only target)
- Linux users can run `contextify-ingest` to create databases
- But they cannot use Total Recall (the primary feature)
- No way to install or verify skills on Linux

---

## Component Inventory

### All Installation Components

| Component | Path | Purpose | Required For |
|-----------|------|---------|--------------|
| **Shim** | `/opt/homebrew/bin/contextify-query` | CLI entry point | All CLI usage |
| | `/usr/local/bin/contextify-query` | (Intel Mac) | |
| | `~/bin/contextify-query` | (fallback) | |
| **Plugin Cache** | `~/.claude/plugins/cache/contextify/query/{version}/` | Plugin code | Claude Code plugin features |
| **Plugin Manifest** | `~/.claude/plugins/installed_plugins.json` | Registration | Claude Code discovery |
| **Claude Skill** | `~/.claude/skills/total-recall/SKILL.md` | Skill definition | /total-recall in Claude Code |
| **Codex Skill** | `~/.codex/skills/total-recall/SKILL.md` | Skill definition | /total-recall in Codex CLI |
| **Agent** | `~/.claude/plugins/cache/contextify/query/{version}/agents/contextify-researcher.md` | Researcher agent | Multi-query delegation |
| **Database** | `~/Library/Application Support/Contextify/contextify.db` | Data store | All queries |
| | (Linux) `~/.local/share/contextify/contextify.db` | | |

### Platform Variations

| Component | macOS DMG | macOS App Store | Linux |
|-----------|-----------|-----------------|-------|
| Shim location | System paths | User-selected (bookmark) | `~/.local/bin` or system |
| Shim type | Binary copy | Shell script | Binary |
| Plugin cache | ✓ | ✓ | N/A (no Claude Code plugin system on Linux?) |
| Plugin manifest | ✓ | ✓ | N/A |
| Claude skill | ✓ | ✓ (via Homebrew CLI) | ✓ |
| Codex skill | ✓ | ✓ (via Homebrew CLI) | ✓ |
| Agent | ✓ | ✓ | N/A |
| Database | App creates | App creates | CLI creates |
| Admin install | May need sudo | N/A (sandbox) | May need sudo |

---

## Proposed Solution: `contextify-query doctor`

### Command Design

```bash
contextify-query doctor [--json] [--fix]
```

**Options:**
- `--json`: Output as JSON for programmatic consumption (app integration)
- `--fix`: Attempt to repair missing components (runs install-plugin if needed)

### Output Format (Human)

```
Contextify Installation Health Check
====================================

Shim:
  ✓ /opt/homebrew/bin/contextify-query
  ✓ Version: 1.1.0
  ✓ On PATH: yes

Plugin:
  ✓ Cache: ~/.claude/plugins/cache/contextify/query/1.1.0/
  ✓ Manifest: entry exists in installed_plugins.json
  ✓ Agent: contextify-researcher.md present

Skills:
  ✓ Claude: ~/.claude/skills/total-recall/SKILL.md
  ✓ Codex: ~/.codex/skills/total-recall/SKILL.md
  ✓ Content: identical (hash: a1b2c3d4)

Database:
  ✓ Path: ~/Library/Application Support/Contextify/contextify.db
  ✓ Schema: v32 (current)
  ✓ FTS5: enabled
  ✓ Stats: 5 projects, 42 transcripts, 1234 entries

Overall: HEALTHY
```

### Output Format (JSON)

```json
{
  "version": "1.1.0",
  "timestamp": "2026-01-10T18:30:00Z",
  "platform": "darwin",
  "overall": "healthy",
  "components": {
    "shim": {
      "status": "ok",
      "path": "/opt/homebrew/bin/contextify-query",
      "version": "1.1.0",
      "on_path": true
    },
    "plugin": {
      "status": "ok",
      "cache_path": "~/.claude/plugins/cache/contextify/query/1.1.0/",
      "manifest_entry": true,
      "agent_present": true
    },
    "skills": {
      "status": "ok",
      "claude": {
        "exists": true,
        "path": "~/.claude/skills/total-recall/SKILL.md",
        "hash": "a1b2c3d4"
      },
      "codex": {
        "exists": true,
        "path": "~/.codex/skills/total-recall/SKILL.md",
        "hash": "a1b2c3d4",
        "is_symlink": false
      },
      "content_match": true
    },
    "database": {
      "status": "ok",
      "path": "~/Library/Application Support/Contextify/contextify.db",
      "schema_version": 32,
      "fts_enabled": true,
      "project_count": 5,
      "transcript_count": 42,
      "entry_count": 1234
    }
  },
  "issues": [],
  "suggestions": []
}
```

### Status Values

| Status | Meaning |
|--------|---------|
| `healthy` | All components present and valid |
| `degraded` | Some components missing but core functionality works |
| `broken` | Critical components missing, CLI won't function |
| `unconfigured` | Fresh install, nothing set up yet |

### Issue Detection

```json
{
  "issues": [
    {
      "component": "skills",
      "severity": "warning",
      "code": "CODEX_SKILL_MISSING",
      "message": "Codex skill not installed - /total-recall won't work in Codex CLI",
      "fix": "Run: contextify-query install-plugin"
    },
    {
      "component": "shim",
      "severity": "error",
      "code": "SHIM_NOT_ON_PATH",
      "message": "CLI shim exists but ~/bin is not on PATH",
      "fix": "Add to ~/.zshrc: export PATH=\"$HOME/bin:$PATH\""
    }
  ]
}
```

---

## App Integration

### Current: CLICoordinator.computeState()

```swift
private static func computeState() -> State {
  // Only checks shim + manifest
  guard let shimPath = findInstalledShim() else { return .disabled }
  guard let pluginVersion = readInstalledPluginVersion() else { return .disabled }
  // ... returns .enabled
}
```

### Proposed: Use doctor for comprehensive check

```swift
private static func computeState() -> State {
  // Try CLI doctor first (if CLI exists)
  if let doctorResult = runDoctorCommand() {
    return mapDoctorToState(doctorResult)
  }

  // Fall back to basic checks if CLI not available
  return basicStateCheck()
}

private static func runDoctorCommand() -> DoctorResult? {
  // Shell out to: contextify-query doctor --json
  // Parse JSON response
  // Return nil if CLI doesn't exist or fails
}

private static func mapDoctorToState(_ result: DoctorResult) -> State {
  switch result.overall {
  case "healthy":
    return .enabled(version: result.version, pathWarning: !result.shim.onPath)
  case "degraded":
    return .degraded(issues: result.issues)  // New state
  case "broken":
    return .failed(error: result.issues.first?.message ?? "Unknown error")
  case "unconfigured":
    return .disabled
  }
}
```

### New UI State: Degraded

Add a "degraded" state to the Settings UI:

```
CLI Installation          ⚠️ Warning
─────────────────────────────────────
Installed (v1.1.0) - Some issues detected

⚠️ Codex skill not installed
   /total-recall won't work in Codex CLI

[Repair]  [Disable]
```

The "Repair" button runs `contextify-query doctor --fix` or `install-plugin`.

---

## Implementation Plan

### Phase 0: Extract CLIHealthChecker to ContextifyCore (P0 - Do First)

**Rationale:** Both the app (`CLICoordinator`) and CLI (`doctor` command) need health checking logic. Extracting to a shared module in ContextifyCore provides a single source of truth and avoids duplication that would drift over time.

**Deliverables:**

1. Create `app/Sources/ContextifyCore/Installation/CLIHealthChecker.swift`
   - `struct CLIHealthChecker` with pure filesystem checks
   - `func checkHealth() -> HealthReport`
   - `struct HealthReport: Codable, Sendable` with component statuses
   - `enum HealthStatus: healthy | degraded | broken | unconfigured`
   - Platform-aware: full checks on macOS, skills-only on Linux

2. Refactor `CLICoordinator.computeState()` to use `CLIHealthChecker`
   - Remove duplicated filesystem logic
   - Map `HealthReport` to existing `State` enum
   - Keep UI-specific logic (throttling, operation flags) in CLICoordinator

3. Add unit tests: `Tests/ContextifyCoreTests/CLIHealthCheckerTests.swift`
   - All components present → healthy
   - Missing Codex skill → degraded with correct issue
   - Missing shim → broken/unconfigured
   - Platform-specific behavior

4. Verify build passes, existing tests pass

**Validation:** App Settings > CLI tab shows same behavior as before extraction.

**Design doc:** `/tmp/cli-health-checker-extraction.md`

---

### Temporary Fix in Place

A quick fix was added to `CLICoordinator.computeState()` to check for skill file existence:

**Location:** `Contextify/Contextify/CLICoordinator.swift:325-382`

**What it does:**
- Checks if `~/.claude/skills/total-recall/SKILL.md` exists
- Checks if `~/.codex/skills/total-recall/SKILL.md` exists
- Returns repair state if skills missing

**To be replaced by:** Phase 0 (CLIHealthChecker extraction)

Search for `#CLI-DOCTOR` to find the TODO marker.

---

### Phase 1: CLI doctor command (P0 for Linux release)

1. Add `doctor` case to Command enum
2. Call `CLIHealthChecker.checkHealth()` (from Phase 0)
3. Format output (human-readable and JSON)
4. Add `--fix` flag to run `install-plugin` if issues detected

### Phase 2: Linux build (P0 for Linux release)

1. Add `contextify-query` to Linux Package.swift targets
2. CLIHealthChecker already handles platform differences (from Phase 0)
3. Add to Linux CI workflow
4. Verify `install-plugin` creates skill files on Linux

### Phase 3: App integration (P1) - SUPERSEDED

~~Original plan: Shell out to `contextify-query doctor --json`~~

**New approach (Phase 0):** App uses `CLIHealthChecker` directly from ContextifyCore. No subprocess needed. This is simpler and avoids bootstrap problems (what if CLI is broken?).

The repair state UI is already implemented. Phase 0 just extracts the logic to a shared location.

### Phase 4: Unified health check spec (P2) - SUPERSEDED

~~Original plan: Document canonical paths in shared location~~

**New approach (Phase 0):** CLIHealthChecker IS the unified spec. Paths are defined once in code, used by both app and CLI.

---

## Testing Strategy

### Unit Tests

- `DoctorCommandTests.swift`:
  - All components present → healthy
  - Missing skill → degraded
  - Missing shim → broken
  - JSON output format validation

### Integration Tests

- QA script: `scripts/qa/codex-support/interactive-qa-doctor.sh`
  - Clear all components
  - Run doctor → unconfigured
  - Run install-plugin
  - Run doctor → healthy
  - Remove one skill
  - Run doctor → degraded with correct issue
  - Run doctor --fix
  - Run doctor → healthy

### Platform Tests

- macOS DMG: Full component set
- macOS App Store: Homebrew-installed CLI
- Linux: Skills only (no plugin system)

---

## Open Questions

1. **Linux plugin system**: Does Claude Code on Linux use `~/.claude/plugins/`? If not, what components apply?

2. **Version compatibility**: Should doctor warn if CLI version doesn't match app version?

3. **Database location discovery**: On Linux, where should the database live? Should doctor check multiple locations?

4. **Repair scope**: Should `--fix` only run install-plugin, or also attempt to fix PATH issues?

5. **Caching**: Should app cache doctor results to avoid repeated CLI calls?

---

## References

- `Contextify/Contextify/CLICoordinator.swift` - Current state detection
- `Sources/ContextifyQueryCLI/main.swift` - CLI implementation
- `TODOS.md #LINUX-TOTAL-RECALL` - Tracking item
- `build/docs/architecture/cross-platform-architecture.md` - Platform matrix

---

## Appendix: Current Code Locations

### State Detection (App)

```
CLICoordinator.swift:235-262  computeState()
CLICoordinator.swift:638-676  findInstalledShim()
CLICoordinator.swift:679-693  readInstalledPluginVersion()
```

### Status Command (CLI)

```
main.swift:515-529  case .status
main.swift:1383-1392  printStatus()
```

### Install/Uninstall (CLI)

```
main.swift:1820-2050  runInstallPlugin() / runUninstallPlugin()
```
