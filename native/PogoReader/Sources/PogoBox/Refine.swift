import Foundation
import PogoReader

/// A Swift post-pass over the JavaScript `finish()` result. It does not change the JavaScript logic or its output:
/// `CoreEngine.finish` stays a pure pass-through, and this layer reads its result and the readings and adds what the
/// JavaScript grouping cannot know. `apply` reconciles the result with `LiveGrouper` (run over the same readings and
/// ticks); the JavaScript rows are the base for every value. Three rules, each needing evidence of a real swipe or of a
/// real second Pokemon, because `LiveGrouper` cuts one Pokemon in pieces when the menu or the notification centre opens,
/// the team leader covers the CP or a frame is missing (see TwinSplitTests, cut from real clips):
///
/// (a) Twin split. ONE JavaScript row whose time span covers two or more consecutive `LiveGrouper` rows of the same name,
///     the same HP and bars (each other's and the row's) and related CP is cut where the pieces' card readings are at
///     least `minSwipeGap` (0.55 s, a swipe takes 0.6 s or more) apart AND at least one reading in that gap is flagged
///     `mid-swipe` (the card sliding sideways). Later pieces are flagged `same-as-previous`. HP, bars or CP that disagree
///     are recorded in `disagreements` and nothing is split.
/// (b) Hidden-CP row. An `unmatched` `cp-not-read` entry with a name, an HP, settled bars and exactly one possible CP
///     becomes a row (`cp-computed:<cp>`, values from the JavaScript `finish` over the entry's own readings) when
///     `LiveGrouper` has a row for the stretch with that CP computed or recovered.
/// (c) Duplicate. Such an entry is dropped only when it is the Pokemon on the row beside it: same name and HP, that row's
///     CP is the option, settled bars equal on both sides, no swipe evidence between the two (no tick, no `mid-swipe`
///     reading, no 0.55 s gap between card readings) and `LiveGrouper` has no row of its own for the stretch. The row that
///     absorbed it gets the flag `absorbed-unread` (so it shows in `review`) and `changes` records it.
///
/// Rows are renumbered, `review` is rebuilt from the rows that carry flags, and `changes` says what Refine did. Readings
/// without frame labels are labelled `r<n>` (by position) and the JavaScript is run again on them, so the rows it returns
/// carry those labels. `applyTickOnly` is the first, tick-only version (no `LiveGrouper`).
public enum Refine {
    /// A swipe needs at least this long, so card readings closer than this cannot have a swipe between them.
    public static let minSwipeGap = 0.55

    public struct Change: Equatable {
        public enum Kind: String { case twinSplit, hiddenCP, duplicateDropped }
        public var kind: Kind
        /// The row's index in the refined result.
        public var rowIndex: Int
        public var detail: String
    }

    public struct Refined: Equatable {
        public var scan: ScanResult
        /// How many rows the JavaScript gave.
        public var baseRowCount: Int
        public var changes: [Change]
        /// Entries Refine could have converted but the JavaScript refused (an exception): they stay as they were.
        public var notices: [String] = []
        /// Reconciliation only: places where `LiveGrouper` and the JavaScript row disagree (HP, bars, CP) and nothing was split.
        public var disagreements: [String] = []
    }

    private enum Mode {
        case tickOnly([Double])
        case reconcile([LiveRow], [Double])
    }

    /// Reconcile the JavaScript result with `LiveGrouper` over the same readings and ticks (rules in the type's description).
    public static func apply(to base: ScanResult, readings: [FrameReading], ticks: [Double], engine: CoreEngine, species: SpeciesTable? = try? SpeciesTable.bundled()) throws -> Refined {
        let live = GrouperDiff.liveRows(readings: readings, ticks: ticks, species: species)
        return try run(base, readings: readings, engine: engine, mode: .reconcile(live, ticks.filter { $0.isFinite }.sorted()))
    }

    /// The first version: split at swipe ticks alone (no `LiveGrouper`) and turn every `cp-not-read` entry with one
    /// possible CP into a row. Kept for comparison and for readings with no ticks.
    public static func applyTickOnly(to base: ScanResult, readings: [FrameReading], ticks: [Double], engine: CoreEngine) throws -> Refined {
        try run(base, readings: readings, engine: engine, mode: .tickOnly(ticks.filter { $0.isFinite }.sorted()))
    }

