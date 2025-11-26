import SwiftUI
import OSLog
import ContextifyCore

private let log = Logger(subsystem: "dev.contextify", category: "DeepSearchVM")

/// ViewModel for Deep Search Window
@MainActor
@Observable
final class DeepSearchViewModel {
  // MARK: - Published State

  /// Current search query
  var query: String

  /// Search results
  var result: ConversationSearchResult?

  /// Currently selected hit ID
  var selectedHitId: String?

  /// Context entries for selected hit
  var contextEntries: [TranscriptEntry] = []

  /// Is search in progress
  var isSearching = false

  /// Search error if any
  var searchError: Error?

  // MARK: - Configuration

  let projectId: String
  let projectName: String

  // MARK: - Private Properties

  private let searchService: ConversationSearchService
  private var searchTask: Task<Void, Never>?

  // MARK: - Initialization

  init(
    projectId: String,
    projectName: String,
    initialQuery: String,
    selectedHitId: String?,
    initialResult: ConversationSearchResult?,
    searchService: ConversationSearchService? = nil
  ) {
    self.projectId = projectId
    self.projectName = projectName
    self.query = initialQuery
    self.selectedHitId = selectedHitId
    self.result = initialResult
    self.searchService = searchService ?? ConversationSearchService()

    // Load context if we have a selected hit
    if let hitId = selectedHitId {
      Task {
        await loadContext(for: hitId)
      }
    }
  }

  // MARK: - Search

  /// Execute search for the current project
  func search() {
    let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
    guard !trimmedQuery.isEmpty else { return }

    searchTask?.cancel()
    isSearching = true
    searchError = nil

    searchTask = Task {
      do {
        let request = ConversationSearchRequest(
          query: trimmedQuery,
          scope: .project(projectId),
          limit: 50,
          offset: 0
        )

        let searchResult = try await searchService.search(request)
        guard !Task.isCancelled else { return }

        result = searchResult
        log.info("[SEARCH] '\(trimmedQuery)' returned \(searchResult.hits.count) hits")

        // Auto-select first result if none selected
        if selectedHitId == nil, let firstHit = searchResult.hits.first {
          selectedHitId = firstHit.id
          await loadContext(for: firstHit.id)
        } else if let hitId = selectedHitId {
          await loadContext(for: hitId)
        }
      } catch {
        if !Task.isCancelled {
          searchError = error
          log.error("[SEARCH] Error: \(error.localizedDescription)")
        }
      }

      isSearching = false
    }
  }

  /// Load context entries for a selected hit
  func loadContext(for entryId: String) async {
    do {
      let entries = try await searchService.getContext(entryId: entryId)
      contextEntries = entries
      log.debug("[CONTEXT] Loaded \(entries.count) context entries")
    } catch {
      contextEntries = []
      log.error("[CONTEXT] Failed: \(error.localizedDescription)")
    }
  }

  /// Select a hit and load its context
  func selectHit(_ hitId: String) {
    selectedHitId = hitId
    Task {
      await loadContext(for: hitId)
    }
  }

  // MARK: - Copy Actions

  func copyExcerpt() {
    guard !contextEntries.isEmpty else { return }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    let first = contextEntries.first!
    let last = contextEntries.last!
    let startTime = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(first.timestamp)))
    let endTime = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(last.timestamp)))

    var text = """
      CONTEXTIFY EXCERPT
      Project: \(projectName)
      Time range: \(startTime) - \(endTime)
      Messages: \(contextEntries.count)

      """

    for entry in contextEntries {
      let time = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.timestamp)))
      let role = entry.kind.capitalized
      text += "[\(role), \(time)]: \(entry.content)\n\n"
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    let count = contextEntries.count
    log.info("[COPY] Copied excerpt with \(count) messages")
  }

  func copyForAI() {
    guard !contextEntries.isEmpty else { return }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    let first = contextEntries.first!
    let last = contextEntries.last!
    let startTime = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(first.timestamp)))
    let endTime = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(last.timestamp)))

    var text = """
      CONTEXTIFY CONTEXT EXCERPT
      Project: \(projectName)
      Time range: \(startTime) - \(endTime)

      """

    for entry in contextEntries {
      let time = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(entry.timestamp)))
      let role = entry.kind.capitalized
      text += "[\(role), \(time)]: \(entry.content)\n\n"
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    let count = contextEntries.count
    log.info("[COPY] Copied AI context with \(count) messages")
  }
}
