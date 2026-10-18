import Foundation

/// A card the command keeps tapping with its appraisal CLOSED reads, tap after tap, with the SAME name and HP, no bars, and a CP that a tap partly covers (run17: Staraptor 1999 read as
/// 1299, 1099, 199, 1209, 29, 129, 1129, ... or not at all). Those readings are the stalled card, not other Pokémon: the grouper must not make rows of them, and the end logic must not take a new
/// CP value on the same name and HP for a new card. A card with bars read is the anchor; the barless readings of the same name and HP that follow it, whatever CP they show, take the card's CP.
///
/// Two forms: `feed`, one reading at a time for the extension's live grouper (the progress count and the pause's `read` must not inflate), and `normalise`, over a whole log for the pipeline
/// (a stretch of at least `minTail` barless readings, so a new twin's first barless readings, before its bars settle, are left to the usual rules).
public struct StalledCardNormaliser {
    public init() {}
    public static let minTail = 8

    private var anchor: (name: String, hp: HP, cp: Int?)?

    /// One reading at a time. A reading with bars sets the anchor; a barless reading of the anchor's name and HP gets the anchor's CP; any other card reading drops the anchor.
    public mutating func feed(_ r: FrameReading) -> FrameReading {
        guard let name = r.name, let hp = r.hp else { return r }       // not a whole card reading (name and HP): says nothing
        if r.ivs != nil {
            let same = anchor.map { $0.name == name && $0.hp.max == hp.max } ?? false
            anchor = (name, hp, r.cp ?? (same ? anchor?.cp : nil))
            return r
        }
        guard let a = anchor, a.name == name, a.hp.max == hp.max, let cp = a.cp, cp > 0 else { anchor = nil; return r }
        var o = r
        o.cp = cp; o.cpReads = nil
        return o
    }

    /// A whole log. Returns the readings with the stalled tails' CP set to the card's own.
    public static func normalise(_ readings: [FrameReading], minTail: Int = StalledCardNormaliser.minTail) -> [FrameReading] {
        var out = readings
        var key: (name: String, hp: HP)?
        var anchorCP: Int?
        var tail = [Int]()
        func flush() {
            defer { tail.removeAll() }
            guard tail.count >= minTail else { return }
            var votes = [Int: Int]()
            if let a = anchorCP { votes[a, default: 0] += 1 }
            for i in tail { if let c = out[i].cp, c > 0 { votes[c, default: 0] += 1 } }
            // The most read CP; the anchor's wins a tie. A stall's own CP may never be readable (a tap always covers part of the number) or the anchor's own reading may be the misread,
            // so the most-read value decides, not whether the anchor shows again. Accepted limit: a real next card of the same name and HP read once and then unreadable takes
            // the stalled card's CP (pinned by `testALimitANextCardReadOnceThenUnreadableTakesTheStalledCardsCP`).
            guard let top = votes.max(by: { ($0.value, $0.key == anchorCP ? 1 : 0) < ($1.value, $1.key == anchorCP ? 1 : 0) })?.key else { return }
            for i in tail { out[i].cp = top; out[i].cpReads = nil }
        }
        for (i, r) in readings.enumerated() {
            guard let name = r.name, let hp = r.hp else { continue }       // an unreadable or partial frame neither continues nor ends the stall
            if let k = key, k.name == name, k.hp.max == hp.max {
                if r.ivs != nil { flush(); anchorCP = r.cp ?? anchorCP } else if anchorCP != nil { tail.append(i) }
            } else {
                flush()
                key = (name, hp)
                anchorCP = r.ivs != nil ? r.cp : nil
            }
        }
        flush()
        return out
    }
}