    private static func run(_ base: ScanResult, readings: [FrameReading], engine: CoreEngine, mode: Mode) throws -> Refined {
        var base = base, readings = readings
        // Rows and entries find their readings by frame label. Readings with none (ReplayLog.frameReading) get one by
        // position, and the JavaScript is run again so that its rows and entries carry the labels.
        if readings.contains(where: { $0.frame == nil }) {
            for i in readings.indices where readings[i].frame == nil { readings[i].frame = "r\(i + 1)" }
            base = try engine.finish(readings: readings)
        }
        var labelIndex = [String: Int]()
        for (i, r) in readings.enumerated() { if let f = r.frame, labelIndex[f] == nil { labelIndex[f] = i } }

        struct Placed { var key: Int; var row: ScanRow; var change: (Change.Kind, String)?; var baseIndex: Int? = nil }
        var placed = [Placed]()
        var disagreements = [String]()

        // (a) twin split
        for (n, row) in base.rows.enumerated() {
            let fallback = n * 1000   // keeps unresolvable rows in the JavaScript's order relative to each other
            let pieces: [ScanRow], why: String
            switch mode {
            case .tickOnly(let ticks): pieces = ticks.isEmpty ? [row] : split(row, ticks: ticks); why = "at a swipe tick"
            case .reconcile(let live, _):
                let r = reconcileTwins(row, live: live, readings: readings)
                pieces = r.pieces; why = "where LiveGrouper has \(r.pieces.count) rows"
                if let note = r.disagreement { disagreements.append(note) }
            }
            for (k, piece) in pieces.enumerated() {
                let key = piece.frames.first?.frame.flatMap { labelIndex[$0] } ?? labelKey(piece, readings: readings) ?? Int.max / 2 + fallback
                placed.append(Placed(key: key, row: piece, change: k == 0 ? nil : (.twinSplit, "\(row.display) CP \(row.cp): split from the row before \(why)"), baseIndex: n))
            }
        }

        // (b) hidden-CP rows
        var unmatched = [Unmatched](), notices = [String]()
        var dropped = [(of: ScanRow, text: String)]()
        for u in base.unmatched {
            if case .reconcile(let live, let ticks) = mode {
                switch hiddenGate(u, readings: readings, labelIndex: labelIndex, live: live, ticks: ticks, rows: base.rows) {
                case .keep: unmatched.append(u); continue
                case .duplicate(let n, let at):
                    let of = base.rows[n]
                    // the row that absorbed it says so (and so shows in review)
                    if let k = placed.firstIndex(where: { $0.baseIndex == n && $0.row.frames.contains { $0.time == at } }) ?? placed.firstIndex(where: { $0.baseIndex == n }) {
                        if !placed[k].row.flags.contains("absorbed-unread") { placed[k].row.flags.append("absorbed-unread") }
                    }
                    dropped.append((of, "unmatched \(u.name ?? "?") at \(u.frame ?? "?") is the same Pokemon as \(of.display) CP \(of.cp) beside it; dropped, the row is flagged absorbed-unread")); continue
                case .convert: break
                }
            }
            do {
                if let (row, key) = try hiddenRow(u, readings: readings, labelIndex: labelIndex, engine: engine) {
                    placed.append(Placed(key: key, row: row, change: (.hiddenCP, "\(row.display) CP \(row.cp): computed from HP and bars, was unmatched")))
                } else { unmatched.append(u) }
            } catch CoreEngine.Failure.script(let message, _) {
                // One Pokémon the JavaScript cannot solve must not lose the whole scan: it stays unmatched.
                unmatched.append(u)
                notices.append("\(u.name ?? "?") at \(u.frame ?? "?"): left unmatched, the JavaScript failed on it: \(message)")
            }
        }

        // Stable order by first frame; rows from the JavaScript keep their order among equal keys.
        let order = placed.enumerated().sorted { ($0.element.key, $0.offset) < ($1.element.key, $1.offset) }.map(\.element)
        var rows = [ScanRow](), changes = [Change]()
        for (i, p) in order.enumerated() {
            var row = p.row
            row.index = i + 1
            rows.append(row)
            if let (kind, detail) = p.change { changes.append(Change(kind: kind, rowIndex: row.index, detail: detail)) }
        }
        for d in dropped {
            let at = rows.firstIndex { $0.cp == d.of.cp && $0.frames.first?.frame == d.of.frames.first?.frame && $0.frames.first?.time == d.of.frames.first?.time }
            changes.append(Change(kind: .duplicateDropped, rowIndex: at.map { rows[$0].index } ?? 0, detail: d.text))
        }
        let review = rows.filter { !$0.flags.isEmpty }.map(reviewEntry)
        return Refined(scan: ScanResult(rows: rows, review: review, unmatched: unmatched), baseRowCount: base.rows.count, changes: changes, notices: notices, disagreements: disagreements)
    }

