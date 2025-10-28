import Foundation

/// Centralized ISO8601 timestamp formatting for Contextify
///
/// **Critical:** All timestamps stored in the database MUST use this formatter
/// to ensure lexicographic string comparisons work correctly for date queries.
///
/// **Format:** ISO8601 with fractional seconds, UTC timezone (Z suffix)
/// Example: "2025-10-27T22:15:30.123Z"
///
/// **Usage:**
/// ```swift
/// // Writing timestamps
/// let timestamp = ISO8601Z.string(from: Date())
///
/// // Reading timestamps
/// let date = ISO8601Z.date(from: "2025-10-27T22:15:30.123Z")
/// ```
///
/// **Why centralized?**
/// - Database queries compare timestamps as strings (e.g., `created_at > last_viewed_at`)
/// - Different formatters (with/without timezone, fractional seconds) break comparisons
/// - Single source of truth ensures consistency across codebase
public enum ISO8601Z {

    /// Shared ISO8601 formatter with strict configuration
    /// - UTC timezone (no offset)
    /// - Fractional seconds (milliseconds)
    /// - Internet DateTime format (YYYY-MM-DDTHH:MM:SS.sssZ)
    ///
    /// Note: ISO8601DateFormatter is immutable after creation, making this safe for concurrent access
    nonisolated(unsafe) public static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Convert Date to ISO8601Z string
    /// - Parameter date: Date to format
    /// - Returns: ISO8601Z string (e.g., "2025-10-27T22:15:30.123Z")
    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// Parse ISO8601Z string to Date
    /// - Parameter string: ISO8601Z timestamp string
    /// - Returns: Date if parsing succeeds, nil otherwise
    public static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}
