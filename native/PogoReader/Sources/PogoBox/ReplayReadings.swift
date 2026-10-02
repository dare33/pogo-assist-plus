import Foundation
import PogoReader

/// Frame readings from a file, for running the app core without the extension.
///
/// Two inputs:
/// - a `pogo-read` output: `{ "readings": [ ... ] }` (also a bare JSON array of readings);
/// - a replay log, one JSON object per line (JSON lines).
///
/// FORMAT ASSUMPTION (the replay log's exact format is defined by `ReplayLog` on another branch; this
/// loader is tolerant and everything it assumes is in `isReading(line:)` below): a line is a reading if it
/// has a `"reading"` object (the reading is that object), or if the object itself carries reading fields.
/// Every other line (ticks, dropped-frame markers, a header) is skipped and counted, not an error. A line that
/// is not valid JSON, or whose reading does not decode as a `FrameReading`, is counted as malformed.
public enum ReplayReadings {
    public struct Loaded {
        public var readings: [FrameReading]
        /// JSON-lines only: lines that were valid JSON objects but not readings.
        public var skippedLines = 0
        /// JSON-lines only: blank-line-excluded lines that were not valid JSON or not a decodable reading.
        public var malformedLines = 0
        /// Swipe ticks: tick lines of a replay log, or ticks derived from a pogo-read output's `signatureDiffs`
        /// with the package's own `SwipeTicker`, exactly as `pogo-read` does. Empty when the input has none.
        public var ticks: [Double] = []
        public var hasTicks: Bool { !ticks.isEmpty }
    }

    public enum Failure: Error, LocalizedError {
        case unreadable(String)
        public var errorDescription: String? { if case .unreadable(let m) = self { return m } else { return nil } }
    }

    public static func load(url: URL) throws -> Loaded {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw Failure.unreadable("\(url.lastPathComponent): \(error.localizedDescription)") }
        return try parse(data, name: url.lastPathComponent)
    }

    public static func parse(_ data: Data, name: String = "input") throws -> Loaded {
        let decoder = JSONDecoder()
        // A whole-file JSON value first: a pogo-read output or a bare array. (A one-line replay log is a
        // JSON object too; without a "readings" array it falls through to the line reader.)
        if let whole = try? JSONSerialization.jsonObject(with: data) {
            if let obj = whole as? [String: Any], obj["readings"] is [Any] {
                struct Wrapper: Decodable { var readings: [FrameReading]; var signatureDiffs: [Double?]? }
                do {
                    let w = try decoder.decode(Wrapper.self, from: data)
                    var loaded = Loaded(readings: w.readings)
                    if let diffs = w.signatureDiffs, diffs.count == w.readings.count {
                        var ticker = SwipeTicker()
                        for (r, d) in zip(w.readings, diffs) { if let t = r.time, let tick = ticker.feed(diff: d, time: t) { loaded.ticks.append(tick) } }
                    }
                    return loaded
                }
                catch { throw Failure.unreadable("\(name): readings do not decode: \(error)") }
            }
            if whole is [Any] {
                do { return Loaded(readings: try decoder.decode([FrameReading].self, from: data)) }
                catch { throw Failure.unreadable("\(name): readings do not decode: \(error)") }
            }
        }
        var loaded = Loaded(readings: [])
        var any = false
        for lineData in data.split(separator: UInt8(ascii: "\n")) {
            if lineData.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) { continue }
            any = true
            guard let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any] else { loaded.malformedLines += 1; continue }
            if let t = tickTime(line: obj) { loaded.ticks.append(t); continue }
            guard let payload = readingObject(line: obj) else { loaded.skippedLines += 1; continue }
            guard let bytes = try? JSONSerialization.data(withJSONObject: payload),
                  let reading = try? decoder.decode(FrameReading.self, from: bytes) else { loaded.malformedLines += 1; continue }
            loaded.readings.append(reading)
        }
        if !any { throw Failure.unreadable("\(name): empty") }
        return loaded
    }

    /// Keys only a reading carries (a tick or a dropped-frame marker has none of them).
    static let readingFieldKeys: Set<String> = ["cpText", "nameText", "hpText", "nameConfidence", "ivConfidence", "sharpness", "fills"]

    /// THE format assumption for ticks: a line whose `"kind"` (or `"type"`) is `"tick"`, with the swipe's time in
    /// seconds as `"time"` (or `"t"`), or a line `{"tick": <seconds>}`. Anything else is not a tick.
    static func tickTime(line: [String: Any]) -> Double? {
        if let t = line["tick"] as? Double { return t }
        guard (line["kind"] as? String) == "tick" || (line["type"] as? String) == "tick" else { return nil }
        return (line["time"] as? Double) ?? (line["t"] as? Double)
    }

    /// THE format assumption for readings: the object that is the reading in this line, or nil if the line is not one.
    static func readingObject(line: [String: Any]) -> [String: Any]? {
        if let nested = line["reading"] as? [String: Any] { return nested }
        if !readingFieldKeys.isDisjoint(with: line.keys) { return line }
        return nil
    }
}
