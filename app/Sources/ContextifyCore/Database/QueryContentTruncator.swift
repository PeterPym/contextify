import Foundation

public enum QueryContentTruncator {
  public static func truncateUTF8PreservingScalars(_ content: String, maxBytes: Int) -> (truncated: String, didTruncate: Bool, fullSizeBytes: Int) {
    let fullSizeBytes = content.utf8.count
    guard fullSizeBytes > maxBytes else {
      return (content, false, fullSizeBytes)
    }

    let data = Data(content.utf8)
    var end = min(maxBytes, data.count)
    while end > 0 {
      if let truncated = String(data: data.subdata(in: 0..<end), encoding: .utf8) {
        return (truncated, true, fullSizeBytes)
      }
      end -= 1
    }
    return ("", true, fullSizeBytes)
  }
}

