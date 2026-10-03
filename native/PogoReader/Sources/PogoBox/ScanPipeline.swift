import Foundation
import PogoReader

/// From a finished broadcast's `replay.jsonl` to the rows the review screen shows: load the log, run the JavaScript
/// `finish`, then `Refine`. The app calls this on the engine's queue; a test calls it directly.
///
/// The log is read with `ReplayLog` (the package's own reader of what the extension writes: `{"k":"r",...}` readings,
/// `{"k":"t",...}` swipe ticks, `{"k":"d",...}` drops), so every reading keeps its time and the swipe ticks reach `Refine`.
/// A file that is not a replay log (a `pogo-read` output, which `ReplayReadings` reads) is passed to `ReplayReadings`.
public enum ScanPipeline {
    public struct Outcome {
        public var scan: ScanResult
        /// Readings given to the grouper, swipe ticks and dropped frames in the log.
        public var readings: Int
        public var ticks: Int
        public var drops: Int
        /// Seconds from the first to the last line of the log that has a time (what the scan took).
        public var duration: Double
        public var changes: [Refine.Change]
        public var notices: [String]
        public var timings: Timings
        /// How fast the paging went (`ScanPace`, from when the on-screen Pokémon changed), when there is enough to measure.
        public var pace: ScanPace?
        /// The pauses in the log (the extension waited at a card that was not the end of the list), each with whether and when a new card was read after it.
        public var pauses: [Pause] = []
    }

    public struct Pause: Equatable {
        public var at: Double, last: Double, read: Int
        public var closed: Bool?
        public var resumedAt: Double?
    }

    public struct Timings: Equatable {
        public var load = 0.0, finish = 0.0, refine = 0.0
        public var total: Double { load + finish + refine }
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case nothingRead
        public var errorDescription: String? { "The scan has no readable Pokémon in it. Scan again with the first Pokémon open and the appraisal showing." }
    }

    /// `paging` is what the app knows about how the scan was paged (a generated command, or by hand); `Refine` uses it to judge twins by the beat.
    public static func process(replay url: URL, engine: CoreEngine, paging: PagingHint? = nil) throws -> Outcome {
        var timings = Timings()
        let t0 = Date()
        var readings = [FrameReading](), ticks = [Double](), drops = 0, times = [Double](), pauses = [Pause]()
        let lines = ReplayLog.trimmed(ReplayLog.lines(in: url))   // the tail after an automatic end is cut
        for line in lines {
            switch line {
            case .reading(let r):
                var f = r.frameReading
                f.frame = "r\(readings.count)"
                readings.append(f); times.append(r.t)
            case .tick(let t): ticks.append(t); times.append(t)
            case .drop(let t): drops += 1; times.append(t)
            case .pause(let at, let last, let read, let closed): pauses.append(Pause(at: at, last: last, read: read, closed: closed))
            case .resume(let at): if let i = pauses.indices.last, pauses[i].resumedAt == nil { pauses[i].resumedAt = at }
            case .end, .stoppedByPerson, .pauseTimedOut: break
            }
        }
        if readings.isEmpty {
            // Not a replay log: a pogo-read output or a bare readings array.
            let loaded = try ReplayReadings.load(url: url)
            readings = loaded.readings; ticks = loaded.ticks
            times = loaded.readings.compactMap { $0.time } + loaded.ticks
        }
        guard !readings.isEmpty else { throw Failure.nothingRead }
        timings.load = Date().timeIntervalSince(t0)

        try engine.prepare()
        let t1 = Date()
        let base = try engine.finish(readings: readings)
        timings.finish = Date().timeIntervalSince(t1)
        let t2 = Date()
        var hint = paging
        if !pauses.isEmpty { hint?.pauses = pauses.map { $0.last...Swift.max($0.last, $0.resumedAt ?? ($0.at + 1_000_000)) } }
        let refined = try Refine.apply(to: base, readings: readings, ticks: ticks, engine: engine, paging: hint)
        timings.refine = Date().timeIntervalSince(t2)
        let span = (times.max() ?? 0) - (times.min() ?? 0)
        return Outcome(scan: refined.scan, readings: readings.count, ticks: ticks.count, drops: drops, duration: max(0, span), changes: refined.changes, notices: refined.notices, timings: timings, pace: ScanPace.measure(rows: refined.scan.rows), pauses: pauses)
    }
}
