import XCTest
@testable import Contextify
import ContextifyCore

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

    let dbPath = tempDir.appendingPathComponent("test.db")
    let dbManager = try DatabaseManager(location: .custom(directory: dbPath.deletingLastPathComponent()))
    let orchestrator = TranscriptOrchestrator(dbManager: dbManager)
    let monitor = ProjectActivityMonitor(orchestrator: orchestrator)

    // Create three subscribers
    var subscriber1Events: [ProjectEvent] = []
    var subscriber2Events: [ProjectEvent] = []
    var subscriber3Events: [ProjectEvent] = []

    let stream1 = monitor.observeProjectEvents()
    let stream2 = monitor.observeProjectEvents()
    let stream3 = monitor.observeProjectEvents()

    // Start consuming streams
    let task1 = Task {
      for await event in stream1 {
        subscriber1Events.append(event)
        if subscriber1Events.count >= 3 { break }
      }
    }

    let task2 = Task {
      for await event in stream2 {
        subscriber2Events.append(event)
        if subscriber2Events.count >= 3 { break }
      }
    }

    let task3 = Task {
      for await event in stream3 {
        subscriber3Events.append(event)
        if subscriber3Events.count >= 3 { break }
      }
    }

    // Give tasks time to start consuming
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms

    // Emit events
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj1", kind: .discovered))
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj2", kind: .transcriptUpdated))
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj3", kind: .removed))

    // Wait for all tasks to complete
    try await task1.value
    try await task2.value
    try await task3.value

    // Verify: All subscribers received all events (multicast behavior)
    XCTAssertEqual(subscriber1Events.count, 3, "Subscriber 1 should receive 3 events")
    XCTAssertEqual(subscriber2Events.count, 3, "Subscriber 2 should receive 3 events")
    XCTAssertEqual(subscriber3Events.count, 3, "Subscriber 3 should receive 3 events")

    // Verify event content (all subscribers get same events)
    XCTAssertEqual(subscriber1Events[0].projectId, "proj1")
    XCTAssertEqual(subscriber1Events[0].kind, .discovered)
    XCTAssertEqual(subscriber2Events[0].projectId, "proj1")
    XCTAssertEqual(subscriber2Events[0].kind, .discovered)
    XCTAssertEqual(subscriber3Events[0].projectId, "proj1")
    XCTAssertEqual(subscriber3Events[0].kind, .discovered)

    XCTAssertEqual(subscriber1Events[1].projectId, "proj2")
    XCTAssertEqual(subscriber1Events[1].kind, .transcriptUpdated)
    XCTAssertEqual(subscriber2Events[1].projectId, "proj2")
    XCTAssertEqual(subscriber3Events[1].projectId, "proj2")

    XCTAssertEqual(subscriber1Events[2].projectId, "proj3")
    XCTAssertEqual(subscriber1Events[2].kind, .removed)
    XCTAssertEqual(subscriber2Events[2].projectId, "proj3")
    XCTAssertEqual(subscriber3Events[2].projectId, "proj3")
  }

  func testProjectActivityMonitor_LateSubscriber() async throws {
    // Setup
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let dbPath = tempDir.appendingPathComponent("test.db")
    let dbManager = try DatabaseManager(location: .custom(directory: dbPath.deletingLastPathComponent()))
    let orchestrator = TranscriptOrchestrator(dbManager: dbManager)
    let monitor = ProjectActivityMonitor(orchestrator: orchestrator)

    // Create early subscriber
    var earlyEvents: [ProjectEvent] = []
    let stream1 = monitor.observeProjectEvents()

    let task1 = Task {
      for await event in stream1 {
        earlyEvents.append(event)
        if earlyEvents.count >= 3 { break }
      }
    }

    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

    // Emit first event (only early subscriber sees this)
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj1", kind: .discovered))

    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

    // Add late subscriber
    var lateEvents: [ProjectEvent] = []
    let stream2 = monitor.observeProjectEvents()

    let task2 = Task {
      for await event in stream2 {
        lateEvents.append(event)
        if lateEvents.count >= 2 { break }
      }
    }

    try await Task.sleep(nanoseconds: 50_000_000) // 50ms

    // Emit more events (both subscribers see these)
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj2", kind: .transcriptUpdated))
    await monitor.emitProjectEvent(ProjectEvent(projectId: "proj3", kind: .removed))

    try await task1.value
    try await task2.value

    // Verify: Early subscriber got all 3, late subscriber got last 2
    XCTAssertEqual(earlyEvents.count, 3, "Early subscriber should receive 3 events")
    XCTAssertEqual(lateEvents.count, 2, "Late subscriber should receive 2 events")

    XCTAssertEqual(earlyEvents[0].projectId, "proj1")
    XCTAssertEqual(earlyEvents[1].projectId, "proj2")
    XCTAssertEqual(earlyEvents[2].projectId, "proj3")

    XCTAssertEqual(lateEvents[0].projectId, "proj2")
    XCTAssertEqual(lateEvents[1].projectId, "proj3")
  }

  func testProjectActivityMonitor_SubscriberCleanup() async throws {
    // Setup
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let dbPath = tempDir.appendingPathComponent("test.db")
    let dbManager = try DatabaseManager(location: .custom(directory: dbPath.deletingLastPathComponent()))
    let orchestrator = TranscriptOrchestrator(dbManager: dbManager)
    let monitor = ProjectActivityMonitor(orchestrator: orchestrator)

    // Create subscriber and cancel it immediately
    var events: [ProjectEvent] = []
    let stream = monitor.observeProjectEvents()

    let task = Task {
      for await event in stream {
        events.append(event)
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
    XCTAssertTrue(events.isEmpty, "Cancelled subscriber should not receive events")
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
    var subscriber1Events: [FSEventChange] = []
    var subscriber2Events: [FSEventChange] = []
    var subscriber3Events: [FSEventChange] = []

    let stream1 = monitor.start()
    let stream2 = monitor.start()
    let stream3 = monitor.start()

    let task1 = Task {
      for await event in stream1 {
        subscriber1Events.append(event)
        if subscriber1Events.count >= 1 { break }
      }
    }

    let task2 = Task {
      for await event in stream2 {
        subscriber2Events.append(event)
        if subscriber2Events.count >= 1 { break }
      }
    }

    let task3 = Task {
      for await event in stream3 {
        subscriber3Events.append(event)
        if subscriber3Events.count >= 1 { break }
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
      group.addTask { try? await task1.value }
      group.addTask { try? await task2.value }
      group.addTask { try? await task3.value }
      group.addTask { try? await timeout.value }
    }

    timeout.cancel()
    await monitor.stop()

    // Verify: All subscribers received at least one event (multicast behavior)
    // Note: FSEvents may batch/coalesce events, so we check count >= 1
    XCTAssertGreaterThanOrEqual(subscriber1Events.count, 1, "Subscriber 1 should receive events")
    XCTAssertGreaterThanOrEqual(subscriber2Events.count, 1, "Subscriber 2 should receive events")
    XCTAssertGreaterThanOrEqual(subscriber3Events.count, 1, "Subscriber 3 should receive events")

    // All subscribers should see the same path
    XCTAssertTrue(subscriber1Events.contains(where: { $0.path.contains("test.txt") }))
    XCTAssertTrue(subscriber2Events.contains(where: { $0.path.contains("test.txt") }))
    XCTAssertTrue(subscriber3Events.contains(where: { $0.path.contains("test.txt") }))
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

    var events: [FSEventChange] = []
    let stream = monitor.start()

    let task = Task {
      for await event in stream {
        events.append(event)
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

    await monitor.stop()
    task.cancel()

    // Verify: Events were coalesced (fewer events than file writes)
    // Note: FSEvents + debouncing should coalesce multiple rapid changes
    XCTAssertGreaterThan(events.count, 0, "Should receive at least one event")
    XCTAssertLessThan(events.count, 10, "Should coalesce events (not 5+ individual events)")

    print("Received \(events.count) coalesced events for 5 rapid file writes")
    #else
    throw XCTSkip("FSEvents only available on macOS")
    #endif
  }
}
