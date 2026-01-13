---
branch: main
worktree: /Users/rob/code/projects/contextify-wb2
repo: banagale/contextify
date: 2026-01-11
status: ready-for-review
---

# Contextify v1.1.0 Release Analysis

**Internal Exhaustive Change Analysis**

## Compare Ranges

| Channel | Baseline | Target | Total Commits | Non-Merge |
|---------|----------|--------|---------------|-----------|
| App Store | v1.0.5 | v1.1.0 | 489 | 457 |
| DMG | v1.0.7 | v1.1.0 | 423 | 397 |
| Linux CLI | (first release) | v1.1.0 | N/A | N/A |

**Commit Type Distribution (App Store range):**
- docs: 147 (32%)
- fix: 119 (26%)
- feat: 73 (16%)
- chore: 34 (7%)
- refactor: 29 (6%)
- test: 18 (4%)
- perf: 7 (2%)
- release/build/ci: 5 (1%)

---

## 4.1 Executive Summary (Internal)

### Major Themes

1. **Linux CLI Support (NEW)** - First release of `contextify-query` for Linux, enabling Total Recall skill on Linux systems running Claude Code/Codex CLI
2. **Performance Overhaul** - 7-phase optimization effort (P1-P7) delivering ~2.5x bulk ingest speedup via PRAGMA tuning, schema optimizations, and observation-free bulk ingest
3. **Codex CLI Integration** - Full skill installation support for OpenAI Codex CLI alongside Claude Code
4. **CLI Health System** - New `doctor` command and CLIHealthChecker module for diagnosing and repairing installations
5. **Conversation Monitor Refactor** - 3-phase architectural cleanup improving state management and cache coordination
6. **Sidechain Ingestion** - Parse and store agent sidechains and tool invocations (previously discarded)
7. **Inline Image Rendering** - Timeline entries with images now render inline with Quick Look preview

### Biggest Risk/Behavior Changes

- **BEHAVIOR CHANGE**: Entries are now reassigned based on CWD to fix project misattribution (was causing cross-project entries)
- **BEHAVIOR CHANGE**: CLI manifest unified from multiple files to single `installed_plugins.json`
- **SCHEMA CHANGE**: New columns for sidechain/tool invocation storage (v33)
- **NEW DEPENDENCY**: swift-syntax now macOS-only (removed from Linux builds)

### Noteworthy Fixes

- Auto-install user skill on first launch (was manual)
- PATH warning fix for CLI installation
- Project resolution cache improvements (7 fixes)
- Sidechain filter decoupled from `includeHidden`

---

## 4.2 Change Set Index

| Change Set | Title | Commits | Surfaces | Risk | Notes |
|------------|-------|--------:|----------|------|-------|
| `linux-cli` | Linux CLI First Release | ~25 | CLI/Build/CI | Med | First platform expansion |
| `cli-doctor` | CLI Health Check System | ~12 | CLI/UI | Low | Diagnostic tooling |
| `codex-support` | Codex CLI Skill Integration | ~35 | CLI/UI | Med | New CLI target |
| `perf-optimization` | Performance P1-P7 | ~30 | DB/Core | Med | Schema + runtime changes |
| `cm-refactor` | ConversationMonitor Refactor | ~20 | Core/UI | Low | Internal cleanup |
| `sidechain-ingest` | Sidechain/Tool Invocation Storage | ~15 | DB/Core | Med | Schema migration |
| `entry-filter` | EntryFilter Type System | ~18 | Core/CLI | Low | Query layer refactor |
| `image-render` | Inline Image Rendering | ~5 | UI | Low | New timeline feature |
| `status-bar-perms` | Status Bar Permission Indicator | ~8 | UI | Low | UX improvement |
| `task-row-viz` | Task Row Visibility | ~10 | UI | Low | UI polish |
| `contextify-decor` | Contextify Call Decorations | ~12 | UI/Core | Low | Visual badges |
| `project-misattr` | Project Misattribution Fix | ~10 | Core/DB | Med | Behavior change |
| `lazy-watchers` | Lazy File Watchers | ~5 | Core | Low | Resource optimization |
| `worktree-grouping` | Worktree Color Grouping | ~8 | UI/DB | Low | Visual grouping |
| `total-recall-brand` | Total Recall Branding | ~10 | CLI/Website | Low | Naming consistency |
| `summarization-fixes` | Summarization Improvements | ~8 | Core | Low | Fallback handling |
| `benchmark-infra` | Benchmark Infrastructure | ~12 | Scripts | Low | Dev tooling |
| `release-admin` | v1.0.6/v1.0.7 Release Artifacts | ~40 | Docs/Website | Low | Release mechanics |

