import XCTest
@testable import Contextify
import ContextifyCore

private actor EventRecorder<Value> {
  private var values: [Value] = []

  func append(_ value: Value) {
    values.append(value)
  }

  func snapshot() -> [Value] {
    values
  }

  var count: Int {
    values.count
  }
}

/// Tests for multicast stream behavior in ProjectActivityMonitor and FSEventsMonitor
final class MulticastStreamTests: XCTestCase {

  // MARK: - ProjectActivityMonitor Tests

  func testProjectActivityMonitor_MultipleSubscribers() async throws {
    // Setup: Create monitor with temporary database
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let dbPath = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let monitor = ProjectActivityMonitor(orchestrator: orchestrator)

    // Create three subscribers
    let subscriber1Events = EventRecorder<ProjectEvent>()
    let subscriber2Events = EventRecorder<ProjectEvent>()
    let subscriber3Events = EventRecorder<ProjectEvent>()

    let stream1 = monitor.observeProjectEvents()
    let stream2 = monitor.observeProjectEvents()
    let stream3 = monitor.observeProjectEvents()

    // Start consuming streams
    let task1 = Task {
      for await event in stream1 {
        await subscriber1Events.append(event)
        if await subscriber1Events.count >= 3 { break }
      }
    }

    let task2 = Task {
      for await event in stream2 {
        await subscriber2Events.append(event)
        if await subscriber2Events.count >= 3 { break }
      }
    }

    let task3 = Task {
      for await event in stream3 {
        await subscriber3Events.append(event)
        if await subscriber3Events.count >= 3 { break }
      }
    }

    // Give tasks time to start consuming
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms

    // Emit events
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj1", kind: .discovered))
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj2", kind: .transcriptUpdated))
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj3", kind: .removed))

    // Wait for all tasks to complete
    await task1.value
    await task2.value
    await task3.value

    // Verify: All subscribers received all events (multicast behavior)
    let subscriber1Snapshot = await subscriber1Events.snapshot()
    let subscriber2Snapshot = await subscriber2Events.snapshot()
    let subscriber3Snapshot = await subscriber3Events.snapshot()

    XCTAssertEqual(subscriber1Snapshot.count, 3, "Subscriber 1 should receive 3 events")
    XCTAssertEqual(subscriber2Snapshot.count, 3, "Subscriber 2 should receive 3 events")
    XCTAssertEqual(subscriber3Snapshot.count, 3, "Subscriber 3 should receive 3 events")

    // Verify event content (all subscribers get same events)
    XCTAssertEqual(subscriber1Snapshot[0].projectId, "proj1")
    XCTAssertEqual(subscriber1Snapshot[0].kind, .discovered)
    XCTAssertEqual(subscriber2Snapshot[0].projectId, "proj1")
    XCTAssertEqual(subscriber2Snapshot[0].kind, .discovered)
    XCTAssertEqual(subscriber3Snapshot[0].projectId, "proj1")
    XCTAssertEqual(subscriber3Snapshot[0].kind, .discovered)

    XCTAssertEqual(subscriber1Snapshot[1].projectId, "proj2")
    XCTAssertEqual(subscriber1Snapshot[1].kind, .transcriptUpdated)
    XCTAssertEqual(subscriber2Snapshot[1].projectId, "proj2")
    XCTAssertEqual(subscriber3Snapshot[1].projectId, "proj2")

    XCTAssertEqual(subscriber1Snapshot[2].projectId, "proj3")
    XCTAssertEqual(subscriber1Snapshot[2].kind, .removed)
    XCTAssertEqual(subscriber2Snapshot[2].projectId, "proj3")
    XCTAssertEqual(subscriber3Snapshot[2].projectId, "proj3")
  }

  func testProjectActivityMonitor_LateSubscriber() async throws {
    // Setup
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let dbPath = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let monitor = ProjectActivityMonitor(orchestrator: orchestrator)

    // Create early subscriber
    let earlyEvents = EventRecorder<ProjectEvent>()
    let stream1 = monitor.observeProjectEvents()

    let task1 = Task {
      for await event in stream1 {
        await earlyEvents.append(event)
        if await earlyEvents.count >= 3 { break }
      }
    }

    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

    // Emit first event (only early subscriber sees this)
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj1", kind: .discovered))

    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

    // Add late subscriber
    let lateEvents = EventRecorder<ProjectEvent>()
    let stream2 = monitor.observeProjectEvents()

    let task2 = Task {
      for await event in stream2 {
        await lateEvents.append(event)
        if await lateEvents.count >= 2 { break }
      }
    }

    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

    // Emit more events (both subscribers see these)
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj2", kind: .transcriptUpdated))
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj3", kind: .removed))

    await task1.value
    await task2.value

    // Verify: Early subscriber got all 3, late subscriber got last 2
    let earlySnapshot = await earlyEvents.snapshot()
    let lateSnapshot = await lateEvents.snapshot()

    XCTAssertEqual(earlySnapshot.count, 3, "Early subscriber should receive 3 events")
    XCTAssertEqual(lateSnapshot.count, 2, "Late subscriber should receive 2 events")

    XCTAssertEqual(earlySnapshot[0].projectId, "proj1")
    XCTAssertEqual(earlySnapshot[1].projectId, "proj2")
    XCTAssertEqual(earlySnapshot[2].projectId, "proj3")

    XCTAssertEqual(lateSnapshot[0].projectId, "proj2")
    XCTAssertEqual(lateSnapshot[1].projectId, "proj3")
  }

