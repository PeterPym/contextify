# Documentation Audit Report

**Date:** 2025-11-17
**Auditor:** Claude (Sonnet 4.5)
**Scope:** Complete documentation surface area (150+ Markdown files)
**Branch:** claude/audit-documentation-01QpWg5HSFiLZzjZRp3p2Hhm

---

## Executive Summary

### Critical Findings

- **Current schema version is v26, but documentation claims v23** - Critical accuracy issue in `build/docs/architecture/sql-backend.md` and `AGENTS.md` that will mislead developers working with the database
- **Database filename inconsistency** - Root `README.md` incorrectly states `transcripts.db` when it was migrated to `contextify.db` (all other docs are correct)
- **Root README misaligned with current product focus** - Emphasizes iTerm2 integration and compose workflow (legacy features), while current app is primarily a transcript monitoring HUD for Claude Code/Codex CLI
- **AGENTS.md has incomplete placeholder sections** - Lines 203-204 contain TODO-style placeholders for Codex/Claude Code storage locations that should be filled in
- **Significant documentation duplication** - 15 standalone markdown files in `scripts/` overlap heavily with organized docs in `build/docs/guides/` and `build/docs/operations/`
- **Inconsistent information architecture** - Recent Nov 2025 reorganization to `build/docs/` was excellent, but execution is incomplete (duplication in scripts/, inconsistent cross-references, outdated root docs)
- **Strong foundation in place** - The `build/docs/` structure is well-organized with clear categorization; most technical architecture docs are accurate and high-quality

### Documentation Inventory

**Total Markdown files audited:** 150+

**Distribution:**
- Root-level: 4 files (README.md, AGENTS.md, CHANGELOG.md, CLAUDE.md symlink)
- `build/docs/`: 45+ files (well-organized)
- `build/docs/archive/`: 74 files (historical context)
- `build/notes/`: 16 files (mixed planning/historical)
- `scripts/`: 15 standalone docs (duplication with build/docs/)
- Package-level: 6 files (app/, Contextify/, Fixtures/)
- Other: 15+ files (.claude/commands/, design-assets/, website/, docs/)

### Quality Assessment

**Strengths:**
- ✅ `build/docs/architecture/` - Comprehensive, well-structured technical docs
- ✅ `build/docs/specifications/` - Excellent detailed format specifications
- ✅ `app/Sources/ContextifyCore/Database/README.md` - Outstanding usage guide
- ✅ `scripts/logging/README.md` - Comprehensive debugging toolkit
- ✅ Archive structure - Good separation of historical context

**Weaknesses:**
- ❌ Root README.md - Outdated product description, wrong database filename
- ❌ Schema version drift - Docs lag behind code (v23 vs v26)
- ❌ Duplication - scripts/ and build/docs/ overlap significantly
- ❌ Placeholders - Production docs contain TODO-style comments
- ❌ Cross-references - Inconsistent linking between related docs

---

## Proposed Documentation Structure

### Top-Level (Repository Root)

```
contextify/
├── README.md           # Project overview, quickstart (NEEDS REWRITE)
├── AGENTS.md           # AI agent guidelines (FIX placeholders & version)
├── CHANGELOG.md        # Release history (KEEP as-is)
├── CONTRIBUTING.md     # NEW: Extract from AGENTS.md for human contributors
└── LICENSE
```

### Core Documentation Hub

```
build/docs/             # KEEP existing structure (well-designed)
├── README.md           # Central index (KEEP as-is)
├── architecture/       # System design (UPDATE sql-backend.md)
├── components/         # Subsystem details (KEEP as-is)
├── specifications/     # External formats (ADD codex-cli-format.md)
├── guides/             # How-to docs (KEEP as-is)
├── testing/            # QA workflows (KEEP as-is)
├── design/             # Design decisions (KEEP as-is)
├── operations/         # Deployment & release (MOVE scripts/*.md here)
└── archive/            # Historical context (ADD README.md)
```

### Scripts Documentation

```
scripts/
├── README.md           # CONSOLIDATE: Index with links to build/docs/
├── logging/
│   └── README.md       # KEEP: Comprehensive logging toolkit
└── [Remove standalone docs, move to build/docs/]
```

### Package-Level

```
app/Sources/ContextifyCore/Database/README.md  # KEEP: Excellent usage guide
Contextify/README.md                           # UPDATE: Refresh for current structure
Fixtures/transcripts/README.md                 # KEEP: Test fixtures
```

