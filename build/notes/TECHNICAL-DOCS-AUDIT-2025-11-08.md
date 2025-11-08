# Technical Documentation Audit & Reorganization Plan

**Date:** 2025-11-08
**Scope:** `build/notes/technical-reference/` directory
**Status:** Comprehensive audit complete - reorganization plan included

---

## Executive Summary

Audit of 20 technical reference documents (totaling 409KB) reveals:

### Key Findings
- ✅ **13 files** (65%) are current, accurate, and well-organized
- ⚠️ **3 files** (15%) need to be archived (investigation docs for resolved issues)
- 📦 **4 files** (20%) should be broken down (>30KB each, multiple topics)
- 🔄 **File naming inconsistent** - mix of kebab-case and descriptions

### Priority Actions
1. **Move to archive:** 3 resolved investigation docs (saves 103KB from active docs)
2. **Break down:** 4 large files into focused topic documents
3. **Standardize naming:** kebab-case + topical grouping
4. **Create index:** Central README.md with categorized links

---

## File-by-File Audit

### 📊 Size Distribution

| Size Range | Count | Files |
|------------|-------|-------|
| 4-10 KB    | 7     | Small, focused docs (ideal)
| 11-20 KB   | 6     | Medium docs (good)
| 21-40 KB   | 4     | Large (consider breaking down)
| 90+ KB     | 3     | Very large (MUST break down)

### 🔍 Detailed Analysis

#### 1. `transcript-inventory-db-integration-gap.md` (91KB)
**Status:** ⚠️ **NEEDS BREAKING DOWN**
- **Current:** Analysis doc for unresolved feature (Transcript Inventory SQL integration)
- **Issue:** Still relevant - feature NOT implemented yet
- **Size:** 2,723 lines - WAY too large
- **Action:** Break into:
  - `transcript-inventory-sql-migration-spec.md` - Problem statement + architecture (10KB)
  - `transcript-inventory-implementation-plan.md` - Step-by-step plan (15KB)
  - Move verbose analysis/debugging to `archive/` or delete

#### 2. `data-flow-complete.md` (52KB, 1,182 lines)
**Status:** ✅ **KEEP - but consider splitting**
- **Date:** 2025-10-22
- **Current:** Comprehensive architectural reference (WORKING)
- **Accuracy:** UP TO DATE - correctly describes 5-stage pipeline
- **Action:** Could optionally split into:
  - `data-flow-overview.md` - High-level pipeline (10KB)
  - `data-flow-detailed.md` - Per-stage deep dive (40KB)
- **Recommendation:** Keep as-is for now (single comprehensive reference is valuable)

#### 3. `window-architectures.md` (36KB, 1,230 lines)
**Status:** ⚠️ **PARTIALLY OUTDATED - archive sections**
- **Date:** 2025-10-22
- **Issue:** References iTerm2 integration (REMOVED in commit 35ce380)
- **Action:**
  - Remove iTerm2 sections
  - Update to reflect current 4-window architecture
  - Move historical iTerm2 content to `archive/macos-ux-hig-window-types.md`
- **Estimated new size:** 25KB after cleanup

#### 4. `cxt-10-11-main-thread-blocking-investigation.md` (33KB, 978 lines)
**Status:** 📦 **MOVE TO ARCHIVE**
- **Date:** November 5, 2025
- **Status in doc:** ✅ RESOLVED
- **Reason:** Investigation complete, issue fixed in commit 086bdb0
- **Value:** Historical debugging reference, not active development
- **Action:** Move to `archive/investigations/cxt-10-11-main-thread-blocking.md`

#### 5. `transcript-ingestion-pipeline.md` (30KB)
**Status:** ✅ **KEEP**
- **Accuracy:** Current, describes HooverEngine correctly
- **Action:** None needed

#### 6. `claude-code-transcript-format.md` (24KB)
**Status:** ✅ **KEEP**
- **Purpose:** Format specification reference
- **Accuracy:** Current
- **Action:** None needed

#### 7. `timeline-cache-llm-architecture.md` (20KB)
**Status:** ✅ **KEEP**
- **Purpose:** LLM processing pipeline architecture
- **Accuracy:** Current
- **Action:** None needed

#### 8. `project-discovery-implementation.md` (20KB)
**Status:** ✅ **KEEP**
- **Purpose:** Project discovery system architecture
- **Accuracy:** Current
- **Action:** None needed

#### 9. `sql-backend-architecture.md` (19KB)
**Status:** ⚠️ **NEEDS UPDATE**
- **Issue:** Shows schema v11, current is v21
- **Referenced in:** TODOS.md line 285 (update needed)
- **Action:** Add v12-v21 migrations section
- **Estimated work:** 2-3 hours to document 10 migrations

