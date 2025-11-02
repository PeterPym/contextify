import Foundation

enum ToastPayloadKey {
    static let message = "message"
    static let duration = "duration"  // Optional TimeInterval, 0 for persistent
}

extension Notification.Name {
    static let contextifyShowToast = Notification.Name("contextifyShowToast")
    static let contextifyTimelineManualRefresh = Notification.Name("contextifyTimelineManualRefresh")
}
