import Foundation

/// Time unit conversion helpers to enforce consistent millisecond/second usage
public enum TimeUnits {
  /// Convert seconds to milliseconds
  @inline(__always)
  public static func msFromSeconds(_ sec: Int) -> Int64 {
    Int64(sec) * 1000
  }

  /// Convert milliseconds to seconds
  @inline(__always)
  public static func secondsFromMs(_ ms: Int64) -> Int {
    Int(ms / 1000)
  }

  /// Get current time in milliseconds (Unix epoch)
  @inline(__always)
  public static func nowMs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  /// Get current time in seconds (Unix epoch)
  @inline(__always)
  public static func nowSec() -> Int {
    Int(Date().timeIntervalSince1970)
  }
}
