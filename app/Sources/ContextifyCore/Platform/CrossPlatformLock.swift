import Foundation
#if canImport(os)
import os.lock
#endif

// MARK: - Thread-Local Storage for Reentrancy Detection (Non-Darwin Only)

#if !os(macOS) && !os(iOS) && !os(tvOS) && !os(watchOS) && !os(visionOS)
#if canImport(Glibc)
import Glibc  // Required for pthread_key_* APIs on Linux
#endif
#if DEBUG
/// Thread-local key for reentrancy detection.
/// Stored outside the generic class because Swift doesn't allow static stored properties in generic types.
///
/// ## Limitations (Debug-Only, Best Effort)
/// This reentrancy detection stores a single pointer per thread. It catches:
/// - Direct reentrancy: `lock.withLock { lock.withLock { ... } }` (deadlock)
///
/// It does NOT catch:
/// - Nested acquisition of different locks: `lockA.withLock { lockB.withLock { lockA.withLock { ... } } }` (A->B->A deadlock)
///
/// For full deadlock detection, a per-thread stack/set of held locks would be needed.
/// This is kept simple as a debug-only guardrail for the most common mistake.
private let _crossPlatformLockReentrancyKey: pthread_key_t = {
  var key: pthread_key_t = 0
  pthread_key_create(&key, nil)
  return key
}()
#endif
#endif

// MARK: - Cross-Platform Lock Abstraction

/// A unified lock abstraction that provides consistent API across Darwin and Linux.
///
/// ## Lock Usage Rules (Critical)
/// - **No async work in lock body:** The closure must be synchronous. Never `await` inside `withLock`.
/// - **Keep locked sections small:** Lock, read/write state, unlock. No I/O, no network, no heavy computation.
///   Target: <1ms lock hold time.
/// - **Non-reentrant:** Do not call `withLock` on the same lock instance from within a `withLock` closure.
///   This will deadlock.
/// - **Thread-safe:** Safe to call from any thread.
///
/// ## Platform Implementation
/// - Darwin: Wraps `OSAllocatedUnfairLock<State>` for maximum performance
/// - Linux: Uses `NSLock` + stored `State` property (fallback for non-Darwin platforms)
///
/// ## Example Usage
/// ```swift
/// struct MyState: Sendable {
///   var counter: Int = 0
/// }
///
/// let lock = CrossPlatformLock(initialState: MyState())
///
/// lock.withLock { state in
///   state.counter += 1
/// }
///
/// let value = lock.withLock { state in
///   state.counter
/// }
/// ```
public final class CrossPlatformLock<State: Sendable>: @unchecked Sendable {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
  // Darwin platforms: Use OSAllocatedUnfairLock for maximum performance

  private let _lock: OSAllocatedUnfairLock<State>

  /// Initialize with an initial state value.
  public init(initialState: State) {
    self._lock = OSAllocatedUnfairLock(initialState: initialState)
  }

  /// Execute a closure with exclusive access to the protected state.
  ///
  /// - Parameter body: A closure that receives an `inout` reference to the state.
  /// - Returns: The value returned by the closure.
  /// - Warning: Do not perform async work, I/O, or heavy computation inside the closure.
  @discardableResult
  public func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
    try _lock.withLock(body)
  }

  #else
  // Linux/non-Darwin fallback using NSLock

  private let _nsLock = NSLock()
  private var _state: State

  /// Initialize with an initial state value.
  public init(initialState: State) {
    self._state = initialState
  }

  /// Execute a closure with exclusive access to the protected state.
  ///
  /// - Parameter body: A closure that receives an `inout` reference to the state.
  /// - Returns: The value returned by the closure.
  /// - Warning: Do not perform async work, I/O, or heavy computation inside the closure.
  @discardableResult
  public func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
    #if DEBUG
    // Reentrancy detection using module-level thread-local key
    let lockPtr = Unmanaged.passUnretained(self).toOpaque()
    let existingPtr = pthread_getspecific(_crossPlatformLockReentrancyKey)
    if existingPtr == lockPtr {
      assertionFailure("CrossPlatformLock: Detected reentrant lock acquisition. This will deadlock.")
    }
    pthread_setspecific(_crossPlatformLockReentrancyKey, lockPtr)
    defer { pthread_setspecific(_crossPlatformLockReentrancyKey, nil) }
    #endif

    _nsLock.lock()
    defer { _nsLock.unlock() }
    return try body(&_state)
  }
  #endif
}
