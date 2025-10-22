import SwiftUI
import ContextifyCore

/// Semantic search interface for conversation history
struct SemanticSearchView: View {
  @Environment(HUDViewModel.self) private var hudModel
  @State private var searchQuery = ""
  @State private var results: [SearchResult] = []
  @State private var isSearching = false
  @State private var error: String?
  @State private var searchDuration: TimeInterval = 0
  @State private var searchAllProjects = false
  @State private var useHybridSearch = true

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
  private nonisolated var bm25Service: BM25Service {
    BM25Service(db: try! DatabaseManager.shared.pool)
  }
  private nonisolated var hybridSearchService: HybridSearchService {
    HybridSearchService(
      semanticSearch: searchService,
      bm25Search: bm25Service,
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

        // Search options
        HStack(spacing: 20) {
          // Project filter toggle
          VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $searchAllProjects) {
              Text("Search across projects")
                .font(.caption)
            }
            .toggleStyle(.checkbox)

            // Status label showing current search scope
            HStack(spacing: 4) {
              Image(systemName: searchAllProjects ? "folder.badge.questionmark" : "folder")
                .foregroundStyle(searchAllProjects ? .orange : .blue)
                .imageScale(.small)

              if searchAllProjects {
                Text("Searching all projects")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              } else if let projectRoot = hudModel.projectRootURL {
                Text("Searching current project: \(projectRoot.lastPathComponent)")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              } else {
                Text("Searching current project")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }

          // Hybrid search toggle
          VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $useHybridSearch) {
              Text("Use hybrid search")
                .font(.caption)
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 4) {
              Image(systemName: useHybridSearch ? "arrow.triangle.merge" : "sparkle")
                .foregroundStyle(useHybridSearch ? .purple : .blue)
                .imageScale(.small)

              Text(useHybridSearch ? "Semantic + keyword (RRF)" : "Semantic only")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
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

      // Determine project ID based on checkbox state
      let projectId: String? = searchAllProjects ? nil : hudModel.projectRootURL?.path

      do {
        let searchResults: [SearchResult]

        if useHybridSearch {
          // Use hybrid search (semantic + keyword with RRF)
          searchResults = try await hybridSearchService.search(
            query: searchQuery,
            topK: 20,
            projectId: projectId,
            minLength: 100,
            semanticWeight: 0.5  // Equal weight for semantic and keyword
          )
        } else {
          // Use semantic-only search
          searchResults = try await searchService.search(
            query: searchQuery,
            topK: 20,
            projectId: projectId,
            minLength: 100
          )
        }

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
  @State private var isExpanded = false

  var body: some View {
    Button(action: { isExpanded.toggle() }) {
      VStack(alignment: .leading, spacing: 0) {
        // Header
        HStack {
          // Expand/collapse chevron
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .foregroundStyle(.secondary)
            .imageScale(.small)

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

          // Parent indicator
          if result.parentId != nil {
            Image(systemName: "bubble.left.fill")
              .foregroundStyle(.blue.opacity(0.6))
              .imageScale(.small)
          }
        }
        .padding()

        // Content preview (collapsed)
        if !isExpanded {
          Text(result.content)
            .font(.body)
            .lineLimit(2)
            .padding(.horizontal)
            .padding(.bottom)

        } else {
        // Expanded view with full content and parent
        VStack(alignment: .leading, spacing: 12) {
          // Score breakdown (if hybrid search) - SHOW FIRST
          if let breakdown = result.scoreBreakdown {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Image(systemName: "function")
                  .foregroundStyle(.purple)
                  .imageScale(.small)
                Text("Score Calculation:")
                  .font(.caption.bold())
                  .foregroundStyle(.secondary)
              }

              VStack(alignment: .leading, spacing: 4) {
                if let semRank = breakdown.semanticRank, let semScore = breakdown.semanticScore {
                  HStack(spacing: 4) {
                    Text("Semantic:")
                      .font(.caption2.monospaced())
                      .foregroundStyle(.secondary)
                    Text("rank #\(semRank + 1)")
                      .font(.caption2.monospaced())
                    Text("(similarity: \(String(format: "%.2f", semScore)))")
                      .font(.caption2.monospaced())
                      .foregroundStyle(.tertiary)
                    Text("→")
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                    if let weight = breakdown.semanticWeight {
                      Text("\(String(format: "%.4f", weight / (60.0 + Double(semRank))))")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(.blue)
                    }
                  }
                }

                if let bm25Rank = breakdown.bm25Rank, let bm25Score = breakdown.bm25Score {
                  HStack(spacing: 4) {
                    Text("BM25:")
                      .font(.caption2.monospaced())
                      .foregroundStyle(.secondary)
                    Text("rank #\(bm25Rank + 1)")
                      .font(.caption2.monospaced())
                    Text("(score: \(String(format: "%.2f", bm25Score)))")
                      .font(.caption2.monospaced())
                      .foregroundStyle(.tertiary)
                    Text("→")
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                    if let weight = breakdown.semanticWeight {
                      Text("\(String(format: "%.4f", (1.0 - weight) / (60.0 + Double(bm25Rank))))")
                        .font(.caption2.monospaced().bold())
                        .foregroundStyle(.orange)
                    }
                  }
                } else {
                  HStack(spacing: 4) {
                    Text("BM25:")
                      .font(.caption2.monospaced())
                      .foregroundStyle(.secondary)
                    Text("not in top results")
                      .font(.caption2.monospaced())
                      .foregroundStyle(.tertiary)
                    Text("→")
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                    Text("0.0000")
                      .font(.caption2.monospaced().bold())
                      .foregroundStyle(.gray)
                  }
                }

                Divider()

                if let rrfScore = breakdown.rrfScore {
                  HStack(spacing: 4) {
                    Text("RRF Total:")
                      .font(.caption2.monospaced().bold())
                      .foregroundStyle(.secondary)
                    Text("\(String(format: "%.4f", rrfScore))")
                      .font(.caption2.monospaced().bold())
                      .foregroundStyle(.purple)
                    Text("→ normalized to \(String(format: "%.0f", result.similarity * 100))%")
                      .font(.caption2)
                      .foregroundStyle(.tertiary)
                  }
                }

                if let weight = breakdown.semanticWeight {
                  Text("(semantic weight: \(String(format: "%.0f", weight * 100))%, keyword weight: \(String(format: "%.0f", (1.0 - weight) * 100))%)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
              }
              .padding(8)
              .background(Color.purple.opacity(0.05))
              .cornerRadius(6)
            }
          }

          // Parent message (if exists) - this is the USER's question
          if let parentContent = result.parentContent, let _ = result.parentRole {
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Image(systemName: "person.fill")
                  .foregroundStyle(.blue)
                  .imageScale(.small)
                Text("User:")
                  .font(.caption.bold())
                  .foregroundStyle(.secondary)
              }

              Text(parentContent)
                .font(.body)
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(6)
                .textSelection(.enabled)
            }
          }

          // Full assistant response - this is the MATCHED result
          VStack(alignment: .leading, spacing: 6) {
            if result.parentId != nil {
              HStack {
                Image(systemName: "cpu")
                  .foregroundStyle(.green)
                  .imageScale(.small)
                Text("Assistant:")
                  .font(.caption.bold())
                  .foregroundStyle(.secondary)
              }
            }

            Text(result.content)
              .font(.body)
              .textSelection(.enabled)
          }
        }
        .padding()
      }
      }
      .background(Color.secondary.opacity(0.05))
      .cornerRadius(8)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
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
