import Foundation
import PogoReader

/// Makes the files a person shares out of the app count their times from an origin inside the file, as the uploaded report does (`ReportTimes`). Scans stored by
/// builds 1 to 4 hold times that are the device's presentation timestamps (seconds since the phone started); that must not leave the phone through the share
/// sheet either. Pure functions from bytes to bytes: the stored files are never rewritten, the app writes the returned bytes to the temporary folder.
///
/// Origins. A saved scan's result and replay log are one scan, so they share ONE origin, the earliest time across both (`ReportTimes.rebase`'s rule, called here,
/// not copied), and agree with each other. The Diagnostics files can come from different runs and builds (`deferred.json` survives a new broadcast, `replay.jsonl`
/// is not cleared by a "Save crops" run, a sample load writes a boot-timed log), so each of the three is shifted on its OWN earliest time, independently: their
/// times cannot be compared with each other. Applying this to its own output changes nothing (the earliest time is then 0). When a file's earliest time is
/// exactly 0 it comes back as the bytes it came in (a replay log with a dropped line cannot: that line is left out). A new build's log can start a fraction of a
/// second after 0 (its first logged line, not its first frame), and that fraction is subtracted too.
///
/// Which values carry a frame time, by file:
/// - Saved scan result (`BoxStore.StoredScan`, `<id>.json`): `rows[].frames[].time` and `review[].frames[].time`; the bars-split text in each `refineChanges` string
///   (its "at 13056.7 s" cut times; `ReportTimes.barsChange`). The file's text is edited in place (`JSONTextEdit`): only those values are rewritten and every other
///   byte stays as stored. It is not decoded and encoded again (which normalises fields), nor parsed and written out again (Foundation can turn a 17-digit number into
///   its neighbouring Double). It must still decode as a `StoredScan` with a schema no newer than this build's
///   (a newer schema could hold a time this list does not know). Checked and left alone, as the `ReportTimes` header lists: `unmatched` (a frame label, a count, CPs
///   and positions), `paging` (a period and a join allowance, settings), `reviewActions` (what the person answered: names, CPs, counts; `ScanReportBuilder.reviewLines`
///   and `BoxMerge`'s line builders print no time), `scanDate`, `savedAt`, `lastReread`, `reportSentAt` (wall-clock dates), `reportHash`, `sourceSignature` (the
///   replay file's size and its modification date in milliseconds since 1970, a wall-clock fact, not a frame time), `id`, `account`, `source`, `kind`, `pass`,
///   `schema`, `storageCount`. The row fields `merged`, `clip`, `shadow`, `dynamax`, `gigantamax`, `lucky`, `details` hold no time. The scan's pace (`ScanPace`)
///   is not stored; where the report derives it, it is a difference.
/// - Replay log, every line: `t` and `last` (`ReportTimes.logTimeKeys`); `ms` and `read` are a duration and a count. A line that is not a JSON object, or whose `t`
///   or `last` is present and not a finite number, is left out and counted (`ReportTimes.rebase`).
/// - Diagnostics state file (`BroadcastState`, `state.json`): `rows[].firstTime` and `rows[].lastTime` (the live grouper's first and last reading of each row).
///   Checked and left alone: `rows[].firstFrame`/`lastFrame` (frame labels, an index), `started`, `updated`, `pausedAt`, `cpCoveredSince` (wall-clock dates),
///   `scanId` (the start date in whole seconds since 1970), `commandPeriod`, `pauseLimitSeconds`, `meanMsPerFrame` (periods, limits and durations), and the
///   counts, memory figures, names and flags. Edited in place like the result.
/// - Diagnostics saved-crop result (`DeferredResult`, `deferred.json`): `rows[].firstTime` and `rows[].lastTime` (the same `LiveRow`); `seconds` is how long the read
///   took, `frames` a count, `peakFootprintMB` a size.
///
/// A file that cannot be read as the shape it should have (not JSON, not the stored scan's format, a schema number newer than this build's, a time that is not a
/// number) is not shared at all: it comes back as `nil` and its name is in `unreadable`. One that was read but could not be written out again comes back as `nil`
/// with its name in `notPrepared`. Neither is ever returned as it came. A new time-carrying key must be added to `rowTimeKeys` (state and saved crops), to
/// `frameTimeKey` (the result) or to `ReportTimes` (the log) and to the list above.
public enum ShareTimes {
    public enum Part: String, Equatable { case result, replayLog, state, deferred }

    /// A saved scan's files, shifted on one origin. `result` is nil when the result could not be read or prepared; `replayLog` is nil when none was given or it could not be read.
    public struct Saved: Equatable {
        public var result: Data?
        public var replayLog: String?
        /// Replay lines left out because they were damaged (`ReportTimes.rebase`).
        public var droppedLines: Int
        public var shift: Double
        public var unreadable: [Part]
        public var notPrepared: [Part]
    }

    /// The Diagnostics screen's three files, each shifted on its own origin (`shifts`: what was subtracted from each file that was shared).
    public struct Diagnostics: Equatable {
        public var state: Data?
        public var deferred: Data?
        public var replayLog: String?
        public var droppedLines: Int
        public var shifts: [Part: Double]
        public var unreadable: [Part]
        public var notPrepared: [Part]
    }

