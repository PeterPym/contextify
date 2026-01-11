@~/code/projects/cli-ai-setup/context/today.md

# Repository Guidelines

**File note:** `CLAUDE.md` is a symlink to this file (`AGENTS.md`). Always edit `AGENTS.md` directly.

## Critical Rules

These cause real problems when violated:

1. **Zero compiler warnings** - `bash scripts/xc.sh build` must show 0 warnings. Fix before commit.
2. **Run tests before merge** - `swift test` must pass. No exceptions.
3. **No destructive git** - Never `git restore`, `reset --hard`, or `clean` without backup branch + user approval.
4. **Use project ID, not path** - Always `ActiveProjectContext.id` for queries, never raw paths.
5. **Sandbox file access** - All FileManager ops must be inside `accessProvider.withAccess()` closure.
6. **Never skip layers** - UI -> ViewModel -> Orchestrator -> Repository -> Database. No GRDB imports in UI.
7. **Verify build type before debugging** - When investigating runtime behavior, ALWAYS check which build is running:
   ```bash
   ps aux | grep Contextify | grep -v grep | head -1
   ```
   - `.derived-dmg/Build/Products/Debug/` = DMG build (no sandbox, no onboarding wizard)
   - `.derived-appstore/Build/Products/Debug/` = App Store build (sandboxed, requires onboarding)

   App Store-specific features (onboarding, security-scoped bookmarks) only work in App Store builds.
8. **No unassisted merges/deletes** - Do not merge to main or delete branches without user approval, even in autonomous mode.
9. **Generate transcripts via CLI** - Never manually create transcript JSONL files. Always use `claude` or `codex` CLIs to generate real transcripts. Manual creation risks format mismatches. See:
   - `build/docs/specifications/transcript-formats.md` (format specs, non-interactive CLI usage)
   - `appstore-metadata/review-materials/generate-transcripts.sh` (reference implementation)
