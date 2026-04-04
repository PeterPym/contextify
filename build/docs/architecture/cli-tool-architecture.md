# CLI Tool Architecture

**Last Updated:** 2026-03-26
**Status:** Active

This document describes the architecture of `contextify-query`, the CLI tool that enables AI coding assistants to search Contextify's conversation database. It covers the component model, platform support, installation flows, state detection, and how to add support for new platforms.

**Start here** when working on CLI installation, skill management, or adding support for new AI CLI tools.

---

## Overview

### What is contextify-query?

`contextify-query` is a CLI tool that bridges AI coding assistants (Claude Code, Codex CLI) with Contextify's conversation database. It enables the "Total Recall" feature - searching past AI conversations from within an active session.

### The "One Database, Many CLIs" Model

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Claude Code   │    │    Codex CLI    │    │   Future CLI    │
│                 │    │                 │    │   (Gemini?)     │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                      │                      │
         │ reads                │ reads                │ reads
         ▼                      ▼                      ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ ~/.claude/      │    │ ~/.codex/       │    │ ~/.gemini/      │
│ skills/         │    │ skills/         │    │ skills/         │
│ total-recall/   │    │ total-recall/   │    │ total-recall/   │
│ SKILL.md        │    │ SKILL.md        │    │ SKILL.md        │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                      │                      │
         │ invokes              │ invokes              │ invokes
         └──────────────────────┼──────────────────────┘
                                ▼
                    ┌───────────────────────┐
                    │   contextify-query    │
                    │   (shim → binary)     │
                    └───────────┬───────────┘
                                │
                                │ queries
                                ▼
                    ┌───────────────────────┐
                    │   Contextify.app      │
                    │   Database            │
                    │   (SQLite/GRDB)       │
                    └───────────────────────┘
```

Each AI CLI tool reads its own skill file, which tells it to invoke `contextify-query`. The CLI connects to Contextify's shared database, enabling cross-tool search.

---

## Component Model

### 1. Shim

**What:** A small executable that finds and runs the real `contextify-query` binary.

**Where:**
- `/opt/homebrew/bin/contextify-query` (Apple Silicon Homebrew)
- `/usr/local/bin/contextify-query` (Intel Homebrew)
- `~/bin/contextify-query` (fallback for non-Homebrew installs)

**Why:** The shim allows the CLI to be invoked from anywhere without knowing where Contextify.app is installed. It discovers all Contextify installs via Launch Services, selects the best candidate (running instance preferred, then highest version), and execs the bundled binary.

**Multi-install warning:** When multiple Contextify installs are found, the shim writes a warning to stderr listing the candidates. This warning is suppressed when stderr is not a TTY (e.g., when invoked by an AI coding assistant from a skill), preventing noisy output in automated contexts. It can also be suppressed with environment variables:
- `CONTEXTIFY_NO_INSTALL_WARNING=1` - suppress the multi-install warning
- `CONTEXTIFY_NO_DEPRECATIONS=1` - suppress all deprecation/advisory messages

**Code location:** `ContextifyQueryShim/main.swift:174-180` (warning gating); `CLICoordinator.swift:420-454` (install logic)

### 2. Plugin Cache

**What:** The actual `contextify-query` binary and supporting files.

**Where:** `~/.claude/plugins/cache/contextify/query/{version}/`

**Why:** Versioned installation allows upgrade detection and rollback. The cache is separate from the shim to support different installation methods.

**Contents:**
- Binary or plugin files
- Agents directory (Claude Code only)

**Code location:** `CLICoordinator.swift:pluginCachePath()`

### 3. Manifest

**What:** JSON file tracking installed plugins and versions.

**Where:** `~/.claude/plugins/installed_plugins.json`

**Why:** Enables version detection for upgrade prompts. Also used by Claude Code's plugin system (legacy, but still functional).

**Format:**
```json
{
  "plugins": {
    "query@contextify": [{
      "version": "1.1.0",
      "installPath": "~/.claude/plugins/cache/contextify/query/1.1.0",
      "installedAt": "2026-01-10T12:00:00Z"
    }]
  }
}
```

**Code location:**
- Read: `CLICoordinator.swift:readInstalledPluginVersion()`
- Write: `CLICoordinator.swift:updatePluginManifest()`
- CLI: `Sources/ContextifyQueryCLI/main.swift:updatePluginManifest()`

### 4. Skills

**What:** SKILL.md files that AI CLI tools read to discover available commands.

**Where:**
- Claude Code: `~/.claude/skills/total-recall/SKILL.md`
- Codex CLI: `~/.codex/skills/total-recall/SKILL.md`
- Future CLIs: `~/.{cli-name}/skills/total-recall/SKILL.md`

**Why:** Skills are the discovery mechanism. Each CLI reads its own skills directory to find available commands. The skill file contains instructions for how to use Total Recall.

**Format:** [Agent Skills Specification](https://agentskills.io/specification)
```yaml
---
name: total-recall
description: Contextify Total Recall - Search past conversations
---

