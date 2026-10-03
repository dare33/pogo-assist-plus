import Foundation
import UserNotifications
import PogoReader

/// Posting a `ScanNotification`, shared by the broadcast extension and the app so both use one path. A notification with the same identifier REPLACES the earlier one, so the
/// extension's and the app's fallback for one event can never leave two. The "Finish scan" action of a pause is registered by the app (a category is app-wide).
enum ScanNotifier {
    static func registerCategories() {
        let finish = UNNotificationAction(identifier: ScanNotification.finishActionID, title: "Finish scan", options: [])
        let paused = UNNotificationCategory(identifier: ScanNotification.pausedCategoryID, actions: [finish], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([paused])
    }

    static func post(_ n: ScanNotification, completion: ((Error?) -> Void)? = nil) {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.sound = .default
        if n.offersFinish { content.categoryIdentifier = ScanNotification.pausedCategoryID }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: n.identifier, content: content, trigger: nil)) { completion?($0) }
    }

    /// For the app's fallback: whether a notification with this identifier is already delivered or pending.
    static func exists(_ identifier: String, _ answer: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            if delivered.contains(where: { $0.request.identifier == identifier }) { answer(true); return }
            center.getPendingNotificationRequests { answer($0.contains { $0.identifier == identifier }) }
        }
    }
}
