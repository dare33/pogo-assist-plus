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
    }

    public struct Timings: Equatable {
        public var load = 0.0, finish = 0.0, refine = 0.0
        public var total: Double { load + finish + refine }
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case nothingRead
        public var errorDescription: String? { "The scan has no readable Pokémon in it. Scan again with the first Pokémon open and the appraisal showing." }
    }

    public static func process(replay url: URL, engine: CoreEngine) throws -> Outcome {
        var timings = Timings()
        let t0 = Date()
        var readings = [FrameReading](), ticks = [Double](), drops = 0, times = [Double]()
        let lines = ReplayLog.lines(in: url)
        for line in lines {
            switch line {
            case .reading(let r):
                var f = r.frameReading
                f.frame = "r\(readings.count)"
                readings.append(f); times.append(r.t)
            case .tick(let t): ticks.append(t); times.append(t)
            case .drop(let t): drops += 1; times.append(t)
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
        let refined = try Refine.apply(to: base, readings: readings, ticks: ticks, engine: engine)
        timings.refine = Date().timeIntervalSince(t2)
        let span = (times.max() ?? 0) - (times.min() ?? 0)
        return Outcome(scan: refined.scan, readings: readings.count, ticks: ticks.count, drops: drops, duration: max(0, span), changes: refined.changes, notices: refined.notices, timings: timings)
    }
}
