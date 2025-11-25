---
todo_id: P1-CONVO-SEARCH
title: Conversation Search Implementation Briefing
type: implementation
date: 2025-11-25
status: ready
description: Code-level implementation details for Phase 1 FTS search (migration, SearchService, UI). Companion to P1-CONVO-SEARCH-spec.md.
---
# Conversation Search Implementation - Technical Briefing v2

**Changes from v1:** Addressed blocking issues (migration versioning, table naming, FTS sync, tokenizer) and significant concerns (query escaping, context alignment, pagination caps, responsive layout).

## Executive Summary

Conversation search has a comprehensive spec at `build/notes/todo-support/P1-CONVO-SEARCH-spec.md`. This briefing focuses on **Phase 1 implementation specifics**: code changes, UX decisions, and resolved questions.

**Phase 1 Scope:**
- FTS5 full-text search on user/assistant messages
- Quick Search (HUD, Enter) - project-scoped
- Deep Search (Search Center, Cmd+Enter) - cross-project
- Context excerpts with copy actions

---

## 1. Database Schema (FTS5)

**Migration v28** - Uses existing `createMigrator()` pattern, targets `transcript_entries` table.

```swift
// DatabaseSchema.swift - Add to createMigrator()

migrator.registerMigration("v28_fts_search") { db in
    // Create FTS5 virtual table with underscore as separator for code identifiers
    try db.execute(sql: """
        CREATE VIRTUAL TABLE transcript_entries_fts USING fts5(
            content,
            entry_id UNINDEXED,
            project_id UNINDEXED,
            role UNINDEXED,
            created_at UNINDEXED,
            tokenize = 'unicode61 remove_diacritics 2 separators _'
        )
    """)

    // Populate from existing entries (user/assistant only, display_in_timeline)
    try db.execute(sql: """
        INSERT INTO transcript_entries_fts (content, entry_id, project_id, role, created_at)
        SELECT content, id, project_id, role, created_at
        FROM transcript_entries
        WHERE role IN ('user', 'assistant')
          AND display_in_timeline = 1
          AND content IS NOT NULL
          AND content != ''
    """)

    // AFTER INSERT trigger
    try db.execute(sql: """
        CREATE TRIGGER transcript_entries_fts_insert
        AFTER INSERT ON transcript_entries
        WHEN NEW.role IN ('user', 'assistant')
          AND NEW.display_in_timeline = 1
          AND NEW.content IS NOT NULL
          AND NEW.content != ''
        BEGIN
            INSERT INTO transcript_entries_fts (content, entry_id, project_id, role, created_at)
            VALUES (NEW.content, NEW.id, NEW.project_id, NEW.role, NEW.created_at);
        END
    """)

    // AFTER UPDATE trigger
    try db.execute(sql: """
        CREATE TRIGGER transcript_entries_fts_update
        AFTER UPDATE ON transcript_entries
        BEGIN
            -- Delete if no longer indexable
            DELETE FROM transcript_entries_fts
            WHERE entry_id = OLD.id
              AND (NEW.role NOT IN ('user', 'assistant')
                   OR NEW.display_in_timeline = 0
                   OR NEW.content IS NULL);

            -- Update if still indexable and was indexable
            UPDATE transcript_entries_fts
            SET content = NEW.content,
                project_id = NEW.project_id,
                role = NEW.role,
                created_at = NEW.created_at
            WHERE entry_id = OLD.id
              AND NEW.role IN ('user', 'assistant')
              AND NEW.display_in_timeline = 1
              AND NEW.content IS NOT NULL;

            -- Insert if newly indexable
            INSERT INTO transcript_entries_fts (content, entry_id, project_id, role, created_at)
            SELECT NEW.content, NEW.id, NEW.project_id, NEW.role, NEW.created_at
            WHERE NEW.role IN ('user', 'assistant')
              AND NEW.display_in_timeline = 1
              AND NEW.content IS NOT NULL
          AND NEW.content != ''
              AND NOT EXISTS (SELECT 1 FROM transcript_entries_fts WHERE entry_id = NEW.id);
        END
    """)

    // AFTER DELETE trigger
    try db.execute(sql: """
        CREATE TRIGGER transcript_entries_fts_delete
        AFTER DELETE ON transcript_entries
        BEGIN
            DELETE FROM transcript_entries_fts WHERE entry_id = OLD.id;
        END
    """)

    // Log backfill for observability
    let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries_fts") ?? 0
    try db.execute(sql: """
        INSERT INTO system_events (event_type, payload, timestamp)
        VALUES ('fts_backfill', '{"rows": \(count)}', CAST(strftime('%s','now') AS INTEGER))
    """)
}

// Update schema version
static let version = 28
```

