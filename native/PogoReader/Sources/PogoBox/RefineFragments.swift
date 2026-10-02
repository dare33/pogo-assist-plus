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
    static func absorbFragments(_ scan: ScanResult, ticks: [Double] = []) -> (scan: ScanResult, marks: [(flag: String, detail: String, label: String)]) {
        var rows = scan.rows
        guard rows.count >= 2 else { return (scan, []) }
        let pace = ScanPace.measure(rows: rows)
        let period: Double? = (pace?.isRegular ?? false) ? pace?.medianPeriod : nil
        var marks = [(flag: String, detail: String, label: String)]()
        var flaggedOnly = false
        /// The better row of a pair keeps the Pokémon: one that solved exactly, then the one with more readings.
        func quality(_ r: ScanRow) -> (Int, Int) { (r.solveStatus == "exact" ? 1 : 0, r.frames.count) }
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
                if let p = period, let outer = outerSpan(rows, around: min(i, j), and: max(i, j)) {
                    together = outer <= fragmentPairMaxPeriods * p
                } else {
                    let gap = j > i ? na - b : a - nb
                    together = gap <= fragmentFallbackGapSeconds + 1e-9
                }
                guard together else { continue }
                guard hpCompatible(f.hp, n.hp), barsCompatible(f, n) else { continue }
                // The worse of the two is the fragment: a good row is never folded into a worse one beside it.
                let qf = quality(f), qn = quality(n)
                guard qn.0 > qf.0 || (qn.0 == qf.0 && qn.1 >= qf.1) else { continue }
                // A fragment with its own CP that solved (a level fits), that differs from the neighbour's and is not a part of it, is not folded in: it
                // may be a different Pokémon. It stays its own row, with a flag that asks for a look.
                let solved = f.cp > 0 && f.level != nil && !f.flags.contains { $0 == "no-level-fits" || $0.hasPrefix("no-level-fits:") }
                if solved && f.cp != n.cp && !isPartRead(f.cp, of: n.cp) {
                    let flag = "read-once-beside:\(n.cp)"
                    if !rows[i].flags.contains(flag) { rows[i].flags.append(flag); flaggedOnly = true }
                    break
                }
                absorbedBy = j
                break
            }
            guard let j = absorbedBy else { i += 1; continue }
            let n = rows[j]
            // Same CP: a note. Another CP folded in: a check, when a page tick or a beat boundary lies between the two (adjacent rows of a
            // regular beat always have one).
            let nts = n.frames.compactMap(\.time)
            let lo = j > i ? b : (nts.max() ?? b), hi = j > i ? (nts.min() ?? a) : a
            let tickBetween = ticks.contains { $0 >= lo && $0 <= hi }
            let flag = (f.cp != n.cp && (tickBetween || period != nil)) ? "absorbed-other-cp:\(f.cp)" : "absorbed-fragment:\(f.cp)"
            if !rows[j].flags.contains(flag) { rows[j].flags.append(flag) }
            // The fragment's readings join the row they were part of (its values stay as the JavaScript solved them).
            rows[j].frames = (rows[j].frames + f.frames).sorted { ($0.time ?? 0) < ($1.time ?? 0) }
            marks.append((flag, "\(f.display) CP \(f.cp) (\(f.frames.count) reading\(f.frames.count == 1 ? "" : "s")) is part of the \(rows[j].display) CP \(rows[j].cp) beside it; removed", rows[j].frames.first?.frame ?? ""))
            rows.remove(at: i)
        }
        guard !marks.isEmpty || flaggedOnly else { return (scan, []) }
        for k in rows.indices { rows[k].index = k + 1 }
        return (ScanResult(rows: rows, review: rows.filter { !$0.flags.isEmpty }.map(reviewEntry), unmatched: scan.unmatched), marks)
    }

    /// The CP read is a run of the other's digits (182 in 1982): a part read of it, not another number.
    private static func isPartRead(_ a: Int, of b: Int) -> Bool {
        func subsequence(_ small: [Character], _ big: [Character]) -> Bool { var i = 0; for c in big where i < small.count && c == small[i] { i += 1 }; return i == small.count }
        let x = Array(String(a)), y = Array(String(b))
        return x.count < y.count ? subsequence(x, y) : (y.count < x.count ? subsequence(y, x) : false)
    }

    /// The flags a fragment absorption, a lone-CP-outlier fix or a bars split leave on a row; a row solved again keeps them.
    static let refineFlagPrefixes = ["absorbed-fragment", "absorbed-other-cp", "read-once-beside", "cp-outlier-dropped", "split-by-bars"]
    static func carriedFlags(_ row: ScanRow) -> [String] { row.flags.filter { f in refineFlagPrefixes.contains { f == $0 || f.hasPrefix($0 + ":") || f.hasPrefix($0 + "-") } } }

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
    static func dropCpOutliers(_ scan: ScanResult, readings: [FrameReading], engine: CoreEngine) throws -> (scan: ScanResult, marks: [(flag: String, detail: String, label: String)]) {
        var rows = scan.rows
        var marks = [(flag: String, detail: String, label: String)]()
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
            // the freshly solved row keeps what the earlier steps flagged on this one (an absorbed fragment and the like)
            for carried in carriedFlags(row) where !fixed.flags.contains(carried) { fixed.flags.append(carried) }
            fixed.flags.append(flag)
            marks.append((flag, "\(row.display): CP \(row.cp) was one read that needed the bars changed; the other reads are the tail of \(fixed.cp), which fits the bars exactly", fixed.frames.first?.frame ?? row.frames.first?.frame ?? ""))
            rows[k] = fixed
        }
        guard !marks.isEmpty else { return (scan, []) }
        return (ScanResult(rows: rows, review: rows.filter { !$0.flags.isEmpty }.map(reviewEntry), unmatched: scan.unmatched), marks)
    }
}
