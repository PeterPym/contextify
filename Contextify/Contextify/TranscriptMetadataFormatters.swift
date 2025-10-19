import Foundation

// MARK: - Metadata Budgets

/// Centralized configuration for LLM context budgets and limits
nonisolated enum MetadataBudgets {
  // LLM token budgets
  static let totalTokens = 4096
  static let outputTokens = 150          // Small JSON: title ≤60, description ≤200, topics
  static let promptOverhead = 900        // Instructions + safety sanitizers + formatting
  static let safetyMargin = 300          // ~7% of 4096, covers Apple safety wrapper variability

  // Per-exchange limits
  static let perExchangeCharLimit = 200  // ~80 tokens per exchange with compressed paths/code

  // Token estimation (auto-tuned by LLM observations)
  nonisolated(unsafe) static var charsPerToken: Double = 2.5  // Default, updated by LLM observations

  // Sampling configuration
  static let bookendCount = 10           // Number of exchanges to take from head/tail
  static let fullStrategyLimit = 25      // Max exchanges before switching to adaptive

  // Remote fallback (feature flag)
  nonisolated(unsafe) static var enableRemoteLargeWindowFallback = false  // Enable 32K+ context remote service for rare overflow cases

  // Computed sampler budget (unified source of truth)
  static var samplerBudget: Int {
    calculateBudget(overhead: nil)
  }

  /// Single unified budget calculation
  /// - Parameter overhead: Calibrated overhead if available, otherwise uses static overhead
  /// - Returns: Available tokens for context
  static func calculateBudget(overhead: Int?) -> Int {
    let effectiveOverhead = overhead ?? promptOverhead
    return totalTokens - outputTokens - effectiveOverhead - safetyMargin
  }
}

// MARK: - Shared Formatters

/// Cached formatters and regex instances to avoid repeated allocations
nonisolated enum Formatters {
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
  static let collapseWhitespace: NSRegularExpression = {
    try! NSRegularExpression(pattern: #"\s+"#, options: [])
  }()

  /// Regex for filename detection
  static let filenamePattern: NSRegularExpression = {
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
