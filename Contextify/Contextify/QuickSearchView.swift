import SwiftUI
import OSLog
import ContextifyCore

private let log = Logger(subsystem: "dev.contextify", category: "QuickSearchView")

/// Quick Search results view - compact results-only list for HUD
/// Click a result or press Cmd+Enter to open Deep Search Window with context
struct QuickSearchView: View {
  @Environment(QuickSearchViewModel.self) private var viewModel
  @Environment(HUDViewModel.self) private var hudModel

  let projectId: String
  let projectName: String
  let onDeepSearch: (String?) -> Void  // Optional selected hit ID
  let onOpenInTimeline: (String) -> Void

  var body: some View {
    VStack(spacing: 0) {
      searchModeBar
      Divider()

      if let result = viewModel.result {
        resultsList(result)
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
        Text("Results for \"\(query)\"")
          .font(.headline)
          .lineLimit(1)

        if let result = viewModel.result {
          Text("\u{00B7}").foregroundStyle(.secondary)
          if result.cappedResults {
            Text("5000+")
              .foregroundStyle(.orange)
          } else {
            Text("\(result.totalCount)")
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

      Button("Exit") {
        viewModel.exitSearch()
      }
      .buttonStyle(.bordered)
      .controlSize(.small)

      Button {
        onDeepSearch(nil)
      } label: {
        Image(systemName: "arrow.up.right.square")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .help("Open in Deep Search (Cmd+Enter)")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - Results List

  private func resultsList(_ result: ConversationSearchResult) -> some View {
    VStack(spacing: 0) {
      if result.hits.isEmpty {
        noResultsState
      } else {
        List {
          ForEach(result.hits) { hit in
            SearchHitRow(hit: hit, isSelected: false)
              .contentShape(Rectangle())
              .onTapGesture {
                // Open Deep Search Window scrolled to this result
                onDeepSearch(hit.id)
              }
          }
        }
        .listStyle(.plain)

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
        Text("No matches for \"\(query)\"")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var cappedResultsFooter: some View {
    HStack {
      Text("Top 50 of 5000+ results")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Button("See all...") {
        onDeepSearch(nil)
      }
      .font(.caption)
      .buttonStyle(.link)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  // MARK: - Loading/Error States

  private var loadingState: some View {
    VStack(spacing: 8) {
      ProgressView()
      Text("Searching...")
        .font(.caption)
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
        viewModel.search(projectId: projectId)
      }
      .buttonStyle(.bordered)
    }
  }
}

// MARK: - Search Hit Row

struct SearchHitRow: View {
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
          .lineLimit(3)
          .font(.body)

        Text(hit.createdAt, format: .dateTime.month().day().hour().minute())
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
    .background(isSelected ? Color.contextifyYellow.opacity(0.15) : Color.clear)
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

// Colors defined in SharedExtensions.swift
