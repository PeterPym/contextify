# Implementation Plan: Transcript Inventory SQL Migration

**Created**: 2025-10-22
**Status**: Planning
**Assignee**: TBD
**Estimated Effort**: 2-3 days
**Risk Level**: Medium

---

## Executive Summary

**Problem**: Transcript Inventory window uses in-memory metadata cache instead of SQL backend, causing metadata loss on app restart and wasted LLM quota.

**Solution**: Migrate TranscriptInventory to use SQL backend for both transcript discovery and metadata storage, mirroring the proven architecture of ConversationMonitor.

**Impact**:
- ✅ Metadata persists across app restarts
- ✅ 80-90% reduction in LLM quota usage (cache reuse)
- ✅ Consistent data model across all windows
- ✅ Faster startup (SQL reads vs LLM regeneration)

**Key Changes**:
1. Add `persistDiscoveredSessions()` method to TranscriptInventoryView
2. Migrate `SidecarMetadataStore` from in-memory to SQL backend
3. Update `TranscriptMetadataOrchestrator` to use SQL
4. Update `.onChange` handler to persist before loading

---

## Scope & Objectives

### In Scope

1. **Database Integration**
   - Persist discovered transcripts to `transcripts` table
   - Migrate metadata storage to `transcript_metadata` table
   - Remove in-memory `SidecarMetadataStore` cache

2. **UI Updates**
   - Update TranscriptInventoryView to use SQL backend
   - Ensure metadata loads from database after restart
   - Maintain existing UI/UX behavior

3. **Testing**
   - Unit tests for new methods
   - Integration tests for SQL persistence
   - Manual testing for restart scenarios

### Out of Scope

1. Schema changes (transcript_metadata table already exists in v4 migration)
2. UI redesign or new features
3. Performance optimization beyond current architecture
4. Migration of existing in-memory data (no users in production yet)

### Success Criteria

- [ ] Transcripts appear in `transcripts` table after discovery
- [ ] Metadata appears in `transcript_metadata` table after generation
- [ ] Metadata survives app restart (no LLM regeneration)
- [ ] Inventory window shows same data as main timeline
- [ ] No performance regression vs current implementation
- [ ] All existing tests pass
- [ ] New tests cover persistence behavior

---

## Implementation Phases

### Phase 1: Add Discovery Persistence (Day 1, Morning)

**Goal**: Ensure discovered transcripts are written to database

**Files to Modify**:
- `Contextify/Contextify/TranscriptInventoryView.swift`

**Changes**:

#### 1.1 Add `persistDiscoveredSessions()` Method

**Location**: TranscriptInventoryView.swift (add after line 149)

```swift
/// Persist discovered transcript sessions to database
/// This ensures sessions exist in the transcripts table before loading metadata
private func persistDiscoveredSessions(_ sessions: [TranscriptSession]) async {
    guard let projectId = monitor.currentProjectId,
          let orchestrator = monitor.orchestrator else {
        log.warning("Cannot persist sessions: missing projectId or orchestrator")
        return
    }

    log.debug("Persisting \(sessions.count) discovered sessions to database")

    for session in sessions {
        do {
            // Persist to database (idempotent - safe to call multiple times)
            try orchestrator.discoverTranscript(
                projectId: projectId,
                fileURL: session.fileURL,
                provider: session.provider.rawValue,
                providerSessionId: session.providerSessionId ?? "",
                startWatching: false  // Inventory doesn't need real-time file watching
            )
            log.debug("Persisted transcript: \(session.identifier)")
        } catch {
            log.error("Failed to persist transcript \(session.identifier): \(error.localizedDescription)")
        }
    }

    log.debug("Finished persisting \(sessions.count) sessions")
}
```

#### 1.2 Update `.onChange(of: monitor.allSessions)` Handler

**Location**: TranscriptInventoryView.swift (lines 138-149)

**Before**:
```swift
.onChange(of: monitor.allSessions) { _, newSessions in
    // Clear selection if selected session no longer exists
    if let selectedId = selectedTranscriptId,
       !newSessions.contains(where: { $0.identifier == selectedId }) {
        selectedTranscriptId = nil
    }

    // Load metadata for new sessions (centralized, not per-row)
    Task {
        await loadMetadataForSessions(newSessions)
    }
}
```

**After**:
```swift
.onChange(of: monitor.allSessions) { _, newSessions in
    // Clear selection if selected session no longer exists
    if let selectedId = selectedTranscriptId,
       !newSessions.contains(where: { $0.identifier == selectedId }) {
        selectedTranscriptId = nil
    }

    // PHASE 1: Persist discovered sessions to database
    // This ensures transcripts exist in DB before loading metadata
    Task {
        await persistDiscoveredSessions(newSessions)
    }

    // PHASE 2: Load metadata from database (or generate if missing)
    Task {
        await loadMetadataForSessions(newSessions)
    }
}
```

