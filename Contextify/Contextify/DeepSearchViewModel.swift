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

  /// Context extent state
  var earlierCount: Int = 0  // Entries available before current window
  var laterCount: Int = 0    // Entries available after current window
  var contextBefore: Int = 10  // How many entries loaded before hit
  var contextAfter: Int = 10   // How many entries loaded after hit

  /// Whether to scroll to hit after context loads (false when loading more)
  var shouldScrollToHit: Bool = false

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
  private var contextTask: Task<Void, Never>?

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

    let resultCount = initialResult?.hits.count ?? 0
    log.info("[DEEPSEARCH-INIT] projectId=\(projectId, privacy: .public) query='\(initialQuery, privacy: .public)' initialResultCount=\(resultCount) selectedHitId=\(selectedHitId ?? "nil", privacy: .public)")

    // Load context if we have a selected hit, or auto-select first result
    if let hitId = selectedHitId {
      log.debug("[DEEPSEARCH-INIT] Loading context for explicit selection: \(hitId, privacy: .public)")
      let searchService = self.searchService
      contextTask = Task.detached { [searchService, hitId] in
        do {
          let data = try await Self.fetchContextData(
            searchService: searchService,
            entryId: hitId,
            before: 10,
            after: 10
          )
          guard !Task.isCancelled else { return }
          await MainActor.run { [weak self] in
            self?.applyContext(data: data, before: 10, after: 10, scrollToHit: true)
          }
        } catch {
          guard !Task.isCancelled else { return }
          await MainActor.run {
            log.error("[DEEPSEARCH-INIT] Failed to load context: \(error.localizedDescription)")
          }
        }
      }
    } else if let firstHit = initialResult?.hits.first {
      // Auto-select first result when opening via Cmd+Enter (no explicit selection)
      log.debug("[DEEPSEARCH-INIT] Auto-selecting first result: \(firstHit.id, privacy: .public)")
      self.selectedHitId = firstHit.id
      let searchService = self.searchService
      let hitId = firstHit.id
      contextTask = Task.detached { [searchService, hitId] in
        do {
          let data = try await Self.fetchContextData(
            searchService: searchService,
            entryId: hitId,
            before: 10,
            after: 10
          )
          guard !Task.isCancelled else { return }
          await MainActor.run { [weak self] in
            self?.applyContext(data: data, before: 10, after: 10, scrollToHit: true)
          }
        } catch {
          guard !Task.isCancelled else { return }
          await MainActor.run {
            log.error("[DEEPSEARCH-INIT] Failed to load context: \(error.localizedDescription)")
          }
        }
      }
    } else {
      log.debug("[DEEPSEARCH-INIT] No results to select")
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

    log.info("[DEEPSEARCH-START] query='\(trimmedQuery, privacy: .public)' projectId=\(self.projectId, privacy: .public)")

    // Snapshot main-actor state before detaching
    let searchService = self.searchService
    let projectId = self.projectId
    let previousSelection = self.selectedHitId

    searchTask = Task.detached { [searchService, projectId, trimmedQuery, previousSelection] in
      do {
        let searchStart = Date()
        let request = ConversationSearchRequest(
          query: trimmedQuery,
          scope: .project(projectId),
          limit: 50,
          offset: 0
        )

        let searchResult = try await searchService.search(request)
        let searchDuration = Date().timeIntervalSince(searchStart)

        guard !Task.isCancelled else {
          await MainActor.run { log.debug("[DEEPSEARCH-CANCEL] Search cancelled for query='\(trimmedQuery, privacy: .public)'") }
          return
        }

        // Determine selection off main actor using snapshot
        var selectedId: String? = nil
        if let hitId = previousSelection,
           searchResult.hits.contains(where: { $0.id == hitId }) {
          selectedId = hitId
        } else {
          selectedId = searchResult.hits.first?.id
        }

        // Fetch context off main actor if we have a selection
        var contextData: ContextData? = nil
        if let hitId = selectedId {
          contextData = try await Self.fetchContextData(
            searchService: searchService,
            entryId: hitId,
            before: 10,
            after: 10
          )
        }

        let totalDuration = Date().timeIntervalSince(searchStart)
        let contextDuration = totalDuration - searchDuration

        guard !Task.isCancelled else { return }

        // Single hop back to main actor to update ALL UI state
        await MainActor.run { [weak self] in
          guard let self else { return }

          self.result = searchResult
          self.selectedHitId = selectedId

          if let data = contextData {
            self.applyContext(data: data, before: 10, after: 10, scrollToHit: true)
          } else {
            self.clearContext()
          }

          self.isSearching = false

          log.debug("[DEEPSEARCH-TIMING] FTS query took \(String(format: "%.3f", searchDuration), privacy: .public)s")
          log.debug("[DEEPSEARCH-TIMING] Context load took \(String(format: "%.3f", contextDuration), privacy: .public)s")
          log.info("[DEEPSEARCH-DONE] query='\(trimmedQuery, privacy: .public)' hits=\(searchResult.hits.count)")
          log.debug("[DEEPSEARCH-TIMING] Search complete, isSearching=false")
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

  /// Load more entries before the current window
  func loadMoreEarlier() {
    guard let entryId = selectedHitId else { return }
    contextBefore += 5
    shouldScrollToHit = false  // Don't scroll when loading more

    let searchService = self.searchService
    let before = self.contextBefore
    let after = self.contextAfter

    Task.detached { [searchService, entryId, before, after] in
      do {
        let data = try await Self.fetchContextData(
          searchService: searchService,
          entryId: entryId,
          before: before,
          after: after
        )
        guard !Task.isCancelled else { return }
        await MainActor.run { [weak self] in
          self?.applyContext(data: data, before: before, after: after, scrollToHit: false)
        }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run {
          log.error("[CONTEXT] Load more earlier failed: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Load more entries after the current window
  func loadMoreLater() {
    guard let entryId = selectedHitId else { return }
    contextAfter += 5
    shouldScrollToHit = false  // Don't scroll when loading more

    let searchService = self.searchService
    let before = self.contextBefore
    let after = self.contextAfter

    Task.detached { [searchService, entryId, before, after] in
      do {
        let data = try await Self.fetchContextData(
          searchService: searchService,
          entryId: entryId,
          before: before,
          after: after
        )
        guard !Task.isCancelled else { return }
        await MainActor.run { [weak self] in
          self?.applyContext(data: data, before: before, after: after, scrollToHit: false)
        }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run {
          log.error("[CONTEXT] Load more later failed: \(error.localizedDescription)")
        }
      }
    }
  }

  /// Select a hit and load its context
  func selectHit(_ hitId: String) {
    // Cancel any in-flight context load
    contextTask?.cancel()
    selectedHitId = hitId
    log.debug("[SELECTHIT] Selected hit: \(hitId, privacy: .public)")

    let searchService = self.searchService
    contextTask = Task.detached { [searchService, hitId] in
      do {
        let loadStart = Date()
        let data = try await Self.fetchContextData(
          searchService: searchService,
          entryId: hitId,
          before: 10,
          after: 10
        )
        let loadDuration = Date().timeIntervalSince(loadStart)

        guard !Task.isCancelled else {
          await MainActor.run { log.debug("[SELECTHIT] Cancelled after load: \(hitId, privacy: .public)") }
          return
        }

        await MainActor.run { [weak self] in
          guard let self else { return }
          self.applyContext(data: data, before: 10, after: 10, scrollToHit: true)
          log.debug("[SELECTHIT] Context applied: \(data.entries.count) entries in \(String(format: "%.3f", loadDuration))s for \(hitId, privacy: .public)")
        }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run { [weak self] in
          self?.clearContext()
          log.error("[SELECTHIT] Failed to load context for \(hitId, privacy: .public): \(error.localizedDescription)")
        }
      }
    }
  }

  /// Clear results when query is edited (invalidate stale results)
  func clearResults() {
    searchTask?.cancel()
    result = nil
    selectedHitId = nil
    contextEntries = []
    earlierCount = 0
    laterCount = 0
    isSearching = false
    searchError = nil
  }

  // MARK: - Private Helpers

  /// Data structure for context fetch results (Sendable for cross-actor transfer)
  private struct ContextData: Sendable {
    let entries: [TranscriptEntry]
    let earlierCount: Int
    let laterCount: Int
  }

  /// Fetch context data off main actor
  /// - Note: This is a static helper to ensure it runs off main actor
  private static func fetchContextData(
    searchService: ConversationSearchService,
    entryId: String,
    before: Int,
    after: Int
  ) async throws -> ContextData {
    let entries = try await searchService.getContext(entryId: entryId, before: before, after: after)
    let counts = try await searchService.getContextCounts(entryId: entryId, currentBefore: before, currentAfter: after)
    return ContextData(entries: entries, earlierCount: counts.earlierCount, laterCount: counts.laterCount)
  }

  /// Apply context data to UI state (must be called on main actor)
  private func applyContext(
    data: ContextData,
    before: Int,
    after: Int,
    scrollToHit: Bool
  ) {
    contextEntries = data.entries
    earlierCount = data.earlierCount
    laterCount = data.laterCount
    contextBefore = before
    contextAfter = after
    shouldScrollToHit = scrollToHit
  }

  /// Clear context state
  private func clearContext() {
    contextEntries = []
    earlierCount = 0
    laterCount = 0
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
