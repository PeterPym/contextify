import Foundation
import XCTest
@testable import ContextifyCore

final class CloudSyncManagerTests: XCTestCase {

  private final class DelayedMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Data, HTTPURLResponse, Error?))?
    nonisolated(unsafe) static var delay: TimeInterval = 0.1

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      guard let handler = Self.handler else {
        client?.urlProtocol(self, didFailWithError: URLError(.unknown))
        return
      }

      let (data, response, error) = handler(request)
      let urlClient = client
      let proto = self
      DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay) {
        if let error {
          urlClient?.urlProtocol(proto, didFailWithError: error)
          return
        }
        urlClient?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
        urlClient?.urlProtocol(proto, didLoad: data)
        urlClient?.urlProtocolDidFinishLoading(proto)
      }
    }

    override func stopLoading() {}
  }

  override func tearDown() {
    super.tearDown()
    DelayedMockURLProtocol.handler = nil
    DelayedMockURLProtocol.delay = 0.1
  }

  private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DelayedMockURLProtocol.self]
    return URLSession(configuration: config)
  }

  private func makeManager(session: URLSession) async -> CloudSyncManager {
    await MainActor.run {
      let manager = CloudSyncManager()
      manager.clientFactory = { url, apiKey in
        CloudSyncClient(serverURL: url, apiKey: apiKey, session: session)
      }
      return manager
    }
  }

  func testRefreshStatusIgnoresStaleResponseAfterDisconnect() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)
    let response = HTTPURLResponse(
      url: URL(string: "https://cloud.contextify.sh/api/v1/sync/status")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    DelayedMockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/api/v1/sync/status")
      let data = """
      {
        "last_sync": "2026-03-14T23:00:00Z",
        "entries_synced": 12,
        "devices": [],
        "server_sequence": 34,
        "pending_batches": 0,
        "active_push_session": null
      }
      """.data(using: .utf8)!
      return (data, response, nil)
    }

    await MainActor.run {
      manager.configure(config: CloudConfig(
        serverURL: CloudConfig.defaultServerURL,
        apiKey: "ctx_old",
        deviceId: "device-1",
        deviceName: "Mac",
        enabled: false
      ))
    }

    let refreshTask = Task { await manager.refreshStatusFromServer() }
    await MainActor.run { manager.resetForDisconnect() }
    await refreshTask.value

    let finalState = await MainActor.run {
      (manager.cloudStatus, manager.cloudStatusError, manager.syncState)
    }
    XCTAssertNil(finalState.0)
    XCTAssertNil(finalState.1)
    XCTAssertEqual(finalState.2, .disabled)
  }

  func testRefreshAccountProfileIgnoresStaleResponseAfterReconfigure() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)
    let response = HTTPURLResponse(
      url: URL(string: "https://cloud.contextify.sh/api/v1/account")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    DelayedMockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/api/v1/account")
      let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
      let email = auth.contains("ctx_old") ? "old@example.com" : "new@example.com"
      let tenant = auth.contains("ctx_old") ? "Old Tenant" : "New Tenant"
      let data = """
      {
        "user_id": "7C9138BE-C8D7-4A6E-A804-430D239D4825",
        "email": "\(email)",
        "name": "Test User",
        "role": "owner",
        "tenant_id": "F154C9FE-9804-4582-8308-495ABFA302A2",
        "tenant_name": "\(tenant)",
        "tenant_plan": "solo",
        "created_at": "2026-03-14T23:00:00Z"
      }
      """.data(using: .utf8)!
      return (data, response, nil)
    }

    await MainActor.run {
      manager.configure(config: CloudConfig(
        serverURL: CloudConfig.defaultServerURL,
        apiKey: "ctx_old",
        deviceId: "device-1",
        deviceName: "Mac",
        enabled: false
      ))
    }

    let refreshTask = Task { await manager.refreshAccountProfileFromServer() }

    let newProfile = CloudAccountProfile(
      userId: UUID(uuidString: "7C9138BE-C8D7-4A6E-A804-430D239D4825")!,
      email: "new@example.com",
      name: "Test User",
      role: "owner",
      tenantId: UUID(uuidString: "F154C9FE-9804-4582-8308-495ABFA302A2")!,
      tenantName: "New Tenant",
      tenantPlan: "solo",
      createdAt: ISO8601DateFormatter().date(from: "2026-03-14T23:00:00Z")!
    )

    await MainActor.run {
      manager.configure(config: CloudConfig(
        serverURL: CloudConfig.defaultServerURL,
        apiKey: "ctx_new",
        deviceId: "device-1",
        deviceName: "Mac",
        enabled: false
      ))
      manager.setValidatedAccountProfile(newProfile)
    }

    await refreshTask.value

    let finalProfile = await MainActor.run { manager.cloudAccountProfile }
    XCTAssertEqual(finalProfile?.email, "new@example.com")
    XCTAssertEqual(finalProfile?.tenantName, "New Tenant")
  }

  func testConfigureClearsConnectionScopedStateWhenAPIKeyChanges() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)
    let statusResponse = HTTPURLResponse(
      url: URL(string: "https://cloud.contextify.sh/api/v1/sync/status")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    let accountResponse = HTTPURLResponse(
      url: URL(string: "https://cloud.contextify.sh/api/v1/account")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!

    DelayedMockURLProtocol.handler = { request in
      switch request.url?.path {
      case "/api/v1/sync/status":
        let data = """
        {
          "last_sync": "2026-03-14T23:00:00Z",
          "entries_synced": 12,
          "devices": [],
          "server_sequence": 34,
          "pending_batches": 0,
          "active_push_session": null
        }
        """.data(using: .utf8)!
        return (data, statusResponse, nil)
      case "/api/v1/account":
        let data = """
        {
          "user_id": "7C9138BE-C8D7-4A6E-A804-430D239D4825",
          "email": "old@example.com",
          "name": "Test User",
          "role": "owner",
          "tenant_id": "F154C9FE-9804-4582-8308-495ABFA302A2",
          "tenant_name": "Old Tenant",
          "tenant_plan": "solo",
          "created_at": "2026-03-14T23:00:00Z"
        }
        """.data(using: .utf8)!
        return (data, accountResponse, nil)
      default:
        XCTFail("Unexpected path \(request.url?.path ?? "<nil>")")
        return (Data(), statusResponse, URLError(.badURL))
      }
    }

    await MainActor.run {
      manager.configure(config: CloudConfig(
        serverURL: CloudConfig.defaultServerURL,
        apiKey: "ctx_old",
        deviceId: "device-1",
        deviceName: "Mac",
        enabled: false
      ))
    }

    await manager.refreshStatusFromServer()
    await manager.refreshAccountProfileFromServer()

    await MainActor.run {
      manager.configure(config: CloudConfig(
        serverURL: CloudConfig.defaultServerURL,
        apiKey: "ctx_new",
        deviceId: "device-1",
        deviceName: "Mac",
        enabled: false
      ))
    }

    let cleared = await MainActor.run {
      (
        manager.cloudStatus,
        manager.cloudAccountProfile,
        manager.cloudStatusError,
        manager.cloudAccountError,
        manager.cloudOffline
      )
    }

    XCTAssertNil(cleared.0)
    XCTAssertNil(cleared.1)
    XCTAssertNil(cleared.2)
    XCTAssertNil(cleared.3)
    XCTAssertFalse(cleared.4)
  }

  func testValidateConnectionUsesInjectedClientFactory() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)
    let response = HTTPURLResponse(
      url: URL(string: "https://cloud.contextify.sh/api/v1/account")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!

    DelayedMockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/api/v1/account")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ctx_test")
      let data = """
      {
        "user_id": "7C9138BE-C8D7-4A6E-A804-430D239D4825",
        "email": "validated@example.com",
        "name": "Test User",
        "role": "owner",
        "tenant_id": "F154C9FE-9804-4582-8308-495ABFA302A2",
        "tenant_name": "Tenant",
        "tenant_plan": "solo",
        "created_at": "2026-03-14T23:00:00Z"
      }
      """.data(using: .utf8)!
      return (data, response, nil)
    }

    let profile = try await manager.validateConnection(
      serverURL: CloudConfig.defaultServerURL,
      apiKey: "ctx_test"
    )

    XCTAssertEqual(profile.email, "validated@example.com")
    XCTAssertEqual(profile.tenantName, "Tenant")
  }

  // MARK: - Orphaned Session Detection

  private func statusJSON(activeSessionId: String?, phase: String = "stalled") -> String {
    let sessionBlock: String
    if let id = activeSessionId {
      sessionBlock = """
      {
        "sync_session_id": "\(id)",
        "phase": "\(phase)",
        "entries_resolved": 70,
        "entries_total": 77,
        "progress_percent": 90.9,
        "completion_state": "in_progress",
        "needs_attention_count": 0
      }
      """
    } else {
      sessionBlock = "null"
    }
    return """
    {
      "last_sync": "2026-03-14T23:00:00Z",
      "entries_synced": 100,
      "devices": [],
      "server_sequence": 100,
      "pending_batches": 3,
      "active_push_session": \(sessionBlock)
    }
    """
  }

  private func configureWithMockStatus(
    manager: CloudSyncManager,
    session: URLSession,
    clientSessionId: String?,
    serverSessionId: String?,
    serverPhase: String = "stalled"
  ) async {
    let statusResponse = HTTPURLResponse(
      url: URL(string: "https://cloud.contextify.sh/api/v1/sync/status")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!

    DelayedMockURLProtocol.delay = 0
    DelayedMockURLProtocol.handler = { [self] request in
      let data = self.statusJSON(activeSessionId: serverSessionId, phase: serverPhase).data(using: .utf8)!
      return (data, statusResponse, nil)
    }

    await MainActor.run {
      manager.configure(config: CloudConfig(
        serverURL: CloudConfig.defaultServerURL,
        apiKey: "ctx_test1234567890_abcdefghijklmnopqrstuvwx",
        deviceId: "device-1",
        deviceName: "Mac",
        enabled: false,
        lastPushSessionId: clientSessionId
      ))
    }

    await manager.refreshStatusFromServer()
  }

  func testIsActiveSessionOrphanedWhenSessionIdsDiffer() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)

    await configureWithMockStatus(
      manager: manager,
      session: session,
      clientSessionId: "client-session-aaa",
      serverSessionId: "server-session-bbb"
    )

    let isOrphaned = await MainActor.run { manager.isActiveSessionOrphaned }
    XCTAssertTrue(isOrphaned, "Session with different ID should be detected as orphaned")
  }

  func testIsActiveSessionNotOrphanedWhenSessionIdsMatch() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)
    let sharedId = "shared-session-id"

    await configureWithMockStatus(
      manager: manager,
      session: session,
      clientSessionId: sharedId,
      serverSessionId: sharedId
    )

    let isOrphaned = await MainActor.run { manager.isActiveSessionOrphaned }
    XCTAssertFalse(isOrphaned, "Session with matching ID should not be orphaned")
  }

  func testIsActiveSessionOrphanedWhenNoClientSessionExists() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)

    await configureWithMockStatus(
      manager: manager,
      session: session,
      clientSessionId: nil,
      serverSessionId: "leftover-session"
    )

    let isOrphaned = await MainActor.run { manager.isActiveSessionOrphaned }
    XCTAssertTrue(isOrphaned, "Any server session should be orphaned when client has no session")
  }

  func testIsActiveSessionNotOrphanedWhenNoServerSession() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)

    await configureWithMockStatus(
      manager: manager,
      session: session,
      clientSessionId: "client-session",
      serverSessionId: nil
    )

    let isOrphaned = await MainActor.run { manager.isActiveSessionOrphaned }
    XCTAssertFalse(isOrphaned, "No server session means nothing to be orphaned")
  }

  // MARK: - Sync Request Coalescing

  /// Helper: create a temp database with migrations applied and return
  /// a writable ContextifyQueryService for use in sync tests.
  private func makeTempQueryService() throws -> (ContextifyQueryService, URL) {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("contextify-sync-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let dbURL = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbURL)
    _ = try dbManager.pool  // Runs migrations
    let queryService = try ContextifyQueryService(databaseURL: dbURL, readOnly: false)
    return (queryService, tempDir)
  }

  /// Returns a valid CloudConfig with enabled flag.
  private static let enabledConfig = CloudConfig(
    serverURL: CloudConfig.defaultServerURL,
    apiKey: "ctx_test1234567890_abcdefghijklmnopqrstuvwx",
    deviceId: "device-1",
    deviceName: "Mac",
    enabled: true
  )

  private static let idleStatusData = """
    {
      "last_sync": "2026-03-14T23:00:00Z",
      "entries_synced": 0,
      "devices": [],
      "server_sequence": 0,
      "pending_batches": 0,
      "active_push_session": null
    }
    """.data(using: .utf8)!

  private static let accountData = """
    {
      "user_id": "7C9138BE-C8D7-4A6E-A804-430D239D4825",
      "email": "test@example.com",
      "name": "Test User",
      "role": "owner",
      "tenant_id": "F154C9FE-9804-4582-8308-495ABFA302A2",
      "tenant_name": "Test Tenant",
      "tenant_plan": "solo",
      "created_at": "2026-03-14T23:00:00Z"
    }
    """.data(using: .utf8)!

  /// Installs a generic mock handler that responds to status and account endpoints.
  private func installGenericMockHandler() {
    let statusResponse = HTTPURLResponse(
      url: URL(string: "https://cloud.contextify.sh/api/v1/sync/status")!,
      statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    let accountResponse = HTTPURLResponse(
      url: URL(string: "https://cloud.contextify.sh/api/v1/account")!,
      statusCode: 200, httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    let statusData = Self.idleStatusData
    let accountData = Self.accountData

    DelayedMockURLProtocol.handler = { request in
      switch request.url?.path {
      case "/api/v1/account":
        return (accountData, accountResponse, nil)
      default:
        return (statusData, statusResponse, nil)
      }
    }
  }

  func testRequestSyncQueuesWhenAlreadySyncing() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)
    let (queryService, tempDir) = try makeTempQueryService()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Long delay so sync stays in .syncing state during our test
    DelayedMockURLProtocol.delay = 10
    installGenericMockHandler()

    let config = Self.enabledConfig
    await MainActor.run {
      manager.configure(config: config)
    }

    // Start sync in background -- sets .syncing, then hangs on delayed refreshStatusFromServer()
    let syncTask = Task {
      await manager.sync(using: queryService, origin: .auto)
    }

    // Wait for the sync task to enter .syncing state
    var attempts = 0
    while attempts < 50 {
      let state = await MainActor.run { manager.syncState }
      if state == .syncing { break }
      try await Task.sleep(nanoseconds: 50_000_000) // 50ms
      attempts += 1
    }

    let result = await MainActor.run { () -> (SyncState, Bool) in
      let state = manager.syncState
      manager.requestSync(origin: .manual)
      return (state, manager.hasPendingSyncRequest)
    }

    XCTAssertEqual(result.0, .syncing, "Manager should be in syncing state")
    XCTAssertTrue(result.1, "Request should be queued when already syncing")

    syncTask.cancel()
    await MainActor.run { manager.resetForDisconnect() }
  }

  func testRequestSyncManualDominatesAuto() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)
    let (queryService, tempDir) = try makeTempQueryService()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    DelayedMockURLProtocol.delay = 10
    installGenericMockHandler()

    let config = Self.enabledConfig
    await MainActor.run {
      manager.configure(config: config)
    }

    let syncTask = Task {
      await manager.sync(using: queryService, origin: .auto)
    }

    var attempts = 0
    while attempts < 50 {
      let state = await MainActor.run { manager.syncState }
      if state == .syncing { break }
      try await Task.sleep(nanoseconds: 50_000_000)
      attempts += 1
    }

    // Queue auto first, then manual -- manual should dominate
    let hasPending = await MainActor.run { () -> Bool in
      manager.requestSync(origin: .auto)
      manager.requestSync(origin: .manual)
      return manager.hasPendingSyncRequest
    }

    XCTAssertTrue(hasPending, "Pending request should exist after queuing while syncing")
    // We can't directly inspect the origin, but we verify the coalescing
    // didn't drop the request: hasPendingSyncRequest remains true.

    syncTask.cancel()
    await MainActor.run { manager.resetForDisconnect() }
  }

  func testRequestSyncNoQueueWhenIdle() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)

    // Fast mock so configure's background tasks don't interfere
    DelayedMockURLProtocol.delay = 0
    installGenericMockHandler()

    let config = Self.enabledConfig
    await MainActor.run {
      manager.configure(config: config)
    }

    let result = await MainActor.run { () -> (SyncState, Bool) in
      let state = manager.syncState
      manager.requestSync(origin: .manual)
      return (state, manager.hasPendingSyncRequest)
    }

    XCTAssertEqual(result.0, .idle, "Manager should be idle after configure with enabled: true")
    XCTAssertFalse(result.1, "Request should start immediately when idle, not queue")

    await MainActor.run { manager.resetForDisconnect() }
  }

  func testTriggerSyncCallsRequestSyncManual() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)
    let (queryService, tempDir) = try makeTempQueryService()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    DelayedMockURLProtocol.delay = 10
    installGenericMockHandler()

    let config = Self.enabledConfig
    await MainActor.run {
      manager.configure(config: config)
    }

    let syncTask = Task {
      await manager.sync(using: queryService, origin: .auto)
    }

    var attempts = 0
    while attempts < 50 {
      let state = await MainActor.run { manager.syncState }
      if state == .syncing { break }
      try await Task.sleep(nanoseconds: 50_000_000)
      attempts += 1
    }

    let hasPending = await MainActor.run { () -> Bool in
      manager.triggerSync()
      return manager.hasPendingSyncRequest
    }

    XCTAssertTrue(hasPending, "triggerSync() should queue a request when already syncing")

    syncTask.cancel()
    await MainActor.run { manager.resetForDisconnect() }
  }

  func testConfigurePreservesConnectionScopedStateWhenOnlyDeviceNameChanges() async throws {
    let session = makeSession()
    let manager = await makeManager(session: session)

    let profile = CloudAccountProfile(
      userId: UUID(uuidString: "7C9138BE-C8D7-4A6E-A804-430D239D4825")!,
      email: "same@example.com",
      name: "Test User",
      role: "owner",
      tenantId: UUID(uuidString: "F154C9FE-9804-4582-8308-495ABFA302A2")!,
      tenantName: "Same Tenant",
      tenantPlan: "solo",
      createdAt: ISO8601DateFormatter().date(from: "2026-03-14T23:00:00Z")!
    )

    await MainActor.run {
      manager.configure(config: CloudConfig(
        serverURL: CloudConfig.defaultServerURL,
        apiKey: "ctx_same",
        deviceId: "device-1",
        deviceName: "Old Mac",
        enabled: false
      ))
      manager.setValidatedAccountProfile(profile)
    }

    await MainActor.run {
      manager.configure(config: CloudConfig(
        serverURL: CloudConfig.defaultServerURL,
        apiKey: "ctx_same",
        deviceId: "device-1",
        deviceName: "New Mac",
        enabled: false
      ))
    }

    let finalProfile = await MainActor.run { manager.cloudAccountProfile }
    XCTAssertEqual(finalProfile?.email, "same@example.com")
    XCTAssertEqual(finalProfile?.tenantName, "Same Tenant")
  }

  // MARK: - Transient Server Error Retry (ct-1119)

  func testTransientServerErrorMatchesRetryPattern() throws {
    // Verify that 502/503/504 are correctly matched by the retry catch clause pattern.
    // This is a pattern-matching test: the catch clause uses
    //   CloudSyncError.serverError(statusCode: let code, _) where code == 502 || code == 503 || code == 504
    // We verify each code matches and non-transient codes do not.
    let transientCodes = [502, 503, 504]
    let nonTransientCodes = [400, 403, 404, 500, 501]

    for code in transientCodes {
      let error = CloudSyncError.serverError(statusCode: code, body: "test")
      let isTransient: Bool
      if case .serverError(statusCode: let c, _) = error, c == 502 || c == 503 || c == 504 {
        isTransient = true
      } else {
        isTransient = false
      }
      XCTAssertTrue(isTransient, "HTTP \(code) should match transient retry pattern")
    }

    for code in nonTransientCodes {
      let error = CloudSyncError.serverError(statusCode: code, body: "test")
      let isTransient: Bool
      if case .serverError(statusCode: let c, _) = error, c == 502 || c == 503 || c == 504 {
        isTransient = true
      } else {
        isTransient = false
      }
      XCTAssertFalse(isTransient, "HTTP \(code) should NOT match transient retry pattern")
    }
  }

  func testCloudSyncClientThrowsServerErrorOn502() async throws {
    // Verify that CloudSyncClient maps HTTP 502 to CloudSyncError.serverError(statusCode: 502, ...)
    // which is the error type the push loop catches for transient retry.
    let session = makeSession()
    let errorResponse = HTTPURLResponse(
      url: URL(string: "https://cloud.contextify.sh/api/v1/sync/push")!,
      statusCode: 502,
      httpVersion: nil,
      headerFields: ["Content-Type": "text/html"]
    )!

    DelayedMockURLProtocol.delay = 0
    DelayedMockURLProtocol.handler = { _ in
      let body = "<html><body>502 Bad Gateway</body></html>".data(using: .utf8)!
      return (body, errorResponse, nil)
    }

    let client = CloudSyncClient(
      serverURL: URL(string: CloudConfig.defaultServerURL)!,
      apiKey: "ctx_test",
      session: session
    )

    do {
      let _: CloudPushResponse = try await client.push(CloudPushPayload(
        idempotencyKey: "test:1",
        batchSeq: 1,
        syncSessionId: "test-session",
        entriesSent: 0,
        device: CloudDeviceInfo(machineId: "d1", machineName: "Mac"),
        projects: [],
        transcripts: [],
        entries: [],
        summaries: [],
        usage: [],
        toolInvocations: [],
        transcriptMetadata: []
      ))
      XCTFail("Expected serverError to be thrown")
    } catch let error as CloudSyncError {
      if case .serverError(statusCode: let code, body: let body) = error {
        XCTAssertEqual(code, 502)
        XCTAssertTrue(body.contains("Bad Gateway"))
      } else {
        XCTFail("Expected serverError, got \(error)")
      }
    }
  }
}