#### 1.3 Testing Phase 1

**Manual Tests**:
1. Launch app with existing transcript files
2. Open Transcript Inventory window
3. Query database: `SELECT * FROM transcripts`
4. **Expected**: All discovered transcripts appear in table

**Acceptance Criteria**:
- [ ] Transcripts written to database on discovery
- [ ] No duplicate entries (idempotency works)
- [ ] Transcripts have correct project_id, file_path, provider

**Estimated Time**: 2 hours

---

### Phase 2: Migrate Metadata to SQL Backend (Day 1, Afternoon)

**Goal**: Store and retrieve metadata from `transcript_metadata` table instead of in-memory cache

**Files to Modify**:
- `Contextify/Contextify/TranscriptInventoryView.swift`
- `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`

**Changes**:

#### 2.1 Add SQL Methods to TranscriptOrchestrator

**Location**: `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`

**Add Methods**:

```swift
// MARK: - Transcript Metadata Operations

/// Get transcript metadata from database
/// - Parameter transcriptId: Transcript UUID
/// - Returns: TranscriptMetadata if exists, nil otherwise
public func getTranscriptMetadata(transcriptId: String) throws -> TranscriptMetadata? {
    return try dbManager.read { db in
        let row = try Row.fetchOne(db, sql: """
            SELECT transcript_id, title, description, topics, created_at, updated_at
            FROM transcript_metadata
            WHERE transcript_id = ?
        """, arguments: [transcriptId])

        guard let row else { return nil }

        // Parse topics JSON
        let topicsJSON = row["topics"] as? String
        let topics: [String] = (try? JSONDecoder().decode([String].self, from: topicsJSON?.data(using: .utf8) ?? Data())) ?? []

        return TranscriptMetadata(
            title: row["title"] as? String ?? "Untitled Session",
            description: row["description"] as? String ?? "",
            topics: topics
        )
    }
}

/// Save transcript metadata to database
/// - Parameters:
///   - transcriptId: Transcript UUID
///   - metadata: TranscriptMetadata to save
public func saveTranscriptMetadata(transcriptId: String, metadata: TranscriptMetadata) throws {
    let now = Int(Date().timeIntervalSince1970)

    try dbManager.write { db in
        // Encode topics as JSON
        let topicsData = try JSONEncoder().encode(metadata.topics)
        let topicsJSON = String(data: topicsData, encoding: .utf8) ?? "[]"

        // UPSERT (insert or update)
        try db.execute(sql: """
            INSERT INTO transcript_metadata (transcript_id, title, description, topics, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(transcript_id) DO UPDATE SET
                title = excluded.title,
                description = excluded.description,
                topics = excluded.topics,
                updated_at = excluded.updated_at
        """, arguments: [transcriptId, metadata.title, metadata.description, topicsJSON, now, now])
    }
}

/// Delete transcript metadata from database
/// - Parameter transcriptId: Transcript UUID
public func deleteTranscriptMetadata(transcriptId: String) throws {
    try dbManager.write { db in
        try db.execute(sql: "DELETE FROM transcript_metadata WHERE transcript_id = ?", arguments: [transcriptId])
    }
}

/// Get all transcript metadata for a project
/// - Parameter projectId: Project UUID
/// - Returns: Dictionary mapping transcript ID to metadata
public func getAllTranscriptMetadata(projectId: String) throws -> [String: TranscriptMetadata] {
    return try dbManager.read { db in
        let rows = try Row.fetchAll(db, sql: """
            SELECT m.transcript_id, m.title, m.description, m.topics
            FROM transcript_metadata m
            JOIN transcripts t ON t.id = m.transcript_id
            WHERE t.project_id = ?
        """, arguments: [projectId])

        var result: [String: TranscriptMetadata] = [:]
        for row in rows {
            let transcriptId = row["transcript_id"] as! String
            let topicsJSON = row["topics"] as? String
            let topics: [String] = (try? JSONDecoder().decode([String].self, from: topicsJSON?.data(using: .utf8) ?? Data())) ?? []

            result[transcriptId] = TranscriptMetadata(
                title: row["title"] as? String ?? "Untitled Session",
                description: row["description"] as? String ?? "",
                topics: topics
            )
        }
        return result
    }
}
```

#### 2.2 Update `loadMetadataForSessions()` in TranscriptInventoryView

**Location**: TranscriptInventoryView.swift (lines 200-250, approximate)

