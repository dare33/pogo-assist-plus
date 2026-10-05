import Foundation

/// A run of cards in a finished scan that all failed the same way: the likely cause is one thing (an alarm banner over the CP, the appraisal not opened), not each Pokémon. Pure: a value
/// computed from the scan's rows and unmatched items; nothing in the scan changes. It carries facts, never wording: the app words the resume instructions.
public struct TroubleStretch: Equatable {
    public enum Kind: String, Equatable {
        /// The CP was not on screen: rows flagged `cp-computed` (the CP was worked out from the HP and the bars) and unmatched items with reason `cp-not-read`.
        case cpHidden
        /// The IV bars were not read: rows with no IVs, or flagged `ivs-unread`. Only rows can fail this way (an unmatched item has no row to place it by).
        case barsUnread
        // There is no `nameUnread`: a card whose name could not be read is only an unmatched item (`name-not-read`), never a row, so it has no row to start or end a stretch at and no
        // neighbour to say where to resume from.
    }

    /// A row of the scan as the person would look for it in the game.
    public struct Card: Equatable {
        /// The row's position in `ScanResult.rows` (0-based; the row's own `index` is this plus one).
        public var position: Int
        public var name: String
        /// The CP as the scan has it: for a `cpHidden` row, the one worked out.
        public var cp: Int
    }

    public var kind: Kind
    /// Positions (0-based, in `ScanResult.rows`) of the first and last affected ROW.
    public var firstRow: Int
    public var lastRow: Int
    /// Cards affected: the failing rows plus the unread cards (`unreadCards`) placed inside the stretch. Clean rows allowed inside (`cleanRowsInside`) are not counted.
    public var count: Int
    /// The position of the last cleanly read row before the stretch, nil when the stretch starts the scan.
    public var rowBefore: Int?
    /// Unmatched `cp-not-read` cards inside the stretch (`cpHidden` only).
    public var unreadCards: Int
    /// Clean rows between failures that did not split the stretch (at most `TroubleStretches.maximumCleanGap` in a row).
    public var cleanRowsInside: Int
    public var firstCard: Card
    public var lastCard: Card
    /// The last cleanly read row before the stretch.
    public var cardBefore: Card?
    /// How many cards there are from the first affected card to the END of the scan, that first card included: rows, plus unmatched cards (`cp-not-read`, `name-not-read`, `stationed`, and a
    /// `blank-card` stretch's `count`) that are placed after it. Unmatched items whose frame cannot be placed among the rows are not counted. The app names the smallest command that covers it.
    public var cardsToEnd: Int
}

public enum TroubleStretches {
    /// A stretch needs this many failing cards in a row. A banner stays up for several seconds and a card passes in about 1.2 s, so a banner hides about five cards or more; a single card with
    /// a hidden CP or unread bars is normal (a changing card, an animation) and is never worth telling the person about.
    public static let defaultMinimum = 5
    /// Clean rows allowed between two failures of one stretch without ending it: a stretch is one cause, and a card that reads cleanly in the middle (a banner's gap, a lucky frame) must not
    /// split it into several. Two, so a stretch cannot be glued across a real recovery.
    public static let maximumCleanGap = 2

    public static func find(_ scan: ScanResult, minimum: Int = defaultMinimum) -> [TroubleStretch] {
        var out = [TroubleStretch]()
        for kind in [TroubleStretch.Kind.cpHidden, .barsUnread] { out += find(scan, kind: kind, minimum: minimum) }
        return out.sorted { ($0.firstRow, $0.kind.rawValue) < ($1.firstRow, $1.kind.rawValue) }
    }

    // MARK: - placing cards

