import SwiftUI
import ContextifyCore

/// Test view for verifying end-to-end embedding database operations
struct EmbeddingDatabaseTestView: View {
  @State private var isRunning = false
  @State private var result: String = ""
  @State private var error: String? = nil
  @State private var stats: (total: Int, embedded: Int, pending: Int)?

  private let embeddingService = EmbeddingService()

  private nonisolated var repository: EmbeddingRepository {
    EmbeddingRepositoryImpl(db: try! DatabaseManager.shared.pool)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Embedding Database Test")
        .font(.headline)

      if let stats = stats {
        VStack(alignment: .leading, spacing: 4) {
          Text("Database Stats:")
            .font(.subheadline.bold())
          Text("Total entries: \(stats.total)")
          Text("With embeddings: \(stats.embedded)")
          Text("Pending: \(stats.pending)")
        }
        .font(.caption)
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(4)
      }

      Button(action: runEndToEndTest) {
        if isRunning {
          ProgressView()
            .scaleEffect(0.7)
            .frame(width: 16, height: 16)
        } else {
          Text("Run End-to-End Test")
        }
      }
      .disabled(isRunning)

      Button("Refresh Stats") {
        Task { await loadStats() }
      }
      .disabled(isRunning)

      if let error = error {
        Text("Error: \(error)")
          .foregroundColor(.red)
          .font(.caption)
      }

      if !result.isEmpty {
        ScrollView {
          Text(result)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        }
        .frame(maxHeight: 300)
      }
    }
    .padding()
    .frame(width: 600)
    .task {
      await loadStats()
    }
  }

  private func loadStats() async {
    do {
      stats = try await repository.countEmbeddings(projectId: nil)
    } catch {
      self.error = "Stats error: \(error.localizedDescription)"
    }
  }

  private func runEndToEndTest() {
    Task { @MainActor in
      isRunning = true
      error = nil
      result = ""

      do {
        var log = "🧪 Starting End-to-End Test\n\n"

        // Step 1: Get an entry without embedding
        log += "1️⃣ Finding entry without embedding...\n"
        let pendingIds = try await repository.getEntriesWithoutEmbeddings(version: 1, projectId: nil)

        guard let testEntryId = pendingIds.first else {
          log += "❌ No entries without embeddings found\n"
          log += "💡 All entries already have embeddings!\n"
          result = log
          isRunning = false
          await loadStats()
          return
        }

        log += "✅ Found entry: \(testEntryId.prefix(12))...\n\n"

        // Step 2: Generate embedding
        log += "2️⃣ Generating embedding...\n"
        let testText = "This is a test embedding for entry \(testEntryId)"
        let vector = try await embeddingService.generateEmbedding(for: testText)
        log += "✅ Generated \(vector.count)-dim vector\n\n"

        // Step 3: Save to database
        log += "3️⃣ Saving to database...\n"
        try await repository.saveEmbedding(entryId: testEntryId, vector: vector, version: 1)
        log += "✅ Saved embedding\n\n"

        // Step 4: Retrieve from database
        log += "4️⃣ Retrieving from database...\n"
        guard let retrieved = try await repository.getEmbedding(entryId: testEntryId) else {
          log += "❌ Failed to retrieve embedding\n"
          result = log
          isRunning = false
          return
        }
        log += "✅ Retrieved embedding\n\n"

        // Step 5: Verify round-trip
        log += "5️⃣ Verifying round-trip...\n"
        let matches = vector == retrieved
        log += matches ? "✅ PASS: Vectors match!\n\n" : "❌ FAIL: Vectors don't match\n\n"

        // Step 6: Verify it no longer appears in pending
        log += "6️⃣ Checking pending list...\n"
        let newPending = try await repository.getEntriesWithoutEmbeddings(version: 1, projectId: nil)
        let nowPending = newPending.contains(testEntryId)
        log += nowPending ? "❌ FAIL: Still in pending list\n\n" : "✅ PASS: Removed from pending\n\n"

        // Summary
        log += "📊 Test Summary:\n"
        log += "Entry ID: \(testEntryId)\n"
        log += "Vector dimension: \(vector.count)\n"
        log += "Min value: \(String(format: "%.4f", vector.min() ?? 0))\n"
        log += "Max value: \(String(format: "%.4f", vector.max() ?? 0))\n"
        log += "Round-trip: \(matches ? "✅ PASS" : "❌ FAIL")\n"
        log += "Removed from pending: \(!nowPending ? "✅ PASS" : "❌ FAIL")\n"

        if matches && !nowPending {
          log += "\n🎉 ALL TESTS PASSED!"
        }

        result = log
        await loadStats()

      } catch {
        self.error = error.localizedDescription
      }

      isRunning = false
    }
  }
}

#Preview {
  EmbeddingDatabaseTestView()
}
