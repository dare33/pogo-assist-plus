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

    static func write(_ state: BroadcastState) {
        guard let url = stateURL, let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(notificationName as CFString), nil, nil, true)
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
}