    /// The keys of a state or saved-crop row that hold a frame time.
    static let rowTimeKeys = ["firstTime", "lastTime"]
    /// The key of a result frame that holds a frame time.
    static let frameTimeKey = "time"

    /// A saved scan's result file and its replay log, as the files on disk (`BoxStore.files`). `replayLog` is nil when the scan has none.
    public static func savedScan(result: Data, replayLog: Data?) -> Saved {
        var unreadable = [Part](), notPrepared = [Part]()
        var scan = decodeStored(result)
        var tree = scan == nil ? nil : (try? JSONSerialization.jsonObject(with: result)) as? [String: Any]
        if let t = tree, !resultTimesAreNumbers(t) { tree = nil }
        if tree == nil { scan = nil; unreadable.append(.result) }
        var logText: String?
        if let replayLog { if let t = String(data: replayLog, encoding: .utf8) { logText = t } else { unreadable.append(.replayLog) } }

        let scanResult = scan.map { ScanResult(rows: $0.rows, review: $0.review, unmatched: $0.unmatched) } ?? ScanResult(rows: [], review: [], unmatched: [])
        let r = ReportTimes.rebase(replayLog: logText ?? "", result: scanResult, refineChanges: [])
        let log = logText.map { r.droppedLines == 0 && r.shift == 0 ? $0 : r.replayLog }

        var out: Data?
        if let tree {
            if r.shift == 0 { out = result } else {
                out = JSONTextEdit(numbers: ["rows/[]/frames/[]/time", "review/[]/frames/[]/time"], transform: { ReportTimes.tidy($0 - r.shift) },
                                   strings: ["refineChanges/[]"], rewrite: { ReportTimes.barsChange($0, shift: r.shift) }).apply(to: result)
                if out == nil { notPrepared.append(.result) }
            }
        }
        return Saved(result: out, replayLog: log, droppedLines: r.droppedLines, shift: r.shift, unreadable: unreadable, notPrepared: notPrepared)
    }

    /// An unsaved scan's replay log on its own (the review's share when sending fails). Nil when it is not text.
    public static func replayLog(_ data: Data) -> (text: String, droppedLines: Int, shift: Double)? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let r = ReportTimes.rebase(replayLog: text, result: ScanResult(rows: [], review: [], unmatched: []))
        return (r.droppedLines == 0 && r.shift == 0 ? text : r.replayLog, r.droppedLines, r.shift)
    }

    /// The state file, the saved-crop result and the replay log of the Diagnostics screen, each on its own origin. Each is optional (a file that does not exist).
    public static func diagnostics(state: Data?, deferred: Data?, replayLog: Data?) -> Diagnostics {
        var unreadable = [Part](), notPrepared = [Part](), shifts = [Part: Double]()
        func rows(_ data: Data?, _ part: Part) -> Data? {
            guard let data else { return nil }
            guard let parsed = rowTimes(data) else { unreadable.append(part); return nil }
            let shift = parsed.times.min() ?? 0
            shifts[part] = shift
            if shift == 0 { return data }
            if let d = JSONTextEdit(numbers: rowTimeKeys.map { "rows/[]/\($0)" } .reduce(into: Set<String>()) { $0.insert($1) }, transform: { ReportTimes.tidy($0 - shift) }).apply(to: data) { return d }
            notPrepared.append(part); return nil
        }
        let s = rows(state, .state), d = rows(deferred, .deferred)
        var log: String?, dropped = 0
        if let replayLog {
            if let r = ShareTimes.replayLog(replayLog) { log = r.text; dropped = r.droppedLines; shifts[.replayLog] = r.shift } else { unreadable.append(.replayLog) }
        }
        return Diagnostics(state: s, deferred: d, replayLog: log, droppedLines: dropped, shifts: shifts, unreadable: unreadable, notPrepared: notPrepared)
    }

    // MARK: - the stored scan

    private static func decodeStored(_ data: Data) -> BoxStore.StoredScan? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let s = try? d.decode(BoxStore.StoredScan.self, from: data), s.schema <= BoxStore.schemaVersion else { return nil }
        return s
    }

    /// Every `time` of a row's or review entry's frame, where present, is a finite number or null.
    private static func resultTimesAreNumbers(_ tree: [String: Any]) -> Bool {
        for list in ["rows", "review"] {
            guard let entries = tree[list] as? [[String: Any]] else { return false }
            for entry in entries {
                guard let frames = entry["frames"] as? [[String: Any]] else { return false }
                for f in frames { if let v = f[frameTimeKey], !(v is NSNull), ReportTimes.number(v) == nil { return false } }
            }
        }
        return true
    }

    // MARK: - state and saved-crop rows

    /// The parsed object when the file has the shape that holds times safely: an object whose `rows`, if present, is an array of objects whose time keys are
    /// numbers or null (or absent).
    private static func rowTimes(_ data: Data) -> (object: [String: Any], times: [Double])? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard let rows = o["rows"] else { return (o, []) }
        guard let list = rows as? [[String: Any]] else { return nil }
        var found = [Double]()
        for row in list {
            for k in rowTimeKeys {
                guard let v = row[k], !(v is NSNull) else { continue }
                guard let t = ReportTimes.number(v) else { return nil }
                found.append(t)
            }
        }
        return (o, found)
    }
}
