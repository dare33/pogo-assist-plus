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
}
