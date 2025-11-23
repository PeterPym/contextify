# Code Smell Hotspots - Issue Concentration Map

**Date:** 2025-11-23
**Purpose:** Identify files and features with highest concentration of issues
**Usage:** Prioritize refactoring, focus code review attention

---

## Heat Map - Files by Issue Density

### 🔥🔥🔥 Critical Hotspots (3+ P0/P1 issues)

#### 1. TranscriptOrchestrator.swift
**Lines:** 2,134 | **Issues:** 15+ | **P0/P1:** 5

**Problems:**
- ❌ Raw SQL bypassing Repository (4 queries)
- ❌ Missing display_in_timeline filter (2 queries)
- ⚠️ God class (too many responsibilities)
- ⚠️ Layer violation (should delegate to Repository)

**Specific Issues:**
| Line | Issue | Priority |
|------|-------|----------|
| 2091 | getEntriesAfterCursor - missing filter | P0 |
| 2102 | getEntriesAfterCursor (no cursor) - missing filter | P0 |
| 1770 | markProjectViewed doesn't return state | P1 |
| 326, 440, 473, 663, 1256, 2051, 2060 | Raw SQL (7 locations) | P1 |

**Impact:**
- User-visible bugs (hidden entries shown)
- High duplication (queries reimplemented)
- Hard to maintain (2100+ lines)

