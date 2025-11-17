# Repository Guidelines

## ⚠️ CRITICAL RULES (Read First)

### Attribution
**NEVER** attribute work to AI/Claude/Codex in commits, co-authors, or comments.

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

---

## Project Overview

Contextify is a macOS SwiftUI HUD for project-centric AI sessions. It ingests dropped files or URLs, creates timestamped Markdown artifacts, provides checkpoints, and monitors Claude Code/Codex CLI conversation timelines with real-time LLM-powered summaries. Built with Swift 6 + SwiftUI on Xcode 16 (macOS 26 SDK, minimum deployment macOS 14/15).

## Target Platform & Tooling
- Xcode: 16+ (set Command Line Tools to Xcode 16)
- SDKs: Base `macOS 26` (Tahoe); min deployment `macOS 14` or `15`
- Language: Swift 6; Frameworks: SwiftUI, Observation; optional: SwiftData, Core ML
- Availability: gate Tahoe-only APIs (`@available(macOS 26, *)`) with clear fallbacks

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
- `build/docs/specifications/claude-code-format.md` - Claude Code format spec
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

## Coding Style & Naming Conventions

- Swift: 2-space indent; follow Swift API Design Guidelines. Types `UpperCamelCase`, methods/vars `lowerCamelCase`
- Concurrency (Swift 6): use async/await, structured `Task`s, `@MainActor` for UI, `Sendable` where crossing threads
- State: prefer Observation (`@Observable`) or `@StateObject` ViewModels; keep Views declarative and side-effect-free
- Availability: isolate new APIs behind small adapters; `#available(macOS 26, *)` guards with working fallbacks
- File/dir names: kebab-case for non-code folders (e.g., `docs/sessions/active/`)
- Keep modules small; separate UI (Views), state (ViewModels), and services

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
- **Diagnostics API** (DEBUG builds): `./scripts/timeline_api.sh status|latest|recent|watch`

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
2. **Read relevant docs:** `build/docs/specifications/claude-code-format.md`
3. **Reference parser:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

**For complete workflow:** See `build/docs/guides/TRANSCRIPT-ANALYSIS.md`

## Testing

- **XCTest** (or Swift Testing) under `ContextifyTests/` for app modules
- Key test files:
  - `GitDetectionTests.swift`: Git resolution, worktree handling, HEAD parsing
  - `ContextifyTests.swift`: HUD view model tests
  - `TestHelpers.swift`: Shared test utilities
- Target: tests for every feature; smoke tests for HUD launch and file ingest

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
