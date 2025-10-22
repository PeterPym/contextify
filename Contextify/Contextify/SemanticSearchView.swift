import SwiftUI
import ContextifyCore
import UniformTypeIdentifiers

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

  // Synthesis state
  @State private var synthesis: SynthesisResult?
  @State private var isSynthesizing = false
  @State private var synthesisError: String?
  @State private var showSources = false

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
  private let synthesisService = SynthesisService()

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

            // Synthesize button
            Button(action: performSynthesis) {
              HStack(spacing: 4) {
                if isSynthesizing {
                  ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                  Text("Analyzing Results...")
                } else {
                  Image(systemName: "sparkles")
                    .imageScale(.small)
                  Text("Summarize These Results")
                }
              }
            }
            .disabled(isSynthesizing)
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .font(.caption)

            Button("Clear") {
              searchQuery = ""
              results = []
              error = nil
              synthesis = nil
              synthesisError = nil
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

      // Main content area: show either synthesis OR results
      if let synthesis = synthesis {
        // Show synthesis (replaces results view)
        VStack(spacing: 0) {
          SynthesisDisplayView(
            synthesis: synthesis,
            showSources: $showSources,
            onCopy: { copySynthesisToClipboard(synthesis) },
            onSave: { saveSynthesisToFile(synthesis) },
            onDismiss: { self.synthesis = nil }
          )
          .padding()
        }
      } else if let synthesisError = synthesisError {
        // Show synthesis error
        VStack {
          Spacer()
          HStack {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
              .imageScale(.large)
            Text("Synthesis error: \(synthesisError)")
              .font(.body)
              .foregroundStyle(.red)
          }
          .padding()
          Spacer()
        }
      } else if results.isEmpty && !isSearching {
        // Show empty state
        ContentUnavailableView {
          Label("No Results", systemImage: "magnifyingglass")
        } description: {
          Text("Enter a search query to find relevant conversation entries")
        }
      } else {
        // Show search results
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
      synthesis = nil
      synthesisError = nil

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

  private func performSynthesis() {
    guard !results.isEmpty else { return }

    Task { @MainActor in
      isSynthesizing = true
      synthesisError = nil

      do {
        let result = try await synthesisService.synthesize(
          query: searchQuery,
          results: results,
          maxResults: 10
        )
        synthesis = result
      } catch {
        synthesisError = error.localizedDescription
      }

      isSynthesizing = false
    }
  }

  private func copySynthesisToClipboard(_ synthesis: SynthesisResult) {
    let markdown = formatSynthesisAsMarkdown(synthesis)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(markdown, forType: .string)
  }

  private func saveSynthesisToFile(_ synthesis: SynthesisResult) {
    let markdown = formatSynthesisAsMarkdown(synthesis)

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    panel.nameFieldStringValue = "synthesis-\(synthesis.query.prefix(30)).md"
    panel.message = "Save synthesis to file"

    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }

      do {
        try markdown.write(to: url, atomically: true, encoding: .utf8)
      } catch {
        self.synthesisError = "Failed to save file: \(error.localizedDescription)"
      }
    }
  }

  private func formatSynthesisAsMarkdown(_ synthesis: SynthesisResult) -> String {
    var markdown = "# Search Query: \(synthesis.query)\n\n"
    markdown += "Generated: \(synthesis.generatedAt.formatted())\n\n"
    markdown += "## Synthesis\n\n"
    markdown += synthesis.summary
    markdown += "\n\n## Sources\n\n"

    for (index, source) in synthesis.sources.enumerated() {
      markdown += "### [\(index + 1)] \(source.role.capitalized) - \(source.timestamp.formatted())\n\n"

      if let parentContent = source.parentContent {
        markdown += "**User:** \(parentContent)\n\n"
      }

      markdown += "**Assistant:** \(source.content)\n\n"
      markdown += "---\n\n"
    }

    return markdown
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

// MARK: - Synthesis Display

struct SynthesisDisplayView: View {
  let synthesis: SynthesisResult
  @Binding var showSources: Bool
  let onCopy: () -> Void
  let onSave: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header
      HStack {
        // Back button
        Button(action: onDismiss) {
          HStack(spacing: 4) {
            Image(systemName: "chevron.left")
              .imageScale(.small)
            Text("Back to Results")
          }
        }
        .buttonStyle(.bordered)
        .font(.caption)

        Spacer()

        Image(systemName: "sparkles")
          .foregroundStyle(.purple)
          .imageScale(.medium)

        Text("AI Synthesis")
          .font(.headline)
          .foregroundStyle(.purple)

        Spacer()

        // Export buttons
        HStack(spacing: 8) {
          Button(action: onCopy) {
            HStack(spacing: 4) {
              Image(systemName: "doc.on.doc")
                .imageScale(.small)
              Text("Copy")
            }
          }
          .buttonStyle(.bordered)
          .font(.caption)

          Button(action: onSave) {
            HStack(spacing: 4) {
              Image(systemName: "square.and.arrow.down")
                .imageScale(.small)
              Text("Save")
            }
          }
          .buttonStyle(.bordered)
          .font(.caption)
        }
      }

      // Meta info
      HStack(spacing: 8) {
        Label("\(synthesis.sources.count) sources", systemImage: "doc.text")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text("•")
          .foregroundStyle(.secondary)

        Text("Generated \(synthesis.generatedAt, style: .relative)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Divider()

      // Synthesis content (full-height, scrollable)
      ScrollView {
        Text(.init(synthesis.summary))  // Parse markdown
          .font(.body)
          .textSelection(.enabled)
          .padding(.vertical, 4)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      Divider()

      // Sources toggle
      Button(action: { showSources.toggle() }) {
        HStack {
          Image(systemName: showSources ? "chevron.down" : "chevron.right")
            .foregroundStyle(.secondary)
            .imageScale(.small)

          Text("View Sources (\(synthesis.sources.count))")
            .font(.caption.bold())

          Spacer()
        }
      }
      .buttonStyle(.plain)

      // Expandable sources
      if showSources {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(Array(synthesis.sources.enumerated()), id: \.element.id) { index, source in
              SourceReferenceRow(source: source, index: index + 1)
            }
          }
        }
      }
    }
  }
}