**Key changes from v1:**
- Uses `transcript_entries` (correct table name)
- Adds `separators _` to tokenizer so `UNREAD_COUNT_UPDATED` matches `unread`, `count`, `updated`
- Includes `display_in_timeline = 1` filter to match timeline semantics
- Has complete `AFTER UPDATE` trigger handling all state transitions
- Logs backfill to `system_events` for observability

---

## 2. Search Service

```swift
// app/Sources/ContextifyCore/Search/SearchService.swift (NEW)

import GRDB

public enum SearchScope: Sendable {
    case project(String)           // Quick Search
    case allProjects               // Deep Search default
    case projects([String])        // Deep Search filtered
}

public struct SearchRequest: Sendable {
    public let query: String
    public let scope: SearchScope
    public let limit: Int
    public let offset: Int

    public init(query: String, scope: SearchScope, limit: Int = 50, offset: Int = 0) {
        self.query = query
        self.scope = scope
        self.limit = min(limit, 50)  // Cap at 50 per page
        self.offset = min(offset, 5000)  // Cap pagination depth
    }
}

public struct SearchHit: Sendable, Identifiable {
    public let id: String          // entry_id
    public let projectId: String
    public let projectName: String
    public let role: String
    public let content: String
    public let createdAt: Date
    public let rank: Double        // BM25 score
    public let snippet: String     // Highlighted snippet
}

public struct SearchResult: Sendable {
    public let hits: [SearchHit]
    public let totalCount: Int
    public let cappedResults: Bool  // True if total > 5000
    public let query: String
    public let scope: SearchScope
}

/// SearchService is read-only and actor-isolated for convenience.
/// It wraps GRDB's read pool; it does not manage its own connection.
public actor SearchService {
    private let dbManager: DatabaseManager

    public init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    public func search(_ request: SearchRequest) async throws -> SearchResult {
        try await dbManager.read { db in
            // Build safe FTS query
            let ftsQuery = Self.buildSafeFTSQuery(request.query)

            guard !ftsQuery.isEmpty else {
                return SearchResult(hits: [], totalCount: 0, cappedResults: false,
                                    query: request.query, scope: request.scope)
            }

            var sql = """
                SELECT
                    f.entry_id,
                    f.project_id,
                    p.name as project_name,
                    f.role,
                    f.content,
                    f.created_at,
                    bm25(transcript_entries_fts) as rank,
                    snippet(transcript_entries_fts, 0, '<mark>', '</mark>', '...', 64) as snippet
                FROM transcript_entries_fts f
                LEFT JOIN projects p ON p.id = f.project_id
                WHERE transcript_entries_fts MATCH ?
            """

            var arguments: [DatabaseValueConvertible] = [ftsQuery]

            // Add scope filter
            switch request.scope {
            case .project(let projectId):
                sql += " AND f.project_id = ?"
                arguments.append(projectId)
            case .allProjects:
                break
            case .projects(let projectIds):
                guard !projectIds.isEmpty else { break }
                let placeholders = projectIds.map { _ in "?" }.joined(separator: ", ")
                sql += " AND f.project_id IN (\(placeholders))"
                arguments.append(contentsOf: projectIds)
            }

            // Order by relevance, then recency as tie-breaker
            sql += """
                ORDER BY rank, f.created_at DESC
                LIMIT ? OFFSET ?
            """
            arguments.append(request.limit)
            arguments.append(request.offset)

            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

            let hits = rows.map { row in
                SearchHit(
                    id: row["entry_id"],
                    projectId: row["project_id"],
                    projectName: row["project_name"] ?? "Unknown",
                    role: row["role"],
                    content: row["content"],
                    createdAt: Date(timeIntervalSince1970: TimeInterval(row["created_at"] as Int64)),
                    rank: row["rank"],
                    snippet: row["snippet"]
                )
            }

            // Get total count (capped query)
            var countSql = """
                SELECT COUNT(*) FROM transcript_entries_fts
                WHERE transcript_entries_fts MATCH ?
            """
            var countArgs: [DatabaseValueConvertible] = [ftsQuery]

            switch request.scope {
            case .project(let projectId):
                countSql += " AND project_id = ?"
                countArgs.append(projectId)
            case .allProjects:
                break
            case .projects(let projectIds):
                guard !projectIds.isEmpty else { break }
                let placeholders = projectIds.map { _ in "?" }.joined(separator: ", ")
                countSql += " AND project_id IN (\(placeholders))"
                countArgs.append(contentsOf: projectIds)
            }

            let rawCount = try Int.fetchOne(db, sql: countSql, arguments: StatementArguments(countArgs)) ?? 0
            let cappedResults = rawCount > 5000
            let totalCount = min(rawCount, 5000)

            return SearchResult(
                hits: hits,
                totalCount: totalCount,
                cappedResults: cappedResults,
                query: request.query,
                scope: request.scope
            )
        }
    }

    /// Get surrounding context for a hit, matching timeline display semantics
    public func getContext(entryId: String, before: Int = 10, after: Int = 19) async throws -> [TranscriptEntry] {
        try await dbManager.read { db in
            // Get the hit's project and created_at for ordering
            guard let hit = try Row.fetchOne(db, sql: """
                SELECT project_id, created_at FROM transcript_entries WHERE id = ?
            """, arguments: [entryId]) else {
                return []
            }

            let projectId: String = hit["project_id"]
            let createdAt: Int64 = hit["created_at"]

            // Get context entries using same predicates as timeline view
            // Uses created_at ordering to match timeline display
            return try TranscriptEntry.fetchAll(db, sql: """
                SELECT * FROM (
                    SELECT * FROM transcript_entries
                    WHERE project_id = ?
                      AND display_in_timeline = 1
                      AND created_at <= ?
                    ORDER BY created_at DESC
                    LIMIT ?
                )
                UNION ALL
                SELECT * FROM (
                    SELECT * FROM transcript_entries
                    WHERE project_id = ?
                      AND display_in_timeline = 1
                      AND created_at > ?
                    ORDER BY created_at ASC
                    LIMIT ?
                )
                ORDER BY created_at ASC
            """, arguments: [projectId, createdAt, before + 1, projectId, createdAt, after])
        }
    }

    /// Check if FTS index is populated (for "indexing in progress" UI)
    public func isIndexReady() async throws -> Bool {
        try await dbManager.read { db in
            let ftsCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcript_entries_fts") ?? 0
            let entryCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM transcript_entries
                WHERE role IN ('user', 'assistant') AND display_in_timeline = 1
            """) ?? 0

            // Consider ready if FTS has at least 90% of entries, or both are 0
            return entryCount == 0 || ftsCount >= Int(Double(entryCount) * 0.9)
        }
    }

    /// Build a safe FTS5 query from user input.
    /// Treats input as space-separated AND of quoted tokens.
    /// E.g., "unread counts bug" → "unread" AND "counts" AND "bug"
    internal static func buildSafeFTSQuery(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Check if user provided an explicit phrase with quotes
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 2 {
            // User wants exact phrase - validate and pass through
            let phrase = String(trimmed.dropFirst().dropLast())
            let sanitized = phrase.replacingOccurrences(of: "\"", with: "")
            return "\"\(sanitized)\""
        }

        // Split on whitespace, wrap each token in quotes, join with AND
        let tokens = trimmed.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { token in
                // Remove any quotes and special chars from individual tokens
                let clean = token
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: ")", with: "")
                return "\"\(clean)\""
            }

        guard !tokens.isEmpty else { return "" }
        return tokens.joined(separator: " AND ")
    }
}
```

