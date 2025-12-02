import SwiftUI
import OSLog
import ContextifyCore

private let log = Logger(subsystem: "dev.contextify", category: "QuickSearch")

/// HUD mode for switching between timeline and search
enum HUDMode: Equatable {
  case timeline
  case quickSearch(query: String)
}

/// ViewModel for Quick Search functionality in the HUD
@MainActor
@Observable
final class QuickSearchViewModel {
  // MARK: - Published State

  /// Current search query text
  var query: String = ""

  /// Search results
  var result: ConversationSearchResult?

  /// Currently selected hit ID
  var selectedHitId: String?

  /// Context entries for selected hit
  var contextEntries: [TranscriptEntry] = []

  /// Is search in progress
  var isSearching = false

  /// Is FTS index ready
  var isIndexReady = true

  /// Search error if any
  var searchError: Error?

  /// Current HUD mode
  var mode: HUDMode = .timeline

  // MARK: - Private Properties

  private let searchService: ConversationSearchService
  private var searchTask: Task<Void, Never>?

  // MARK: - Initialization

  init(searchService: ConversationSearchService? = nil) {
    self.searchService = searchService ?? ConversationSearchService()
    Task { await checkIndexStatus() }
  }

  // MARK: - Public Methods

  /// Execute search for the current project
  /// - Parameter projectId: The project ID to search within
  func search(projectId: String) {
    let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
    guard !trimmedQuery.isEmpty else {
      exitSearch()
      return
    }

    // Cancel any in-flight search
    searchTask?.cancel()

    isSearching = true
    searchError = nil
    mode = .quickSearch(query: trimmedQuery)

    log.info("[SEARCH-START] QuickSearch query='\(trimmedQuery, privacy: .public)' projectId=\(projectId, privacy: .public)")

    // Snapshot main-actor state before detaching
    let searchService = self.searchService

    searchTask = Task.detached { [searchService, projectId, trimmedQuery] in
      do {
        let request = ConversationSearchRequest(
          query: trimmedQuery,
          scope: .project(projectId),
          limit: 50,
          offset: 0
        )

        let searchResult = try await searchService.search(request)

        guard !Task.isCancelled else {
          await MainActor.run { log.debug("[SEARCH-CANCEL] QuickSearch cancelled for query='\(trimmedQuery, privacy: .public)'") }
          return
        }

        // Determine selection and fetch context off main actor
        var contextEntries: [TranscriptEntry] = []
        let selectedId = searchResult.hits.first?.id
        if let hitId = selectedId {
          contextEntries = try await searchService.getContext(entryId: hitId)
        }

        guard !Task.isCancelled else { return }

        // Single hop back to main actor to update ALL UI state
        await MainActor.run { [weak self] in
          guard let self else { return }

          self.result = searchResult
          self.selectedHitId = selectedId
          self.contextEntries = contextEntries
          self.isSearching = false

          log.info("[SEARCH-DONE] QuickSearch query='\(trimmedQuery, privacy: .public)' hits=\(searchResult.hits.count) total=\(searchResult.totalCount)")
        }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run { [weak self] in
          guard let self else { return }
          self.searchError = error
          self.isSearching = false
          log.error("[SEARCH] Error: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Execute search and wait for completion
  /// - Parameter projectId: The project ID to search within
  func searchAndWait(projectId: String) async {
    search(projectId: projectId)
    await searchTask?.value
  }

  /// Select a hit and load its context
  /// - Parameter hitId: The hit ID to select
  func selectHit(_ hitId: String) {
    selectedHitId = hitId

    let searchService = self.searchService
    Task.detached { [searchService, hitId] in
      do {
        let entries = try await searchService.getContext(entryId: hitId)
        guard !Task.isCancelled else { return }
        await MainActor.run { [weak self] in
          self?.contextEntries = entries
          log.debug("[CONTEXT] Loaded \(entries.count) context entries for \(hitId)")
        }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run { [weak self] in
          self?.contextEntries = []
          log.error("[CONTEXT] Failed to load context: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Exit search mode and return to timeline
  func exitSearch() {
    searchTask?.cancel()
    mode = .timeline
    result = nil
    selectedHitId = nil
    contextEntries = []
    isSearching = false
    searchError = nil
    // Note: query is preserved for re-use
  }

  /// Clear the search query
  func clearQuery() {
    query = ""
    exitSearch()
  }

  /// Clear results only (keeps query for re-search)
  /// Called when user edits the search field to invalidate stale results
  func clearResults() {
    searchTask?.cancel()
    result = nil
    selectedHitId = nil
    contextEntries = []
    isSearching = false
    searchError = nil
    if mode != .timeline {
      mode = .timeline
    }
  }

  /// Check if FTS index is ready
  private func checkIndexStatus() async {
    do {
      isIndexReady = try await searchService.isIndexReady()
    } catch {
      isIndexReady = true // Assume ready on error
    }
  }

  // MARK: - Copy Actions

  /// Copy visible context entries to clipboard
  func copyVisible(projectName: String) {
    guard !contextEntries.isEmpty else { return }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    // DateFormatter uses non-breaking spaces (U+00A0) - normalize to regular spaces
    func normalizeSpaces(_ str: String) -> String {
      str.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    let first = contextEntries.first!
    let last = contextEntries.last!
    let startTime = normalizeSpaces(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(first.timestamp))))
    let endTime = normalizeSpaces(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(last.timestamp))))

    var text = """
      CONTEXTIFY EXCERPT
      Project: \(projectName)
      Time range: \(startTime) - \(endTime)

      """

    for entry in contextEntries {
      let time = normalizeSpaces(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.timestamp))))
      let role = entry.kind.capitalized
      text += "[\(role), \(time)]: \(entry.content)\n\n"
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    let count = contextEntries.count
    log.info("[COPY] Copied \(count) visible messages")
  }
}