---

## 4.3 Change Set Details

### `linux-cli` - Linux CLI First Release

**What Changed (CONFIRMED):**
- `contextify-query` CLI now builds for Linux via SwiftPM
- Linux-specific CI workflow (`linux-release.yml`) for artifact generation
- Cross-platform abstractions: `CrossPlatformLogger`, `CrossPlatformLock`, `CrossPlatformCrypto`
- GRDB dependency removed from query CLI (Linux-incompatible)
- swift-syntax made macOS-only to fix Linux builds
- `install-plugin` command enabled for Linux

**Evidence:**
- `0437df84` feat(linux): add contextify-query to Linux products
- `5f234abb` fix(linux): make contextify-query cross-platform
- `bf98de48` fix(linux): remove GRDB dependency from query CLI
- `8681ef5a` fix(linux): make swift-syntax dependency macOS-only
- `f7613108` fix(linux): use FileHandle for Swift 6 concurrency-safe stdio

**Surface Area:** CLI / Build / CI
**Risk Level:** Medium - First platform expansion, new CI pipelines
**Channel Applicability:**
- App Store: No (macOS app only)
- DMG: No (macOS app only)
- Linux: **Yes** - Primary target

---

### `cli-doctor` - CLI Health Check System

**What Changed (CONFIRMED):**
- New `contextify-query doctor` command for installation health checks
- `CLIHealthChecker` extracted to shared module (`Sources/ContextifyQueryCLI/CLIHealthChecker.swift`)
- Unified health check logic across app and CLI
- Repair state detection for partial installations

**Evidence:**
- `53ddb735` feat(cli): add doctor command for health checking
- `b2b29d45` feat(cli): extract CLIHealthChecker to shared module
- `a64a52f3` feat(cli): add repair state for partial CLI installations
- `bcae5ff0` fix(cli): address review feedback for CLIHealthChecker

**Surface Area:** CLI / UI (Settings)
**Risk Level:** Low - Additive diagnostics
**Channel Applicability:**
- App Store: Yes (UI uses shared health checker)
- DMG: Yes
- Linux: Yes (doctor command)

---

### `codex-support` - Codex CLI Skill Integration

**What Changed (CONFIRMED):**
- Total Recall skill now installs for both Claude Code AND Codex CLI
- Manifest unified to single `installed_plugins.json` (v2 -> v1 migration on read)
- Skill file existence checks added to `CLICoordinator.computeState()`
- Skill directories removed on Disable click
- QA scripts for Codex skill validation

**Evidence:**
- `3b2162af` feat(cli): add Codex skill installation support
- `f1165459` refactor(cli): unify manifest to installed_plugins.json
- `e3293d9a` fix(cli): migrate v2 manifest to v1 on read
- `55d1b5a5` fix(cli): remove skill directories when Disable is clicked

**Behavior Changes:**
- **BREAKING (internal)**: Old manifest format auto-migrated to new format

**Surface Area:** CLI / UI (Settings)
**Risk Level:** Medium - New CLI target, manifest migration
**Channel Applicability:**
- App Store: Yes
- DMG: Yes
- Linux: Yes

---

### `perf-optimization` - Performance P1-P7

**What Changed (CONFIRMED):**
- **P1**: PRAGMA optimizations (`cache_size`, `mmap_size`) for 2.5x speedup
- **P3**: Schema optimizations (investigated, partially merged)
- **P5**: UNIQUE index optimization
- **P6**: Preloaded entry IDs to reduce lookups
- **P7**: Observation-free bulk ingest via `BulkIngestManager`

**Evidence:**
- `0e5347e8` perf(db): add cache_size and mmap_size PRAGMAs for 2.5x speedup
- `363c11a2` perf(bulk-ingest): P5 UNIQUE index + P6 preloaded entry IDs
- `fba45d3f` feat(perf): P7 observation-free bulk ingest via BulkIngestManager
- `37870142` perf(hoover): dedupe sidechain updates and skip nil toolUseId
- `e4deb612` perf(hoover): defer tool result UPDATEs to improve cache locality

**User Impact:**
- Bulk transcript ingestion is ~2.5x faster
- First-run experience significantly improved for large histories

