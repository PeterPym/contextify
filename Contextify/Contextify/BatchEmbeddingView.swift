import SwiftUI
import ContextifyCore

/// UI for batch embedding generation with progress tracking
struct BatchEmbeddingView: View {
  @State private var isRunning = false
  @State private var progress: EmbeddingOrchestrator.Progress?
  @State private var stats: GenerationStats?
  @State private var error: String?
  @State private var dbStats: (total: Int, embedded: Int, pending: Int)?

  private let embeddingService = EmbeddingService()
  private nonisolated var repository: EmbeddingRepository {
    EmbeddingRepositoryImpl(db: try! DatabaseManager.shared.pool)
  }
  private nonisolated var orchestrator: EmbeddingOrchestrator {
    EmbeddingOrchestrator(
      embeddingService: embeddingService,
      repository: repository,
      db: try! DatabaseManager.shared.pool
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Batch Embedding Generation")
        .font(.headline)

      // Database stats
      if let dbStats = dbStats {
        VStack(alignment: .leading, spacing: 8) {
          Text("Database Status")
            .font(.subheadline.bold())

          HStack(spacing: 16) {
            statBox("Total Entries", value: "\(dbStats.total)")
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

      Spacer()

      // Action buttons
      HStack {
        Button(action: startBatchGeneration) {
          if isRunning {
            HStack {
              ProgressView()
                .scaleEffect(0.7)
              Text("Generating...")
            }
          } else {
            Text("Generate Embeddings for All Entries")
          }
        }
        .disabled(isRunning || (dbStats?.pending ?? 0) == 0)
        .buttonStyle(.borderedProminent)

        Button("Refresh Stats") {
          Task { await loadStats() }
        }
        .disabled(isRunning)
      }
    }
    .padding()
    .frame(width: 600, height: 500)
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
      dbStats = try await repository.countEmbeddings(projectId: nil)
    } catch {
      self.error = "Failed to load stats: \(error.localizedDescription)"
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
          batchSize: 10
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
}

#Preview {
  BatchEmbeddingView()
}
