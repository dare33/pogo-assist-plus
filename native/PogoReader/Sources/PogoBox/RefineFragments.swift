import Foundation
import PogoReader

extension Refine {
    /// A pair (fragment and the row it joins) lasts at most this many periods of the measured beat. One period is a Pokemon;
    /// the reading times jitter, so a little over is allowed. Two Pokemon are two periods.
    public static let fragmentPairMaxPeriods = 1.4
    /// With no regular beat: the fragment's reading and the neighbour's nearest reading are consecutive (two frame periods
    /// at most, no unreadable stretch between them).
    public static let fragmentFallbackGapSeconds = 0.4
    /// A frame whose bars have this confidence or more counts as settled (the same number the JavaScript uses).
    public static let settledBarsConfidence = 0.7

    /// Step 1, before everything else: ONE Pokemon's readings cut into two rows because a single early or late frame
    /// disagrees with the rest (a wing over the CP, bars mid-animation). A row backed by one reading (or by readings spanning
    /// less than half the measured period) that sits next to a row of the same species, with no paging boundary between them
    /// (the two together last about one period of a regular beat; with no regular beat: consecutive readings, no more than
    /// `fragmentFallbackGapSeconds` apart) is that Pokemon when its HP equals the neighbour's or is unread and its read bars
    /// (`ivsRead`, before the solver) equal the neighbour's, are unread, or differ by at most one unit on every bar while none
    /// of its frames' bars were settled. It is never absorbed when its own settled bars differ AND its HP differs (another
    /// Pokemon). The fragment is removed; the neighbour keeps its values and gets the flag `absorbed-fragment:<cp>`.
    static func absorbFragments(_ scan: ScanResult) -> (scan: ScanResult, marks: [(flag: String, detail: String)]) {
        var rows = scan.rows
        guard rows.count >= 2 else { return (scan, []) }
        let pace = ScanPace.measure(rows: rows)
        let period: Double? = (pace?.isRegular ?? false) ? pace?.medianPeriod : nil
        var marks = [(flag: String, detail: String)]()
        var i = 0
        while i < rows.count {
            let f = rows[i]
            let ts = f.frames.compactMap(\.time)
            guard let a = ts.min(), let b = ts.max(), ts.count == f.frames.count else { i += 1; continue }
            let small = f.frames.count == 1 || (period.map { b - a < 0.5 * $0 } ?? false)
            guard small else { i += 1; continue }
            var absorbedBy: Int?
            for j in [i - 1, i + 1] where j >= 0 && j < rows.count {
                let n = rows[j]
                guard n.name == f.name else { continue }
                let nts = n.frames.compactMap(\.time)
                guard let na = nts.min(), let nb = nts.max(), nts.count == n.frames.count else { continue }
                // no paging boundary between them
                var together: Bool
                let lo = min(a, na), hi = max(b, nb)
                if let p = period, let outer = outerSpan(rows, around: min(i, j), and: max(i, j)) {
                    together = outer <= fragmentPairMaxPeriods * p
                    _ = (lo, hi)
                } else {
                    let gap = j > i ? na - b : a - nb
                    together = gap <= fragmentFallbackGapSeconds + 1e-9
                }
                guard together else { continue }
                guard hpCompatible(f.hp, n.hp), barsCompatible(f, n) else { continue }
                absorbedBy = j
                break
            }
            guard let j = absorbedBy else { i += 1; continue }
            let flag = "absorbed-fragment:\(f.cp)"
            if !rows[j].flags.contains(flag) { rows[j].flags.append(flag) }
            marks.append((flag, "\(f.display) CP \(f.cp) (\(f.frames.count) reading\(f.frames.count == 1 ? "" : "s")) is part of the \(rows[j].display) CP \(rows[j].cp) beside it; removed"))
            rows.remove(at: i)
        }
        guard !marks.isEmpty else { return (scan, []) }
        for k in rows.indices { rows[k].index = k + 1 }
        return (ScanResult(rows: rows, review: rows.filter { !$0.flags.isEmpty }.map(reviewEntry), unmatched: scan.unmatched), marks)
    }