**Key changes from v1:**
- Uses `transcript_entries` consistently
- Adds `created_at DESC` tie-breaker to ranking
- Caps pagination at offset 5000
- `cappedResults` flag for "5000+ results" UI
- Context query uses `display_in_timeline = 1` and `created_at` ordering
- `isIndexReady()` for detecting incomplete indexing
- Proper `buildSafeFTSQuery()` that wraps tokens in quotes and joins with AND

---

## 3. HUD Search Field

```swift
// Contextify/Contextify/HUDSearchField.swift (NEW)

import SwiftUI

struct HUDSearchField: View {
    @Binding var query: String
    let onSearch: () -> Void           // Enter pressed
    let onDeepSearch: () -> Void       // Cmd+Enter pressed

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search messages...", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        onSearch()
                    }
                }
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        onDeepSearch()
                        return .handled
                    }
                    return .ignored
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .frame(width: 200)
    }
}
```

---

## 4. Quick Search View (Responsive Layout)

```swift
// Contextify/Contextify/QuickSearchView.swift (NEW)

import SwiftUI

struct QuickSearchView: View {
    let projectId: String
    let projectName: String
    let query: String
    let result: SearchResult
    @Binding var selectedHitId: String?
    let contextEntries: [TranscriptEntry]
    let isIndexReady: Bool
    let onExitSearch: () -> Void
    let onDeepSearch: () -> Void
    let onOpenInTimeline: (String) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 0) {
            // Search Mode Bar
            searchModeBar

            Divider()

            // Responsive split view
            if isCompact {
                verticalLayout
            } else {
                horizontalLayout
            }
        }
    }

    private var isCompact: Bool {
        // Use vertical layout for narrow windows
        // This will be refined based on actual window width
        sizeClass == .compact
    }

    private var searchModeBar: some View {
        HStack {
            Text("Search results for \"\(query)\"")
                .font(.headline)
                .lineLimit(1)

            Text("·").foregroundStyle(.secondary)

            Text(projectName)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("·").foregroundStyle(.secondary)

            if result.cappedResults {
                Text("5000+ matches")
                    .foregroundStyle(.orange)
            } else {
                Text("\(result.totalCount) matches")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Exit Search") { onExitSearch() }

            Button("Deep Search... ⌘⏎") { onDeepSearch() }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var horizontalLayout: some View {
        HSplitView {
            resultsList
                .frame(minWidth: 250, idealWidth: 300)

            contextPreview
                .frame(minWidth: 300)
        }
    }

    @ViewBuilder
    private var verticalLayout: some View {
        VSplitView {
            resultsList
                .frame(minHeight: 150, idealHeight: 200)

            contextPreview
                .frame(minHeight: 200)
        }
    }

    private var resultsList: some View {
        Group {
            if !isIndexReady {
                indexingBanner
            }

            SearchResultList(
                hits: result.hits,
                selectedId: $selectedHitId,
                showProject: false
            )

            if result.cappedResults {
                Text("Showing first 5000 results. Refine your search for better results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private var indexingBanner: some View {
        HStack {
            ProgressView().scaleEffect(0.7)
            Text("Indexing conversations... results may be incomplete")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.yellow.opacity(0.1))
    }

    @ViewBuilder
    private var contextPreview: some View {
        if let hitId = selectedHitId {
            SearchContextPreview(
                hitId: hitId,
                entries: contextEntries,
                onOpenInTimeline: { onOpenInTimeline(hitId) },
                onCopyExcerpt: { copyExcerpt() },
                onCopyForAI: { copyForAI() }
            )
        } else {
            ContentUnavailableView(
                "Select a result",
                systemImage: "doc.text.magnifyingglass"
            )
        }
    }

    private func copyExcerpt() {
        // Format and copy to clipboard
    }

    private func copyForAI() {
        // Format AI-friendly block and copy
    }
}
```

