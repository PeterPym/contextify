import Foundation
import OSLog

@MainActor
final class TimelineIntegration {
    static let shared = TimelineIntegration()

    private let log = Logger(subsystem: "dev.contextify", category: "TimelineIntegration")
    private var observers: [NSObjectProtocol] = []
    private var isActive = false

    private init() {}

    func startMonitoring(projectId: String) async {
        guard !isActive else { return }
        log.info("Timeline integration starting")

        let notificationName = Notification.Name.conversationMonitoringDidStart
        ConversationMonitor.shared.startMonitoring(projectId: projectId)

        // Await monitor start (with timeout to avoid hangs)
        do {
            try await withTimeout(seconds: 3) {
                for await _ in NotificationCenter.default.notifications(named: notificationName) {
                    break
                }
            }
        } catch {
            log.warning("TimelineIntegration: monitor did not start within timeout; continuing defensively")
        }

        isActive = true
        registerNotifications()
        ConversationMonitor.shared.requestImmediateRefresh(trigger: .manualHotkey)
    }

    // Helper for timeout-bounded async operations
    private func withTimeout(seconds: Double, operation: @escaping @Sendable () async -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            try await group.next()
            group.cancelAll()
        }
    }

    func stopMonitoring() {
        guard isActive else { return }
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
        observers.removeAll()
        ConversationMonitor.shared.stopMonitoring()
        isActive = false
    }

    func requestManualRefresh(trigger: TimelineRefreshTrigger) {
        ConversationMonitor.shared.requestImmediateRefresh(trigger: trigger)
    }

    private func registerNotifications() {
        let manual = NotificationCenter.default.addObserver(
            forName: .contextifyTimelineManualRefresh,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestManualRefresh(trigger: .manualHotkey)
            }
        }

        observers.append(manual)
    }
}
