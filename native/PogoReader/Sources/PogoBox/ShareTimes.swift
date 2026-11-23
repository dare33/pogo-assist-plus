import Foundation
import PogoReader

/// Makes the files a person shares out of the app count their times from the scan's first frame, as the uploaded report does (`ReportTimes`). Scans stored by
/// builds 1 to 4 hold times that are the device's presentation timestamps (seconds since the phone started); that must not leave the phone through the share
/// sheet either. Pure functions from bytes to bytes: the stored files are never rewritten, the app writes the returned bytes to the temporary folder.
///
/// One origin per share: the earliest frame time across everything shared together (the replay log, the result, the state and saved-crop rows), so the shared
/// files agree with each other. It is `ReportTimes.rebase`'s rule, called here, not copied. Applying it to its own output changes nothing (the earliest time is
/// then 0). When the earliest time is exactly 0 a file comes back as the bytes it came in (a replay log with an unreadable line cannot: that line is dropped).
///
/// Which values carry a frame time, by file:
/// - Saved scan result (`BoxStore.StoredScan`, `<id>.json`): `rows[].frames[].time` and `review[].frames[].time`; the bars-split text in `refineChanges` (its
///   "at 13056.7 s" cut times; `ReportTimes.barsChange`). Checked and left alone, as the `ReportTimes` header lists: `unmatched` (a frame label, a count, CPs and
///   positions), `paging` (a period and a join allowance, settings), `reviewActions` (what the person answered: names, CPs, counts; `ScanReportBuilder.reviewLines`
///   and `BoxMerge`'s line builders print no time), `scanDate`, `savedAt`, `lastReread`, `reportSentAt` (wall-clock dates), `reportHash`, `sourceSignature` (the
///   replay file's size and its modification date in milliseconds since 1970, a wall-clock fact, not a frame time), `id`, `account`, `source`, `kind`, `pass`,
///   `schema`, `storageCount`. The row fields `merged`, `clip`, `shadow`, `dynamax`, `gigantamax`, `lucky`, `details` hold no time. The scan's pace (`ScanPace`)
///   is not stored; where the report derives it, it is a difference.
/// - Replay log, every line: `t` and `last` (`ReportTimes.logTimeKeys`); `ms` and `read` are a duration and a count.
/// - Diagnostics state file (`BroadcastState`, `state.json`): `rows[].firstTime` and `rows[].lastTime` (the live grouper's first and last reading of each row).
///   Checked and left alone: `rows[].firstFrame`/`lastFrame` (frame labels, an index), `started`, `updated`, `pausedAt`, `cpCoveredSince` (wall-clock dates),
///   `scanId` (the start date in whole seconds since 1970), `commandPeriod`, `pauseLimitSeconds`, `meanMsPerFrame` (periods, limits and durations), and the
///   counts, memory figures, names and flags.
/// - Diagnostics saved-crop result (`DeferredResult`, `deferred.json`): `rows[].firstTime` and `rows[].lastTime` (the same `LiveRow`); `seconds` is how long the read
///   took, `frames` a count, `peakFootprintMB` a size.
///
/// A file that cannot be read as the shape it should have (not JSON, not the stored scan's format, a newer schema, a time that is not a number) is not shared at
/// all: it comes back as `nil` and its name is in `unreadable`. It is never returned as it came. A new time-carrying key must be added to `rowTimeKeys` (state
/// and saved crops) or `ReportTimes` (the log and the result) and to the list above.
public enum ShareTimes {
    public enum Part: String, Equatable { case result, replayLog, state, deferred }

    /// A saved scan's files, shifted. `result` is nil when the result could not be read; `replayLog` is nil when none was given or it could not be read.
    public struct Saved: Equatable {
        public var result: Data?
        public var replayLog: String?
        /// Replay lines left out because they were not a JSON object.
        public var droppedLines: Int
        public var shift: Double
        public var unreadable: [Part]
    }

    /// The Diagnostics screen's three files, shifted by one origin.
    public struct Diagnostics: Equatable {
        public var state: Data?
        public var deferred: Data?
        public var replayLog: String?
        public var droppedLines: Int
        public var shift: Double
        public var unreadable: [Part]
    }

    /// The keys of a state or saved-crop row that hold a frame time.
    static let rowTimeKeys = ["firstTime", "lastTime"]

