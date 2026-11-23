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
/// - refine changes (the report's `refineChanges`, one string each, `"<kind>: <detail>"`): ONLY the bars-split shape holds a frame time. `RefineBars` writes
///   "... bars change A to B at 13056.7 s, then C to D at 13060.1 s, each held by two or more readings: ..." where each time is the midpoint of two frame times.
///   Those "at <number> s" times, between "bars change " and ", each held by", are shifted and printed to one decimal as RefineBars prints them. Checked and
///   left alone, because they hold no frame time: the timing split ("stayed 5.0 s, 3 periods of 1.20 s": a duration), the twin split ("at a swipe tick" /
///   "where LiveGrouper has N rows": words), hidden CP, duplicate dropped, fragment absorbed / joined, CP outlier, forms from stats, IVs chosen by fit and
///   CP recovered (rows, CPs, IVs and counts only). `Refine.reconcileTwins` writes "... at 13056.7 s" into `Refined.disagreements`, and `RefineBars`
///   writes a time into `notices` (`RefineTiming`'s notice holds a duration); neither list is in the report (the app reads `outcome.changes` only).
/// - ScanPace, StoredPaging and the report's `scan` fields (`measuredPeriod`, `measuredRegularity`, `expectedPeriod`, `joinExtraSeconds`) are
///   differences or settings, not times, and stay. `scanDate` and the app/device fields are wall-clock or hardware facts and stay.
///
/// The origin is the earliest of the log's and the result's times, so the earliest frame in the scan is 0 and every difference is kept. Applying it
/// again changes nothing. `ShareTimes` uses the same rules for the files the person shares out of the app. When the earliest time is exactly 0 the log text is returned as it came (each line as written, lines joined by "\n"; a
/// blank line is dropped); otherwise each line is re-serialised (sorted keys, 17 significant digits, which decode to the same values).
///
/// A replay line this cannot read as a JSON object (a half-written last line, damage), or whose `t` or `last` is present and is not a finite number (a string, null, a
/// boolean, a list, an object), is left out of the upload and counted, because its text might hold a boot time that cannot be shifted. A line of a kind this does not know has its numeric `t` and `last` shifted like the known ones;
/// a time kept under any other key in a future line kind would NOT be shifted (a new time-carrying key must be added to `logTimeKeys`).
public enum ReportTimes {
    public struct Rebased: Equatable {
        public var replayLog: String
        public var result: ScanResult
        public var refineChanges: [String]
        /// Replay lines left out because they were not a JSON object.
        public var droppedLines: Int
        /// What was subtracted from every time (0 when the scan already started at 0, or holds no time at all).
        public var shift: Double
    }

    /// The keys of a replay line that hold a frame time.
    static let logTimeKeys = ["t", "last"]

    /// The subtraction is rounded to nine decimals, so two times that were equal before the shift are equal after it. It does not shorten the printed
    /// number: JSONSerialization writes 17 significant digits, which decode to the same value.
    static func tidy(_ x: Double) -> Double { (x * 1e9).rounded() / 1e9 }

    /// `extraTimes` are further frame times that belong to the same scan and are shared with it (the diagnostics' state and saved-crop rows, `ShareTimes`); they count towards
    /// the origin only. Empty for the report.
    /// A line whose `t` or `last` is present must hold a finite number: no writer in the repo ever wrote null or anything else there (`ReplayLog` encodes non-optional
    /// Doubles, and a non-finite one fails to encode), so a line with such a value is damaged, and its text might hold a time that cannot be shifted.
    static func logTimesAreNumbers(_ o: [String: Any]) -> Bool {
        for k in logTimeKeys { if let v = o[k], number(v) == nil { return false } }
        return true
    }

    public static func rebase(replayLog: String, result: ScanResult, refineChanges: [String] = [], extraTimes: [Double] = []) -> Rebased {
        var objects = [[String: Any]?]()
        var earliest = Double.infinity
        for text in replayLog.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any], logTimesAreNumbers(o) else { objects.append(nil); continue }
            for k in logTimeKeys { if let v = number(o[k]) { earliest = min(earliest, v) } }
            objects.append(o)
        }
        for row in result.rows { for f in row.frames { if let t = f.time { earliest = min(earliest, t) } } }
        for entry in result.review { for f in entry.frames { if let t = f.time { earliest = min(earliest, t) } } }
        for t in extraTimes where t.isFinite { earliest = min(earliest, t) }
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
        let changes = shift == 0 ? refineChanges : refineChanges.map { barsChange($0, shift: shift) }
        return Rebased(replayLog: out.isEmpty ? "" : out.joined(separator: "\n") + "\n", result: r, refineChanges: changes, droppedLines: dropped, shift: shift)
    }

    /// A bars-split change text with its cut times shifted; any other text is returned as it is. Only the span from "bars change " to ", each held by" is
    /// touched, so a duration elsewhere in a text is never shifted. The detail starts with the species' display name, not a nickname; a name that itself held
    /// "bars change " would only start the span earlier, and the real cut is still inside it.
    static func barsChange(_ text: String, shift: Double) -> String {
        guard let start = text.range(of: "bars change "), let end = text.range(of: ", each held by", range: start.upperBound..<text.endIndex) else { return text }
        var span = String(text[start.upperBound..<end.lowerBound])
        let pattern = try! NSRegularExpression(pattern: " at (-?[0-9]+(?:\\.[0-9]+)?) s")
        for m in pattern.matches(in: span, range: NSRange(span.startIndex..., in: span)).reversed() {
            guard let whole = Range(m.range, in: span), let num = Range(m.range(at: 1), in: span), let t = Double(span[num]) else { continue }
            span.replaceSubrange(whole, with: " at \(String(format: "%.1f", max(0, t - shift))) s")
        }
        return String(text[..<start.upperBound]) + span + String(text[end.lowerBound...])
    }

    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue.isFinite ? n.doubleValue : nil
    }
}
