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
        content.userInfo = ["scan": n.scanId]
        if n.offersFinish { content.categoryIdentifier = ScanNotification.pausedCategoryID }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: n.identifier, content: content, trigger: nil)) { error in
            if error == nil { ReaderSettings.postedNotifications += [n.identifier] }
            completion?(error)
        }
    }

    /// Removes the delivered and the pending pause notifications of `scan` (of every scan when nil): when the scan resumes or finishes and when a new scan starts, so an old
    /// "Finish scan" button is never left on the lock screen.
    static func removePauseNotifications(scan: Int? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { ScanNotification.isPause($0, scan: scan) })
        }
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map { $0.identifier }.filter { ScanNotification.isPause($0, scan: scan) })
        }
    }

    /// For the app's fallback: whether a notification with this identifier was already posted: recorded as handed to the system (so one the person swiped away still counts),
    /// or delivered, or pending.
    static func exists(_ identifier: String, _ answer: @escaping (Bool) -> Void) {
        if ReaderSettings.postedNotifications.contains(identifier) { answer(true); return }
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            if delivered.contains(where: { $0.request.identifier == identifier }) { answer(true); return }
            center.getPendingNotificationRequests { answer($0.contains { $0.identifier == identifier }) }
        }
    }
}