**Before** (uses in-memory cache):
```swift
private func loadMetadataForSessions(_ sessions: [TranscriptSession]) async {
    // ... existing code that uses SidecarMetadataStore
}
```

**After** (uses SQL backend):
```swift
/// Load metadata for transcript sessions from SQL database
/// Generates metadata via LLM if not cached
private func loadMetadataForSessions(_ sessions: [TranscriptSession]) async {
    guard let orchestrator = monitor.orchestrator else {
        log.warning("Cannot load metadata: orchestrator not available")
        return
    }

    log.debug("Loading metadata for \(sessions.count) sessions")

    for session in sessions {
        let transcriptId = session.identifier

        // Skip if already loading
        guard !loadingMetadata.contains(transcriptId) else {
            log.debug("Already loading metadata for \(transcriptId), skipping")
            continue
        }

        // Check if metadata already loaded in UI state
        if metadata[transcriptId] != nil {
            log.debug("Metadata already loaded for \(transcriptId), skipping")
            continue
        }

        // Try to load from SQL cache first
        do {
            if let cachedMetadata = try orchestrator.getTranscriptMetadata(transcriptId: transcriptId) {
                log.debug("✅ Cache HIT for \(transcriptId): \(cachedMetadata.title)")
                await MainActor.run {
                    metadata[transcriptId] = cachedMetadata
                }
                continue  // Skip LLM generation
            } else {
                log.debug("❌ Cache MISS for \(transcriptId), will generate")
            }
        } catch {
            log.error("Error reading metadata from database: \(error.localizedDescription)")
        }

        // Cache miss - generate metadata
        await MainActor.run {
            loadingMetadata.insert(transcriptId)
        }

        let task = Task {
            defer {
                Task { @MainActor in
                    loadingMetadata.remove(transcriptId)
                }
            }

            // Generate metadata (LLM or heuristic fallback)
            log.debug("Generating metadata for \(transcriptId)")
            let generatedMetadata = await TranscriptMetadataOrchestrator.shared.metadata(
                for: transcriptId,
                fileURL: session.fileURL
            )

            // Save to SQL database (not in-memory)
            do {
                try orchestrator.saveTranscriptMetadata(
                    transcriptId: transcriptId,
                    metadata: generatedMetadata
                )
                log.debug("✅ Saved metadata to SQL for \(transcriptId): \(generatedMetadata.title)")
            } catch {
                log.error("Failed to save metadata to database: \(error.localizedDescription)")
            }

            // Update UI state
            await MainActor.run {
                metadata[transcriptId] = generatedMetadata
            }
        }

        await MainActor.run {
            metadataTasks[transcriptId] = task
        }
    }

    log.debug("Finished loading metadata for \(sessions.count) sessions")
}
```

#### 2.3 Update TranscriptMetadataOrchestrator (Optional Enhancement)

**Location**: `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`

**Current Behavior**: Uses SidecarMetadataStore (in-memory)

**Future Behavior**: Could be refactored to use SQL directly, but for Phase 2 we'll keep the current implementation and just ensure it calls `orchestrator.saveTranscriptMetadata()` after generation.

**Decision**: Keep TranscriptMetadataOrchestrator as-is for now. The saving to SQL happens in `loadMetadataForSessions()` above. We can refactor later if needed.

#### 2.4 Testing Phase 2

**Manual Tests**:
1. Launch app, open Inventory window
2. Wait for metadata generation (LLM or heuristic)
3. Query database: `SELECT * FROM transcript_metadata`
4. **Expected**: Metadata appears in table
5. Restart app
6. Open Inventory window again
7. **Expected**: Metadata loads instantly from SQL (no LLM calls)

**Database Verification**:
```sql
-- Check metadata exists
SELECT
    t.file_path,
    m.title,
    m.description,
    m.topics
FROM transcripts t
LEFT JOIN transcript_metadata m ON m.transcript_id = t.id
WHERE t.project_id = '<current-project-id>'
LIMIT 10;
```

**Acceptance Criteria**:
- [ ] Metadata written to `transcript_metadata` table
- [ ] Metadata survives app restart
- [ ] No LLM calls on second launch (cache hit)
- [ ] UI shows titles/descriptions correctly

**Estimated Time**: 4 hours

---

### Phase 3: Remove In-Memory Cache (Day 2, Morning)

**Goal**: Deprecate `SidecarMetadataStore` and clean up references

**Files to Modify**:
- `Contextify/Contextify/SidecarMetadataStore.swift`
- `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`

**Changes**:

#### 3.1 Mark SidecarMetadataStore as Deprecated

**Location**: `Contextify/Contextify/SidecarMetadataStore.swift`