---

## Per-File Audit

### Root Documentation

#### README.md
- **Path:** `/README.md`
- **Status:** Keep but major update required
- **Issues:**
  - **Line 205**: Database location is wrong (`transcripts.db` should be `contextify.db`)
  - **Lines 1-3**: Opening description emphasizes "iTerm2 integration" when primary value is transcript monitoring
  - **Lines 5-9**: "Core Workflow" describes outdated keyboard-capture workflow
  - **Lines 135-199**: Dedicates 65 lines to transcript conversion (Phase 1 feature), overshadowing core features
  - Missing clear explanation of what Contextify actually does (monitor Claude Code/Codex transcripts with LLM summaries)
  - **Good:** Architecture notes section (202-260) is accurate
- **Recommended changes:**
  - **CRITICAL: Fix database filename** (line 205): `transcripts.db` → `contextify.db`
  - **Rewrite opening** (lines 1-11): Focus on transcript monitoring as primary feature
  - **Add "What is Contextify?" section** before Quickstart explaining:
    - Automatic discovery of Claude Code/Codex transcripts
    - Real-time timeline monitoring
    - LLM-powered summaries
    - Multi-project support
  - **Restructure feature priorities**: Move transcript conversion to appendix
  - **De-emphasize or remove** iTerm2/compose features if they're legacy (verify with maintainer)
- **See:** Example rewrite in "Example Edits" section below

#### AGENTS.md
- **Path:** `/AGENTS.md`
- **Status:** Keep but update
- **Issues:**
  - **Line 103**: References schema "v23" but actual version is v26 (verified in `DatabaseSchema.swift:13`)
  - **Lines 203-204**: Placeholder comments in production doc:
    ```markdown
    - [Put actual codex storage locaion here to be explicit this is so important]
    - [same for CC]
    ```
  - **Good:** Line 173 correctly states database is `contextify.db`
- **Recommended changes:**
  - **Update schema version**: Line 103 should say "DatabaseSchema.swift - Current schema (v26)"
  - **Fill in placeholders** (lines 203-204) with actual paths:
    - Claude Code: `~/.claude/projects/<project-hash>/*.jsonl`
    - Codex CLI: `~/.codex/sessions/YYYY/MM/DD/*.jsonl`
  - **Add cross-reference** to `build/docs/specifications/transcript-formats.md` for detailed specs
- **See:** Example edit in "Example Edits" section below

#### CHANGELOG.md
- **Path:** `/CHANGELOG.md`
- **Status:** Keep as-is ✅
- **Issues:** None
- **Recommended changes:** None - well-maintained, follows semantic versioning guidelines

#### CLAUDE.md
- **Path:** `/CLAUDE.md` (symlink to AGENTS.md)
- **Status:** Keep as-is ✅
- **Issues:** None
- **Recommended changes:** None

---

### Package-Level Documentation

#### Contextify/README.md
- **Path:** `/Contextify/README.md`
- **Status:** Keep but update
- **Issues:**
  - References "Phase 2 Features" (line 21) - outdated planning terminology
  - Describes `outputs/` directory and file ingestion (lines 14, 23-24) - verify these features still exist
  - Minimal documentation (40 lines) for entire Xcode project
  - No mention of transcript monitoring (primary feature per AGENTS.md)
- **Recommended changes:**
  - **Verify feature accuracy**: Confirm if file drop, URL ingest, and `outputs/` still exist
  - **Add transcript monitoring section**: Explain ConversationMonitor, timeline view, LLM summaries
  - **Update "Phase 2" terminology**: Replace with current feature status
  - **Cross-reference**: Link to `build/docs/architecture/COMPONENTS.md`

#### app/Sources/ContextifyCore/Database/README.md
- **Path:** `/app/Sources/ContextifyCore/Database/README.md`
- **Status:** Keep as-is ✅
- **Issues:** None - excellent usage guide with accurate code examples
- **Recommended changes:**
  - **Minor clarification**: Lines 240-256 reference "schema v6" - add note that this refers to "design iteration 6" not migration version (current is v26)

#### Fixtures/transcripts/README.md
- **Path:** `/Fixtures/transcripts/README.md`
- **Status:** Keep as-is ✅ (assumed)
- **Issues:** Not reviewed in detail (test fixtures)
- **Recommended changes:** None

