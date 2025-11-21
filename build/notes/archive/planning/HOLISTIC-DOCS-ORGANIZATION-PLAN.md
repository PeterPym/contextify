# Holistic Documentation Organization Plan

**Date:** 2025-11-08
**Scope:** `build/notes/` reorganization
**Problem:** Documentation lifecycle mismatch with development workflow

---

## Executive Summary

**Current State:** 98 markdown files with lifecycle problems:
- Implementation plans become stale immediately after shipping
- Manual "completed" tracking ignored (too much overhead)
- `technical-reference/` polluted with gap analyses and proposals
- No clear distinction between current-state docs vs transient planning

**Root Cause:** Documentation lifecycle doesn't match development workflow

**Solution:** Two-tier system (you already use `/tmp/` for planning, just formalize it)

---

## The Problem

### Current Development Flow (What You Actually Do)
```
1. Write planning docs to /tmp/ (ephemeral, auto-cleaned)
2. Implement
3. Ship or abandon
4. Move on (manual doc updates forgotten)
```

### Current Repository Reality (What's Broken)
```
build/notes/
├── feature-specs/           ← Created during planning, NEVER updated
│   ├── project-switcher/    ← Says "Not Started" but SHIPPED
│   └── startup-coordinator/ ← Says "Not Started" but commit 531ac70 shipped it
├── implementation-plans/    ← Stale after ship
├── technical-reference/     ← Mixed: current state + gap analyses + investigations
├── completed.md             ← Last updated Oct 2 (now stale)
└── current.md               ← Last updated Oct 9 (now stale)
```

**Key Insight:** You're already doing the right thing (`/tmp/`), but the repo is full of old docs that were created "the wrong way" and never cleaned up.

---

## Solution: Two-Tier System

### Tier 1: Transient Planning → `/tmp/` (NOT VERSIONED)
**Lifespan:** Days to weeks (auto-cleaned by OS)
**Purpose:** Active work-in-progress, throwaway docs
**Examples:**
- Implementation plans
- Gap analyses
- Checklists
- Code review notes

**Location:** `/tmp/contextify-planning/[feature-name]/` or just `/tmp/[feature-name]/`

**No repo changes needed** - you already do this!

---

### Tier 2: Stable Reference → `build/docs/` (VERSIONED)
**Lifespan:** Months to years
**Purpose:** Current state documentation ONLY

**What belongs here:**
- ✅ Architecture: "How does SQL backend work?"
- ✅ Specifications: "Claude Code transcript format" (external dependency)
- ✅ Guides: "How to use diagnostics API"
- ✅ Design: "Color scheme decisions"
- ✅ Historical: "Why we chose SQL" (design rationale in `archive/`)

**What does NOT belong here:**
- ❌ "Gap analysis for feature X" → `/tmp/`
- ❌ "Implementation plan for Y" → `/tmp/`
- ❌ "STATUS: Not Started" tracking files → `/tmp/`
- ❌ Manual tracking (completed.md, current.md) → delete (git log is truth)

---

## Proposed Repository Structure

```
contextify/
│
├── build/docs/                          ← RENAMED from build/notes/
│   ├── README.md                        ← NEW: Central index with categories
│   │
│   ├── architecture/                    ← Current state: System design
│   │   ├── README.md
│   │   ├── data-flow.md
│   │   ├── sql-backend.md
│   │   ├── llm-processing.md
│   │   ├── startup-coordinator.md
│   │   └── window-system.md
│   │
│   ├── components/                      ← Current state: Component docs
│   │   ├── README.md
│   │   ├── conversation-monitor.md
│   │   ├── transcript-ingestion.md
│   │   ├── timeline-cache.md
│   │   └── project-discovery.md
│   │
│   ├── specifications/                  ← External dependencies (stable)
│   │   ├── README.md
│   │   ├── claude-code-transcript-format.md
│   │   └── codex-transcript-format.md
│   │
│   ├── guides/                          ← How-to docs (operational)
│   │   ├── README.md
│   │   ├── diagnostics-api.md
│   │   ├── linux-ci-builds.md
│   │   ├── logging-best-practices.md
│   │   └── release-process.md
│   │
│   ├── design/                          ← Design decisions
│   │   ├── README.md
│   │   ├── color-scheme.md
│   │   ├── help-system.md
│   │   └── typography.md
│   │
│   ├── operations/                      ← Release, app store, marketing
│   │   ├── app-store/
│   │   │   └── sandbox-requirements.md
│   │   ├── marketing/
│   │   │   ├── distribution-strategy.md
│   │   │   └── show-hn-draft.md
│   │   └── release/
│   │       └── notarization-guide.md
│   │
│   └── archive/                         ← Historical context
│       ├── README.md                    ← "Historical docs, not current state"
│       ├── investigations/              ← Completed debugging sessions
│       │   ├── 2025-11-05-main-thread-blocking.md
│       │   └── 2025-11-03-intent-classification.md
│       └── feature-specs/               ← Original specs (design rationale)
│           ├── project-switcher.md
│           └── startup-coordinator.md
│
└── /tmp/contextify-planning/            ← Transient docs (not in repo)
    └── [current-feature]/
        ├── implementation-plan.md
        ├── checklist.md
        └── gap-analysis.md
```