#### 10. `conversation-monitor-state-architecture.md` (18K)
**Status:** ✅ **KEEP**
- **Purpose:** Timeline state management
- **Accuracy:** Current
- **Action:** None needed

#### 11. `timeline-diagnostics-framework.md` (16KB)
**Status:** ✅ **KEEP**
- **Purpose:** HTTP diagnostics API (`/health`, `/diagnostics`, etc.)
- **Accuracy:** Current
- **Action:** None needed

#### 12. `llm-processing-architecture.md` (16KB)
**Status:** ✅ **KEEP**
- **Purpose:** Dual-queue LLM architecture overview
- **Accuracy:** Current (references TimelineCacheMissGenerator + TranscriptMetadataOrchestrator)
- **Action:** None needed

#### 13. `technical-brief-transcript-inventory-codex-support.md` (14KB)
**Status:** ✅ **KEEP**
- **Purpose:** Codex CLI support implementation brief
- **Accuracy:** Current
- **Action:** None needed

#### 14. `startup-coordinator-architecture.md` (13KB)
**Status:** ✅ **KEEP**
- **Purpose:** StartupCoordinator design doc
- **Accuracy:** Current (feature IMPLEMENTED in commit 531ac70)
- **Note:** TODOS.md incorrectly says "Planned" - should reference this doc
- **Action:** None for this file (TODOS.md already fixed)

#### 15. `intent-classification-analysis.md` (12KB)
**Status:** 📦 **MOVE TO ARCHIVE**
- **Purpose:** Analysis of timeline summary intent classification improvements
- **Date:** 2025-11-03
- **Status:** COMPLETE - improvements shipped in commits 7493bec through 1755813
- **Value:** Historical analysis, not active development
- **Action:** Move to `archive/analyses/intent-classification-2025-11-03.md`

#### 16. `diagnostics-api-usage.md` (7.9KB)
**Status:** ✅ **KEEP**
- **Purpose:** HTTP API usage guide
- **Accuracy:** Current
- **Action:** None needed

#### 17. `linux-ci-builds.md` (7.0KB)
**Status:** ✅ **KEEP**
- **Purpose:** CI build guidance for non-macOS environments
- **Accuracy:** Current (references on-demand-build.yml workflow)
- **Action:** None needed

#### 18. `logging-preferences.md` (5.5KB)
**Status:** ✅ **KEEP**
- **Purpose:** OSLog usage guidelines
- **Accuracy:** Current
- **Action:** None needed

#### 19. `feature-flags.md` (5.4KB)
**Status:** ✅ **KEEP**
- **Purpose:** Feature flag documentation
- **Accuracy:** Current
- **Action:** None needed

#### 20. `transcript-resumption-guide.md` (4.7KB)
**Status:** ⚠️ **VERIFY ACCURACY**
- **Purpose:** Guide for resuming transcript ingestion
- **Action:** Quick audit against current HooverEngine implementation

---

## Recommended Organizational Structure

### Proposed Directory Layout

```
build/notes/technical-reference/
├── README.md (NEW - central index with categories)
│
├── architecture/                     (High-level system architecture)
│   ├── data-flow-overview.md        (Overview of 5-stage pipeline)
│   ├── sql-backend.md               (Database architecture)
│   ├── llm-processing.md            (Dual-queue LLM system)
│   ├── startup-coordinator.md       (Project identity pipeline)
│   └── window-system.md             (4-window architecture)
│
├── components/                       (Component-specific docs)
│   ├── conversation-monitor.md      (Timeline state management)
│   ├── transcript-ingestion.md      (HooverEngine pipeline)
│   ├── timeline-cache.md            (LLM cache architecture)
│   └── project-discovery.md         (Discovery system)
│
├── specifications/                   (Format specs & protocols)
│   ├── claude-code-transcript-format.md
│   ├── codex-transcript-format.md  (Extract from current docs)
│   └── transcript-metadata-schema.md
│
├── guides/                           (How-to guides)
│   ├── diagnostics-api.md           (HTTP API usage)
│   ├── transcript-resumption.md     (Resuming ingestion)
│   ├── logging-best-practices.md
│   ├── linux-ci-builds.md
│   └── feature-flags.md
│
└── investigations/ → archive/        (Completed investigations)
    ├── cxt-10-11-main-thread-blocking.md
    ├── intent-classification-analysis.md
    └── transcript-inventory-gap-analysis.md
```

