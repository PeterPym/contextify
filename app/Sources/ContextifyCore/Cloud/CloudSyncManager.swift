// SPDX-License-Identifier: MIT
// CloudSyncManager.swift - Orchestrator for cloud push/pull sync operations

import Foundation

#if canImport(OSLog)
import OSLog
private let log = Logger(subsystem: "dev.contextify", category: "CloudSyncManager")
#else
private let log = CrossPlatformLogger(subsystem: "dev.contextify", category: "CloudSyncManager")
#endif

// MARK: - Sync State

/// Represents the current state of the cloud sync manager.
public enum SyncState: Sendable, Equatable {
  case idle
  case syncing
  case error(String)
  case disabled

  public static func == (lhs: SyncState, rhs: SyncState) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle), (.syncing, .syncing), (.disabled, .disabled):
      return true
    case (.error(let a), .error(let b)):
      return a == b
    default:
      return false
    }
  }
}

// MARK: - Result Types

/// Result of a push operation.
public struct PushResult: Sendable {
  /// Number of entries accepted by the server.
  public let entriesPushed: Int
  /// Number of entries skipped as duplicates.
  public let duplicatesSkipped: Int
  /// Server sequence after the push.
  public let serverSequence: Int
}

/// Result of a pull operation.
public struct PullResult: Sendable {
  /// Total entries imported across all pages.
  public let entriesImported: Int
  /// Total entries skipped (already existed locally).
  public let entriesSkipped: Int
  /// Number of pages fetched.
  public let pagesFetched: Int
}

/// Process-wide cached machine ID. Computed once on first access to avoid
/// spawning ioreg on every push. Thread-safe via NSLock.
private final class CachedMachineId: @unchecked Sendable {
  static let shared = CachedMachineId()
  private var _value: String?
  private let _lock = NSLock()

  func get(compute: () -> String) -> String {
    // Fast path: return cached value without computing
    _lock.lock()
    if let v = _value { _lock.unlock(); return v }
    _lock.unlock()

    // Compute outside lock (may spawn ioreg)
    let v = compute()

    // Double-checked: another thread may have computed while we were unlocked
    _lock.lock()
    defer { _lock.unlock() }
    if let existing = _value { return existing }
    _value = v
    return v
  }
}

// MARK: - CloudSyncManager

/// Orchestrator for cloud sync push and pull operations.
///
/// Coordinates between the local database (via `ContextifyQueryService`) and the
/// remote cloud server (via `CloudSyncClient`). Manages configuration persistence,
/// cursor tracking for incremental pulls, and exposes observable state for UI binding.
///
/// Threading model:
/// - Observable state properties are `@MainActor`-isolated for safe SwiftUI binding.
/// - Private `client`/`config` are also `@MainActor`-isolated; sync methods snapshot
///   them at the start via `MainActor.run` to avoid data races.
/// - The class is `@unchecked Sendable` because all mutable state is either
///   `@MainActor`-isolated or stack-local. Do NOT add non-isolated mutable state
///   without adding synchronization.
@Observable
public final class CloudSyncManager: @unchecked Sendable {

  // MARK: - Observable State (MainActor-isolated for SwiftUI)

  /// Timestamp of the last successful sync completion.
  @MainActor public private(set) var lastSyncDate: Date?

  /// Current sync state for UI display.
  @MainActor public private(set) var syncState: SyncState = .idle

  /// Result from the most recent push operation.
  @MainActor public private(set) var lastPushResult: PushResult?

  /// Result from the most recent pull operation.
  @MainActor public private(set) var lastPullResult: PullResult?

  // MARK: - Private State (MainActor-isolated, snapshotted by sync methods)

  @MainActor private var client: CloudSyncClient?
  @MainActor private var config: CloudConfig?

  // MARK: - Initialization

  /// Shared app-level instance. Lives for the entire app lifecycle so sync
  /// survives Settings window open/close.
  @MainActor public static let shared = CloudSyncManager()

  /// Whether auto-sync is currently running.
  @MainActor public private(set) var autoSyncEnabled: Bool = false

  /// Task handle for the auto-sync loop.
  @MainActor private var autoSyncTask: Task<Void, Never>?

  public init() {}

  // MARK: - Configuration

