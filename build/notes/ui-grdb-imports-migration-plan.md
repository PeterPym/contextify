# UI Layer GRDB Imports - Migration Plan

**Date:** 2025-11-23
**Priority:** P1 (Layer boundary violation)
**Status:** Documented, ready for implementation

---

## Summary

5 UI layer files directly import GRDB and execute database queries, violating the intended architecture. All database access should go through the Orchestrator layer.

**Architecture:** UI → State → Orchestrator → Repository → Database

---

## Files Requiring Migration

| File | Type | Lines | Database Operations | Priority |
|------|------|-------|---------------------|----------|
| TranscriptMetadataOrchestrator.swift | Orchestrator (misplaced) | ~800 | Metadata CRUD | P1 - High |
| SemanticSearchView.swift | Search UI | ~400 | Search queries | P1 - High |
| BatchEmbeddingView.swift | Admin UI | ~400 | Embedding stats | P1 - Medium |
| ProjectBadgesContainer.swift | Widget | ~100 | Badge counts | P1 - Medium |
| EmbeddingDatabaseTestView.swift | Test UI | ~100 | Debug queries | P2 - Low |

---

## File #1: TranscriptMetadataOrchestrator.swift (High Priority)

**Issue:** This is an Orchestrator class placed in the UI layer (Contextify/Contextify/)
**Correct location:** Should be in app/Sources/ContextifyCore/Database/

### Migration Steps

1. **Move file** from `Contextify/Contextify/` to `app/Sources/ContextifyCore/Database/`
2. **Remove `import GRDB`** from the file (should use Repository layer)
3. **Update imports** in files that reference it
4. **Verify tests** still pass after move

**Effort:** 30 minutes
**Impact:** High - fixes architectural layering issue

---

## File #2: SemanticSearchView.swift (High Priority)

**Issue:** Search UI directly queries database for search results

### Current Pattern (Bad)

```swift
import GRDB

struct SemanticSearchView: View {
  @State var db: DatabasePool
  @State var results: [SearchResult] = []

  func search() {
    results = try! db.read { db in
      // Direct database query
      try Row.fetchAll(db, sql: "SELECT ... FROM ...")
    }
  }
}
```

### Target Pattern (Good)

```swift
// No GRDB import

struct SemanticSearchView: View {
  @State var searchService: SearchService
  @State var results: [SearchResult] = []

  func search() async {
    results = try await searchService.search(query: query)
  }
}
```

### Migration Steps

1. **Add async methods to SearchService/HybridSearchService**
   - `search(query: String, projectId: String?) async throws -> [SearchResult]`
2. **Update SemanticSearchView** to call SearchService instead of DB
3. **Remove `import GRDB`** from SemanticSearchView
4. **Test** search functionality works

**Effort:** 1 hour
**Impact:** High - main search feature

---

## File #3: BatchEmbeddingView.swift (Medium Priority)

**Issue:** Admin UI for batch embedding generation queries database for stats

### Database Operations

- Count entries by content length
- Count entries with/without embeddings
- Trigger embedding generation

### Migration Steps

1. **Add methods to EmbeddingOrchestrator:**
   - `getContentLengthStats() async throws -> ContentStats`
   - `getEmbeddingCoverageStats() async throws -> EmbeddingStats`
2. **Update BatchEmbeddingView** to use Orchestrator
3. **Remove `import GRDB`**

**Effort:** 1 hour
**Impact:** Medium - admin tool, not critical path

---

## File #4: ProjectBadgesContainer.swift (Medium Priority)

**Issue:** Widget queries database for badge counts

### Database Operations

- Count unread entries per project
- Get project metadata for badges

### Migration Steps

1. **Add method to TranscriptOrchestrator:**
   - `getBadgeCounts(projectIds: [String]) async throws -> [String: Int]`
2. **Update ProjectBadgesContainer** to use Orchestrator
3. **Remove `import GRDB`**

**Effort:** 30 minutes
**Impact:** Medium - widget display

---

## File #5: EmbeddingDatabaseTestView.swift (Low Priority)

**Issue:** Test/debug UI for viewing embedding database state

### Migration Steps

**Option A:** Move to test target (if it's just for testing)
**Option B:** Add debug methods to EmbeddingOrchestrator
**Option C:** Leave as-is and document exception (it's a debug tool)

**Recommendation:** Option C - document as exception for now

**Effort:** N/A (defer)
**Impact:** Low - debug tool only

---

## Implementation Plan

### Phase 1: High Priority (Week 1)

**Tasks:**
1. ✅ Move TranscriptMetadataOrchestrator to correct layer
2. ✅ Migrate SemanticSearchView to use SearchService

**Effort:** 1.5 hours
**Impact:** Fixes main architectural violations

### Phase 2: Medium Priority (Week 2)

**Tasks:**
1. ✅ Migrate BatchEmbeddingView to use EmbeddingOrchestrator
2. ✅ Migrate ProjectBadgesContainer to use TranscriptOrchestrator

**Effort:** 1.5 hours
**Impact:** Completes UI layer cleanup

### Phase 3: Document Exception (Week 2)

**Tasks:**
1. ✅ Add comment to EmbeddingDatabaseTestView explaining exception
2. ✅ Or move to test target if appropriate

**Effort:** 15 minutes
**Impact:** Clarifies architectural boundaries

---

## Verification

After migration, verify:

```bash
# Should return no results (or only EmbeddingDatabaseTestView if exception documented)
rg "import GRDB" --type swift Contextify/Contextify/

# Verify no direct database access in UI
rg "DatabasePool|Database\(" --type swift Contextify/Contextify/ | grep -v "// Test"
```

---

## Benefits

**Architecture:**
- Clear layer boundaries (UI → Orchestrator → Repository → DB)
- Easier to test (mock Orchestrator, no need for DB)
- Easier to refactor database layer

**Maintainability:**
- Database changes don't affect UI directly
- Business logic centralized in Orchestrator
- Consistent patterns across codebase

**Type Safety:**
- Orchestrator provides typed interfaces
- No raw SQL strings in UI layer
- Compiler catches API changes

---

## Current Status

**Completed:**
- P0 critical fixes (SQL filters, state sync)
- P1 unsafe concurrency fix
- Documentation of UI GRDB import issue

**Remaining:**
- 5 files to migrate (3.5 hours total effort)
- Recommended: Do in phases over 2 weeks

---

## Next Steps

1. **This Week:** Move TranscriptMetadataOrchestrator + Migrate SemanticSearchView
2. **Next Week:** Migrate BatchEmbeddingView + ProjectBadgesContainer
3. **Document:** EmbeddingDatabaseTestView exception (or move to tests)

---

**Status:** Ready for implementation
**Estimated Total Effort:** 3.5 hours (2 weeks, phased approach)
