import Foundation

// MARK: - Metadata Budgets

/// Centralized configuration for LLM context budgets and limits
nonisolated enum MetadataBudgets {
  // LLM token budgets
  static let totalTokens = 4096
  static let outputTokens = 300
  static let promptOverhead = 250

  // Per-exchange limits
  static let perExchangeCharLimit = 300  // ~75 tokens per exchange

  // Sampling configuration
  static let bookendCount = 10           // Number of exchanges to take from head/tail
  static let fullStrategyLimit = 25      // Max exchanges before switching to adaptive

  // Computed sampler budget with safety margin
  static var samplerBudget: Int {
    totalTokens - outputTokens - promptOverhead - 200 // 200 token safety margin
  }
}

// MARK: - Shared Formatters

/// Cached formatters and regex instances to avoid repeated allocations
enum Formatters {
  /// ISO8601 formatter with fractional seconds
  nonisolated(unsafe) static let isoWithFrac: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  /// ISO8601 formatter without fractional seconds
  nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  /// Regex for collapsing whitespace
  nonisolated(unsafe) static let collapseWhitespace: NSRegularExpression = {
    try! NSRegularExpression(pattern: #"\s+"#, options: [])
  }()

  /// Regex for filename detection
  nonisolated(unsafe) static let filenamePattern: NSRegularExpression = {
    let pattern = #"([A-Za-z0-9_.\-/]+\.(swift|md|ts|js|kt|py|rb|java|go|rs|c|cpp|h|hpp|json|yaml|yml|toml|txt|sh))"#
    return try! NSRegularExpression(pattern: pattern, options: [])
  }()
}

// MARK: - Date Parsing/Encoding Utilities

enum ISO8601ms {
  /// Encodes a date to ISO8601 string with fractional seconds
  nonisolated static func encode(_ date: Date) -> String {
    Formatters.isoWithFrac.string(from: date)
  }

  /// Decodes an ISO8601 string to Date, supporting both fractional and non-fractional formats
  nonisolated static func decode(_ string: String) -> Date? {
    Formatters.isoWithFrac.date(from: string) ?? Formatters.iso.date(from: string)
  }
}
