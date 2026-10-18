import Foundation
import PogoReader

/// Frame readings from a file, for running the app core without the extension.
///
/// Two inputs:
/// - a `pogo-read` output: `{ "readings": [ ... ], "signatureDiffs": [ ... ] }` (also a bare JSON array of readings);
///   swipe ticks are derived from `signatureDiffs` with `SwipeTicker`, as `pogo-read` does;
/// - the extension's replay log (JSON lines, `k` = "r" reading, "t" tick, "d" drop). The format has ONE source of
///   truth, `PogoReader.ReplayLog`; this loader only calls `ReplayLog.decode`. A line it does not decode is counted
///   as skipped (or malformed when it is not a JSON object), never an error. The log's readings carry no frame label,
///   so each gets `"r<line number>"` (unique labels let the JavaScript place rows and let `Refine` find frames).
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
        /// Replay log only: frames the extension dropped (a count; a drop carries no reading).
        public var drops = 0
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
        var endLast: Double?
        for lineData in data.split(separator: UInt8(ascii: "\n")) {
            if lineData.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) { continue }
            any = true
            switch ReplayLog.decode(Data(lineData)) {
            case .reading(let r)?:
                var reading = r.frameReading
                reading.frame = "r\(loaded.readings.count + 1)"
                loaded.readings.append(reading)
            case .tick(let t)?: loaded.ticks.append(t)
            case .drop?: loaded.drops += 1
            case .end(_, let last)?: endLast = last
            case .pause?, .resume?, .stoppedByPerson?, .pauseTimedOut?: break
            case nil:
                if (try? JSONSerialization.jsonObject(with: lineData)) is [String: Any] { loaded.skippedLines += 1 } else { loaded.malformedLines += 1 }
            }
        }
        if !any { throw Failure.unreadable("\(name): empty") }
        if let endLast {   // an automatic end: the tail after the last new Pokémon is cut, as `ReplayLog.trimmed` does
            let limit = endLast + EndOfListDetector.keepAfterLast
            loaded.readings = loaded.readings.filter { ($0.time ?? 0) <= limit }
            loaded.ticks = loaded.ticks.filter { $0 <= limit }
        }
        return loaded
    }
}