# Skill instructions...
```

**Critical:** Codex CLI ignores symlinked skill directories. Skills must be **copied**, not symlinked.

**Code location:** `Sources/ContextifyQueryCLI/main.swift:runInstallPlugin()` (lines 1698-1741)

### 5. Agents

**What:** Agent definitions for complex multi-query searches.

**Where:** `~/.claude/plugins/cache/contextify/query/{version}/agents/contextify-researcher.md`

**Why:** Enables Claude Code to delegate complex searches to a specialized agent that runs multiple queries.

**Limitation:** Only works in Claude Code. Codex CLI lacks a native Task tool, so agent delegation is not available.

**Code location:** Agent installed as part of plugin cache.

---

## Platform Support Matrix

| Platform | Skill Location | Agents | Install Method | State Detection | Status |
|----------|----------------|--------|----------------|-----------------|--------|
| Claude Code (macOS) | `~/.claude/skills/` | Yes | DMG auto, Homebrew | Full | **Shipped** |
| Codex CLI (macOS) | `~/.codex/skills/` | No | DMG auto, Homebrew | Full | **Shipped** |
| Claude Code (Linux) | `~/.claude/skills/` | Yes | Tarball | Planned | **P0 v1.1.0** |
| Codex CLI (Linux) | `~/.codex/skills/` | No | Tarball | Planned | **P0 v1.1.0** |
| Gemini CLI | TBD | TBD | TBD | TBD | Not started |

### Platform-Specific Notes

**Claude Code:**
- Has Task tool for agent delegation
- Full Total Recall functionality including contextify-researcher agent
- Skills discovered from `~/.claude/skills/`

**Codex CLI:**
- No native Task tool (agent delegation unavailable)
- Single-query mode only (skill works, delegation instructions ignored)
- Skills discovered from `~/.codex/skills/`
- **Critical:** Ignores symlinked directories - must copy skill files

**Linux:**
- No Contextify.app, CLI-only usage
- Database created by `contextify-ingest` CLI
- Skills work the same way
- See `build/notes/todo-support/LINUX-TOTAL-RECALL-spec.md`

---

## Installation Flows

### DMG Build (macOS) - Auto-Install

**Trigger:** App launch when CLI not installed and `/opt/homebrew/bin` is writable.

**Flow:**
1. App detects CLI not installed (`computeState()` returns `.disabled`)
2. `CLICoordinator.enable()` called automatically or via Settings
3. `installShimAndPlugin()` executes:
   - Copy shim to `/opt/homebrew/bin/contextify-query`
   - Copy plugin to `~/.claude/plugins/cache/contextify/query/{version}/`
   - Update manifest
   - Run `contextify-query install-plugin` to create skills
4. State updated to `.enabled`

**Code location:** `CLICoordinator.swift:installShimAndPlugin()` (lines 363-500)

### App Store Build (Homebrew)

**Constraint:** Sandboxed apps cannot write to system paths.

**Flow:**
1. User installs via Homebrew: `brew install PeterPym/contextify/contextify-query`
2. User runs: `contextify-query install-plugin`
3. Skills created for Claude Code and Codex
4. App detects Homebrew CLI via `findHomebrewCLI()`, shows `.enabledViaHomebrew` state

**Code location:** `CLICoordinator.swift:findHomebrewCLI()` (lines 297-312)

### Linux (Tarball)

**Flow:** (Planned for v1.1.0)
1. User downloads tarball from GitHub releases
2. Extracts `contextify-query` and `contextify-ingest` binaries
3. Adds to PATH manually
4. Runs `contextify-query install-plugin`

**Documentation:** `build/notes/todo-support/LINUX-TOTAL-RECALL-spec.md`

---

## State Detection

### Components Checked

`CLICoordinator.computeState()` checks these components in order:

| # | Component | Check | If Missing |
|---|-----------|-------|------------|
| 1 | Shim | `findShimPath()` returns path | → `.disabled` |
| 2 | Manifest | `readInstalledPluginVersion()` returns version | → `.disabled` |
| 3 | Claude skill | File exists at `~/.claude/skills/total-recall/SKILL.md` | → See below |
| 4 | Codex skill | File exists at `~/.codex/skills/total-recall/SKILL.md` | → See below |
| 5 | PATH | Shim directory on PATH | → `pathWarning: true` |

**Code location:** `CLICoordinator.swift:computeState()` (lines 220-295)

### State Enum

```swift
public enum RepairReason: Equatable {
  case claudeSkillMissing
  case codexSkillMissing
  case bothSkillsMissing
  case manifestMissing
}

