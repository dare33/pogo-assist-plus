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

    /// Step 1c: two different Pokemon joined into one row because the JavaScript grouping treats rows with the same name, CP and HP
    /// as one (their bars were `ivs-disagree`). Inside one row, when the settled bars change from one value to another, each value is
    /// held by at least two consecutive settled readings (confidence at or above `settledBarsConfidence`), and the change falls on a
    /// beat boundary, the row is cut at the change. With a regular beat each part lasts about one period (`barsSplitPartTolerance`)
    /// and the row about two; with no regular beat each state must have been held for about 0.6 of the command's period (and with none known the row is not split). Each part
    /// is solved again by the JavaScript on its own readings, so it gets its own bars, level and flags; the second row is flagged
    /// `split-by-bars` (not `same-as-previous`: they are different Pokemon).
    /// A single odd reading never splits a row: the first frame after a page is the previous Pokemon's bars moving to the new ones.
    static func splitByBars(_ scan: ScanResult, readings: [FrameReading], engine: CoreEngine, hintPeriod: Double? = nil) throws -> (scan: ScanResult, marks: [(label: String, detail: String)], notices: [String]) {
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
            guard let cut = barsChange(row, readings: readings, labelIndex: labelIndex) else { out.append(row); continue }
            // beat evidence
            if let p = period, !boundaries.isEmpty, n >= 1, n <= scan.rows.count - 2, let b0 = boundaries[n - 1], let b1 = boundaries[n] {
                let tol = barsSplitPartTolerance * p
                guard abs((cut.time - b0) - p) <= tol, abs((b1 - cut.time) - p) <= tol else { out.append(row); continue }
            } else {
                // No regular beat: real evidence, not a short gap (every gap at the tap reading rate is 0.4 s). With the command's period known, each
                // state must have been held for about 0.6 of it; with none known, the row is not split and keeps its `ivs-disagree`.
                guard let p = hintPeriod, cut.heldA >= barsSplitFallbackHeldPeriods * p, cut.heldB >= barsSplitFallbackHeldPeriods * p else { out.append(row); continue }
            }
            // each part solved on its own readings
            let parts = [row.frames.filter { $0.time! <= cut.time }, row.frames.filter { $0.time! > cut.time }]
            var solved = [ScanRow]()
            for part in parts {
                let own = part.compactMap { f in f.frame.flatMap { labelIndex[$0] }.map { readings[$0] } }
                guard own.count == part.count, let result = try? engine.finish(readings: own), result.rows.count == 1, let r = result.rows.first else { solved = []; break }
                solved.append(r)
            }
            guard solved.count == 2 else {
                notices.append("bars: \(row.display) CP \(row.cp) changes bars at \(String(format: "%.1f", cut.time)) s but a part could not be solved on its own: not split")
                out.append(row); continue
            }
            // BOTH parts are flagged: either may be the wrong one (the first can solve exactly on transient bars). Each keeps what the earlier steps
            // flagged on the row, and the original `ivs-disagree` is still a fact about the pair.
            for k in solved.indices {
                for carried in carriedFlags(row) where !solved[k].flags.contains(carried) { solved[k].flags.append(carried) }
                if !solved[k].flags.contains("split-by-bars") { solved[k].flags.append("split-by-bars") }
            }
            let detail = "\(row.display) CP \(row.cp): bars change \(cut.from) to \(cut.to) at \(String(format: "%.1f", cut.time)) s, each held by two or more readings: two Pokemon"
            marks.append((solved[1].frames.first?.frame ?? "", detail))
            out += solved
        }
        guard !marks.isEmpty else { return (scan, [], notices) }
        for k in out.indices { out[k].index = k + 1 }
        return (ScanResult(rows: out, review: out.filter { !$0.flags.isEmpty }.map(reviewEntry), unmatched: scan.unmatched), marks, notices)
    }

    /// Where a row's settled bars change from one state to another: the time of the cut (halfway between the last reading of the
    /// first state and the first of the second), the two values, and how long each state was held.
    private static func barsChange(_ row: ScanRow, readings: [FrameReading], labelIndex: [String: Int]) -> (time: Double, from: String, to: String, heldA: Double, heldB: Double)? {
        guard row.frames.allSatisfy({ $0.time != nil }) else { return nil }
        let frames = row.frames.sorted { $0.time! < $1.time! }
        let settled = frames.filter { ($0.ivConfidence ?? 0) >= settledBarsConfidence && $0.ivs != nil }
        // runs of equal bars among the settled readings, in time order
        var runs = [(ivs: String, items: [FrameLabel])]()
        for f in settled {
            if let last = runs.last, last.ivs == f.ivs! { runs[runs.count - 1].items.append(f) } else { runs.append((f.ivs!, [f])) }
        }
        let states = runs.enumerated().filter { $0.element.items.count >= barsStateMinReadings }
        guard states.count == 2, let a = states.first, let b = states.last, a.element.ivs != b.element.ivs else { return nil }
        // only one-reading runs (the animation) may lie between the two states
        guard b.offset - a.offset >= 1, runs[(a.offset + 1)..<b.offset].allSatisfy({ $0.items.count < barsStateMinReadings }) else { return nil }
        // a run of one reading BEFORE the first state or after the second is the animation or a misread: fine
        let lastA = a.element.items.last!.time!, firstB = b.element.items.first!.time!
        let cut = (lastA + firstB) / 2
        // how long each state was held (first to last settled reading)
        let heldA = lastA - a.element.items.first!.time!, heldB = b.element.items.last!.time! - firstB
        return (cut, a.element.ivs, b.element.ivs, heldA, heldB)
    }
}
