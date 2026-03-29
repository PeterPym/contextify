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
    hours: Int? = nil,
    now: Date = Date()
  ) throws -> QueryTimeRange {
    if let days {
      guard days >= 0 else { throw QueryTimeParseError.invalidValue("--days must be >= 0") }
    }
    if let hours {
      guard hours >= 0 else { throw QueryTimeParseError.invalidValue("--hours must be >= 0") }
    }
    let shorthandCount = [days != nil, hours != nil, since != nil || until != nil].filter { $0 }.count
    if shorthandCount > 1 {
      throw QueryTimeParseError.invalidValue("Use only one of --days, --hours, or --since/--until")
    }

    let sinceTs: Int?
    let untilTs: Int?
    if let days {
      let sinceDate = now.addingTimeInterval(-Double(days) * 86_400)
      sinceTs = Int(sinceDate.timeIntervalSince1970)
      untilTs = nil
    } else if let hours {
      let sinceDate = now.addingTimeInterval(-Double(hours) * 3_600)
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
