import Foundation
import PogoReader

/// What the broadcast extension writes to the app group and the app reads: the live rows and the
/// run's numbers (frames, timing, memory). One small JSON file, replaced atomically after each change.
struct BroadcastState: Codable, Equatable {
    var rows: [LiveRow] = []
    var framesSeen = 0          // frames offered at the 5 fps rate
    var framesRead = 0          // frames the reader finished
    var framesDropped = 0       // offered while the previous frame was still being read
    var meanMsPerFrame = 0.0
    var footprintMB = 0.0       // phys_footprint now
    var peakFootprintMB = 0.0
    var lowestAvailableMB: Double?   // lowest os_proc_available_memory seen
    var started = Date()
    var updated = Date()
    var finished = false
    var mode = ReaderMode.accurate.rawValue   // the reader mode the extension started in
    var skippedLowMemory = 0    // frames where Vision was skipped because little memory was left
    var savedFrames = 0         // "save crops" mode: frames written
    var savedFiles = 0
    var savedMB = 0.0
}

/// The app group container and the Darwin notification the extension posts after each write.
/// The group id is read from Info.plist (`AppGroupID`, set from Config/Identifiers.xcconfig).
enum SharedStore {
    static var groupID: String { (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.com.dare33.pogoassist" }
    static var notificationName: String { groupID + ".state-changed" }

    static var stateURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appendingPathComponent("state.json")
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    /// The app group container exists. False when the entitlement or the group is not set up (signing).
    static var containerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    /// Replace the state file atomically and post the notification. Returns false when it could not be written.
    @discardableResult
    static func write(_ state: BroadcastState) -> Bool {
        guard let url = stateURL, let data = try? encoder.encode(state) else { return false }
        do { try data.write(to: url, options: .atomic) } catch { return false }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(notificationName as CFString), nil, nil, true)
        return true
    }

    static func read() -> BroadcastState? {
        guard let url = stateURL, let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(BroadcastState.self, from: data)
    }

    static func clear() {
        if let url = stateURL { try? FileManager.default.removeItem(at: url) }
    }

    /// Where "save crops" mode writes (and the app reads and then empties).
    static var cropsURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appendingPathComponent("crops", isDirectory: true)
    }

    /// The app's result of reading the saved crops (shareable).
    static var deferredURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?.appendingPathComponent("deferred.json")
    }
}