**Update header comment**:
```swift
//
//  SidecarMetadataStore.swift
//  Contextify
//
//  DEPRECATED: This in-memory cache has been replaced with SQL backend (transcript_metadata table)
//  TODO: Remove this file after verifying SQL migration is stable
//  See: build/notes/implementation-plans/transcript-inventory-sql-migration.md
//

@available(*, deprecated, message: "Use TranscriptOrchestrator.getTranscriptMetadata() instead")
actor SidecarMetadataStore {
    // ... existing code
}
```

#### 3.2 Update TranscriptMetadataOrchestrator to Remove Sidecar Dependency

**Location**: `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`

**Current**: Uses `SidecarMetadataStore.shared`

**Update**: Remove sidecar references, rely on caller to persist to SQL

**Changes**:
1. Remove `private let store = SidecarMetadataStore.shared` property
2. Remove `await store.load()` calls
3. Remove `await store.save()` calls
4. Add comment: "// Caller is responsible for persisting to SQL via orchestrator.saveTranscriptMetadata()"

**Note**: The actual persistence happens in `TranscriptInventoryView.loadMetadataForSessions()`, so TranscriptMetadataOrchestrator just needs to generate and return metadata.

#### 3.3 Testing Phase 3

**Verification**:
1. Search codebase for `SidecarMetadataStore` usage
2. Confirm only deprecated file remains
3. Build succeeds with deprecation warnings
4. App runs without errors

**Acceptance Criteria**:
- [ ] No active usage of SidecarMetadataStore (except deprecated file)
- [ ] App functions correctly without in-memory cache
- [ ] All tests pass

**Estimated Time**: 2 hours

---

### Phase 4: Integration Testing & Polish (Day 2, Afternoon)

**Goal**: Comprehensive testing and edge case handling

**Test Scenarios**:

#### 4.1 Happy Path Tests

**Test 1: Fresh Discovery**
```
1. Delete database: rm ~/Library/Application\ Support/Contextify/transcripts.db*
2. Launch app
3. Open Inventory window
4. Wait for discovery and metadata generation
5. Verify:
   - Transcripts in database
   - Metadata in database
   - UI shows titles/descriptions
6. Restart app
7. Verify:
   - Metadata loads instantly (no LLM calls)
   - Same titles/descriptions appear
```

**Test 2: New Transcript Added**
```
1. App running, Inventory window open
2. Create new JSONL file in ~/.claude/projects/<project>/
3. Wait for discovery (10 seconds)
4. Verify:
   - New transcript appears in UI
   - New transcript in database
   - Metadata generated and saved
```

**Test 3: Project Switching**
```
1. Open Inventory for Project A
2. Switch to Project B (via Projects window or HUD)
3. Open Inventory window
4. Verify:
   - Shows Project B's transcripts
   - Metadata loads from database
   - No cross-contamination with Project A data
```

#### 4.2 Edge Case Tests

**Test 4: LLM Failure (Circuit Breaker)**
```
1. Simulate LLM failures (disconnect network or mock failure)
2. Open Inventory window
3. Verify:
   - Heuristic fallback generates titles
   - Heuristic metadata saved to database
   - UI shows "Developer Chat" or first-sentence titles
4. Reconnect network/fix LLM
5. Flush cache (existing UI button)
6. Verify:
   - LLM regenerates better titles
   - Database updated with new metadata
```

**Test 5: Concurrent Discovery**
```
1. Open Inventory window
2. Rapidly switch between projects
3. Verify:
   - No race conditions
   - Each project's metadata persists correctly
   - No database corruption
```

**Test 6: Empty Project**
```
1. Create new project with no transcript files
2. Open Inventory window
3. Verify:
   - Shows empty state
   - No errors
   - No database writes (except project record)
```

**Test 7: Database Migration (v4 → v4)**
```
1. Verify schema version: SELECT user_version FROM pragma_user_version
2. Expected: 4 (transcript_metadata table already exists)
3. Launch app
4. Verify:
   - No migration runs (already at v4)
   - transcript_metadata table accessible
```

#### 4.3 Performance Tests

**Test 8: Large Project (100+ Transcripts)**
```
1. Create project with 100+ transcript files
2. Open Inventory window
3. Measure:
   - Discovery time (target: <2 seconds)
   - Metadata load time from SQL (target: <500ms for cache hits)
   - UI responsiveness (no freezing)
4. Verify:
   - All transcripts appear
   - Scrolling is smooth
   - Search works correctly
```

