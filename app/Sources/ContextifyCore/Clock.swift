import Foundation

/// Protocol for deterministic time in tests. Injectable into repositories for timestamp generation.
public protocol Clock: Sendable {
  func now() -> Date
}

/// System clock that returns current time
public struct SystemClock: Clock {
  public init() {}

  public func now() -> Date {
    Date()
  }
}

/// Fixed clock for testing that always returns the same time
public struct FixedClock: Clock {
  public let fixedDate: Date

  public init(fixedDate: Date) {
    self.fixedDate = fixedDate
  }

  public func now() -> Date {
    fixedDate
  }
}
