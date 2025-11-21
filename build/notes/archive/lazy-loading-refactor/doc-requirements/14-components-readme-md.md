# Change Requirements: build/docs/components/README.md

**Document:** `build/docs/components/README.md`
**Priority:** 5 (READMEs)
**Impact:** Low - Components directory index
**Estimated Effort:** 30 minutes

---

## Current State Analysis

**File:** Directory index listing component documents
**Current Content:**
- Lists component docs with brief descriptions

**Issues:**
1. No mention of LightweightDiscoveryService
2. ProjectDiscoveryService description doesn't mention Phase 3 role change
3. StartupCoordinator description doesn't mention legacy status

---

## Required Changes

### 1. Add Phase 3 Note at Top

```markdown
# Component Documentation

**Status:** Updated for Phase 3 lazy loading architecture (Nov 2025)

**New in Phase 3:**
- AppStateOrchestrator (see `../architecture/COMPONENTS.md`)
- LightweightDiscoveryService (two-tier discovery)

---
```

### 2. Update Component Descriptions

```markdown
## Discovery & Coordination

**project-discovery.md** - Project discovery patterns and multi-provider support
- **Phase 3:** Two-tier architecture (lightweight + full discovery)

**project-discovery-service-implementation.md** - Implementation guide for discovery services
- **Updated for Phase 3:** LightweightDiscoveryService (Tier 1), ProjectDiscoveryService (Tier 2)
- Stat-only scanning patterns

**startup-coordinator-implementation.md** - Startup coordination implementation
- **Phase 3 Note:** StartupCoordinator now legacy compatibility shim
- See AppStateOrchestrator for new architecture

---

## State Management

**active-session-policy.md** - Active transcript following policy
- Unchanged in Phase 3

**timeline-cache.md** - Timeline cache and LLM integration
- Unchanged in Phase 3 (ConversationMonitor not refactored)

**timeline-cache-invalidation.md** - Cache invalidation strategies
- Unchanged in Phase 3

---

## Data Layer

**database-migration.md** - Database migration between locations
- Unchanged in Phase 3

**transcript-ingestion.md** - Transcript parsing and ingestion
- Unchanged in Phase 3 (HooverEngine stable)

---

## Infrastructure

**error-handling-security-scope.md** - Error handling for security-scoped bookmarks
- Unchanged in Phase 3

---
```

### 3. Add Phase 3 References Section

```markdown
## Phase 3 Architecture

**For AppStateOrchestrator:**
- See: `../architecture/COMPONENTS.md` - "Application State Coordination"
- Code: `app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift`

**For LightweightDiscoveryService:**
- See: `project-discovery-service-implementation.md` - "LightweightDiscoveryService Implementation"
- Code: `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift`

---
```

**Estimated Effort:** 30 minutes

---

## Summary of Changes

1. **Add:** Phase 3 status note (~8 lines)
2. **Update:** Component descriptions (Phase 3 notes) (~20 lines modified)
3. **Add:** Phase 3 references section (~12 lines)

**Total Lines Added/Modified:** ~40 lines
**Estimated Effort:** 30 minutes

---

## Validation Checklist

After making changes, verify:

- [ ] All referenced files exist
- [ ] Phase 3 notes accurate
- [ ] Component descriptions match actual docs
- [ ] Cross-references resolve
- [ ] Code file paths correct

---

**Document Version:** 1.0
**Created:** 2025-11-19
**Implements:** Phase 3 documentation update item #14
