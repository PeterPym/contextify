# Change Requirements: build/docs/architecture/README.md

**Document:** `build/docs/architecture/README.md`
**Priority:** 5 (READMEs)
**Impact:** Low - Architecture directory index
**Estimated Effort:** 30 minutes

---

## Current State Analysis

**File:** Directory index listing architecture documents
**Current Content:**
- Lists architecture docs with brief descriptions
- Reading order recommendations

**Issues:**
1. Descriptions don't reflect Phase 3 changes
2. No mention of AppStateOrchestrator as central coordinator
3. Reading order should prioritize Phase 3 docs

---

## Required Changes

### 1. Update Document Descriptions

**Add Phase 3 Note at Top:**

```markdown
# Architecture Documentation

**Status:** Updated for Phase 3 lazy loading architecture (Nov 2025)

**Start Here for Phase 3:** `COMPONENTS.md` - "Application State Coordination" section

---
```

**Update Individual Descriptions:**

```markdown
## Core Architecture

**COMPONENTS.md** - Architecture overview and key components
- **Updated for Phase 3:** AppStateOrchestrator (central coordinator), LightweightDiscoveryService, lazy loading architecture
- **Start here** for understanding the system

**data-pipeline-architecture.md** - Complete data flow reference (5 levels of detail)
- **Updated for Phase 3:** Lightweight startup flow, JIT ingestion, background indexing
- Comprehensive with mermaid diagrams

**startup-coordinator.md** - Startup sequencing and project identity
- **Phase 3 Note:** StartupCoordinator now legacy compatibility shim (AppStateOrchestrator is primary)
- Will be removed in Phase 4

**architecture-refactoring-analysis.md** - Refactoring opportunities and roadmap
- **Updated for Phase 3:** 85% alignment achieved, architecture grade A- (up from B+)
- Phase 4 planning document

---

## Specialized Topics

**llm-processing.md** - LLM queue architecture (timeline summaries, transcript metadata)
- Unchanged in Phase 3 (ConversationMonitor not refactored)

**conversation-monitor-state.md** - Timeline state management
- Unchanged in Phase 3 (deferred to Phase 4)

**sql-backend.md** - Database layer (GRDB, schema v26, migrations)
- Unchanged in Phase 3 (database layer stable)

**project-switcher.md** - Multi-project UI patterns
- Unchanged in Phase 3

**transcript-access-security.md** - Security-scoped bookmarks (App Store builds)
- Unchanged in Phase 3

**sandbox-appstore-architecture.md** - Sandboxed build patterns
- Unchanged in Phase 3

**window-system.md** - Window management patterns
- Unchanged in Phase 3

---
```

### 2. Add Recommended Reading Order Section

```markdown
## Recommended Reading Order

### For Understanding Phase 3 Architecture

1. **COMPONENTS.md** - Start with "Application State Coordination" section
2. **data-pipeline-architecture.md** - Level 1-3 (skip Level 4-5 initially)
3. **architecture-refactoring-analysis.md** - Read Phase 3 update section

### For Deep Dive

4. **data-pipeline-architecture.md** - Level 4-5 (implementation details)
5. **startup-coordinator.md** - Legacy integration patterns
6. **llm-processing.md** - Timeline cache and LLM queues

### For Phase 4 Planning

7. **architecture-refactoring-analysis.md** - Full roadmap
8. **conversation-monitor-state.md** - What will be refactored

---
```

### 3. Add Cross-References Section

```markdown
## Phase 3 References

**Implementation Guides:**
- `../components/project-discovery-service-implementation.md` - Two-tier discovery
- `../components/startup-coordinator-implementation.md` - Legacy integration

**Analysis:**
- `../../notes/phase3-refactor-comparison-analysis.md` - Detailed comparison
- `../../notes/phase3-documentation-update-master-list.md` - Doc update tracker

---
```

**Estimated Effort:** 30 minutes

---

## Summary of Changes

1. **Add:** Phase 3 status note (~5 lines)
2. **Update:** Document descriptions (Phase 3 notes) (~40 lines modified)
3. **Add:** Recommended reading order (~25 lines)
4. **Add:** Phase 3 cross-references (~10 lines)

**Total Lines Added/Modified:** ~80 lines
**Estimated Effort:** 30 minutes

---

## Validation Checklist

After making changes, verify:

- [ ] All referenced files exist
- [ ] Phase 3 notes accurate
- [ ] Reading order logical
- [ ] Cross-references resolve
- [ ] Descriptions match actual content

---

**Document Version:** 1.0
**Created:** 2025-11-19
**Implements:** Phase 3 documentation update item #13
