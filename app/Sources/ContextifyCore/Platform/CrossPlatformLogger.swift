import Foundation

#if canImport(OSLog)
import OSLog
#endif

// MARK: - Cross-Platform Logger

/// A cross-platform logging abstraction that wraps OSLog on Darwin and stderr on Linux.
///
/// ## Platform Implementation
/// - Darwin: Wraps `OSLog.Logger` for system-integrated logging
/// - Linux: Prints to stderr with timestamp and level prefixes
///
/// ## Usage
/// ```swift
/// let log = CrossPlatformLogger(subsystem: "dev.contextify", category: "Parser")
/// log.info("Processing started")
/// log.error("Failed to parse: \(error)")
/// ```
///
/// ## Privacy
/// On Darwin, all string interpolations use `.public` privacy by default for debugging.
/// Linux logging always outputs full content (no privacy filtering).
public struct CrossPlatformLogger: Sendable {
  private let subsystem: String
  private let category: String

  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
  private let _osLogger: Logger
  #endif

  /// Create a logger with the given subsystem and category.
  ///
  /// - Parameters:
  ///   - subsystem: The subsystem identifier (e.g., "dev.contextify").
  ///   - category: The category for this logger (e.g., "Parser", "Database").
  public init(subsystem: String, category: String) {
    self.subsystem = subsystem
    self.category = category
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    self._osLogger = Logger(subsystem: subsystem, category: category)
    #endif
  }

  // MARK: - Log Methods

  /// Log a debug message (verbose, development-only).
  public func debug(_ message: String) {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    _osLogger.debug("\(message, privacy: .public)")
    #else
    logToStderr(level: "DEBUG", message: message)
    #endif
  }

  /// Log an info message (normal operation).
  public func info(_ message: String) {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    _osLogger.info("\(message, privacy: .public)")
    #else
    logToStderr(level: "INFO", message: message)
    #endif
  }

  /// Log a warning message (recoverable issues).
  public func warning(_ message: String) {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    _osLogger.warning("\(message, privacy: .public)")
    #else
    logToStderr(level: "WARN", message: message)
    #endif
  }

  /// Log an error message (failures requiring attention).
  public func error(_ message: String) {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    _osLogger.error("\(message, privacy: .public)")
    #else
    logToStderr(level: "ERROR", message: message)
    #endif
  }

  // MARK: - Linux Implementation

  #if !os(macOS) && !os(iOS) && !os(tvOS) && !os(watchOS) && !os(visionOS)
  private func logToStderr(level: String, message: String) {
    // Use Swift's value-type ISO8601 formatting - no shared mutable state needed.
    // This is thread-safe unlike ISO8601DateFormatter which requires synchronization.
    let timestamp = Date().ISO8601Format(.iso8601WithTimeZone(includingFractionalSeconds: true))
    let output = "[\(timestamp)] [\(level)] [\(category)] \(message)\n"
    FileHandle.standardError.write(Data(output.utf8))
  }
  #endif
}

// MARK: - Convenience Aliases

/// Type alias for existing code that imports OSLog.Logger on Darwin.
/// On Linux, this is the CrossPlatformLogger.
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
// On Darwin, OSLog.Logger is available; use it directly or through CrossPlatformLogger
#else
// On Linux, provide Logger as an alias to CrossPlatformLogger for minimal migration
public typealias Logger = CrossPlatformLogger
#endif