---

### build/docs/ - Core Documentation

#### build/docs/README.md
- **Path:** `/build/docs/README.md`
- **Status:** Keep as-is ✅
- **Issues:** None
- **Recommended changes:** None - well-organized index created during Nov 2025 reorganization

#### build/docs/architecture/sql-backend.md
- **Path:** `/build/docs/architecture/sql-backend.md`
- **Status:** Keep but update
- **Issues:**
  - **CRITICAL - Line 4**: Says "Schema Version: 23 (v21-v23...)" but actual version is 26 (verified in `DatabaseSchema.swift:13`)
  - **Line 24**: Says "Schema Design (v6)" - confusing dual versioning (design iteration vs migration version)
  - References to "v6" throughout (lines 54, 71) could be misinterpreted as schema version
- **Recommended changes:**
  - **Fix schema version**: Line 4 should say "Schema Version: 26 (current)"
  - **Add versioning note**: Clarify that "v6" = design iteration, "v26" = migration version
  - **Add migration history reference**: "See DatabaseSchema.swift for complete migration history v16-v26"
- **See:** Example edit in "Example Edits" section below

#### build/docs/architecture/COMPONENTS.md
- **Path:** `/build/docs/architecture/COMPONENTS.md`
- **Status:** Keep as-is ✅ (not fully reviewed)
- **Issues:** None found in spot-check
- **Recommended changes:** None

#### build/docs/specifications/transcript-formats.md
- **Path:** `/build/docs/specifications/transcript-formats.md`
- **Status:** Keep as-is ✅
- **Issues:** None - comprehensive, accurate technical specification
- **Recommended changes:**
  - **Enhancement**: Add explicit storage paths at top of each section for quick reference

#### build/docs/guides/DEVELOPMENT.md
- **Path:** `/build/docs/guides/DEVELOPMENT.md`
- **Status:** Keep as-is ✅
- **Issues:** None
- **Recommended changes:** None - comprehensive, accurate, well-organized

---

### scripts/ - Script Documentation