**Test 9: Startup Time Comparison**
```
1. Before SQL migration (in-memory):
   - Launch app, open Inventory
   - Measure time to show all metadata (with LLM regeneration)
   - Expected: 1-3 seconds per transcript × 10 transcripts = 10-30 seconds

2. After SQL migration:
   - Launch app, open Inventory
   - Measure time to show all metadata (from cache)
   - Expected: <500ms for 10 transcripts

3. Speedup: 20-60× faster
```

#### 4.4 Polish & UX Improvements

**Enhancement 1: Loading States**

Update TranscriptInventoryView to show better loading indicators:
```swift
// For each session row
if loadingMetadata.contains(session.identifier) {
    ProgressView()
        .scaleEffect(0.5)
        .help("Generating metadata...")
} else if let meta = metadata[session.identifier] {
    Text(meta.title)
} else {
    Text("Untitled Session")
        .foregroundStyle(.tertiary)
}
```

**Enhancement 2: Cache Statistics**

Add debug UI (developer mode only):
```swift
if devMode.isEnabled {
    VStack(alignment: .leading, spacing: 4) {
        Text("Cache Statistics")
            .font(.caption.bold())
        Text("Total sessions: \(monitor.allSessions.count)")
        Text("Cached metadata: \(metadata.count)")
        Text("Loading: \(loadingMetadata.count)")
    }
    .padding()
    .background(.thinMaterial)
}
```

**Enhancement 3: Manual Refresh Button**

Ensure existing refresh button works correctly:
```swift
Button {
    refreshSessions()  // Triggers discovery + metadata load
} label: {
    Label("Refresh", systemImage: "arrow.clockwise")
        .labelStyle(.iconOnly)
}
.buttonStyle(.borderless)
```

**Estimated Time**: 4 hours

---

### Phase 5: Documentation & Code Review (Day 3)

**Goal**: Update documentation and prepare for review

**Tasks**:

#### 5.1 Update Code Comments

**Files**:
- TranscriptInventoryView.swift
- TranscriptOrchestrator.swift
- SidecarMetadataStore.swift (deprecation notice)

**Add/Update**:
- Method documentation (SwiftDoc format)
- Inline comments explaining SQL operations
- TODO comments for future cleanup

#### 5.2 Update Technical Documentation

**Files**:
- `build/notes/technical-reference/window-architectures.md`
  - Update "Known Issues" section (remove metadata persistence gap)
  - Update "Performance Characteristics" table with new metrics

- `build/notes/technical-reference/transcript-inventory-db-integration-gap.md`
  - Add "✅ RESOLVED" header
  - Document solution implemented
  - Add link to this implementation plan

- `build/notes/technical-reference/data-flow-complete.md`
  - Update "The Gap" section to show it's fixed
  - Update comparison table

#### 5.3 Create Migration Guide

**File**: `build/notes/migration-guides/transcript-inventory-sql-migration.md`

**Content**:
- Overview of changes
- Database schema (transcript_metadata table)
- API changes (new orchestrator methods)
- Migration steps for developers
- Before/after performance comparison

#### 5.4 Update CHANGELOG

**File**: `CHANGELOG.md` (if exists) or create entry for PR description

```markdown
## [Unreleased]

### Fixed
- **Transcript Inventory**: Metadata now persists to SQL database instead of in-memory cache
  - Metadata survives app restarts (no LLM regeneration)
  - 20-60× faster startup for Inventory window (SQL reads vs LLM calls)
  - Consistent data model with main timeline
  - Fixes issue where circuit breaker state was lost on restart

### Changed
- **TranscriptInventoryView**: Now persists discovered transcripts to database
- **TranscriptOrchestrator**: Added metadata CRUD methods
- **SidecarMetadataStore**: Deprecated in favor of SQL backend

### Performance
- Inventory window startup: 10-30s → <500ms (cache hits)
- LLM quota usage: Reduced by 80-90% (cache reuse across restarts)
```

**Estimated Time**: 3 hours

---

## Risk Assessment

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **Database write failures** | Low | High | Wrap all SQL calls in try-catch, log errors, graceful degradation to in-memory cache if needed |
| **Schema mismatch (v4 not applied)** | Low | High | Add schema version check at startup, fail fast with clear error message |
| **Race conditions (concurrent access)** | Medium | Medium | Use existing GRDB connection pool (thread-safe), test concurrent scenarios |
| **Performance regression** | Low | Medium | Benchmark before/after, SQL reads are faster than LLM calls |
| **Metadata format incompatibility** | Low | Low | TranscriptMetadata model unchanged, JSON encoding is standard |
| **Circuit breaker state loss** | Medium | Low | Document as known limitation for Phase 2, address in Phase 3 if needed |

