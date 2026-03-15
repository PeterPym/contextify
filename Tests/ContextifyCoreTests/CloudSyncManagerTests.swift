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
}