### File Naming Convention

**Standard:** `{topic}-{subtopic}.md` (kebab-case)

**Examples:**
- ✅ `sql-backend-architecture.md`
- ✅ `llm-processing-overview.md`
- ✅ `transcript-ingestion-pipeline.md`
- ❌ `cxt-10-11-main-thread-blocking-investigation.md` (investigation ID not descriptive)
- ❌ `data-flow-complete.md` (vague "complete")

---

## Central Index (README.md) - Draft

```markdown
# Technical Reference Documentation

**Last Updated:** 2025-11-08
**Scope:** Contextify architecture, components, and specifications

---

## Quick Navigation

| Category | Description | Key Documents |
|----------|-------------|---------------|
| **Architecture** | System design & data flow | [Data Flow](#data-flow), [SQL Backend](#sql-backend), [LLM Processing](#llm-processing)
| **Components** | Individual subsystems | [Conversation Monitor](#conversation-monitor), [Transcript Ingestion](#transcript-ingestion)
| **Specifications** | Format specs & schemas | [Transcript Formats](#transcript-formats)
| **Guides** | How-to documentation | [Diagnostics API](#diagnostics-api), [CI Builds](#ci-builds)

---

## Architecture

### Data Flow
**File:** `architecture/data-flow-overview.md`
**Purpose:** End-to-end data pipeline from filesystem → database → UI
**Topics:** Discovery, persistence, streaming, monitoring, rendering

### SQL Backend
**File:** `architecture/sql-backend.md`
**Purpose:** SQLite database architecture and schema design
**Topics:** Tables, migrations (v1-v21), repositories, GRDB integration
**Current Schema:** v21 (database_access_metadata)

### LLM Processing
**File:** `architecture/llm-processing.md`
**Purpose:** Dual-queue LLM architecture (FoundationLLM)
**Topics:** TimelineCacheMissGenerator, TranscriptMetadataOrchestrator, status aggregation

### Startup Coordinator
**File:** `architecture/startup-coordinator.md`
**Purpose:** Deterministic project identity pipeline
**Topics:** ActiveProjectContext, startup sequencing, AsyncStream-based updates

### Window System
**File:** `architecture/window-system.md`
**Purpose:** 4-window macOS app architecture
**Topics:** Main HUD, Transcript Inventory, Projects, Settings

---

## Components

### Conversation Monitor
**File:** `components/conversation-monitor.md`
**Purpose:** Timeline state management and real-time updates
**Topics:** TimelineState, entry filtering, system messages

### Transcript Ingestion
**File:** `components/transcript-ingestion.md`
**Purpose:** HooverEngine streaming JSONL parser
**Topics:** Batch processing, checkpointing, window tracking

### Timeline Cache
**File:** `components/timeline-cache.md`
**Purpose:** LLM-generated summary caching
**Topics:** Cache keys (content + window SHA256), miss detection, batch generation

### Project Discovery
**File:** `components/project-discovery.md`
**Purpose:** Multi-project detection and monitoring
**Topics:** ConversationSources, provider-specific scanners, FSEvents

---

## Specifications

### Transcript Formats
**Files:**
- `specifications/claude-code-transcript-format.md` - Claude Code JSONL format
- `specifications/codex-transcript-format.md` - Codex CLI JSONL format

**Key Differences:**
- Content blocks: Claude Code uses `text`, Codex uses `input_text`/`output_text`
- Message structure: Claude Code has top-level `uuid`/`type`, Codex wraps in `payload`

---

## Guides

### Diagnostics API
**File:** `guides/diagnostics-api.md`
**Purpose:** HTTP API for debugging (DEBUG builds only)
**Endpoints:** `/health`, `/diagnostics`, `/timeline/recent`, `/timeline/latest`

### Linux CI Builds
**File:** `guides/linux-ci-builds.md`
**Purpose:** Building Contextify from non-macOS environments
**Topics:** On-demand GitHub Actions, artifact downloads

### Logging Best Practices
**File:** `guides/logging-best-practices.md`
**Purpose:** OSLog usage guidelines
**Topics:** Log levels, privacy annotations, console filters

---

## Archive

Completed investigations and analyses moved to `archive/`:
- **Investigations:** Debugging sessions for resolved issues
- **Analyses:** Research docs for shipped features

See `archive/README.md` for full listing.
```

---

## Action Plan

### Phase 1: Quick Wins (2-3 hours)
1. **Create central README.md** with categorized index (draft above)
2. **Move to archive:**
   - `cxt-10-11-main-thread-blocking-investigation.md` → `archive/investigations/`
   - `intent-classification-analysis.md` → `archive/analyses/`