### Migration Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **Existing users have in-memory metadata** | N/A | N/A | No production users yet (early development) |
| **Database corruption during migration** | Very Low | High | WAL mode + backups, test on fresh DB first |
| **Rollback needed** | Low | Medium | Keep SidecarMetadataStore (deprecated) for easy rollback |

### UX Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| **Slower initial metadata generation** | Low | Low | Same as current behavior (LLM generation required on first load) |
| **Missing loading indicators** | Medium | Low | Add ProgressView indicators (Phase 4 polish) |
| **Confusing error messages** | Low | Medium | Add clear logging, graceful error handling |

---

## Rollback Plan

If critical issues arise during/after deployment:

### Quick Rollback (< 5 minutes)

**Step 1**: Revert code changes
```bash
git revert <merge-commit-sha>
```

**Step 2**: Re-enable SidecarMetadataStore
```swift
// In TranscriptInventoryView.swift
// Comment out SQL persistence, uncomment old in-memory code
```

**Step 3**: Rebuild and deploy
```bash
bash scripts/xc.sh build
```

### Database Cleanup (if needed)

```sql
-- Delete metadata added during SQL migration
DELETE FROM transcript_metadata
WHERE created_at > <migration-start-timestamp>;

-- Or nuke entire table (metadata will regenerate)
DELETE FROM transcript_metadata;
```

### Verification After Rollback

- [ ] App launches without errors
- [ ] Inventory window shows sessions
- [ ] Metadata regenerates on each launch (old behavior)
- [ ] No SQL errors in logs

---

## Success Criteria

### Functional Requirements

- [x] Phase 1 Complete
  - [ ] `persistDiscoveredSessions()` method added
  - [ ] `.onChange` handler updated to persist before loading
  - [ ] Transcripts written to database on discovery
  - [ ] Idempotency verified (no duplicates)

- [x] Phase 2 Complete
  - [ ] `getTranscriptMetadata()` method added to orchestrator
  - [ ] `saveTranscriptMetadata()` method added to orchestrator
  - [ ] `loadMetadataForSessions()` updated to use SQL
  - [ ] Metadata survives app restart

- [x] Phase 3 Complete
  - [ ] SidecarMetadataStore marked as deprecated
  - [ ] No active usage of in-memory cache
  - [ ] App functions without SidecarMetadataStore

- [x] Phase 4 Complete
  - [ ] All happy path tests pass
  - [ ] All edge case tests pass
  - [ ] Performance benchmarks meet targets
  - [ ] UX polish applied

- [x] Phase 5 Complete
  - [ ] Code comments updated
  - [ ] Technical documentation updated
  - [ ] Migration guide created
  - [ ] PR ready for review

### Performance Requirements

- [ ] Inventory window startup (cached): <500ms for 10 transcripts
- [ ] Inventory window startup (uncached): Same as current (LLM-dependent)
- [ ] Database write time: <5ms per metadata entry
- [ ] Database read time: <1ms per metadata entry
- [ ] No UI freezing during metadata load

### Quality Requirements

- [ ] No new compiler warnings
- [ ] No new runtime errors
- [ ] All existing tests pass
- [ ] New tests cover SQL persistence
- [ ] Code review approved
- [ ] Documentation updated

---

## Timeline

### Estimated Schedule

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| **Phase 1**: Discovery Persistence | 2 hours | None |
| **Phase 2**: SQL Migration | 4 hours | Phase 1 |
| **Phase 3**: Cleanup | 2 hours | Phase 2 |
| **Phase 4**: Testing & Polish | 4 hours | Phase 3 |
| **Phase 5**: Documentation | 3 hours | Phase 4 |
| **Total** | **15 hours** (~2 days) | - |

### Detailed Schedule

**Day 1**:
- Morning (4 hours):
  - 9:00-11:00: Phase 1 (Discovery Persistence)
  - 11:00-12:00: Testing Phase 1

- Afternoon (4 hours):
  - 13:00-17:00: Phase 2 (SQL Migration)

**Day 2**:
- Morning (4 hours):
  - 9:00-11:00: Phase 3 (Cleanup)
  - 11:00-13:00: Testing Phase 3

- Afternoon (3 hours):
  - 14:00-17:00: Phase 4 (Integration Testing)

**Day 3**:
- Morning (3 hours):
  - 9:00-12:00: Phase 5 (Documentation)

- Afternoon (1 hour):
  - 13:00-14:00: Code Review & PR submission

---

## Dependencies

### External Dependencies

- None (all schema and infrastructure already exist)

### Internal Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| `transcript_metadata` table (v4 schema) | ✅ Exists | Created in DatabaseSchema.swift migration v4 |
| `TranscriptOrchestrator` | ✅ Ready | Core API stable |
| `ConversationMonitor.allSessions` | ✅ Working | Populated by discovery loop |
| `TranscriptMetadataOrchestrator` | ✅ Working | Generates metadata |
| GRDB connection pool | ✅ Working | Thread-safe, WAL mode enabled |

