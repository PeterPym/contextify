import Foundation

/// Centralized logging configuration for Contextify
///
/// Controls verbosity of different subsystems to reduce log volume while maintaining
/// diagnostic capability. All flags default to `false` (quiet) to minimize production
/// log noise. Enable specific flags during development/debugging as needed.
///
/// **Usage:**
/// ```swift
/// if LoggingConfig.enableVerboseWatcherLogs {
///     log.debug("[WATCHER-FD-OPEN] fd=\(fd)")
/// }
/// ```
///
/// **See also:** `scripts/logging/README.md` for complete logging documentation
public enum LoggingConfig {

    // MARK: - TranscriptWatcher Logging

    /// Enable verbose file descriptor operations (open, create, resume)
    ///
    /// **Impact:** ~12,000 logs per session (WATCHER-FD-OPEN, WATCHER-SOURCE-CREATE, WATCHER-SOURCE-RESUME)
    ///
    /// **When to enable:**
    /// - Debugging file descriptor leaks
    /// - Investigating watcher lifecycle issues
    /// - Diagnosing "too many open files" errors
    ///
    /// **Affected tags:**
    /// - `[WATCHER-FD-OPEN]` - File descriptor open operations
    /// - `[WATCHER-SOURCE-CREATE]` - DispatchSource creation
    /// - `[WATCHER-SOURCE-RESUME]` - DispatchSource resume
    /// - `[WATCHER-WATCH-START]` - Watch initialization
    /// - `[FSEVENTS-WATCH-START]` - FSEvents monitoring start
    public static let enableVerboseWatcherLogs: Bool = false

    /// Enable verbose watcher recovery operations
    ///
    /// **Impact:** ~6,000 logs per session (WATCHER-RECOVERY-START, WATCHER-RECOVERY-SUCCESS, WATCHER-RECOVERY-SKIP)
    ///
    /// **When to enable:**
    /// - Debugging transcript recovery after errors
    /// - Investigating why transcripts aren't being monitored
    /// - Diagnosing watcher restart behavior
    ///
    /// **Affected tags:**
    /// - `[WATCHER-RECOVERY-START]` - Recovery attempt initiated
    /// - `[WATCHER-RECOVERY-SUCCESS]` - Recovery completed successfully
    /// - `[WATCHER-RECOVERY-SKIP]` - Recovery skipped (already watching)
    /// - `[WATCHER-ARM-START]` - Watcher armed and ready
    public static let enableVerboseWatcherRecovery: Bool = false

    /// Enable verbose watcher health checks
    ///
    /// **Impact:** ~3,000 logs per session (ENSURE-WATCHER-CHECK)
    ///
    /// **When to enable:**
    /// - Debugging why watchers aren't being created
    /// - Investigating polling behavior
    /// - Diagnosing watcher liveness issues
    ///
    /// **Affected tags:**
    /// - `[ENSURE-WATCHER-CHECK]` - Watcher health check polling
    /// - `[ENSURE-WATCHER-START]` - Ensuring watcher exists
    /// - `[ENSURE-WATCHER-DONE]` - Watcher verification complete
    public static let enableVerboseWatcherHealthChecks: Bool = false

    // MARK: - TranscriptOrchestrator Logging

    /// Enable verbose project discovery operations
    ///
    /// **Impact:** ~500 logs per session (Found existing project, project queries)
    ///
    /// **When to enable:**
    /// - Debugging project discovery
    /// - Investigating duplicate project creation
    /// - Diagnosing project identity issues
    ///
    /// **Affected logs:**
    /// - "Found existing project" messages
    /// - Project lookup queries
    /// - Project canonicalization operations
    public static let enableVerboseProjectDiscovery: Bool = false

    // MARK: - Fast Path Logging

    /// Enable verbose fast path ingestion operations
    ///
    /// **Impact:** ~1,000 logs per session (FAST-PATH-*, JIT-INGEST)
    ///
    /// **When to enable:**
    /// - Debugging fast path vs full hoover behavior
    /// - Investigating timeline update delays
    /// - Diagnosing incremental ingestion issues
    ///
    /// **Affected tags:**
    /// - `[FAST-PATH-FILTER]` - Fast path filtering operations
    /// - `[FAST-PATH-ENTRY]` - Entry-level fast path processing
    /// - `[JIT-INGEST]` - Just-in-time ingestion
    public static let enableVerboseFastPath: Bool = false

    // MARK: - Timeline/UI Logging

    /// Enable verbose timeline UI updates
    ///
    /// **Impact:** ~500 logs per session (ROW-APPEAR, UIOPT-*)
    ///
    /// **When to enable:**
    /// - Debugging timeline rendering performance
    /// - Investigating UI update delays
    /// - Diagnosing view lifecycle issues
    ///
    /// **Affected tags:**
    /// - `[ROW-APPEAR]` - Timeline row appearance
    /// - `[UIOPT-*]` - UI optimization traces
    /// - `[TIMELINE-REFRESH-PROGRESS]` - Timeline refresh updates
    public static let enableVerboseTimelineUI: Bool = false
}