public enum State: Equatable {
  case disabled
  case installing
  case enabled(version: String, pathWarning: Bool, repairIssue: RepairReason?)
  case enabledViaHomebrew(version: String)  // App Store only
  case upgrading(from: String, to: String)
  case failed(error: String)
}
```

### UI Mapping

| State | Button | Status Text | Warning |
|-------|--------|-------------|---------|
| `.disabled` | **Enable** | "Not installed" | - |
| `.enabled(v, false, nil)` | **Disable** | "Installed (vX.Y.Z)" | - |
| `.enabled(v, true, nil)` | **Disable** | "Installed (vX.Y.Z)" | PATH warning |
| `.enabled(v, _, .claudeSkillMissing)` | **Repair** | "Installed (vX.Y.Z)" | Claude skill missing |
| `.enabled(v, _, .codexSkillMissing)` | **Repair** | "Installed (vX.Y.Z)" | Codex skill missing |
| `.enabled(v, _, .bothSkillsMissing)` | **Repair** | "Installed (vX.Y.Z)" | Both skills missing |
| `.enabled(v, _, .manifestMissing)` | **Repair** | "Installed (vunknown)" | Manifest missing |
| `.enabledViaHomebrew(v)` | - | "Installed via Homebrew" | - |
| `.installing` | - | "Installing..." | - |
| `.failed(e)` | **Retry** | Error message | - |

---

## Error States & Recovery

### Failure Mode Matrix

| # | Missing Component | Claude Works? | Codex Works? | UI |
|---|-------------------|---------------|--------------|-----|
| 1 | Nothing | Yes | Yes | Enabled |
| 2 | Shim | No | No | Disabled |
| 3 | Manifest only | Yes* | Yes* | Repair |
| 4 | Claude skill only | No | Yes | Repair |
| 5 | Codex skill only | Yes | No | Repair |
| 6 | Both skills | No | No | Repair** |
| 7 | Shim + manifest + all skills | No | No | Disabled |
| 8 | PATH issue | Maybe | Maybe | Warning |

*Manifest missing means version detection fails, but skills may still work.
**Both skills missing but shim exists - can be repaired.

### Repair Flow

When in a partial installation state (skills missing but shim exists):

1. User sees "Repair" button instead of "Disable"
2. Clicking "Repair" calls `CLICoordinator.repair()`
3. `repair()` runs `contextify-query install-plugin` to reinstall skills
4. State refreshes, should now show fully enabled

**Alternative:** User can click Disable then Enable for full reinstall.

### User Messaging

| State | Message |
|-------|---------|
| Claude skill missing | "Claude Code skill missing - Total Recall won't work in Claude Code" |
| Codex skill missing | "Codex skill missing - Total Recall won't work in Codex CLI" |
| Both missing | "CLI skills missing - Total Recall won't work. Click Repair to fix." |
| Manifest missing | "Installation incomplete. Click Repair to fix." |

---

## Adding New Platform Support

### Checklist

When adding support for a new AI CLI tool (e.g., Gemini CLI):

#### 1. Research Phase
- [ ] Identify skill location (`~/.{tool}/skills/` or similar)
- [ ] Confirm SKILL.md format compatibility (most follow agentskills.io spec)
- [ ] Check for agent/Task tool support
- [ ] Identify any quirks (e.g., Codex ignores symlinks)
- [ ] Document findings in this doc's Platform Support Matrix

#### 2. Code Changes

**Install logic** (`Sources/ContextifyQueryCLI/main.swift:runInstallPlugin()`):
```swift
// Add new skill installation
let newToolSkillsDir = home.appendingPathComponent(".newtool/skills/total-recall")
try FileManager.default.createDirectory(at: newToolSkillsDir, withIntermediateDirectories: true)
// Copy (not symlink!) skill file
let skillData = try Data(contentsOf: skillFile)
try skillData.write(to: newToolSkillsDir.appendingPathComponent("SKILL.md"), options: .atomic)
```

**Uninstall logic** (`Sources/ContextifyQueryCLI/main.swift:runUninstallPlugin()`):
```swift
// Add new skill removal
let newToolSkillDir = home.appendingPathComponent(".newtool/skills/total-recall")
if FileManager.default.fileExists(atPath: newToolSkillDir.path) {
  try FileManager.default.removeItem(at: newToolSkillDir)
}
```

**State detection** (`Contextify/CLICoordinator.swift:computeState()`):
```swift
// Add skill existence check
let newToolSkillPath = homeDir.appendingPathComponent(".newtool/skills/total-recall/SKILL.md").path
let newToolSkillExists = fileManager.fileExists(atPath: newToolSkillPath)
// Update skillWarning logic
```

**UI** (`Contextify/Settings/CLISkillsSettingsTab.swift`):
- Update warning messages to mention new tool
- Add any tool-specific UI if needed

#### 3. Testing

- [ ] Add to `scripts/qa/codex-support/interactive-qa.sh` or create new QA script
- [ ] Test headless skill discovery
- [ ] Test headless skill execution
- [ ] Test uninstall cleanup
- [ ] Verify no symlinks (if tool ignores them)

#### 4. Documentation

- [ ] Update this doc's Platform Support Matrix
- [ ] Update `build/docs/guides/cli-installation.md`
- [ ] Update Homebrew formula caveats if applicable
- [ ] Create validation plan in `scripts/qa/{tool}-support/VALIDATION-PLAN.md`

### Code Locations Reference

| Operation | File | Function/Lines |
|-----------|------|----------------|
| Install shim | `CLICoordinator.swift` | `installShimAndPlugin()` :363 |
| Install skills | `main.swift` | `runInstallPlugin()` :1686 |
| Uninstall skills | `main.swift` | `runUninstallPlugin()` :1797 |
| State detection | `CLICoordinator.swift` | `computeState()` :220 |
| UI rendering | `CLISkillsSettingsTab.swift` | Lines 240-350 |
| Find Homebrew CLI | `CLICoordinator.swift` | `findHomebrewCLI()` :297 |
| Manifest read | `CLICoordinator.swift` | `readInstalledPluginVersion()` :726 |
| Manifest write | `CLICoordinator.swift` | `updatePluginManifest()` :869 |

---

## CLI Commands Reference

### Database Commands
```bash
contextify-query status              # Database status
contextify-query search "query"      # Search entries (FTS5; hyphenated terms auto-quoted)
contextify-query projects            # List projects
contextify-query transcripts         # List transcripts
contextify-query entry <uuid>        # Get specific entry
contextify-query context <uuid>      # Get context around entry
contextify-query tag <id> [<tag>]    # Add tag to transcript; --remove to remove it
```

**`--exclude-tags` flag:** The `search` command accepts `--exclude-tags <csv>` to exclude transcripts that have any of the specified tags. Comma-separated list of tag names (e.g., `--exclude-tags archived,noise`).

**`--project` flag:** Most commands accept `--project <value>` to scope results to a project. The value can be:
- A project name (e.g., `--project contextify`) - resolved via name-based lookup
- `.` or `current` - resolves to the current working directory
- A file path - matches by path prefix

**FTS5 hyphen preprocessing:** The `search` command automatically rewrites hyphenated terms before passing them to FTS5. For example, `ct-708` becomes `"ct 708"` (quoted phrase) and `cli-ai-setup` becomes `"cli ai setup"`. This prevents FTS5 from misinterpreting hyphens as column references. Hints are written to stderr when ambiguous cases are detected.

### Cloud Commands
```bash
contextify cloud setup               # Configure cloud sync (API key, tenant)
contextify cloud status              # Show cloud sync status
contextify cloud push                # Push local entries to cloud
contextify cloud pull                # Pull remote entries to local DB
contextify cloud sync                # Bidirectional sync (push + pull)
contextify cloud search "query"      # Search across all cloud-synced machines
```

Cloud commands are available on both macOS and Linux. On macOS, `contextify cloud ...` dispatches directly to the shared `ContextifyCloudCommands` library target when `cloud` is the first token, so cloud subcommand flags are parsed by ArgumentParser. Flags placed before `cloud` are rejected with a clear error.

### Plugin Commands
```bash
contextify-query install-plugin      # Install skills for all supported CLIs
contextify-query uninstall-plugin    # Remove skills from all CLIs
```

### Health Check Commands
```bash
contextify-query doctor              # Health check of CLI installation
contextify-query doctor --json       # Machine-readable health check output
```

**Repair:** If doctor reports issues, run `contextify-query install-plugin` to fix.

The doctor command uses `CLIHealthChecker` to verify all installation components:
- Shim binary exists and is on PATH
- Plugin manifest entry exists
- Claude Code skill file exists
- Codex CLI skill file exists

On Linux, doctor checks skills only (no shim/manifest - binary runs directly).

---

## Related Documents

### Detailed Specifications
- [Codex Support Spec](../specifications/total-recall-codex-support.md) - Deep dive on Codex integration, validation requirements
- [Linux/Doctor Spec](../../notes/todo-support/LINUX-TOTAL-RECALL-spec.md) - Linux support and doctor command design

### User-Facing
- [CLI Installation Guide](../guides/cli-installation.md) - User documentation

### Cross-Platform
- [Cross-Platform Architecture](cross-platform-architecture.md) - macOS vs Linux, platform abstractions

### QA & Validation
- [QA Scripts](../../../scripts/qa/codex-support/) - Validation scripts and plans
- [VALIDATION-PLAN.md](../../../scripts/qa/codex-support/VALIDATION-PLAN.md) - Current validation status

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2025-Q4 | Initial release, Claude Code only |
| 1.1.0 | 2026-01 | Added Codex CLI support, doctor command, Linux support |
| 1.1.x | 2026-03 | FTS5 hyphen preprocessing, --project name-based lookup, shim TTY gating for multi-install warning |
| 1.2.x | 2026-04 | Cloud commands available on macOS via shared ContextifyCloudCommands target (ct-848) |
