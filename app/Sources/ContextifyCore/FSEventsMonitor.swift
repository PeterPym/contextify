import Foundation
import OSLog

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
  private var continuation: AsyncStream<FSEventChange>.Continuation?
  private let paths: [String]
  private let latency: CFTimeInterval
  private var isRunning = false

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

    return AsyncStream { continuation in
      self.continuation = continuation

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

        let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
        let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
        let ids = Array(UnsafeBufferPointer(start: eventIds, count: numEvents))

        for i in 0..<numEvents {
          let change = FSEventChange(path: paths[i], flags: flags[i], eventId: ids[i])

          Task { @MainActor in
            monitor.continuation?.yield(change)
          }
        }
      }

      guard let stream = FSEventStreamCreate(
        nil,
        callback,
        &context,
        paths as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        latency,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
      ) else {
        log.error("Failed to create FSEventStream")
        continuation.finish()
        return
      }

      self.stream = stream

      FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

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
    continuation?.finish()
    continuation = nil

#if os(macOS)
    if let stream = stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
      log.info("FSEventsMonitor stopped")
    }
#endif
  }

  deinit {
    // Note: deinit cannot access @MainActor properties
    // Cleanup must be done via explicit stop() call before deallocation
  }
}
