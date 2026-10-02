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
    static var autoEndPeriod: Double? {
        get { defaults?.object(forKey: "autoEndPeriod") as? Double }
        set { if let newValue { defaults?.set(newValue, forKey: "autoEndPeriod") } else { defaults?.removeObject(forKey: "autoEndPeriod") } }
    }
}
