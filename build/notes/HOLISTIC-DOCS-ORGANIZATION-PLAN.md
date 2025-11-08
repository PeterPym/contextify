# Holistic Documentation Organization Plan

**Date:** 2025-11-08
**Scope:** Entire `build/notes/` directory lifecycle management
**Problem:** Documentation lifecycle mismatch with actual development workflow

---

## Executive Summary

**Current State:** 98 markdown files (13,801 lines of feature-specs/implementation-plans alone) with lifecycle problems:
- Implementation plans become stale immediately after shipping
- Manual "completed" tracking ignored (too much overhead)
- technical-reference/ polluted with gap analyses and proposals
- No clear distinction between current-state docs vs transient planning docs

**Root Cause:** Documentation lifecycle doesn't match development lifecycle

**Solution:** Three-tier system with clear lifecycle boundaries + automation

---

## The Lifecycle Problem

### Current Development Flow (Actual)
```
1. Plan feature (sometimes in /tmp/, sometimes in repo)
2. Implement
3. Ship or abandon
4. Move on (manual doc updates forgotten)
```

### Current Documentation Structure (Broken)
```
build/notes/
├── feature-specs/           ← Created during planning, NEVER updated after ship
│   ├── project-switcher/    ← Example: Says "Not Started" but SHIPPED
│   └── startup-coordinator/ ← Example: Says "Not Started" but commit 531ac70 shipped it
├── implementation-plans/    ← Created during implementation, stale after ship
├── technical-reference/     ← SHOULD be current state, but has gap analyses
├── completed.md             ← Last updated Oct 2, now stale
└── current.md               ← Shows Oct 9 work, likely shipped
```

**The Gap:** No mechanism to move docs through lifecycle stages automatically or with minimal friction.

---

## Document Lifecycle Stages

### Stage 1: Transient Planning (SHOULD NOT BE VERSIONED)
**Lifespan:** Days to weeks
**Purpose:** Active work-in-progress, brainstorming, implementation details
**Examples:**
- "How should I implement X?"
- "Gap analysis for feature Y"
- "Implementation checklist"
- "Code review notes"

**Characteristics:**
- Changes rapidly
- Only relevant during active development
- Value drops to zero after implementation
- Creates merge conflicts if versioned

**Current Location:** `feature-specs/*/implementation-files.md`, `feature-specs/*/STATUS.md`, `implementation-plans/`

**Proposed Location:** `.workbench/` (gitignored) or `/tmp/`

---

### Stage 2: Stable Reference (SHOULD BE VERSIONED)
**Lifespan:** Months to years
**Purpose:** Current state documentation, architectural decisions, specifications
**Examples:**
- "How does the SQL backend work?" (architecture)
- "What's the Claude Code transcript format?" (external dependency spec)
- "What colors does the app use?" (design decisions)
- "How do I use the diagnostics API?" (operational guide)

**Characteristics:**
- Describes current reality (not plans)
- Updated when implementation changes (rarely)
- High long-term value
- Few merge conflicts

**Current Location:** `technical-reference/` (mixed), `design-reference/` (good)

**Proposed Location:** `build/docs/` (renamed from `notes/`)

---

### Stage 3: Historical Archive (VERSIONED BUT CLEARLY MARKED)
**Lifespan:** Forever (for historical context)
**Purpose:** Design rationale, investigation notes, completed feature specs
**Examples:**
- "Why did we choose SQL over CoreData?" (design rationale)
- "How did we debug the main thread blocking issue?" (investigation)
- "Original spec for project switcher" (design decisions)

**Characteristics:**
- Immutable (never updated)
- Historical value only
- Helps understand "why" decisions were made
- Safe to version (no conflicts)

**Current Location:** `archive/` (good!)

**Proposed Location:** `archive/` (keep as-is)

---

## Proposed Structure

### Option A: Three-Tier System (Recommended)

