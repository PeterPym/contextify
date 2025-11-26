import SwiftUI
import OSLog
import ContextifyCore

private let log = Logger(subsystem: "dev.contextify", category: "QuickSearchView")

/// Quick Search results view with split layout (results + context preview)
struct QuickSearchView: View {
  @Environment(QuickSearchViewModel.self) private var viewModel
  @Environment(HUDViewModel.self) private var hudModel
  @Environment(\.colorScheme) private var colorScheme

  let projectId: String
  let projectName: String
  let onDeepSearch: () -> Void
  let onOpenInTimeline: (String) -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Search Mode Bar
      searchModeBar
      Divider()

      // Main split view
      if let result = viewModel.result {
        HSplitView {
          resultsList(result)
            .frame(minWidth: 250, idealWidth: 300)

          contextPreview
            .frame(minWidth: 300)
        }
      } else if viewModel.isSearching {
        loadingState
      } else if let error = viewModel.searchError {
        errorState(error)
      }
    }
  }

  // MARK: - Search Mode Bar

  private var searchModeBar: some View {
    HStack(spacing: 8) {
      if case .quickSearch(let query) = viewModel.mode {
        Text("Search results for \"\(query)\"")
          .font(.headline)
          .lineLimit(1)

        Text("\u{00B7}").foregroundStyle(.secondary)

        Text(projectName)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text("\u{00B7}").foregroundStyle(.secondary)

        if let result = viewModel.result {
          if result.cappedResults {
            Text("5000+ matches")
              .foregroundStyle(.orange)
          } else {
            Text("\(result.totalCount) matches")
              .foregroundStyle(.secondary)
          }
        }
      }

      Spacer()

      if !viewModel.isIndexReady {
        HStack(spacing: 4) {
          ProgressView().scaleEffect(0.6)
          Text("Indexing...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Button("Exit Search") {
        viewModel.exitSearch()
      }
      .buttonStyle(.bordered)

      Button {
        onDeepSearch()
      } label: {
        Text("Deep Search...")
        Text("\u{2318}\u{21A9}").foregroundStyle(.secondary)
      }
      .buttonStyle(.bordered)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - Results List

  private func resultsList(_ result: ConversationSearchResult) -> some View {
    VStack(spacing: 0) {
      if result.hits.isEmpty {
        noResultsState
      } else {
        List(selection: Binding(
          get: { viewModel.selectedHitId },
          set: { newValue in
            if let id = newValue {
              viewModel.selectHit(id)
            }
          }
        )) {
          ForEach(result.hits) { hit in
            SearchHitRow(hit: hit, isSelected: hit.id == viewModel.selectedHitId)
              .tag(hit.id)
          }
        }
        .listStyle(.sidebar)

        // Footer if capped
        if result.cappedResults {
          cappedResultsFooter
        }
      }
    }
  }

  private var noResultsState: some View {
    ContentUnavailableView {
      Label("No Results", systemImage: "magnifyingglass")
    } description: {
      if case .quickSearch(let query) = viewModel.mode {
        Text("No matches found for \"\(query)\" in \(projectName)")
      }
    } actions: {
      Button("Search All Projects...") {
        onDeepSearch()
      }
      .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var cappedResultsFooter: some View {
    HStack {
      Text("Showing top 50 of 5000+ results")
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer()

      Button("See more in Deep Search...") {
        onDeepSearch()
      }
      .font(.caption)
      .buttonStyle(.link)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - Context Preview

  @ViewBuilder
  private var contextPreview: some View {
    if let hitId = viewModel.selectedHitId {
      VStack(spacing: 0) {
        // Context header
        contextHeader

        Divider()

        // Context messages
        if viewModel.contextEntries.isEmpty {
          ProgressView("Loading context...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollViewReader { proxy in
            List {
              ForEach(viewModel.contextEntries, id: \.id) { entry in
                ContextEntryRow(
                  entry: entry,
                  isHighlighted: entry.id == hitId
                )
                .id(entry.id)
              }
            }
            .listStyle(.plain)
            .onAppear {
              // Scroll to highlighted entry
              proxy.scrollTo(hitId, anchor: .center)
            }
            .onChange(of: hitId) { _, newId in
              withAnimation {
                proxy.scrollTo(newId, anchor: .center)
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
        Button {
          if let hitId = viewModel.selectedHitId {
            onOpenInTimeline(hitId)
          }
        } label: {
          Label("Open in Timeline", systemImage: "arrow.right.circle")
        }
        .buttonStyle(.borderless)

        Menu {
          Button("Copy Excerpt") {
            viewModel.copyExcerpt(projectName: projectName)
          }
          Button("Copy for AI") {
            viewModel.copyForAI(projectName: projectName)
          }
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 60)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - Loading/Error States

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
      if case .quickSearch(_) = viewModel.mode {
        Button("Retry") {
          viewModel.search(projectId: projectId)
        }
        .buttonStyle(.bordered)
      }
    }
  }
}

// MARK: - Search Hit Row

struct SearchHitRow: View {
  let hit: ConversationSearchHit
  let isSelected: Bool

  private var roleIcon: String {
    hit.role == "user" ? "person.fill" : "sparkles"
  }

  private var roleColor: Color {
    hit.role == "user" ? .blue : .purple
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: roleIcon)
        .foregroundStyle(roleColor)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 4) {
        // Snippet with highlighting (using AttributedString for <mark> tags)
        Text(attributedSnippet)
          .lineLimit(3)
          .font(.body)

        // Timestamp
        Text(hit.createdAt, format: .dateTime.month().day().hour().minute())
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  private var attributedSnippet: AttributedString {
    // Parse <mark> tags and create highlighted attributed string
    var result = AttributedString()
    var remaining = hit.snippet

    while let markStart = remaining.range(of: "<mark>") {
      // Add text before <mark>
      let beforeMark = String(remaining[..<markStart.lowerBound])
      result.append(AttributedString(beforeMark))

      // Find closing </mark>
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

    // Add remaining text
    result.append(AttributedString(remaining))

    return result
  }
}

// MARK: - Context Entry Row

struct ContextEntryRow: View {
  let entry: TranscriptEntry
  let isHighlighted: Bool

  private var roleIcon: String {
    entry.kind == "user" ? "person.fill" : "sparkles"
  }

  private var roleColor: Color {
    entry.kind == "user" ? .blue : .purple
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: roleIcon)
        .foregroundStyle(roleColor)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 4) {
        Text(entry.content)
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
        .fill(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(isHighlighted ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
    )
  }
}
