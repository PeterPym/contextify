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

// MARK: - CloudSyncManager

/// Orchestrator for cloud sync push and pull operations.
///
/// Coordinates between the local database (via `ContextifyQueryService`) and the
/// remote cloud server (via `CloudSyncClient`). Manages configuration persistence,
/// cursor tracking for incremental pulls, and exposes observable state for UI binding.
@MainActor
@Observable
public final class CloudSyncManager {

  // MARK: - Observable State

  /// Timestamp of the last successful sync completion.
  public private(set) var lastSyncDate: Date?

  /// Current sync state for UI display.
  public private(set) var syncState: SyncState = .idle

  /// Result from the most recent push operation.
  public private(set) var lastPushResult: PushResult?

  /// Result from the most recent pull operation.
  public private(set) var lastPullResult: PullResult?

  // MARK: - Private State

  private var client: CloudSyncClient?
  private var config: CloudConfig?

  // MARK: - Initialization

  public init() {}

  // MARK: - Configuration

  /// Configure the manager with cloud connection settings.
  ///
  /// Creates a new `CloudSyncClient` using the provided configuration.
  /// Must be called before `sync()`, `push()`, or `pull()`.
  ///
  /// - Parameter config: Cloud configuration with server URL and API key.
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
    guard syncState != .disabled else {
      log.info("Sync skipped: cloud sync is disabled")
      return
    }

    syncState = .syncing
    log.info("Starting full sync cycle")

    do {
      let pushResult = try await push(using: queryService)
      lastPushResult = pushResult

      let pullResult = try await pull(using: queryService)
      lastPullResult = pullResult

      lastSyncDate = Date()
      syncState = .idle

      let pushed = pushResult.entriesPushed
      let pulled = pullResult.entriesImported
      log.info("Sync complete: pushed \(pushed, privacy: .public), pulled \(pulled, privacy: .public)")
    } catch {
      let message = userFriendlyMessage(for: error)
      syncState = .error(message)
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
    guard let client, let config else {
      throw CloudSyncError.networkError(URLError(.notConnectedToInternet))
    }

    log.info("Starting push")

    // Export data from local database
    let exportData = try queryService.exportForCloudPush()

    if exportData.entries.isEmpty {
      log.info("Push: no entries to push")
      return PushResult(entriesPushed: 0, duplicatesSkipped: 0, serverSequence: 0)
    }

    // Build the push payload
    let device = CloudDeviceInfo(
      machineId: config.deviceId,
      machineName: config.deviceName,
      os: "macos",
      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    )

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

    log.info("Pushing \(payload.entries.count, privacy: .public) entries")

    let response = try await client.push(payload)

    let accepted = response.accepted
    let dupes = response.duplicatesSkipped
    log.info("Push response: accepted=\(accepted, privacy: .public), duplicates=\(dupes, privacy: .public)")

    return PushResult(
      entriesPushed: response.accepted,
      duplicatesSkipped: response.duplicatesSkipped,
      serverSequence: response.serverSequence
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
    guard let client, var config else {
      throw CloudSyncError.networkError(URLError(.notConnectedToInternet))
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

      cursor = response.nextCursor
      hasMore = response.hasMore
    }

    // Update cursor in config and persist
    config.lastPullSequence = cursor
    self.config = config
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
      case .unauthorized:
        return "Authentication failed. Check your API key in cloud settings."
      case .serverError(let code, _):
        return "Server error (HTTP \(code)). Try again later."
      case .networkError:
        return "Network error. Check your internet connection."
      case .decodingError:
        return "Unexpected server response. The server may be running an incompatible version."
      }
    }
    return error.localizedDescription
  }
}
