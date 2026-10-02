import Foundation

/// How fast a scan paged from one Pokemon to the next, measured from when the Pokemon on screen changed. Pure and
/// self-contained (spans in, numbers out), so the app can show it and `Refine` can use it.
///
/// The change between two consecutive rows happens between the last reading of one and the first reading of the next: its
/// time is taken as their midpoint (swipe ticks are not used: a tick is stamped on the frame that confirms the swipe, a
/// fixed lag after the change, which would put a different offset on boundaries that have a tick and those that do not).
/// A row's stay is the time between its two boundaries, so the first and last rows (one boundary each) have none.
public struct ScanPace: Equatable {
    /// Median stay of the interior rows, in seconds: the measured period of the paging.
    public var medianPeriod: Double
    /// Median absolute deviation of the stays over the median (0.05 = steady to about 5%). Smaller is steadier.
    public var regularity: Double
    /// `regularity` is within `regularityTolerance`.
    public var isRegular: Bool
    /// Stays within 35% of the median: the Pokemon that were on screen for exactly one period.
    public var periodsObserved: Int
    /// All stays measured.
    public var staysMeasured: Int

    /// Median absolute deviation over the median at or under which a beat counts as regular. Real paged clips measure about
    /// 0.05 to 0.07 (reading times jitter by a frame or two); hand-tapped paging with menus opened is above 0.3.
    public static let regularityTolerance = 0.12
    /// A stay this close to the median (as a fraction) counts as one period.
    public static let singlePeriodBand = 0.35

    /// The time each row's Pokemon changed to the next one: `boundaries[i]` is between row i and row i + 1. Nil where
    /// the rows overlap in time (no clean change).
    public static func boundaries(spans: [(first: Double, last: Double)]) -> [Double?] {
        zip(spans, spans.dropFirst()).map { a, b in a.last <= b.first ? (a.last + b.first) / 2 : nil }
    }

    /// Stay of every row (nil for the first, the last, and rows next to a missing boundary).
    public static func stays(spans: [(first: Double, last: Double)]) -> [Double?] {
        let b = boundaries(spans: spans)
        return spans.indices.map { i in
            guard i >= 1, i <= spans.count - 2, let a = b[i - 1], let c = b[i] else { return nil }
            return c - a
        }
    }

    public static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// Median absolute deviation over the median; nil with no values or a zero median.
    static func relativeMAD(_ xs: [Double]) -> (median: Double, mad: Double)? {
        guard let m = median(xs), m > 0, let d = median(xs.map { abs($0 - m) }) else { return nil }
        return (m, d / m)
    }

    public static func measure(spans: [(first: Double, last: Double)]) -> ScanPace? {
        let stays = Self.stays(spans: spans).compactMap { $0 }.filter { $0 > 0 }
        guard stays.count >= 3, let (m, mad) = relativeMAD(stays) else { return nil }
        return ScanPace(medianPeriod: m, regularity: mad, isRegular: mad <= regularityTolerance,
                        periodsObserved: stays.filter { abs($0 - m) <= singlePeriodBand * m }.count, staysMeasured: stays.count)
    }

    public static func measure(rows: [ScanRow]) -> ScanPace? { measure(spans: spans(of: rows).compactMap { $0 }) }

    /// Time span of each row's frames; nil for a row with no frame times.
    static func spans(of rows: [ScanRow]) -> [(first: Double, last: Double)?] {
        rows.map { r in
            let ts = r.frames.compactMap(\.time)
            guard let a = ts.min(), let b = ts.max() else { return nil }
            return (a, b)
        }
    }
}