**CRITICAL: Significant duplication with build/docs/**

15 standalone markdown files in `scripts/` overlap with organized documentation in `build/docs/guides/` and `build/docs/operations/`. This creates maintenance burden and version drift risk.

#### scripts/README.md
- **Path:** `/scripts/README.md`
- **Status:** Keep but consolidate
- **Issues:**
  - Only documents 4 scripts (migrate-transcripts, analyze_intent, generate_intent, xc.sh)
  - 15 standalone markdown files exist that aren't indexed here
  - Heavy duplication with `build/docs/`
- **Recommended changes:**
  - **Option A (Recommended)**: Convert to index-only README with links to `build/docs/guides/`
  - **Option B**: Keep standalone docs but add clear "authoritative source" headers
- **See:** Example consolidated README in "Example Edits" section

#### scripts/CI-TRIGGER-README.md
- **Status:** Merge into build/docs/guides/linux-ci-builds.md, then delete
- **Issues:** Duplicates content in `build/docs/guides/linux-ci-builds.md`

#### scripts/CLAUDE-CODE-WEB-CI-GUIDE.md
- **Status:** Merge into build/docs/guides/linux-ci-builds.md, then delete
- **Issues:** Specific to Claude Code Web - belongs with linux-ci-builds guide

#### scripts/DATABASE-MANAGEMENT.md
- **Status:** Merge into build/docs/operations/DATABASE-LOCATIONS.md, then delete
- **Issues:** Duplicates operations docs

#### scripts/LOG-CAPTURE-README.md
- **Status:** Merge into scripts/logging/README.md, then delete
- **Issues:** `scripts/logging/README.md` is more comprehensive

#### scripts/LOG-SETUP-SUMMARY.md
- **Status:** Merge into scripts/logging/README.md, then delete
- **Issues:** Redundant with logging/README.md

#### scripts/RELEASE.md
- **Status:** Move to build/docs/operations/release/RELEASE-PROCESS.md
- **Issues:** Operations doc in wrong location

#### scripts/SIGNING-SETUP.md
- **Status:** Move to build/docs/operations/release/ or merge with notarization docs
- **Issues:** Part of release operations

#### scripts/CODEX_REQUIREMENTS_FINAL.md, scripts/CODEX_SESSION_FORMAT.md, scripts/CODEX_SESSION_REQUIREMENTS.md
- **Status:** Consolidate into build/docs/specifications/codex-cli-format.md
- **Issues:** 3 separate files for same topic, should be unified specification

#### scripts/TRANSCRIPT_CONVERTER_README.md
- **Status:** Keep (script-specific) ✅
- **Issues:** None
- **Recommended changes:** Update root README.md to link here instead of duplicating content

#### scripts/QUICK-REFERENCE.md
- **Status:** Delete or merge into build/docs/guides/DEVELOPMENT.md
- **Issues:** Duplicates DEVELOPMENT.md

#### scripts/REVIEW-PREP-README.md
- **Status:** Delete (internal workflow doc)
- **Issues:** Agent session prep doc - belongs in `/tmp/` or git-ignored notes

#### scripts/TEST_TRANSCRIPT_LOCATIONS.md
- **Status:** Move to build/docs/testing/transcript-test-fixtures.md
- **Issues:** Testing doc in wrong location

#### scripts/logging/README.md
- **Path:** `/scripts/logging/README.md`
- **Status:** Keep as-is ✅
- **Issues:** None
- **Recommended changes:** Update AGENTS.md to reference this as primary logging docs (currently references less complete guide)

---

### build/notes/ - Planning & Historical

**Status:** Mixed - some active planning, some historical artifacts

16 markdown files with inconsistent purpose and lifecycle.

**Recommended actions:**

- **TODOS.md, TODOS-backup.md**: Keep (active planning)
- **PR-DESCRIPTION.md, SESSION-HANDOFF-*.md**: Delete (ephemeral, should be in /tmp/)
- **RELEASE-NOTES-*.md**: Move to `build/docs/operations/release/notes/`
- **CODE-AUDIT-REPORT.md, TECHNICAL-DOCS-AUDIT-*.md**: Move to `build/docs/archive/investigations/`
- **future-features.md**: Keep OR move to GitHub Issues
- **transcript-window-refactor-*.md, viewport-aware-*.md, welcome-modal-audit-*.md, transcript-view-ui-inconsistencies.md**: Move to `build/docs/archive/investigations/`
- **website-launch-status.md**: Move to `build/docs/operations/marketing/` or delete if outdated

---

### build/docs/archive/

**Status:** Keep structure ✅

74 archived files providing historical context - appropriate use of archive.

**Recommended changes:**
- Add `build/docs/archive/README.md` explaining archive purpose
- Spot-check for files referencing `transcripts.db` and add migration notes

---

### Other Directories

#### docs/ (Apple knowledge, roadmap)
- **Issue:** Confusing to have both `docs/` and `build/docs/`
- **Recommended changes:**
  - **Option A**: Rename `docs/` to `reference/` or `external-docs/`
  - **Option B**: Move content into `build/docs/` and delete `docs/`
  - `docs/roadmap/initial-contextify-swift-macos-setup.md`: Archive or delete

#### design-assets/README.md
- **Status:** Not reviewed
- **Issues:** Unknown
- **Recommended changes:** Audit separately if in scope

#### website/README.md
- **Status:** Not reviewed in detail
- **Issues:** None found
- **Recommended changes:** Ensure cross-referenced from `build/docs/operations/WEBSITE.md`

#### .claude/commands/*.md
- **Status:** Keep as-is ✅
- **Issues:** None
- **Recommended changes:** None (slash command definitions)

---

## New or Missing Documentation

### 1. CONTRIBUTING.md (Root)
- **Purpose:** Contributor guide for human developers (extracted from AGENTS.md)
- **Location:** `/CONTRIBUTING.md`
- **Outline:**
  - Code of conduct reference
  - Development environment setup
  - Running tests
  - Commit message conventions
  - Pull request process
  - Code review expectations
  - Link to AGENTS.md for AI-specific guidelines

### 2. build/docs/architecture/CURRENT-FEATURES.md
- **Purpose:** Single source of truth for "what features are shipped?"
- **Location:** `/build/docs/architecture/CURRENT-FEATURES.md`
- **Outline:**
  - Feature matrix (shipped vs planned)
  - Primary workflows (transcript monitoring, project switching, timeline view)
  - Legacy features status (iTerm2 integration, compose panel - active?)
  - Known limitations
  - Links to detailed architecture docs

### 3. build/docs/operations/DOCUMENTATION-MAINTENANCE.md
- **Purpose:** Guidelines to prevent future documentation drift
- **Location:** `/build/docs/operations/DOCUMENTATION-MAINTENANCE.md`
- **Outline:**
  - Documentation lifecycle (when/where to document, when to archive)
  - Required docs for new features
  - Schema version update checklist
  - Cross-reference audit process
  - Duplication prevention

### 4. build/docs/specifications/codex-cli-format.md
- **Purpose:** Consolidate 3 Codex specification files from scripts/
- **Location:** `/build/docs/specifications/codex-cli-format.md`
- **Outline:**
  - Storage location and discovery
  - JSONL record format
  - Session metadata
  - Comparison with Claude Code format
  - Parser implementation reference

### 5. build/docs/guides/QUICKSTART.md
- **Purpose:** Get developers productive in 5 minutes
- **Location:** `/build/docs/guides/QUICKSTART.md`
- **Outline:**
  - Prerequisites (Xcode 16, macOS 15+)
  - Clone and build (3 commands)
  - Launch and grant permissions
  - Verify transcript discovery
  - Next steps (links to detailed guides)

### 6. build/docs/archive/README.md
- **Purpose:** Explain archive purpose and contents
- **Location:** `/build/docs/archive/README.md`
- **Outline:**
  - What belongs in archive (historical context, design rationale)
  - How to find current docs (link to build/docs/README.md)
  - Archive organization (investigations/, feature-specs/, completed-work/)

---

## Example Edits

### 1. README.md - Corrected Opening Section

**Current (lines 1-28):**
```markdown
# Contextify - Claude Code Terminal Integration

Contextify is a macOS HUD that bridges Claude Code CLI sessions in iTerm2 with a compose interface for reviewing and editing AI interactions. Built with Swift 6 + SwiftUI on Xcode 16 (macOS 26 SDK).

## Core Workflow
1. Work with Claude Code in iTerm2
2. Press **Cmd+Shift+K+K** to capture terminal content
3. Review/edit in Contextify compose panel
4. Send back to iTerm2 (or undo with **Cmd+Z** in iTerm2)

## Key Features

### Terminal Integration
- **Global hotkey capture**: Cmd+Shift+K+K grabs terminal content system-wide
- **iTerm2 integration**: Python daemon + AppleScript fallback for terminal reading
...
```

**Proposed (rewrite lines 1-50):**
```markdown
# Contextify

**A macOS HUD for monitoring Claude Code and Codex CLI conversations with real-time LLM-powered timeline summaries.**

Contextify automatically discovers and indexes your AI coding assistant transcripts, providing a persistent timeline view that helps you understand conversation flow, track task completion, and navigate across sessions. Built with Swift 6 + SwiftUI on Xcode 16 (macOS 26 SDK).

## What is Contextify?

- **Automatic Discovery**: Scans `~/.claude/projects/` and `~/.codex/sessions/` to find all your AI assistant conversations
- **Real-Time Monitoring**: Watches active transcripts and updates timeline as conversation progresses
- **LLM Summaries**: Generates natural-language summaries of each conversation turn using Apple Intelligence (macOS 26.0+) or legacy on-device models
- **Multi-Project Support**: Switch between projects, browse conversation history, and track unread messages
- **Persistent Database**: SQLite backend (v26) with crash-safe ingestion and fast querying

## Quickstart

### Requirements
- Xcode 16+ (beta OK)
- macOS 15+ runtime (macOS 26+ for Apple Intelligence summaries)
- Active Claude Code or Codex CLI sessions (transcripts in `~/.claude/` or `~/.codex/`)

### Build & Run
```bash
# Build (auto-detects Xcode-beta if installed)
make build
# or
bash scripts/xc.sh build

# Run in Xcode
open Contextify/Contextify.xcodeproj
# Select scheme: Contextify
# Run on: My Mac
```

First launch: Contextify will request permissions to access `~/.claude/` and `~/.codex/` directories. Grant access to enable transcript monitoring.

**Next steps:** See [DEVELOPMENT.md](build/docs/guides/DEVELOPMENT.md) for detailed build commands and [architecture docs](build/docs/architecture/) for technical deep-dive.

## Key Features

### Transcript Monitoring
- Real-time file watching with automatic ingestion
- Supports Claude Code (`.jsonl`) and Codex CLI (`.jsonl`) formats
- Parse error isolation (bad lines don't block ingestion)
- Crash-safe checkpointing and resume

### Timeline View
- Conversation timeline with user/assistant/system messages
- LLM-generated summaries with disposition classification (directive, completion, question, etc.)
- Cached summaries for instant loading (content+window hash-based invalidation)
- Provider-specific branding (Claude Code: orange, Codex CLI: blue)

### Project Management
- Multi-project discovery with git integration
- Unread message tracking
- Project switcher UI
- Git branch display and monitoring
```

**Line 205 database fix:**
```markdown
# BEFORE:
- **Location**: `~/Library/Application Support/Contextify/transcripts.db`

# AFTER:
- **Location**: `~/Library/Application Support/Contextify/contextify.db`
```

---

### 2. AGENTS.md - Fix Schema Version and Placeholders

**Current (lines 101-104):**
```markdown
**Database work:**
- `build/docs/architecture/sql-backend.md` - Schema, migrations, repositories
- `build/docs/architecture/COMPONENTS.md` - Database layer components
- `build/docs/operations/DATABASE-LOCATIONS.md` - Custom locations, discovery
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - Current schema (v23)
```

**Proposed:**
```markdown
**Database work:**
- `build/docs/architecture/sql-backend.md` - Schema, migrations, repositories
- `build/docs/architecture/COMPONENTS.md` - Database layer components
- `build/docs/operations/DATABASE-LOCATIONS.md` - Custom locations, discovery
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - Current schema (v26)
```

**Current (lines 200-205):**
```markdown
**IMPORTANT:** For all transcript work, **ALWAYS consult** `build/docs/specifications/transcript-formats.md` FIRST
- Storage locations (Claude Code vs Codex)
  - [Put actual codex storage locaion here to be explicit this is so important]
  - [same for CC]

- Project discovery (directory vs `cwd` field)
```

**Proposed:**
```markdown
**IMPORTANT:** For all transcript work, **ALWAYS consult** `build/docs/specifications/transcript-formats.md` FIRST

**Storage locations (Claude Code vs Codex):**
- **Claude Code**: `~/.claude/projects/<project-hash>/<session-uuid>.jsonl`
  - Project hash format: Path with `/` → `-` (e.g., `/Users/rob/code/contextify` → `-Users-rob-code-contextify`)
  - Each project directory contains multiple session files (one `.jsonl` per session)
- **Codex CLI**: `~/.codex/sessions/YYYY/MM/DD/<session-name>.jsonl`
  - Date-based hierarchy (year/month/day directories)
  - Session name includes timestamp and UUID
  - Example: `~/.codex/sessions/2025/11/17/my-feature-2025-11-17T14-30-00-<uuid>.jsonl`

**Project discovery:**
- Claude Code: Project path encoded in directory name
- Codex CLI: Project path in `cwd` field of each record
```

---

### 3. build/docs/architecture/sql-backend.md - Correct Schema Version

**Current (lines 1-8):**
```markdown
# SQL Backend Architecture

**Status:** Post-Implementation (v23 current)
**Database:** SQLite via GRDB.swift
**Schema Version:** 23 (v21-v23: access metadata, strategy constraint fix, active transcript follow)
**Related:** `app/Sources/ContextifyCore/Database/README.md` (usage guide)

---

## System Overview
```

**Proposed:**
```markdown
# SQL Backend Architecture

**Status:** Post-Implementation (v26 current)
**Database:** SQLite via GRDB.swift
**Schema Version:** 26 (latest: removed sandbox container path projects)
**Related:** `app/Sources/ContextifyCore/Database/README.md` (usage guide)

**Schema versioning note:** References to "v6" in this doc refer to the 6th design iteration (denormalization cleanup), while v26 is the current migration version. See `DatabaseSchema.swift` for complete migration history (v16-v26).

---

## System Overview
```

---

### 4. scripts/README.md - Consolidated Index

**Current (118 lines with detailed examples)**

**Proposed (concise index with cross-references):**
```markdown
# Contextify Scripts

Utility scripts for Contextify development and operations.

## Quick Reference

**Most common commands:**
```bash
# Build and run
bash scripts/xc.sh build

# Run tests
bash scripts/xc.sh test

# Trigger CI build from Linux/Claude Code Web
./scripts/trigger-ci-build.sh Debug

# Manage database
./scripts/db_manager.sh

# Convert transcripts between CLI formats
./scripts/convert_transcript.py --from claude-code --to codex <input> <output>
```

## Comprehensive Guides

**For detailed documentation, see:**
- **Development**: [build/docs/guides/DEVELOPMENT.md](../build/docs/guides/DEVELOPMENT.md) - Build, test, CI
- **Database**: [build/docs/operations/DATABASE-LOCATIONS.md](../build/docs/operations/DATABASE-LOCATIONS.md) - Database management
- **Release**: [build/docs/operations/release/](../build/docs/operations/release/) - Release workflow
- **Logging**: [scripts/logging/README.md](./logging/README.md) - Complete logging toolkit
- **Transcript formats**: [build/docs/specifications/transcript-formats.md](../build/docs/specifications/transcript-formats.md)

## Script Reference

### Build & Development
- **xc.sh** - Xcode build wrapper with auto-detection
- **trigger-ci-build.sh** - On-demand GitHub Actions builds (Linux/Web environments)

### Database & Transcripts
- **db_manager.sh** - Safe database operations (never use `rm` directly)
- **migrate-transcripts.sh** - Migrate transcripts when project path changes
- **convert_transcript.py** - Convert between Claude Code ↔ Codex CLI formats
- **classify_transcript.sh** - Identify transcript format and metadata

### Analysis & Diagnostics
- **analyze_intent_classification.sh** - Survey timeline cache for placeholder summaries
- **generate_intent_improvements.py** - Generate code recommendations for intent patterns
- **timeline_api.sh** - Query diagnostics API (DEBUG builds only)

### Deployment
- **deploy-website.sh** - Deploy contextify.sh static site
- **install-shell-bindings.sh** - Install shell integration (if using compose features)

## Adding New Scripts

1. Create script with `.sh` or `.py` extension
2. Add shebang and usage documentation in header comments
3. Update this README with one-line description
4. If the script relates to operations/testing/architecture, consider creating docs in `build/docs/`
```

---

## Verification Against Codebase

### Schema Version Verification

**Documentation claims:**
- `build/docs/architecture/sql-backend.md:4` - "Schema Version: 23"
- `AGENTS.md:103` - "Current schema (v23)"

**Actual code:**
```swift
// app/Sources/ContextifyCore/Database/DatabaseSchema.swift:13
static let version = 26
```

**Verdict:** ❌ Documentation is INCORRECT (3 versions behind)

### Database Filename Verification

**Documentation claims:**
- `README.md:205` - `transcripts.db`
- `AGENTS.md:173` - `contextify.db`
- `app/Sources/ContextifyCore/Database/README.md` - `contextify.db`
- `build/docs/` - `contextify.db` (consistently)

**Actual code:**
```swift
// app/Sources/ContextifyCore/Database/DatabaseManager.swift:202
return contextifyDir.appendingPathComponent("contextify.db")

// app/Sources/ContextifyCore/Database/DatabaseManager.swift:174-190
// Migration: transcripts.db → contextify.db
let oldPath = contextifyDir.appendingPathComponent("transcripts.db")
let newPath = contextifyDir.appendingPathComponent("contextify.db")
```

**Verdict:** ❌ Root README.md is INCORRECT (only file with wrong filename)

### Key Entry Points Verification

**Documentation claims (AGENTS.md:81-86):**
- `HUDViewModel` - Main app coordinator
- `StartupCoordinator` - Project identity pipeline
- `TranscriptOrchestrator` - Database API
- `ConversationMonitor` - Timeline display
- `DatabaseManager` - Singleton for GRDB

**Actual code:**
```bash
$ find . -name "StartupCoordinator.swift" -o -name "TranscriptOrchestrator.swift"
./app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift
./app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift
```

**Verdict:** ✅ Documentation is CORRECT (files exist at expected locations)

---

## Implementation Recommendations

### Phase 1: Critical Fixes (Immediate)

**Priority 1 - Accuracy Issues:**
1. Fix schema version in `build/docs/architecture/sql-backend.md` (v23 → v26)
2. Fix schema version in `AGENTS.md` (v23 → v26)
3. Fix database filename in `README.md` (transcripts.db → contextify.db)
4. Fill in placeholders in `AGENTS.md` lines 203-204

**Estimated effort:** 30 minutes
**Impact:** Critical - prevents misleading developers

### Phase 2: Root Documentation Refresh (High Priority)

**Priority 2 - Alignment Issues:**
1. Rewrite `README.md` opening section (focus on transcript monitoring)
2. Restructure `README.md` feature sections (de-emphasize legacy features)
3. Update `Contextify/README.md` (remove Phase 2 terminology, add current features)

**Estimated effort:** 2-3 hours
**Impact:** High - ensures accurate product representation

### Phase 3: Consolidation (Strategic)

**Priority 3 - Information Architecture:**
1. Consolidate `scripts/` standalone docs into `build/docs/`
2. Rewrite `scripts/README.md` as index with cross-references
3. Move misplaced docs to appropriate `build/docs/` locations
4. Create missing docs (CONTRIBUTING.md, codex-cli-format.md, archive/README.md)

**Estimated effort:** 4-6 hours
**Impact:** Medium - reduces maintenance burden, improves discoverability

### Phase 4: Enhancements (Low Priority)

**Priority 4 - Quality Improvements:**
1. Add `build/docs/architecture/CURRENT-FEATURES.md`
2. Add `build/docs/operations/DOCUMENTATION-MAINTENANCE.md`
3. Add `build/docs/guides/QUICKSTART.md`
4. Audit `build/notes/` and move files to appropriate locations
5. Resolve `docs/` vs `build/docs/` naming conflict

**Estimated effort:** 3-4 hours
**Impact:** Low - nice-to-have improvements

---

## Conclusion

The Contextify documentation has a **strong foundation** with the well-organized `build/docs/` structure, but suffers from:
1. **Critical accuracy issues** (schema version, database filename)
2. **Outdated root documentation** (README.md misaligned with current product)
3. **Organizational inconsistency** (duplication between scripts/ and build/docs/)

The November 2025 reorganization created an excellent structure, but execution is incomplete. Implementing Phase 1 (30 minutes) will fix critical issues immediately. Phases 2-3 will bring documentation into full alignment with the codebase and current product vision.

**Key strength:** Technical architecture documentation (`build/docs/architecture/`, `specifications/`, `guides/`) is high-quality and mostly accurate.

**Key weakness:** Entry-point documentation (root README.md, AGENTS.md) contains inaccuracies that will mislead new developers and AI agents.

---

## Appendix: Files by Status

### Keep As-Is ✅ (High Quality)
- CHANGELOG.md
- build/docs/README.md
- build/docs/guides/DEVELOPMENT.md
- build/docs/specifications/transcript-formats.md
- app/Sources/ContextifyCore/Database/README.md
- scripts/logging/README.md
- scripts/TRANSCRIPT_CONVERTER_README.md

### Update (Fix Inaccuracies) ⚠️
- README.md - Wrong database filename, outdated focus
- AGENTS.md - Wrong schema version, placeholders
- build/docs/architecture/sql-backend.md - Wrong schema version
- Contextify/README.md - Outdated terminology

### Consolidate/Move 📦
- scripts/CI-TRIGGER-README.md → build/docs/guides/linux-ci-builds.md
- scripts/CLAUDE-CODE-WEB-CI-GUIDE.md → build/docs/guides/linux-ci-builds.md
- scripts/DATABASE-MANAGEMENT.md → build/docs/operations/DATABASE-LOCATIONS.md
- scripts/RELEASE.md → build/docs/operations/release/
- scripts/SIGNING-SETUP.md → build/docs/operations/release/
- scripts/CODEX_*.md (3 files) → build/docs/specifications/codex-cli-format.md
- scripts/QUICK-REFERENCE.md → build/docs/guides/DEVELOPMENT.md

### Delete 🗑️
- scripts/REVIEW-PREP-README.md (internal workflow)
- scripts/LOG-CAPTURE-README.md (redundant with logging/README.md)
- scripts/LOG-SETUP-SUMMARY.md (redundant)
- build/notes/PR-DESCRIPTION.md (ephemeral)
- build/notes/SESSION-HANDOFF-*.md (ephemeral)

### Create (Missing) 📝
- CONTRIBUTING.md (root)
- build/docs/architecture/CURRENT-FEATURES.md
- build/docs/operations/DOCUMENTATION-MAINTENANCE.md
- build/docs/specifications/codex-cli-format.md
- build/docs/guides/QUICKSTART.md
- build/docs/archive/README.md