**Recommendation:**
- **Immediate:** Fix missing filters (Fix #3)
- **Short-term:** Make markProjectViewed return state (Fix #5)
- **Long-term:** Extract responsibilities, delegate to Repository

---

#### 2. ConversationMonitor.swift
**Lines:** 3,189 | **Issues:** 12+ | **P0/P1:** 3

**Problems:**
- ⚠️ God class (timeline + cache + monitoring + coordination)
- ⚠️ Too many detached tasks without cancellation (8 tasks)
- ⚠️ Complex state management (hard to track mutations)

**Specific Issues:**
| Line | Issue | Priority |
|------|-------|----------|
| 1594 | Task.detached for cursor persistence - not cancellable | P1 |
| 342, 399, 462, 527, 555 | More detached/uncancelled tasks | P1 |
| 71-195 | Complex nested state classes | P2 |

**Impact:**
- Resource leaks (tasks running after view dismissed)
- Race conditions (stale updates)
- Hard to understand (too many responsibilities)

**Recommendation:**
- **Short-term:** Make tasks cancellable, store references
- **Long-term:** Split into TimelineState, TimelineLoader, CacheCoordinator, SessionMonitor

---

#### 3. Repositories.swift
**Lines:** 1,125 | **Issues:** 8 | **P0/P1:** 3

**Problems:**
- ❌ Missing display_in_timeline filter (2 methods)
- ⚠️ Multiple repository patterns in one file
- ⚠️ Raw SQL in some methods

**Specific Issues:**
| Line | Issue | Priority |
|------|-------|----------|
| 363 | byTranscript - missing filter | P0 |
| 373 | search - missing filter | P0 |
| 411, 450, 537, 605, 679, 915 | Raw SQL (6 locations) | P1 |

**Impact:**
- User-visible bugs (search shows hidden entries)
- Inconsistent query patterns

**Recommendation:**
- **Immediate:** Fix missing filters (Fix #1, #2)
- **Long-term:** Consider query builder pattern

---

#### 4. ProjectSwitcherState.swift
**Lines:** 962 | **Issues:** 6 | **P0/P1:** 2

**Problems:**
- ❌ State not refreshed after markProjectViewed (lines 608-619)
- ⚠️ Multiple detached tasks (4 tasks)
- ⚠️ Complex state mutations

**Specific Issues:**
| Line | Issue | Priority |
|------|-------|----------|
| 612-614 | markProjectViewed without state refresh | P0 |
| 312, 545, 600, 608 | Task.detached not tracked | P1 |

**Impact:**
- Unread counts don't update after viewing
- Resource leaks from uncancelled tasks

**Recommendation:**
- **Immediate:** Add state refresh after markProjectViewed (Fix #4)
- **Short-term:** Track and cancel all tasks

---

### 🔥🔥 Moderate Hotspots (1-2 P0/P1 issues)

#### 5. FoundationLLM.swift
**Lines:** 2,096 | **Issues:** 3 | **P0/P1:** 1

**Problems:**
- ⚠️ God class (LLM calls + prompts + parsing + caching)
- ⚠️ Complex error handling (multiple catch types)

**Recommendation:** Split into PromptBuilder, ResponseParser, LLMClient

---

#### 6. HUDCore.swift
**Lines:** 1,196 | **Issues:** 2 | **P0/P1:** 1

**Problems:**
- ⚠️ nonisolated(unsafe) for mutable state (line 28)
- ⚠️ Multiple responsibilities

**Specific Issues:**
| Line | Issue | Priority |
|------|-------|----------|
| 28 | hasWarnedLegacyDefaults - unsafe mutable | P1 |

**Recommendation:** Use actor isolation for mutable flags

---

#### 7-8. More Files Over 1000 Lines

| File | Lines | Main Issue |
|------|-------|------------|
| TranscriptInventoryView.swift | 1,173 | UI + business logic mixed |
| ProjectDiscoveryService.swift | 1,123 | Discovery + validation + persistence |
| TranscriptParsers.swift | 1,115 | Multiple parser implementations |

**Priority:** P2 (refactor during feature work)

---

### 🔥 Minor Hotspots (P2/P3 issues only)

#### UI Files with GRDB Import

| File | Line | Issue | Priority |
|------|------|-------|----------|
| TranscriptMetadataOrchestrator.swift | 5 | import GRDB | P1 |
| BatchEmbeddingView.swift | 3 | import GRDB | P1 |
| SemanticSearchView.swift | 4 | import GRDB | P1 |
| EmbeddingDatabaseTestView.swift | 3 | import GRDB | P2 (test UI) |
| ProjectBadgesContainer.swift | 3 | import GRDB | P1 |

**Recommendation:** Move all database access to Orchestrator

---

## Heat Map - Features by Issue Concentration

### Timeline Entry Loading ⚠️ CRITICAL
**Total Issues:** 13 | **P0:** 3 | **Impact:** High

**Problem:** 48% of queries missing display_in_timeline filter

**Affected Paths:**
- Load by transcript (byTranscript) - MISSING FILTER
- Search entries (search) - MISSING FILTER
- Incremental updates (getEntriesAfterCursor) - MISSING FILTER
- Recent feed (recentFeed) - ✅ Has filter
- New entries (newEntries) - ✅ Has filter

**Impact:**
- Hidden entries shown in timeline UI
- ~480 unnecessary LLM summary calls
- User confusion

**Fix:** See P0 fixes #1-3

---

### Project Switching/Viewing ⚠️ HIGH
**Total Issues:** 6 | **P0:** 1 | **Impact:** High

**Problem:** State not synced after database writes

**Affected Operations:**
- Mark project viewed - NO STATE REFRESH ❌
- Mark project selected - NO STATE REFRESH ❌
- Hide project - ✅ Has refresh
- Unhide project - ✅ Has refresh

**Impact:**
- Unread counts stale
- Requires manual refresh
- Confusing UX

**Fix:** See P0 fixes #4-5

---

### Cache Management ⚠️ MEDIUM
**Total Issues:** 5 | **P1:** 2 | **Impact:** Medium

**Problem:** Detached tasks without cancellation

**Affected Operations:**
- Cache miss generation (ongoing task)
- Cursor persistence (fire-and-forget)
- Cache refresh (debounced task)

**Impact:**
- Wasted LLM calls
- Resource leaks
- Race conditions

**Fix:** Track and cancel tasks

---

### LLM Summarization ⚠️ MEDIUM
**Total Issues:** 3 | **P1:** 1 | **Impact:** Medium

**Problem:** Complex coordination in FoundationLLM (2096 lines)

**Impact:**
- Hard to maintain
- Error handling inconsistent
- Resource usage unclear

**Fix:** Split responsibilities (long-term)

---

## Heat Map - By Anti-Pattern Type

### SQL Duplication & Missing Filters
**Files Affected:** 3
**Total Instances:** 13
**Priority:** P0

**Hottest Files:**
1. TranscriptOrchestrator.swift (4 missing filters, 7 raw SQL)
2. Repositories.swift (2 missing filters, 6 raw SQL)

---

### Observable State Sync Violations
**Files Affected:** 2
**Total Instances:** 2
**Priority:** P0

**Hottest Files:**
1. ProjectSwitcherState.swift (markProjectViewed, markProjectSelected)

---

### Layer Violations
**Files Affected:** 5 UI files + 1 Orchestrator
**Total Instances:** 11
**Priority:** P1

**Hottest Files:**
1. TranscriptOrchestrator.swift (bypassing Repository)
2. BatchEmbeddingView.swift (UI → DB)

---

### God Classes
**Files Affected:** 8
**Priority:** P2

**Largest:**
1. ConversationMonitor.swift (3,189 lines)
2. TranscriptOrchestrator.swift (2,134 lines)
3. FoundationLLM.swift (2,096 lines)

---

### Detached Tasks Without Cancellation
**Files Affected:** 3
**Total Instances:** 25
**Priority:** P1

**Hottest Files:**
1. ConversationMonitor.swift (8 tasks)
2. ProjectSwitcherState.swift (4 tasks)
3. SettingsView.swift (2 tasks)

---

### Unsafe Concurrent Access
**Files Affected:** 6
**Total Instances:** 22
**Priority:** P1 (verify safety)

**Files to Audit:**
1. HUDCore.swift (2 unsafe properties)
2. StartupCoordinator.swift (2 properties)
3. ISO8601Z.swift, TranscriptMetadataOrchestrator.swift (singletons)

---

## Clean Areas (Low Issue Density)

### 🟢 Exemplary Code - Learn From These

| File | Lines | Why It's Good |
|------|-------|---------------|
| DatabaseSchema.swift | ~900 | Clear migrations, single responsibility |
| ProjectModel.swift | ~100 | Simple data models, focused |
| ISO8601Z.swift | ~50 | Clean utility, proper isolation |
| PathNormalizer.swift | ~150 | Single purpose, testable |
| ProjectIdentity.swift | ~100 | Focused, pure functions |

**Common patterns in clean code:**
- Single, clear responsibility
- Small file size (<500 lines)
- No state management complexity
- Pure functions or simple utilities
- Well-tested

---

## Prioritized Refactoring Targets

### Week 1 (Critical)
1. **Repositories.swift** - Fix missing filters (Fix #1-2)
2. **TranscriptOrchestrator.swift** - Fix missing filters (Fix #3)
3. **ProjectSwitcherState.swift** - Add state refresh (Fix #4-5)

**Effort:** ~3 hours | **Impact:** Fixes user-visible bugs

---

### Month 1 (High Priority)
1. **TranscriptOrchestrator.swift** - Delegate to Repository (eliminate raw SQL)
2. **ConversationMonitor.swift** - Make tasks cancellable
3. **UI files** - Remove GRDB imports, use Orchestrator
4. **HUDCore.swift** - Fix unsafe mutable state

**Effort:** ~20 hours | **Impact:** Reduces fragility, improves maintainability

---

### Quarter 1 (Long-term)
1. **ConversationMonitor.swift** - Split into focused classes
2. **TranscriptOrchestrator.swift** - Extract responsibilities
3. **FoundationLLM.swift** - Split LLM coordination
4. **Implement query builder** - Prevent filter bugs systematically

**Effort:** ~60 hours | **Impact:** Long-term maintainability, prevents new issues

---

## Code Review Focus Areas

**When reviewing PRs touching these files, pay extra attention:**

### 🔴 High-Risk Files (Review Every Change Carefully)
- TranscriptOrchestrator.swift
- ConversationMonitor.swift
- Repositories.swift
- ProjectSwitcherState.swift

**Check for:**
- ✅ display_in_timeline filter in any new entry queries
- ✅ State refresh after database writes
- ✅ Tasks are cancellable
- ✅ No new raw SQL in Orchestrator

### 🟡 Medium-Risk Files (Standard Review)
- FoundationLLM.swift
- HUDCore.swift
- Any file over 1000 lines

**Check for:**
- ✅ No new nonisolated(unsafe) without justification
- ✅ Error handling consistent with layer
- ✅ No new responsibilities added to god classes

### 🟢 Low-Risk Files (Quick Review)
- Model files (ProjectModel, etc.)
- Utilities (ISO8601Z, PathNormalizer, etc.)
- Small focused files (<300 lines)

---

## Metrics Dashboard

### Overall Health Score: 62/100 ⚠️

**Breakdown:**
- SQL query consistency: 52% (target: 100%)
- State sync discipline: 33% (target: 100%)
- Layer boundary respect: 90% (target: 100%)
- File size health: 80% (8 files >1000 lines)
- Concurrency safety: 70% (22 unsafe usages to verify)
- Error handling consistency: 60% (varying strategies)

**Target:** >90% across all metrics

---

## Next Steps

1. **This Week:** Apply P0 fixes (#1-6) - 3 hours
2. **This Month:** Address P1 layer violations - 20 hours
3. **This Quarter:** Refactor god classes - 60 hours
4. **Ongoing:** Enforce guidelines in code review

---

**End of Hotspot Map**

**Last Updated:** 2025-11-23
**Next Review:** After P0 fixes applied (reassess hotspots)