    // MARK: - (a)

    /// The row cut at every tick that passes the rule; the row itself when none does.
    static func split(_ row: ScanRow, ticks: [Double]) -> [ScanRow] {
        guard row.frames.count >= 2, row.frames.allSatisfy({ $0.time != nil }) else { return [row] }
        let frames = row.frames.sorted { $0.time! < $1.time! }
        guard let first = frames.first?.time, let last = frames.last?.time else { return [row] }
        var parts = [frames]
        for t in ticks where t > first && t < last {
            let current = parts[parts.count - 1]
            let cards = current.filter { $0.cp != nil }
            guard let before = cards.last(where: { $0.time! < t }), let after = cards.first(where: { $0.time! >= t }) else { continue }
            guard after.time! - before.time! >= minSwipeGap - 1e-9 else { continue }
            parts[parts.count - 1] = current.filter { $0.time! < t }
            parts.append(current.filter { $0.time! >= t })
        }
        guard parts.count > 1 else { return [row] }
        return parts.enumerated().map { k, frames in
            var r = row
            r.frames = frames
            if k > 0 && !r.flags.contains("same-as-previous") { r.flags.append("same-as-previous") }
            return r
        }
    }

    private static func labelKey(_ row: ScanRow, readings: [FrameReading]) -> Int? {
        guard let t = row.frames.first?.time else { return nil }
        return readings.firstIndex { ($0.time ?? -1) >= t }
    }

    // MARK: - reconciliation with LiveGrouper

    private static func sameName(_ r: ScanRow, _ l: LiveRow) -> Bool { l.name == r.display || l.name == r.name }
    /// CP the same Pokemon can show: equal, one unread, or one the tail of the other ("919" read of 1919).
    private static func cpRelated(_ a: Int?, _ b: Int?) -> Bool {
        guard let a, let b else { return true }
        return a == b || String(a).hasSuffix(String(b)) || String(b).hasSuffix(String(a))
    }
    private static func agrees<T: Equatable>(_ a: T?, _ b: T?) -> Bool { a == nil || b == nil || a == b }

    static func rowSpan(_ row: ScanRow) -> (Double, Double)? {
        let ts = row.frames.compactMap(\.time)
        guard let a = ts.min(), let b = ts.max() else { return nil }
        return (a, b)
    }