---

## Decision Tree: What Goes Where?

```
┌─────────────────────────────────────────────────┐
│ Is this about the CURRENT state of the app?    │
└─────────────┬───────────────────────────────────┘
              │
        ┌─────┴─────┐
       YES          NO
        │            │
        ▼            ▼
   build/docs/   ┌────────────────────────────┐
                 │ Is it planning FUTURE work?│
                 └─────┬──────────────────────┘
                       │
                 ┌─────┴─────┐
                YES          NO
                 │            │
                 ▼            ▼
              /tmp/      ┌────────────────────┐
                         │ Historical context?│
                         └─────┬──────────────┘
                               │
                         ┌─────┴─────┐
                        YES          NO
                         │            │
                         ▼            ▼
                 build/docs/     [DELETE]
                    archive/
```

### Examples

| Document | Current Location | Proposed | Versioned? |
|----------|-----------------|----------|------------|
| **Gap analysis: "Transcripts not using SQL"** | technical-reference/ ❌ | /tmp/ | No |
| **Implementation checklist** | feature-specs/*/STATUS.md ❌ | /tmp/ | No |
| **Code review notes** | feature-specs/*/code-review-response.md ❌ | /tmp/ | No |
| **Architecture: "How SQL backend works"** | technical-reference/sql-backend-architecture.md ✅ | build/docs/architecture/sql-backend.md | Yes |
| **External spec: "Claude Code format"** | technical-reference/claude-code-transcript-format.md ✅ | build/docs/specifications/claude-code-transcript-format.md | Yes |
| **Investigation: "CXT-10 debugging"** | technical-reference/cxt-10-11-investigation.md ❌ | build/docs/archive/investigations/2025-11-05-cxt-10-11.md | Yes (historical) |
| **Original spec: "Project switcher"** | feature-specs/project-switcher/spec.md ❌ | build/docs/archive/feature-specs/project-switcher.md | Yes (rationale) |

---

## Migration Plan

### Phase 1: Reorganize `build/notes/` → `build/docs/` (3-4 hours)

#### Step 1: Create new structure

```bash
mkdir -p build/docs/{architecture,components,specifications,guides,design,operations,archive}
mkdir -p build/docs/archive/{investigations,feature-specs}
```

#### Step 2: Move current-state docs (use `git mv` to preserve history)

**Architecture:**
```bash
git mv build/notes/technical-reference/data-flow-complete.md \
       build/docs/architecture/data-flow.md

git mv build/notes/technical-reference/sql-backend-architecture.md \
       build/docs/architecture/sql-backend.md

git mv build/notes/technical-reference/llm-processing-architecture.md \
       build/docs/architecture/llm-processing.md

git mv build/notes/technical-reference/startup-coordinator-architecture.md \
       build/docs/architecture/startup-coordinator.md

git mv build/notes/technical-reference/window-architectures.md \
       build/docs/architecture/window-system.md

git mv build/notes/technical-reference/conversation-monitor-state-architecture.md \
       build/docs/architecture/conversation-monitor-state.md
```

**Components:**
```bash
git mv build/notes/technical-reference/transcript-ingestion-pipeline.md \
       build/docs/components/transcript-ingestion.md

git mv build/notes/technical-reference/timeline-cache-llm-architecture.md \
       build/docs/components/timeline-cache.md

git mv build/notes/technical-reference/project-discovery-implementation.md \
       build/docs/components/project-discovery.md
```

**Specifications:**
```bash
git mv build/notes/technical-reference/claude-code-transcript-format.md \
       build/docs/specifications/claude-code-transcript-format.md
```

**Guides:**
```bash
git mv build/notes/technical-reference/diagnostics-api-usage.md \
       build/docs/guides/diagnostics-api.md

git mv build/notes/technical-reference/linux-ci-builds.md \
       build/docs/guides/linux-ci-builds.md

git mv build/notes/technical-reference/logging-preferences.md \
       build/docs/guides/logging-best-practices.md

git mv build/notes/technical-reference/transcript-resumption-guide.md \
       build/docs/guides/transcript-resumption.md

git mv build/notes/technical-reference/timeline-diagnostics-framework.md \
       build/docs/guides/timeline-diagnostics.md

git mv build/notes/technical-reference/feature-flags.md \
       build/docs/guides/feature-flags.md
```

