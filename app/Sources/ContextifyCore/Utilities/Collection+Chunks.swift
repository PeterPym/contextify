import Foundation

/// Utilities for batching collections into fixed-size chunks
/// Used by FastPathIngestionCoordinator to batch DB writes
extension Collection {
  /// Splits this collection into chunks of the specified size
  ///
  /// Example:
  /// ```
  /// [1,2,3,4,5].chunks(of: 2) // [[1,2], [3,4], [5]]
  /// ```
  ///
  /// - Parameter size: Maximum number of elements per chunk
  /// - Returns: Array of subsequences, each containing at most `size` elements
  func chunks(of size: Int) -> [SubSequence] {
    guard size > 0 else { return [] }

    var chunks: [SubSequence] = []
    var start = startIndex

    while start < endIndex {
      let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
      chunks.append(self[start..<end])
      start = end
    }

    return chunks
  }
}