**Key changes from v1:**
- Responsive layout: vertical split for narrow windows
- `cappedResults` warning banner
- `isIndexReady` for indexing-in-progress UI

---

## 5. Deep Search ViewModel (Dependency Injection)

```swift
// Contextify/Contextify/DeepSearchViewModel.swift

@MainActor
final class DeepSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var scopeSelection: ScopeSelection = .all
    @Published var result: SearchResult?
    @Published var selectedHitId: String?
    @Published var contextEntries: [TranscriptEntry] = []
    @Published var isSearching = false
    @Published var isIndexReady = true
    @Published var searchError: Error?
    @Published var offset = 0
    @Published var availableProjects: [DiscoveredProject] = []

    // Injected dependency
    private let searchService: SearchService

    init(searchService: SearchService) {
        self.searchService = searchService
        Task { await checkIndexStatus() }
    }

    // Convenience init for production
    convenience init() {
        self.init(searchService: SearchService(dbManager: .shared))
    }

    private func checkIndexStatus() async {
        do {
            isIndexReady = try await searchService.isIndexReady()
        } catch {
            isIndexReady = true // Assume ready on error
        }
    }

    func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isSearching = true
        searchError = nil

        Task {
            do {
                let scope: SearchScope = switch scopeSelection {
                case .all: .allProjects
                case .project(let id): .project(id)
                }

                let request = SearchRequest(
                    query: query,
                    scope: scope,
                    limit: 50,
                    offset: offset
                )

                result = try await searchService.search(request)

                // Auto-select first result
                if let firstHit = result?.hits.first {
                    selectedHitId = firstHit.id
                    await loadContext(for: firstHit.id)
                }
            } catch {
                searchError = error
            }
            isSearching = false
        }
    }

    func loadContext(for entryId: String) async {
        do {
            contextEntries = try await searchService.getContext(entryId: entryId)
        } catch {
            contextEntries = []
        }
    }

    func nextPage() {
        guard let result = result, offset + 50 < result.totalCount else { return }
        offset += 50
        search()
    }

    func previousPage() {
        guard offset > 0 else { return }
        offset = max(0, offset - 50)
        search()
    }

    // ... other methods unchanged
}
```

**Key changes from v1:**
- `SearchService` injected via init (testable)
- `isIndexReady` state for UI
- Pagination respects `totalCount` cap

---

## 6. Testing Requirements

