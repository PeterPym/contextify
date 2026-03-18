// SPDX-License-Identifier: MIT
// CloudSyncManager.swift - Orchestrator for cloud push/pull sync operations

import Foundation
import GRDB

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
  case waitingForIngest
  case deferred
  case error(String)
  case disabled

  public static func == (lhs: SyncState, rhs: SyncState) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle), (.syncing, .syncing), (.waitingForIngest, .waitingForIngest), (.deferred, .deferred), (.disabled, .disabled):
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
  /// Total wall-clock duration of the push operation in seconds.
  public let durationSeconds: Double
  /// Number of batches completed during this push.
  public let batchesCompleted: Int
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
  @MainActor public private(set) var syncState: SyncState = .disabled

  /// Result from the most recent push operation.
  @MainActor public private(set) var lastPushResult: PushResult?

  /// Result from the most recent pull operation.
  @MainActor public private(set) var lastPullResult: PullResult?

  /// Most recently fetched server-side sync status projection.
  @MainActor public private(set) var cloudStatus: CloudSyncStatus?

  /// Authenticated account/profile data for the current API key.
  @MainActor public private(set) var cloudAccountProfile: CloudAccountProfile?

  /// Last error encountered while fetching status (separate from sync run errors).
  @MainActor public private(set) var cloudStatusError: String?

  /// Last error encountered while fetching account/profile data.
  @MainActor public private(set) var cloudAccountError: String?

  /// True when latest status fetch failed due to connectivity.
  @MainActor public private(set) var cloudOffline: Bool = false

  /// Timestamp of the latest status refresh attempt.
  @MainActor public private(set) var cloudStatusUpdatedAt: Date?

  // Smoothed metrics for stable UX ETA/throughput display.
   public private(set) var cloudSmoothedThroughputEntriesPerMin: Double?
   public private(set) var cloudSmoothedEtaSeconds: Int?

  /// The push session ID this client is currently using or last used.
  /// Exposed so the UI can compare against the server's active push session
  /// to detect orphaned/stalled sessions from previous connections.
  @MainActor public var currentPushSessionId: String? {
    config?.lastPushSessionId
  }

  /// Whether the server's active push session is from a different/previous
  /// connection and should be ignored for UI state decisions.
  ///
  /// After disconnect/reconnect, the server may still report a stalled session
  /// from the old connection. The client's current session ID won't match,
  /// so the UI should treat the server session as irrelevant.
  @MainActor public var isActiveSessionOrphaned: Bool {
    guard let serverSessionId = cloudStatus?.activePushSession?.syncSessionId else {
      return false
    }
    guard let clientSessionId = currentPushSessionId else {
      // No client session yet; any server session is from a prior connection
      return true
    }
    return serverSessionId != clientSessionId
  }

  // MARK: - Push Progress Tracking (MainActor-isolated for SwiftUI)

  /// Total entries counted at push start for progress estimation.
  @MainActor public private(set) var pushTotalEntries: Int = 0

  /// Estimated total batches for the current push (ceil(totalEntries / batchSize)).
  @MainActor public private(set) var pushEstimatedTotalBatches: Int = 0

  /// Number of batches completed so far in the current push.
  @MainActor public private(set) var pushBatchesCompleted: Int = 0

  /// Client-side estimated seconds remaining for the push to complete.
  /// Computed from elapsed time and batch completion rate.
  @MainActor public private(set) var pushEstimatedSecondsRemaining: Int?

  /// Timestamp when the current push operation started.
  @MainActor public private(set) var pushStartTime: Date?

  // MARK: - Private State (MainActor-isolated, snapshotted by sync methods)

  @MainActor private var client: CloudSyncClient?
  @MainActor private var config: CloudConfig?

  /// The configured cloud server base URL (e.g. "https://cloud.contextify.sh").
  /// Nil when cloud sync is not configured.
  @MainActor public var configuredServerURL: String? { config?.serverURL }
  @MainActor private var connectionRevision: UInt64 = 0
  @MainActor var clientFactory: @Sendable (URL, String) -> CloudSyncClient = {
    CloudSyncClient(serverURL: $0, apiKey: $1)
  }

  // MARK: - Initialization

  /// Shared app-level instance. Lives for the entire app lifecycle so sync
  /// survives Settings window open/close.
  @MainActor public static let shared = CloudSyncManager()

  /// Whether auto-sync is currently running.
  @MainActor public private(set) var autoSyncEnabled: Bool = false

  /// Task handle for the auto-sync loop.
  @MainActor private var autoSyncTask: Task<Void, Never>?

  /// Task handle for lightweight cloud status polling used by UI surfaces.
  @MainActor private var statusPollTask: Task<Void, Never>?

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
    let previousConfig = self.config
    let connectionIdentityChanged =
      previousConfig?.serverURL != config.serverURL || previousConfig?.apiKey != config.apiKey

    guard let url = URL(string: config.serverURL) else {
      log.error("Invalid server URL in config: \(config.serverURL, privacy: .public)")
      syncState = .error("Invalid server URL")
      return
    }

    connectionRevision &+= 1
    if connectionIdentityChanged {
      clearConnectionScopedState()
    }
    self.config = config
    self.client = clientFactory(url, config.apiKey)

    if config.enabled {
      syncState = .idle
      startStatusPollingIfNeeded()
      Task.detached(priority: .utility) { [weak self] in
        await self?.refreshStatusFromServer()
        await self?.refreshAccountProfileFromServer()
      }
    } else {
      syncState = .disabled
      stopStatusPolling()
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
    // Pre-flight: if ingest is active, don't even start. No network calls,
    // no payload assembly. Show a neutral waiting state and return.
    let ingestActive = await DatabaseWriteCoordinator.shared.isIngestActive
    if ingestActive {
      await MainActor.run { self.syncState = .waitingForIngest }
      log.info("Sync skipped: ingest is active, waiting for completion")
      return
    }

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
    await refreshStatusFromServer()
    log.info("Starting full sync cycle")

    do {
      let pushResult = try await push(using: queryService)
      await MainActor.run { self.lastPushResult = pushResult }

      // Gate the pull through the write coordinator so it never overlaps
      // with active bulk ingest. On timeout, defer instead of blocking.
      let pullResult: PullResult
      if let result = try await DatabaseWriteCoordinator.shared.withSyncScope(timeout: .seconds(30), {
        try await self.pull(using: queryService)
      }) {
        pullResult = result
      } else {
        // Ingest is active and did not finish within the timeout window
        await MainActor.run { self.syncState = .deferred }
        log.info("Sync deferred: ingest is active, will retry next cycle")
        await refreshStatusFromServer()
        return
      }

      await MainActor.run {
        self.lastPullResult = pullResult
        self.lastSyncDate = Date()
        self.syncState = .idle
      }
      await refreshStatusFromServer()

      let pushed = pushResult.entriesPushed
      let pulled = pullResult.entriesImported
      log.info("Sync complete: pushed \(pushed, privacy: .public), pulled \(pulled, privacy: .public)")
    } catch {
      if isTransientDatabaseError(error) {
        await MainActor.run { self.syncState = .deferred }
        log.info("Sync deferred due to transient database contention")
      } else {
        let message = userFriendlyMessage(for: error)
        await MainActor.run { self.syncState = .error(message) }
        log.error("Sync failed: \(message, privacy: .public)")
      }
      await refreshStatusFromServer()
    }
  }

  /// Fetches cloud status snapshot for UI state projection.
  public func refreshStatusFromServer() async {
    // Snapshot MainActor-isolated state to avoid data races
    let (client, revision) = await MainActor.run { (self.client, self.connectionRevision) }
    guard let client else { return }

    do {
      let status = try await client.status()
      await MainActor.run {
        guard self.connectionRevision == revision else { return }
        self.cloudStatus = status
        self.cloudStatusUpdatedAt = Date()
        self.cloudStatusError = nil
        self.cloudOffline = false
        self.updateSmoothedProgressMetrics(from: status)
      }
    } catch {
      let message = userFriendlyMessage(for: error)
      let offline = isConnectivityError(error)
      await MainActor.run {
        guard self.connectionRevision == revision else { return }
        self.cloudStatusUpdatedAt = Date()
        self.cloudStatusError = message
        self.cloudOffline = offline
      }
      log.warning("Status refresh failed: \(message, privacy: .public)")
    }
  }

  /// Fetches authenticated account/profile data for the current API key.
  public func refreshAccountProfileFromServer() async {
    let (client, revision) = await MainActor.run { (self.client, self.connectionRevision) }
    guard let client else { return }

    do {
      let profile = try await client.account()
      await MainActor.run {
        guard self.connectionRevision == revision else { return }
        self.cloudAccountProfile = profile
        self.cloudAccountError = nil
      }
    } catch {
      let message = userFriendlyMessage(for: error)
      await MainActor.run {
        guard self.connectionRevision == revision else { return }
        self.cloudAccountProfile = nil
        self.cloudAccountError = message
      }
      log.warning("Account refresh failed: \(message, privacy: .public)")
    }
  }

  /// Validate an API key and return the account profile it resolves to.
  public func validateConnection(
    serverURL: String,
    apiKey: String
  ) async throws -> CloudAccountProfile {
    guard let url = URL(string: serverURL) else {
      throw CloudSyncError.serverError(statusCode: 0, body: "Invalid server URL")
    }
    let factory = await MainActor.run { self.clientFactory }
    let client = factory(url, apiKey)
    return try await client.account()
  }

  /// Applies a known-good validated account profile immediately so UI can
  /// reflect the authenticated identity without waiting on a follow-up fetch.
  @MainActor
  public func setValidatedAccountProfile(_ profile: CloudAccountProfile) {
    cloudAccountProfile = profile
    cloudAccountError = nil
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
    let (client, loadedConfig) = await MainActor.run { (self.client, self.config) }
    guard let client, let loadedConfig else {
      throw CloudSyncError.notConfigured
    }
    var config = loadedConfig

    log.info("Starting push")

    // macOS cloud sync uses the shared app-level machine ID so app, CLI, and
    // persisted cloud config converge on one stable device identity.
    let machineId = MachineID.normalizedCloudDeviceID(config.deviceId)
    if machineId != config.deviceId {
      config.deviceId = machineId
      await MainActor.run { self.config = config }
      saveConfig(config)
    }
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
    var syncSessionId = config.lastPushSessionId ?? UUID().uuidString
    var batchSeq = (config.lastPushBatchSeq ?? 0) + 1
    var totalAccepted = 0
    var totalDupes = 0
    var lastServerSequence = 0

    // Count total entries remaining ONCE at push start for progress estimation.
    let totalEntriesToPush = try queryService.countEntriesForCloudPush(
      afterTimestamp: afterTimestamp,
      afterEntryId: afterEntryId
    )
    let estimatedTotalBatches = totalEntriesToPush > 0
      ? Int((Double(totalEntriesToPush) / Double(batchSize)).rounded(.up))
      : 0
    let pushStartTime = Date()
    var batchesCompletedLocal = 0

    await MainActor.run {
      self.pushTotalEntries = totalEntriesToPush
      self.pushEstimatedTotalBatches = estimatedTotalBatches
      self.pushBatchesCompleted = 0
      self.pushEstimatedSecondsRemaining = nil
      self.pushStartTime = pushStartTime
    }

    log.info("Push: \(totalEntriesToPush, privacy: .public) entries remaining, ~\(estimatedTotalBatches, privacy: .public) batches estimated")

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

      let entriesInBatch = exportData.entries.count
      let payload = CloudPushPayload(
        idempotencyKey: "\(syncSessionId):\(batchSeq)",
        batchSeq: batchSeq,
        syncSessionId: syncSessionId,
        entriesSent: entriesInBatch,
        totalBatches: estimatedTotalBatches > 0 ? estimatedTotalBatches : nil,
        device: device,
        projects: exportData.projects.map { proj in
          CloudPushProject(
            id: proj.id,
            name: proj.name,
            rootPath: proj.rootPath,
            repoGroupKey: proj.repoGroupKey,
            repoIdentity: proj.repoIdentity,
            repoOriginNormalized: proj.repoOriginNormalized,
            gitCommonDir: proj.gitCommonDir,
            isWorktree: proj.isWorktree,
            defaultBranch: proj.defaultBranch,
            vcsProvider: proj.vcsProvider,
            worktreeName: proj.worktreeName,
            repoName: proj.repoName
          )
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
            sourceDeviceId: entry.sourceDeviceId,
            sourceDeviceName: entry.sourceDeviceName,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt
          )
        }
      )

      log.info(
        "Pushing batch seq=\(batchSeq, privacy: .public): \(payload.entries.count, privacy: .public) entries session=\(syncSessionId, privacy: .public)")
      let response: CloudPushResponse
      do {
        response = try await client.push(payload)
      } catch CloudSyncError.serverError(statusCode: 409, _) {
        // Idempotency conflict: stale key from a previous failed attempt.
        // Generate a fresh session ID and retry this batch once.
        let newSessionId = UUID().uuidString
        log.warning(
          "Push 409 conflict: rotating session \(syncSessionId, privacy: .public) -> \(newSessionId, privacy: .public) and retrying batch \(batchSeq, privacy: .public)")
        syncSessionId = newSessionId
        batchSeq = 1
        let retryPayload = CloudPushPayload(
          idempotencyKey: "\(syncSessionId):\(batchSeq)",
          batchSeq: batchSeq,
          syncSessionId: syncSessionId,
          entriesSent: payload.entriesSent,
          device: payload.device,
          projects: payload.projects,
          transcripts: payload.transcripts,
          entries: payload.entries
        )
        response = try await client.push(retryPayload)
      } catch CloudSyncError.serverError(statusCode: 429, let body) {
        // Rate limited: back off and retry this batch.
        log.warning(
          "Push 429 rate limited on batch \(batchSeq, privacy: .public): \(body, privacy: .public). Waiting 30s.")
        try await Task.sleep(for: .seconds(30))
        response = try await client.push(payload)
      }

      if let returnedSession = response.syncSessionId, !returnedSession.isEmpty {
        syncSessionId = returnedSession
      }

      let resolvedCount = response.entriesResolved ?? 0
      let sentCount = response.entriesSent ?? entriesInBatch
      let serverDeclaredSafe = response.checkpointSafe ?? response.errors.isEmpty
      let checkpointSafe = serverDeclaredSafe && resolvedCount == sentCount

      // Fail closed: never advance cursor if server says batch is unsafe.
      if !checkpointSafe {
        let sampleErrors = response.errors.prefix(3).joined(separator: "; ")
        let sampleCodes = (response.errorCodes ?? []).prefix(3).joined(separator: ", ")
        let detail = !sampleCodes.isEmpty ? sampleCodes : sampleErrors
        log.error(
          "Push batch unsafe: seq=\(batchSeq, privacy: .public) resolved=\(resolvedCount, privacy: .public)/\(sentCount, privacy: .public) detail=\(detail, privacy: .public)"
        )
        // Persist session id so retries reuse deterministic identity for this batch.
        config.lastPushSessionId = syncSessionId
        await MainActor.run { self.config = config }
        saveConfig(config)
        throw CloudSyncError.partialPushFailure(
          accepted: totalAccepted,
          errors: Array(response.errors.prefix(5)) + Array((response.errorCodes ?? []).prefix(5))
        )
      }

      totalAccepted += response.entriesAccepted ?? response.accepted
      totalDupes += response.entriesDuplicates ?? response.duplicatesSkipped
      lastServerSequence = response.serverSequence

      // Advance keyset cursor from last entry in this batch
      if let last = exportData.entries.last {
        afterTimestamp = last.timestamp
        afterEntryId = last.id
      }

      // Persist checkpoint after every checkpoint-safe batch (durable resume).
      config.lastPushTimestamp = afterTimestamp
      config.lastPushEntryId = afterEntryId
      config.lastPushSessionId = syncSessionId
      config.lastPushBatchSeq = batchSeq
      await MainActor.run { self.config = config }
      saveConfig(config)
      if let ts = afterTimestamp, let eid = afterEntryId {
        log.info(
          "Push checkpoint saved: seq=\(batchSeq, privacy: .public), timestamp=\(ts, privacy: .public), entryId=\(eid, privacy: .public)")
      }

      // Update progress tracking after each successful batch.
      batchesCompletedLocal += 1
      let elapsed = Date().timeIntervalSince(pushStartTime)
      let etaSeconds: Int? = {
        guard elapsed > 0, batchesCompletedLocal > 0 else { return nil }
        let batchesPerSecond = Double(batchesCompletedLocal) / elapsed
        guard batchesPerSecond > 0 else { return nil }
        let remaining = Double(estimatedTotalBatches - batchesCompletedLocal)
        guard remaining > 0 else { return nil }
        return Int((remaining / batchesPerSecond).rounded(.up))
      }()

      await MainActor.run {
        self.pushBatchesCompleted = batchesCompletedLocal
        self.pushEstimatedSecondsRemaining = etaSeconds
      }

      batchSeq += 1

      // Short page means we have exported everything
      if exportData.entries.count < batchSize {
        break
      }
    }

    // Clear progress state and compute final duration.
    let pushDuration = Date().timeIntervalSince(pushStartTime)
    await MainActor.run {
      self.pushEstimatedSecondsRemaining = nil
      self.pushStartTime = nil
    }

    log.info("Push complete: accepted=\(totalAccepted, privacy: .public), duplicates=\(totalDupes, privacy: .public), batches=\(batchesCompletedLocal, privacy: .public), duration=\(String(format: "%.1f", pushDuration), privacy: .public)s")

    return PushResult(
      entriesPushed: totalAccepted,
      duplicatesSkipped: totalDupes,
      serverSequence: lastServerSequence,
      durationSeconds: pushDuration,
      batchesCompleted: batchesCompletedLocal
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
          if let deviceId = entry.uploadedByDeviceId { d["source_device_id"] = deviceId }
          if let deviceName = entry.uploadedByDeviceName { d["source_device_name"] = deviceName }
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

        // Retry on transient SQLITE_BUSY within the same sync cycle rather than
        // deferring the entire cycle. The write coordinator prevents overlap in
        // most cases, but TranscriptOrchestrator lightweight writes can still
        // briefly contend.
        var importResult: CloudPullImportResult
        var importAttempt = 0
        let maxImportRetries = 3
        while true {
          do {
            importResult = try queryService.importFromCloudPull(
              projects: projectDicts,
              transcripts: transcriptDicts,
              entries: entryDicts,
              summaries: summaryDicts
            )
            break
          } catch let error as DatabaseError where error.resultCode == .SQLITE_BUSY || error.resultCode == .SQLITE_LOCKED {
            importAttempt += 1
            guard importAttempt < maxImportRetries else { throw error }
            log.warning("Pull import retry \(importAttempt, privacy: .public)/\(maxImportRetries, privacy: .public) after SQLITE_BUSY")
            try await Task.sleep(for: .milliseconds(100 * (1 << (importAttempt - 1))))
          }
        }

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

  /// Returns true when the given error represents a connectivity outage.
  private func isConnectivityError(_ error: Error) -> Bool {
    if let syncError = error as? CloudSyncError {
      if case .networkError = syncError {
        return true
      }
    }
    return false
  }

  /// Returns true when the error is a transient SQLite lock contention that
  /// should result in a deferred sync rather than a user-visible error badge.
  private func isTransientDatabaseError(_ error: Error) -> Bool {
    if let dbError = error as? DatabaseError {
      return dbError.resultCode == .SQLITE_BUSY
          || dbError.resultCode == .SQLITE_LOCKED
    }
    return false
  }

  @MainActor
  private func startStatusPollingIfNeeded() {
    guard statusPollTask == nil else { return }
    guard config?.enabled == true else { return }

    statusPollTask = Task.detached(priority: .utility) { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        await self.refreshStatusFromServer()

        let intervalSeconds = await MainActor.run { () -> Double in
          switch self.syncState {
          case .syncing:
            return 15
          default:
            return 60
          }
        }
        try? await Task.sleep(for: .seconds(intervalSeconds))
      }
    }
    log.debug("Started cloud status polling task")
  }

  @MainActor
  private func stopStatusPolling() {
    statusPollTask?.cancel()
    statusPollTask = nil
    log.debug("Stopped cloud status polling task")
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

        // Wait for the 5-minute timer OR for ingest to complete (whichever
        // comes first). This triggers an immediate sync after ingest finishes
        // rather than waiting up to 5 minutes for the next cycle.
        //
        // We always listen for ingest completion, not just when state is
        // .waitingForIngest. Ingest can start mid-sleep (after a successful
        // sync), and we want to sync again as soon as it produces new data.
        await withTaskGroup(of: Void.self) { group in
          group.addTask {
            try? await Task.sleep(for: .seconds(300))
          }
          group.addTask {
            // Wait for ingest to finish. If no ingest is active right now,
            // this returns immediately -- so we also sleep to avoid a tight
            // loop. The key: if ingest starts and finishes during our sleep,
            // waitForIngestComplete won't catch it (already done). We poll
            // periodically to cover that gap.
            while !Task.isCancelled {
              let ingestActive = await DatabaseWriteCoordinator.shared.isIngestActive
              if ingestActive {
                // Ingest is running -- wait for it to finish, then break
                await DatabaseWriteCoordinator.shared.waitForIngestComplete()
                break
              }
              // No ingest right now. Check again in 10 seconds.
              try? await Task.sleep(for: .seconds(10))
            }
          }
          // First task to finish wins; cancel the other
          await group.next()
          group.cancelAll()
        }
      }
    }
  }

  /// Stop the auto-sync loop.
  @MainActor
  public func stopAppLevelAutoSync() {
    autoSyncTask?.cancel()
    autoSyncTask = nil
    autoSyncEnabled = false
    stopStatusPolling()
    log.info("Stopped app-level auto-sync")
  }

  /// Full reset for disconnect: stop sync, clear all in-memory state.
  /// Call this when the user disconnects from cloud sync in Settings.
  @MainActor
  public func resetForDisconnect() {
    connectionRevision &+= 1
    stopAppLevelAutoSync()
    stopStatusPolling()
    client = nil
    config = nil
    clearConnectionScopedState()
    syncState = .disabled
    log.info("Reset cloud sync manager after disconnect")
  }

  @MainActor
  private func clearConnectionScopedState() {
    lastSyncDate = nil
    lastPushResult = nil
    lastPullResult = nil
    cloudStatus = nil
    cloudStatusError = nil
    cloudAccountProfile = nil
    cloudAccountError = nil
    cloudOffline = false
    cloudStatusUpdatedAt = nil
    cloudSmoothedThroughputEntriesPerMin = nil
    cloudSmoothedEtaSeconds = nil
    pushTotalEntries = 0
    pushEstimatedTotalBatches = 0
    pushBatchesCompleted = 0
    pushEstimatedSecondsRemaining = nil
    pushStartTime = nil
  }

  /// Toggle auto-sync on/off. For use by Settings UI.
  /// Persists the `enabled` preference to cloud.json so it survives app restart.
  /// Persist BEFORE start so startAppLevelAutoSync() sees enabled=true in config.
  @MainActor
  public func setAutoSync(enabled: Bool) {
    // Persist first so startAppLevelAutoSync() reads enabled=true from disk
    if var config = loadConfig() {
      config.enabled = enabled
      self.config = config
      saveConfig(config)
      log.info("Persisted auto-sync enabled=\(enabled, privacy: .public) to cloud.json")
    } else {
      log.warning("setAutoSync called but no cloud config on disk; preference not persisted")
    }

    if enabled {
      startAppLevelAutoSync()
    } else {
      stopAppLevelAutoSync()
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

private extension CloudSyncManager {
  @MainActor
  func updateSmoothedProgressMetrics(from status: CloudSyncStatus) {
    let alpha = 0.35

    guard let active = status.activePushSession,
      (active.completionState?.lowercased() == "in_progress"
        || active.phase.lowercased() == "initial_upload"
        || active.phase.lowercased() == "syncing"
        || active.phase.lowercased() == "stalled")
    else {
      cloudSmoothedThroughputEntriesPerMin = nil
      cloudSmoothedEtaSeconds = nil
      return
    }

    if let throughput = active.throughputEntriesPerMin, throughput > 0 {
      if let prev = cloudSmoothedThroughputEntriesPerMin {
        cloudSmoothedThroughputEntriesPerMin = (alpha * throughput) + ((1.0 - alpha) * prev)
      } else {
        cloudSmoothedThroughputEntriesPerMin = throughput
      }
    }

    if let eta = active.etaSeconds, eta > 0 {
      if let prev = cloudSmoothedEtaSeconds {
        let smoothed = (alpha * Double(eta)) + ((1.0 - alpha) * Double(prev))
        cloudSmoothedEtaSeconds = Int(smoothed.rounded())
      } else {
        cloudSmoothedEtaSeconds = eta
      }
    }
  }
}
