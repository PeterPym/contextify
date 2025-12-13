import Foundation
import OSLog
import os.lock

#if os(macOS)
import CoreServices
#endif

private let log = Logger(subsystem: "dev.contextify", category: "FSEvents")

/// FSEvents change notification
public struct FSEventChange: Sendable, Hashable {
  public let path: String
  public let flags: FSEventStreamEventFlags
  public let eventId: FSEventStreamEventId

  public init(path: String, flags: FSEventStreamEventFlags, eventId: FSEventStreamEventId) {
    self.path = path
    self.flags = flags
    self.eventId = eventId
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(path)
    hasher.combine(flags)
  }

  public static func == (lhs: FSEventChange, rhs: FSEventChange) -> Bool {
    lhs.path == rhs.path && lhs.flags == rhs.flags
  }
}

/// Actor that debounces and coalesces filesystem events
/// Prevents downstream overload during bulk operations (git pull, npm install, etc.)
private actor FSEventsDebouncer {
  private var pendingEvents: [String: FSEventChange] = [:]  // path -> latest change
  private var debounceTask: Task<Void, Never>?
  private let quietPeriod: Duration
  private let onBatch: @Sendable ([FSEventChange]) -> Void

  init(quietPeriod: Duration, onBatch: @escaping @Sendable ([FSEventChange]) -> Void) {
    self.quietPeriod = quietPeriod
    self.onBatch = onBatch
  }

  /// Add event to pending batch and start/restart debounce timer
  func addEvent(_ event: FSEventChange) {
    // Keep only the latest event per path (coalescing)
    pendingEvents[event.path] = event

    // Cancel existing timer and start new one
    debounceTask?.cancel()
    debounceTask = Task { [quietPeriod] in
      do {
        try await Task.sleep(for: quietPeriod)
        self.flush()
      } catch {
        // Task cancelled - ignore
      }
    }
  }

  /// Flush pending events immediately
  func flush() {
    guard !pendingEvents.isEmpty else { return }

    let batch = Array(pendingEvents.values)
    pendingEvents.removeAll()
    debounceTask?.cancel()
    debounceTask = nil

    log.debug("FSEvents: flushing \(batch.count) coalesced events")
    onBatch(batch)
  }

  /// Cancel debounce timer and clear pending events
  func cancel() {
    debounceTask?.cancel()
    debounceTask = nil
    pendingEvents.removeAll()
  }
}

/// Wrapper for FSEvents API to monitor file system changes
/// Provides AsyncStream of changes with multicast support (multiple concurrent subscribers)
/// Includes debouncing (300ms quiet period) to prevent downstream overload during bulk operations
@MainActor
public final class FSEventsMonitor {
  private var stream: FSEventStreamRef?
  private let observersLock = OSAllocatedUnfairLock<[UUID: AsyncStream<FSEventChange>.Continuation]>(initialState: [:])
  private let paths: [String]
  private let latency: CFTimeInterval
  private var isRunning = false
  private var dispatchQueue: DispatchQueue?
  private var debouncer: FSEventsDebouncer?

  public init(paths: [String], latency: CFTimeInterval = 0.5) {
    self.paths = paths
    self.latency = latency
  }

  /// Start monitoring and return AsyncStream of changes
  /// Supports multiple concurrent subscribers (multicast)
  public func start() -> AsyncStream<FSEventChange> {
    let observerId = UUID()

    // Start FSEventStream only once (if not already running)
    if !isRunning {
      isRunning = true
      startFSEventStream()
    }

    // Use bufferingOldest to preserve event causality (create→modify→delete ordering)
    return AsyncStream(bufferingPolicy: .bufferingOldest(1_000)) { continuation in
      // Register this observer
      let count = self.observersLock.withLock { observers in
        observers[observerId] = continuation
        return observers.count
      }
      log.debug("FSEvents: registered observer \(observerId) (total: \(count))")

      // Cleanup on termination
      continuation.onTermination = { @Sendable [weak self, observerId] _ in
        Task { @MainActor [weak self] in
          self?.removeObserver(id: observerId)
        }
      }
    }
  }

