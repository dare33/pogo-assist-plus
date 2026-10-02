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
        public enum Kind: String { case twinSplit, hiddenCP }
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
    }

    public static func apply(to base: ScanResult, readings: [FrameReading], ticks: [Double], engine: CoreEngine) throws -> Refined {
        var labelIndex = [String: Int]()
        for (i, r) in readings.enumerated() { if let f = r.frame, labelIndex[f] == nil { labelIndex[f] = i } }

        struct Placed { var key: Int; var row: ScanRow; var change: (Change.Kind, String)? }
        var placed = [Placed]()
        let sortedTicks = ticks.filter { $0.isFinite }.sorted()

        // (a) twin split
        for (n, row) in base.rows.enumerated() {
            let fallback = n * 1000   // keeps unresolvable rows in the JavaScript's order relative to each other
            let pieces = sortedTicks.isEmpty ? [row] : split(row, ticks: sortedTicks)
            for (k, piece) in pieces.enumerated() {
                let key = piece.frames.first?.frame.flatMap { labelIndex[$0] } ?? labelKey(piece, readings: readings) ?? Int.max / 2 + fallback
                placed.append(Placed(key: key, row: piece, change: k == 0 ? nil : (.twinSplit, "\(row.display) CP \(row.cp): split from the row before at a swipe tick")))
            }
        }

        // (b) hidden-CP rows
        var unmatched = [Unmatched](), notices = [String]()
        for u in base.unmatched {
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
        let review = rows.filter { !$0.flags.isEmpty }.map(reviewEntry)
        return Refined(scan: ScanResult(rows: rows, review: review, unmatched: unmatched), baseRowCount: base.rows.count, changes: changes, notices: notices)
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
