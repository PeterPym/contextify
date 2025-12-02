import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "SandboxedWatcher")

/// Watches Claude transcript directory for new project subdirectories in sandboxed builds.
///
/// Uses DispatchSource (kqueue) to watch the Claude projects root directory.
/// When new subdirectories appear, triggers `AppStateOrchestrator.refreshProjects()`.
///
/// Note: Only watches Claude (flat structure). Codex uses a nested date-based structure
/// that requires polling instead of directory watching.
@MainActor
public final class SandboxedDirectoryWatcher {
  private let accessProvider: TranscriptAccessProvider
  // nonisolated(unsafe) required for access in deinit and DispatchSource handlers
  nonisolated(unsafe) private var claudeWatchSource: DispatchSourceFileSystemObject?
  nonisolated(unsafe) private var claudeFileDescriptor: Int32 = -1

  // Debounce state
  private var debounceTask: Task<Void, Never>?
  private let debounceInterval: TimeInterval = 0.25  // 250ms

  public init(accessProvider: TranscriptAccessProvider) {
    self.accessProvider = accessProvider
  }

  deinit {
    // Clean up in deinit (nonisolated context)
    claudeWatchSource?.cancel()
    // Cancel handler will close the file descriptor
  }

  /// Start watching Claude transcript directory for new projects.
  /// Call after initial discovery completes and access provider is configured.
  public func startWatching() {
    log.info("[SANDBOX-WATCH] Starting Claude directory watcher...")

    // Get the root URL while access is active, then set up watcher
    let rootURL: URL?
    do {
      rootURL = try accessProvider.withAccess(for: TranscriptProviderID.claude) { url in
        return url
      }
    } catch {
      log.error("[SANDBOX-WATCH] Cannot access Claude directory: \(error.localizedDescription, privacy: .public)")
      NotificationCenter.default.post(
        name: .sandboxAccessRevoked,
        object: TranscriptProviderID.claude
      )
      return
    }

    guard let rootURL else {
      log.error("[SANDBOX-WATCH] Claude root URL is nil")
      return
    }

    // Set up the watcher (file descriptor opened during withAccess scope stays valid)
    watchDirectory(rootURL)
    log.info("[SANDBOX-WATCH] Claude directory watcher started successfully")
  }

  /// Stop watching and clean up resources.
  public func stopWatching() {
    log.info("[SANDBOX-WATCH] Stopping Claude directory watcher")
    debounceTask?.cancel()
    debounceTask = nil

    claudeWatchSource?.cancel()
    claudeWatchSource = nil
    // File descriptor is closed by the cancel handler
  }

  // MARK: - Private

  private func watchDirectory(_ url: URL) {
    let fd = open(url.path, O_EVTONLY)
    guard fd >= 0 else {
      log.error("[SANDBOX-WATCH] Failed to open directory for watching: \(url.path, privacy: .public)")
      return
    }

    claudeFileDescriptor = fd

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .delete, .rename],  // .write catches new entries
      queue: .main
    )

    source.setEventHandler { [weak self] in
      guard let self else { return }
      log.info("[SANDBOX-WATCH] Directory change detected in Claude projects root")
      self.scheduleRefresh()
    }

    source.setCancelHandler {
      close(fd)
      log.debug("[SANDBOX-WATCH] Closed file descriptor for Claude directory")
    }

    source.resume()
    claudeWatchSource = source

    log.info("[SANDBOX-WATCH] Watching directory: \(url.path, privacy: .public)")
  }

  /// Debounced refresh - coalesces rapid directory events into a single refresh.
  private func scheduleRefresh() {
    debounceTask?.cancel()
    debounceTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: UInt64(self?.debounceInterval ?? 0.25 * 1_000_000_000))
        guard !Task.isCancelled else { return }
        log.info("[SANDBOX-WATCH] Triggering refreshProjects() after debounce")
        await AppStateOrchestrator.shared.refreshProjects()
      } catch {
        // Task was cancelled, don't refresh
      }
    }
  }
}

// MARK: - Notifications

extension Notification.Name {
  /// Posted when sandbox access to transcript directories is revoked or unavailable.
  /// Object contains the provider ID (e.g., TranscriptProviderID.claude).
  public static let sandboxAccessRevoked = Notification.Name("contextify.sandboxAccessRevoked")
}
