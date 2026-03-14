import XCTest
@testable import ContextifyCore

// MARK: - Model Encoding/Decoding Tests

final class CloudSyncModelsTests: XCTestCase {

  /// Models use explicit CodingKeys with snake_case raw values, so no key
  /// encoding/decoding strategy is needed. A plain encoder/decoder suffices.
  private func makeEncoder() -> JSONEncoder {
    let enc = JSONEncoder()
    enc.outputFormatting = .sortedKeys
    return enc
  }

  private func makeDecoder() -> JSONDecoder {
    JSONDecoder()
  }

  // MARK: - Push Payload Encoding

  func testCloudPushPayloadEncodesAsSnakeCase() throws {
    let payload = CloudPushPayload(
      idempotencyKey: "test-key",
      batchSeq: 1,
      syncSessionId: "sess-123",
      entriesSent: 1,
      device: CloudDeviceInfo(
        machineId: "m-123",
        machineName: "Test Mac",
        os: "macos",
        appVersion: "1.0.0"
      ),
      projects: [
        CloudPushProject(
          id: "p-1",
          name: "MyProject",
          rootPath: "/Users/test/project",
          repoGroupKey: "repo-origin-sha256:def456",
          repoIdentity: "git-common-dir:abc123",
          repoOriginNormalized: "github.com/example/project",
          gitCommonDir: "/Users/test/project/.git",
          isWorktree: true,
          defaultBranch: "main",
          vcsProvider: "github",
          worktreeName: "project-wb1",
          repoName: "project"
        )
      ],
      entries: [
        CloudPushEntry(
          id: "e-1",
          transcriptId: "t-1",
          projectId: "p-1",
          provider: "claude",
          kind: "user",
          timestamp: 1700000000,
          content: "Hello",
          contentSha256: String(repeating: "a", count: 64),
          createdAt: 1700000000,
          updatedAt: 1700000000
        )
      ]
    )

    let data = try makeEncoder().encode(payload)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    // Verify snake_case keys
    XCTAssertNotNil(json["idempotency_key"])
    XCTAssertNotNil(json["batch_seq"])
    XCTAssertNotNil(json["device"])

    let device = json["device"] as! [String: Any]
    XCTAssertEqual(device["machine_id"] as? String, "m-123")
    XCTAssertEqual(device["machine_name"] as? String, "Test Mac")

    let entries = json["entries"] as! [[String: Any]]
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries[0]["transcript_id"] as? String, "t-1")
    XCTAssertEqual(entries[0]["content_sha256"] as? String, String(repeating: "a", count: 64))
    XCTAssertEqual(entries[0]["display_in_timeline"] as? Bool, true)