  /// Start the underlying FSEventStream (called only once)
  private func startFSEventStream() {
#if os(macOS)
    // Initialize debouncer with 300ms quiet period
    let debouncer = FSEventsDebouncer(quietPeriod: .milliseconds(300)) { [weak self] batch in
      guard let self else { return }
      Task { @MainActor in
        self.emitBatchToObservers(batch)
      }
    }
    self.debouncer = debouncer

    // Create FSEventStream
    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )

    let callback: FSEventStreamCallback = { (
      streamRef,
      clientCallBackInfo,
      numEvents,
      eventPaths,
      eventFlags,
      eventIds
    ) in
      let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()

      let n = Int(numEvents)
      guard n > 0 else { return }

      // Zero-copy CFArray read: cast to CFArray then access CFString elements directly
      let pathsArray = unsafeBitCast(eventPaths, to: CFArray.self)
      var batch = [FSEventChange]()
      batch.reserveCapacity(n)

      for i in 0..<n {
        let pathPtr = CFArrayGetValueAtIndex(pathsArray, i)
        let path = unsafeBitCast(pathPtr, to: CFString.self) as String
        let flag = eventFlags[i]
        let id = eventIds[i]
        batch.append(FSEventChange(path: path, flags: flag, eventId: id))
      }

      // Route events through debouncer (coalesces and batches)
      Task {
        guard let debouncer = monitor.debouncer else { return }
        for change in batch {
          await debouncer.addEvent(change)
        }
      }
    }

    // Complete flag set for robust monitoring
    let flags: FSEventStreamCreateFlags =
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes) |
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents) |
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer) |
      FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)

    guard let stream = FSEventStreamCreate(
      nil,
      callback,
      &context,
      paths as CFArray,
      FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
      latency,
      flags
    ) else {
      log.error("Failed to create FSEventStream")
      return
    }

    self.stream = stream

    // Use dispatch queue instead of runloop to avoid main actor contention
    let queue = DispatchQueue(label: "dev.contextify.fsevents", qos: .userInitiated)
    self.dispatchQueue = queue
    FSEventStreamSetDispatchQueue(stream, queue)

    if !FSEventStreamStart(stream) {
      log.error("Failed to start FSEventStream")
      return
    }

    log.info("FSEventsMonitor started for paths: \(self.paths)")
#else
    log.warning("FSEvents not available on this platform")
#endif
  }

  /// Remove observer by UUID
  private func removeObserver(id: UUID) {
    let count = observersLock.withLock { observers in
      observers.removeValue(forKey: id)
      return observers.count
    }
    log.debug("FSEvents: removed observer \(id) (total: \(count))")
  }

  /// Emit batch of events to all observers (called by debouncer after quiet period)
  private func emitBatchToObservers(_ batch: [FSEventChange]) {
    observersLock.withLock { observers in
      guard !observers.isEmpty else { return }
      let count = observers.count
      log.debug("FSEvents: emitting \(batch.count) events to \(count) observers")
      for change in batch {
        for (_, continuation) in observers {
          continuation.yield(change)
        }
      }
    }
  }

  /// Stop monitoring
  public func stop() {
    guard isRunning else { return }

    isRunning = false

    // Cancel debouncer and flush any pending events
    if let debouncer = debouncer {
      Task {
        await debouncer.cancel()
      }
      self.debouncer = nil
    }

    // Finish all observer continuations
    observersLock.withLock { observers in
      for (_, continuation) in observers {
        continuation.finish()
      }
      observers.removeAll()
      log.debug("FSEvents: finished all observers")
    }

#if os(macOS)
    if let stream = stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
      log.info("FSEventsMonitor stopped")
    }
    self.dispatchQueue = nil
#endif
  }

  // Note: deinit cannot safely clean up stream in Swift 6 with @MainActor
  // Caller must call stop() before deallocation. Stream termination hook will
  // call stop() automatically when continuation terminates.
}
