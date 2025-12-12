import Foundation

public struct QueryTimeRange: Sendable, Equatable {
  public var sinceTimestamp: Int?
  public var untilTimestamp: Int?

  public init(sinceTimestamp: Int? = nil, untilTimestamp: Int? = nil) {
    self.sinceTimestamp = sinceTimestamp
    self.untilTimestamp = untilTimestamp
  }
}

public enum QueryTimeParseError: Error {
  case invalidValue(String)
}

public enum QueryTimeParser {
  public static func parseSinceUntil(
    since: String?,
    until: String?,
    days: Int?,
    now: Date = Date()
  ) throws -> QueryTimeRange {
    if let days {
      guard days >= 0 else { throw QueryTimeParseError.invalidValue("--days must be >= 0") }
    }
    if days != nil && (since != nil || until != nil) {
      throw QueryTimeParseError.invalidValue("Use either --days or --since/--until, not both")
    }

    let sinceTs: Int?
    let untilTs: Int?
    if let days {
      let sinceDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: now) ?? now
      sinceTs = Int(sinceDate.timeIntervalSince1970)
      untilTs = nil
    } else {
      sinceTs = try parseTimestamp(since)
      untilTs = try parseTimestamp(until)
    }

    if let sinceTs, let untilTs, sinceTs > untilTs {
      throw QueryTimeParseError.invalidValue("--since must be <= --until")
    }

    return QueryTimeRange(sinceTimestamp: sinceTs, untilTimestamp: untilTs)
  }

  public static func parseTimestamp(_ value: String?) throws -> Int? {
    guard let value else { return nil }
    if let ts = Int(value) { return ts }

    for formatOptions in [
      ISO8601DateFormatter.Options([.withInternetDateTime, .withFractionalSeconds]),
      ISO8601DateFormatter.Options([.withInternetDateTime]),
    ] {
      let isoFormatter = ISO8601DateFormatter()
      isoFormatter.formatOptions = formatOptions
      isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
      if let date = isoFormatter.date(from: value) {
        return Int(date.timeIntervalSince1970)
      }
    }

    let dateOnly = DateFormatter()
    dateOnly.calendar = Calendar(identifier: .gregorian)
    dateOnly.locale = Locale(identifier: "en_US_POSIX")
    dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
    dateOnly.dateFormat = "yyyy-MM-dd"
    if let date = dateOnly.date(from: value) {
      return Int(date.timeIntervalSince1970)
    }

    throw QueryTimeParseError.invalidValue("Invalid timestamp: \(value)")
  }
}