3. **Update sql-backend-architecture.md** with v12-v21 migrations

### Phase 2: Structural Reorganization (4-6 hours)
1. **Create subdirectories:**
   - `architecture/`
   - `components/`
   - `specifications/`
   - `guides/`
2. **Move files** according to new structure (preserving git history with `git mv`)
3. **Update all internal cross-references** (grep for `](` and update relative paths)

### Phase 3: Content Breakdown (6-8 hours)
1. **Break down `transcript-inventory-db-integration-gap.md`:**
   - Extract: Problem statement + solution spec (keep active)
   - Archive: Verbose analysis sections
2. **Clean up `window-architectures.md`:**
   - Remove iTerm2 sections
   - Update to current 4-window structure
3. **Optionally split `data-flow-complete.md`:**
   - Overview (10KB)
   - Detailed per-stage docs (40KB)

### Phase 4: Documentation Completeness (4-6 hours)
1. **Create missing docs:**
   - `specifications/codex-transcript-format.md` (extract from existing docs)
   - `specifications/transcript-metadata-schema.md`
2. **Audit `transcript-resumption-guide.md`** against current HooverEngine
3. **Add diagrams** where helpful (Mermaid or ASCII art)

---

## Naming Audit

### Current Issues
| Current Name | Issue | Recommended Name |
|--------------|-------|------------------|
| `data-flow-complete.md` | Vague "complete" | `data-flow-overview.md` |
| `cxt-10-11-main-thread-blocking-investigation.md` | Investigation ID not descriptive | `main-thread-blocking-investigation.md` (in archive) |
| `technical-brief-transcript-inventory-codex-support.md` | "technical-brief" redundant | `transcript-inventory-codex-support.md` |

### Proposed Standard
- **Architecture docs:** `{system}-architecture.md` or `{system}-overview.md`
- **Component docs:** `{component}-{aspect}.md` (e.g., `conversation-monitor-state.md`)
- **Specifications:** `{format}-specification.md` or `{format}-format.md`
- **Guides:** `{task}-guide.md` or `{topic}-best-practices.md`

---

## Metrics

### Before Reorganization
- **Total files:** 20
- **Total size:** 409KB
- **Average size:** 20.4KB
- **Files >30KB:** 4 (20%)
- **Organization:** Flat directory, inconsistent naming

### After Reorganization (Projected)
- **Active files:** 17 (3 moved to archive)
- **Active size:** ~306KB (103KB archived)
- **Average size:** ~18KB
- **Files >30KB:** 1 (5%) - only `data-flow-complete.md` if kept as-is
- **Organization:** 4 subdirectories + central index

**Size reduction:** 25% of active documentation
**Discoverability:** Significantly improved with categorized structure

---

## Backward Compatibility

### Cross-Reference Updates Required

Files referencing technical docs that will move:
- `TODOS.md` - References:
  - `build/notes/technical-reference/claude-code-transcript-format.md` ✅ (stays in place or moves to `specifications/`)
  - `build/notes/technical-reference/sql-backend-architecture.md` ✅ (needs update anyway)
- `CLAUDE.md` - References:
  - LLM architecture docs (will move to `architecture/`)
  - SQL backend architecture (will move to `architecture/`)
  - Startup coordinator (will move to `architecture/`)

**Action:** Update all cross-references with new paths after reorganization.

---

## Implementation Notes

### Git History Preservation
Use `git mv` to preserve history:
```bash
git mv build/notes/technical-reference/cxt-10-11-main-thread-blocking-investigation.md \\
        build/notes/archive/investigations/main-thread-blocking.md
```

### Gradual Migration
Can implement incrementally:
1. Phase 1 (quick wins) immediately
2. Phase 2 (reorganization) in single PR
3. Phase 3-4 (content breakdown) over multiple PRs

### Documentation of Changes
Create `build/notes/technical-reference/MIGRATION-2025-11-08.md` documenting:
- Old path → New path mapping
- Rationale for changes
- How to find relocated docs

---

## Conclusion

**Status:** Audit complete, reorganization plan ready for implementation

**Recommendation:** Implement Phase 1 (quick wins) immediately, then decide on Phase 2-4 based on available time and priorities.

**Key Benefits:**
- 25% reduction in active documentation size
- Improved discoverability with categorized structure
- Better separation of current vs. historical content
- Standardized naming convention
- Central index for easy navigation

**Risk:** Minimal - using `git mv` preserves history, and cross-reference updates are straightforward grep-and-replace operations.
