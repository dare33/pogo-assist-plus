import Foundation
import PogoReader

extension Refine {
    /// Each part of a row cut at a change of bars lasts about one period of a regular beat, within this fraction of a period.
    public static let barsSplitPartTolerance = 0.35
    /// With no regular beat the split also needs each state held for this fraction of the command's period (when it is known).
    public static let barsSplitFallbackHeldPeriods = 0.6
    /// A state is a bars value held by this many consecutive settled readings. One reading is the previous Pokemon's bars on
    /// their way (the first frame after a page), or a misread.
    public static let barsStateMinReadings = 2
    /// A row is cut only when it has this many states or fewer. Three: run23's Charmander CP 12 / HP 11 is three Pokemon (bars 11/13/3, 11/4/4, 10/7/0; the owner confirmed three in the game,
    /// 4 Oct 2026, and run13, run14, run15 and run23 all show the same triplet). More than three states is left as one row `ivs-disagree`: no log has one and a row of four cards is
    /// more likely a stall with changing bars than four Pokemon; nothing is cut and the row keeps its flag.
    public static let barsSplitMaxStates = 3

    /// Step 1c: two different Pokemon joined into one row because the JavaScript grouping treats rows with the same name, CP and HP
    /// as one (their bars were `ivs-disagree`). Inside one row, when the settled bars change from one value to another, each value is
    /// held by at least two consecutive settled readings (confidence at or above `settledBarsConfidence`), and the change falls on a
    /// beat boundary, the row is cut at the change. With a regular beat each part lasts about one period (`barsSplitPartTolerance`)
    /// and the row about two; with no regular beat each state must have been held for about 0.6 of the command's period (and with none known the row is not split). Each part
    /// is solved again by the JavaScript on its own readings, so it gets its own bars, level and flags; the second row is flagged
    /// `split-by-bars` (not `same-as-previous`: they are different Pokemon).
    /// A single odd reading never splits a row: the first frame after a page is the previous Pokemon's bars moving to the new ones.
    static func splitByBars(_ scan: ScanResult, readings: [FrameReading], engine: CoreEngine, hintPeriod: Double? = nil, maxStates: Int = barsSplitMaxStates) throws -> (scan: ScanResult, marks: [(label: String, detail: String)], notices: [String]) {
        var labelIndex = [String: Int]()
        for (i, r) in readings.enumerated() { if let f = r.frame, labelIndex[f] == nil { labelIndex[f] = i } }
        let pace = ScanPace.measure(rows: scan.rows)
        let period: Double? = (pace?.isRegular ?? false) ? pace?.medianPeriod : nil
        let spans = ScanPace.spans(of: scan.rows)
        let allSpans = spans.allSatisfy { $0 != nil } ? spans.compactMap { $0 } : []
        let boundaries = allSpans.isEmpty ? [] : ScanPace.boundaries(spans: allSpans)

        var out = [ScanRow](), marks = [(label: String, detail: String)](), notices = [String]()
        for (n, row) in scan.rows.enumerated() {
            guard row.flags.contains("ivs-disagree") || row.frames.count >= 4 else { out.append(row); continue }
            // Interior rows only have both paging boundaries (the first and the last row have one each).
            let bounds: (b0: Double, b1: Double)? = {
                guard n >= 1, n <= scan.rows.count - 2, !boundaries.isEmpty, let b0 = boundaries[n - 1], let b1 = boundaries[n] else { return nil }
                return (b0, b1)
            }()
            var found = barsChanges(row, lenient: false, maxStates: maxStates)
            var lenient = false
            if found == nil, hintPeriod != nil, let l = barsChanges(row, lenient: true, maxStates: maxStates) { found = l; lenient = true }
            guard let change = found else { out.append(row); continue }
            if lenient {
                // Bars below the settled confidence count only when the cuts they imply lie on the command's beat: each cut a whole number (at least one) of expected periods from the
                // row's own boundaries, within `timingMultipleTolerance`. The same confidence floor still protects every other row.
                guard let p = hintPeriod, let bd = bounds, change.cuts.allSatisfy({ onBeat($0.time - bd.b0, p) && onBeat(bd.b1 - $0.time, p) }) else { out.append(row); continue }
            } else if let p = period, let bd = bounds {
                // beat evidence: with a regular beat each part lasts about one period (cut j is j periods after the row's first boundary, the last part one period before its end)
                let tol = barsSplitPartTolerance * p
                guard change.cuts.indices.allSatisfy({ abs((change.cuts[$0].time - bd.b0) - Double($0 + 1) * p) <= tol }), abs((bd.b1 - change.cuts.last!.time) - p) <= tol else { out.append(row); continue }
            } else {
                // No regular beat: real evidence, not a short gap (every gap at the tap reading rate is 0.4 s). With the command's period known, each
                // state must have been held for about 0.6 of it; with none known, the row is not split and keeps its `ivs-disagree`.
                guard let p = hintPeriod, change.held.allSatisfy({ $0 >= barsSplitFallbackHeldPeriods * p }) else { out.append(row); continue }
            }
            // each part solved on its own readings
            var parts = [[FrameLabel]](repeating: [], count: change.cuts.count + 1)
            for f in row.frames { parts[change.cuts.filter { $0.time < f.time! }.count].append(f) }
            var solved = [ScanRow]()
            for part in parts {
                let own = part.compactMap { f in f.frame.flatMap { labelIndex[$0] }.map { readings[$0] } }
                guard own.count == part.count, let result = try? engine.finish(readings: own), result.rows.count == 1, let r = result.rows.first else { solved = []; break }
                solved.append(r)
            }
            guard solved.count == parts.count else {
                notices.append("bars: \(row.display) CP \(row.cp) changes bars at \(change.cuts.map { String(format: "%.1f", $0.time) }.joined(separator: ", ")) s but a part could not be solved on its own: not split")
                out.append(row); continue
            }
            // EVERY part is flagged: any may be the wrong one (the first can solve exactly on transient bars). Each keeps what the earlier steps
            // flagged on the row, and the original `ivs-disagree` is still a fact about the group.
            for k in solved.indices {
                for carried in carriedFlagsForSplit(row) where !solved[k].flags.contains(carried) { solved[k].flags.append(carried) }
                if !solved[k].flags.contains("split-by-bars") { solved[k].flags.append("split-by-bars") }
            }
            let what = change.cuts.map { "\($0.from) to \($0.to) at \(String(format: "%.1f", $0.time)) s" }.joined(separator: ", then ")
            let detail = "\(row.display) CP \(row.cp): bars change \(what), each held by two or more readings: \(solved.count) Pokemon\(lenient ? " (bars below the settled confidence, cut on the command's beat)" : "")"
            for part in solved.dropFirst() { marks.append((part.frames.first?.frame ?? "", detail)) }
            out += solved
        }
        guard !marks.isEmpty else { return (scan, [], notices) }
        for k in out.indices { out[k].index = k + 1 }
        return (ScanResult(rows: out, review: out.filter { !$0.flags.isEmpty }.map(reviewEntry), unmatched: scan.unmatched), marks, notices)
    }

    /// A whole number (at least one) of periods, within `timingMultipleTolerance` of a period.
    private static func onBeat(_ x: Double, _ period: Double) -> Bool {
        let k = (x / period).rounded()
        return k >= 1 && abs(x - k * period) <= timingMultipleTolerance * period
    }

    /// Where a row's bars change from one state to another, each state held by at least `barsStateMinReadings` consecutive readings with exactly equal bars: the time of each cut (halfway
    /// between the last reading of one state and the first of the next), the two values, and how long each state was held (first to last reading). Any number of states: a row of three
    /// Pokemon has two cuts. Readings that are alone between two states (the animation, or a misread) are ignored. Strict: only readings at or above `settledBarsConfidence` count.
    /// Lenient: every reading with bars counts, whatever its confidence (the caller then demands the beat).
    private static func barsChanges(_ row: ScanRow, lenient: Bool, maxStates: Int) -> (cuts: [(time: Double, from: String, to: String)], held: [Double])? {
        guard row.frames.allSatisfy({ $0.time != nil }) else { return nil }
        let frames = row.frames.sorted { $0.time! < $1.time! }
        let pool = frames.filter { f in f.ivs != nil && (lenient || (f.ivConfidence ?? 0) >= settledBarsConfidence) }
        // runs of equal bars in time order
        var runs = [(ivs: String, items: [FrameLabel])]()
        for f in pool {
            if let last = runs.last, last.ivs == f.ivs! { runs[runs.count - 1].items.append(f) } else { runs.append((f.ivs!, [f])) }
        }
        // A state is a run of at least two readings; two states with equal bars on either side of a lone reading are one state.
        var states = [(ivs: String, first: Double, last: Double)]()
        for r in runs where r.items.count >= barsStateMinReadings {
            if let s = states.last, s.ivs == r.ivs { states[states.count - 1].last = r.items.last!.time! } else { states.append((r.ivs, r.items.first!.time!, r.items.last!.time!)) }
        }
        guard states.count >= 2, states.count <= maxStates else { return nil }
        let cuts = zip(states, states.dropFirst()).map { (time: ($0.last + $1.first) / 2, from: $0.ivs, to: $1.ivs) }
        return (cuts, states.map { $0.last - $0.first })
    }
}
