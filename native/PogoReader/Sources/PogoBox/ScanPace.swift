import Foundation
import PogoReader

/// How fast a finished scan went through the Pokémon, measured from its replay log: the median time between one Pokémon and
/// the next. It tells the person which Voice Control command actually ran (a normal-pace command played when a fast one was
/// meant shows as about 2.1 s, not 1.6 s).
public enum ScanPace {
    public struct Measured: Equatable {
        public enum Basis: String, Equatable { case swipeTicks, readingGaps }
        public var secondsPerPokemon: Double
        public var basis: Basis
        /// How many gaps the median is over.
        public var samples: Int
    }

    /// Needs at least this many gaps to say anything.
    public static let minimumSamples = 5

    /// From the swipe ticks when there are enough (one per swipe; a missed tick makes one long gap, which the median ignores);
    /// else from the times the on-screen Pokémon changed (a Tap-mode scan has no ticks), counting only readings that held for two
    /// frames in a row so a misread CP does not count as a new Pokémon. nil when neither gives enough to go on.
    public static func measure(_ lines: [ReplayLine]) -> Measured? {
        var ticks = [Double](), readings = [ReplayReading]()
        for line in lines {
            switch line {
            case .tick(let t): ticks.append(t)
            case .reading(let r): readings.append(r)
            case .drop: break
            }
        }
        if let m = median(gaps(ticks.sorted()), .swipeTicks) { return m }
        // Reading runs: a run is a stretch of readings with the same name and CP; it counts when it lasts two frames or more.
        var starts = [Double](), runStart: Double?, runKey: String?, runLength = 0
        func close() { if let s = runStart, runLength >= 2 { starts.append(s) }; runStart = nil; runLength = 0 }
        for r in readings {
            guard let name = r.name, !name.isEmpty, let cp = r.cp else { close(); runKey = nil; continue }
            let key = "\(name)|\(cp)"
            if key != runKey { close(); runKey = key; runStart = r.t }
            runLength += 1
        }
        close()
        return median(gaps(starts), .readingGaps)
    }

    public static func measure(replay url: URL) -> Measured? { measure(ReplayLog.lines(in: url)) }

    private static func gaps(_ times: [Double]) -> [Double] { zip(times, times.dropFirst()).map { $1 - $0 } }

    private static func median(_ gaps: [Double], _ basis: Measured.Basis) -> Measured? {
        guard gaps.count >= minimumSamples else { return nil }
        let s = gaps.sorted(), mid = s.count / 2
        let m = s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
        return Measured(secondsPerPokemon: m, basis: basis, samples: gaps.count)
    }
}
