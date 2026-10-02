import Foundation
import PogoReader

/// A Swift post-pass over the JavaScript `finish()` result. It does not change the JavaScript logic or its
/// output: `CoreEngine.finish` stays a pass-through, and this layer reads its result and the readings and
/// adds what the JavaScript grouping cannot know. Two rules:
///
/// (a) Twin split. The JavaScript merges two identical neighbouring Pokémon (same name, CP, HP, bars) into
///     one row. A swipe tick (the luma signature seen by the extension, see `SwipeTicker`) that lies strictly
///     inside a row's time span, with card readings of that row on both sides of it at least `minSwipeGap`
///     (0.55 s: a swipe takes 0.6 s or more, so it fits) apart, means two Pokémon. The row is split at the tick
///     into rows with the same values; every row after the first is flagged `same-as-previous`. With no ticks
///     (a readings file without a log) rule (a) does nothing.
/// (b) Hidden-CP row. An `unmatched` entry with reason `cp-not-read` that has a name, an HP, settled bars and
///     exactly one value in `cpOptions` becomes a row, placed by its first frame, with that CP and the flag
///     `cp-computed:<cp>`. Its values (species, level, dust) come from running the JavaScript `finish` over
///     that Pokémon's own readings with the CP filled in, so the solver is the JavaScript one. Any other
///     `cp-not-read` entry stays in `unmatched`.
///
/// Rows are then renumbered, `review` is rebuilt from the rows that carry flags, and `changes` says which
/// refined rows Refine made.
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
        case reconcile([LiveRow])
    }

    /// Reconcile the JavaScript result with `LiveGrouper` run over the same readings and ticks. The JavaScript rows
    /// are the base for every value; `LiveGrouper` only says where the JavaScript merged two Pokemon or left one unread:
    ///
    /// - Twin: ONE JavaScript row whose time span covers TWO OR MORE consecutive `LiveGrouper` rows of the same name, with
    ///   equal or unread HP and bars, related CP, and the same HP and bars as the JavaScript row, becomes that many rows
    ///   (the JavaScript row's values; frames divided between the `LiveGrouper` rows' spans; every later one flagged
    ///   `same-as-previous`). If the `LiveGrouper` rows differ from each other or from the row in HP, bars or CP, nothing is
    ///   split and the place is recorded in `disagreements`.
    /// - Hidden CP: a `cp-not-read` entry (name, HP, settled bars, exactly one possible CP) becomes a row only when
    ///   `LiveGrouper` has a row for the same stretch and name whose CP is that option and was computed or recovered
    ///   (`cp-computed:` / `cp-recovered:`) AND no JavaScript row next to it in time is the same Pokemon (same name and HP,
    ///   bars equal or unread, CP the option). If one is, the entry is a duplicate of it and is dropped (a change of kind
    ///   `duplicateDropped`). Its values come from the JavaScript `finish`, as before.
    /// - Everything else `LiveGrouper` has and the JavaScript has not, or the reverse, is not applied (see `GrouperDiff`).
    public static func apply(to base: ScanResult, readings: [FrameReading], ticks: [Double], engine: CoreEngine, species: SpeciesTable? = try? SpeciesTable.bundled()) throws -> Refined {
        let live = GrouperDiff.liveRows(readings: readings, ticks: ticks, species: species)
        return try run(base, readings: readings, engine: engine, mode: .reconcile(live))
    }

    /// The first version: split at swipe ticks alone (no `LiveGrouper`) and turn every `cp-not-read` entry with one
    /// possible CP into a row. Kept for comparison and for readings with no ticks.
    public static func applyTickOnly(to base: ScanResult, readings: [FrameReading], ticks: [Double], engine: CoreEngine) throws -> Refined {
        try run(base, readings: readings, engine: engine, mode: .tickOnly(ticks.filter { $0.isFinite }.sorted()))
    }

    private static func run(_ base: ScanResult, readings: [FrameReading], engine: CoreEngine, mode: Mode) throws -> Refined {
        var labelIndex = [String: Int]()
        for (i, r) in readings.enumerated() { if let f = r.frame, labelIndex[f] == nil { labelIndex[f] = i } }

        struct Placed { var key: Int; var row: ScanRow; var change: (Change.Kind, String)? }
        var placed = [Placed]()
        var disagreements = [String]()

        // (a) twin split
        for (n, row) in base.rows.enumerated() {
            let fallback = n * 1000   // keeps unresolvable rows in the JavaScript's order relative to each other
            let pieces: [ScanRow], why: String
            switch mode {
            case .tickOnly(let ticks): pieces = ticks.isEmpty ? [row] : split(row, ticks: ticks); why = "at a swipe tick"
            case .reconcile(let live):
                let r = reconcileTwins(row, live: live)
                pieces = r.pieces; why = "where LiveGrouper has \(r.pieces.count) rows"
                if let note = r.disagreement { disagreements.append(note) }
            }
            for (k, piece) in pieces.enumerated() {
                let key = piece.frames.first?.frame.flatMap { labelIndex[$0] } ?? labelKey(piece, readings: readings) ?? Int.max / 2 + fallback
                placed.append(Placed(key: key, row: piece, change: k == 0 ? nil : (.twinSplit, "\(row.display) CP \(row.cp): split from the row before \(why)")))
            }
        }

        // (b) hidden-CP rows
        var unmatched = [Unmatched](), notices = [String]()
        var dropped = [(of: ScanRow, text: String)]()
        for u in base.unmatched {
            if case .reconcile(let live) = mode {
                switch hiddenGate(u, readings: readings, labelIndex: labelIndex, live: live, rows: base.rows) {
                case .keep: unmatched.append(u); continue
                case .duplicate(let of): dropped.append((of, "unmatched \(u.name ?? "?") at \(u.frame ?? "?") is the same Pokemon as \(of.display) CP \(of.cp) beside it; dropped")); continue
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

    /// The row as the pieces `LiveGrouper` shows, or [row] when it does not show two or more.
    static func reconcileTwins(_ row: ScanRow, live: [LiveRow]) -> (pieces: [ScanRow], disagreement: String?) {
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
            if n > 0 {
                let p = group[n - 1]
                if !agrees(p.hp, l.hp) || !agrees(p.ivs, l.ivs) || !cpRelated(p.cp, l.cp) { return ([row], "grouper-disagrees: \(label): the \(group.count) LiveGrouper rows differ from each other in HP, bars or CP") }
            }
        }
        // Frames go to the LiveGrouper row they fall in; the cut is halfway between one row's end and the next one's start.
        let cuts = zip(group, group.dropFirst()).map { (($0.lastTime ?? 0) + ($1.firstTime ?? 0)) / 2 }
        let frames = row.frames.sorted { $0.time! < $1.time! }
        var parts = [[FrameLabel]](repeating: [], count: group.count)
        for f in frames { parts[cuts.filter { $0 <= f.time! }.count].append(f) }
        guard parts.allSatisfy({ !$0.isEmpty }) else { return ([row], "grouper-disagrees: \(label): \(group.count) LiveGrouper rows but a part of the row has no frames") }
        return (parts.enumerated().map { k, frames in
            var r = row
            r.frames = frames
            if k > 0 && !r.flags.contains("same-as-previous") { r.flags.append("same-as-previous") }
            return r
        }, nil)
    }

    private enum Gate { case keep, convert, duplicate(of: ScanRow) }

    /// Reconciliation's rule for one `cp-not-read` entry (see `apply`).
    private static func hiddenGate(_ u: Unmatched, readings: [FrameReading], labelIndex: [String: Int], live: [LiveRow], rows: [ScanRow]) -> Gate {
        guard u.reason == "cp-not-read", let name = u.name, !name.isEmpty, let hp = u.hp, let ivs = u.ivs,
              let options = u.cpOptions, options.count == 1, let cp = options.first,
              let frame = u.frame, let start = labelIndex[frame] else { return .keep }
        // The stretch: this entry's readings (name, no CP) from its first frame.
        var times = [Double]()
        var i = start
        while i < readings.count {
            let r = readings[i]
            if r.cp != nil { break }
            if let n = r.name, n != name { break }
            if r.name == name, let t = r.time { times.append(t) }
            i += 1
        }
        guard let t0 = times.min(), let t1 = times.max() else { return .keep }
        // A JavaScript row beside it in time (the last one starting before the stretch, the first one after it) that is
        // this Pokemon: same name and HP, bars equal or unread, and the CP is one the entry allows.
        func isSame(_ r: ScanRow) -> Bool {
            (r.display == name || r.name == name) && r.hp == hp && agrees(r.ivs ?? r.ivsRead, ivs) && options.contains(r.cp)
        }
        let before = rows.last { ($0.frames.compactMap(\.time).min() ?? .infinity) <= t0 }
        let after = rows.first { ($0.frames.compactMap(\.time).min() ?? -.infinity) > t0 }
        for r in [before, after].compactMap({ $0 }) where isSame(r) {
            // beside it: it ends close to the stretch start, or starts close to the stretch end
            let rs = rowSpan(r)
            if let rs, (rs.1 >= t0 - 2.5 && rs.0 <= t1 + 2.5) { return .duplicate(of: r) }
        }
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
        // The Pokémon's own readings: from its first frame, those with this name and no CP, skipping unreadable
        // frames, up to the next card of anything else. (The JavaScript's stretch is the same frames.)
        var own = [FrameReading]()
        var i = start
        while i < readings.count {
            let r = readings[i]
            if r.cp != nil { break }
            if let n = r.name, n != name { break }
            if r.name == name { var c = r; c.cp = cp; c.cpText = String(cp); c.cpReads = nil; own.append(c) }   // no partial reads: the JS would rank those, not the CP
            i += 1
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
