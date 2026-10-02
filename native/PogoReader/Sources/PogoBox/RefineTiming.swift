import Foundation
import PogoReader

/// What the app knows about how the scan was paged. All optional: with no hint the timing rule works from the measured beat.
public struct PagingHint: Equatable {
    /// False: the player paged by hand, the beat means nothing, the timing split is off.
    public var pagedByCommand: Bool
    /// The period the generated command was written for, in seconds. Voice Control plays about 5% slower, so this is a
    /// sanity check (the measured period must be within 25% of it), not the period used.
    public var expectedPeriod: Double?
    /// Extra seconds a chain of batches adds at each join (about 0.8). Nil means that default; 0 means there are no joins.
    public var joinExtraSeconds: Double?

    public init(pagedByCommand: Bool = true, expectedPeriod: Double? = nil, joinExtraSeconds: Double? = nil) {
        self.pagedByCommand = pagedByCommand; self.expectedPeriod = expectedPeriod; self.joinExtraSeconds = joinExtraSeconds
    }
}

extension Refine {
    /// A row's beat is regular when the stays of up to six interior rows each side (at least three each side) have a median
    /// absolute deviation within `ScanPace.regularityTolerance` of their median and each side's median is within this
    /// fraction of the combined one.
    public static let timingSideTolerance = 0.12
    /// A stay is a whole number of periods (n >= 2) when it is within this fraction of a period of n periods. A quarter
    /// would be the widest sensible (a reading time jitters by up to a frame or two each end of a stay, 0.1 to 0.2 of a period);
    /// 0.2 keeps a batch join (one period plus 0.8 s) from passing as two periods at a 1.0 s beat.
    public static let timingMultipleTolerance = 0.2
    public static let defaultJoinExtraSeconds = 0.8
    /// Readings with neither a CP nor an HP (the menu, a notification, a swipe in progress) allowed inside a row's own span.
    /// A tap changes the card within a frame and a fast swipe leaves one or two unreadable frames; the menu, the notification
    /// centre and an animation that hides the card leave three or more (measured on the labelled false twins: 3 to 11).
    public static let timingMaxUnreadInside = 2
    /// Only pairs are split: a stay of three or more periods is more often a page that did not take, a pause or an open menu
    /// than three identical Pokemon in a row (darentas-03, paged by a gesture on a steady 2.1 s beat, has stays of 3, 5 and 7 periods
    /// on single Pokemon: the finger was shown touching while the card stayed).
    public static let timingMaxCopies = 2
    /// With no hint from the app (it did not say the paging was a generated command) the rule is stricter: the beat must be
    /// regular as a whole scan to this (`ScanPace.regularity` over every stay; the local test below still applies) and no faster
    /// than `timingMinimumPeriod`, the fastest beat the app generates. Locally, hand tapping measures as regular as a command to
    /// within the reading-time jitter (darentas-02: 0.05 to 0.1 around a stay at about 1.0 s); over the whole scan the paced runs
    /// measure 0.03 to 0.06 and the hand-tapped ones 0.11 to 0.22. The hint says outright.
    public static let timingStrictRegularity = 0.07
    public static let timingMinimumPeriod = 1.0