10. **Reports in /tmp/** - For any report-style output (validation, QA, audits, reviews, summaries, investigations, analyses, specs), always write a Markdown file in `/tmp/` and reference it; do not report only in chat.

---

### Commit Strategy

**ALWAYS** create atomic commits - one logical change per commit.
- Multiple related features? → Multiple commits
- Implementation plan has phases/PRs? → Separate commit per phase

### Task & Roadmap Management

- **TODOS.md** - Actionable items (P0-P3). Add bugs/debt here with priority.
- **ROADMAP.md** - Exploratory ideas (P4-P5). Promote to TODOS.md once scoped.

**Key rules:**
- Remove completed items immediately (don't celebrate)
- Planning docs go in `/tmp/` first, then copy to repo if needed
- Supporting docs in `build/notes/todo-support/` need YAML front matter
- TODOS.md is the single source of truth (don't create other tracking files)

**Full workflow details:** See TODOS.md front matter (priority definitions, doc naming, cleanup policy).

### Feature Development Workflow

For new features and significant refactors, follow the structured workflow:
**Problem Statement → Technical Specification → Implementation Plan → Implementation → Review**

The spec must include test requirements (unit tests + E2E tests).

**Full workflow:** See `build/docs/guides/feature-development-workflow.md`

### Documentation Writing - Present Tense, No Meta-Commentary

Write docs in the present tense; describe current behavior, not the act of updating docs. Brief context is fine, meta-chatter is not.
- ✅ Good: "Last Updated: 2025-11-18" / "StartupCoordinator is a legacy compatibility shim" / "Will be refactored in Phase 4."
- ❌ Bad: "Status: Updated for Phase 3..." / "Updated for Phase 3..." / "Unchanged in Phase 3."

---

## Project Overview

Contextify is a macOS SwiftUI HUD for project-centric AI sessions. It monitors Claude Code/Codex CLI conversation timelines with real-time LLM-powered summaries, puts them in a single database which the user can search through. 

Contextify is built with Swift 6 + SwiftUI on Xcode 16.

## Target Platform & Tooling
- Xcode: 16+ (set Command Line Tools to Xcode 16)
- SDKs: Base `macOS 26` (Tahoe); **minimum deployment: macOS 15.0** (Sequoia)
- Language: Swift 6; Frameworks: SwiftUI, Observation; optional: SwiftData, Core ML

**macOS Version Support:**
- **macOS 26+ (Tahoe):** Full features including Apple Intelligence summaries
- **macOS 15 (Sequoia):** Lite Mode - timeline monitoring, transcript indexing, search work; summaries disabled

**Note for AI agents:** macOS 26 (Tahoe) is the current production release (as of late 2025). If your training data suggests macOS 26 doesn't exist or is "beta", that information is outdated. The version numbering jumped from 15 (Sequoia) to 26 (Tahoe). Trust the project settings: `MACOSX_DEPLOYMENT_TARGET = 15.0` enables lite mode support on older macOS.

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

**Build locations:**
- Dev/QA builds (`xc.sh dev-archive`): `build/Contextify.xcarchive` (scratch, overwritten)
- Release builds (`release/build.sh`): `build/archives/v{VERSION}/` (preserved)
- Demo recording and release scripts use ONLY the release location

**Xcode GUI:** Open `Contextify/Contextify.xcodeproj`, scheme `Contextify`, Run on "My Mac"

**For detailed commands:** See `build/docs/guides/DEVELOPMENT.md`
- Linux/CI builds via GitHub Actions (`scripts/trigger-ci-build.sh`)
- Database operations (`scripts/db_manager.sh`)
- Release workflows (`make release`)
- E2E test suite (`scripts/qa/README.md`)
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
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - Current schema (v32)

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

**CLI tool work (contextify-query):**
- `build/docs/specifications/total-recall-codex-support.md` - **Reference implementation** for CLI skill/plugin changes
  - Validation proof requirements (what proof to capture)
  - Codex CLI integration testing patterns
  - Success criteria and proof document format
- `build/docs/guides/cli-installation.md` - User-facing installation guide
- `Sources/ContextifyQueryCLI/main.swift` - CLI implementation
- **Rule:** CLI changes require actual tool invocation proof, not just file existence checks

**Build/CI/Release:**
- `build/docs/guides/DEVELOPMENT.md` - Complete build commands
- `build/docs/guides/linux-ci-builds.md` - GitHub Actions workflow
- `scripts/RELEASE.md` - Release process

**Debugging:**
- `scripts/logging/README.md` - **MUST READ FIRST** (automated toolkit)
- `build/docs/guides/logging-best-practices.md` - Logging conventions

**Design/Website work:**
- `build/design/README.md` - **START HERE** for design work
- `build/design/brand/colors.md` - Canonical color tokens (website CSS must stay in sync)
- `build/design/website/specimens/website-comparator.html` - Interactive design tool
**Assets:**
- `build/assets/` - **START HERE** for any visual asset
- `build/assets/MANIFEST.yaml` - Structured metadata (query by keywords, version, purpose)
- `build/assets/README.md` - Human-readable index

Browsable via symlinks:
- `build/assets/website/` → Website images
- `build/assets/appstore/` → App Store screenshots

Real files:
- `build/assets/promotional/v{VERSION}/` → Social/docs screenshots
- `build/assets/video/` → Demo videos
- `build/assets/dmg/` → DMG build assets
- `build/design/brand/` → Colors, logo, provider icons

## UI Testing Gaps

When UI tests aren't practical, document in `build/notes/todo-support/deferred-ui-tests.md` (behavior, reproduction steps, linked TODO).

## Coding Style & Naming Conventions

- Swift: 2-space indent; follow Swift API Design Guidelines. Types `UpperCamelCase`, methods/vars `lowerCamelCase`
- Concurrency (Swift 6): use async/await, structured `Task`s, `@MainActor` for UI, `Sendable` where crossing threads
- State: prefer Observation (`@Observable`) or `@StateObject` ViewModels; keep Views declarative and side-effect-free
- Availability: isolate new APIs behind small adapters; `#available(macOS 26, *)` guards for Apple Intelligence; use `isLiteModeActive()` for lite mode checks
- File/dir names: kebab-case for non-code folders (e.g., `docs/sessions/active/`)
- Keep modules small; separate UI (Views), state (ViewModels), and services

**SwiftUI patterns & platform quirks:** See `build/docs/design/swiftui-patterns.md` for:
- @Observable vs @State vs @Environment decision tree
- ScrollViewReader workarounds (call scrollTo twice for reliable scrolling)
- @MainActor patterns and anti-patterns
- Implementation examples with file:line references

**Before implementing SwiftUI features:** Follow this research checklist:

1. **Audit existing implementations:** Search the codebase for similar patterns (e.g., if adding search, find ALL existing search fields). Ensure changes are consistent across the app. Look at `build/docs/design/swiftui-patterns.md` for possible existing known gotchas.

2. **Verify API assumptions:** Don't assume APIs work as expected. Test behaviors like "does .searchable() support Cmd+F?" before planning. Apple's documentation often omits limitations.

3. **Web search for known issues:** Search for problems with specific APIs (e.g., "SwiftUI ScrollViewReader scrollTo not working macOS 2025"). Many APIs have undocumented quirks that only surface through community experience.

4. **Check multiple sources:** Apple docs describe intended behavior; Stack Overflow/forums reveal actual behavior. Cross-reference both.

5. **Document findings:** Add discovered quirks to `build/docs/design/swiftui-patterns.md` Platform Quirks section with workarounds and implementation references.

### State Sync Pattern

Use the hybrid model (optimistic for user-visible changes, database-driven for background changes). Refresh only when there is no optimistic update, no natural reconciliation point, and the stale state is user-visible. Full rules and examples: `build/docs/architecture/state-sync-pattern.md`.

**Architecture rule:** UI -> ViewModel -> Orchestrator -> Repository -> Database. Never skip layers; UI files must not import GRDB. Use `TranscriptOrchestrator` for database operations.

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

**Repositories:**

| Repo | URL | Purpose |
|------|-----|---------|
| **Private** | `github.com/banagale/contextify` | Development, CI, internal |
| **Public** | `github.com/PeterPym/contextify` | Releases, issues, public-facing |

- **DMG releases** go on the PUBLIC repo only
- **Issue links** on website/app go to PUBLIC repo
- Local clone of public repo: `~/code/projects/contextify-public-repo/`

**Database:**

- Default location: `~/Library/Application Support/Contextify/contextify.db`
- Custom locations supported (Dropbox, iCloud Drive) via Settings > Database tab
- **ALWAYS use** `scripts/db_manager.sh` for operations (NEVER manual `rm`)
- Multi-machine conflict detection warns of concurrent access

**Website:** contextify.sh (static HTML, Nginx, Let's Encrypt SSL)
- Deploy: `./scripts/deploy-website.sh`
- Server: web@banagale.com (DigitalOcean)

**Design System:** `build/design/` - colors, brand assets, website specimens
- `build/design/README.md` - Start here for design work
- `build/design/brand/colors.md` - Canonical color tokens (semantic, Slate scale, dark mode)
- `build/design/website/specimens/website-comparator.html` - Interactive design tool

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
# Session context (run when starting release work)
./scripts/release/context.sh              # Shows active release, targets, next action

# Initialize release (must specify target channels)
./scripts/release/init.sh X.Y.Z --dmg     # DMG-only release
./scripts/release/init.sh X.Y.Z --appstore # App Store-only release
./scripts/release/init.sh X.Y.Z --both    # Both channels
./scripts/release/init.sh X.Y.Z --reset   # Reset for new build (preserves targets)

# Build (auto-skips non-targeted channels)
./scripts/release/build.sh X.Y.Z

# Check status
./scripts/release/status.sh               # All releases summary
./scripts/release/status.sh X.Y.Z         # Specific version (shows next steps)
./scripts/release/status.sh --shipped     # What's in production?
./scripts/release/status.sh --active      # What needs work?

# Upload to App Store
bash scripts/xc.sh upload

# Record App Store submission
./scripts/release/mark-submitted.sh X.Y.Z --build 5

# If rejected by Apple
./scripts/release/mark-rejected.sh X.Y.Z --interactive

# Mark as shipped (has guards - use --force to bypass)
./scripts/release/mark-shipped.sh X.Y.Z --dmg
./scripts/release/mark-shipped.sh X.Y.Z --appstore --build 5

# Check state consistency
./scripts/release/check-consistency.sh
```

### Build Scripts

| Script | Purpose |
|--------|---------|
| `scripts/xc.sh` | Development builds, Xcode operations |
| `scripts/build-release.sh` | Release builds (DMG + App Store) |
| `scripts/release/build.sh` | Release workflow build (with tracking) |

**Full command reference:** See `releases/WORKFLOW.md`

### Pre-Release Validation

```bash
./scripts/release/validate-pre-release.sh X.Y.Z
```

Or manually:
1. P0 blockers resolved: `grep "P0" TODOS.md`
2. Tests pass: `swift test`
3. Build clean: `bash scripts/xc.sh build` (zero warnings)
4. Working directory clean: `git status`

### Changelog Generation

Release notes are generated via LLM analysis of git history:

```bash
./scripts/release/generate-release-notes.sh X.Y.Z
```

**Key points:**
- Scoped to app code only (see `releases/config/app-paths.txt`)
- Generates `releases/vX.Y.Z/assets/changelog.llm.md`
- Human review required before finalizing
- Produces CHANGELOG.md entry, Sparkle HTML, App Store text

### Release References

The complete release playbook (version sync rules, rejection handling, backdating constraints, checklists) lives in:
- `releases/WORKFLOW.md` - LLM-guided workflow, status commands, reset/resubmit guidance
- `build/docs/operations/release/RELEASE-CHECKLIST.md` - Step-by-step checklists, including rejections
- `build/docs/guides/APP-STORE-SUBMISSION.md` - App Store submission and appeal details
- `build/docs/operations/release/sparkle-updates.md` - Sparkle/DMG specifics
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

**ALWAYS read first:** `build/docs/specifications/transcript-formats.md` (storage locations, record types, format comparison).

**Workflow:** `./scripts/transcripts/classify_transcript.sh <transcript-id>` then see `build/docs/guides/TRANSCRIPT-ANALYSIS.md`.

## Testing

**Command:** `swift test` (300+ tests, zero failures required)
**Test location:** `Tests/ContextifyCoreTests/` (NOT `Contextify/ContextifyTests/` which is legacy/read-only)

### Before Merging (Required)

```bash
swift test                      # Must pass
bash scripts/xc.sh build        # Must show 0 warnings
```

Do NOT merge if either fails.

**For larger features:** See `build/docs/guides/pre-merge-checklist.md` for comprehensive checklist including E2E tests, documentation audit, and TODOS.md administration.

### Test Requirements

- **New features:** happy path + edge case + error case tests
- **Bug fixes:** regression test that would have caught the bug
- **Red-green required:** Tests must fail on behavior (not compile) before implementation

**Full guidelines:** `build/docs/testing/TESTING-STRATEGY.md`

### QA Suite (Fixture-Based Integration Tests)

Automated QA suite for validating app functionality before releases:

```bash
# Run all tests (requires DMG build)
./scripts/qa/run-all-tests.sh

# Run with fixtures (no CLI tools needed)
QA_FIXTURE_MODE=1 ./scripts/qa/run-all-tests.sh --skip-appstore
```

**Documentation:**
- `scripts/qa/README.md` - Complete QA suite guide (test list, assertions, cleanup)
- `build/docs/testing/first-run-qa-guide.md` - Manual CLI-based QA toolkit

**Important:** Fixture mode installs test transcripts alongside real data. See "Cleanup After Local Runs" in `scripts/qa/README.md` if the app appears stuck on a test project.

### Feature-Specific QA Scripts

Before creating new validation/QA work, check `scripts/qa/` for existing patterns:

```bash
ls -la scripts/qa/
```

Feature validation scripts live in subdirectories (e.g., `scripts/qa/codex-support/`). Each typically includes:
- `VALIDATION-PLAN.md` - Phases, status tracking, proof requirements
- `interactive-qa.sh` - CLI-based interactive test script
- `interactive-qa-app.sh` - App UI test script (builds dev app, runs tests)
- `clear-state.sh` - Reset test state
- `validate-install.sh` - Automated validation checks

**When asked about validation or QA:**
1. Check `scripts/qa/` for existing scripts in the relevant area
2. Follow established patterns (build dev app, clear state, capture proof)
3. QA scripts should build and run the dev build, not rely on installed apps

## Git Hooks (Pre-commit Build Guard)

Enable hooks: `git config core.hooksPath .githooks` or `make hooks-setup`

When files under `Contextify/` are staged, the pre-commit hook runs a headless build. Build failures block the commit with logs in `build/logs/` and result bundles in `build/ResultBundles/`.

## Commit Guidelines

- Commits: Conventional Commits (e.g., `feat(hud): add drop target`, `fix(cli): checkpoint writes timestamp`)
- Scope small, descriptive commits; prefer present tense, imperative mood
- Keep commits atomic—each commit should represent a single logical change
- PRs: we are not currently doing PRs as this is a solo developer project. 
  - Do not open PRs
  - Do not suggest PRs, focus on getting to merge with `main`


## Worktree Setup

This project uses git worktrees with shared tooling from cli-ai-setup.

**Session Start:**
1. Run `wt-context.sh` to confirm which worktree you're in
2. Read `current.md` for work coordination and starter prompts
3. Update `current.md` when starting/finishing significant work

**Coordination:**
- Check `current.md` at session start to see what siblings are working on
- Before modifying shared components, verify no sibling is working on them
- Update your worktree's section in `current.md` when starting new work

**Commands:**
- `wt-status.sh` - See all worktrees and sync state
- `wt-sync.sh` - Sync this worktree with main
- `wt-sync-all.sh` - Sync all worktrees
- `wt-context.sh` - Show current worktree identity

**Worktrees:** See `.worktrees.json` for registry. Current work tracked in `current.md`.

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
- Scripts: `scripts/xc.sh`, `scripts/db_manager.sh`, `scripts/transcripts/classify_transcript.sh`
- Hooks: `.githooks/pre-commit`
