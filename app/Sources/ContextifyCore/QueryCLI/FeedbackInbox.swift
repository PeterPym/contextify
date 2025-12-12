import Foundation

public struct QueryCLIFeedbackContext: Codable, Sendable {
  public let timestamp: String
  public let cliVersion: String
  public let appSchemaVersion: Int
  public let capabilities: [String]
}

public struct QueryCLIFeedbackItem: Codable, Sendable {
  public let id: String
  public let summary: String
  public let intent: String?
  public let gap: String?
  public let workaround: String?
  public let proposal: String?
  public let context: QueryCLIFeedbackContext
}

public struct QueryCLIFeedbackListItem: Codable, Sendable {
  public let id: String
  public let summary: String
  public let timestamp: String
}

public struct QueryCLIFeedbackRecorded: Codable, Sendable {
  public let id: String
  public let path: String
  public let summary: String
}

public struct QueryCLIFeedbackRecordResult: Codable, Sendable {
  public let recorded: QueryCLIFeedbackRecorded
  public let warnings: [String]
}

public enum QueryCLIFeedbackFormat: String, Sendable {
  case md
  case todo
  case json
}

public enum QueryCLIFeedbackError: Error, Sendable {
  case notFound(String)
  case invalidArgs(String)
}

public final class QueryCLIFeedbackInbox: Sendable {
  private let root: URL
  private let now: @Sendable () -> Date
  private let calendar: Calendar

  public init(root: URL, now: @escaping @Sendable () -> Date = Date.init) {
    self.root = root
    self.now = now
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    self.calendar = calendar
  }

  public func record(
    summary: String,
    intent: String?,
    gap: String?,
    workaround: String?,
    proposal: String?,
    cliVersion: String,
    appSchemaVersion: Int,
    capabilities: [String],
    force: Bool = false
  ) throws -> QueryCLIFeedbackRecordResult {
    let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw QueryCLIFeedbackError.invalidArgs("summary is required") }

    try ensureDirectories()
    var warnings: [String] = []
    warnings.append(contentsOf: try checkDuplicateWarnings(summary: trimmed, intent: intent, force: force))
    warnings.append(contentsOf: try checkRateLimitWarnings(force: force))

    let timestamp = iso8601(now())

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    var recorded: QueryCLIFeedbackRecorded?
    var attempts = 0
    while recorded == nil {
      attempts += 1
      if attempts > 10 {
        throw QueryCLIFeedbackError.invalidArgs("Failed to allocate unique feedback id after 10 attempts")
      }

      let id = try nextId()
      let item = QueryCLIFeedbackItem(
        id: id,
        summary: trimmed,
        intent: intent,
        gap: gap,
        workaround: workaround,
        proposal: proposal,
        context: QueryCLIFeedbackContext(
          timestamp: timestamp,
          cliVersion: cliVersion,
          appSchemaVersion: appSchemaVersion,
          capabilities: capabilities
        )
      )

      let data = try encoder.encode(item)

      let destURL = inboxURL(forId: id)
      let tmpURL = inboxDir().appendingPathComponent(".tmp-\(UUID().uuidString).json")
      try data.write(to: tmpURL, options: .atomic)
      do {
        try FileManager.default.moveItem(at: tmpURL, to: destURL)
        recorded = QueryCLIFeedbackRecorded(id: id, path: destURL.path, summary: trimmed)
      } catch {
        try? FileManager.default.removeItem(at: tmpURL)
        continue
      }
    }

    try enforceStorageCap()