**Design:**
```bash
git mv build/notes/design-reference build/docs/design
```

**Operations:**
```bash
git mv build/notes/app-store build/docs/operations/app-store
git mv build/notes/marketing build/docs/operations/marketing

# Release docs
git mv build/notes/notarization-setup.md build/docs/operations/release/
git mv build/notes/notarization-success.md build/docs/operations/release/
git mv build/notes/release-build-verification.md build/docs/operations/release/
git mv build/notes/release-readiness.md build/docs/operations/release/
```

#### Step 3: Archive historical docs

**Investigations (completed debugging sessions):**
```bash
git mv build/notes/technical-reference/cxt-10-11-main-thread-blocking-investigation.md \
       build/docs/archive/investigations/2025-11-05-main-thread-blocking.md

git mv build/notes/technical-reference/intent-classification-analysis.md \
       build/docs/archive/investigations/2025-11-03-intent-classification.md
```

**Feature specs (original design docs only, keep for rationale):**
```bash
# Keep ONLY the original spec.md files, archive them
git mv build/notes/feature-specs/project-switcher/spec.md \
       build/docs/archive/feature-specs/project-switcher.md

git mv build/notes/feature-specs/startup-coordinator/implementation-plan.md \
       build/docs/archive/feature-specs/startup-coordinator.md

git mv build/notes/feature-specs/status-bar/spec-final.md \
       build/docs/archive/feature-specs/status-bar.md

# Add more as needed
```

**Archive completed implementation docs:**
```bash
git mv build/notes/archive build/docs/archive/completed-work
```

#### Step 4: Delete stale tracking files

```bash
# These are never updated and provide no value
git rm build/notes/completed.md
git rm build/notes/current.md
git rm build/notes/IMPLEMENTATION-COMPLETE.md
git rm build/notes/implementation-summary.md
git rm build/notes/phase2-complete.md

# Delete STATUS.md, implementation-files.md, etc. from feature-specs
find build/notes/feature-specs -name "STATUS.md" -o -name "implementation-files.md" -o -name "code-review-response.md" | xargs git rm
```

#### Step 5: Delete gap analyses and implementation plans

```bash
# Gap analysis (91KB) - issue tracked in TODOS.md P1.3
git rm build/notes/technical-reference/transcript-inventory-db-integration-gap.md

# Delete remaining feature-specs and implementation-plans directories
git rm -r build/notes/feature-specs
git rm -r build/notes/implementation-plans
```

#### Step 6: Delete or archive other miscellaneous files

```bash
# Bug tracking should be in GitHub issues, not markdown files
git rm -r build/notes/bugs

# Research docs (RAG feature) - move to archive if needed
git mv build/notes/research/rag build/docs/archive/research-rag

# Old notes that are no longer relevant
git rm build/notes/fix-summary-word-boundary-truncation.md
git rm build/notes/QA-production-fixes.md
```

---

### Phase 2: Create Central Index (1 hour)

Create `build/docs/README.md`:

```markdown
# Contextify Documentation

**Last Updated:** 2025-11-08
**Purpose:** Current state documentation, architectural decisions, operational guides

---

## Quick Navigation

| Category | Purpose | Key Documents |
|----------|---------|---------------|
| **Architecture** | System design & data flow | [Data Flow](architecture/data-flow.md), [SQL Backend](architecture/sql-backend.md), [LLM Processing](architecture/llm-processing.md) |
| **Components** | Individual subsystems | [Transcript Ingestion](components/transcript-ingestion.md), [Timeline Cache](components/timeline-cache.md) |
| **Specifications** | External dependencies | [Claude Code Format](specifications/claude-code-transcript-format.md) |
| **Guides** | How-to documentation | [Diagnostics API](guides/diagnostics-api.md), [Linux CI](guides/linux-ci-builds.md) |
| **Design** | Design decisions | [Color Scheme](design/color-scheme.md), [Help System](design/help-system.md) |
| **Operations** | Release & deployment | [App Store](operations/app-store/), [Marketing](operations/marketing/) |
| **Archive** | Historical context | [Investigations](archive/investigations/), [Feature Specs](archive/feature-specs/) |

---

## What Goes Where?

- **Current state docs** → `architecture/`, `components/`, `specifications/`, `guides/`, `design/`
- **Operational docs** → `operations/` (app store, marketing, release)
- **Historical context** → `archive/` (completed investigations, original feature specs)
- **Planning docs** → `/tmp/` (NOT in repo)

See [HOLISTIC-DOCS-ORGANIZATION-PLAN.md](../notes/HOLISTIC-DOCS-ORGANIZATION-PLAN.md) for detailed lifecycle management.

---

## Documentation Principles

1. **Current state only** - Docs describe reality, not plans
2. **No gap analyses** - Use TODOS.md or write to /tmp/
3. **No manual tracking** - Git log is the source of truth
4. **Archive, don't delete** - Historical context has value

---

## Subdirectories

### architecture/
System-level design documents. How the major components fit together.

### components/
Component-specific implementation details. How individual subsystems work.

### specifications/
External dependency formats. Claude Code transcripts, Codex transcripts, etc.

### guides/
Operational how-to docs. How to use diagnostics API, build on Linux, etc.

### design/
Design decisions. Color scheme, typography, help system UX.

### operations/
Release management, app store submission, marketing materials.

### archive/
Historical context. Completed investigations, original feature specs (design rationale).
```

