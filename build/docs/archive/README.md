# Archive

Historical context and completed work documentation.

## Purpose

This directory contains **immutable historical documentation** that provides context for past decisions and implementations. These docs are NOT current state - they represent snapshots of thinking at specific points in time.

**Key principle:** Once a doc is archived, it should NOT be updated. It's a historical artifact.

## Subdirectories

### investigations/
**Topics:** Completed debugging sessions and technical investigations
- Performance issues (main thread blocking, timeline lag, etc.)
- Bug root cause analyses
- System behavior investigations

**Key docs:**
- [2025-11-05 Main Thread Blocking](investigations/2025-11-05-main-thread-blocking.md) - CXT-10-11 investigation (resolved in commit 086bdb0)
- [2025-11-03 Intent Classification](investigations/2025-11-03-intent-classification.md) - Timeline summary improvements (shipped in commits 7493bec-1755813)

### feature-specs/
**Topics:** Original feature specifications and design documents
- Initial problem statements and design rationale
- Architectural decisions and alternatives considered
- Original implementation plans (as-written, not updated post-ship)

**Why keep these?**
- Explains "why we chose X over Y"
- Documents constraints and context at decision time
- Useful for understanding design evolution

**Key docs:**
- [Project Switcher](feature-specs/project-switcher.md) - Original spec for project switcher UI
- [Startup Coordinator](feature-specs/startup-coordinator.md) - Design rationale for deterministic startup (shipped in 531ac70)
- [Status Bar](feature-specs/status-bar.md) - LLM status monitoring design

### completed-work/
**Topics:** Historical implementation plans, analysis docs, and research
- Old implementation plans from before /tmp/ workflow
- Technical analyses and research docs
- Planning documents for shipped features
- RAG feature research and roadmaps

**Note:** This is a catch-all for historical docs that don't fit investigations/ or feature-specs/. Most documents from the old `build/notes/archive/` and `build/notes/research/rag/` ended up here.

---

## What Belongs in Archive?

### ✅ DO Archive:
- Completed debugging investigations (with resolution noted)
- Original feature specs AFTER feature ships
- Technical analyses that led to architectural decisions
- Research docs for experimental features (RAG, embedding search, etc.)
- Implementation plans that are no longer active

### ❌ DON'T Archive:
- Current state documentation (goes in architecture/, components/, etc.)
- Active planning docs (goes in /tmp/, NOT in repo)
- Partial or abandoned work without context
- Duplicate information already in current docs

---

## Using Archived Docs

**When referencing archived docs:**
```markdown
See original design in [archive/feature-specs/project-switcher.md](../archive/feature-specs/project-switcher.md) for context on why we chose tabs over sidebar.
```

**When creating new archived docs:**
```bash
# After completing an investigation
vim build/docs/archive/investigations/2025-11-XX-issue-name.md
git add build/docs/archive/
git commit -m "docs(archive): preserve investigation for issue XYZ"

# After shipping a feature with interesting design decisions
vim build/docs/archive/feature-specs/my-feature.md
git add build/docs/archive/
git commit -m "docs(archive): preserve design rationale for my-feature"
```

---

## Relationship to Other Docs

- **Architecture/** - Current state, may reference archived docs for historical context
- **Components/** - Current implementation, may link to investigations for bug context
- **Guides/** - Operational docs, may reference archived investigations for troubleshooting

---

## Archive Organization

Documents are organized by:
1. **Type** (investigations vs feature-specs vs completed-work)
2. **Date** (where applicable, use YYYY-MM-DD prefix for chronological sorting)

**Naming conventions:**
- Investigations: `YYYY-MM-DD-issue-name.md` (e.g., `2025-11-05-main-thread-blocking.md`)
- Feature specs: `feature-name.md` (e.g., `project-switcher.md`)
- Completed work: Original filename or descriptive name

---

## Note on 2025-11-08 Reorganization

This archive contains documents from the 2025-11-08 holistic documentation reorganization:
- Historical docs from `build/notes/archive/` → `completed-work/`
- Completed investigations from `build/notes/technical-reference/` → `investigations/`
- Original specs from `build/notes/feature-specs/` → `feature-specs/`
- RAG research from `build/notes/research/rag/` → `completed-work/`

See [HOLISTIC-DOCS-ORGANIZATION-PLAN.md](../../notes/HOLISTIC-DOCS-ORGANIZATION-PLAN.md) for migration details.