struct SourceReferenceRow: View {
  let source: SearchResult
  let index: Int
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Header
      Button(action: { isExpanded.toggle() }) {
        HStack {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .foregroundStyle(.secondary)
            .imageScale(.small)

          Text("[\(index)]")
            .font(.caption.monospaced().bold())
            .foregroundStyle(.purple)

          Text(source.role.capitalized)
            .font(.caption)
            .foregroundStyle(.secondary)

          Text("•")
            .font(.caption)
            .foregroundStyle(.tertiary)

          Text(source.timestamp, style: .relative)
            .font(.caption)
            .foregroundStyle(.tertiary)

          Spacer()

          // Similarity badge
          Text("\(String(format: "%.0f", source.similarity * 100))%")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.7))
            .cornerRadius(3)
        }
      }
      .buttonStyle(.plain)

      // Expanded content
      if isExpanded {
        VStack(alignment: .leading, spacing: 8) {
          if let parentContent = source.parentContent {
            VStack(alignment: .leading, spacing: 4) {
              Text("User:")
                .font(.caption.bold())
                .foregroundStyle(.blue)

              Text(parentContent)
                .font(.caption)
                .padding(8)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(4)
            }
          }

          VStack(alignment: .leading, spacing: 4) {
            Text("Assistant:")
              .font(.caption.bold())
              .foregroundStyle(.green)

            Text(source.content)
              .font(.caption)
              .lineLimit(5)
              .padding(8)
              .background(Color.green.opacity(0.05))
              .cornerRadius(4)
          }
        }
        .padding(.leading, 20)
      }
    }
    .padding(8)
    .background(Color.secondary.opacity(0.05))
    .cornerRadius(6)
  }
}

#Preview {
  SemanticSearchView()
}