    /// The row as the pieces `LiveGrouper` shows, cut only where a swipe is evidenced; [row] when it is not cut.
    static func reconcileTwins(_ row: ScanRow, live: [LiveRow], readings: [FrameReading]) -> (pieces: [ScanRow], disagreement: String?) {
        guard let (first, last) = rowSpan(row), row.frames.allSatisfy({ $0.time != nil }) else { return ([row], nil) }
        // LiveGrouper rows of this name that sit in the row's time span (midpoint inside, a quarter second of slack).
        let inside = live.indices.filter { i in
            guard sameName(row, live[i]), let a = live[i].firstTime, let b = live[i].lastTime else { return false }
            let mid = (a + b) / 2
            return mid >= first - 0.25 && mid <= last + 0.25
        }
        guard inside.count >= 2 else { return ([row], nil) }
        // They must be next to each other in LiveGrouper's order: another Pokemon between them is not a twin.
        guard zip(inside, inside.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { return ([row], nil) }
        let group = inside.map { live[$0] }
        let label = "\(row.display) CP \(row.cp) at \(String(format: "%.1f", first)) s"
        let rowIvs = row.ivs ?? row.ivsRead
        for (n, l) in group.enumerated() {
            if !agrees(l.hp, row.hp) { return ([row], "grouper-disagrees: \(label): LiveGrouper row \(n + 1) of \(group.count) has HP \(l.hp.map(String.init) ?? "?"), the JavaScript row \(row.hp.map(String.init) ?? "?")") }
            if !agrees(l.ivs, rowIvs) { return ([row], "grouper-disagrees: \(label): LiveGrouper row \(n + 1) of \(group.count) has different bars") }
            if !cpRelated(l.cp, row.cp) { return ([row], "grouper-disagrees: \(label): LiveGrouper row \(n + 1) of \(group.count) has CP \(l.cp.map(String.init) ?? "?"), the JavaScript row \(row.cp)") }
            if n > 0 {
                let p = group[n - 1]
                if !agrees(p.hp, l.hp) || !agrees(p.ivs, l.ivs) || !cpRelated(p.cp, l.cp) { return ([row], "grouper-disagrees: \(label): the \(group.count) LiveGrouper rows differ from each other in HP, bars or CP") }
            }
        }
        // A cut needs a swipe: card readings of the row at least `minSwipeGap` apart across it AND a mid-swipe reading between them.
        let frames = row.frames.sorted { $0.time! < $1.time! }
        var cuts = [Double]()
        for (a, b) in zip(group, group.dropFirst()) {
            let cut = ((a.lastTime ?? 0) + (b.firstTime ?? 0)) / 2
            guard let before = frames.last(where: { $0.time! < cut }), let after = frames.first(where: { $0.time! >= cut }) else { continue }
            let (t0, t1) = (before.time!, after.time!)
            guard t1 - t0 >= minSwipeGap - 1e-9 else { continue }
            guard readings.contains(where: { ($0.time ?? -1) > t0 && ($0.time ?? -1) < t1 && $0.flags.contains("mid-swipe") }) else { continue }
            cuts.append(cut)
        }
        guard !cuts.isEmpty else { return ([row], nil) }
        var parts = [[FrameLabel]](repeating: [], count: cuts.count + 1)
        for f in frames { parts[cuts.filter { $0 <= f.time! }.count].append(f) }
        guard parts.allSatisfy({ !$0.isEmpty }) else { return ([row], "grouper-disagrees: \(label): a part of the cut row would have no frames") }
        return (parts.enumerated().map { k, frames in
            var r = row
            r.frames = frames
            if k > 0 && !r.flags.contains("same-as-previous") { r.flags.append("same-as-previous") }
            return r
        }, nil)
    }

    private enum Gate { case keep, convert, duplicate(of: Int, at: Double) }

    /// The readings of an unmatched entry's stretch: from its first frame, those with its name and no CP, up to the
    /// `frames` the JavaScript counted for it (so it stops where the JavaScript's stretch stopped, not at a following
    /// entry of the same species), skipping unreadable frames, up to the next card of anything else.
    static func stretch(_ u: Unmatched, name: String, readings: [FrameReading], start: Int) -> [Int] {
        var out = [Int](), i = start
        let limit = u.frames ?? Int.max
        while i < readings.count, out.count < limit {
            let r = readings[i]
            if r.cp != nil { break }
            if let n = r.name, n != name { break }
            if r.name == name { out.append(i) }
            i += 1
        }
        return out
    }

    /// Evidence of a swipe between two times: a tick, a `mid-swipe` reading, or card readings (a CP or an HP read)
    /// at least `minSwipeGap` apart with nothing card-like between them.
    static func swipeEvidence(from a: Double, to b: Double, readings: [FrameReading], ticks: [Double]) -> Bool {
        if ticks.contains(where: { $0 > a && $0 <= b }) { return true }
        let between = readings.filter { ($0.time ?? -1) >= a && ($0.time ?? -1) <= b }
        if between.contains(where: { $0.flags.contains("mid-swipe") }) { return true }
        let cardTimes = between.filter { $0.cp != nil || $0.hp != nil }.compactMap(\.time)
        let edges = [a] + cardTimes + [b]
        return zip(edges, edges.dropFirst()).contains { $1 - $0 >= minSwipeGap - 1e-9 }
    }

    /// Reconciliation's rule for one `cp-not-read` entry (see the type's description).
    private static func hiddenGate(_ u: Unmatched, readings: [FrameReading], labelIndex: [String: Int], live: [LiveRow], ticks: [Double], rows: [ScanRow]) -> Gate {
        guard u.reason == "cp-not-read", let name = u.name, !name.isEmpty, let hp = u.hp, let ivs = u.ivs,
              let options = u.cpOptions, options.count == 1, let cp = options.first,
              let frame = u.frame, let start = labelIndex[frame] else { return .keep }
        let times = stretch(u, name: name, readings: readings, start: start).compactMap { readings[$0].time }
        guard let t0 = times.min(), let t1 = times.max() else { return .keep }
        // (c) a duplicate of the row beside it: the same Pokemon, settled equal bars, no swipe between, and LiveGrouper
        // has no row of its own for the stretch.
        func rowStart(_ r: ScanRow) -> Double { r.frames.compactMap(\.time).min() ?? .infinity }
        let beforeIdx = rows.indices.last { rowStart(rows[$0]) <= t0 }
        let afterIdx = rows.indices.first { rowStart(rows[$0]) > t0 }
        for candidate in [(beforeIdx, true), (afterIdx, false)] {
            guard let n = candidate.0 else { continue }
            let r = rows[n]
            let times = r.frames.compactMap(\.time)
            guard (r.display == name || r.name == name), r.hp == hp, options.contains(r.cp),
                  let rIvs = r.ivs, rIvs == ivs, !r.flags.contains("bars-unsettled"),
                  let tn = candidate.1 ? times.filter({ $0 <= t0 }).max() : times.filter({ $0 >= t1 }).min() else { continue }
            let (a, b) = candidate.1 ? (tn, t0) : (t1, tn)
            guard a <= b, !swipeEvidence(from: a, to: b, readings: readings, ticks: ticks) else { continue }
            return .duplicate(of: n, at: tn)
        }
        // (b) LiveGrouper has a row for the stretch with this CP computed or recovered.
        let hasRow = live.contains { l in
            guard l.name == name, l.cp == cp, let a = l.firstTime, let b = l.lastTime, a <= t1 && b >= t0 else { return false }
            return l.flags.contains { $0.hasPrefix("cp-computed:") || $0.hasPrefix("cp-recovered:") }
        }
        return hasRow ? .convert : .keep
    }

    // MARK: - (b)

    private static func hiddenRow(_ u: Unmatched, readings: [FrameReading], labelIndex: [String: Int], engine: CoreEngine) throws -> (ScanRow, Int)? {
        guard u.reason == "cp-not-read", let name = u.name, !name.isEmpty, let hp = u.hp, u.ivs != nil,
              let options = u.cpOptions, options.count == 1, let cp = options.first,
              let frame = u.frame, let start = labelIndex[frame] else { return nil }
        // The Pokémon's own readings: the entry's stretch (as many frames as the JavaScript counted for it).
        let own: [FrameReading] = stretch(u, name: name, readings: readings, start: start).map { i in
            var c = readings[i]; c.cp = cp; c.cpText = String(cp); c.cpReads = nil   // no partial reads: the JS would rank those, not the CP
            return c
        }
        guard !own.isEmpty else { return nil }
        let result = try engine.finish(readings: own)
        guard result.rows.count == 1, var row = result.rows.first, row.cp == cp, row.hp == nil || row.hp == hp else { return nil }
        row.flags.append("cp-computed:\(cp)")
        return (row, start)
    }

    static func reviewEntry(_ r: ScanRow) -> ReviewEntry {
        ReviewEntry(index: r.index, name: r.name, cp: r.cp, hp: r.hp, ivs: r.ivs, ivsRead: r.ivsRead, ivsGuess: r.ivsGuess, level: r.level,
                    levelMax: r.levelMax, flags: r.flags, frames: r.frames, clip: r.clip, shadow: r.shadow)
    }
}