  /// Configure the manager with cloud connection settings.
  ///
  /// Creates a new `CloudSyncClient` using the provided configuration.
  /// Must be called before `sync()`, `push()`, or `pull()`.
  ///
  /// - Parameter config: Cloud configuration with server URL and API key.
  @MainActor
  public func configure(config: CloudConfig) {
    guard let url = URL(string: config.serverURL) else {
      log.error("Invalid server URL in config: \(config.serverURL, privacy: .public)")
      syncState = .error("Invalid server URL")
      return
    }

    self.config = config
    self.client = CloudSyncClient(serverURL: url, apiKey: config.apiKey)

    if config.enabled {
      syncState = .idle
    } else {
      syncState = .disabled
    }

    log.info("Configured cloud sync with server: \(config.serverURL, privacy: .public)")
  }

  /// Set an error message for UI display. Used when sync cannot even start
  /// (e.g., database open failure) and the caller needs to surface the error.
  @MainActor
  public func setErrorForUI(_ message: String) {
    self.syncState = .error(message)
  }

  /// Load configuration from ~/.config/contextify/cloud.json.
  ///
  /// - Returns: The loaded configuration, or nil if the file does not exist or is invalid.
  public func loadConfig() -> CloudConfig? {
    do {
      let config = try CloudConfig.load()
      log.debug("Loaded cloud config from disk")
      return config
    } catch {
      log.debug("No cloud config found: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /// Save configuration to ~/.config/contextify/cloud.json.
  ///
  /// - Parameter config: The configuration to persist.
  public func saveConfig(_ config: CloudConfig) {
    do {
      try config.save()
      log.info("Saved cloud config to disk")
    } catch {
      log.error("Failed to save cloud config: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Sync Operations

  /// Perform a full sync cycle: push local entries, then pull remote entries.
  ///
  /// Updates `syncState` to `.syncing` during the operation and to `.idle` or
  /// `.error` upon completion. Results are available via `lastPushResult` and
  /// `lastPullResult`.
  ///
  /// - Parameter queryService: The query service for database export/import.
  public func sync(using queryService: ContextifyQueryService) async {
    // Atomic check-and-set: skip if already syncing or disabled
    let shouldStart = await MainActor.run { () -> Bool in
      switch self.syncState {
      case .disabled:
        return false
      case .syncing:
        return false
      default:
        self.syncState = .syncing
        return true
      }
    }
    guard shouldStart else {
      let reason = await MainActor.run { () -> String in
        switch self.syncState {
        case .disabled: return "disabled"
        case .syncing: return "already_syncing"
        default: return "unknown"
        }
      }
      log.info("Sync skipped: \(reason, privacy: .public)")
      return
    }
    log.info("Starting full sync cycle")

    do {
      let pushResult = try await push(using: queryService)
      await MainActor.run { self.lastPushResult = pushResult }

      let pullResult = try await pull(using: queryService)
      await MainActor.run {
        self.lastPullResult = pullResult
        self.lastSyncDate = Date()
        self.syncState = .idle
      }

      let pushed = pushResult.entriesPushed
      let pulled = pullResult.entriesImported
      log.info("Sync complete: pushed \(pushed, privacy: .public), pulled \(pulled, privacy: .public)")
    } catch {
      let message = userFriendlyMessage(for: error)
      await MainActor.run { self.syncState = .error(message) }
      log.error("Sync failed: \(message, privacy: .public)")
    }
  }

  /// Push local entries to the cloud server.
  ///
  /// Exports entries from the local database using `queryService.exportForCloudPush()`,
  /// maps them into a `CloudPushPayload`, and sends them via the client.
  ///
  /// - Parameter queryService: The query service for database export.
  /// - Returns: The push result with counts.
  /// - Throws: `CloudSyncError` on failure.
  public func push(using queryService: ContextifyQueryService) async throws -> PushResult {
    // Snapshot MainActor-isolated state to avoid data races
    let (client, config) = await MainActor.run { (self.client, self.config) }
    guard let client, let config else {
      throw CloudSyncError.notConfigured
    }

    log.info("Starting push")

    // Build device info once (cached machine ID avoids repeated ioreg calls)
    let machineId = config.deviceId.isEmpty
      ? CachedMachineId.shared.get(compute: computeMachineId)
      : config.deviceId
    let machineName = config.deviceName.isEmpty
      ? (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
      : config.deviceName
    let device = CloudDeviceInfo(
      machineId: machineId,
      machineName: machineName,
      os: "macos",
      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    )

    // Keyset pagination: loop batches until a short page is returned.
    // Resume from saved cursor to avoid re-uploading the entire database.
    let batchSize = 500
    var afterTimestamp: Int? = config.lastPushTimestamp
    var afterEntryId: String? = config.lastPushEntryId
    var totalAccepted = 0
    var totalDupes = 0
    var lastServerSequence = 0

    if let ts = afterTimestamp {
      log.info("Push: resuming from saved cursor timestamp=\(ts, privacy: .public)")
    }

    while true {
      let exportData = try queryService.exportForCloudPush(
        afterTimestamp: afterTimestamp,
        afterEntryId: afterEntryId,
        limit: batchSize
      )

      if exportData.entries.isEmpty {
        if afterTimestamp == nil {
          log.info("Push: no entries to push")
        }
        break
      }

      let payload = CloudPushPayload(
        idempotencyKey: UUID().uuidString,
        device: device,
        projects: exportData.projects.map { proj in
          CloudPushProject(id: proj.id, name: proj.name, rootPath: proj.rootPath)
        },
        transcripts: exportData.transcripts.map { tx in
          CloudPushTranscript(
            id: tx.id,
            projectId: tx.projectId,
            filePath: tx.filePath,
            provider: tx.provider,
            providerSessionId: tx.providerSessionId,
            lineCount: tx.lineCount,
            createdAt: tx.createdAt,
            updatedAt: tx.updatedAt
          )
        },
        entries: exportData.entries.map { entry in
          CloudPushEntry(
            id: entry.id,
            transcriptId: entry.transcriptId,
            projectId: entry.projectId,
            sessionId: entry.sessionId,
            provider: entry.provider,
            kind: entry.kind,
            timestamp: entry.timestamp,
            content: entry.content,
            contentSha256: entry.contentSha256,
            displayInTimeline: entry.displayInTimeline,
            gitBranch: entry.gitBranch,
            gitCommit: entry.gitCommit,
            cwd: entry.cwd,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt
          )
        }
      )

      log.info("Pushing batch: \(payload.entries.count, privacy: .public) entries")
      let response = try await client.push(payload)

      // Fail closed: do NOT advance cursor when server reports errors.
      // Save progress from prior successful batches, then throw.
      if !response.errors.isEmpty {
        let sample = response.errors.prefix(3).joined(separator: "; ")
        log.error("Push batch returned errors: \(sample, privacy: .public)")
        // Persist cursor at last successful batch boundary before throwing
        if let ts = afterTimestamp, let eid = afterEntryId {
          var checkpoint = config
          checkpoint.lastPushTimestamp = ts
          checkpoint.lastPushEntryId = eid
          await MainActor.run { self.config = checkpoint }
          saveConfig(checkpoint)
          log.info("Push cursor checkpointed before error: timestamp=\(ts, privacy: .public)")
        }
        throw CloudSyncError.partialPushFailure(
          accepted: totalAccepted,
          errors: Array(response.errors.prefix(5))
        )
      }

      totalAccepted += response.accepted
      totalDupes += response.duplicatesSkipped
      lastServerSequence = response.serverSequence

      // Advance keyset cursor from last entry in this batch
      if let last = exportData.entries.last {
        afterTimestamp = last.timestamp
        afterEntryId = last.id
      }

      // Short page means we have exported everything
      if exportData.entries.count < batchSize {
        break
      }
    }

    // Persist the push cursor so next cycle is incremental
    if let ts = afterTimestamp, let eid = afterEntryId {
      var updatedConfig = config
      updatedConfig.lastPushTimestamp = ts
      updatedConfig.lastPushEntryId = eid
      await MainActor.run { self.config = updatedConfig }
      saveConfig(updatedConfig)
      log.info("Push cursor saved: timestamp=\(ts, privacy: .public), entryId=\(eid, privacy: .public)")
    }

    log.info("Push complete: accepted=\(totalAccepted, privacy: .public), duplicates=\(totalDupes, privacy: .public)")

    return PushResult(
      entriesPushed: totalAccepted,
      duplicatesSkipped: totalDupes,
      serverSequence: lastServerSequence
    )
  }

  /// Pull entries from the cloud server with cursor-based pagination.
  ///
  /// Fetches pages of entries from the server, importing each page into the local
  /// database via `queryService.importFromCloudPull()`. Updates the pull cursor
  /// in the configuration after each page and saves the config on completion.
  ///
  /// - Parameter queryService: The query service for database import.
  /// - Returns: The pull result with import counts.
  /// - Throws: `CloudSyncError` on failure.
  public func pull(using queryService: ContextifyQueryService) async throws -> PullResult {
    // Snapshot MainActor-isolated state to avoid data races
    let (client, config) = await MainActor.run { (self.client, self.config) }
    guard let client, var config else {
      throw CloudSyncError.notConfigured
    }

    var cursor = config.lastPullSequence
    var totalImported = 0
    var totalSkipped = 0
    var pagesFetched = 0

    log.info("Starting pull from cursor \(cursor, privacy: .public)")

    var hasMore = true
    while hasMore {
      let response = try await client.pull(since: cursor, limit: 200)
      pagesFetched += 1

      let entryCount = response.entries.count
      let more = response.hasMore
      log.debug("Pull page \(pagesFetched, privacy: .public): \(entryCount, privacy: .public) entries, hasMore=\(more, privacy: .public)")

      if !response.entries.isEmpty {
        // Convert typed response objects to dictionaries for importFromCloudPull
        let projectDicts: [[String: Any]] = response.projects.map { proj in
          var d: [String: Any] = ["id": proj.id, "root_path": proj.rootPath]
          if let name = proj.name { d["name"] = name }
          return d
        }

        let transcriptDicts: [[String: Any]] = response.transcripts.map { tx in
          [
            "id": tx.id,
            "project_id": tx.projectId,
            "file_path": tx.filePath,
            "provider": tx.provider,
          ] as [String: Any]
        }

        let entryDicts: [[String: Any]] = response.entries.map { entry in
          var d = [String: Any]()
          d["id"] = entry.id
          d["transcript_id"] = entry.transcriptId
          d["project_id"] = entry.projectId
          d["provider"] = entry.provider
          d["kind"] = entry.kind
          d["timestamp"] = entry.timestamp
          d["content"] = entry.content
          d["content_sha256"] = entry.contentSha256
          d["display_in_timeline"] = entry.displayInTimeline
          d["created_at"] = entry.createdAt
          d["updated_at"] = entry.updatedAt
          if let s = entry.sessionId { d["session_id"] = s }
          if let b = entry.gitBranch { d["git_branch"] = b }
          if let c = entry.gitCommit { d["git_commit"] = c }
          if let c = entry.cwd { d["cwd"] = c }
          return d
        }

        let summaryDicts: [[String: Any]] = response.summaries.map { summary in
          var d: [String: Any] = [
            "entry_id": summary.entryId,
            "present_form": summary.presentForm,
            "past_form": summary.pastForm,
          ]
          if let disposition = summary.disposition { d["disposition"] = disposition }
          return d
        }

        let importResult = try queryService.importFromCloudPull(
          projects: projectDicts,
          transcripts: transcriptDicts,
          entries: entryDicts,
          summaries: summaryDicts
        )

        totalImported += importResult.entriesImported
        totalSkipped += importResult.entriesSkipped
      }

      // Guard against non-advancing cursors to prevent infinite loops
      let nextCursor = response.nextCursor
      if response.hasMore && nextCursor <= cursor {
        log.error("Pull cursor did not advance: stuck at \(cursor, privacy: .public)")
        throw CloudSyncError.serverError(
          statusCode: 500,
          body: "Protocol error: next_cursor did not advance (stuck at \(cursor))")
      }
      cursor = nextCursor
      hasMore = response.hasMore
    }

    // Update cursor in config and persist
    config.lastPullSequence = cursor
    await MainActor.run { self.config = config }
    saveConfig(config)

    log.info("Pull complete: imported=\(totalImported, privacy: .public), skipped=\(totalSkipped, privacy: .public), pages=\(pagesFetched, privacy: .public), cursor=\(cursor, privacy: .public)")

    return PullResult(
      entriesImported: totalImported,
      entriesSkipped: totalSkipped,
      pagesFetched: pagesFetched
    )
  }

  // MARK: - Private Helpers

  /// Stable machine identifier using IOPlatformUUID on macOS, /etc/machine-id on Linux.
  /// If ioreg fails (e.g. in a sandboxed app), falls back to a persisted UUID stored
  /// in Application Support to ensure stability across reboots and hostname changes.
  /// Called once via `cachedMachineId` lazy property; do not call directly.
  private func computeMachineId() -> String {
    #if os(macOS)
    // Try IOPlatformUUID first (works outside sandbox)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    process.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    let output = String(
      data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if let range = output.range(of: "IOPlatformUUID\" = \"") {
      let start = range.upperBound
      if let end = output[start...].firstIndex(of: "\"") {
        return String(output[start..<end])
      }
    }
    // Fallback: persisted UUID in Application Support (sandbox-safe)
    return getOrCreatePersistedDeviceId()
    #else
    if let id = try? String(contentsOfFile: "/etc/machine-id", encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines) {
      return id
    }
    return ProcessInfo.processInfo.hostName
    #endif
  }

  /// Returns a stable device ID persisted in Application Support.
  /// Creates and stores a new UUID if one doesn't exist yet.
  private func getOrCreatePersistedDeviceId() -> String {
    let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask).first!
    let contextifyDir = appSupport.appendingPathComponent("Contextify")
    let deviceIdFile = contextifyDir.appendingPathComponent("device_id.txt")

    // Try to read existing
    if let existing = try? String(contentsOf: deviceIdFile, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines),
       !existing.isEmpty {
      return existing
    }

    // Generate and persist a new UUID
    let newId = UUID().uuidString
    do {
      try FileManager.default.createDirectory(
        at: contextifyDir, withIntermediateDirectories: true)
      try newId.write(to: deviceIdFile, atomically: true, encoding: .utf8)
      log.info("Generated and persisted new device ID")
    } catch {
      log.warning("Failed to persist device ID: \(error.localizedDescription, privacy: .public)")
    }
    return newId
  }

  /// Map CloudSyncError to a user-friendly message string.
  private func userFriendlyMessage(for error: Error) -> String {
    if let syncError = error as? CloudSyncError {
      switch syncError {
      case .notConfigured:
        return "Cloud sync not configured. Set up cloud sync in Settings."
      case .unauthorized:
        return "Authentication failed. Check your API key in cloud settings."
      case .serverError(let code, _):
        return "Server error (HTTP \(code)). Try again later."
      case .networkError:
        return "Network error. Check your internet connection."
      case .encodingError:
        return "Failed to prepare sync data. This may indicate a data issue."
      case .decodingError:
        return "Unexpected server response. The server may be running an incompatible version."
      case .partialPushFailure(let accepted, let errors):
        return "Push partially failed: \(accepted) entries synced, \(errors.count) failed. Will retry on next sync."
      }
    }
    return error.localizedDescription
  }

  // MARK: - App-Level Auto-Sync

  /// Start the app-level auto-sync loop if cloud is configured.
  /// Called once at app launch. Loads config from disk and begins
  /// syncing every 5 minutes. Safe to call multiple times (no-ops if running).
  @MainActor
  public func startAppLevelAutoSync() {
    guard autoSyncTask == nil else { return }
    guard let config = loadConfig(), config.enabled else {
      log.debug("Auto-sync skipped: no config or disabled")
      return
    }
    configure(config: config)
    autoSyncEnabled = true
    log.info("Starting app-level auto-sync")

    autoSyncTask = Task.detached(priority: .background) { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        do {
          let dbURL = try DatabaseManager.shared.databasePath()
          let queryService = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)
          await self.sync(using: queryService)
        } catch {
          await self.setErrorForUI("Auto-sync failed to open local database.")
        }
        try? await Task.sleep(for: .seconds(300))
      }
    }
  }

  /// Stop the auto-sync loop.
  @MainActor
  public func stopAppLevelAutoSync() {
    autoSyncTask?.cancel()
    autoSyncTask = nil
    autoSyncEnabled = false
    log.info("Stopped app-level auto-sync")
  }

  /// Toggle auto-sync on/off. For use by Settings UI.
  /// Persists the `enabled` preference to cloud.json so it survives app restart.
  @MainActor
  public func setAutoSync(enabled: Bool) {
    if enabled {
      startAppLevelAutoSync()
    } else {
      stopAppLevelAutoSync()
    }

    // Persist the enabled preference to disk
    if var config = loadConfig() {
      config.enabled = enabled
      saveConfig(config)
      log.info("Persisted auto-sync enabled=\(enabled, privacy: .public) to cloud.json")
    }
  }

  /// Trigger a one-shot sync. Returns immediately; sync runs in background.
  @MainActor
  public func triggerSync() {
    Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      do {
        let dbURL = try DatabaseManager.shared.databasePath()
        let queryService = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)
        await self.sync(using: queryService)
      } catch {
        await self.setErrorForUI("Failed to open local database for sync.")
      }
    }
  }
}
