# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Contextify is a macOS SwiftUI HUD for project-centric sessions. It ingests dropped files or URLs, creates timestamped Markdown artifacts, and provides checkpoints. Built with Swift 6 + SwiftUI on Xcode 16 (macOS 26 SDK, minimum deployment macOS 14/15).

## Build & Test Commands

**Primary build script:** `bash scripts/xc.sh build` (auto-detects Xcode-beta if installed)

Common commands:
- Build: `make build` or `bash scripts/xc.sh build`
- Test: `make test` or `bash scripts/xc.sh test`
- Clean: `make clean` (removes DerivedData)
- Full setup with hooks: `make setup`

**Xcode GUI:** Open `Contextify/Contextify.xcodeproj`, scheme `Contextify`, Run on "My Mac"

Build output: `.derived/Build/Products/Debug/Contextify.app`

## Git Hooks & Pre-commit Guard

Enable hooks: `git config core.hooksPath .githooks` or `make hooks-setup`

When files in `Contextify/` are staged, the pre-commit hook runs a headless build using Xcode-beta (if present). Build failures block the commit with logs in `build/logs/` and result bundles in `build/ResultBundles/`.

## Architecture & Key Modules

### Core Components
- **HUDViewModel** (`app/Sources/ContextifyCore/HUDCore.swift:370-1032`): Main `@Observable` `@MainActor` view model. Manages:
  - Project root detection (environment → persisted → CWD → existing)
  - Git repository discovery and branch monitoring via file watchers
  - File/URL ingestion with Markdown artifact generation
  - Session and checkpoint management
  - Security-scoped bookmarks for sandboxed access

- **GitRepositoryResolver** (`app/Sources/ContextifyCore/HUDCore.swift:142-368`): Git repository detection. Finds `.git` root, parses HEAD (handles detached state, worktrees), and executes `git rev-parse` with timeout/fallback.

- **HUDPreferences** (`app/Sources/ContextifyCore/HUDCore.swift:13-126`): Manages UserDefaults with suite fallback. Stores project root path and security-scoped bookmarks. Auto-migration from legacy defaults with warnings.

### UI Layer
- **ContentView** (`Contextify/Contextify/ContentView.swift`): Main UI with header (project/branch display, "Set Project Root" button), URL entry field, drop zone, controls (New Session, Checkpoint, Reveal Outputs), and toast notifications.

- **IngestDropZone** (`Contextify/Contextify/IngestDropZone.swift`): Drag-and-drop target for files, uses SwiftUI `onDrop` with completion handlers and main actor marshaling.

### Supporting
- **WindowTitleWriter** (`Contextify/Contextify/WindowTitleWriter.swift`): Updates window title to show current project name.
- **ComposePresenter/ComposeSheet** (`Contextify/Contextify/ComposePresenter.swift`, `ComposeSheet.swift`): URL routing and compose workflows (automation support).
- **ITerm2Bridge** (`Contextify/Contextify/ITerm2Bridge.swift`): iTerm2 integration for shell bindings.

## Persistence & Project Root Resolution

**Startup precedence (init):**
1. Security-scoped bookmark (sandboxed)
2. Persisted path from UserDefaults
3. Falls back to no project

**Runtime update precedence (`updateGitInfo`):**
1. `CONTEXTIFY_PROJECT_ROOT` environment variable
2. Persisted path (if bookmark or saved path exists)
3. Current working directory (CWD)
4. Existing project root (if already set)

**Backward compatibility:** Out of scope. Remove legacy migrations; assume clean builds with no user data.

## Git Monitoring

- Uses file watchers on `.git/HEAD`, resolved ref file (e.g., `.git/refs/heads/main`), and `.git/packed-refs`
- Sandboxed: parses HEAD directly (no git subprocess)
- Non-sandboxed: runs `git rev-parse --abbrev-ref HEAD` with 2s timeout, falls back to HEAD parsing
- Handles worktrees (`.git` file with `gitdir:` pointer)
- Debounces events (150ms) and re-arms watchers on file deletion/rename

## File Output Structure

- Outputs: `~/Contextify/outputs` (or `$CONTEXTIFY_OUTPUTS_DIR` if set; `Application Support/Contextify/outputs` in sandbox)
- Ingested files copied to `outputs/ingest/` with timestamp prefix
- Artifacts: `outputs/{timestamp}.md` (file/URL metadata)
- Checkpoints: `outputs/checkpoints/checkpoint-{session}-{timestamp}.md`

## Coding Standards

- **Swift:** 2-space indent, Swift API Design Guidelines (UpperCamelCase types, lowerCamelCase methods/vars)
- **Concurrency:** Swift 6 strict concurrency. Use async/await, `@MainActor` for UI, `Sendable` across threads. Avoid detached tasks.
- **State:** Prefer `@Observable` or `@StateObject` ViewModels. Keep Views declarative, side-effect-free.
- **Availability:** Gate macOS 26+ APIs with `@available(macOS 26, *)` and working fallbacks.
- **Commits:** Conventional Commits (e.g., `feat(hud): add drop target`, `fix(cli): checkpoint writes timestamp`). Atomic commits, present tense, imperative mood. **DO NOT** add Claude Code attribution footers or Co-Authored-By tags in this project.

## Testing

- **XCTest** (or Swift Testing) under `ContextifyTests/` for app modules
- Key test files:
  - `GitDetectionTests.swift`: Git resolution, worktree handling, HEAD parsing
  - `ContextifyTests.swift`: HUD view model tests
  - `TestHelpers.swift`: Shared test utilities
- Target: tests for every feature; smoke tests for HUD launch and file ingest

## Important Rules

- **NEVER** delete or clean tracked files without a backup branch/patch coordinated with the user
- **NEVER** run destructive git commands (`git restore`, `reset --hard`, `clean`) without explicit user coordination
- Keep PRs small; rely on CI (macOS build workflow) to validate changes
- Require passing checks and reviewer approval before merge; rebase onto `main`

## Project File Locations

- Main project: `Contextify/Contextify.xcodeproj`
- Source: `Contextify/Contextify/*.swift`, `app/Sources/ContextifyCore/*.swift`
- Tests: `Contextify/ContextifyTests/*.swift`, `Contextify/ContextifyUITests/*.swift`
- Scripts: `scripts/xc.sh`, `scripts/install-shell-bindings.sh`
- Hooks: `.githooks/pre-commit`