    let projects = json["projects"] as! [[String: Any]]
    XCTAssertEqual(projects[0]["repo_group_key"] as? String, "repo-origin-sha256:def456")
    XCTAssertEqual(projects[0]["repo_identity"] as? String, "git-common-dir:abc123")
    XCTAssertEqual(projects[0]["repo_origin_normalized"] as? String, "github.com/example/project")
    XCTAssertEqual(projects[0]["is_worktree"] as? Bool, true)
    XCTAssertEqual(projects[0]["default_branch"] as? String, "main")
    XCTAssertEqual(projects[0]["worktree_name"] as? String, "project-wb1")
    XCTAssertEqual(projects[0]["repo_name"] as? String, "project")
  }

  func testCloudPushPayloadDefaultsToEmptyArrays() throws {
    let payload = CloudPushPayload(
      device: CloudDeviceInfo(machineId: "m-1", machineName: "Mac")
    )

    let data = try makeEncoder().encode(payload)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    XCTAssertNil(json["idempotency_key"] as? String)
    XCTAssertEqual((json["entries"] as? [Any])?.count, 0)
    XCTAssertEqual((json["projects"] as? [Any])?.count, 0)
    XCTAssertEqual((json["transcripts"] as? [Any])?.count, 0)
    XCTAssertEqual((json["summaries"] as? [Any])?.count, 0)
    XCTAssertEqual((json["usage"] as? [Any])?.count, 0)
    XCTAssertEqual((json["tool_invocations"] as? [Any])?.count, 0)
    XCTAssertEqual((json["transcript_metadata"] as? [Any])?.count, 0)
  }

  // MARK: - Push Response Decoding

  func testCloudPushResponseDecodesFromSnakeCase() throws {
    let json = """
    {
      "accepted": 5,
      "duplicates_skipped": 2,
      "errors": ["Entry abc: conflict"],
      "sync_token": "tok-123",
      "idempotency_key": "idem-1",
      "sync_session_id": "550e8400-e29b-41d4-a716-446655440000",
      "batch_seq": 7,
      "entries_sent": 500,
      "entries_accepted": 480,
      "entries_duplicates": 20,
      "entries_conflicted": 0,
      "entries_blocked_policy": 0,
      "entries_retriable_failed": 0,
      "entries_resolved": 500,
      "checkpoint_safe": true,
      "completion_state": "in_progress",
      "needs_attention_count": 0,
      "error_codes": [],
      "server_sequence": 42
    }
    """.data(using: .utf8)!

    let response = try makeDecoder().decode(CloudPushResponse.self, from: json)

    XCTAssertEqual(response.accepted, 5)
    XCTAssertEqual(response.duplicatesSkipped, 2)
    XCTAssertEqual(response.errors, ["Entry abc: conflict"])
    XCTAssertEqual(response.syncToken, "tok-123")
    XCTAssertEqual(response.idempotencyKey, "idem-1")
    XCTAssertEqual(response.syncSessionId, "550e8400-e29b-41d4-a716-446655440000")
    XCTAssertEqual(response.batchSeq, 7)
    XCTAssertEqual(response.entriesSent, 500)
    XCTAssertEqual(response.entriesAccepted, 480)
    XCTAssertEqual(response.entriesDuplicates, 20)
    XCTAssertEqual(response.entriesResolved, 500)
    XCTAssertEqual(response.checkpointSafe, true)
    XCTAssertEqual(response.completionState, "in_progress")
    XCTAssertEqual(response.needsAttentionCount, 0)
    XCTAssertEqual(response.errorCodes ?? [], [])
    XCTAssertEqual(response.serverSequence, 42)
  }

  // MARK: - Pull Response Decoding

  func testCloudPullResponseDecodesFullPayload() throws {
    let json = """
    {
      "entries": [{
        "id": "e-1",
        "transcript_id": "t-1",
        "project_id": "p-1",
        "session_id": null,
        "provider": "claude",
        "kind": "assistant",
        "timestamp": 1700000000,
        "content": "Hello from cloud",
        "content_sha256": "\(String(repeating: "b", count: 64))",
        "display_in_timeline": true,
        "git_branch": "main",
        "git_commit": null,
        "cwd": "/Users/test",
        "uploaded_by_user_id": "u-1",
        "uploaded_by_device_id": null,
        "server_sequence": 10,
        "created_at": 1700000000,
        "updated_at": 1700000001
      }],
      "projects": [{"id": "p-1", "name": "TestProj", "root_path": "/test"}],
      "transcripts": [{"id": "t-1", "project_id": "p-1", "file_path": "/test/tx.jsonl", "provider": "claude"}],
      "summaries": [{"entry_id": "e-1", "present_form": "Doing X", "past_form": "Did X", "disposition": "neutral"}],
      "has_more": true,
      "next_cursor": 10,
      "server_sequence": 42
    }
    """.data(using: .utf8)!

    let response = try makeDecoder().decode(CloudPullResponse.self, from: json)

    XCTAssertEqual(response.entries.count, 1)
    XCTAssertEqual(response.entries[0].id, "e-1")
    XCTAssertEqual(response.entries[0].kind, "assistant")
    XCTAssertEqual(response.entries[0].serverSequence, 10)
    XCTAssertEqual(response.entries[0].uploadedByUserId, "u-1")

    XCTAssertEqual(response.projects.count, 1)
    XCTAssertEqual(response.projects[0].name, "TestProj")

    XCTAssertEqual(response.transcripts.count, 1)
    XCTAssertEqual(response.transcripts[0].provider, "claude")

    XCTAssertEqual(response.summaries.count, 1)
    XCTAssertEqual(response.summaries[0].presentForm, "Doing X")

    XCTAssertTrue(response.hasMore)
    XCTAssertEqual(response.nextCursor, 10)
    XCTAssertEqual(response.serverSequence, 42)
  }

  func testCloudPullResponseDecodesEmptyPayload() throws {
    let json = """
    {
      "entries": [],
      "projects": [],
      "transcripts": [],
      "summaries": [],
      "has_more": false,
      "next_cursor": 0,
      "server_sequence": 0
    }
    """.data(using: .utf8)!

    let response = try makeDecoder().decode(CloudPullResponse.self, from: json)

    XCTAssertTrue(response.entries.isEmpty)
    XCTAssertFalse(response.hasMore)
    XCTAssertEqual(response.nextCursor, 0)
  }

  // MARK: - Status Response Decoding

  func testCloudSyncStatusDecodesWithDevices() throws {
    let json = """
    {
      "last_sync": "2025-01-15T10:30:00Z",
      "entries_synced": 150,
      "devices": [
        {"machine_id": "m-1", "machine_name": "Work Mac", "os": "macos", "app_version": "1.3.0"},
        {"machine_id": "m-2", "machine_name": "Home Mac", "os": "macos", "app_version": null}
      ],
      "server_sequence": 99,
      "pending_batches": 1,
      "active_push_session": {
        "sync_session_id": "550e8400-e29b-41d4-a716-446655440000",
        "phase": "initial_upload",
        "entries_resolved": 300,
        "entries_total": 1000,
        "progress_percent": 30.0,
        "throughput_entries_per_min": 2500.0,
        "eta_seconds": 420,
        "checkpoint_safe": true,
        "completion_state": "in_progress",
        "needs_attention_count": 0,
        "last_batch_at": "2026-03-12T00:00:00Z"
      }
    }
    """.data(using: .utf8)!

    let status = try makeDecoder().decode(CloudSyncStatus.self, from: json)

    XCTAssertEqual(status.lastSync, "2025-01-15T10:30:00Z")
    XCTAssertEqual(status.entriesSynced, 150)
    XCTAssertEqual(status.devices.count, 2)
    XCTAssertEqual(status.devices[0].machineId, "m-1")
    XCTAssertEqual(status.devices[0].machineName, "Work Mac")
    XCTAssertEqual(status.devices[1].appVersion, nil)
    XCTAssertEqual(status.serverSequence, 99)
    XCTAssertEqual(status.pendingBatches, 1)
    XCTAssertEqual(status.activePushSession?.phase, "initial_upload")
    XCTAssertEqual(status.activePushSession?.entriesResolved, 300)
    XCTAssertEqual(status.activePushSession?.entriesTotal, 1000)
    XCTAssertEqual(status.activePushSession?.checkpointSafe, true)
  }

  func testCloudSyncStatusDecodesWithNullLastSync() throws {
    let json = """
    {
      "last_sync": null,
      "entries_synced": 0,
      "devices": [],
      "server_sequence": 0
    }
    """.data(using: .utf8)!

    let status = try makeDecoder().decode(CloudSyncStatus.self, from: json)
    XCTAssertNil(status.lastSync)
    XCTAssertEqual(status.entriesSynced, 0)
    XCTAssertTrue(status.devices.isEmpty)
  }

  func testCloudAccountProfileDecodesFromSnakeCase() throws {
    let json = """
    {
      "user_id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "rob@contextify.sh",
      "name": "Rob",
      "role": "owner",
      "tenant_id": "d9428888-122b-11e1-b85c-61cd3cbb3210",
      "tenant_name": "Contextify",
      "tenant_plan": "free",
      "created_at": "2026-03-14T18:00:00Z"
    }
    """.data(using: .utf8)!

    let decoder = makeDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let profile = try decoder.decode(CloudAccountProfile.self, from: json)

    XCTAssertEqual(profile.email, "rob@contextify.sh")
    XCTAssertEqual(profile.name, "Rob")
    XCTAssertEqual(profile.role, "owner")
    XCTAssertEqual(profile.tenantName, "Contextify")
    XCTAssertEqual(profile.tenantPlan, "free")
  }

  // MARK: - CloudConfig Push Cursor Tests

  func testCloudConfigEncodesNewPushCursorFields() throws {
    let config = CloudConfig(
      serverURL: "https://cloud.contextify.sh",
      apiKey: "ctx_test",
      lastPullSequence: 42,
      lastPushTimestamp: 1700000000,
      lastPushEntryId: "entry-abc-123",
      lastPushSessionId: "550e8400-e29b-41d4-a716-446655440000",
      lastPushBatchSeq: 7
    )

    let data = try makeEncoder().encode(config)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    XCTAssertEqual(json["last_push_timestamp"] as? Int, 1700000000)
    XCTAssertEqual(json["last_push_entry_id"] as? String, "entry-abc-123")
    XCTAssertEqual(json["last_push_session_id"] as? String, "550e8400-e29b-41d4-a716-446655440000")
    XCTAssertEqual(json["last_push_batch_seq"] as? Int, 7)
    XCTAssertEqual(json["last_pull_sequence"] as? Int, 42)
  }

  func testCloudConfigDecodesWithPushCursorFields() throws {
    let json = """
    {
      "server_url": "https://cloud.contextify.sh",
      "api_key": "ctx_test",
      "device_id": "",
      "device_name": "",
      "enabled": true,
      "last_pull_sequence": 10,
      "last_push_timestamp": 1700000000,
      "last_push_entry_id": "entry-xyz-789",
      "last_push_session_id": "550e8400-e29b-41d4-a716-446655440000",
      "last_push_batch_seq": 11
    }
    """.data(using: .utf8)!

    let config = try makeDecoder().decode(CloudConfig.self, from: json)

    XCTAssertEqual(config.lastPushTimestamp, 1700000000)
    XCTAssertEqual(config.lastPushEntryId, "entry-xyz-789")
    XCTAssertEqual(config.lastPushSessionId, "550e8400-e29b-41d4-a716-446655440000")
    XCTAssertEqual(config.lastPushBatchSeq, 11)
    XCTAssertEqual(config.lastPullSequence, 10)
  }

  func testCloudConfigDecodesWithoutPushCursorFields() throws {
    // Backward compatibility: existing configs without the new fields
    let json = """
    {
      "server_url": "https://cloud.contextify.sh",
      "api_key": "ctx_test",
      "device_id": "",
      "device_name": "",
      "enabled": true,
      "last_pull_sequence": 5
    }
    """.data(using: .utf8)!

    let config = try makeDecoder().decode(CloudConfig.self, from: json)

    XCTAssertNil(config.lastPushTimestamp)
    XCTAssertNil(config.lastPushEntryId)
    XCTAssertNil(config.lastPushSessionId)
    XCTAssertNil(config.lastPushBatchSeq)
    XCTAssertEqual(config.lastPullSequence, 5)
  }

  func testCloudConfigPushCursorDefaultsToNil() throws {
    let config = CloudConfig(
      serverURL: "https://cloud.contextify.sh",
      apiKey: "ctx_test"
    )

    XCTAssertNil(config.lastPushTimestamp)
    XCTAssertNil(config.lastPushEntryId)
    XCTAssertNil(config.lastPushSessionId)
    XCTAssertNil(config.lastPushBatchSeq)
  }

  func testCloudConfigRoundTripWithPushCursor() throws {
    let original = CloudConfig(
      serverURL: "https://cloud.contextify.sh",
      apiKey: "ctx_test_key",
      deviceId: "device-1",
      deviceName: "Test Mac",
      enabled: true,
      lastPullSequence: 99,
      lastPushTimestamp: 1700500000,
      lastPushEntryId: "e-final",
      lastPushSessionId: "550e8400-e29b-41d4-a716-446655440000",
      lastPushBatchSeq: 123
    )

    let data = try makeEncoder().encode(original)
    let decoded = try makeDecoder().decode(CloudConfig.self, from: data)

    XCTAssertEqual(decoded.serverURL, original.serverURL)
    XCTAssertEqual(decoded.apiKey, original.apiKey)
    XCTAssertEqual(decoded.lastPullSequence, original.lastPullSequence)
    XCTAssertEqual(decoded.lastPushTimestamp, original.lastPushTimestamp)
    XCTAssertEqual(decoded.lastPushEntryId, original.lastPushEntryId)
    XCTAssertEqual(decoded.lastPushSessionId, original.lastPushSessionId)
    XCTAssertEqual(decoded.lastPushBatchSeq, original.lastPushBatchSeq)
  }
}

