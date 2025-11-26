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

    // Load context if we have a selected hit, or auto-select first result
    if let hitId = selectedHitId {
      Task {
        await loadContext(for: hitId)
      }
    } else if let firstHit = initialResult?.hits.first {
      // Auto-select first result when opening via Cmd+Enter (no explicit selection)
      self.selectedHitId = firstHit.id
      Task {
        await loadContext(for: firstHit.id)
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
    // Reset context extent when loading new hit
    contextBefore = 10
    contextAfter = 10

    do {
      let entries = try await searchService.getContext(
        entryId: entryId,
        before: contextBefore,
        after: contextAfter
      )
      contextEntries = entries

      // Get counts for "load more" UI
      let counts = try await searchService.getContextCounts(
        entryId: entryId,
        currentBefore: contextBefore,
        currentAfter: contextAfter
      )
      earlierCount = counts.earlierCount
      laterCount = counts.laterCount

      log.debug("[CONTEXT] Loaded \(entries.count) entries (\(self.earlierCount) earlier, \(self.laterCount) later available)")
    } catch {
      contextEntries = []
      earlierCount = 0
      laterCount = 0
      log.error("[CONTEXT] Failed: \(error.localizedDescription)")
    }
  }

  /// Load more entries before the current window
  func loadMoreEarlier() {
    guard let entryId = selectedHitId else { return }
    contextBefore += 5
    Task {
      do {
        let entries = try await searchService.getContext(
          entryId: entryId,
          before: contextBefore,
          after: contextAfter
        )
        contextEntries = entries

        let counts = try await searchService.getContextCounts(
          entryId: entryId,
          currentBefore: contextBefore,
          currentAfter: contextAfter
        )
        earlierCount = counts.earlierCount
        laterCount = counts.laterCount
      } catch {
        log.error("[CONTEXT] Load more earlier failed: \(error.localizedDescription)")
      }
    }
  }

  /// Load more entries after the current window
  func loadMoreLater() {
    guard let entryId = selectedHitId else { return }
    contextAfter += 5
    Task {
      do {
        let entries = try await searchService.getContext(
          entryId: entryId,
          before: contextBefore,
          after: contextAfter
        )
        contextEntries = entries

        let counts = try await searchService.getContextCounts(
          entryId: entryId,
          currentBefore: contextBefore,
          currentAfter: contextAfter
        )
        earlierCount = counts.earlierCount
        laterCount = counts.laterCount
      } catch {
        log.error("[CONTEXT] Load more later failed: \(error.localizedDescription)")
      }
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
