// SPDX-License-Identifier: MIT
// CloudSyncClient.swift - HTTP client for contextify-cloud sync API

import Foundation

#if canImport(OSLog)
import OSLog
private let log = Logger(subsystem: "dev.contextify", category: "CloudSyncClient")
#else
private let log = CrossPlatformLogger(subsystem: "dev.contextify", category: "CloudSyncClient")
#endif

// MARK: - Error Types

/// Errors that can occur during cloud sync API calls.
public enum CloudSyncError: Error, Sendable {
  /// Cloud sync is not configured. The user must run setup first.
  case notConfigured
  /// The server returned HTTP 401 (unauthorized). The API key may be invalid or revoked.
  case unauthorized
  /// The server returned a non-success HTTP status code.
  case serverError(statusCode: Int, body: String)
  /// A network-level error occurred (DNS failure, timeout, connection refused, etc.).
  case networkError(Error)
  /// The request payload could not be encoded to JSON.
  case encodingError(Error)
  /// The response body could not be decoded into the expected type.
  case decodingError(Error)
}

extension CloudSyncError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "Cloud sync not configured. Run setup first."
    case .unauthorized:
      return "Unauthorized: check your API key"
    case .serverError(let code, let body):
      return "Server error (HTTP \(code)): \(body)"
    case .networkError(let error):
      return "Network error: \(error.localizedDescription)"
    case .encodingError(let error):
      return "Encoding error: \(error.localizedDescription)"
    case .decodingError(let error):
      return "Decoding error: \(error.localizedDescription)"
    }
  }
}

// MARK: - Client