    /// A saved scan's result file and its replay log, as the files on disk (`BoxStore.files`). `replayLog` is nil when the scan has none.
    public static func savedScan(result: Data, replayLog: Data?) -> Saved {
        var unreadable = [Part]()
        let scan = decodeStored(result)
        if scan == nil { unreadable.append(.result) }
        var logText: String?
        if let replayLog { if let t = String(data: replayLog, encoding: .utf8) { logText = t } else { unreadable.append(.replayLog) } }

        let scanResult = scan.map { ScanResult(rows: $0.rows, review: $0.review, unmatched: $0.unmatched) } ?? ScanResult(rows: [], review: [], unmatched: [])
        let r = ReportTimes.rebase(replayLog: logText ?? "", result: scanResult, refineChanges: scan?.refineChanges ?? [])
        let log = logText.map { r.droppedLines == 0 && r.shift == 0 ? $0 : r.replayLog }

        var out: Data?
        if let scan {
            if r.shift == 0 { out = result } else {
                var s = scan
                s.rows = r.result.rows; s.review = r.result.review
                if scan.refineChanges != nil { s.refineChanges = r.refineChanges }
                out = try? encoder.encode(s)
                if out == nil { unreadable.append(.result) }
            }
        }
        return Saved(result: out, replayLog: log, droppedLines: r.droppedLines, shift: r.shift, unreadable: unreadable)
    }

    /// An unsaved scan's replay log on its own (the review's share when sending fails). Nil when it is not text.
    public static func replayLog(_ data: Data) -> (text: String, droppedLines: Int, shift: Double)? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let r = ReportTimes.rebase(replayLog: text, result: ScanResult(rows: [], review: [], unmatched: []))
        return (r.droppedLines == 0 && r.shift == 0 ? text : r.replayLog, r.droppedLines, r.shift)
    }

    /// The state file, the saved-crop result and the replay log of the Diagnostics screen. Each is optional (a file that does not exist).
    public static func diagnostics(state: Data?, deferred: Data?, replayLog: Data?) -> Diagnostics {
        var unreadable = [Part]()
        func parse(_ data: Data?, _ part: Part) -> [String: Any]? {
            guard let data else { return nil }
            if let o = rowTimes(data) { return o.object }
            unreadable.append(part); return nil
        }
        let stateObject = parse(state, .state), deferredObject = parse(deferred, .deferred)
        var logText: String?
        if let replayLog { if let t = String(data: replayLog, encoding: .utf8) { logText = t } else { unreadable.append(.replayLog) } }

        let times = [stateObject, deferredObject].compactMap { $0 }.flatMap { times(in: $0) }
        let r = ReportTimes.rebase(replayLog: logText ?? "", result: ScanResult(rows: [], review: [], unmatched: []), extraTimes: times)
        let log = logText.map { r.droppedLines == 0 && r.shift == 0 ? $0 : r.replayLog }

        func shifted(_ object: [String: Any]?, original: Data?, _ part: Part) -> Data? {
            guard let object, let original else { return nil }
            if r.shift == 0 { return original }
            if let d = serialise(moved(object, by: r.shift)) { return d }
            unreadable.append(part); return nil
        }
        let s = shifted(stateObject, original: state, .state), d = shifted(deferredObject, original: deferred, .deferred)
        return Diagnostics(state: s, deferred: d, replayLog: log, droppedLines: r.droppedLines, shift: r.shift, unreadable: unreadable)
    }

    // MARK: - the stored scan

    private static let encoder: JSONEncoder = {   // the store's own settings (`BoxStore.encoder`)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }()

    private static func decodeStored(_ data: Data) -> BoxStore.StoredScan? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        guard let s = try? d.decode(BoxStore.StoredScan.self, from: data), s.schema <= BoxStore.schemaVersion else { return nil }
        return s
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

    private static func times(in object: [String: Any]) -> [Double] {
        ((object["rows"] as? [[String: Any]]) ?? []).flatMap { row in rowTimeKeys.compactMap { ReportTimes.number(row[$0]) } }
    }

    private static func moved(_ object: [String: Any], by shift: Double) -> [String: Any] {
        guard var rows = object["rows"] as? [[String: Any]] else { return object }
        for i in rows.indices { for k in rowTimeKeys { if let t = ReportTimes.number(rows[i][k]) { rows[i][k] = ReportTimes.tidy(t - shift) } } }
        var o = object; o["rows"] = rows
        return o
    }

    private static func serialise(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