    /// The number in a frame label ("r762" is 762), nil when there is none.
    static func frameNumber(_ label: String?) -> Int? {
        guard let label else { return nil }
        let digits = label.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    private enum Event { case row(Int), item(Int, frame: Int) }

    private static func hasFlag(_ r: ScanRow, _ prefix: String) -> Bool { r.flags.contains { $0 == prefix || $0.hasPrefix(prefix + ":") } }

    private static func fails(_ r: ScanRow, _ kind: TroubleStretch.Kind) -> Bool {
        switch kind {
        case .cpHidden: return hasFlag(r, "cp-computed")
        case .barsUnread: return r.ivs == nil || hasFlag(r, "ivs-unread")
        }
    }

    /// Rows and placed unmatched items in scan order. An item sits after the last row whose first frame is not later than its own; one with no frame number, or when the rows carry no frame
    /// numbers, is not placed.
    private static func events(_ scan: ScanResult) -> [Event] {
        let firsts = scan.rows.map { frameNumber($0.frames.first?.frame) }
        var after = [Int: [(Int, Int)]]()   // row position (-1 before the first) -> (frame number, item index)
        for (k, u) in scan.unmatched.enumerated() {
            guard let f = frameNumber(u.frame) else { continue }
            var p = -1
            for (i, rf) in firsts.enumerated() { if let rf, rf <= f { p = i } }
            if p == -1, !firsts.contains(where: { $0 != nil }) { continue }
            after[p, default: []].append((f, k))
        }
        var out = [Event]()
        for (f, k) in (after[-1] ?? []).sorted(by: { $0.0 < $1.0 }) { out.append(.item(k, frame: f)) }
        for i in scan.rows.indices {
            out.append(.row(i))
            for (f, k) in (after[i] ?? []).sorted(by: { $0.0 < $1.0 }) { out.append(.item(k, frame: f)) }
        }
        return out
    }

    private static func find(_ scan: ScanResult, kind: TroubleStretch.Kind, minimum: Int) -> [TroubleStretch] {
        let ev = events(scan)
        func failing(_ e: Event) -> Bool {
            switch e {
            case .row(let i): return fails(scan.rows[i], kind)
            case .item(let k, _): return kind == .cpHidden && scan.unmatched[k].reason == "cp-not-read"
            }
        }
        var stretches = [TroubleStretch]()
        var run = [Int](), gap = 0   // indexes into `ev` of the failures, clean rows since the last one
        func close() {
            defer { run = []; gap = 0 }
            let rowsHit = run.compactMap { i -> Int? in if case .row(let r) = ev[i] { return r } else { return nil } }
            guard run.count >= minimum, let firstRow = rowsHit.first, let lastRow = rowsHit.last else { return }
            let unread = run.count - rowsHit.count
            // clean rows between the first and the last failure of the run
            let cleanInside = ev[run.first!...run.last!].reduce(0) { n, e in if case .row(let r) = e, !fails(scan.rows[r], kind) { return n + 1 } else { return n } }
            func card(_ r: Int) -> TroubleStretch.Card { TroubleStretch.Card(position: r, name: scan.rows[r].name, cp: scan.rows[r].cp) }
            var before: Int?
            for i in stride(from: run.first! - 1, through: 0, by: -1) { if case .row(let r) = ev[i], !fails(scan.rows[r], kind) { before = r; break } }
            // From the first affected card (a row, or an unread card ahead of the first row) to the end.
            let start = run.first!
            var toEnd = 0
            for e in ev[start...] {
                switch e {
                case .row: toEnd += 1
                case .item(let k, _):
                    let u = scan.unmatched[k]
                    switch u.reason {
                    case "cp-not-read", "name-not-read", "stationed": toEnd += 1
                    case "blank-card": toEnd += max(1, u.count ?? 1)
                    default: break
                    }
                }
            }
            stretches.append(TroubleStretch(kind: kind, firstRow: firstRow, lastRow: lastRow, count: run.count, rowBefore: before, unreadCards: unread, cleanRowsInside: cleanInside,
                                            firstCard: card(firstRow), lastCard: card(lastRow), cardBefore: before.map(card), cardsToEnd: toEnd))
        }
        for (i, e) in ev.enumerated() {
            if failing(e) { run.append(i); gap = 0; continue }
            if case .row = e { gap += 1; if gap > maximumCleanGap { close() } }
        }
        close()
        return stretches
    }
}
