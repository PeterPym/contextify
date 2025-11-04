import Foundation
import OSLog

@MainActor
final class TimelineIntegration {
    static let shared = TimelineIntegration()

    private let log = Logger(subsystem: "dev.contextify", category: "TimelineIntegration")
    private var observers: [NSObjectProtocol] = []
    private var isActive = false

    private init() {}

    func startMonitoring(projectId: String) {
        guard !isActive else { return }
        log.info("Timeline integration starting")
        ConversationMonitor.shared.startMonitoring(projectId: projectId)
        // Flip active only after the monitor reports started (same runloop is fine)
        if ConversationMonitor.shared.isMonitoring {
            isActive = true
            registerNotifications()
            ConversationMonitor.shared.requestImmediateRefresh(trigger: .manualHotkey)
        } else {
            log.warning("TimelineIntegration: monitor did not enter isMonitoring; deferring activation")
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
