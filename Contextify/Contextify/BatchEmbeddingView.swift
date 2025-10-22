import SwiftUI
import ContextifyCore
import GRDB

/// UI for batch embedding generation with progress tracking
struct BatchEmbeddingView: View {
  @State private var isRunning = false
  @State private var progress: EmbeddingOrchestrator.Progress?
  @State private var stats: GenerationStats?
  @State private var error: String?
  @State private var dbStats: (total: Int, embedded: Int, pending: Int)?
  @State private var lengthDistribution: [String: Int]?
  @State private var minLength: Double = 100

  // Hold references safely; build once in init
  private let embeddingService: EmbeddingService
  private let repository: EmbeddingRepository
  private let orchestrator: EmbeddingOrchestrator

  @Environment(\.dismiss) private var dismiss

  init() {
    // Build dependencies once with proper error handling
    let embeddingService = EmbeddingService()
    self.embeddingService = embeddingService

    do {
      let pool = try DatabaseManager.shared.pool
      let repository = EmbeddingRepositoryImpl(db: pool)
      self.repository = repository
      self.orchestrator = EmbeddingOrchestrator(
        embeddingService: embeddingService,
        repository: repository,
        db: pool
      )
    } catch {
      // Fallback stubs so view can render error message in .task
      let memPool = try! DatabasePool(path: ":memory:")
      let fallbackRepo = EmbeddingRepositoryImpl(db: memPool)
      self.repository = fallbackRepo
      self.orchestrator = EmbeddingOrchestrator(
        embeddingService: embeddingService,
        repository: fallbackRepo,
        db: memPool
      )
      // Error will be displayed when loadStats() runs in .task
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header with close button
      HStack {
        Text("Batch Embedding Generation")
          .font(.headline)
        Spacer()
        Button(action: { dismiss() }) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .imageScale(.large)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
      }
      .padding()

      Divider()

      // Scrollable content
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {

      // Content Length Distribution
      if let lengthDistribution = lengthDistribution {
        VStack(alignment: .leading, spacing: 12) {
          Text("Content Length Distribution")
            .font(.subheadline.bold())

          Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
            GridRow {
              Text("Range").font(.caption.bold())
              Text("Count").font(.caption.bold())
              Text("% of Total").font(.caption.bold())
            }
            .foregroundStyle(.secondary)

            ForEach(["<50", "50-99", "100-199", "200-499", "500+"], id: \.self) { key in
              let count = lengthDistribution[key] ?? 0
              let total = lengthDistribution.values.reduce(0, +)
              let percentage = total > 0 ? Double(count) / Double(total) * 100 : 0
              let isFiltered = (key == "<50" || key == "50-99") && minLength >= 100

              GridRow {
                Text(key + " chars")
                  .font(.caption.monospaced())
                  .foregroundStyle(isFiltered ? .secondary : .primary)
                  .strikethrough(isFiltered)
                Text("\(count)")
                  .font(.caption.monospaced())
                  .foregroundStyle(isFiltered ? .secondary : .primary)
                Text(String(format: "%.1f%%", percentage))
                  .font(.caption.monospaced())
                  .foregroundStyle(isFiltered ? .secondary : .primary)
              }
            }
          }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
      }

      // Minimum Length Filter
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Minimum Content Length")
            .font(.subheadline.bold())
          Spacer()
          Text("\(Int(minLength)) characters")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }

        Slider(value: $minLength, in: 50...500, step: 50) {
          Text("Min Length")
        }
        .disabled(isRunning)
        .onChange(of: minLength) { _, _ in
          Task { await loadStats() }
        }

        HStack(spacing: 4) {
          Text("⚠️")
            .font(.caption)
          Text("Only entries with ≥\(Int(minLength)) chars will be embedded")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding()
      .background(Color.blue.opacity(0.1))
      .cornerRadius(8)

      // Database stats
      if let dbStats = dbStats {
        VStack(alignment: .leading, spacing: 8) {
          Text("Embedding Status")
            .font(.subheadline.bold())

          HStack(spacing: 16) {
            statBox("Eligible", value: "\(dbStats.total)")
            statBox("Embedded", value: "\(dbStats.embedded)", color: .green)
            statBox("Pending", value: "\(dbStats.pending)", color: .orange)
          }

          if dbStats.embedded > 0 {
            let percentage = Double(dbStats.embedded) / Double(dbStats.total) * 100
            Text("Coverage: \(String(format: "%.1f", percentage))%")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
      }

      Divider()

      // Progress section
      if let progress = progress {
        VStack(alignment: .leading, spacing: 12) {
          Text("Generating Embeddings")
            .font(.subheadline.bold())

          ProgressView(value: Double(progress.current), total: Double(progress.total)) {
            HStack {
              Text("\(progress.current) / \(progress.total)")
              Spacer()
              Text("\(String(format: "%.1f", progress.percentage))%")
            }
            .font(.caption)
          }

          if let estimate = progress.estimatedSecondsRemaining, estimate > 0 {
            Text("Estimated time remaining: \(formatDuration(estimate))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let entryId = progress.currentEntryId {
            Text("Current: \(entryId.prefix(12))...")
              .font(.caption2)
              .foregroundStyle(.tertiary)
              .monospaced()
          }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
      }

      // Results section
      if let stats = stats {
        VStack(alignment: .leading, spacing: 8) {
          Text("Generation Complete")
            .font(.subheadline.bold())

          Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
              Text("Processed:")
              Text("\(stats.totalProcessed) entries")
                .foregroundStyle(.secondary)
            }
            GridRow {
              Text("Succeeded:")
              Text("\(stats.succeeded)")
                .foregroundStyle(.green)
            }
            if stats.failed > 0 {
              GridRow {
                Text("Failed:")
                Text("\(stats.failed)")
                  .foregroundStyle(.red)
              }
            }
            GridRow {
              Text("Duration:")
              Text("\(String(format: "%.1f", stats.durationSeconds))s")
                .foregroundStyle(.secondary)
            }
            GridRow {
              Text("Rate:")
              Text("\(String(format: "%.1f", stats.entriesPerSecond)) entries/sec")
                .foregroundStyle(.secondary)
            }
            GridRow {
              Text("Success Rate:")
              Text("\(String(format: "%.1f", stats.successRate))%")
                .foregroundStyle(stats.successRate >= 95 ? .green : .orange)
            }
          }
          .font(.caption)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
      }

      // Error display
      if let error = error {
        Text("Error: \(error)")
          .font(.caption)
          .foregroundColor(.red)
          .padding()
          .background(Color.red.opacity(0.1))
          .cornerRadius(8)
      }

        }
        .padding()
      }

      Divider()

      // Action buttons (fixed at bottom)
      HStack {
        Button(action: startBatchGeneration) {
          if isRunning {
            HStack {
              ProgressView()
                .scaleEffect(0.7)
              Text("Generating...")
            }
          } else {
            Text("Generate Embeddings (≥\(Int(minLength)) chars)")
          }
        }
        .disabled(isRunning || (dbStats?.pending ?? 0) == 0)
        .buttonStyle(.borderedProminent)

        Button("Clear All Embeddings") {
          Task { await clearAllEmbeddings() }
        }
        .disabled(isRunning || (dbStats?.embedded ?? 0) == 0)
        .buttonStyle(.bordered)

        Button("Refresh Stats") {
          Task { await loadStats() }
        }
        .disabled(isRunning)
      }
      .padding()
    }
    .frame(width: 600, height: 650)
    .task {
      await loadStats()
    }
  }

  private func statBox(_ label: String, value: String, color: Color = .primary) -> some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.title2.bold())
        .foregroundStyle(color)
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  private func formatDuration(_ seconds: Int) -> String {
    if seconds < 60 {
      return "\(seconds)s"
    } else if seconds < 3600 {
      let mins = seconds / 60
      let secs = seconds % 60
      return "\(mins)m \(secs)s"
    } else {
      let hours = seconds / 3600
      let mins = (seconds % 3600) / 60
      return "\(hours)h \(mins)m"
    }
  }

  private func loadStats() async {
    do {
      dbStats = try await repository.countEmbeddings(
        version: EmbeddingService.currentEmbeddingVersion,
        projectId: nil,
        minLength: Int(minLength)
      )
      lengthDistribution = try await loadLengthDistribution()
    } catch {
      self.error = "Failed to load stats: \(error.localizedDescription)"
    }
  }

  private func loadLengthDistribution() async throws -> [String: Int] {
    let db = try DatabaseManager.shared.pool
    return try await db.read { db in
      var distribution: [String: Int] = [:]

      // Count entries in each range
      distribution["<50"] = try Int.fetchOne(db,
        sql: "SELECT COUNT(*) FROM transcript_entries WHERE length(content) < 50") ?? 0
      distribution["50-99"] = try Int.fetchOne(db,
        sql: "SELECT COUNT(*) FROM transcript_entries WHERE length(content) >= 50 AND length(content) < 100") ?? 0
      distribution["100-199"] = try Int.fetchOne(db,
        sql: "SELECT COUNT(*) FROM transcript_entries WHERE length(content) >= 100 AND length(content) < 200") ?? 0
      distribution["200-499"] = try Int.fetchOne(db,
        sql: "SELECT COUNT(*) FROM transcript_entries WHERE length(content) >= 200 AND length(content) < 500") ?? 0
      distribution["500+"] = try Int.fetchOne(db,
        sql: "SELECT COUNT(*) FROM transcript_entries WHERE length(content) >= 500") ?? 0

      return distribution
    }
  }

  private func startBatchGeneration() {
    Task { @MainActor in
      isRunning = true
      error = nil
      stats = nil
      progress = nil

      do {
        let generatedStats = try await orchestrator.generateEmbeddingsForAllEntries(
          version: 1,
          projectId: nil,
          batchSize: 10,
          minLength: Int(minLength)
        ) { currentProgress in
          Task { @MainActor in
            self.progress = currentProgress
          }
        }

        stats = generatedStats
        await loadStats()

      } catch {
        self.error = error.localizedDescription
      }

      isRunning = false
    }
  }

  private func clearAllEmbeddings() async {
    do {
      let db = try DatabaseManager.shared.pool
      try await db.write { db in
        try db.execute(
          sql: """
            UPDATE transcript_entries
            SET embedding = NULL,
                embedding_version = NULL,
                embedding_generated_at = NULL
            WHERE embedding IS NOT NULL
          """
        )
      }
      await loadStats()
      self.stats = nil
      self.progress = nil
      self.error = nil
    } catch {
      self.error = "Failed to clear embeddings: \(error.localizedDescription)"
    }
  }
}

#Preview {
  BatchEmbeddingView()
}
