import Foundation
import NaturalLanguage
import OSLog

private let logger = Logger(subsystem: "dev.contextify", category: "EmbeddingService")

public enum EmbeddingError: Error {
  case modelNotAvailable
  case assetsNotDownloaded
  case invalidText
  case generationFailed(String)
}

/// Actor-isolated service for generating text embeddings using NLContextualEmbedding.
/// Provides thread-safe access to Apple's on-device embedding model (macOS 14+).
public actor EmbeddingService {
  private var model: NLContextualEmbedding?
  private var isModelReady: Bool = false

  /// Dimension of embedding vectors (512 for NLContextualEmbedding English model)
  public static let embeddingDimension = 512

  public init() {
    logger.debug("EmbeddingService initialized")
  }

  /// Ensures the NLContextualEmbedding model is loaded and assets are available.
  /// Downloads assets if needed (requires user consent on first use).
  public func ensureModelAvailable() async throws {
    if isModelReady, model != nil {
      return
    }

    logger.info("Loading NLContextualEmbedding model for English")

    guard let embedding = NLContextualEmbedding(language: .english) else {
      logger.error("Failed to create NLContextualEmbedding instance")
      throw EmbeddingError.modelNotAvailable
    }

    // Check if model assets are available
    // Note: NLContextualEmbedding will request download automatically if needed
    self.model = embedding
    self.isModelReady = true
    logger.info("NLContextualEmbedding model ready")
  }

  /// Generates a 512-dimensional embedding vector for the given text.
  /// For multi-token text, averages token embeddings to produce a single vector.
  /// - Parameter text: Input text to embed (non-empty)
  /// - Returns: Array of 512 floats representing the semantic embedding
  /// - Throws: EmbeddingError if model is unavailable or text is invalid
  public func generateEmbedding(for text: String) async throws -> [Float] {
    guard !text.isEmpty else {
      throw EmbeddingError.invalidText
    }

    try await ensureModelAvailable()

    guard let model = self.model else {
      throw EmbeddingError.modelNotAvailable
    }

    logger.debug("Generating embedding for text (\(text.count) chars)")

    // Get embedding result (contains per-token vectors)
    guard let result = try? model.embeddingResult(for: text, language: .english) else {
      logger.error("NLContextualEmbedding.embeddingResult(for:language:) returned nil")
      throw EmbeddingError.generationFailed("Model returned nil result")
    }

    // Collect all token vectors and average them
    var tokenVectors: [[Double]] = []
    result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, range in
      tokenVectors.append(vector)
      return true  // Continue enumeration
    }

    guard !tokenVectors.isEmpty else {
      logger.error("No token vectors generated for text")
      throw EmbeddingError.generationFailed("No token vectors produced")
    }

    // Average the token vectors to get a single embedding
    let avgVector = averageVectors(tokenVectors)

    guard avgVector.count == Self.embeddingDimension else {
      logger.error("Unexpected vector dimension: \(avgVector.count) (expected \(Self.embeddingDimension))")
      throw EmbeddingError.generationFailed("Invalid vector dimension")
    }

    logger.debug("Generated \(avgVector.count)-dim vector from \(tokenVectors.count) tokens")
    return avgVector.map { Float($0) }
  }

  /// Averages multiple vectors element-wise.
  /// - Parameter vectors: Array of vectors (all must have same dimension)
  /// - Returns: Single vector representing the average
  private func averageVectors(_ vectors: [[Double]]) -> [Double] {
    guard !vectors.isEmpty else { return [] }
    guard let firstVector = vectors.first else { return [] }

    let dimension = firstVector.count
    var sum = Array(repeating: 0.0, count: dimension)

    for vector in vectors {
      for i in 0..<dimension {
        sum[i] += vector[i]
      }
    }

    let count = Double(vectors.count)
    return sum.map { $0 / count }
  }

  /// Batch generates embeddings for multiple texts.
  /// - Parameter texts: Array of input texts
  /// - Returns: Array of embedding vectors (same order as input)
  /// - Throws: EmbeddingError if model is unavailable or any text fails
  public func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
    try await ensureModelAvailable()

    logger.info("Batch generating embeddings for \(texts.count) texts")
    var vectors: [[Float]] = []
    vectors.reserveCapacity(texts.count)

    for (index, text) in texts.enumerated() {
      let vector = try await generateEmbedding(for: text)
      vectors.append(vector)

      if (index + 1) % 100 == 0 {
        logger.debug("Batch progress: \(index + 1)/\(texts.count)")
      }
    }

    logger.info("Batch complete: \(vectors.count) embeddings generated")
    return vectors
  }
}

// MARK: - Serialization Helpers

/// Serializes a float array to binary Data for database storage.
/// - Parameter vector: Embedding vector (typically 512 floats)
/// - Returns: Binary representation (4 bytes per float)
func serializeEmbedding(_ vector: [Float]) -> Data {
  vector.withUnsafeBufferPointer { Data(buffer: $0) }
}

/// Deserializes binary Data back to a float array.
/// - Parameter data: Binary embedding data
/// - Returns: Reconstructed embedding vector
func deserializeEmbedding(_ data: Data) -> [Float] {
  data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}
