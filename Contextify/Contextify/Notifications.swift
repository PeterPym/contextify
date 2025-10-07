import Foundation

enum ToastPayloadKey {
    static let message = "message"
}

extension Notification.Name {
    static let contextifyFocusEditor = Notification.Name("contextifyFocusEditor")
    static let contextifyShowToast = Notification.Name("contextifyShowToast")
    static let contextifyTimelineManualRefresh = Notification.Name("contextifyTimelineManualRefresh")
}
