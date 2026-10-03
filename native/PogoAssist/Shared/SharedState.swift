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
    var replayLines = 0          // lines in replay.jsonl so far (live modes)
    var replayLogTruncated = false   // the replay log hit its size cap and stopped
    var replayLogFailed = false      // a write to the replay log failed: it was switched off (reading was unaffected)
    var endedAtListEnd = false       // the extension ended the scan itself because the end of the list was reached
    var commandPeriod: Double?       // the command's period the scan was started with (nil: paged by hand); what Refine and the review use afterwards
    var paused = false               // the scan is paused at a card that was not clearly the end: reading goes on, the person was told
    var pauseCount = 0               // pauses so far in this scan
    var pausedCard: String?          // "Name CP n" of the card it paused at
    var pausedAt: Date?
    var pauseLimitSeconds: Double?   // what was left of the pause's limit when it began (the 180 s window, or less if an earlier pause of the same stall used up some of the 600 s cap)
    var readCount = 0                // Pokémon read so far (the live grouper's rows), for the progress line
    var storageCount: Int?           // the count the scan was started with (nil: none known, or not a Full scan)
    var eggCount: Int?               // the eggs typed for it (nil: none, the flat allowance applies)
    var pausesAllowed = false        // the scan was started as a Full scan, the only kind that pauses
    /// Counts each pause and each end of a command scan; the notification's identifier carries it, so the extension's notification and the app's fallback are the same one.
    var eventSeq = 0
    /// This scan's id: its start time in whole seconds. Notification identifiers and the finish request carry it.
    var scanId = 0
    /// The person ended the scan ("Finish now", the notification action); `endedAtListEnd` is then false, so it is judged like a stop from the red bar.
    var stoppedByPerson = false
    /// A pause went unanswered and the scan finished at the time limit; `endedAtListEnd` is then false too, so it is never judged Full.
    var stoppedByTimeout = false
}

extension BroadcastState {
    /// Every field falls back to its default, so a state file written by an older build (without the
    /// newer fields) still decodes and its results stay visible after an update.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decodeIfPresent([LiveRow].self, forKey: .rows) ?? rows
        framesSeen = try c.decodeIfPresent(Int.self, forKey: .framesSeen) ?? framesSeen
        framesRead = try c.decodeIfPresent(Int.self, forKey: .framesRead) ?? framesRead
        framesDropped = try c.decodeIfPresent(Int.self, forKey: .framesDropped) ?? framesDropped
        meanMsPerFrame = try c.decodeIfPresent(Double.self, forKey: .meanMsPerFrame) ?? meanMsPerFrame
        footprintMB = try c.decodeIfPresent(Double.self, forKey: .footprintMB) ?? footprintMB
        peakFootprintMB = try c.decodeIfPresent(Double.self, forKey: .peakFootprintMB) ?? peakFootprintMB
        lowestAvailableMB = try c.decodeIfPresent(Double.self, forKey: .lowestAvailableMB)
        started = try c.decodeIfPresent(Date.self, forKey: .started) ?? started
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? updated
        finished = try c.decodeIfPresent(Bool.self, forKey: .finished) ?? finished
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? mode
        skippedLowMemory = try c.decodeIfPresent(Int.self, forKey: .skippedLowMemory) ?? skippedLowMemory
        savedFrames = try c.decodeIfPresent(Int.self, forKey: .savedFrames) ?? savedFrames
        savedFiles = try c.decodeIfPresent(Int.self, forKey: .savedFiles) ?? savedFiles
        savedMB = try c.decodeIfPresent(Double.self, forKey: .savedMB) ?? savedMB
        replayLines = try c.decodeIfPresent(Int.self, forKey: .replayLines) ?? replayLines
        replayLogTruncated = try c.decodeIfPresent(Bool.self, forKey: .replayLogTruncated) ?? replayLogTruncated
        replayLogFailed = try c.decodeIfPresent(Bool.self, forKey: .replayLogFailed) ?? replayLogFailed
        endedAtListEnd = try c.decodeIfPresent(Bool.self, forKey: .endedAtListEnd) ?? endedAtListEnd
        commandPeriod = try c.decodeIfPresent(Double.self, forKey: .commandPeriod)
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        pauseCount = try c.decodeIfPresent(Int.self, forKey: .pauseCount) ?? 0
        pausedCard = try c.decodeIfPresent(String.self, forKey: .pausedCard)
        pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
        pauseLimitSeconds = try c.decodeIfPresent(Double.self, forKey: .pauseLimitSeconds)
        readCount = try c.decodeIfPresent(Int.self, forKey: .readCount) ?? 0
        storageCount = try c.decodeIfPresent(Int.self, forKey: .storageCount)
        eggCount = try c.decodeIfPresent(Int.self, forKey: .eggCount)
        pausesAllowed = try c.decodeIfPresent(Bool.self, forKey: .pausesAllowed) ?? false
        eventSeq = try c.decodeIfPresent(Int.self, forKey: .eventSeq) ?? 0
        scanId = try c.decodeIfPresent(Int.self, forKey: .scanId) ?? 0
        stoppedByPerson = try c.decodeIfPresent(Bool.self, forKey: .stoppedByPerson) ?? false
        stoppedByTimeout = try c.decodeIfPresent(Bool.self, forKey: .stoppedByTimeout) ?? false
    }
}

/// The app group container and the Darwin notification the extension posts after each write.
/// The group id is read from Info.plist (`AppGroupID`, set from Config/Identifiers.xcconfig).
enum SharedStore {
    static var groupID: String { (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.com.dare33.pogoassist" }
    static var notificationName: String { groupID + ".state-changed" }

    /// The app group's folder. In an unsigned simulator build the group does not exist; there, and only there, the app's
    /// Documents folder stands in so the whole flow can be driven (the broadcast extension cannot run in the simulator).
    static var containerURL: URL? {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) { return url }
        #if targetEnvironment(simulator)
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("AppGroupFallback", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #else
        return nil
        #endif
    }

    static var stateURL: URL? {
        containerURL?.appendingPathComponent("state.json")
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    /// The app group container exists. False when the entitlement or the group is not set up (signing).
    static var containerAvailable: Bool {
        containerURL != nil
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
        if let url = replayURL { try? FileManager.default.removeItem(at: url) }
    }

    /// Where "save crops" mode writes (and the app reads and then empties).
    static var cropsURL: URL? {
        containerURL?.appendingPathComponent("crops", isDirectory: true)
    }

    /// The extension's replay log: one JSON line per reading, swipe tick and dropped frame (live modes).
    static var replayURL: URL? {
        containerURL?.appendingPathComponent("replay.jsonl")
    }

    /// The app's result of reading the saved crops (shareable).
    static var deferredURL: URL? {
        containerURL?.appendingPathComponent("deferred.json")
    }
}