    return QueryCLIFeedbackRecordResult(
      recorded: recorded!,
      warnings: warnings
    )
  }

  public func list() throws -> [QueryCLIFeedbackListItem] {
    try ensureDirectories()
    let urls = try FileManager.default.contentsOfDirectory(at: inboxDir(), includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix("fb_") && $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    return try urls.compactMap { url in
      let data = try Data(contentsOf: url)
      let item = try JSONDecoder().decode(QueryCLIFeedbackItem.self, from: data)
      return QueryCLIFeedbackListItem(id: item.id, summary: item.summary, timestamp: item.context.timestamp)
    }
  }

  public func load(id: String) throws -> QueryCLIFeedbackItem {
    let url = inboxURL(forId: id)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw QueryCLIFeedbackError.notFound(id)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(QueryCLIFeedbackItem.self, from: data)
  }

  public func dismiss(id: String) throws {
    try ensureDirectories()
    let src = inboxURL(forId: id)
    guard FileManager.default.fileExists(atPath: src.path) else {
      throw QueryCLIFeedbackError.notFound(id)
    }
    let dest = dismissedDir().appendingPathComponent(src.lastPathComponent)
    try FileManager.default.moveItem(at: src, to: dest)
  }

  public func archive(olderThanDays: Int?) throws -> Int {
    try ensureDirectories()
    let urls = try FileManager.default.contentsOfDirectory(at: inboxDir(), includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix("fb_") && $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    let cutoff: Date?
    if let olderThanDays {
      cutoff = calendar.date(byAdding: .day, value: -olderThanDays, to: now())
    } else {
      cutoff = nil
    }

    var moved = 0
    for url in urls {
      if let cutoff, let date = parseISO8601FromFile(url), date >= cutoff {
        continue
      }
      let dest = archiveDir().appendingPathComponent(url.lastPathComponent)
      try FileManager.default.moveItem(at: url, to: dest)
      moved += 1
    }
    return moved
  }

  public func clearAll() throws -> Int {
    try ensureDirectories()
    let urls = try FileManager.default.contentsOfDirectory(at: inboxDir(), includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix("fb_") && $0.pathExtension == "json" }
    var moved = 0
    for url in urls {
      let dest = clearedDir().appendingPathComponent(url.lastPathComponent)
      try FileManager.default.moveItem(at: url, to: dest)
      moved += 1
    }
    return moved
  }

  public func exportMarkdown(item: QueryCLIFeedbackItem) -> String {
    var lines: [String] = []
    lines.append("# Query CLI Feedback: \(item.id)")
    lines.append("")
    lines.append("- Summary: \(item.summary)")
    if let intent = item.intent { lines.append("- Intent: \(intent)") }
    if let gap = item.gap { lines.append("- Gap: \(gap)") }
    if let workaround = item.workaround { lines.append("- Workaround: \(workaround)") }
    if let proposal = item.proposal { lines.append("- Proposal: \(proposal)") }
    lines.append("")
    lines.append("## Context")
    lines.append("")
    lines.append("- Timestamp: \(item.context.timestamp)")
    lines.append("- CLI Version: \(item.context.cliVersion)")
    lines.append("- App Schema Version: \(item.context.appSchemaVersion)")
    lines.append("- Capabilities: \(item.context.capabilities.joined(separator: ", "))")
    lines.append("")
    return lines.joined(separator: "\n")
  }

  public func exportTodoLine(item: QueryCLIFeedbackItem) -> String {
    let proposal = item.proposal ?? item.summary
    return "- [ ] P2: \(proposal) (feedback: \(item.id))"
  }

  private func ensureDirectories() throws {
    try FileManager.default.createDirectory(at: inboxDir(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: archiveDir(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dismissedDir(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: clearedDir(), withIntermediateDirectories: true)
  }

  private func inboxDir() -> URL {
    root.appendingPathComponent("feedback", isDirectory: true)
  }

  private func archiveDir() -> URL {
    root.appendingPathComponent("feedback/archive", isDirectory: true)
  }

  private func dismissedDir() -> URL {
    root.appendingPathComponent("feedback/archive/dismissed", isDirectory: true)
  }

  private func clearedDir() -> URL {
    root.appendingPathComponent("feedback/archive/cleared", isDirectory: true)
  }

  private func inboxURL(forId id: String) -> URL {
    inboxDir().appendingPathComponent("\(id).json")
  }

  private func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }

  private func parseISO8601FromFile(_ url: URL) -> Date? {
    guard let data = try? Data(contentsOf: url),
          let item = try? JSONDecoder().decode(QueryCLIFeedbackItem.self, from: data) else {
      return nil
    }
    return parseISO8601(item.context.timestamp)
  }

  private func nextId() throws -> String {
    let date = now()
    let ymd = String(format: "%04d%02d%02d",
                     calendar.component(.year, from: date),
                     calendar.component(.month, from: date),
                     calendar.component(.day, from: date))

    let files = (try? FileManager.default.contentsOfDirectory(at: inboxDir(), includingPropertiesForKeys: nil)) ?? []
    let prefix = "fb_\(ymd)_"
    let existing = files.compactMap { url -> Int? in
      let name = url.deletingPathExtension().lastPathComponent
      guard name.hasPrefix(prefix) else { return nil }
      let suffix = String(name.dropFirst(prefix.count))
      return Int(suffix)
    }
    let next = (existing.max() ?? 0) + 1
    return String(format: "fb_%@_%03d", ymd, next)
  }

  private func checkDuplicateWarnings(summary: String, intent: String?, force: Bool) throws -> [String] {
    guard !force else { return [] }
    let key = (summary + "|" + (intent ?? "")).lowercased(with: Locale(identifier: "en_US_POSIX"))
    let items = try list()
    let recent = items.filter { item in
      guard let date = parseISO8601(item.timestamp) else { return true }
      let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now()) ?? now()
      return date >= sevenDaysAgo
    }
    for item in recent {
      let otherKey = (item.summary + "|" + (intent ?? "")).lowercased(with: Locale(identifier: "en_US_POSIX"))
      if otherKey == key {
        return ["Similar feedback exists (\(item.id)). Use --force to suppress."]
      }
    }
    return []
  }

  private func checkRateLimitWarnings(force: Bool) throws -> [String] {
    guard !force else { return [] }
    let items = try list()
    let oneHourAgo = now().addingTimeInterval(-3600)
    let recentCount = items.filter { item in
      guard let date = parseISO8601(item.timestamp) else { return true }
      return date >= oneHourAgo
    }.count
    if recentCount > 5 {
      return ["\(recentCount) feedback items in the last hour. Consider consolidating. Use --force to suppress."]
    }
    return []
  }

  private func enforceStorageCap() throws {
    let items = try list()
    guard items.count > 100 else { return }
    let overflow = items.count - 100
    for item in items.prefix(overflow) {
      let src = inboxURL(forId: item.id)
      if FileManager.default.fileExists(atPath: src.path) {
        let dest = archiveDir().appendingPathComponent(src.lastPathComponent)
        try? FileManager.default.moveItem(at: src, to: dest)
      }
    }
  }

  private func parseISO8601(_ value: String) -> Date? {
    for formatOptions in [
      ISO8601DateFormatter.Options([.withInternetDateTime, .withFractionalSeconds]),
      ISO8601DateFormatter.Options([.withInternetDateTime]),
    ] {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = formatOptions
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      if let date = formatter.date(from: value) {
        return date
      }
    }
    return nil
  }
}