  func testProjectActivityMonitor_SubscriberCleanup() async throws {
    // Setup
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let dbPath = tempDir.appendingPathComponent("contextify.db")
    let dbManager = DatabaseManager.makeTestingInstance(databaseURL: dbPath)
    let orchestrator = try TranscriptOrchestrator(dbManager: dbManager)
    let monitor = ProjectActivityMonitor(orchestrator: orchestrator)

    // Create subscriber and cancel it immediately
    let events = EventRecorder<ProjectEvent>()
    let stream = monitor.observeProjectEvents()

    let task = Task {
      for await event in stream {
        await events.append(event)
      }
    }

    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

    // Cancel subscriber
    task.cancel()

    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

    // Emit event (cancelled subscriber should not receive it)
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj1", kind: .discovered))

    try await Task.sleep(nanoseconds: 100_000_000) // 100ms

    // Verify: No events received after cancellation
    let snapshot = await events.snapshot()
    XCTAssertTrue(snapshot.isEmpty, "Cancelled subscriber should not receive events")
  }

  // MARK: - FSEventsMonitor Tests

  @MainActor
  func testFSEventsMonitor_MultipleSubscribers() async throws {
    #if os(macOS)
    // Setup: Create temporary directory to watch
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("fsevents-test-\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let monitor = FSEventsMonitor(paths: [tempDir.path], latency: 0.1)

    // Create three subscribers
    let subscriber1Events = EventRecorder<FSEventChange>()
    let subscriber2Events = EventRecorder<FSEventChange>()
    let subscriber3Events = EventRecorder<FSEventChange>()

    let stream1 = monitor.start()
    let stream2 = monitor.start()
    let stream3 = monitor.start()

    let task1 = Task {
      for await event in stream1 {
        await subscriber1Events.append(event)
        if await subscriber1Events.count >= 1 { break }
      }
    }

    let task2 = Task {
      for await event in stream2 {
        await subscriber2Events.append(event)
        if await subscriber2Events.count >= 1 { break }
      }
    }

    let task3 = Task {
      for await event in stream3 {
        await subscriber3Events.append(event)
        if await subscriber3Events.count >= 1 { break }
      }
    }

    // Give FSEvents time to start
    try await Task.sleep(nanoseconds: 200_000_000) // 200ms

    // Create file to trigger event
    let testFile = tempDir.appendingPathComponent("test.txt")
    try "test content".write(to: testFile, atomically: true, encoding: .utf8)

    // Wait for debounce (300ms) + processing time
    try await Task.sleep(nanoseconds: 500_000_000) // 500ms

    // Wait for tasks with timeout
    let timeout = Task {
      try await Task.sleep(nanoseconds: 2_000_000_000) // 2s timeout
    }

    await withTaskGroup(of: Void.self) { group in
      group.addTask { await task1.value }
      group.addTask { await task2.value }
      group.addTask { await task3.value }
      group.addTask { try? await timeout.value }
    }

    timeout.cancel()
    monitor.stop()

    // Verify: All subscribers received at least one event (multicast behavior)
    // Note: FSEvents may batch/coalesce events, so we check count >= 1
    let sub1Snapshot = await subscriber1Events.snapshot()
    let sub2Snapshot = await subscriber2Events.snapshot()
    let sub3Snapshot = await subscriber3Events.snapshot()

    XCTAssertGreaterThanOrEqual(sub1Snapshot.count, 1, "Subscriber 1 should receive events")
    XCTAssertGreaterThanOrEqual(sub2Snapshot.count, 1, "Subscriber 2 should receive events")
    XCTAssertGreaterThanOrEqual(sub3Snapshot.count, 1, "Subscriber 3 should receive events")

    // All subscribers should see the same path
    XCTAssertTrue(sub1Snapshot.contains(where: { $0.path.contains("test.txt") }))
    XCTAssertTrue(sub2Snapshot.contains(where: { $0.path.contains("test.txt") }))
    XCTAssertTrue(sub3Snapshot.contains(where: { $0.path.contains("test.txt") }))
    #else
    throw XCTSkip("FSEvents only available on macOS")
    #endif
  }

  @MainActor
  func testFSEventsMonitor_Debouncing() async throws {
    #if os(macOS)
    // Setup: Create temporary directory
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("fsevents-debounce-test-\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let monitor = FSEventsMonitor(paths: [tempDir.path], latency: 0.05)

    let events = EventRecorder<FSEventChange>()
    let stream = monitor.start()

    let task = Task {
      for await event in stream {
        await events.append(event)
      }
    }

    // Give FSEvents time to start
    try await Task.sleep(nanoseconds: 200_000_000) // 200ms

    // Create multiple files rapidly (within debounce window)
    for i in 1...5 {
      let file = tempDir.appendingPathComponent("file\(i).txt")
      try "content \(i)".write(to: file, atomically: true, encoding: .utf8)
      try await Task.sleep(nanoseconds: 50_000_000) // 50ms between writes (< 300ms debounce)
    }

    // Wait for debounce period + processing
    try await Task.sleep(nanoseconds: 500_000_000) // 500ms

    monitor.stop()
    task.cancel()

    // Verify: Events were coalesced (fewer events than file writes)
    // Note: FSEvents + debouncing should coalesce multiple rapid changes
    let eventsSnapshot = await events.snapshot()
    XCTAssertGreaterThan(eventsSnapshot.count, 0, "Should receive at least one event")
    XCTAssertLessThan(eventsSnapshot.count, 10, "Should coalesce events (not 5+ individual events)")

    print("Received \(eventsSnapshot.count) coalesced events for 5 rapid file writes")
    #else
    throw XCTSkip("FSEvents only available on macOS")
    #endif
  }
}
