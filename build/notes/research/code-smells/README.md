# Code Smell Research - November 2025

**Date:** 2025-11-23
**Status:** Analysis Complete, Ready for Implementation

## Overview

This directory contains comprehensive code smell analysis from three parallel investigations that audited the Contextify codebase from different angles.

## Key Documents

### Primary Analysis
- **CONSOLIDATED-CODE-SMELL-ANALYSIS.md** - **START HERE**
  - Master analysis combining all findings
  - Deduplication results
  - Holistic refactoring opportunities
  - Phased action plan (83 hours over 3 months)
  - Integration with TODOS.md and ROADMAP.md

### Supporting Reports (Keep for Reference)

- **code-smell-audit-2025-11-23.md**
  - Comprehensive catalog of 10 anti-patterns
  - Detailed examples and instances
  - Good for understanding pattern context

- **sql-duplication-audit.md**
  - Deep dive into SQL layer architecture
  - 43 SQL locations cataloged
  - Functional duplicate analysis

- **observable-state-sync-audit.md**
  - Deep dive into @Observable state bugs
  - 23 DB write operations analyzed
  - Race condition analysis

### Draft Guidelines (To Be Integrated)

These were extracted from the reports and should be integrated into CLAUDE.md:

- **claude-md-guidelines-code-quality.md**
  - Comprehensive prevention guidelines
  - SQL query patterns
  - State management patterns
  - Layer discipline patterns

- **sql-guidelines-for-claude-md.md**
  - SQL-specific section for CLAUDE.md
  - Repository layer discipline
  - Filter requirements
  - Query builder vs raw SQL

### Implementation Plans (Superseded by Consolidated Doc)

- **code-smell-hotspots.md** - Heat map by file and feature
- **code-smell-p0-fixes.md** - P0 quick-fix list
- **code-smell-refactoring-roadmap.md** - Phased refactoring plan
- **sql-duplication-hotfixes.md** - SQL-specific P0 fixes

*Note: These are now superseded by the consolidated analysis but kept for historical reference.*

## Summary of Findings

### Critical Issues (P0)
1. Missing `display_in_timeline = 1` filter in 3 query methods
2. Unread counts don't update after viewing project
3. Orphaned project status doesn't refresh UI

### High-Risk Patterns (P1)
1. SQL duplication (Orchestrator bypassing Repository)
2. Layer violations (UI importing GRDB)
3. Detached tasks without cancellation (25 instances)
4. Unsafe concurrent access (22 usages to audit)

### Code Quality Issues (P2)
1. God classes (8 files over 1000 lines)
2. Inconsistent error handling
3. Primitive obsession

## Integration Status

### Already in TODOS.md
- ✅ #P1-QUERY-CENTRALIZE - Query builder pattern (matches our recommendation)
- ✅ Evidence of `getEntriesAfterCursor()` issue already documented

### Needs Addition to TODOS.md
See CONSOLIDATED-CODE-SMELL-ANALYSIS.md § "Integration with TODOS.md and ROADMAP.md"

- P0: 3 critical bugs
- P1: 4 architectural violations
- P2: 4 quality improvements
- P3: 2 long-term refactorings

### Needs Addition to ROADMAP.md
- P4: 4 future considerations
- P5: 3 research questions

## Metrics

**Current Health Score:** 75/100 (updated 2025-12-31; P0 bugs fixed in commit ad190448)

**Target Health Score:** >90/100

**Estimated Effort to Target:**
- Phase 1 (Critical Bugs): 3 hours
- Phase 2 (Fragility): 20 hours
- Phase 3 (Architecture): 60 hours
- **Total: ~83 hours over 3 months**

## Next Steps

1. **Review** CONSOLIDATED-CODE-SMELL-ANALYSIS.md
2. **Decide** on Phase 1 priority
3. **Execute** critical bug fixes (Week 1, 3 hours)
4. **Update** TODOS.md with P0 items
5. **Integrate** guidelines into CLAUDE.md
6. **Track** progress with weekly metrics

## Branch History

**Source Branches:**
- `claude/audit-code-smells-01Xorkk1r3H4K1VcuVq63jMs`
- `claude/investigate-sql-duplication-015TXEzexTX38cf4xdG92DVC`
- `claude/fix-observable-state-sync-01A7DEvMHbKaEqAkRzN6frsT`

**Consolidation Branch:**
- `claude/consolidate-code-smell-reports` (this branch)

## References

- TODOS.md § #P1-QUERY-CENTRALIZE
- build/notes/todo-support/P1-QUERY-CENTRALIZE-design.md
- build/notes/todo-support/P1-QUERY-CENTRALIZE-source-analysis.md

---

**Status:** Analysis complete. Ready for implementation planning and execution.