```
contextify/
├── .workbench/                          ← NEW: Transient planning (GITIGNORED)
│   ├── .gitkeep                         ← Track directory but not contents
│   ├── [current-feature]/               ← One dir per active feature
│   │   ├── implementation-plan.md
│   │   ├── checklist.md
│   │   ├── code-review-notes.md
│   │   └── STATUS.md
│   └── README.md                        ← Explains: "Throwaway docs, not versioned"
│
├── build/docs/                          ← RENAMED from build/notes/
│   ├── README.md                        ← Central index, explains structure
│   │
│   ├── architecture/                    ← Current state: System architecture
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
│   │   ├── codex-transcript-format.md
│   │   └── database-schema.md
│   │
│   ├── guides/                          ← How-to docs (operational)
│   │   ├── README.md
│   │   ├── diagnostics-api.md
│   │   ├── linux-ci-builds.md
│   │   ├── logging-best-practices.md
│   │   └── release-process.md
│   │
│   ├── design/                          ← Design decisions (rarely change)
│   │   ├── README.md
│   │   ├── color-scheme.md
│   │   ├── help-system.md
│   │   └── typography.md
│   │
│   ├── operations/                      ← Release, app store, marketing
│   │   ├── app-store/
│   │   │   └── sandbox-implementation-plan.md
│   │   ├── marketing/
│   │   │   ├── distribution-strategy.md
│   │   │   └── show-hn-draft.md
│   │   └── release/
│   │       ├── notarization-guide.md
│   │       └── build-verification.md
│   │
│   └── archive/                         ← Historical (design rationale, investigations)
│       ├── README.md                    ← Explains: "Historical docs, not current"
│       ├── by-date/
│       │   └── 2025-10-XX-feature-name.md
│       ├── investigations/
│       │   ├── cxt-10-11-main-thread-blocking.md
│       │   └── intent-classification-analysis.md
│       └── feature-specs/               ← Completed feature specs (design rationale)
│           ├── project-switcher/
│           │   └── original-spec.md     ← Keep ONLY the spec, not STATUS/checklist
│           └── startup-coordinator/
│               └── original-spec.md
│
└── .gitignore                           ← Add: .workbench/*
```

---

## What Goes Where: Decision Tree

```
┌─────────────────────────────────────────────────────────┐
│ Is this about the CURRENT state of the app?            │
└─────────────┬───────────────────────────────────────────┘
              │
        ┌─────┴─────┐
       Yes          No
        │            │
        ▼            ▼
   build/docs/   ┌──────────────────────────────────────┐
                 │ Is it planning for FUTURE work?      │
                 └─────┬────────────────────────────────┘
                       │
                 ┌─────┴─────┐
                Yes          No
                 │            │
                 ▼            ▼
            .workbench/   ┌──────────────────────────────┐
            (gitignored)  │ Is it HISTORICAL context?    │
                          └─────┬────────────────────────┘
                                │
                          ┌─────┴─────┐
                         Yes          No
                          │            │
                          ▼            ▼
                  build/docs/     [DELETE IT]
                     archive/
```

### Detailed Examples

