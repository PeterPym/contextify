import Foundation

public enum ContextifyQueryShimMarker {
  public static let markerString = "dev.contextify.contextify-query-shim.v1"

  public static func fileLooksLikeOurShim(at url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return false }
    return dataContainsMarker(data)
  }

  public static func dataContainsMarker(_ data: Data) -> Bool {
    guard let markerData = markerString.data(using: .utf8), !markerData.isEmpty else { return false }
    return data.range(of: markerData) != nil
  }
}

