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
    static func absorbFragments(_ scan: ScanResult) -> (scan: ScanResult, marks: [(flag: String, detail: String, label: String)]) {
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
            // Both neighbours are examined: the fragment may belong to the one behind it or the one ahead.
            var candidates = [Int]()
            var byFallback = Set<Int>()   // pairs judged without a regular beat around them (consecutive readings only)
            for j in [i - 1, i + 1] where j >= 0 && j < rows.count {
                let n = rows[j]
                guard n.name == f.name else { continue }
                let nts = n.frames.compactMap(\.time)
                guard let na = nts.min(), nts.max() != nil, nts.count == n.frames.count else { continue }
                // no paging boundary between them
                var together: Bool
                if let p = period, let outer = outerSpan(rows, around: min(i, j), and: max(i, j)) {
                    together = outer <= fragmentPairMaxPeriods * p
                } else {
                    byFallback.insert(j)
                    let gap = j > i ? na - b : a - (nts.max() ?? a)
                    together = gap <= fragmentFallbackGapSeconds + 1e-9
                }
                guard together, hpCompatible(f.hp, n.hp), barsCompatible(f, n) else { continue }
                // The worse of the two is the fragment: a good row is never folded into a worse one beside it.
                let qf = quality(f), qn = quality(n)
                guard qn.0 > qf.0 || (qn.0 == qf.0 && qn.1 >= qf.1) else { continue }
                candidates.append(j)
            }
            // A neighbour with the fragment's own CP, or that the fragment is a part read of, is the Pokémon it belongs to. Otherwise a fragment with its
            // own CP that solved (a level fits) is not folded into a different number: it stays its own row and asks for a look.
            var absorbedBy = candidates.first { rows[$0].cp == f.cp || isPartRead(f.cp, of: rows[$0].cp) }
            if absorbedBy == nil, let first = candidates.first {
                let solved = f.cp > 0 && f.level != nil && !f.flags.contains { $0 == "no-level-fits" || $0.hasPrefix("no-level-fits:") }
                if solved {
                    let flag = "read-once-beside:\(rows[first].cp)"
                    if !rows[i].flags.contains(flag) { rows[i].flags.append(flag); flaggedOnly = true }
                } else { absorbedBy = first }
            }
            guard let j = absorbedBy else { i += 1; continue }
            let n = rows[j]
            // Same CP, or a part read of the kept CP: a note. Any other CP folded in: always a check (a once-read real Pokémon must not vanish quietly).
            // A once-read, solved fragment with the SAME CP, folded in with no regular beat to say a boundary lies between, could be a real identical twin.
            let solvedFragment = f.cp > 0 && f.level != nil && !f.flags.contains { $0 == "no-level-fits" || $0.hasPrefix("no-level-fits:") }
            let flag: String
            if f.cp != n.cp && !isPartRead(f.cp, of: n.cp) { flag = "absorbed-other-cp:\(f.cp)" }
            else if f.cp == n.cp && solvedFragment && byFallback.contains(j) { flag = "absorbed-same-cp:\(f.cp)" }
            else { flag = "absorbed-fragment:\(f.cp)" }
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

    /// The FIRST card of a scan is on screen while the person starts the broadcast and says the command, and the appraisal is still opening (its bars animate): readings
    /// with no bars, then one or two with unsettled bars, then the settled ones. The grouper makes the unsettled start one row and the settled readings another (run15: Rayquaza
    /// CP 4262 HP 190, "ambiguous-ivs" then 13/12/14, 2.03 s apart). The first two rows are ONE stay when they have the same name, CP and HP (or an HP unread), the first one's
    /// IVs did not settle (none read, or none that contradict the second's beyond a notch) and the second's did, the readings are consecutive, no swipe tick lies between, and (with a known period) the first card was held longer than one beat
    /// before the second began (a real pair of twins is one beat apart). The second row keeps the Pokémon; the first one's readings join it.
    static func joinOpeningCard(_ scan: ScanResult, period: Double?, ticks: [Double]) -> (scan: ScanResult, marks: [(flag: String, detail: String, label: String)]) {
        var rows = scan.rows
        guard rows.count >= 2 else { return (scan, []) }
        let a = rows[0], b = rows[1]
        let at = a.frames.compactMap(\.time), bt = b.frames.compactMap(\.time)
        guard !at.isEmpty, at.count == a.frames.count, !bt.isEmpty, bt.count == b.frames.count,
              let aFirst = at.min(), let aLast = at.max(), let bFirst = bt.min(), aLast <= bFirst else { return (scan, []) }
        guard a.speciesId == b.speciesId, a.cp == b.cp, a.cp > 0, hpCompatible(a.hp, b.hp), a.solveStatus != "exact", b.solveStatus == "exact", b.ivs != nil else { return (scan, []) }
        // The stated cause is bars that were unsettled or unread on the first row (no settled IVs). A first row with its own settled IVs that differ from the second's beyond a
        // notch is another Pokémon (Fidough 768/89 15/4/10 then 15/11/12 stay two), whatever its solve status.
        if let settled = a.ivs, let later = b.ivs, !IVFit.near(IVFit.index(later), settled) { return (scan, []) }
        guard bFirst - aLast <= max(1.5, (period ?? 0) * 1.5) else { return (scan, []) }
        if let p = period, bFirst - aFirst <= 1.4 * p { return (scan, []) }
        if ticks.contains(where: { $0 > aFirst && $0 < bFirst }) { return (scan, []) }
        let flag = "absorbed-fragment:\(a.cp)"
        if !rows[1].flags.contains(flag) { rows[1].flags.append(flag) }
        rows[1].frames = (a.frames + b.frames).sorted { ($0.time ?? 0) < ($1.time ?? 0) }
        let mark = (flag: flag, detail: "\(a.display) CP \(a.cp), the first card of the scan read while its appraisal opened (\(a.frames.count) readings, IVs not settled), is the same stay as the \(b.display) after it; joined", label: rows[1].frames.first?.frame ?? "")
        rows.remove(at: 0)
        for k in rows.indices { rows[k].index = k + 1 }
        return (ScanResult(rows: rows, review: rows.filter { !$0.flags.isEmpty }.map(reviewEntry), unmatched: scan.unmatched), [mark])
    }

    /// `a` is a part read of `b`: its digits are a run of the KEPT row's CP (182 in 1982). The reverse (1982 beside a better-read 182) is another number.
    private static func isPartRead(_ a: Int, of b: Int) -> Bool {
        let x = Array(String(a)), y = Array(String(b))
        guard x.count < y.count else { return false }
        var i = 0
        for c in y where i < x.count && c == x[i] { i += 1 }
        return i == x.count
    }

    /// The flags a fragment absorption, a lone-CP-outlier fix or a bars split leave on a row; a row solved again keeps them.
    static let refineFlagPrefixes = ["absorbed-fragment", "absorbed-other-cp", "absorbed-same-cp", "read-once-beside", "cp-outlier-dropped", "split-by-bars"]
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
