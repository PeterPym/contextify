import Foundation
import GRDB

/// Serializes database write operations to prevent SQLITE_BUSY errors
/// under concurrent load. All write operations should go through this actor.
public actor DatabaseWriteQueue {
  private let pool: DatabasePool
  private let maxRetries = 3  // P1-4: Retry transient SQLITE_BUSY
  private let baseDelay: Duration = .milliseconds(50)  // P1-4: 50/100/200ms backoff

  public init(pool: DatabasePool) {
    self.pool = pool
  }

  /// Execute a database write operation with serialization guarantee
  /// P1-4: Retries transient SQLITE_BUSY with exponential backoff
  public func write<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
    var attempt = 0
    while true {
      do {
        return try await pool.write { db in try block(db) }
      } catch let error as DatabaseError where error.resultCode == .SQLITE_BUSY {
        attempt += 1
        guard attempt < maxRetries else { throw error }
        try await Task.sleep(for: baseDelay * (1 << (attempt - 1)))  // 50/100/200ms
      }
    }
  }

  /// Execute a database write operation that returns Void
  /// P1-4: Retries transient SQLITE_BUSY with exponential backoff
  public func write(_ block: @Sendable @escaping (Database) throws -> Void) async throws {
    var attempt = 0
    while true {
      do {
        try await pool.write { db in try block(db) }
        return
      } catch let error as DatabaseError where error.resultCode == .SQLITE_BUSY {
        attempt += 1
        guard attempt < maxRetries else { throw error }
        try await Task.sleep(for: baseDelay * (1 << (attempt - 1)))  // 50/100/200ms
      }
    }
  }
}
