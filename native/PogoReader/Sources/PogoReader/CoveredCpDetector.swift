import Foundation

/// Decides that something (a notification or an alarm banner) is covering the CP while a scan runs, so the phone can tell the
/// player. Fed each frame reading in the order the grouper receives it, plus each swipe tick (a swipe is a new card, even one
/// that reads exactly like the last). It holds a handful of values and nothing else: the extension's memory limit is tight.
///
/// Real data (run25, 5 Oct 2026): a banner covered the top of the screen for 139 cards in a row; each reading had a name, HP and
/// bars and no CP at all, and the player found out afterwards. A reading with no CP also occurs singly in a normal scan (the first
/// seconds of a card, a blank frame), so one or two cards are never a signal.
public struct CoveredCpDetector {
    /// Consecutive cards read with a name and an HP (or bars) but no CP in any of their readings before the CP counts as covered.
    /// A banner stays several seconds, and at the 1.2 s command period five cards are about six seconds, so a banner that covers the
    /// CP long enough to lose a card or two is caught while the player can still lift it; a normal scan never has more than a few
    /// such cards in a row (the walk over the device runs in the tests reports every place this fires).
    public static let defaultThreshold = 5
    /// After firing, consecutive cards WITH a CP before it can fire again: one long banner is one alert, a later banner alerts again.
    public static let defaultRearm = 3
    /// While a stretch stays covered, one reminder per this many further cards with no CP after the firing.
    public static let defaultStillEvery = 5

    public struct Covered: Equatable {
        /// The first card of the stretch with no CP: its name and HP maximum, the time of its first reading and its position in the
        /// detector's own card count (cards seen so far, from 1).
        public var firstName: String
        public var firstHpMax: Int?
        public var startedAt: Double?
        public var startCard: Int
        /// The last card read with a CP before the stretch (nil before any card was read with one).
        public var lastGoodName: String?
        public var lastGoodCp: Int?
        public var lastGoodAt: Double?
        /// The reading that completed the threshold.
        public var firedAt: Double?
    }

    public enum Event: Equatable {
        /// The CP is being covered (once per stretch).
        case covered(Covered)
        /// `rearm` cards with a CP in a row after it fired: it can fire again.
        case cleared(at: Double?)
        /// The stretch goes on: `cards` more cards with no CP since it fired (5, 10, ...), once per `stillEvery` until `.cleared`.
        case stillCovered(cards: Int)
    }

    public let threshold: Int, rearm: Int, stillEvery: Int
    /// True from the firing until it re-arms.
    public private(set) var isCovered = false

    private var cards = 0                       // distinct cards seen (by identity change or swipe), for `startCard`
    private var key: String?                    // identity of the current card: name and HP maximum
    private var swiped = true                   // a swipe was seen since the last card reading: the next one is a new card
    private var cardHasCp = false               // the current card has shown a CP
    private var noCpCards = 0                   // consecutive cards with no CP, the current one included
    private var sinceFire = 0                   // cards with no CP since firing (reminder count); a card with a CP does not reset it, only `.cleared` does
    private var cpCards = 0                     // consecutive cards with a CP since firing (re-arm count)
    private var first: (name: String, hpMax: Int?, at: Double?, card: Int)?
    private var good: (name: String?, cp: Int, at: Double?)?

    public init(threshold: Int = CoveredCpDetector.defaultThreshold, rearm: Int = CoveredCpDetector.defaultRearm, stillEvery: Int = CoveredCpDetector.defaultStillEvery) {
        self.threshold = max(1, threshold); self.rearm = max(1, rearm); self.stillEvery = max(1, stillEvery)
    }

    /// A swipe was seen: the next card reading is a new card.
    public mutating func swipe() { swiped = true }

    @discardableResult
    public mutating func feed(_ r: FrameReading) -> Event? {
        // Nothing read, and a stationed card (no CP and no HP by design), neither count nor reset.
        if r.isStationed { return nil }
        guard let name = r.name, !name.isEmpty else { return nil }
        let hasCp = r.cp != nil
        guard hasCp || r.hp != nil || r.ivs != nil else { return nil }   // a name alone is not a card that lost its CP
        let id = name + "|" + (r.hp.map { String($0.max) } ?? "-")
        let isNew = swiped || id != key
        swiped = false
        if isNew { cards += 1; key = id; cardHasCp = false }

        if let cp = r.cp {
            good = (name, cp, r.time)
            let firstOfCard = !cardHasCp
            cardHasCp = true
            noCpCards = 0; first = nil          // a CP in any reading of a card resets the count, even one that was counted
            if isCovered, firstOfCard {
                cpCards += 1
                if cpCards >= rearm { isCovered = false; cpCards = 0; sinceFire = 0; return .cleared(at: r.time) }
            }
            return nil
        }
        // A reading with no CP on a card that has shown one is a flicker of that card, not a covered one.
        if cardHasCp { return nil }
        if isNew {
            noCpCards += 1
            if noCpCards == 1 { first = (name, r.hp?.max, r.time, cards) }
            cpCards = 0
            if isCovered {
                sinceFire += 1
                if sinceFire % stillEvery == 0 { return .stillCovered(cards: sinceFire) }
            }
        }
        guard !isCovered, noCpCards >= threshold, let f = first else { return nil }
        isCovered = true
        return .covered(Covered(firstName: f.name, firstHpMax: f.hpMax, startedAt: f.at, startCard: f.card,
                                lastGoodName: good?.name, lastGoodCp: good?.cp, lastGoodAt: good?.at, firedAt: r.time))
    }
}
