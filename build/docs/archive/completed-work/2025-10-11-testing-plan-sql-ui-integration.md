# Testing Plan: SQL UI Integration - Establish Feedback Loop

**Date:** 2025-10-11
**Status:** In Progress
**Priority:** P0 - Critical for development velocity

## Problem Statement

Current state:
- Timeline shows entries with icons but **missing text content**
- Transcript inventory shows **zero transcripts** despite discovery fix
- **No test coverage** for SQL integration changes
- **No feedback loop** to verify changes work before committing
- Flying blind - can't tell if bugs are in DB, parsing, mapping, or UI

## Root Cause Analysis

### Missing Text Content
Possible causes:
1. TranscriptEntry.content field is empty in database
2. Cache presentForm/pastForm are empty
3. Fallback logic `String(entry.content.prefix(100))` hitting empty strings
4. Parsing/hoovering failing silently during ingestion

### Zero Transcripts in Inventory
Possible causes:
1. Discovery task not executing
2. Discovery succeeding but `allSessions` not updating
3. UI not observing `allSessions` from ConversationMonitor
4. `mapTranscriptsToSessions()` returning empty array

## Testing Strategy

### Phase 1: Immediate Diagnostics (30 min)
**Goal:** Understand actual state before writing tests

1. **Add diagnostic logging** to key paths:
   - Discovery: log file count, paths discovered
   - Hoovering: log entries parsed, content length
   - Mapping: log entries mapped, summary/detail lengths
   - UI binding: log allSessions count, entries count

2. **Direct database inspection**:
   - Query transcript_entries table directly
   - Check content field length
   - Check timeline_cache table state
   - Verify foreign keys

3. **Console.app monitoring**:
   - Filter by `dev.contextify` subsystem
   - Look for errors, warnings
   - Track execution flow

**Exit criteria:** Know exactly where data is being lost

### Phase 2: Test Infrastructure Setup (1 hour)
**Goal:** Enable fast red-green-refactor cycle

#### 2.1 In-Memory Database Factory
Create `TestHelpers/DatabaseFactory.swift`:
```swift
enum TestDatabaseFactory {
    static func makeInMemoryPool() throws -> DatabasePool {
        let pool = try DatabasePool(path: ":memory:")
        var migrator = DatabaseSchema.createMigrator()
        try migrator.migrate(pool)
        return pool
    }

    static func seedTranscripts(pool: DatabasePool, count: Int) throws {
        // Helper to populate test data
    }
}
```

#### 2.2 Testable Seams in ConversationMonitor
Make dependencies injectable:
```swift
@MainActor
final class ConversationMonitor {
    // Inject for testing
    init(
        orchestrator: TranscriptOrchestrator? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.orchestrator = orchestrator
        self.notificationCenter = notificationCenter
    }

    // Expose for testing
    internal func _test_getEntries() -> [TimelineEntry] { entries }
    internal func _test_getAllSessions() -> [TranscriptSession] { allSessions }
}
```

#### 2.3 Fake Cache Generator
```swift
actor FakeCacheMissGenerator: TimelineCacheGenerating {
    var generatedCaches: [CacheMiss: TimelineCache] = [:]

    func queueMisses(_ misses: [CacheMiss]) {
        // Return predetermined caches instantly
    }
}
```

**Exit criteria:** Can construct ConversationMonitor with test doubles

### Phase 3: Unit Tests - Database Layer (1 hour)
**Goal:** Prove DB operations work in isolation

#### 3.1 Hoover Engine Tests
`ContextifyTests/HooverEngineTests.swift`:
- ✅ Parse Claude Code JSONL format
- ✅ Parse Codex CLI JSONL format
- ✅ Extract content correctly
- ✅ Compute content SHA256
- ✅ Compute window SHA256
- ✅ Insert entries with content

#### 3.2 Repository Tests
`ContextifyTests/RepositoryTests.swift`:
- ✅ EntryRepository.recentFeed() returns entries with cache
- ✅ CacheRepository.upsert() preserves user_edited
- ✅ TranscriptRepository.byProject() returns all transcripts

#### 3.3 Entry Mapping Tests
`ContextifyTests/EntryMappingTests.swift`:
- ✅ toTimelineEntry() populates summary from cache
- ✅ toTimelineEntry() uses fallback when cache missing
- ✅ toTimelineEntry() preserves content in detail field
- ✅ toTimelineEntry() populates cache keys

**Exit criteria:** All DB operations proven with < 1s tests

### Phase 4: Unit Tests - Discovery & Mapping (1 hour)
**Goal:** Prove file discovery and session mapping work

#### 4.1 Discovery Tests
`ContextifyTests/TranscriptDiscoveryTests.swift`:
```swift
func testDiscoveryScansSubdirectories() throws {
    // Setup: Create temp dir with subdirs containing .jsonl
    // Run: discoverNewTranscripts()
    // Assert: All files found and hoovered
}

func testDiscoverySkipsExistingTranscripts() throws {
    // Setup: Seed DB with existing transcript
    // Run: discoverNewTranscripts()
    // Assert: Existing not re-hoovered, new ones added
}
```

