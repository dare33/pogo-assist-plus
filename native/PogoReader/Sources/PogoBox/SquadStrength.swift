import Foundation

/// Rule 32 (pass 2-5, rewritten): one strength bar for a whole squad, measured against the squad's BEST squad. The reference is the squad's unedited Best suggestion with each slot
/// taken at its full build (level 50, 15/15/15, its best moves: the figure a not-owned Best row gets). The value is the squad's slot figures added up (each as its slot's picker
/// row shows it) over the reference's, capped at 100%. Pure: the figures come in as arguments, so the screens, which work each slot's figure out the way its picker row does,
/// share one rule.
public struct SquadStrength: Equatable {
    /// What one slot contributes.
    public enum Slot: Equatable {
        /// Nothing in the slot: counts as 0 (its reference slot still counts).
        case empty
        /// A Pokémon with no figure (IVs or level not read, "score not known"): left out together with the reference's slot at the same index.
        case unscored
        /// The row's figure now, and after the suggested upgrade (nil when it has none), both 0 to 1.
        case figure(now: Double, after: Double?)

        /// The slot for the figure its Pokémon shows as a row; nil is an empty slot. A row with no solid part (nothing read) or no score is unscored.
        public static func of(_ strength: Strength?) -> Slot {
            guard let s = strength else { return .empty }
            if s.kind == .score && s.score == nil { return .unscored }
            guard let now = s.now else { return .unscored }
            return .figure(now: min(1, max(0, now)), after: s.after.map { min(1, max(0, $0)) })
        }
    }

    public var kind: Strength.Kind
    /// The squad's figures now over the reference's, 0 to 1, capped at 1; nil when no slot counts or the reference has no figure.
    public var now: Double?
    /// The same with each slot's figure after its upgrade (never below the figure now, capped at 1).
    public var after: Double?
    /// Slots that counted (a figure, or empty with a reference figure); `total` is all of them.
    public var scored: Int
    public var total: Int
    /// The squad reached the reference (before the cap): it reads 100%.
    public var matchesBest = false
    /// The unedited Best tab: the reference itself, 100% by definition.
    public var isBestSquad = false

    public init(kind: Strength.Kind, now: Double?, after: Double?, scored: Int, total: Int, matchesBest: Bool = false, isBestSquad: Bool = false) {
        self.kind = kind; self.now = now; self.after = after; self.scored = scored; self.total = total; self.matchesBest = matchesBest; self.isBestSquad = isBestSquad
    }

    /// The squad's slots over the reference's. `reference[i]` is the full-build figure of the Best squad's slot i (0 to 1), nil when that slot has none. An empty slot counts 0 against its
    /// reference slot; an unscored slot, or a slot whose reference has no figure, is left out of both sums.
    public static func against(_ slots: [Slot], reference: [Double?], kind: Strength.Kind = .damage) -> SquadStrength {
        var sumNow = 0.0, sumAfter = 0.0, sumRef = 0.0, counted = 0
        for (i, s) in slots.enumerated() {
            guard i < reference.count, let ref = reference[i], ref > 0 else { continue }   // one rule for "has a figure" (as in `bestSquad`)
            switch s {
            case .unscored: continue
            case .empty: sumRef += ref; counted += 1
            case let .figure(now, after): sumNow += now; sumAfter += max(now, after ?? now); sumRef += ref; counted += 1
            }
        }
        guard counted > 0, sumRef > 0 else { return SquadStrength(kind: kind, now: nil, after: nil, scored: counted, total: slots.count) }
        let matches = sumNow >= sumRef - 1e-9
        let now = min(1, sumNow / sumRef)
        return SquadStrength(kind: kind, now: now, after: max(now, min(1, sumAfter / sumRef)), scored: counted, total: slots.count, matchesBest: matches)
    }

    /// From the figures of the slots' Pokémon (`nil` = an empty slot).
    public static func against(figures: [Strength?], reference: [Double?], kind: Strength.Kind = .damage) -> SquadStrength {
        against(figures.map(Slot.of), reference: reference, kind: kind)
    }

    /// The unedited Best tab: the squad is the reference, so it reads 100% ... through the same safeguards as any squad: a reference slot with no figure is left out (and the label says
    /// "N of M slots scored"), and with no reference figure at all there is no bar.
    public static func bestSquad(reference: [Double?], kind: Strength.Kind = .damage) -> SquadStrength {
        let counted = reference.compactMap { $0 }.filter { $0 > 0 }.count
        guard counted > 0 else { return SquadStrength(kind: kind, now: nil, after: nil, scored: 0, total: reference.count) }
        return SquadStrength(kind: kind, now: 1, after: nil, scored: counted, total: reference.count, matchesBest: true, isBestSquad: true)
    }

    /// The whole percent shown: rounded DOWN, so 100% reads only when the squad matches or beats the reference.
    static func floorPercent(_ x: Double) -> Int { Int((min(1, max(0, x)) * 100 + 1e-9).rounded(.down)) }

    /// The bar's figures, in the picker row bar's own type, so the one drawing serves both. Nothing to draw when no slot counts.
    public var strength: Strength { Strength(kind: kind == .score ? .damage : kind, now: now, after: after.map { max($0, now ?? 0) }) }

    /// A faint part is drawn: the bar's own test (`Strength.hasFaint`), so the "after upgrades" words show exactly when the bar shows the part.
    public var hasAfter: Bool { strength.hasFaint }

    /// "Squad strength 78% of best"; "Squad strength 100%" at or over the reference and for the unedited Best tab (pass 2-6, Greg: no "the best squad", no "Matches the best squad").
    /// "Squad strength not read" when no slot counts.
    public var text: String {
        guard let n = now else { return "Squad strength not read" }
        let pct = Self.floorPercent(n)
        if isBestSquad || matchesBest { return "Squad strength \(pct)%" }
        return "Squad strength \(pct)% of best"
    }
    /// "92% after upgrades"; nil when the upgrades add nothing (and always nil for a Score, which is already of the built option).
    public var afterText: String? {
        guard kind != .score, !matchesBest, hasAfter, let a = after, let n = now, Self.floorPercent(a) > Self.floorPercent(n) else { return nil }
        return "\(Self.floorPercent(a))% after upgrades"
    }
    /// "5 of 6 slots scored"; nil when every slot has a figure.
    public var scoredText: String? { scored < total ? "\(scored) of \(total) slots scored" : nil }

    /// What VoiceOver reads: the visible words, joined.
    public var spoken: String {
        [text.replacingOccurrences(of: "%", with: " percent"), afterText?.replacingOccurrences(of: "%", with: " percent"), scoredText]
            .compactMap { $0 }.joined(separator: ", ")
    }
}
