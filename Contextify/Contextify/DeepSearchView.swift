import SwiftUI
import OSLog
import ContextifyCore

private let log = Logger(subsystem: "dev.contextify", category: "DeepSearchView")

/// Deep Search window content with split-view layout
struct DeepSearchView: View {
  @Environment(DeepSearchViewModel.self) private var viewModel

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()

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
  }

  // MARK: - Toolbar

  private var toolbar: some View {
    HStack(spacing: 12) {
      Text(viewModel.projectName)
        .font(.headline)
        .foregroundStyle(.secondary)

      Spacer()

      // Search field
      HStack(spacing: 4) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)

        TextField("Search messages...", text: Binding(
          get: { viewModel.query },
          set: { viewModel.query = $0 }
        ))
        .textFieldStyle(.plain)
        .onSubmit {
          viewModel.search()
        }

        if !viewModel.query.isEmpty {
          Button {
            viewModel.query = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(Color(nsColor: .textBackgroundColor))
      )
      .frame(width: 250)

      if viewModel.isSearching {
        ProgressView()
          .scaleEffect(0.7)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  // MARK: - Results List

  private func resultsList(_ result: ConversationSearchResult) -> some View {
    VStack(spacing: 0) {
      // Results header
      HStack {
        if result.cappedResults {
          Text("5000+ results")
            .font(.caption)
            .foregroundStyle(.orange)
        } else {
          Text("\(result.totalCount) results")
            .font(.caption)
            .foregroundStyle(.secondary)
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
          .onAppear {
            // Scroll to selected hit if any
            if let hitId = viewModel.selectedHitId {
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
          .foregroundStyle(.contextifyBlue)
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

  private var provider: TimelineSourceContext.Provider {
    TimelineSourceContext.Provider(rawValue: entry.provider) ?? .other
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      // Use person icon for user, provider icon for assistant
      if entry.kind == "user" {
        Image(systemName: "person.fill")
          .foregroundStyle(.contextifyBlue)
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
        .fill(isHighlighted ? Color.contextifyYellow.opacity(0.15) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(isHighlighted ? Color.contextifyYellow.opacity(0.5) : Color.clear, lineWidth: 1.5)
    )
  }
}
