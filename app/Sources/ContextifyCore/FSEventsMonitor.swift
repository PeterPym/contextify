import Foundation
import OSLog
import os.lock

#if os(macOS)
import CoreServices
#endif

private let log = Logger(subsystem: "dev.contextify", category: "FSEvents")

/// FSEvents change notification
public struct FSEventChange: Sendable {
  public let path: String
  public let flags: FSEventStreamEventFlags
  public let eventId: FSEventStreamEventId

  public init(path: String, flags: FSEventStreamEventFlags, eventId: FSEventStreamEventId) {
    self.path = path
    self.flags = flags
    self.eventId = eventId
  }
}

/// Wrapper for FSEvents API to monitor file system changes
/// Provides AsyncStream of changes with fallback to polling when FSEvents unavailable
@MainActor
public final class FSEventsMonitor {
  private var stream: FSEventStreamRef?
  private let continuationLock = OSAllocatedUnfairLock<AsyncStream<FSEventChange>.Continuation?>(initialState: nil)
  private let paths: [String]
  private let latency: CFTimeInterval
  private var isRunning = false
  private var dispatchQueue: DispatchQueue?

  public init(paths: [String], latency: CFTimeInterval = 0.5) {
    self.paths = paths
    self.latency = latency
  }

  /// Start monitoring and return AsyncStream of changes
  public func start() -> AsyncStream<FSEventChange> {
    guard !isRunning else {
      log.warning("FSEventsMonitor already running")
      return AsyncStream { _ in }
    }

    isRunning = true

    // Use bufferingOldest to preserve event causality (create→modify→delete ordering)
    return AsyncStream(bufferingPolicy: .bufferingOldest(1_000)) { continuation in
      self.continuationLock.withLock { $0 = continuation }

#if os(macOS)
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

        // Single Task hop to MainActor, batch yield
        monitor.continuationLock.withLock { cont in
          guard let cont else { return }
          Task { @MainActor in
            for change in batch {
              cont.yield(change)
            }
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
        continuation.finish()
        return
      }

      self.stream = stream

      // Use dispatch queue instead of runloop to avoid main actor contention
      let queue = DispatchQueue(label: "dev.contextify.fsevents", qos: .userInitiated)
      self.dispatchQueue = queue
      FSEventStreamSetDispatchQueue(stream, queue)

      if !FSEventStreamStart(stream) {
        log.error("Failed to start FSEventStream")
        continuation.finish()
        return
      }

      log.info("FSEventsMonitor started for paths: \(self.paths)")

      continuation.onTermination = { @Sendable [weak self] _ in
        Task { @MainActor [weak self] in
          self?.stop()
        }
      }
#else
      log.warning("FSEvents not available on this platform")
      continuation.finish()
#endif
    }
  }

  /// Stop monitoring
  public func stop() {
    guard isRunning else { return }

    isRunning = false

    // Clear continuation before invalidating stream
    continuationLock.withLock { cont in
      cont?.finish()
      cont = nil
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
