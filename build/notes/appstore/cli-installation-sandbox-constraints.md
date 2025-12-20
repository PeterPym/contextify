---
title: App Store CLI Installation - Sandbox Constraints
created: 2025-12-18
status: blocked
priority: P4
related_branch: feat/cli-auto-install
tags: [appstore, sandbox, cli, gatekeeper]
summary: |
  Comprehensive investigation into installing CLI tools from sandboxed App Store builds.
  Multiple approaches attempted, all blocked by macOS security constraints.
  Conclusion: App Store CLI requires Homebrew distribution or alternative architecture.
---

# App Store CLI Installation - Sandbox Constraints

This document captures a deep investigation into enabling CLI installation from the sandboxed App Store build. Multiple approaches were attempted, each revealing new constraints.

## Background

The `contextify-query` CLI enables Claude Code and Codex skills to query Contextify's database. For DMG builds (unsandboxed), installation is straightforward - copy binary to `/opt/homebrew/bin` or `/usr/local/bin`.

App Store builds are sandboxed, creating multiple barriers to CLI installation.

## The Journey: Approaches Attempted

### Attempt 1: Write to ~/bin (Original Approach)

**Hypothesis:** Use `FileManager.default.homeDirectoryForCurrentUser` to write to `~/bin`.

**Result:** FAILED

**Why:** In sandbox, `homeDirectoryForCurrentUser` returns the container path:
```
/Users/rob/Library/Containers/sh.contextify.Contextify/Data/
```

The shim gets written to `Container/Data/bin/contextify-query` - useless because:
- Not on user's PATH
- Not accessible outside the container
- UI showed "Installed" but CLI was non-functional

### Attempt 2: Security-Scoped Bookmarks via File Picker

**Hypothesis:** Use NSOpenPanel to let user select install location. The `com.apple.security.files.user-selected.read-write` entitlement grants write access to user-selected folders.

**Implementation:**
- Added file picker with `canCreateDirectories = true`
- User selects `~/bin` (or creates it)
- Store security-scoped bookmark for future access
- Write shim to selected location

**Result:** PARTIALLY WORKED - writing succeeded, but...

### Attempt 3: Binary Shim Blocked by Gatekeeper

**Discovery:** The installed binary shim triggered Gatekeeper:
```
"contextify-query" Not Opened
Apple could not verify "contextify-query" is free of malware
```

**Why:** Binaries extracted from App Store apps don't inherit the app's signature trust. When placed outside the app bundle and executed directly, Gatekeeper blocks them.

**Options considered:**
- User manually allows via System Preferences (poor UX)
- Code sign with Developer ID (not available for App Store builds)

### Attempt 4: Shell Script Shim

**Hypothesis:** Shell scripts don't need code signing. Write a bash script that finds and calls the real CLI inside the app bundle.

**Implementation:**
```bash
#!/bin/bash
# Find Contextify.app and run the real CLI
CLI="/Applications/Contextify.app/Contents/MacOS/contextify-query"
[ -x "$CLI" ] && exec "$CLI" "$@"
# ... fallback to mdfind, running process, etc.
```

**Result:** Script runs, but...

### Attempt 5: CLI Binary is Sandboxed

**Discovery:** When calling the CLI binary inside the App Store app bundle:
```bash
$ .derived-appstore/.../Contextify.app/Contents/MacOS/contextify-query status
# Exit code 133 (SIGPIPE) - no output
```

The DMG build's CLI works fine:
```bash
$ .derived-dmg/.../Contextify.app/Contents/MacOS/contextify-query status
db_path: /Users/rob/Library/Application Support/Contextify/contextify.db
db_schema_version: 28
# ... works perfectly
```

**Root cause:** Checked entitlements:
```bash
$ codesign -d --entitlements - .derived-appstore/.../contextify-query
com.apple.security.app-sandbox = true   # <-- PROBLEM
```

The App Store build's CLI binary has sandbox entitlements embedded. When run from terminal (outside the app's container), it can't access the database.

**Why this happens:** The `xc.sh` build script passes `CODE_SIGN_ENTITLEMENTS` globally to xcodebuild, applying sandbox entitlements to ALL targets including the CLI.

### Attempt 6: Separate CLI Entitlements

**Hypothesis:** Create `Contextify-CLI.entitlements` without sandbox, configure Xcode to use it for CLI target only.

**Blocker:** Apple requires ALL executables in an App Store bundle to be sandboxed. An unsandboxed CLI binary would fail App Store review.

This is the fundamental constraint.

## Root Cause Analysis

