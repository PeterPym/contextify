import SwiftUI
import ContextifyCore

/// Semantic search interface for conversation history
struct SemanticSearchView: View {
  @State private var searchQuery = ""
  @State private var results: [SearchResult] = []
  @State private var isSearching = false
  @State private var error: String?
  @State private var searchDuration: TimeInterval = 0

  private let embeddingService = EmbeddingService()
  private nonisolated var repository: EmbeddingRepository {
    EmbeddingRepositoryImpl(db: try! DatabaseManager.shared.pool)
  }
  private nonisolated var searchService: SearchService {
    SearchService(
      embeddingService: embeddingService,
      repository: repository,
      db: try! DatabaseManager.shared.pool
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      // Search header
      VStack(alignment: .leading, spacing: 12) {
        Text("Semantic Search")
          .font(.headline)

        HStack {
          TextField("Search your conversation history...", text: $searchQuery)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
              performSearch()
            }

          Button(action: performSearch) {
            if isSearching {
              ProgressView()
                .scaleEffect(0.7)
                .frame(width: 20, height: 20)
            } else {
              Image(systemName: "magnifyingglass")
            }
          }
          .disabled(isSearching || searchQuery.isEmpty)
          .buttonStyle(.borderedProminent)
        }

        if !results.isEmpty {
          HStack {
            Text("\(results.count) results")
              .font(.caption)
              .foregroundStyle(.secondary)

            if searchDuration > 0 {
              Text("•")
                .foregroundStyle(.secondary)
              Text("\(String(format: "%.0f", searchDuration * 1000))ms")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Clear") {
              searchQuery = ""
              results = []
              error = nil
            }
            .font(.caption)
            .buttonStyle(.plain)
          }
        }

        if let error = error {
          Text("Error: \(error)")
            .font(.caption)
            .foregroundColor(.red)
        }
      }
      .padding()

      Divider()

      // Results list
      if results.isEmpty && !isSearching {
        ContentUnavailableView {
          Label("No Results", systemImage: "magnifyingglass")
        } description: {
          Text("Enter a search query to find relevant conversation entries")
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(results) { result in
              SearchResultRow(result: result)
            }
          }
          .padding()
        }
      }
    }
    .frame(width: 800, height: 600)
  }

  private func performSearch() {
    guard !searchQuery.isEmpty else { return }

    Task { @MainActor in
      isSearching = true
      error = nil
      results = []

      let startTime = Date()

      do {
        let searchResults = try await searchService.search(
          query: searchQuery,
          topK: 20,
          projectId: nil
        )

        results = searchResults
        searchDuration = Date().timeIntervalSince(startTime)

      } catch {
        self.error = error.localizedDescription
      }

      isSearching = false
    }
  }
}

struct SearchResultRow: View {
  let result: SearchResult

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        // Similarity score
        Text("\(String(format: "%.0f", result.similarity * 100))%")
          .font(.caption.bold())
          .foregroundStyle(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(similarityColor)
          .cornerRadius(4)

        // Role badge
        Text(result.role)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textCase(.uppercase)

        // Timestamp
        Text(result.timestamp, style: .relative)
          .font(.caption)
          .foregroundStyle(.tertiary)

        Spacer()
      }

      // Content preview
      Text(result.content)
        .font(.body)
        .lineLimit(4)
        .textSelection(.enabled)

      if result.content.count > 200 {
        Text("...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .background(Color.secondary.opacity(0.05))
    .cornerRadius(8)
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
    )
  }

  private var similarityColor: Color {
    if result.similarity >= 0.8 {
      return .green
    } else if result.similarity >= 0.6 {
      return .orange
    } else {
      return .gray
    }
  }
}

#Preview {
  SemanticSearchView()
}
