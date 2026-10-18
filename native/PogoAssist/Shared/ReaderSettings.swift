import Foundation
import PogoReader

/// The reader mode, chosen in the app before the broadcast starts and read by the extension at
/// `broadcastStarted`; kept in the app group's defaults.
enum ReaderSettings {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedStore.groupID) }

    static var mode: ReaderMode {
        get { defaults?.string(forKey: ReaderMode.defaultsKey).flatMap(ReaderMode.init(rawValue:)) ?? .accurate }
        set { defaults?.set(newValue.rawValue, forKey: ReaderMode.defaultsKey) }
    }

    /// The command's period in seconds when the next scan is paged by a Pogo scan command, else nil (paging by hand): the extension ends such
    /// a scan by itself when the list ends (`EndOfListDetector`). Never set for hand paging, because a person may pause on a Pokémon.
    /// The storage count the person gave (nil: none): the extension finishes at once when the Pokémon read reach it, and otherwise pauses.
    static var storageCount: Int? {
        get { (defaults?.object(forKey: "storageCount") as? Int).flatMap { $0 > 0 ? $0 : nil } }
        set { if let newValue { defaults?.set(newValue, forKey: "storageCount") } else { defaults?.removeObject(forKey: "storageCount") } }
    }
    /// The eggs the person typed for a Full scan (nil: none, the flat allowance applies). Captured by the extension at broadcast start with the count.
    static var eggCount: Int? {
        get { (defaults?.object(forKey: "eggCount") as? Int).flatMap { StorageCountRules.validEggs($0) } }
        set { if let newValue { defaults?.set(newValue, forKey: "eggCount") } else { defaults?.removeObject(forKey: "eggCount") } }
    }
    /// Whether the next scan is a Full scan (the only kind that may pause). Absent means not full: a scan then ends exactly as it did before the pause existed.
    static var scanIsFull: Bool {
        get { defaults?.bool(forKey: "scanIsFull") ?? false }
        set { defaults?.set(newValue, forKey: "scanIsFull") }
    }
    /// The command sizes ("Pogo scan N"), from the app's one table, for the pause notification's suggested command.
    static var commandSizes: [Int] {
        get { (defaults?.array(forKey: "commandSizes") as? [Int]) ?? [] }
        set { defaults?.set(newValue, forKey: "commandSizes") }
    }
    /// Set by the app ("Finish now", the notification's "End scan" action) to the id of the scan the person means (`BroadcastState.scanId`); the extension checks it on its
    /// one-second heartbeat and honours it for the running scan while it is paused, and keeps it up to `ScanNotification.finishRequestGraceSeconds` while the scan is not paused (see `finishRequestVerdict`); another scan's or an older request is dropped. Cleared at broadcast start and when honoured or dropped.
    static var finishRequestedScan: Int? {
        get { (defaults?.object(forKey: "finishRequestedScan") as? Int).flatMap { $0 != 0 ? $0 : nil } }
        set { if let newValue { defaults?.set(newValue, forKey: "finishRequestedScan") } else { defaults?.removeObject(forKey: "finishRequestedScan") } }
    }

    /// The identifiers of the last few notifications that were handed to the system (by the extension or the app). The app's fallback does not post one of these again: a
    /// notification the person has swiped away is no longer delivered, but it was posted.
    static var postedNotifications: [String] {
        get { (defaults?.array(forKey: "postedNotifications") as? [String]) ?? [] }
        set { defaults?.set(Array(newValue.suffix(8)), forKey: "postedNotifications") }
    }

    /// When the finish request was made (seconds since 1970), so a request for a scan that is not paused at that moment can wait a short while for the next pause.
    static var finishRequestedAt: Double? {
        get { defaults?.object(forKey: "finishRequestedAt") as? Double }
        set { if let newValue { defaults?.set(newValue, forKey: "finishRequestedAt") } else { defaults?.removeObject(forKey: "finishRequestedAt") } }
    }
    /// The one way to ask: the scan and the moment.
    static func requestFinish(scan: Int) { finishRequestedAt = Date().timeIntervalSince1970; finishRequestedScan = scan }
    static func clearFinishRequest() { finishRequestedScan = nil; finishRequestedAt = nil }

    static var autoEndPeriod: Double? {
        get { defaults?.object(forKey: "autoEndPeriod") as? Double }
        set { if let newValue { defaults?.set(newValue, forKey: "autoEndPeriod") } else { defaults?.removeObject(forKey: "autoEndPeriod") } }
    }
}