Also create `README.md` files in each subdirectory explaining their purpose.

---

### Phase 3: Update Cross-References (1 hour)

```bash
# Find all references to old paths
grep -r "build/notes/technical-reference" --include="*.md" --include="*.swift"
grep -r "build/notes/feature-specs" --include="*.md"
grep -r "build/notes/design-reference" --include="*.md"

# Update paths in TODOS.md, CLAUDE.md, and other files
# Example: s|build/notes/technical-reference/sql-backend-architecture.md|build/docs/architecture/sql-backend.md|g
```

**Key files to update:**
- `TODOS.md` (references technical-reference and feature-specs)
- `CLAUDE.md` (references architecture docs)
- Any cross-references within docs themselves

---

### Phase 4: Clean Up Old Directory (10 min)

```bash
# After confirming everything moved correctly:
git rm -r build/notes/technical-reference
git rm -r build/notes/design-reference
rm -rf build/notes  # Should be empty or nearly empty now
```

---

## Ongoing Workflow

### When Starting New Feature

**Do:**
```bash
# Create planning docs in /tmp/
mkdir -p /tmp/contextify-my-feature
echo "# Implementation Plan" > /tmp/contextify-my-feature/plan.md
echo "# Checklist" > /tmp/contextify-my-feature/checklist.md
echo "# Gap Analysis" > /tmp/contextify-my-feature/gaps.md

# Work on feature, update /tmp/ docs as needed
# Ship feature
# Forget about it (OS cleans /tmp/)
```

**Don't:**
```bash
# ❌ Don't create feature-specs/ in repo
# ❌ Don't create STATUS.md tracking files
# ❌ Don't create implementation-plans/ in repo
```

### When Documenting Current State

**After shipping a feature or making an architectural decision:**

```bash
# Write current-state doc
vim build/docs/architecture/my-new-system.md

# Or update existing doc
vim build/docs/architecture/sql-backend.md

# Commit
git add build/docs/
git commit -m "docs(architecture): document my-new-system"
```

### When Archiving Historical Context

**If the "why" behind a decision is valuable:**

```bash
# Write immutable historical doc
vim build/docs/archive/feature-specs/my-feature.md
# Or
vim build/docs/archive/investigations/2025-11-08-issue-xyz.md

# Commit
git add build/docs/archive/
git commit -m "docs(archive): preserve design rationale for my-feature"
```

---

## Benefits

### For You
- ✅ **No more manual tracking** - No updating completed.md, current.md, STATUS.md
- ✅ **No repo clutter** - 13,801 lines of stale docs deleted
- ✅ **Matches workflow** - You already use /tmp/, just formalize it
- ✅ **Clear mental model** - Two simple tiers: transient (/tmp/) vs stable (build/docs/)

### For Others
- ✅ **Easy to find current state** - Organized by category
- ✅ **No false confidence** - No "STATUS: Not Started" for shipped features
- ✅ **Understands history** - archive/ explains "why" decisions were made

---

## Metrics

### Before
- **Total files:** 98
- **Total lines (feature-specs + implementation-plans):** 13,801
- **Manual tracking files:** 5 (completed.md, current.md, IMPLEMENTATION-COMPLETE.md, etc.)
- **Stale docs:** Unknown (many)
- **Organization:** Flat, unclear lifecycle

### After
- **Versioned files:** ~35-40 (current-state + archive)
- **Transient files:** 0 in repo (use /tmp/)
- **Manual tracking files:** 0 (git log is truth)
- **Stale docs:** 0 (by definition - only current state is versioned)
- **Organization:** Two-tier with clear categories

**Reduction:** ~70% fewer versioned documentation files

---

## Summary

**Core Insight:** You already do the right thing (/tmp/ for planning). Just need to:
1. Clean up old repo docs that should never have been versioned
2. Reorganize remaining docs into clear categories
3. Establish "no planning docs in repo" policy going forward

**Time Investment:** 5-6 hours total
**Result:** Clean, maintainable documentation with zero ongoing overhead
