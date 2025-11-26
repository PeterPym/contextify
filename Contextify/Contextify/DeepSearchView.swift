import SwiftUI
import OSLog
import ContextifyCore

private let log = Logger(subsystem: "dev.contextify", category: "DeepSearchView")

/// Deep Search window content with split-view layout
struct DeepSearchView: View {
  @Environment(DeepSearchViewModel.self) private var viewModel
  @State private var isSearchPresented = false  // Cmd+F support

  /// Extract search terms from query for highlighting in context
  private var searchTerms: [String] {
    // Split query into words, filter out empty strings and very short terms
    viewModel.query
      .components(separatedBy: .whitespaces)
      .map { $0.trimmingCharacters(in: .punctuationCharacters) }
      .filter { $0.count >= 2 }
  }

  var body: some View {
    Group {
      if let result = viewModel.result {
        HSplitView {
          resultsList(result)
            .frame(minWidth: 280, idealWidth: 320)

          contextPane
            .frame(minWidth: 350)
        }
      } else if viewModel.isSearching {
        loadingState
      } else if let error = viewModel.searchError {
        errorState(error)
      } else {
        emptyState
      }
    }
    .searchable(
      text: Binding(
        get: { viewModel.query },
        set: { viewModel.query = $0 }
      ),
      isPresented: $isSearchPresented,
      prompt: "Search"
    )
    .onSubmit(of: .search) {
      viewModel.search()
    }
    // Cmd+F to focus search field
    .background {
      Button("") { isSearchPresented = true }
        .keyboardShortcut("f", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
    }
  }

  @State private var showSearchInfo = false

  // MARK: - Results List

  private func resultsList(_ result: ConversationSearchResult) -> some View {
    VStack(spacing: 0) {
      // Results header with role breakdown and info button
      HStack(spacing: 6) {
        resultsBreakdown(result)

        InfoButton(isPresented: $showSearchInfo)
          .popover(isPresented: $showSearchInfo) {
            SearchInfoPopover()
          }

        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color(nsColor: .controlBackgroundColor))

      Divider()

      if result.hits.isEmpty {
        noResultsState
      } else {
        ScrollViewReader { proxy in
          List(selection: Binding(
            get: { viewModel.selectedHitId },
            set: { newValue in
              if let id = newValue {
                viewModel.selectHit(id)
              }
            }
          )) {
            ForEach(result.hits) { hit in
              DeepSearchHitRow(hit: hit, isSelected: hit.id == viewModel.selectedHitId)
                .tag(hit.id)
                .id(hit.id)
            }
          }
          .listStyle(.sidebar)
          .onChange(of: viewModel.selectedHitId) { _, newId in
            // Scroll results list to selected hit
            if let hitId = newId {
              proxy.scrollTo(hitId, anchor: .center)
            }
          }
        }
      }
    }
  }

  private var noResultsState: some View {
    ContentUnavailableView {
      Label("No Results", systemImage: "magnifyingglass")
    } description: {
      Text("No matches found for \"\(viewModel.query)\"")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Context Pane

  @ViewBuilder
  private var contextPane: some View {
    if let hitId = viewModel.selectedHitId {
      VStack(spacing: 0) {
        contextHeader
        Divider()

        if viewModel.contextEntries.isEmpty {
          ProgressView("Loading context...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollViewReader { proxy in
            List {
              // Load more earlier row
              if viewModel.earlierCount > 0 {
                LoadMoreRow(
                  direction: .earlier,
                  count: viewModel.earlierCount,
                  action: { viewModel.loadMoreEarlier() }
                )
              }

              ForEach(viewModel.contextEntries, id: \.id) { entry in
                ContextEntryRow(
                  entry: entry,
                  isHighlighted: entry.id == hitId,
                  searchTerms: searchTerms
                )
                .id(entry.id)
              }

              // Load more later row
              if viewModel.laterCount > 0 {
                LoadMoreRow(
                  direction: .later,
                  count: viewModel.laterCount,
                  action: { viewModel.loadMoreLater() }
                )
              }
            }
            .listStyle(.plain)
            .onChange(of: viewModel.contextEntries.first?.id) { _, newFirstId in
              // Scroll to highlighted entry when context entries change
              // But NOT when loading more entries (shouldScrollToHit = false)
              guard viewModel.shouldScrollToHit else { return }

              let hitExists = viewModel.contextEntries.contains { $0.id == hitId }
              if newFirstId != nil && hitExists {
                // Workaround: Call scrollTo twice - SwiftUI lazy loading miscalculates
                // offsets on first call. See: https://stackoverflow.com/a/77042664
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                  proxy.scrollTo(hitId, anchor: .center)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                  proxy.scrollTo(hitId, anchor: .center)
                }
              } else if !hitExists {
                log.warning("[CONTEXT-PANE] Cannot scroll - hitId \(hitId, privacy: .public) not found in \(viewModel.contextEntries.count) entries")
              }
            }
          }
        }
      }
    } else {
      ContentUnavailableView(
        "Select a result",
        systemImage: "doc.text.magnifyingglass",
        description: Text("Choose a search result to see the conversation context")
      )
    }
  }

  private var contextHeader: some View {
    HStack {
      Text("Conversation Context")
        .font(.headline)

      Spacer()

      if !viewModel.contextEntries.isEmpty {
        Menu {
          Button("Copy Excerpt") {
            viewModel.copyExcerpt()
          }
          Button("Copy for AI") {
            viewModel.copyForAI()
          }
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 70)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - States

  private var loadingState: some View {
    VStack(spacing: 12) {
      ProgressView()
        .scaleEffect(1.2)
      Text("Searching...")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func errorState(_ error: Error) -> some View {
    ContentUnavailableView {
      Label("Search Error", systemImage: "exclamationmark.triangle")
    } description: {
      Text(error.localizedDescription)
    } actions: {
      Button("Retry") {
        viewModel.search()
      }
      .buttonStyle(.bordered)
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("Search", systemImage: "magnifyingglass")
    } description: {
      Text("Enter a search term to find messages")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Deep Search Hit Row

struct DeepSearchHitRow: View {
  @Environment(\.colorScheme) private var colorScheme
  let hit: ConversationSearchHit
  let isSelected: Bool

  private var provider: TimelineSourceContext.Provider {
    TimelineSourceContext.Provider(rawValue: hit.provider) ?? .other
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      // Use person icon for user, provider icon for assistant
      if hit.role == "user" {
        Image(systemName: "person.fill")
          .foregroundStyle(Color.contextifyBlue)
          .frame(width: 16)
      } else {
        Image(provider.iconImage)
          .renderingMode(.template)
          .foregroundStyle(provider.color)
          .shadow(
            color: (colorScheme == .light && provider == .codexCLI) ? .black.opacity(0.7) : .clear,
            radius: 0.5
          )
          .frame(width: 16)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(attributedSnippet)
          .lineLimit(4)
          .font(.body)

        Text(hit.createdAt, format: .dateTime.month().day().hour().minute())
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 4)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? Color.contextifyYellow.opacity(0.15) : Color.clear)
    )
    .contextMenu {
      Button("Copy as JSON") {
        copyAsJSON()
      }
    }
  }

  private func copyAsJSON() {
    let json: [String: Any] = [
      "id": hit.id,
      "project_id": hit.projectId,
      "project_name": hit.projectName,
      "provider": hit.provider,
      "role": hit.role,
      "content": String(hit.content.prefix(500)),
      "created_at": ISO8601DateFormatter().string(from: hit.createdAt),
      "snippet": hit.snippet.replacingOccurrences(of: "<mark>", with: "")
                           .replacingOccurrences(of: "</mark>", with: "")
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else { return }
    string.copyToClipboard()
  }

  private var attributedSnippet: AttributedString {
    var result = AttributedString()
    var remaining = hit.snippet

    while let markStart = remaining.range(of: "<mark>") {
      let beforeMark = String(remaining[..<markStart.lowerBound])
      result.append(AttributedString(beforeMark))

      remaining = String(remaining[markStart.upperBound...])
      if let markEnd = remaining.range(of: "</mark>") {
        let highlighted = String(remaining[..<markEnd.lowerBound])
        var highlightedAttr = AttributedString(highlighted)
        highlightedAttr.backgroundColor = .yellow.opacity(0.3)
        highlightedAttr.font = .body.bold()
        result.append(highlightedAttr)
        remaining = String(remaining[markEnd.upperBound...])
      }
    }

    result.append(AttributedString(remaining))
    return result
  }
}

// MARK: - Context Entry Row (uses Contextify Yellow for highlight)

struct ContextEntryRow: View {
  @Environment(\.colorScheme) private var colorScheme
  let entry: TranscriptEntry
  let isHighlighted: Bool
  var searchTerms: [String] = []  // Terms to highlight in non-selected entries

  private var provider: TimelineSourceContext.Provider {
    TimelineSourceContext.Provider(rawValue: entry.provider) ?? .other
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      // Use person icon for user, provider icon for assistant
      if entry.kind == "user" {
        Image(systemName: "person.fill")
          .foregroundStyle(Color.contextifyBlue)
          .frame(width: 16)
      } else {
        Image(provider.iconImage)
          .renderingMode(.template)
          .foregroundStyle(provider.color)
          .shadow(
            color: (colorScheme == .light && provider == .codexCLI) ? .black.opacity(0.7) : .clear,
            radius: 0.5
          )
          .frame(width: 16)
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(highlightedContent)
          .font(.body)
          .textSelection(.enabled)

        Text(Date(timeIntervalSince1970: TimeInterval(entry.timestamp)), format: .dateTime.hour().minute().second())
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 8)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isHighlighted ? Color.contextifyYellow.opacity(0.15) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(isHighlighted ? Color.contextifyYellow.opacity(0.5) : Color.clear, lineWidth: 1.5)
    )
    .contextMenu {
      Button("Copy as JSON") {
        copyAsJSON()
      }
    }
  }

  private func copyAsJSON() {
    let json: [String: Any] = [
      "id": entry.id,
      "transcript_id": entry.transcriptId,
      "project_id": entry.projectId,
      "provider": entry.provider,
      "kind": entry.kind,
      "timestamp": entry.timestamp,
      "content": String(entry.content.prefix(500)),
      "is_highlighted": isHighlighted
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else { return }
    string.copyToClipboard()
  }

  /// Highlight search terms in the content (for non-selected entries)
  private var highlightedContent: AttributedString {
    guard !isHighlighted, !searchTerms.isEmpty else {
      return AttributedString(entry.content)
    }

    var result = AttributedString(entry.content)

    // Highlight each search term
    for term in searchTerms {
      guard !term.isEmpty else { continue }

      // Case-insensitive search
      var searchStart = result.startIndex
      while let range = result[searchStart...].range(of: term, options: .caseInsensitive) {
        result[range].backgroundColor = .yellow.opacity(0.3)
        searchStart = range.upperBound
      }
    }

    return result
  }
}

// MARK: - Load More Row

struct LoadMoreRow: View {
  enum Direction {
    case earlier
    case later

    var icon: String {
      switch self {
      case .earlier: return "arrow.up"
      case .later: return "arrow.down"
      }
    }

    var label: String {
      switch self {
      case .earlier: return "Load 5 earlier"
      case .later: return "Load 5 later"
      }
    }
  }

  let direction: Direction
  let count: Int
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: direction.icon)
          .font(.caption)
          .foregroundStyle(.blue)

        Text(direction.label)
          .font(.caption)
          .foregroundStyle(.blue)

        Text("· \(count) remaining")
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 12)
    }
    .buttonStyle(.plain)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(Color.blue.opacity(0.05))
    )
  }
}

// MARK: - Results Breakdown Helper

extension DeepSearchView {
  /// Formats results count with role breakdown: "47 results (12 user, 35 assistant)"
  @ViewBuilder
  func resultsBreakdown(_ result: ConversationSearchResult) -> some View {
    let userCount = result.hits.filter { $0.role == "user" }.count
    let assistantCount = result.hits.filter { $0.role == "assistant" }.count
    let summaryCount = result.hits.filter { $0.role == "summary" }.count

    if result.cappedResults {
      Text("5000+ results")
        .font(.caption)
        .foregroundStyle(.orange)
    } else {
      HStack(spacing: 4) {
        Text("\(result.totalCount) results")
          .font(.caption)
          .foregroundStyle(.secondary)

        if result.totalCount > 0 {
          Text(roleBreakdownText(user: userCount, assistant: assistantCount, summary: summaryCount))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
      }
    }
  }

  private func roleBreakdownText(user: Int, assistant: Int, summary: Int) -> String {
    var parts: [String] = []
    if user > 0 { parts.append("\(user) user") }
    if assistant > 0 { parts.append("\(assistant) assistant") }
    if summary > 0 { parts.append("\(summary) summary") }

    guard !parts.isEmpty else { return "" }
    return "(\(parts.joined(separator: ", ")))"
  }
}

// MARK: - Search Info Popover

struct SearchInfoPopover: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Search Scope")
        .font(.headline)

      VStack(alignment: .leading, spacing: 6) {
        Text("Searching:")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Label("User prompts", systemImage: "person.fill")
          .font(.caption)
        Label("Assistant responses", systemImage: "sparkles")
          .font(.caption)
        Label("LLM-generated summaries", systemImage: "text.quote")
          .font(.caption)
      }

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        Text("Not searched:")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Label("Tool use / function calls", systemImage: "hammer.fill")
          .font(.caption)
          .foregroundStyle(.tertiary)
        Label("System events", systemImage: "gearshape.fill")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      Divider()

      HStack {
        Text("Scope:")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Text("All projects")
          .font(.caption)
      }
    }
    .padding()
    .frame(width: 220)
  }
}