```
┌─────────────────────────────────────────────────────────────┐
│                    App Store Requirements                    │
├─────────────────────────────────────────────────────────────┤
│ 1. Main app MUST be sandboxed                               │
│ 2. ALL executables in bundle MUST be sandboxed              │
│ 3. Sandboxed binaries can't access files outside container  │
│ 4. Extracted binaries lose App Store signature trust        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      CLI Requirements                        │
├─────────────────────────────────────────────────────────────┤
│ 1. Must run from user's terminal (outside app)              │
│ 2. Must access database in ~/Library/Application Support/   │
│ 3. Must be on user's PATH                                   │
│ 4. Must not trigger Gatekeeper warnings                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    FUNDAMENTALLY INCOMPATIBLE
```

## Viable Solutions

### Option A: Homebrew Distribution (Recommended)

Distribute CLI separately via Homebrew:

```bash
brew tap contextify/tap
brew install contextify-query
```

**Pros:**
- CLI is unsandboxed, can access database
- Standard macOS CLI distribution method
- Auto-updates via brew upgrade
- No Gatekeeper issues (Developer ID signed)

**Cons:**
- Requires Homebrew (most dev users have it)
- Separate installation step
- Version sync between app and CLI

**App Store UI would show:**
```
┌─────────────────────────────────────────────────────────────┐
│ CLI Installation                                            │
├─────────────────────────────────────────────────────────────┤
│ The CLI enables Contextify skills in Claude Code and Codex. │
│                                                             │
│ Install via Homebrew:                                       │
│ ┌─────────────────────────────────────────────────────┐     │
│ │ brew install contextify/tap/contextify-query       │ 📋  │
│ └─────────────────────────────────────────────────────┘     │
│                                                             │
│ After installing, run: contextify-query status              │
└─────────────────────────────────────────────────────────────┘
```

### Option B: XPC Communication

App runs an XPC service. Shell script shim communicates with running app via XPC to query database.

**Pros:**
- No separate installation
- Database access handled by sandboxed app

**Cons:**
- Complex architecture
- App must be running for CLI to work
- Significant implementation effort

### Option C: DMG-Only Feature

CLI features only available in DMG build. App Store build shows:

```
CLI features require the direct download version.
Visit contextify.sh/download
```

**Pros:**
- Simple
- Clear messaging

**Cons:**
- Feature disparity between builds
- Confusing for users

## Recommendation

**Option A (Homebrew)** is the best path forward:

1. Most Contextify users are developers who have Homebrew
2. Standard distribution method for macOS CLI tools
3. Clean separation of app (sandboxed) and CLI (unsandboxed)
4. Can version CLI independently if needed

### Apple Guidelines Consideration

Directing users to install via Homebrew is allowed. Apple's guidelines prohibit:
- Requiring external software to function
- Circumventing sandbox for app functionality

But the CLI is an **optional enhancement** for power users. The app works fully without it. This is similar to how VS Code directs users to install the `code` command separately.

## Implementation Plan

### Phase 1: DMG CLI (DONE in this branch)
- Auto-install to homebrew bin paths
- Admin install dialog for non-homebrew users
- Shell script shim for dev environments

### Phase 2: App Store Homebrew Instructions (Future P4)
- Update CLI tab UI for App Store builds
- Show Homebrew install instructions
- Detect if CLI is installed (check PATH)
- Show status when installed

### Phase 3: Homebrew Tap (Future P4)
- Create `contextify/tap` repository
- Formula for `contextify-query`
- CI to publish on release

## Files Modified (This Investigation)

```
Contextify/Contextify/CLICoordinator.swift
  - File picker implementation
  - Shell script shim for sandboxed builds
  - Security-scoped bookmark handling

app/Sources/ContextifyCore/HUDCore.swift
  - CLI bookmark storage methods

Contextify/Contextify/Settings/CLISkillsSettingsTab.swift
  - App Store UI instructions (partial)

Contextify/Contextify-CLI.entitlements (created, not used)
  - Attempted unsandboxed CLI entitlements
```

## Key Learnings

1. **Sandbox is absolute** - Can't escape it for any executable in App Store bundle
2. **Gatekeeper blocks extracted binaries** - Even signed binaries lose trust outside bundle
3. **Shell scripts work** - But underlying binary still sandboxed
4. **`CODE_SIGN_ENTITLEMENTS` is global** - Applies to all targets in xcodebuild
5. **mdfind doesn't index build directories** - Dev builds not discoverable via Spotlight
6. **Running process detection works** - `ps` can find app path for dev testing

## References

- [Apple: App Sandbox](https://developer.apple.com/documentation/security/app_sandbox)
- [Mac App Store: Embedding CLI Tools](https://blog.timac.org/2021/0516-mac-app-store-embedding-a-command-line-tool-using-paths-as-arguments/)
- [Security-Scoped Bookmarks](https://developer.apple.com/documentation/security/app_sandbox/accessing_files_from_the_macos_app_sandbox)
- [Homebrew Taps](https://docs.brew.sh/Taps)