```swift
// Tests/ContextifyCoreTests/SearchServiceTests.swift

final class SearchServiceTests: XCTestCase {

    // MARK: - Query Building Tests

    func testBuildSafeFTSQuery_simpleTokens() {
        let result = SearchService.buildSafeFTSQuery("unread count")
        XCTAssertEqual(result, "\"unread\" AND \"count\"")
    }

    func testBuildSafeFTSQuery_phraseSearch() {
        let result = SearchService.buildSafeFTSQuery("\"exact phrase\"")
        XCTAssertEqual(result, "\"exact phrase\"")
    }

    func testBuildSafeFTSQuery_specialCharacters() {
        let result = SearchService.buildSafeFTSQuery("foo* (bar) \"baz\"")
        XCTAssertEqual(result, "\"foo\" AND \"bar\" AND \"baz\"")
    }

    func testBuildSafeFTSQuery_empty() {
        let result = SearchService.buildSafeFTSQuery("   ")
        XCTAssertEqual(result, "")
    }

    // MARK: - Tokenizer Behavior Tests

    func testFTS_underscoreSeparator_matchesIndividualTokens() async throws {
        // Setup: Insert entry with "UNREAD_COUNT_UPDATED"
        // Search for "unread" - should match
        // Search for "count" - should match
        // Search for "unread count" - should match
    }

    func testFTS_displayInTimeline_excludesHiddenEntries() async throws {
        // Setup: Insert entry with display_in_timeline = 0
        // Search - should NOT appear in results
    }

    // MARK: - Context Query Tests

    func testGetContext_respectsDisplayInTimeline() async throws {
        // Setup: Insert mix of visible/hidden entries
        // Get context - should only include display_in_timeline = 1
    }

    func testGetContext_orderedByCreatedAt() async throws {
        // Setup: Insert entries with various timestamps
        // Get context - should be ordered by created_at ASC
    }
}
```

---

## 7. Resolved Open Questions

| Question | Decision |
|----------|----------|
| FTS5 schema UNINDEXED? | Yes, metadata columns are UNINDEXED |
| Triggers vs GRDB observers? | Triggers - centralizes sync guarantee |
| SearchService as actor? | Yes, actor is fine for read-only service |
| Context window efficiency? | `created_at` ordering with UNION is efficient |
| Handle updates/deletes? | Full trigger coverage (INSERT/UPDATE/DELETE) |
| Time estimate? | 12-16 hours realistic with tests + polish |
| Shared vs separate service? | Shared SearchService with scope enum |
| Large result sets? | Cap at 5000, show "refine search" message |
| HSplitView compactness? | Responsive: vertical split for narrow windows |
| Migration blocking? | Synchronous backfill OK for now, log to system_events |
| Tokenizer for code? | `separators _` so identifiers match partial terms |
| Ranking recency? | `ORDER BY rank, created_at DESC` |

---

## 8. Implementation Phases (Updated)

### Phase 1A: Core Search (5-7 hours)
- Add FTS5 migration v28 with triggers
- Implement SearchService with safe query builder
- Add search field to HUD toolbar
- Quick Search view with responsive layout
- Basic copy actions

### Phase 1B: Deep Search Window (3-4 hours)
- Create DeepSearchWindow with injected SearchService
- Pagination with 5000 cap
- Project filter dropdown
- "Open in HUD" action

### Phase 1C: Polish (3-4 hours)
- Keyboard navigation
- "Indexing in progress" UI
- Empty states
- Error handling
- Unit tests for query builder and tokenizer

**Total Phase 1: 12-16 hours**

---

## 9. File Changes Summary

| File | Change |
|------|--------|
| `DatabaseSchema.swift` | Add migration v28 (FTS5 + triggers) |
| `SearchService.swift` | NEW - Search backend with safe query builder |
| `SearchModels.swift` | NEW - SearchRequest, SearchHit, SearchResult |
| `HUDSearchField.swift` | NEW - Search field component |
| `QuickSearchView.swift` | NEW - Responsive Quick Search UI |
| `SearchResultList.swift` | NEW - Reusable result list |
| `SearchContextPreview.swift` | NEW - Context excerpt view |
| `DeepSearchWindow.swift` | NEW - Deep Search window |
| `DeepSearchViewModel.swift` | NEW - With DI for SearchService |
| `SearchServiceTests.swift` | NEW - Query builder + tokenizer tests |

---

## References

- Full spec: `build/notes/todo-support/P1-CONVO-SEARCH-spec.md`
- FTS5 documentation: https://www.sqlite.org/fts5.html
- GRDB FTS support: https://github.com/groue/GRDB.swift/blob/master/Documentation/FullTextSearch.md