#### 4.2 Session Mapping Tests
`ContextifyTests/SessionMappingTests.swift`:
```swift
func testMapTranscriptsToSessionsReturnsAllSessions() {
    // Given: Transcripts with various providers
    // When: mapTranscriptsToSessions()
    // Then: All mapped with correct provider enum
}

func testMapTranscriptsToSessionsSortsByActivity() {
    // Given: Transcripts with different updated_at
    // When: mapTranscriptsToSessions()
    // Then: Sorted newest first
}
```

**Exit criteria:** Discovery and mapping logic proven

### Phase 5: Integration Tests - Full Flow (1.5 hours)
**Goal:** Prove end-to-end data flow

#### 5.1 Feed Loading Tests
`ContextifyTests/FeedLoadingTests.swift`:
```swift
func testLoadFeedPopulatesEntriesWithContent() async {
    // Given: In-memory DB with transcripts + entries
    // When: ConversationMonitor.startMonitoring()
    // Then: visibleEntries populated with non-empty summaries
}

func testLoadFeedPopulatesCacheKeys() async {
    // Given: Entries in DB
    // When: loadFeedFromSQL()
    // Then: All entries have contentSha256, windowSha256
}

func testLoadFeedBuildsIndex() async {
    // Given: Feed loaded
    // When: Check indexByCacheKey
    // Then: All entries indexed by composite key
}
```

#### 5.2 Cache Update Tests
`ContextifyTests/CacheUpdateTests.swift`:
```swift
func testCacheUpdateRefreshesInPlace() async {
    // Given: Entries with generating state
    // When: Post TimelineCacheUpdated notification
    // Then: Summaries update, no reload, generating cleared
}

func testCacheUpdateSkipsUserEdited() async {
    // Given: Cache with user_edited=1
    // When: Background generation completes
    // Then: User edit preserved
}
```

#### 5.3 Session List Tests
`ContextifyTests/SessionListTests.swift`:
```swift
func testAllSessionsPopulatesAfterDiscovery() async {
    // Given: Transcript files on disk
    // When: Discovery completes
    // Then: allSessions contains all sessions
}

func testSessionSwitchLoadsCorrectEntries() async {
    // Given: Multiple transcripts
    // When: switchToSessionFromUser()
    // Then: Only that session's entries loaded
}
```

**Exit criteria:** Full flow from disk → DB → UI proven

### Phase 6: Audit Existing Tests (30 min)
**Goal:** Ensure existing tests still relevant

#### Review Test Files
- `ContextifyTests/GitDetectionTests.swift` - ✅ Keep (still relevant)
- `ContextifyTests/ContextifyTests.swift` - ⚠️ Update for SQL
- `ContextifyTests/TestHelpers.swift` - ✅ Extend with DB helpers

#### Actions
1. Run existing tests: `make test`
2. Document failures
3. Update or remove obsolete tests
4. Ensure all passing

**Exit criteria:** Test suite green, no obsolete tests

### Phase 7: Fix Bugs with Tests (2 hours)
**Goal:** Use TDD to fix actual issues

#### Bug 1: Missing Text Content
1. Write failing test proving content is empty
2. Add logging to find where it's lost
3. Fix the bug
4. Verify test passes

#### Bug 2: Zero Transcripts
1. Write failing test proving allSessions is empty
2. Add logging to discovery flow
3. Fix the bug
4. Verify test passes

**Exit criteria:** Bugs fixed with test coverage

## Implementation Schedule

### Day 1 (Today)
- [x] Write this plan (30 min)
- [ ] Phase 1: Diagnostics (30 min)
- [ ] Phase 2: Test Infrastructure (1 hour)
- [ ] Phase 3: Database Tests (1 hour)

### Day 2
- [ ] Phase 4: Discovery Tests (1 hour)
- [ ] Phase 5: Integration Tests (1.5 hours)
- [ ] Phase 6: Audit Existing (30 min)
- [ ] Phase 7: Fix Bugs (2 hours)

## Success Criteria

- ✅ Can run `make test` and get instant feedback
- ✅ Tests prove DB operations work
- ✅ Tests prove discovery works
- ✅ Tests prove UI mapping works
- ✅ Timeline shows entries with text content
- ✅ Transcript inventory shows sessions
- ✅ All tests passing
- ✅ No more blind changes

## Test Commands

```bash
# Run all tests
make test

# Run specific test
xcodebuild test -scheme Contextify -destination 'platform=macOS' -only-testing:ContextifyTests/HooverEngineTests

# Run with verbose output
bash scripts/xc.sh test 2>&1 | tee build/logs/test-$(date +%s).log

# Check database directly
sqlite3 ~/Library/Application\ Support/Contextify/contextify.db "SELECT COUNT(*) FROM transcript_entries"
```

## Metrics

Track these to measure progress:
- Test execution time (target: < 5s for unit tests)
- Test coverage (target: > 80% for new code)
- Time to feedback (target: < 10s from change to result)
- Bug reproduction rate (target: 100% reproducible via test)

## Notes

- Use `@testable import` to access internal members
- Prefer in-memory DB over temp files (10x faster)
- Mock NotificationCenter to avoid global state
- Use XCTest expectations for async tests
- Add accessibility IDs for UI tests

## Related Documents

- `build/notes/archive/technical-briefing-local-history-claude-code-codex.md` - Parsing reference
- `build/notes/archive/sql-implementation-plan-05.md` - Database schema
- `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` - Schema code
