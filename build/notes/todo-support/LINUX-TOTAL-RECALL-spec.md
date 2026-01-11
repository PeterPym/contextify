---
todo_id: LINUX-TOTAL-RECALL
title: CLI Installation Health Check - Technical Specification
type: spec
date: 2026-01-10
status: superseded
description: Unified approach to verifying CLI tool and skill installation across platforms
---

# CLI Installation Health Check - Technical Specification

## Executive Summary

During validation of Codex skill support, we discovered that Contextify lacks a unified method for verifying that all CLI components are properly installed. The app and CLI have divergent, incomplete health checks, leading to situations where the UI shows "Enabled" but the actual functionality is broken.

Contextify now provides a unified `contextify-query doctor` command that provides comprehensive installation health checking, usable by both the CLI (for user debugging) and the app (for accurate UI state). The app and CLI share `CLIHealthChecker` in ContextifyCore. Repair flows use `contextify-query install-plugin`; `doctor --fix` is deferred.

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

## Solution: `contextify-query doctor`

### Command Design

```bash
contextify-query doctor [--json]
```

**Options:**
- `--json`: Output as JSON for programmatic consumption (app integration)

**Repair:** If issues are reported, run `contextify-query install-plugin`. The `--fix` flag is deferred.

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

The "Repair" button runs `contextify-query install-plugin`.

---

## Implementation Status

### Phase 0: CLIHealthChecker extraction (complete)
- [x] `CLIHealthChecker` lives in ContextifyCore with platform-aware checks
- [x] `CLICoordinator.computeState()` uses `CLIHealthChecker`
- [x] Unit tests cover component presence and platform behavior
- [x] Settings > CLI mirrors health checks

### Phase 1: CLI doctor command (complete)
- [x] Doctor command is available
- [x] Human-readable output and JSON output are supported
- [ ] `--fix` flag is deferred; use `contextify-query install-plugin`

### Phase 2: Linux build (complete, CI pending)
- [x] `contextify-query` ships in Linux products
- [x] `install-plugin` creates skills on Linux
- [ ] Linux CI covers `contextify-query` (tracked in `scripts/qa/codex-support/VALIDATION-PLAN.md`)

### App integration and unified spec (complete)
- [x] App uses `CLIHealthChecker` directly (no subprocess)
- [x] CLIHealthChecker defines canonical paths for app and CLI

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
  - Run install-plugin
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

4. **Repair scope**: Should a future `--fix` only run install-plugin, or also attempt to fix PATH issues?

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