    /// Timing-based twin split, a step after the others. Pure: scan in, scan out.
    ///
    /// A command pages on a steady beat, so a Pokemon that stayed n periods (n >= 2) was n identical Pokemon in a row, whether or
    /// not any swipe was seen (a tap leaves no `mid-swipe` reading). The row is split into n identical rows, the later ones
    /// flagged `same-as-previous` and `split-by-timing`, its frames divided by time. Only when all of these hold:
    /// - the row is not the first (on screen before the command starts) or the last (the list ends there and the last
    ///   Pokemon stays);
    /// - the beat around it is regular (see `timingSideTolerance`) with at least three measured stays each side (stricter with no
    ///   hint, see `timingStrictRegularity`), and n is 2 (`timingMaxCopies`);
    /// - nothing read inside the row changes (HP, settled bars): that is not a twin; and at most `timingMaxUnreadInside` readings
///   inside its span show no card at all (a menu or notification open on one Pokemon is not a beat);
    /// - the stay is n periods within `timingMultipleTolerance`, tried as n periods and as n periods plus one batch join
    ///   (`joinExtraSeconds`), taking whichever fits better. A stay that fits "one period plus a join" best is a join, not a twin;
    ///   one that fits "n periods plus a join" best is split in n (a twin at a join), as the arithmetic allows;
    /// - each piece would hold at least one reading.
    public static func splitByTiming(_ scan: ScanResult, readings: [FrameReading], paging: PagingHint? = nil) -> (scan: ScanResult, changes: [Change], notices: [String], indexMap: [Int: Int]) {
        if let p = paging, !p.pagedByCommand { return (scan, [], [], [:]) }
        let rows = scan.rows
        let optSpans = ScanPace.spans(of: rows)
        guard rows.count >= 9, optSpans.allSatisfy({ $0 != nil }) else { return (scan, [], [], [:]) }
        let spans = optSpans.compactMap { $0 }
        let boundaries = ScanPace.boundaries(spans: spans)
        let stays = ScanPace.stays(spans: spans)
        let join = paging?.joinExtraSeconds ?? defaultJoinExtraSeconds
        if paging == nil {
            guard let whole = ScanPace.measure(spans: spans), whole.regularity <= timingStrictRegularity else { return (scan, [], [], [:]) }
        }

        var out = [ScanRow](), changes = [Change](), notices = [String]()
        var placed = [(row: ScanRow, change: String?)]()
        for (i, row) in rows.enumerated() {
            guard let stay = stays[i], i >= 1, i <= rows.count - 2, let startB = boundaries[i - 1] else { placed.append((row, nil)); continue }
            let left = stays[max(1, i - 6)..<i].compactMap { $0 }
            let right = i + 1 <= rows.count - 2 ? stays[(i + 1)...min(rows.count - 2, i + 6)].compactMap { $0 } : []
            guard left.count >= 3, right.count >= 3, let all = ScanPace.relativeMAD(left + right), all.mad <= ScanPace.regularityTolerance,
                  let lm = ScanPace.median(left), let rm = ScanPace.median(right),
                  abs(lm - all.median) <= timingSideTolerance * all.median, abs(rm - all.median) <= timingSideTolerance * all.median
            else { placed.append((row, nil)); continue }
            let period = all.median
            if paging == nil && period < timingMinimumPeriod { placed.append((row, nil)); continue }
            if let expected = paging?.expectedPeriod, abs(period - expected) > 0.25 * expected { placed.append((row, nil)); continue }
            guard readingsAgree(row), unreadInside(row, readings: readings) <= timingMaxUnreadInside else { placed.append((row, nil)); continue }
            // n periods, or n periods plus a join: the better fit decides.
            var best: (n: Int, resid: Double, joined: Bool)?
            for joined in join > 0 ? [false, true] : [false] {
                let extra = joined ? join : 0
                let n = Int(((stay - extra) / period).rounded())
                guard n >= 1 else { continue }
                let resid = abs(stay - (Double(n) * period + extra))
                if best == nil || resid < best!.resid { best = (n, resid, joined) }
            }
            guard let b = best, b.n >= 2, b.n <= timingMaxCopies, b.resid <= timingMultipleTolerance * period else { placed.append((row, nil)); continue }
            guard row.frames.allSatisfy({ $0.time != nil }) else { placed.append((row, nil)); continue }
            let frames = row.frames.sorted { ($0.time ?? 0) < ($1.time ?? 0) }
            var parts = [[FrameLabel]](repeating: [], count: b.n)
            for f in frames { parts[min(b.n - 1, max(0, Int((((f.time ?? startB) - startB) / stay * Double(b.n)).rounded(.down))))].append(f) }
            guard parts.allSatisfy({ !$0.isEmpty }) else {
                notices.append("timing: \(row.display) CP \(row.cp) stayed \(String(format: "%.1f", stay)) s (\(b.n) periods of \(String(format: "%.2f", period)) s) but a piece would have no readings: not split")
                placed.append((row, nil)); continue
            }
            let detail = "\(row.display) CP \(row.cp): stayed \(String(format: "%.1f", stay)) s, \(b.n) periods of \(String(format: "%.2f", period)) s\(b.joined ? " plus a batch join" : "")"
            for (k, part) in parts.enumerated() {
                var r = row
                r.frames = part
                if k > 0 { for f in ["same-as-previous", "split-by-timing"] where !r.flags.contains(f) { r.flags.append(f) } }
                placed.append((r, k == 0 ? nil : detail))
            }
        }
        var indexMap = [Int: Int]()
        for (k, p) in placed.enumerated() {
            var r = p.row
            if p.change == nil { indexMap[r.index] = k + 1 }   // a row that is not a later piece keeps its place, renumbered
            r.index = k + 1
            out.append(r)
            if let d = p.change { changes.append(Change(kind: .timingSplit, rowIndex: r.index, detail: d)) }
        }
        guard !changes.isEmpty else { return (scan, [], notices, [:]) }
        return (ScanResult(rows: out, review: out.filter { !$0.flags.isEmpty }.map(reviewEntry), unmatched: scan.unmatched), changes, notices, indexMap)
    }

    /// How many readings between a row's first and last card reading carry neither a CP nor an HP.
    static func unreadInside(_ row: ScanRow, readings: [FrameReading]) -> Int {
        let ts = row.frames.compactMap(\.time)
        guard let a = ts.min(), let b = ts.max() else { return 0 }
        var n = 0
        for r in readings {
            guard let t = r.time, t > a, t < b else { continue }
            if r.cp == nil && r.hp == nil { n += 1 }
        }
        return n
    }

    /// True when the readings inside a row are of one Pokemon: one HP and one set of settled bars.
    static func readingsAgree(_ row: ScanRow) -> Bool {
        let hps = Set(row.frames.compactMap(\.hp))
        let ivs = Set(row.frames.filter { ($0.ivConfidence ?? 0) >= 0.7 }.compactMap(\.ivs))
        // (CP reads are not compared: a dropped or doubled digit in one frame is a misread, and the row's CP is voted.)
        return hps.count <= 1 && ivs.count <= 1
    }
}