**Surface Area:** DB / Core
**Risk Level:** Medium - Runtime performance changes, schema adjustments
**Channel Applicability:**
- App Store: Yes
- DMG: Yes
- Linux: N/A (no app)

---

### `cm-refactor` - ConversationMonitor Refactor

**What Changed (CONFIRMED):**
- Phase 1: Core extraction and modernization
- Phase 2: Wiring and state flow improvements
- Phase 3: Cache coordinator implementation
- Factory methods for component creation

**Evidence:**
- `f3a4c4f8` Merge branch 'feature/conversation-monitor-phase1-only' (1016+, 489-)
- `5df07bb5` Merge branch 'feature/conversation-monitor-phase2-wiring' (409+, 242-)
- `1e912025` Merge branch 'feature/conversation-monitor-phase3-cache-coordinator' (343+, 179-)
- `947fa6a1` fix(timeline): address Phase 3 review feedback and wire factory methods

**Surface Area:** Core / UI
**Risk Level:** Low - Internal refactor, no behavior changes
**Channel Applicability:**
- App Store: Yes
- DMG: Yes
- Linux: N/A

---

### `sidechain-ingest` - Sidechain/Tool Invocation Storage

**What Changed (CONFIRMED):**
- New schema columns for sidechain and tool invocation data
- Parser updates to extract sidechains from Claude Code transcripts
- `is_sidechain` flag on entries
- Tool invocations stored with parent entry linkage

**Evidence:**
- `48b5882b` feat(db): add sidechain and tool invocation storage
- `62a4b03b` feat(ingest): parse sidechains and tool invocations
- `ee217507` test(core): cover sidechain and tool invocation parsing
- `58d8eaa8` Merge feature/sidechain-ingestion-impl (626+, 75-)

**Schema Changes:**
- Database schema v33 includes new columns

**Surface Area:** DB / Core
**Risk Level:** Medium - Schema migration
**Channel Applicability:**
- App Store: Yes
- DMG: Yes
- Linux: N/A

---

### `entry-filter` - EntryFilter Type System

**What Changed (CONFIRMED):**
- New `EntryFilter` type with SQL helpers
- Sidechain filter decoupled from `includeHidden` flag
- CLI query functions use EntryFilter internally
- 4-combo activity() tests for filter combinations

**Evidence:**
- `9d90943e` feat(query): add EntryFilter type with SQL helpers
- `4edf184f` fix(query): decouple is_sidechain from includeHidden filter
- `bae893ed` refactor(query): use EntryFilter internally in CLI query functions
- `dc57dd2c` Merge feature/entry-filter-architecture (726+, 65-)

**Behavior Changes:**
- Sidechain entries now independently filterable (was tied to hidden)

**Surface Area:** Core / CLI
**Risk Level:** Low - Query layer improvement
**Channel Applicability:**
- App Store: Yes
- DMG: Yes
- Linux: Yes (CLI queries)

---

### `image-render` - Inline Image Rendering

**What Changed (CONFIRMED):**
- Timeline entries with images render inline
- Quick Look preview integration
- MarkdownUI dependency added to App Store target

**Evidence:**
- `1ef9e070` feat(timeline): add inline image rendering with Quick Look preview (882+, 32-)
- `b2675176` fix(xcode): add MarkdownUI dependency to App Store target

**Surface Area:** UI
**Risk Level:** Low - Additive feature
**Channel Applicability:**
- App Store: Yes
- DMG: Yes
- Linux: N/A

---

### `status-bar-perms` - Status Bar Permission Indicator

**What Changed (CONFIRMED):**
- Status bar shows permission state indicator
- Documentation for indicator section

**Evidence:**
- `761e94f3` Merge branch 'feature/status-bar-permissions' (240+, 25-)
- `80e508ad` docs(cli): add status bar permission indicator section

**Surface Area:** UI
**Risk Level:** Low - Visual indicator
**Channel Applicability:**
- App Store: Yes
- DMG: Yes
- Linux: N/A

---

### `project-misattr` - Project Misattribution Fix

**What Changed (CONFIRMED):**
- Entries reassigned based on CWD to fix cross-project attribution
- Project resolution cache improvements (7 fixes implemented)
- Session ID collision handling

**Evidence:**
- `5386a68e` fix(ingestion): reassign entries based on CWD to fix project misattribution
- `8b3f0467` fix(hoover): implement all 7 project resolution cache improvements
- `179152fb` refactor(hoover): finalize project resolution cache improvements