// MARK: - CloudSyncClient Tests

final class CloudSyncClientTests: XCTestCase {

  // MARK: - Mock URL Protocol

  /// A mock URLProtocol that returns preconfigured responses for testing.
  private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Data, HTTPURLResponse, Error?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
      guard let handler = MockURLProtocol.handler else {
        let error = URLError(.unknown)
        client?.urlProtocol(self, didFailWithError: error)
        return
      }

      let (data, response, error) = handler(request)
      if let error {
        client?.urlProtocol(self, didFailWithError: error)
      } else {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
      }
    }

    override func stopLoading() {}
  }

  private func makeClient(
    serverURL: String = "https://test.contextify.sh",
    apiKey: String = "ctx_test_secret"
  ) -> CloudSyncClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return CloudSyncClient(
      serverURL: URL(string: serverURL)!,
      apiKey: apiKey,
      session: session
    )
  }

  override func tearDown() {
    MockURLProtocol.handler = nil
    super.tearDown()
  }

  // MARK: - Status Tests

  func testStatusReturnsDecodedResponse() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/api/v1/sync/status")
      XCTAssertEqual(request.httpMethod, "GET")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ctx_test_secret")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

      let json = """
      {"last_sync":null,"entries_synced":42,"devices":[],"server_sequence":10}
      """.data(using: .utf8)!
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (json, response, nil)
    }

    let client = makeClient()
    let status = try await client.status()

    XCTAssertEqual(status.entriesSynced, 42)
    XCTAssertEqual(status.serverSequence, 10)
    XCTAssertNil(status.lastSync)
  }

  // MARK: - Push Tests

  func testPushSendsCorrectRequest() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/api/v1/sync/push")
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ctx_test_secret")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

      // Note: request.httpBody is not reliably available via URLProtocol
      // with async URLSession. We verify the body shape in CloudSyncModelsTests
      // and validate the response decoding here.

      let json = """
      {"accepted":1,"duplicates_skipped":0,"errors":[],"sync_token":"tok","idempotency_key":"idem","server_sequence":5}
      """.data(using: .utf8)!
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (json, response, nil)
    }

    let client = makeClient()
    let payload = CloudPushPayload(
      idempotencyKey: "idem",
      device: CloudDeviceInfo(machineId: "m-1", machineName: "Mac")
    )

    let result = try await client.push(payload)
    XCTAssertEqual(result.accepted, 1)
    XCTAssertEqual(result.serverSequence, 5)
  }

  // MARK: - Pull Tests

  func testPullSendsQueryParameters() async throws {
    MockURLProtocol.handler = { request in
      let url = request.url!
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
      let params = components.queryItems ?? []

      XCTAssertEqual(url.path, "/api/v1/sync/pull")
      XCTAssertEqual(request.httpMethod, "GET")
      XCTAssertTrue(params.contains(URLQueryItem(name: "since", value: "50")))
      XCTAssertTrue(params.contains(URLQueryItem(name: "limit", value: "100")))
      XCTAssertTrue(params.contains(URLQueryItem(name: "project_id", value: "proj-1")))

      let json = """
      {"entries":[],"projects":[],"transcripts":[],"summaries":[],"has_more":false,"next_cursor":50,"server_sequence":50}
      """.data(using: .utf8)!
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (json, response, nil)
    }

    let client = makeClient()
    let result = try await client.pull(since: 50, limit: 100, projectId: "proj-1")

    XCTAssertFalse(result.hasMore)
    XCTAssertEqual(result.nextCursor, 50)
  }

  func testPullOmitsProjectIdWhenNil() async throws {
    MockURLProtocol.handler = { request in
      let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
      let params = components.queryItems ?? []

      // project_id should not be present
      XCTAssertFalse(params.contains(where: { $0.name == "project_id" }))
      XCTAssertTrue(params.contains(URLQueryItem(name: "since", value: "0")))

      let json = """
      {"entries":[],"projects":[],"transcripts":[],"summaries":[],"has_more":false,"next_cursor":0,"server_sequence":0}
      """.data(using: .utf8)!
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (json, response, nil)
    }

    let client = makeClient()
    let result = try await client.pull(since: 0)
    XCTAssertEqual(result.nextCursor, 0)
  }

  func testAccountReturnsDecodedResponse() async throws {
    MockURLProtocol.handler = { request in
      XCTAssertEqual(request.url?.path, "/api/v1/account")
      XCTAssertEqual(request.httpMethod, "GET")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ctx_test_secret")

      let json = """
      {
        "user_id":"550e8400-e29b-41d4-a716-446655440000",
        "email":"rob@contextify.sh",
        "name":"Rob",
        "role":"owner",
        "tenant_id":"d9428888-122b-11e1-b85c-61cd3cbb3210",
        "tenant_name":"Contextify",
        "tenant_plan":"free",
        "created_at":"2026-03-14T18:00:00Z"
      }
      """.data(using: .utf8)!
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (json, response, nil)
    }

    let client = makeClient()
    let profile = try await client.account()

    XCTAssertEqual(profile.email, "rob@contextify.sh")
    XCTAssertEqual(profile.tenantName, "Contextify")
    XCTAssertEqual(profile.role, "owner")
  }

  // MARK: - Error Handling Tests

  func testUnauthorizedThrowsCorrectError() async throws {
    MockURLProtocol.handler = { request in
      let json = """
      {"detail":"Invalid API key"}
      """.data(using: .utf8)!
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
      return (json, response, nil)
    }

    let client = makeClient()
    do {
      _ = try await client.status()
      XCTFail("Expected CloudSyncError.unauthorized")
    } catch let error as CloudSyncError {
      if case .unauthorized = error {
        // Expected
      } else {
        XCTFail("Expected .unauthorized, got \(error)")
      }
    }
  }

  func testServerErrorIncludesStatusCodeAndBody() async throws {
    MockURLProtocol.handler = { request in
      let json = """
      {"detail":"Batch too large: 5000 items exceeds limit of 1000."}
      """.data(using: .utf8)!
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 413, httpVersion: nil, headerFields: nil)!
      return (json, response, nil)
    }

    let client = makeClient()
    do {
      _ = try await client.push(CloudPushPayload(
        device: CloudDeviceInfo(machineId: "m-1", machineName: "Mac")
      ))
      XCTFail("Expected CloudSyncError.serverError")
    } catch let error as CloudSyncError {
      if case .serverError(let code, let body) = error {
        XCTAssertEqual(code, 413)
        XCTAssertTrue(body.contains("Batch too large"))
      } else {
        XCTFail("Expected .serverError, got \(error)")
      }
    }
  }

  func testNetworkErrorWrapsUnderlyingError() async throws {
    MockURLProtocol.handler = { request in
      let error = URLError(.notConnectedToInternet)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 0, httpVersion: nil, headerFields: nil)!
      return (Data(), response, error)
    }

    let client = makeClient()
    do {
      _ = try await client.status()
      XCTFail("Expected CloudSyncError.networkError")
    } catch let error as CloudSyncError {
      if case .networkError = error {
        // Expected
      } else {
        XCTFail("Expected .networkError, got \(error)")
      }
    }
  }

  func testDecodingErrorOnMalformedJSON() async throws {
    MockURLProtocol.handler = { request in
      let json = """
      {"unexpected_field": true}
      """.data(using: .utf8)!
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (json, response, nil)
    }

    let client = makeClient()
    do {
      _ = try await client.pull(since: 0)
      XCTFail("Expected CloudSyncError.decodingError")
    } catch let error as CloudSyncError {
      if case .decodingError = error {
        // Expected
      } else {
        XCTFail("Expected .decodingError, got \(error)")
      }
    }
  }

  // MARK: - URL Construction Tests

  func testTrailingSlashInServerURLIsHandled() async throws {
    MockURLProtocol.handler = { request in
      // Should not have double slashes
      XCTAssertEqual(request.url?.absoluteString, "https://test.contextify.sh/api/v1/sync/status")

      let json = """
      {"last_sync":null,"entries_synced":0,"devices":[],"server_sequence":0}
      """.data(using: .utf8)!
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (json, response, nil)
    }

    // Server URL with trailing slash
    let client = makeClient(serverURL: "https://test.contextify.sh/")
    _ = try await client.status()
  }
}
