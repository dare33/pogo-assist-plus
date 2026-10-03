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
    /// The command sizes ("Pogo scan N"), from the app's one table, for the pause notification's suggested command.
    static var commandSizes: [Int] {
        get { (defaults?.array(forKey: "commandSizes") as? [Int]) ?? [] }
        set { defaults?.set(newValue, forKey: "commandSizes") }
    }
    /// Set by the app ("Finish now", the notification's "Finish scan" action) to the id of the scan the person means (`BroadcastState.scanId`); the extension checks it on its
    /// one-second heartbeat and honours it only for the running scan while it is paused. Cleared at broadcast start, and by the extension whenever it is not honoured.
    static var finishRequestedScan: Int? {
        get { (defaults?.object(forKey: "finishRequestedScan") as? Int).flatMap { $0 != 0 ? $0 : nil } }
        set { if let newValue { defaults?.set(newValue, forKey: "finishRequestedScan") } else { defaults?.removeObject(forKey: "finishRequestedScan") } }
    }

    static var autoEndPeriod: Double? {
        get { defaults?.object(forKey: "autoEndPeriod") as? Double }
        set { if let newValue { defaults?.set(newValue, forKey: "autoEndPeriod") } else { defaults?.removeObject(forKey: "autoEndPeriod") } }
    }
}
