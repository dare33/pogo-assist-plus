import Foundation

/// Makes the times in a report count from the scan's first frame. Scans stored by builds 1 to 4 hold replay logs whose times are the device's
/// presentation timestamps (seconds since the phone started); a time since boot must not be uploaded. Only the uploaded document is changed:
/// the stored log and result are never touched (these are pure functions of their inputs).
///
/// Which values carry a frame time:
/// - replay log, every line kind: `t` (reading "r", swipe tick "t", dropped frame "d", end "e", pause "p", resume "u", stopped by person "s",
///   pause timed out "o", CP-covered note "c"); end "e" and pause "p" also carry `last`, the time the last new Pokémon appeared.
///   `ms` (milliseconds a read took) and `read` (a count) are durations and counts, not times.
/// - result: `frames[].time` of every row and every review entry (the reading times a row was voted from). The frame label ("r12") is an index.
///   `Unmatched.frames` is a count.
/// - ScanPace, StoredPaging and the report's `scan` fields (`measuredPeriod`, `measuredRegularity`, `expectedPeriod`, `joinExtraSeconds`) are
///   differences or settings, not times, and stay. `scanDate` and the app/device fields are wall-clock or hardware facts and stay.
///
/// The origin is the earliest of all of them, so the earliest frame in the scan is 0 and every difference is kept. A log that already starts at 0
/// is returned byte for byte (idempotent).
///
/// A replay line this cannot read as a JSON object (a half-written last line, damage) is left out of the upload and counted, because its text
/// might hold a boot time that cannot be shifted. A line of a kind this does not know is shifted the same way as the known ones (`t` and `last`),
/// so a future line kind cannot carry a boot time through by accident.
public enum ReportTimes {
    public struct Rebased: Equatable {
        public var replayLog: String
        public var result: ScanResult
        /// Replay lines left out because they were not a JSON object.
        public var droppedLines: Int
        /// What was subtracted from every time (0 when the scan already started at 0, or holds no time at all).
        public var shift: Double
    }

    /// The keys of a replay line that hold a frame time.
    static let logTimeKeys = ["t", "last"]

    /// Written precision of the log's times (nine decimals); the subtraction is rounded back to it so no float noise is added.
    private static func tidy(_ x: Double) -> Double { (x * 1e9).rounded() / 1e9 }

    public static func rebase(replayLog: String, result: ScanResult) -> Rebased {
        var objects = [[String: Any]?]()
        var earliest = Double.infinity
        for text in replayLog.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { objects.append(nil); continue }
            for k in logTimeKeys { if let v = number(o[k]) { earliest = min(earliest, v) } }
            objects.append(o)
        }
        for row in result.rows { for f in row.frames { if let t = f.time { earliest = min(earliest, t) } } }
        for entry in result.review { for f in entry.frames { if let t = f.time { earliest = min(earliest, t) } } }
        let shift = earliest.isFinite ? earliest : 0

        var out = [String]()
        var dropped = 0
        let lines = replayLog.split(separator: "\n", omittingEmptySubsequences: true)
        for (i, o) in objects.enumerated() {
            guard var o else { dropped += 1; continue }
            if shift == 0 { out.append(String(lines[i])); continue }      // already scan-relative: the text is kept exactly
            for k in logTimeKeys { if let v = number(o[k]) { o[k] = tidy(v - shift) } }
            guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes]) else { dropped += 1; continue }
            out.append(String(decoding: data, as: UTF8.self))
        }

        var r = result
        if shift != 0 {
            func moved(_ frames: [FrameLabel]) -> [FrameLabel] { frames.map { var f = $0; f.time = f.time.map { tidy($0 - shift) }; return f } }
            for i in r.rows.indices { r.rows[i].frames = moved(r.rows[i].frames) }
            for i in r.review.indices { r.review[i].frames = moved(r.review[i].frames) }
        }
        return Rebased(replayLog: out.isEmpty ? "" : out.joined(separator: "\n") + "\n", result: r, droppedLines: dropped, shift: shift)
    }

    private static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue.isFinite ? n.doubleValue : nil
    }
}