/// HTTP client for the contextify-cloud sync API.
///
/// Thread-safe actor that communicates with a contextify-cloud server
/// for push, pull, and status operations. Uses `URLSession` for HTTP.
/// The model types in `CloudSyncModels.swift` use explicit `CodingKeys`
/// for snake_case JSON serialization, so no key strategy is needed.
///
/// Usage:
/// ```swift
/// let client = CloudSyncClient(
///   serverURL: URL(string: "https://cloud.contextify.sh")!,
///   apiKey: "ctx_abc123_secret"
/// )
///
/// let status = try await client.status()
/// print("Entries synced: \(status.entriesSynced)")
/// ```
public actor CloudSyncClient {

  // MARK: - Properties

  private let serverURL: URL
  private let apiKey: String
  private let session: URLSession
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  // MARK: - Initialization

  /// Creates a new cloud sync client.
  ///
  /// - Parameters:
  ///   - serverURL: Base URL of the contextify-cloud server (e.g. `https://cloud.contextify.sh`).
  ///   - apiKey: API key for authentication (format: `ctx_{key_id}_{secret}`).
  ///   - session: URLSession to use for requests. Defaults to `.shared`.
  public init(
    serverURL: URL,
    apiKey: String,
    session: URLSession = .shared
  ) {
    self.serverURL = serverURL
    self.apiKey = apiKey
    self.session = session
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
  }

  // MARK: - Public API

  /// Push local entries to the cloud server.
  ///
  /// Sends a batch of projects, transcripts, entries, summaries, usage records,
  /// tool invocations, and transcript metadata to the server. The server deduplicates
  /// by content hash and supports idempotency via `idempotencyKey`.
  ///
  /// - Parameter payload: The push payload containing all records to upload.
  /// - Returns: The server's push response with accepted/duplicate/error counts.
  /// - Throws: `CloudSyncError` on network, auth, server, or decoding failure.
  public func push(_ payload: CloudPushPayload) async throws -> CloudPushResponse {
    let url = buildURL(path: "/api/v1/sync/push")
    let body: Data
    do {
      body = try encoder.encode(payload)
    } catch {
      throw CloudSyncError.encodingError(error)
    }

    log.info("Pushing to cloud: \(payload.entries.count, privacy: .public) entries, \(payload.projects.count, privacy: .public) projects, \(payload.transcripts.count, privacy: .public) transcripts")

    var request = buildRequest(url: url, method: "POST")
    request.httpBody = body

    let data = try await execute(request)
    return try decode(CloudPushResponse.self, from: data)
  }

  /// Pull entries from the cloud server (from other devices).
  ///
  /// Uses cursor-based pagination via `server_sequence`. Returns entries with
  /// `server_sequence > since`, ordered ascending. The response includes
  /// referenced projects, transcripts, and summaries for the returned entries.
  ///
  /// - Parameters:
  ///   - since: Server sequence cursor. Only entries with sequence > since are returned.
  ///   - limit: Maximum entries per response (1-1000, default 200).
  ///   - projectId: Optional project ID filter.
  /// - Returns: Pull response with entries, related objects, and pagination info.
  /// - Throws: `CloudSyncError` on network, auth, server, or decoding failure.
  public func pull(
    since: Int,
    limit: Int = 200,
    projectId: String? = nil
  ) async throws -> CloudPullResponse {
    var queryItems = [
      URLQueryItem(name: "since", value: String(since)),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    if let projectId {
      queryItems.append(URLQueryItem(name: "project_id", value: projectId))
    }

    let url = buildURL(path: "/api/v1/sync/pull", queryItems: queryItems)

    log.info("Pulling from cloud: since=\(since, privacy: .public), limit=\(limit, privacy: .public)")

    let request = buildRequest(url: url, method: "GET")
    let data = try await execute(request)
    return try decode(CloudPullResponse.self, from: data)
  }

  /// Get the current sync status from the cloud server.
  ///
  /// Returns information about synced entries, registered devices,
  /// last sync time, and the current server sequence high-water mark.
  ///
  /// - Returns: The sync status for the authenticated user.
  /// - Throws: `CloudSyncError` on network, auth, server, or decoding failure.
  public func status() async throws -> CloudSyncStatus {
    let url = buildURL(path: "/api/v1/sync/status")

    log.debug("Fetching cloud sync status")

    let request = buildRequest(url: url, method: "GET")
    let data = try await execute(request)
    return try decode(CloudSyncStatus.self, from: data)
  }

  // MARK: - Private Helpers

  /// Builds a full URL from a path and optional query items.
  private func buildURL(
    path: String,
    queryItems: [URLQueryItem]? = nil
  ) -> URL {
    let baseString = serverURL.absoluteString.hasSuffix("/")
      ? String(serverURL.absoluteString.dropLast())
      : serverURL.absoluteString

    var components = URLComponents(string: "\(baseString)\(path)")!
    if let queryItems, !queryItems.isEmpty {
      components.queryItems = queryItems
    }
    return components.url!
  }

  /// Builds a URLRequest with standard headers.
  private func buildRequest(url: URL, method: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return request
  }

  /// Executes a URLRequest and maps HTTP status codes to CloudSyncError.
  private func execute(_ request: URLRequest) async throws -> Data {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      log.error("Network error: \(error.localizedDescription, privacy: .public)")
      throw CloudSyncError.networkError(error)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      log.error("Response is not HTTPURLResponse")
      throw CloudSyncError.networkError(
        URLError(.badServerResponse)
      )
    }

    let statusCode = httpResponse.statusCode

    switch statusCode {
    case 200..<300:
      return data
    case 401:
      log.warning("Unauthorized (HTTP 401)")
      throw CloudSyncError.unauthorized
    default:
      let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
      log.warning("Server error: HTTP \(statusCode, privacy: .public): \(body, privacy: .public)")
      throw CloudSyncError.serverError(statusCode: statusCode, body: body)
    }
  }

  /// Decodes JSON data into the specified type, wrapping errors as CloudSyncError.
  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try decoder.decode(type, from: data)
    } catch {
      log.error("Decoding error: \(error.localizedDescription, privacy: .public)")
      throw CloudSyncError.decodingError(error)
    }
  }
}
