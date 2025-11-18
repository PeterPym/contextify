import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "FileDescriptorMonitor")

/// Utilities for monitoring file descriptor usage
/// Used to detect file descriptor exhaustion before it causes crashes
public enum FileDescriptorMonitor {
  /// Count currently open file descriptors for this process
  /// Returns nil if unable to read /dev/fd
  public static func countOpenFileDescriptors() -> Int? {
    do {
      let fds = try FileManager.default.contentsOfDirectory(atPath: "/dev/fd")
      let count = fds.count
      log.debug("[FD-COUNT] Current open file descriptors: \(count, privacy: .public)")
      return count
    } catch {
      log.error("[FD-COUNT] Failed to count file descriptors: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /// Log current FD count with warning if above threshold
  /// - Parameter warningThreshold: Log warning if FD count exceeds this value (default 500)
  public static func logFileDescriptorUsage(warningThreshold: Int = 500) {
    guard let count = countOpenFileDescriptors() else { return }

    if count >= warningThreshold {
      log.warning("[FD-WARNING] File descriptor usage HIGH: \(count, privacy: .public) (threshold: \(warningThreshold, privacy: .public))")
    } else {
      log.info("[FD-USAGE] Current file descriptors: \(count, privacy: .public)")
    }
  }

  /// Get the process-wide file descriptor limit (soft limit)
  /// Returns nil if unable to get limit via getrlimit
  public static func getFileDescriptorLimit() -> Int? {
    var limit = rlimit()
    guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else {
      log.error("[FD-LIMIT] Failed to get file descriptor limit via getrlimit")
      return nil
    }
    let softLimit = Int(limit.rlim_cur)
    log.debug("[FD-LIMIT] Process FD soft limit: \(softLimit, privacy: .public)")
    return softLimit
  }

  /// Log comprehensive FD statistics
  public static func logFileDescriptorStats() {
    let count = countOpenFileDescriptors() ?? -1
    let limit = getFileDescriptorLimit() ?? -1

    if count > 0 && limit > 0 {
      let percentage = Double(count) / Double(limit) * 100.0
      log.info("[FD-STATS] FDs: \(count, privacy: .public)/\(limit, privacy: .public) (\(String(format: "%.1f", percentage), privacy: .public)%)")
    } else if count > 0 {
      log.info("[FD-STATS] FDs: \(count, privacy: .public) (limit unknown)")
    }
  }
}
