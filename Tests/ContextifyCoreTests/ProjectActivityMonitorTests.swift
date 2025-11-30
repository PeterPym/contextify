import XCTest
@testable import ContextifyCore

final class ProjectActivityMonitorTests: XCTestCase {
  var tempDir: URL!
  var dbManager: DatabaseManager!
  var orchestrator: TranscriptOrchestrator!
  var monitor: ProjectActivityMonitor!

  override func setUp() async throws {
    try await super.setUp()

    // Create temporary directory for test database
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Set up database and orchestrator
    // Note: TranscriptOrchestrator.init accesses dbManager.pool which runs migrations
    let dbPath = tempDir.appendingPathComponent("test.db")
    dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    monitor = ProjectActivityMonitor(orchestrator: orchestrator)
  }

  override func tearDown() async throws {
    try await super.tearDown()

    // Clean up temp directory
    if let tempDir = tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
  }

  // MARK: - Event Emission Tests

  func testSimulateTranscriptDiscovery_NewProject_EmitsDiscoveredEvent() async throws {
    // Given: A path that doesn't exist in the database
    let projectPath = "/test/new-project-\(UUID().uuidString)"

    // When: We simulate transcript discovery
    let eventKind = try await monitor.simulateTranscriptDiscovery(projectPath: projectPath)

    // Then: The event should be .discovered for a new project
    XCTAssertEqual(eventKind, .discovered, "New project should emit .discovered event")
  }

  func testSimulateTranscriptDiscovery_ExistingProject_EmitsTranscriptUpdatedEvent() async throws {
    // Given: A project that already exists in the database
    let projectPath = "/test/existing-project-\(UUID().uuidString)"

    // Create the project first
    _ = try orchestrator.getOrCreateProject(name: "Existing", rootPath: projectPath)

    // When: We simulate transcript discovery for the same path
    let eventKind = try await monitor.simulateTranscriptDiscovery(projectPath: projectPath)

    // Then: The event should be .transcriptUpdated for an existing project
    XCTAssertEqual(eventKind, .transcriptUpdated, "Existing project should emit .transcriptUpdated event")
  }

  func testSimulateTranscriptDiscovery_EventStreamReceivesCorrectEvent() async throws {
    // Given: A subscription to project events
    let projectPath = "/test/stream-test-\(UUID().uuidString)"

    // Set up event observer
    let eventStream = monitor.observeProjectEvents()

    // Use actor to safely collect events across concurrency boundaries
    actor EventCollector {
      var events: [ProjectEvent] = []
      func append(_ event: ProjectEvent) { events.append(event) }
      func getEvents() -> [ProjectEvent] { events }
    }
    let collector = EventCollector()

    // Start collecting events in background
    let collectTask = Task {
      for await event in eventStream {
        await collector.append(event)
        if await collector.getEvents().count >= 1 {
          break  // Only need one event for this test
        }
      }
    }

    // Small delay to ensure observer is registered
    try await Task.sleep(for: .milliseconds(50))

    // When: We simulate transcript discovery
    _ = try await monitor.simulateTranscriptDiscovery(projectPath: projectPath)

    // Wait for event collection with timeout
    let timeoutTask = Task {
      try await Task.sleep(for: .seconds(2))
      collectTask.cancel()
    }

    await collectTask.value
    timeoutTask.cancel()

    // Then: We should have received a .discovered event
    let receivedEvents = await collector.getEvents()
    XCTAssertEqual(receivedEvents.count, 1, "Should receive exactly one event")
    XCTAssertEqual(receivedEvents.first?.kind, .discovered, "Event should be .discovered for new project")
  }

  func testSimulateTranscriptDiscovery_SecondCall_EmitsTranscriptUpdated() async throws {
    // Given: A path
    let projectPath = "/test/repeat-test-\(UUID().uuidString)"

    // When: We simulate transcript discovery twice
    let firstEventKind = try await monitor.simulateTranscriptDiscovery(projectPath: projectPath)
    let secondEventKind = try await monitor.simulateTranscriptDiscovery(projectPath: projectPath)

    // Then: First should be .discovered, second should be .transcriptUpdated
    XCTAssertEqual(firstEventKind, .discovered, "First call should emit .discovered")
    XCTAssertEqual(secondEventKind, .transcriptUpdated, "Second call should emit .transcriptUpdated")
  }
}