### Prerequisite Checks

Before starting implementation:

```bash
# 1. Verify schema version
sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db "SELECT user_version FROM pragma_user_version"
# Expected: 4

# 2. Verify transcript_metadata table exists
sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db ".schema transcript_metadata"
# Expected: CREATE TABLE transcript_metadata (...)

# 3. Verify app builds
bash scripts/xc.sh build
# Expected: Build succeeds

# 4. Verify tests pass
bash scripts/xc.sh test
# Expected: All tests pass
```

---

## Code Review Checklist

Before submitting PR, verify:

### Code Quality
- [ ] No compiler warnings
- [ ] No force-unwraps (unless documented as safe)
- [ ] Error handling for all SQL operations
- [ ] Logging at appropriate levels (debug/info/error)
- [ ] SwiftDoc comments for public methods

### Testing
- [ ] Unit tests for new orchestrator methods
- [ ] Integration tests for SQL persistence
- [ ] Manual testing on fresh database
- [ ] Manual testing on existing database
- [ ] Performance benchmarks collected

### Documentation
- [ ] Code comments explain "why", not just "what"
- [ ] Technical docs updated
- [ ] Migration guide created
- [ ] CHANGELOG updated

### Database
- [ ] No schema changes (v4 already exists)
- [ ] SQL queries use parameterized statements (no injection risk)
- [ ] Transactions used appropriately
- [ ] Indexes present on queried columns

### UX
- [ ] Loading indicators present
- [ ] Error messages are user-friendly
- [ ] No UI freezing during operations
- [ ] Existing UI behavior preserved

---

## Post-Implementation Tasks

After PR is merged:

### Monitoring (First Week)

- [ ] Monitor logs for SQL errors
- [ ] Track LLM quota usage (should decrease significantly)
- [ ] Monitor app startup time
- [ ] Check for crash reports

### Follow-Up Work (Future Iterations)

1. **Remove SidecarMetadataStore** (after 2 weeks of stable operation)
2. **Add circuit breaker state persistence** (if still needed)
3. **Optimize metadata query performance** (batch queries if >100 transcripts)
4. **Add metadata versioning** (for future schema changes)
5. **Implement metadata refresh** (regenerate if content changes)

### Metrics to Track

| Metric | Before | After (Expected) | Actual |
|--------|--------|------------------|--------|
| Inventory startup (10 transcripts) | 10-30s | <500ms | TBD |
| LLM calls per app launch | 10 (all sessions) | 0-1 (new sessions only) | TBD |
| Metadata persistence rate | 0% (lost on restart) | 100% | TBD |
| Database size growth | N/A | ~5KB per session | TBD |
| SQL query time (avg) | N/A | <1ms | TBD |

---

## Appendix A: SQL Queries Reference

### Query 1: Verify Transcripts Persisted
```sql
SELECT
    t.id,
    t.file_path,
    t.provider,
    t.created_at,
    datetime(t.created_at, 'unixepoch') as created_human
FROM transcripts t
WHERE t.project_id = '<current-project-id>'
ORDER BY t.created_at DESC
LIMIT 10;
```

### Query 2: Verify Metadata Persisted
```sql
SELECT
    m.transcript_id,
    m.title,
    m.description,
    m.topics,
    datetime(m.created_at, 'unixepoch') as created_human,
    datetime(m.updated_at, 'unixepoch') as updated_human
FROM transcript_metadata m
WHERE m.transcript_id IN (
    SELECT id FROM transcripts WHERE project_id = '<current-project-id>'
)
LIMIT 10;
```

### Query 3: Check for Missing Metadata
```sql
-- Transcripts without metadata (cache misses)
SELECT
    t.id,
    t.file_path,
    t.provider
FROM transcripts t
LEFT JOIN transcript_metadata m ON m.transcript_id = t.id
WHERE t.project_id = '<current-project-id>'
  AND m.transcript_id IS NULL;
```

### Query 4: Metadata Coverage Statistics
```sql
-- Percentage of transcripts with cached metadata
SELECT
    COUNT(DISTINCT t.id) as total_transcripts,
    COUNT(DISTINCT m.transcript_id) as cached_transcripts,
    ROUND(100.0 * COUNT(DISTINCT m.transcript_id) / COUNT(DISTINCT t.id), 2) as cache_coverage_percent
FROM transcripts t
LEFT JOIN transcript_metadata m ON m.transcript_id = t.id
WHERE t.project_id = '<current-project-id>';
```

