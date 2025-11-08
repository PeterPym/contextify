# Contextify Documentation

**Last Updated:** 2025-11-08
**Purpose:** Current state documentation, architectural decisions, operational guides

---

## Quick Navigation

| Category | Purpose | Key Documents |
|----------|---------|---------------|
| **Architecture** | System design & data flow | [Data Flow](architecture/data-flow.md), [SQL Backend](architecture/sql-backend.md), [LLM Processing](architecture/llm-processing.md) |
| **Components** | Individual subsystems | [Transcript Ingestion](components/transcript-ingestion.md), [Timeline Cache](components/timeline-cache.md) |
| **Specifications** | External dependencies | [Claude Code Format](specifications/claude-code-format.md) |
| **Guides** | How-to documentation | [Diagnostics API](guides/diagnostics-api.md), [Linux CI](guides/linux-ci-builds.md) |
| **Design** | Design decisions | [Color Scheme](design/color-scheme.md), [Help System](design/help-tooltip-ux-system.md) |
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

**Key docs:**
- [Data Flow](architecture/data-flow.md) - End-to-end data pipeline (discovery → database → UI)
- [SQL Backend](architecture/sql-backend.md) - Database architecture and schema (current: v21)
- [LLM Processing](architecture/llm-processing.md) - Dual-queue LLM system (FoundationLLM)
- [Startup Coordinator](architecture/startup-coordinator.md) - Project identity pipeline
- [Window System](architecture/window-system.md) - 4-window macOS app architecture

### components/
Component-specific implementation details. How individual subsystems work.

**Key docs:**
- [Transcript Ingestion](components/transcript-ingestion.md) - HooverEngine streaming parser
- [Timeline Cache](components/timeline-cache.md) - LLM-generated summary caching
- [Project Discovery](components/project-discovery.md) - Multi-project detection

### specifications/
External dependency formats. Claude Code transcripts, Codex transcripts, etc.

**Key docs:**
- [Claude Code Format](specifications/claude-code-format.md) - Claude Code JSONL format specification

### guides/
Operational how-to docs. How to use diagnostics API, build on Linux, etc.

**Key docs:**
- [Diagnostics API](guides/diagnostics-api.md) - HTTP API for debugging (DEBUG builds)
- [Linux CI Builds](guides/linux-ci-builds.md) - Building from non-macOS environments
- [Logging Best Practices](guides/logging-best-practices.md) - OSLog usage guidelines
- [Feature Flags](guides/feature-flags.md) - Feature flag documentation

### design/
Design decisions. Color scheme, typography, help system UX.

**Key docs:**
- [Color Scheme](design/color-scheme.md) - Color palette and usage
- [Help System](design/help-tooltip-ux-system.md) - Help tooltip UX system

### operations/
Release management, app store submission, marketing materials.

**Subdirectories:**
- `app-store/` - Sandbox requirements, submission checklist
- `marketing/` - Show HN draft, distribution strategy
- `release/` - Notarization, build verification, release readiness

### archive/
Historical context. Completed investigations, original feature specs (design rationale).

**Subdirectories:**
- `investigations/` - Completed debugging sessions (CXT-10, intent classification, etc.)
- `feature-specs/` - Original feature specs (project switcher, startup coordinator, status bar)
- `completed-work/` - Historical implementation plans and analysis docs

---

## Contributing to Documentation

### When to Document

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

### Where to Plan

**When planning a new feature:**
```bash
# Create planning docs in /tmp/ (NOT in repo)
mkdir -p /tmp/contextify-my-feature
echo "# Implementation Plan" > /tmp/contextify-my-feature/plan.md
echo "# Checklist" > /tmp/contextify-my-feature/checklist.md

# Work on feature, update /tmp/ docs as needed
# Ship feature
# Forget about it (OS cleans /tmp/)
```

### When to Archive

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

## Migration History

**2025-11-08:** Complete reorganization from `build/notes/` to `build/docs/`
- Moved current-state docs to categorized structure
- Archived historical docs (investigations, feature specs)
- Deleted stale tracking files and implementation plans
- See: [HOLISTIC-DOCS-ORGANIZATION-PLAN.md](../notes/HOLISTIC-DOCS-ORGANIZATION-PLAN.md)