    /// Time from the change before row `lo` to the change after row `hi` (boundaries are midpoints between neighbouring rows'
    /// readings); nil when `lo` is the first or `hi` the last row, or the rows overlap.
    private static func outerSpan(_ rows: [ScanRow], around lo: Int, and hi: Int) -> Double? {
        guard lo >= 1, hi <= rows.count - 2 else { return nil }
        func edge(_ r: ScanRow) -> (Double, Double)? { let t = r.frames.compactMap(\.time); guard let a = t.min(), let b = t.max() else { return nil }; return (a, b) }
        guard let p = edge(rows[lo - 1]), let l = edge(rows[lo]), let h = edge(rows[hi]), let n = edge(rows[hi + 1]), p.1 <= l.0, h.1 <= n.0 else { return nil }
        return (h.1 + n.0) / 2 - (p.1 + l.0) / 2
    }

    private static func hpCompatible(_ a: Int?, _ b: Int?) -> Bool { a == nil || b == nil || a == b }

    private static func barsCompatible(_ frag: ScanRow, _ nb: ScanRow) -> Bool {
        let settled = frag.frames.contains { ($0.ivConfidence ?? 0) >= settledBarsConfidence && $0.ivs != nil }
        let hpDiffers = frag.hp != nil && nb.hp != nil && frag.hp != nb.hp
        guard let fb = frag.ivsRead else { return true }                // unread bars
        guard let nbBars = nb.ivsRead ?? nb.ivs else { return !(settled && hpDiffers) }
        if fb == nbBars { return true }
        if settled && hpDiffers { return false }                         // another Pokemon
        if settled { return false }                                      // settled and different: not "equal", not "unsettled"
        return abs(fb.atk - nbBars.atk) <= 1 && abs(fb.def - nbBars.def) <= 1 && abs(fb.hp - nbBars.hp) <= 1
    }

    /// Step 1b: a row whose CP is ONE read that had to bend the bars to fit (`ivs-corrected-from-...`) while its other readings
    /// are the tails of one longer number (the first frame read "CP1910", the next "918" and "18": the wing hid a digit). Run
    /// the JavaScript again on that Pokemon's readings without the lone read; accept the result only when it is one row, exact,
    /// with the same HP and bars as were read, a recovered CP (`cp-recovered`) and no correction. The row gets the flag
    /// `cp-outlier-dropped:<cp>`.
    static func dropCpOutliers(_ scan: ScanResult, readings: [FrameReading], engine: CoreEngine) throws -> (scan: ScanResult, marks: [(flag: String, detail: String)]) {
        var rows = scan.rows
        var marks = [(flag: String, detail: String)]()
        var labelIndex = [String: Int]()
        for (i, r) in readings.enumerated() { if let f = r.frame, labelIndex[f] == nil { labelIndex[f] = i } }
        for k in rows.indices {
            let row = rows[k]
            guard row.flags.contains(where: { $0.hasPrefix("ivs-corrected-from-") }) else { continue }
            let withCp = row.frames.filter { $0.cp != nil }
            guard withCp.filter({ $0.cp == row.cp }).count == 1, withCp.count >= 3 else { continue }
            var own = [FrameReading]()
            for f in row.frames {
                guard let label = f.frame, let at = labelIndex[label] else { own = []; break }
                var r = readings[at]
                if r.cp == row.cp { r.cp = nil; r.cpText = ""; r.cpReads = nil }
                own.append(r)
            }
            guard !own.isEmpty, let result = try? engine.finish(readings: own), result.rows.count == 1, result.unmatched.isEmpty,
                  var fixed = result.rows.first, fixed.solveStatus == "exact", fixed.hp == row.hp, fixed.ivsRead == row.ivsRead, fixed.cp != row.cp,
                  fixed.flags.contains(where: { $0.hasPrefix("cp-recovered:") }), !fixed.flags.contains(where: { $0.hasPrefix("ivs-corrected-from-") }) else { continue }
            fixed.index = row.index
            let flag = "cp-outlier-dropped:\(row.cp)"
            fixed.flags.append(flag)
            marks.append((flag, "\(row.display): CP \(row.cp) was one read that needed the bars changed; the other reads are the tail of \(fixed.cp), which fits the bars exactly"))
            rows[k] = fixed
        }
        guard !marks.isEmpty else { return (scan, []) }
        return (ScanResult(rows: rows, review: rows.filter { !$0.flags.isEmpty }.map(reviewEntry), unmatched: scan.unmatched), marks)
    }
}