| Document Type | Current | Proposed | Versioned? |
|--------------|---------|----------|------------|
| **Gap analysis: "Transcript Inventory not using SQL"** | technical-reference/ ❌ | .workbench/ | ❌ No |
| **Implementation checklist: "Project switcher TODO"** | feature-specs/project-switcher/STATUS.md ❌ | .workbench/project-switcher/checklist.md | ❌ No |
| **Code review notes** | feature-specs/*/code-review-response.md ❌ | .workbench/[feature]/review.md | ❌ No |
| **Current architecture: "How does SQL backend work?"** | technical-reference/sql-backend-architecture.md ✅ | build/docs/architecture/sql-backend.md | ✅ Yes |
| **External spec: "Claude Code transcript format"** | technical-reference/claude-code-transcript-format.md ✅ | build/docs/specifications/claude-code-format.md | ✅ Yes |
| **Design decision: "Why these colors?"** | design-reference/color-scheme.md ✅ | build/docs/design/color-scheme.md | ✅ Yes |
| **Investigation: "How we fixed CXT-10"** | technical-reference/cxt-10-11-main-thread-blocking-investigation.md ❌ | build/docs/archive/investigations/cxt-10-11.md | ✅ Yes (historical) |
| **Original feature spec: "Project switcher design"** | feature-specs/project-switcher/spec.md ❌ | build/docs/archive/feature-specs/project-switcher.md | ✅ Yes (rationale) |
| **Current TODO list** | build/notes/TODOS.md ✅ | /TODOS.md (root) | ✅ Yes |

---

## Automation: Lifecycle Management

### Problem
Manual tracking fails because it's:
1. **Boring** - "Update completed.md" is busywork
2. **Forgotten** - Happens after feature ships (no incentive)
3. **Imprecise** - Hard to know when something is "done"

### Solution: Git-based Lifecycle Detection

#### Script: `scripts/vacuum-docs.sh`

```bash
#!/bin/bash
# Auto-detect stale feature-specs and suggest archival

set -euo pipefail

STALE_DAYS=60  # Docs older than 60 days with no recent commits

echo "=== Documentation Lifecycle Check ==="
echo ""

# Find feature-specs not updated in 60 days
find .workbench build/docs/archive/feature-specs -name "*.md" -type f -mtime +${STALE_DAYS} 2>/dev/null | while read -r file; do
    last_commit=$(git log -1 --format="%cr" -- "$file" 2>/dev/null || echo "never")

    if [[ "$last_commit" == *"months ago"* ]] || [[ "$last_commit" == "never" ]]; then
        echo "STALE: $file"
        echo "  Last updated: $last_commit"
        echo "  Suggestion: Move to archive/ or delete"
        echo ""
    fi
done

echo "=== Workbench Cleanup ==="
echo ""

# Check .workbench for abandoned work
if [[ -d .workbench ]]; then
    find .workbench -name "*.md" -type f -mtime +30 | while read -r file; do
        echo "OLD: $file (not touched in 30 days)"
        echo "  Consider archiving or deleting"
        echo ""
    done
fi
```

#### Hook: `.git/hooks/post-merge`

```bash
#!/bin/bash
# Remind about stale docs after pulling

if [[ -f scripts/vacuum-docs.sh ]]; then
    echo ""
    echo "💡 Tip: Run 'scripts/vacuum-docs.sh' to check for stale documentation"
    echo ""
fi
```

---

## Migration Plan

### Phase 1: Create New Structure (1-2 hours)

```bash
# 1. Create new directories
mkdir -p .workbench
mkdir -p build/docs/{architecture,components,specifications,guides,design,operations,archive}

# 2. Add .workbench to .gitignore
echo "# Transient planning docs (not versioned)" >> .gitignore
echo ".workbench/*" >> .gitignore
echo "!.workbench/README.md" >> .gitignore

# 3. Create .workbench/README.md
cat > .workbench/README.md << 'EOF'
# Workbench

This directory holds **transient planning documents** that are not version controlled.

## Purpose
- Implementation plans
- Checklists
- Code review notes
- Gap analyses
- Investigation notes (during active debugging)

## Lifecycle
Documents here are **throwaway**. They're only useful during active development.

Once a feature ships or is abandoned, these docs have no value and can be deleted.

## Why Not Versioned?
- Changes too frequently (causes merge conflicts)
- No long-term value
- Clutters git history
- Easy to forget to update

## Suggested Workflow
1. Create a subdirectory for your feature: `.workbench/my-feature/`
2. Write implementation-plan.md, checklist.md, etc.
3. Ship the feature
4. Delete the directory or let it sit (vacuum script will warn after 30 days)

## If You Need It Later
For design rationale or historical context, write a separate doc in `build/docs/archive/` with:
- **Why** the decision was made
- **What** alternatives were considered
- **When** it was decided

These are **immutable** historical records, not living documents.
EOF

# 4. Commit structure
git add .gitignore .workbench/README.md build/docs/
git commit -m "docs: create three-tier documentation structure

- .workbench/ for transient planning (gitignored)
- build/docs/ for stable reference (versioned)
- build/docs/archive/ for historical context

See .workbench/README.md for lifecycle explanation."
```

### Phase 2: Migrate Current Docs (3-4 hours)

**Categorize existing docs:**

```bash
# A. KEEP in technical-reference → build/docs/
claude-code-transcript-format.md        → specifications/claude-code-format.md
conversation-monitor-state-architecture.md → architecture/conversation-monitor-state.md
data-flow-complete.md                   → architecture/data-flow.md
diagnostics-api-usage.md                → guides/diagnostics-api.md
feature-flags.md                        → guides/feature-flags.md
linux-ci-builds.md                      → guides/linux-ci-builds.md
llm-processing-architecture.md          → architecture/llm-processing.md
logging-preferences.md                  → guides/logging-best-practices.md
project-discovery-implementation.md     → components/project-discovery.md
sql-backend-architecture.md             → architecture/sql-backend.md
startup-coordinator-architecture.md     → architecture/startup-coordinator.md
timeline-cache-llm-architecture.md      → components/timeline-cache.md
timeline-diagnostics-framework.md       → guides/timeline-diagnostics.md
transcript-ingestion-pipeline.md        → components/transcript-ingestion.md
transcript-resumption-guide.md          → guides/transcript-resumption.md
window-architectures.md                 → architecture/window-system.md

# B. MOVE to archive (historical value)
cxt-10-11-main-thread-blocking-investigation.md → archive/investigations/cxt-10-11.md
intent-classification-analysis.md        → archive/investigations/intent-classification.md
technical-brief-transcript-inventory-codex-support.md → archive/feature-specs/transcript-inventory-codex.md

# C. DELETE or move to .workbench (gap analysis, stale)
transcript-inventory-db-integration-gap.md → DELETE (issue tracked in TODOS.md)
```

**Move feature-specs:**

```bash
# For each feature-spec, decide:

# 1. If shipped: Move ONLY the original spec (design rationale) to archive
git mv build/notes/feature-specs/project-switcher/spec.md \\
       build/docs/archive/feature-specs/project-switcher-spec.md

# 2. Delete implementation details (STATUS.md, implementation-files.md, etc.)
rm build/notes/feature-specs/project-switcher/{STATUS.md,implementation-files.md,code-review-response.md}

# 3. If actively being worked on: Move to .workbench
# (none currently active based on git log)
```

### Phase 3: Update Cross-References (1 hour)

```bash
# Find all references to moved files
grep -r "build/notes/technical-reference" . --include="*.md" --include="*.swift"

# Update paths
# Example: s|build/notes/technical-reference/sql-backend-architecture.md|build/docs/architecture/sql-backend.md|g
```

### Phase 4: Enable Automation (1 hour)

```bash
# 1. Create vacuum script
cp <script above> scripts/vacuum-docs.sh
chmod +x scripts/vacuum-docs.sh

# 2. Create post-merge hook
cp <hook above> .git/hooks/post-merge
chmod +x .git/hooks/post-merge

# 3. Add to Makefile
echo "vacuum-docs:" >> Makefile
echo "\t./scripts/vacuum-docs.sh" >> Makefile
```

---

## Ongoing Workflow

### Starting New Feature

**Before (messy):**
```bash
# Create docs in feature-specs/my-feature/
# Try to remember to update STATUS.md
# Forget to move to archive after shipping
```

**After (clean):**
```bash
# 1. Create workbench directory
mkdir .workbench/my-feature

# 2. Write throwaway docs
echo "# Implementation Plan" > .workbench/my-feature/plan.md
echo "# Checklist" > .workbench/my-feature/checklist.md

# 3. Implement

# 4. Ship

# 5. Forget about it (docs auto-detected as stale after 30 days)
```

### Documenting Current State

**When to write:**
- After shipping a feature
- After making an architectural decision
- When you realize something isn't documented

**Where to write:**
```bash
# Architecture decision
build/docs/architecture/my-system.md

# Component behavior
build/docs/components/my-component.md

# External dependency
build/docs/specifications/external-format.md

# How-to guide
build/docs/guides/how-to-x.md
```

### Archiving Historical Context

**When to archive:**
- Feature shipped, want to preserve design rationale
- Investigation complete, want to preserve findings
- Alternative approach rejected, want to explain why

**Where to archive:**
```bash
build/docs/archive/feature-specs/my-feature.md      # Design rationale
build/docs/archive/investigations/issue-xyz.md      # Debugging journey
build/docs/archive/by-date/2025-11-08-decision.md   # Design decision
```

---

## Benefits

### For You
- ✅ **No more manual tracking** - No updating completed.md, current.md, STATUS.md
- ✅ **No merge conflicts** - Transient docs in .workbench are gitignored
- ✅ **Less clutter** - 13,801 lines of stale specs moved out or deleted
- ✅ **Clear mental model** - Three simple categories: transient, current, historical

### For Future You
- ✅ **Easy to find current state** - All in build/docs/, organized by category
- ✅ **Easy to understand history** - archive/ explains "why" decisions were made
- ✅ **Easy to start new work** - .workbench/ is obviously throwaway

### For Others
- ✅ **Clear structure** - README.md files explain what goes where
- ✅ **Current docs stay current** - Only current-state docs are versioned
- ✅ **No false confidence** - No "STATUS: Not Started" for shipped features

---

## Metrics

### Before
- **Total files:** 98
- **Total lines (feature-specs + implementation-plans):** 13,801
- **Manual tracking files:** 3 (completed.md, current.md, IMPLEMENTATION-COMPLETE.md)
- **Stale docs:** Unknown (no way to detect)
- **Organization:** Flat, unclear lifecycle

### After (Projected)
- **Versioned files:** ~40 (current-state + archive)
- **Gitignored files:** ~20-30 in .workbench (for active work)
- **Manual tracking files:** 0 (git log is the truth)
- **Stale docs:** Auto-detected after 30-60 days
- **Organization:** Three-tier, clear lifecycle

**Lines of versioned docs:** ~70% reduction (remove stale implementation-plans)

---

## Risks & Mitigation

### Risk: "I need a doc that was in .workbench"

**Likelihood:** Low (you write these to /tmp/ already)

**Mitigation:**
- Vacuum script only warns, doesn't auto-delete
- Archive important decisions in build/docs/archive/ before deleting .workbench files

### Risk: "Where do I put [specific doc]?"

**Likelihood:** Medium (initial confusion)

**Mitigation:**
- README.md in each directory explains purpose
- Decision tree in this document
- Examples in .workbench/README.md

### Risk: "Cross-references break"

**Likelihood:** Medium (during migration)

**Mitigation:**
- Phase 3 of migration updates all references
- Use relative paths (../architecture/sql-backend.md)
- Grep for broken links after migration

---

## Recommendation

**Implement Phase 1 immediately:**
- Low risk (just creates directories)
- High value (establishes clear mental model)
- ~1 hour of work

**Implement Phase 2-4 over next week:**
- Medium risk (file moves, cross-references)
- Very high value (cleans up 13,801 lines of stale docs)
- ~5-6 hours total

**Result:** Clean, maintainable documentation structure with minimal ongoing overhead.
