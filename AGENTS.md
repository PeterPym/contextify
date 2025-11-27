# Repository Guidelines

**File note:** `CLAUDE.md` is a symlink to this file (`AGENTS.md`). Always edit `AGENTS.md` directly.

## ⚠️ CRITICAL RULES (Read First)

### Commit Strategy
**ALWAYS** create atomic commits - one logical change per commit.
- Multiple related features? → Multiple commits
- Implementation plan has phases/PRs? → Separate commit per phase

### Destructive Operations
**NEVER** run `git restore`, `git reset --hard`, `git clean`, or delete tracked files without:
1. Creating a backup branch first
2. Getting explicit user approval

### Compiler Warnings - Zero Tolerance Policy
**ALWAYS** maintain zero compiler warnings. Warnings are NOT noise - they are diagnostic data.

**Why this matters:**
- **Warning fatigue kills your early warning system** - New critical warnings get lost in noise
- **Swift 6 concurrency warnings point to real bugs** - Actor isolation violations can cause data races, crashes, and the exact refresh/state issues you debug
- **Dead code warnings reveal disabled features** - Unreachable code may be masking intended behavior

**Policy:**
1. **Fix warnings immediately** when they appear (same PR/commit)
2. **Never commit code with new warnings** - Pre-commit hooks should catch this
3. **Treat warnings as potential bugs** - Especially concurrency/actor isolation warnings in Swift 6
4. **During debugging:** If warnings exist in code paths you're debugging, **fix the warnings first** - they may be pointing at root causes

**Enforcement:**
```bash
# Check for warnings before committing
bash scripts/xc.sh build 2>&1 | grep -c "warning:"
# Expected: 0
```

**Remember:** Persistent warnings in `ConversationMonitor`, `ProjectSwitcherState`, etc. aren't style issues - they're the compiler telling you about concurrency hazards in your most complex state management code.

### Task & Roadmap Management

**Two files track work and ideas:**

- **TODOS.md** - Actionable items with clear implementation paths (P0-P3). Ready to work on.
- **ROADMAP.md** - Exploratory ideas and research needing investigation (P4-P5). Not yet actionable.

**Workflow:** Ideas start in ROADMAP.md. Once investigated and scoped, promote to TODOS.md.

**Priority definitions:**
- P0: Release blockers
- P1: High priority (quality/UX)
- P2: Medium priority (nice to have)
- P3: Low priority (future enhancements)
- P4: Future considerations (needs research/design)
- P5: Research/exploratory (questions to investigate)

**Agent Instructions for TODO Management:**