---

## Appendix B: Example Test Cases

### Test Case 1: Fresh Database (Happy Path)

```swift
func testFreshDatabaseMetadataPersistence() async throws {
    // Setup: Clean database
    try dbManager.write { db in
        try db.execute(sql: "DELETE FROM transcript_metadata")
        try db.execute(sql: "DELETE FROM transcripts")
        try db.execute(sql: "DELETE FROM projects")
    }

    // Create test project
    let projectId = try orchestrator.getOrCreateProject(
        name: "Test Project",
        rootPath: "/tmp/test"
    )

    // Create test transcript
    let transcriptId = UUID().uuidString
    try orchestrator.discoverTranscript(
        projectId: projectId,
        fileURL: URL(fileURLWithPath: "/tmp/test/conversation.jsonl"),
        provider: "claude.code",
        providerSessionId: "test-session",
        startWatching: false
    )

    // Save metadata
    let metadata = TranscriptMetadata(
        title: "Test Session",
        description: "Test description",
        topics: ["testing", "swift"]
    )
    try orchestrator.saveTranscriptMetadata(
        transcriptId: transcriptId,
        metadata: metadata
    )

    // Verify persistence
    let loaded = try orchestrator.getTranscriptMetadata(transcriptId: transcriptId)
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.title, "Test Session")
    XCTAssertEqual(loaded?.description, "Test description")
    XCTAssertEqual(loaded?.topics, ["testing", "swift"])
}
```

### Test Case 2: Metadata Update (Idempotency)

```swift
func testMetadataUpdate() async throws {
    // Create transcript and initial metadata
    let transcriptId = try setupTestTranscript()
    try orchestrator.saveTranscriptMetadata(
        transcriptId: transcriptId,
        metadata: TranscriptMetadata(
            title: "Initial Title",
            description: "Initial description",
            topics: ["initial"]
        )
    )

    // Update metadata
    try orchestrator.saveTranscriptMetadata(
        transcriptId: transcriptId,
        metadata: TranscriptMetadata(
            title: "Updated Title",
            description: "Updated description",
            topics: ["updated", "new"]
        )
    )

    // Verify update (not duplicate)
    let loaded = try orchestrator.getTranscriptMetadata(transcriptId: transcriptId)
    XCTAssertEqual(loaded?.title, "Updated Title")
    XCTAssertEqual(loaded?.topics, ["updated", "new"])

    // Verify only one row exists
    let count = try dbManager.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_metadata WHERE transcript_id = ?", arguments: [transcriptId])
    }
    XCTAssertEqual(count, 1)
}
```

### Test Case 3: Bulk Load Performance

```swift
func testBulkMetadataLoad() async throws {
    // Setup: Create 50 transcripts with metadata
    let projectId = try setupTestProject()
    var transcriptIds: [String] = []

    for i in 0..<50 {
        let transcriptId = UUID().uuidString
        try orchestrator.discoverTranscript(
            projectId: projectId,
            fileURL: URL(fileURLWithPath: "/tmp/test/conversation-\(i).jsonl"),
            provider: "claude.code",
            providerSessionId: "session-\(i)",
            startWatching: false
        )
        try orchestrator.saveTranscriptMetadata(
            transcriptId: transcriptId,
            metadata: TranscriptMetadata(
                title: "Session \(i)",
                description: "Test session \(i)",
                topics: ["test"]
            )
        )
        transcriptIds.append(transcriptId)
    }

    // Benchmark: Load all metadata
    let start = Date()
    let allMetadata = try orchestrator.getAllTranscriptMetadata(projectId: projectId)
    let duration = Date().timeIntervalSince(start)

    // Verify
    XCTAssertEqual(allMetadata.count, 50)
    XCTAssertLessThan(duration, 0.5, "Bulk load should take <500ms for 50 transcripts")
}
```

---

## Appendix C: Debugging Commands

### Check Database Schema
```bash
sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db ".schema transcript_metadata"
```

### View All Metadata
```bash
sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db "SELECT * FROM transcript_metadata LIMIT 10"
```

### Count Metadata Entries
```bash
sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db "SELECT COUNT(*) FROM transcript_metadata"
```

### Delete All Metadata (for testing)
```bash
sqlite3 ~/Library/Application\ Support/Contextify/transcripts.db "DELETE FROM transcript_metadata"
```

### Watch SQL Operations (in separate terminal)
```bash
# Enable query logging in GRDB (add to DatabaseManager.swift for debugging)
let config = Configuration()
config.prepareDatabase { db in
    db.trace { print("SQL: \($0)") }
}
```

---

**END OF IMPLEMENTATION PLAN**
