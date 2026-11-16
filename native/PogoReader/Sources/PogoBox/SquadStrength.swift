import Foundation

/// Rule 32 (5 Nov 2026): one strength bar for a whole squad, the mean of its slots' picker-row figures (`Strength`), on the same scale (100% = every slot holds the best in the
/// game for its role). Pure: the figures come in as arguments, so the screens, which work each slot's figure out the way its picker row does, share one rule.
public struct SquadStrength: Equatable {
    /// What one slot contributes.
    public enum Slot: Equatable {
        /// Nothing in the slot: counts as 0.
        case empty
        /// A Pokémon with no figure (IVs or level not read, "score not known"): left out of the mean.
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
    /// The mean over the slots that count (scored and empty), 0 to 1; nil when no slot counts.
    public var now: Double?
    /// The same with each slot's figure after its upgrade (never below its figure now).
    public var after: Double?
    /// Slots with a figure or empty; `total` is all of them.
    public var scored: Int
    public var total: Int

    public init(kind: Strength.Kind, now: Double?, after: Double?, scored: Int, total: Int) {
        self.kind = kind; self.now = now; self.after = after; self.scored = scored; self.total = total
    }

    /// The mean of the slots' figures: an empty slot counts 0, an unscored one is left out.
    public static func of(_ slots: [Slot], kind: Strength.Kind = .damage) -> SquadStrength {
        var sumNow = 0.0, sumAfter = 0.0, counted = 0
        for s in slots {
            switch s {
            case .empty: counted += 1
            case .unscored: break
            case let .figure(now, after): sumNow += now; sumAfter += max(now, after ?? now); counted += 1
            }
        }
        return SquadStrength(kind: kind, now: counted == 0 ? nil : sumNow / Double(counted), after: counted == 0 ? nil : sumAfter / Double(counted), scored: counted, total: slots.count)
    }

    /// From the figures of the slots' Pokémon (`nil` = an empty slot).
    public static func of(figures: [Strength?], kind: Strength.Kind = .damage) -> SquadStrength { of(figures.map(Slot.of), kind: kind) }

    /// The bar's figures, in the picker row bar's own type, so the one drawing serves both. Nothing to draw when no slot counts.
    public var strength: Strength { Strength(kind: kind, now: now, after: after.map { max($0, now ?? 0) }) }

    /// A faint part is drawn: the bar's own test (`Strength.hasFaint`), so the "after upgrades" words show exactly when the bar shows the part.
    public var hasAfter: Bool { strength.hasFaint }

    /// "Squad strength 72%"; PvP reads its mean Score as the screen already shows Scores ("Squad strength: score 72"). "Squad strength not read" when no slot counts.
    public var text: String {
        guard let n = now else { return "Squad strength not read" }
        return kind == .score ? "Squad strength: score \(Strength.percent(n))" : "Squad strength \(Strength.percent(n))%"
    }
    /// "85% after upgrades"; nil when the upgrades add nothing (and always nil for a Score, which is already of the built option).
    public var afterText: String? {
        guard kind != .score, hasAfter, let a = after else { return nil }
        return "\(Strength.percent(a))% after upgrades"
    }
    /// "5 of 6 slots scored"; nil when every slot has a figure.
    public var scoredText: String? { scored < total ? "\(scored) of \(total) slots scored" : nil }

    /// What VoiceOver reads: the visible words, joined.
    public var spoken: String {
        [text.replacingOccurrences(of: "Squad strength:", with: "Squad strength,").replacingOccurrences(of: "%", with: " percent"), afterText?.replacingOccurrences(of: "%", with: " percent"), scoredText]
            .compactMap { $0 }.joined(separator: ", ")
    }
}
