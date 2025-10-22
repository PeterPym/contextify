import SwiftUI
import ContextifyCore

/// Test view for verifying EmbeddingService functionality
struct EmbeddingTestView: View {
  @State private var testText = "Hello world, this is a test of semantic embeddings!"
  @State private var isGenerating = false
  @State private var result: String = ""
  @State private var error: String? = nil

  private let embeddingService = EmbeddingService()

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Embedding Service Test")
        .font(.headline)

      TextField("Test text:", text: $testText, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(3...6)

      Button(action: testEmbedding) {
        if isGenerating {
          ProgressView()
            .scaleEffect(0.7)
            .frame(width: 16, height: 16)
        } else {
          Text("Generate Embedding")
        }
      }
      .disabled(isGenerating || testText.isEmpty)

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
        .frame(maxHeight: 200)
      }
    }
    .padding()
    .frame(width: 500)
  }

  private func testEmbedding() {
    Task { @MainActor in
      isGenerating = true
      error = nil
      result = ""

      do {
        let vector = try await embeddingService.generateEmbedding(for: testText)

        let stats = """
          ✅ Success!
          Dimension: \(vector.count)
          First 10 values:
          \(vector.prefix(10).map { String(format: "%.4f", $0) }.joined(separator: ", "))

          Min: \(String(format: "%.4f", vector.min() ?? 0))
          Max: \(String(format: "%.4f", vector.max() ?? 0))
          Avg: \(String(format: "%.4f", vector.reduce(0, +) / Float(vector.count)))
          """
        result = stats
      } catch {
        self.error = error.localizedDescription
      }

      isGenerating = false
    }
  }
}

#Preview {
  EmbeddingTestView()
}
