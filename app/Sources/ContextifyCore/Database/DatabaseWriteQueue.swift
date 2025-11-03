import Foundation
import GRDB

/// Serializes database write operations to prevent SQLITE_BUSY errors
/// under concurrent load. All write operations should go through this actor.
public actor DatabaseWriteQueue {
  private let pool: DatabasePool

  public init(pool: DatabasePool) {
    self.pool = pool
  }

  /// Execute a database write operation with serialization guarantee
  public func write<T>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
    try await pool.write { db in
      try block(db)
    }
  }

  /// Execute a database write operation that returns Void
  public func write(_ block: @Sendable @escaping (Database) throws -> Void) async throws {
    try await pool.write { db in
      try block(db)
    }
  }
}