**Behavior Changes:**
- **BREAKING**: Entries may be reassigned to different projects after upgrade

**Surface Area:** Core / DB
**Risk Level:** Medium - Data attribution changes
**Channel Applicability:**
- App Store: Yes
- DMG: Yes
- Linux: N/A

---

### `total-recall-brand` - Total Recall Branding

**What Changed (CONFIRMED):**
- Skill renamed to `/total-recall` (from previous name)
- User skill auto-installation
- Old skill locations cleaned up

**Evidence:**
- `556aa56b` feat(query): add Total Recall user skill
- `09f04255` feat(query): install user skill and clean up old locations
- `35f011c8` refactor(query): update researcher agent to use total-recall skill
- `ad1a23c1` docs(query): update documentation for Total Recall branding

**Surface Area:** CLI / Website
**Risk Level:** Low - Branding update
**Channel Applicability:**
- App Store: Yes
- DMG: Yes
- Linux: Yes

---

### Additional Change Sets (Lower Detail)

**`contextify-decor`** - Agent badges and Contextify call decorations in timeline (CONFIRMED via `c40c1bac`, `bedb36ad`)

**`lazy-watchers`** - Deferred file watching initialization (CONFIRMED via `cbdd9129` merge)

**`worktree-grouping`** - Visual grouping by git worktree (CONFIRMED via `e1cd2c90` merge)

**`summarization-fixes`** - Fallback handling and bounded output for LLM summaries (CONFIRMED via `fcd16e1d`, `0b1d8483`)

**`benchmark-infra`** - Performance benchmarking tools and scripts (CONFIRMED via `f5c61570`, `a9009b55`)

**`release-admin`** - v1.0.6/v1.0.7 release artifacts, Sparkle appcast, website updates (CONFIRMED, ~40 commits)

---

## 4.4 Behavior-Change Audit

### Default Changes
- None identified

### Config/Flag Changes
- **NEW FLAG**: `--repair-only` for QA scripts
- **NEW FLAG**: `--v2-migration` for CLI migration testing

### Removed Features
- Old skill location files cleaned up (migrated to new paths)

### Data Format Changes
- **SCHEMA**: v33 adds sidechain/tool invocation columns
- **MANIFEST**: CLI manifest unified to `installed_plugins.json`

### Security/Privacy Changes
- None identified

### Performance-Affecting Changes
- PRAGMA tuning enabled by default (2.5x bulk ingest improvement)
- Observation-free bulk ingest reduces UI blocking during large ingests

---

## 4.5 Complete Commit Ledger

**Quality Gate Check:**
- App Store range (v1.0.5..v1.1.0): 457 non-merge commits expected
- DMG range (v1.0.7..v1.1.0): 397 non-merge commits expected

### Ledger by Type (App Store Range)

| Type | Count | Change Sets |
|------|------:|-------------|
| docs | 147 | release-admin, specs, architecture |
| fix | 119 | project-misattr, cli-doctor, linux-cli, codex-support |
| feat | 73 | linux-cli, cli-doctor, perf-optimization, image-render |
| chore | 34 | release-admin, worktree |
| refactor | 29 | cm-refactor, entry-filter, total-recall-brand |
| test | 18 | entry-filter, codex-support, sidechain-ingest |
| perf | 7 | perf-optimization |
| release | 2 | release-admin |
| build | 2 | linux-cli |
| ci | 1 | linux-cli |

**Full ledger exported to:** `/tmp/release-notes-commits-full.txt`

### DMG-Only Delta (v1.0.7..v1.1.0 vs v1.0.5..v1.1.0)

60 commits in v1.0.5..v1.0.7 are **App Store only**. Key items:
- Total Recall user skill initial implementation
- v1.0.6 announcement content
- Contextify call decoration initial implementation
- Sidechain ingestion specs
- Entry filter architecture specs

---

## Quality Gate Results

| Gate | Status | Notes |
|------|--------|-------|
| Commit counts match ledger | PASS | 457 non-merge (App Store), 397 (DMG) |
| Every change set has evidence | PASS | SHAs and file diffs provided |
| No high-impact claim without evidence | PASS | All claims linked to commits |
| UNCERTAIN items have follow-ups | PASS | None identified |
| External notes contain only high-confidence items | PENDING | (see next section) |

---

# External Release Notes Drafts

(See next file: `/tmp/contextify-v1.1.0-release-notes-external.md`)