When you discover bugs, issues, or technical debt during development:
1. **Add to TODOS.md** with appropriate priority (P0-P3) and clear description
2. **Create supporting docs** in `build/notes/todo-support/` with YAML front matter if complex
3. **Link research/investigation** to the TODO entry using relative paths
4. **Use P2-TODOS-AGENT** (see TODOS.md#P2-TODOS-AGENT) for help with TODO operations

When you complete work:
1. **Remove completed items from TODOS.md** (don't celebrate, just remove)
2. **Archive or delete supporting docs** from `build/notes/todo-support/` per cleanup policy (see TODOS.md front matter)
3. **Move permanent reference docs** to `build/docs/` if they describe current state

When you have exploratory ideas or need research:
1. **Add to ROADMAP.md** (P4-P5) with clear research questions
2. **Iterate in /tmp/** until finalized, then copy to repo if needed
3. **Promote to TODOS.md** once scoped and actionable

**DON'T:**
- ❌ Create planning docs directly in repo (use /tmp/ first)
- ❌ Leave completed items in TODOS.md
- ❌ Create TODO tracking files (TODOS.md is the single source of truth)
- ❌ Skip YAML front matter on supporting docs in `build/notes/todo-support/`

**Documentation lifecycle:**
- Planning/transient work → `/tmp/` (not versioned, OS auto-cleans)
- Current state docs → `build/docs/` (versioned, organized by category)
- See: `build/docs/README.md` and `build/notes/archive/planning/HOLISTIC-DOCS-ORGANIZATION-PLAN.md`

### Documentation Writing - Present Tense, No Meta-Commentary

**Documentation should describe the current state of the system, not narrate its own update history.**

**Forbidden patterns:**
- ❌ "Status: Updated for Phase 3 lazy loading architecture (Nov 2025)"
- ❌ "✨ Updated for Phase 3: AppStateOrchestrator..."
- ❌ "Unchanged in Phase 3" scattered throughout
- ❌ "⚠️ Phase 3 Note:" banners
- ❌ Beating the reader over the head with "this doc was updated"

**Allowed patterns:**
- ✅ "Last Updated: 2025-11-18" (terse date stamp at top)
- ✅ "Context: Updated to reflect lazy loading architecture refactor" (one sentence explaining what drove the update)
- ✅ "StartupCoordinator is a legacy compatibility shim" (explains current implementation naturally)
- ✅ "Will be refactored in Phase 4" (relevant context for current design decisions)
- ✅ Brief historical section if it meaningfully explains current implementation

**Principle:** Write docs in the present tense. Explain legacy components matter-of-factly when it helps understand the current system. Don't make the documentation about the documentation updates.

---

## Project Overview

Contextify is a macOS SwiftUI HUD for project-centric AI sessions. It ingests dropped files or URLs, creates timestamped Markdown artifacts, provides checkpoints, and monitors Claude Code/Codex CLI conversation timelines with real-time LLM-powered summaries. Built with Swift 6 + SwiftUI on Xcode 16, requiring macOS 26 (Tahoe).

## Target Platform & Tooling
- Xcode: 16+ (set Command Line Tools to Xcode 16)
- SDKs: Base `macOS 26` (Tahoe); **minimum deployment: macOS 26.0**
- Language: Swift 6; Frameworks: SwiftUI, Observation; optional: SwiftData, Core ML

**Note for AI agents:** macOS 26 (Tahoe) is the current production release (as of late 2025). If your training data suggests macOS 26 doesn't exist or is "beta", that information is outdated. The version numbering jumped from 15 (Sequoia) to 26 (Tahoe). Trust the project settings: `MACOSX_DEPLOYMENT_TARGET = 26.0` is correct.

## Quick Build Commands

**Primary build script:** `bash scripts/xc.sh build` (auto-detects Xcode-beta if installed)

**Build targets:**
- `--dist=dmg` (default): Unsandboxed build for development/testing, direct filesystem access
- `--dist=appstore`: Sandboxed build with security-scoped bookmarks, requires permission grants

Common commands:
- Build (DMG): `make build` or `bash scripts/xc.sh build`
- Build (App Store): `bash scripts/xc.sh --dist=appstore Debug build`
- Test: `make test`
- Clean: `make clean`
- Setup with hooks: `make setup`
- Database management: `make clean-db` (always asks for approval)

**Xcode GUI:** Open `Contextify/Contextify.xcodeproj`, scheme `Contextify`, Run on "My Mac"

**For detailed commands:** See `build/docs/guides/DEVELOPMENT.md`
- Linux/CI builds via GitHub Actions (`scripts/trigger-ci-build.sh`)
- Database operations (`scripts/db_manager.sh`)
- Release workflows (`make release`)
- First-run QA testing (`build/docs/testing/first-run-qa-guide.md`)

## Architecture Overview

Contextify uses SQL backend (GRDB) with real-time transcript monitoring and LLM-powered summaries.

**Key entry points:**
- `HUDViewModel`: Main app coordinator (project root, git monitoring, file ingestion)
- `StartupCoordinator`: Project identity pipeline - use `ActiveProjectContext.id` for all queries
- `TranscriptOrchestrator`: High-level database API (projects, transcripts, entries)
- `ConversationMonitor`: Timeline display with LLM-generated summaries
- `DatabaseManager`: Singleton for GRDB connection pool and migrations

**Critical rules:**
- Use `ActiveProjectContext.id` as stable primary identity (NOT path)
- Subscribe to `StartupCoordinator.shared.updates` for project changes
- All FileManager ops on Claude/Codex dirs must use `accessProvider.withAccess()`

**For detailed architecture:** See `build/docs/architecture/COMPONENTS.md` and `build/docs/architecture/startup-coordinator.md`

## Documentation Guide (For Agents)

**Apple Developer docs:** When you need to reference Apple documentation, fetch the Markdown version via `https://sosumi.ai/documentation/...` (same path as the Apple URL) and use that copy for reading or testing.

**Before starting work, read the relevant documentation:**

**Database work:**
- `build/docs/architecture/sql-backend.md` - Schema, migrations, repositories
- `build/docs/architecture/COMPONENTS.md` - Database layer components
- `build/docs/operations/DATABASE-LOCATIONS.md` - Custom locations, discovery
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - Current schema (v26)

**LLM/Timeline work:**
- `build/docs/architecture/llm-processing.md` - LLM queue architecture (start here)
- `build/docs/components/timeline-cache.md` - Timeline caching strategy
- `build/docs/architecture/conversation-monitor-state.md` - State management

**Transcript work:**
- `build/docs/specifications/transcript-formats.md` - **MUST READ FIRST**
- `build/docs/guides/TRANSCRIPT-ANALYSIS.md` - Classification workflow
- `build/docs/specifications/claude-code-transcript-format.md` - Claude Code format spec
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` - Parser implementation

**Project identity/startup:**
- `build/docs/architecture/startup-coordinator.md` - Startup sequencing
- `build/notes/technical-reference/system-architecture-overview.md` - High-level overview
- **Rule:** Use `ActiveProjectContext.id` for queries (NOT path)

**Sandbox/App Store builds:**
- `build/docs/architecture/transcript-access-security.md` - Security-scoped access
- **Rule:** All FileManager ops must use `accessProvider.withAccess()`

**Build/CI/Release:**
- `build/docs/guides/DEVELOPMENT.md` - Complete build commands
- `build/docs/guides/linux-ci-builds.md` - GitHub Actions workflow
- `scripts/RELEASE.md` - Release process

**Debugging:**
- `scripts/logging/README.md` - **MUST READ FIRST** (automated toolkit)
- `build/docs/guides/logging-best-practices.md` - Logging conventions

## UI Testing Gaps

When SwiftUI-based UI tests aren’t practical (broken harness, unstable viewport callbacks), note the limitation and deferred test plan in `build/notes/todo-support/deferred-ui-tests.md`. Each entry should capture:
1. The behavior that can’t be covered today (e.g., the viewport queue never fires without scrolling).
2. Logs/DB queries that reproduce the issue (see that doc for the `[SUMM-...]` patterns and sample SQL).
3. The TODO or spec that will consume the test once the environment stabilizes.

This keeps UI test debt visible and ensures future work can pick up the integration check as soon as we can rely on the SwiftUI automation stack.

## Coding Style & Naming Conventions

- Swift: 2-space indent; follow Swift API Design Guidelines. Types `UpperCamelCase`, methods/vars `lowerCamelCase`
- Concurrency (Swift 6): use async/await, structured `Task`s, `@MainActor` for UI, `Sendable` where crossing threads
- State: prefer Observation (`@Observable`) or `@StateObject` ViewModels; keep Views declarative and side-effect-free
- Availability: isolate new APIs behind small adapters; `#available(macOS 26, *)` guards with working fallbacks
- File/dir names: kebab-case for non-code folders (e.g., `docs/sessions/active/`)
- Keep modules small; separate UI (Views), state (ViewModels), and services

**SwiftUI patterns & platform quirks:** See `build/docs/design/swiftui-patterns.md` for:
- @Observable vs @State vs @Environment decision tree
- ScrollViewReader workarounds (call scrollTo twice for reliable scrolling)
- @MainActor patterns and anti-patterns
- Implementation examples with file:line references

**Before implementing SwiftUI features:** Follow this research checklist:

1. **Audit existing implementations:** Search the codebase for similar patterns (e.g., if adding search, find ALL existing search fields). Ensure changes are consistent across the app.

2. **Verify API assumptions:** Don't assume APIs work as expected. Test behaviors like "does .searchable() support Cmd+F?" before planning. Apple's documentation often omits limitations.

3. **Web search for known issues:** Search for problems with specific APIs (e.g., "SwiftUI ScrollViewReader scrollTo not working macOS 2025"). Many APIs have undocumented quirks that only surface through community experience.

4. **Check multiple sources:** Apple docs describe intended behavior; Stack Overflow/forums reveal actual behavior. Cross-reference both.

5. **Document findings:** Add discovered quirks to `build/docs/design/swiftui-patterns.md` Platform Quirks section with workarounds and implementation references.

### State Sync Pattern - Hybrid Model

Contextify uses a **hybrid state synchronization pattern** that balances immediate UI feedback with database-backed consistency.

**Two patterns for different scenarios:**

1. **User-initiated, visible changes** (optimistic updates):
   - Apply optimistic UI update immediately (instant feedback)
   - Write to database in background
   - Reconciliation happens on next natural refresh point
   - Example: Marking project as viewed, clearing unread counts

2. **Background/invisible changes** (database as source of truth):
   - Database is canonical source
   - UI refreshes on next relevant view load or notification
   - Example: New transcript entries from file watcher, LLM summaries

**When is a refresh required?**

A missing refresh is a **bug** only when:
- There's no optimistic update AND
- There's no natural reconciliation point AND
- The stale state is user-visible

**When is a refresh optional?**

Refreshes can be deferred when:
- Optimistic update already applied (user sees immediate feedback)
- Natural reconciliation exists (next project switch, app restart)
- State is not immediately user-visible

**Example (correct pattern):**

```swift
// Optimistic update - immediate UI feedback
@MainActor
func markAsViewed() {
  unreadCounts[projectId] = 0  // Instant UI update

  // Background write - no explicit refresh needed
  Task.detached {
    try orchestrator.markProjectViewed(projectId: projectId, timestamp: Date())
    // Optimistic update already applied, no UI refresh required
  }
}
```

**Example (database-driven pattern):**

```swift
// Background change - refresh from database
func onNewTranscriptEntry(notification: Notification) async {
  // Refresh timeline from database
  await loadTimelineFromDatabase()

  // UI updates automatically via @Observable
}
```

**Architecture rule:** UI → ViewModel → Orchestrator → Repository → Database

Never skip layers. UI files must not import GRDB. Use `TranscriptOrchestrator` for all database operations.

## Debugging & Logging

**Philosophy:** Log to support automated, no-human-in-the-loop debugging. Prefer self-validating test harnesses over manual log inspection.

**Primary resource:** `scripts/logging/README.md` - Complete debugging toolkit with automated test harnesses

**Log analysis guides:**
- `build/docs/guides/log-analysis-methodology.md` - Comprehensive validation methodology
- `build/docs/guides/log-analysis-quick-reference.md` - One-page troubleshooting guide

**Quick dispatch:**
- **Feature not appearing** → `scripts/logging/monitor-pipeline-check.sh` (exit 0=pass, 1=fail)
- **Verify bug fix** → `scripts/logging/monitor-automated-test.sh` (automated test harness)
- **App slow/laggy** → `scripts/logging/monitor-interactive.sh` + `analyze-gaps.sh`

**Logging conventions (OSLog):**
- Use `Logger(subsystem: "dev.contextify", category: "CategoryName")`
- `.debug` - Normal operation, success paths
- `.info` - Significant state changes (watching files, session switches)
- `.warning` - Retries, fallbacks, recoverable issues
- `.error` - Failures requiring intervention
- **Privacy:** When logging identifiers (project IDs, transcript IDs, file paths) set interpolation privacy to `.public` unless there is a strong reason not to. We are in pre-production and biasing toward unrestricted logs to accelerate diagnostics.

**For detailed conventions:** See `build/docs/guides/logging-best-practices.md`

## Operations

**Database:**

- Default location: `~/Library/Application Support/Contextify/contextify.db`
- Custom locations supported (Dropbox, iCloud Drive) via Settings > Database tab
- **ALWAYS use** `scripts/db_manager.sh` for operations (NEVER manual `rm`)
- Multi-machine conflict detection warns of concurrent access

**Website:** contextify.sh (static HTML, Nginx, Let's Encrypt SSL)
- Deploy: `./scripts/deploy-website.sh`
- Server: web@banagale.com (DigitalOcean)

**For details:** See `build/docs/operations/` (DATABASE-LOCATIONS.md, WEBSITE.md, transcript-corruption-detection.md)

## Releases

**Strategy:** DMG leads, App Store follows. Both built from same commit. DMG ships immediately; App Store ships after Apple review (24-48h).

**Release Management System:** `releases/` directory at repo root
- `releases/WORKFLOW.md` - LLM-guided release workflow (start here)
- `releases/config.json` - Release configuration
- `releases/manifest.json` - Release history and current state
- `releases/v{X.Y.Z}/` - Per-release directories with checklists, state, artifacts

**Two distribution channels:**

| Channel | Target | Updates | Build Flag |
|---------|-----------|---------|------------|
| **DMG** | Contextify | Sparkle auto-updates | `--dist=dmg` |
| **App Store** | Contextify AppStore | Apple updates | `--dist=appstore` |

### Quick Commands

```bash
# Initialize new release
./scripts/release/init.sh X.Y.Z

# Check release status
./scripts/release/status.sh X.Y.Z

# DMG Release (ships immediately)
python3 scripts/release.py --version X.Y.Z --yes
./scripts/sparkle/sign.sh dist/Contextify-X.Y.Z.dmg
# Then: update appcast.xml, deploy to website

# App Store Release (ships after review)
bash scripts/xc.sh --dist=appstore Release archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload
# Then: complete submission in App Store Connect
```

### Pre-Release Validation

```bash
./scripts/release/validate-pre-release.sh X.Y.Z
```

Or manually:
1. P0 blockers resolved: `grep "P0" TODOS.md`
2. Tests pass: `swift test`
3. Build clean: `bash scripts/xc.sh build` (zero warnings)
4. Working directory clean: `git status`

### Version Sync Requirement

All sources must match after release:
- Xcode project (`MARKETING_VERSION`)
- Git tag (`vX.Y.Z`)
- Appcast (`sparkle:shortVersionString`)
- App Store Connect
- GitHub Release

### Handling Rejections

If App Store rejects:
1. Read rejection in App Store Connect → Resolution Center
2. Metadata issue? → Fix in App Store Connect, resubmit
3. Code issue? → Fix code, rebuild with same commands, re-upload, resubmit
4. Disagree? → Appeal via Resolution Center
5. Update `releases/vX.Y.Z/release.json` with rejection details

### Version Backdating

To release newer code as an older version (e.g., release "1.1.0" code as "1.0.0"):
1. Update `MARKETING_VERSION` in project.pbxproj to target version
2. Delete any git tags for higher version
3. Create tag for target version
4. Build both distributions normally

**Only valid if:** DMG not yet public, git tag not yet pushed, App Store not yet approved.

**For complete workflow:** See `releases/WORKFLOW.md` or `build/docs/operations/release/RELEASE-CHECKLIST.md`

**Detailed guides:**
- `releases/WORKFLOW.md` - LLM-guided release workflow
- `build/docs/guides/APP-STORE-SUBMISSION.md` - App Store process
- `build/docs/operations/release/sparkle-updates.md` - Sparkle auto-updates
- `build/docs/operations/release/README.md` - Release operations overview

## Transcript Access (App Store Builds)

Sandbox builds require security-scoped bookmarks for `~/.claude/projects/` and `~/.codex/sessions/`.

**Critical requirement:** All FileManager operations must happen inside `accessProvider.withAccess()` closure.

```swift
try accessProvider.withAccess(for: TranscriptProviderID.claude) { root in
  // All file I/O happens here, synchronously
  let files = try FileManager.default.contentsOfDirectory(at: root, ...)
}
```

**For details:** See `build/docs/architecture/transcript-access-security.md`

## Transcript Analysis

**IMPORTANT:** For all transcript work, **ALWAYS consult** `build/docs/specifications/transcript-formats.md` FIRST
- Storage locations:
  - **Claude Code:** `~/.claude/projects/<encoded-path>/*.jsonl` (one directory per repo under the Claude sandbox root)
  - **Codex CLI:** `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (global sessions tree; never mirrored inside the repo)

- Project discovery (directory vs `cwd` field)
- Record types and content blocks
- Format comparison table

**Workflow:**
1. **Classify first:** `./scripts/classify_transcript.sh <transcript-id>`
2. **Read relevant docs:** `build/docs/specifications/claude-code-transcript-format.md`
3. **Reference parser:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

**For complete workflow:** See `build/docs/guides/TRANSCRIPT-ANALYSIS.md`

## Testing

**Canonical Test Suite:** Swift Package Manager (SPM)
**Command:** `swift test`
**Current Baseline:** 46/46 tests passing
**Policy:** Zero test failures, zero compiler warnings

### Validation Commands (AI Agents: Run Before Every Merge)

```bash
# 1. Run tests
swift test

# 2. Only if tests pass, run build
bash scripts/xc.sh build
```

**If `swift test` fails:** Do NOT run the build. Fix tests first.
**If `bash scripts/xc.sh build` fails or reports warnings:** Do NOT merge. Fix and re-run.
**Before merging to main:** ALWAYS run both commands, regardless of what files changed.

### Test Location

**Always add new tests here:**
```
Tests/ContextifyCoreTests/YourNewTest.swift
```

**Never add tests here:**
```
Contextify/ContextifyTests/  # Legacy Xcode tests (READ-ONLY - deprecated)
```

**Treat `Contextify/ContextifyTests/` as read-only.** You may only delete or move tests out, never add or modify tests in place.

### Test Categories (46 tests total)

- **Architectural:** Layer boundary enforcement (UI → Orchestrator → Repository → DB)
- **Repository:** display_in_timeline filters, cursor pagination, search
- **Database:** HooverEngine, crash recovery, ingestion locks, state management
- **Parsers:** Transcript parsing, metadata extraction, project identity

### Quick Commands

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter ArchitecturalTests

# Run single test
swift test --filter testHooverEnginePreviewLimit

# Build verification (must show 0 warnings)
bash scripts/xc.sh build
```

### Test Coverage Requirements

**All new features require:**
1. Happy path test (expected behavior)
2. Edge case test (boundary conditions)
3. Error case test (failure handling)

**All bug fixes require:**
1. Regression test that would have caught the bug

### Before Merging to Main (Critical)

**AI agents must verify:**
```bash
# 1. All tests pass
swift test
# Expected: "Executed 46 tests, with 0 failures"

# 2. Build succeeds with zero warnings
bash scripts/xc.sh build
# Expected: "** BUILD SUCCEEDED **" with no warning lines
```

**Do not merge if either check fails.**

### Complete Testing Strategy

**See:** `build/docs/testing/TESTING-STRATEGY.md` for comprehensive guidelines including:
- Where to put tests
- Test dependencies available
- Naming conventions
- Common mistakes to avoid
- FAQ for AI agents

## Quickstart For Agents

- Ensure Xcode 16 (or Xcode-beta) is installed and selected by the script (it auto-detects)
- Build once: `bash scripts/xc.sh build`
- Database location: Always check for custom location (see Operations section)
- Keep branches small; rely on CI (macOS build workflow) to validate changes
- NEVER run destructive git commands without backup branch/patch
- NEVER delete or clean tracked files without explicit user approval

## Git Hooks (Pre-commit Build Guard)

Enable hooks: `git config core.hooksPath .githooks` or `make hooks-setup`

When files under `Contextify/` are staged, the pre-commit hook runs a headless build. Build failures block the commit with logs in `build/logs/` and result bundles in `build/ResultBundles/`.

## Commit & Pull Request Guidelines

- Commits: Conventional Commits (e.g., `feat(hud): add drop target`, `fix(cli): checkpoint writes timestamp`)
- Scope small, descriptive commits; prefer present tense, imperative mood
- Keep commits atomic—each commit should represent a single logical change
- Do not attribute work to AI in commit messages, PR descriptions, or change logs
- PRs: clear summary, linked issues, screenshots/GIFs for UI, reproduction/acceptance steps
- Require passing checks and reviewer approval before merge; rebase onto `main`

## Code References

When referencing specific functions include the pattern `file_path:line_number` to allow easy navigation.

Example:
```
Clients are marked as failed in the `connectToServer` function in src/services/process.ts:712.
```

## Project File Locations

- Main project: `Contextify/Contextify.xcodeproj`
- Source: `Contextify/Contextify/*.swift`, `app/Sources/ContextifyCore/*.swift`
- Tests: `Contextify/ContextifyTests/*.swift`, `Contextify/ContextifyUITests/*.swift`
- Scripts: `scripts/xc.sh`, `scripts/db_manager.sh`, `scripts/classify_transcript.sh`
- Hooks: `.githooks/pre-commit`
