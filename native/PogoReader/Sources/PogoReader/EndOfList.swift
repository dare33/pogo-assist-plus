import Foundation

/// Knows when a command-paged scan has run past the end of the list, from the same per-frame readings and times the extension already
/// produces. A few stored values, nothing that grows with the scan.
///
/// The end is declared POSITIVELY: the same card has been read, again and again, for the whole quiet time. "Nothing new was counted" is never
/// enough, because a reader that is slow, drops frames, or cannot read a card (a fainted Pokémon) counts nothing new either.
///
/// - The CURRENT card is the one on screen since the quiet clock last reset. The clock resets on ANY reading whose name or HP differs from the current
///   card's (one reading is enough; a part that was not read is not a difference), and on a CP value or a bars value (either alone) that differs from
///   every value read on the card within the last `seenWindowPeriods` periods, again on a SINGLE reading. Values seen a moment ago (OCR variants of a
///   static card recur within a few frames; a CP that is a run of the card's digits is the same value) do not reset it, so twins of one species and HP,
///   and a CP-only read of another Pokémon after a named card, still do. The seen values are a bounded list. A reset is dated at that reading.
/// - `quiet` only grows across consecutive processed frames that both read the current card, at most `gapSeconds` apart. A frame with no card
///   read, and a gap between processed frames (low-memory skipping, dropped stretches), add nothing and do not reset it: a run of unread
///   cards, however long, can never end the scan. If the appraisal closes and nothing is readable the scan does not end by itself; the person stops it.
/// - The end needs the detector ARMED, `quietPeriods` expected periods of `quiet`, and readings of the current card in each third of that time (and,
///   by construction, the one that completes it). Arming keeps its evidence rule: at least `armCount` stable new Pokémon (name and HP, two
///   readings in a row) whose last `armChanges` changes were each `armMinPeriods` to `armMaxPeriods` expected periods after the one before: the
///   command is seen paging at its pace. Until then it never ends, however long the wait before the command was said.
///
/// Accepted limits, documented: a real run of 8 or more identical Pokémon (same name, HP, CP, bars) ends it, so the last of them can be cut; fewer
/// than 5 readable Pokémon never arm it; persistent flapping of the last card's name, HP, CP or bars read delays or prevents the end.
///
/// Only for a scan paged by a command: `make(pagedByCommand:period:)` returns nil for a person paging by hand, who may pause on a Pokémon.
public struct EndOfListDetector {
    public static let quietPeriods = 8.0
    public static let armCount = 5
    public static let armChanges = 3
    public static let armMinPeriods = 0.5, armMaxPeriods = 2.5
    /// Two processed frames further apart than this are a gap: the time between them is not read time.
    public static let gapSeconds = 2.0
    /// What follows the last reset by this many seconds is cut from a log that has an end marker.
    public static let keepAfterLast = 3.0
    private static let recentKeys = 6

    public let period: Double

    // Arming: stable new Pokémon by name and HP.
    private var recent: [String] = []
    private var pending: (key: String, since: Double)?
    private var newTimes: [Double] = []
    public private(set) var distinct = 0
    public private(set) var armedAt: Double?
    public var armed: Bool { armedAt != nil }

    // The end: the current card.
    private var curName: String?, curHP: String?
    private var lastFrame: Double?
    private var thirds = [0, 0, 0]
    /// Seconds the current card has been read since the clock last reset.
    public private(set) var quiet = 0.0
    /// When the clock last reset (the current card began, or a stable other CP or bars value was confirmed).
    public private(set) var lastNew: Double?
    /// Set once: when the end was seen, and when the clock last reset.
    public private(set) var ended: (at: Double, last: Double)?

    public init(period: Double) { self.period = period }

    /// nil unless the scan is paged by a command with a usable period (hand paging never ends by itself).
    public static func make(pagedByCommand: Bool, period: Double?) -> EndOfListDetector? {
        guard pagedByCommand, let period, period.isFinite, period > 0 else { return nil }
        return EndOfListDetector(period: period)
    }

    /// The identity of what the frame shows (name, HP, bars; the CP only when none of those was read), or nil when no card was read at all.
    static func key(_ r: FrameReading) -> String? {
        let hp = r.hp.map { "\($0.current)/\($0.max)" }
        let bars = r.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" }
        if r.name == nil && hp == nil && bars == nil { return r.cp.map { "cp\($0)" } }
        return "\(r.name ?? "?")|\(hp ?? "-")|\(bars ?? "-")"
    }

    /// The arming identity: name and HP (bars vary between reads of one card while they settle), the CP alone when neither was read.
    private func armKey(_ r: FrameReading) -> String? {
        let hp = r.hp.map { "\($0.current)/\($0.max)" }
        if r.name == nil && hp == nil {
            guard let cp = r.cp else { return nil }
            return canonical("cp\(cp)")
        }
        return "\(r.name ?? "?")|\(hp ?? "-")"
    }

    /// A key made from the CP alone is the same card as a recent one whose digits it matches the way a CP misread does: one is a run of the
    /// other's digits (262 in 4262) or they differ in one digit (4260 and 4262, 263 and 262).
    private func canonical(_ key: String) -> String {
        for known in recent + (pending.map { [$0.key] } ?? []) where known.hasPrefix("cp") && Self.sameCard(known, key) { return known }
        return key
    }
    static func sameCard(_ a: String, _ b: String) -> Bool {
        let x = Array(a.dropFirst(2)), y = Array(b.dropFirst(2))
        if x == y { return true }
        func subsequence(_ small: [Character], _ big: [Character]) -> Bool { var i = 0; for c in big where i < small.count && c == small[i] { i += 1 }; return i == small.count }
        if x.count < y.count { return subsequence(x, y) }
        if y.count < x.count { return subsequence(y, x) }
        return zip(x, y).filter { $0 != $1 }.count <= 1
    }

    private mutating func reset(at time: Double) {
        quiet = 0; thirds = [0, 0, 0]; lastNew = time
    }

    /// One frame's reading at `time`. True once the end has been seen (and on every call after).
    @discardableResult
    public mutating func feed(_ r: FrameReading, time: Double) -> Bool {
        if ended != nil { return true }
        guard time.isFinite else { return false }
        defer { lastFrame = time }

        // Arming
        if let key = armKey(r) {
            if pending?.key != key { pending = (key, time) }
            else if !recent.contains(key), let since = pending?.since {
                recent.append(key)
                if recent.count > Self.recentKeys { recent.removeFirst() }
                distinct += 1
                newTimes.append(since)
                if newTimes.count > Self.armChanges + 1 { newTimes.removeFirst() }
                if armedAt == nil, distinct >= Self.armCount, newTimes.count == Self.armChanges + 1,
                   zip(newTimes, newTimes.dropFirst()).allSatisfy({ ($1 - $0) >= Self.armMinPeriods * period && ($1 - $0) <= Self.armMaxPeriods * period }) { armedAt = time }
            }
        }

        // The current card and the quiet clock
        let name = r.name, hp = r.hp.map { "\($0.current)/\($0.max)" }, bars = r.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" }
        guard name != nil || hp != nil || bars != nil || r.cp != nil else { lastFrameWasCard = false; return false }   // no card read: adds nothing, resets nothing
        let previous = lastFrame
        var sameCard = true
        let cpKey = r.cp.map { "cp\($0)" }
        if lastNew == nil {
            curName = name; curHP = hp
            seenCP = []; seenBars = []
            Self.note(&seenCP, cpKey, time); Self.note(&seenBars, bars, time)
            reset(at: time)
        } else {
            let nameDiffers = name != nil && curName != nil && name != curName
            let hpDiffers = hp != nil && curHP != nil && hp != curHP
            // A CP or bars value that differs from every value seen on this card a moment ago is another Pokémon (of the same species and HP, or a
            // CP-only read of another one), on a SINGLE reading: erring toward NOT ending. Values seen on the card within `seenWindowPeriods` (OCR
            // variants of a static card, which recur within a few frames) do not reset it; a twin that comes back a whole beat later does.
            let newCP = cpKey != nil && !Self.isSeen(seenCP, cpKey!, time, window: Self.seenWindowPeriods * period, same: Self.sameCard)
            let newBars = bars != nil && !Self.isSeen(seenBars, bars!, time, window: Self.seenWindowPeriods * period, same: { $0 == $1 })
            if nameDiffers || hpDiffers {
                curName = name; curHP = hp
                seenCP = []; seenBars = []
                Self.note(&seenCP, cpKey, time); Self.note(&seenBars, bars, time)
                reset(at: time); sameCard = false
            } else if newCP || newBars {
                if curName == nil { curName = name }
                if curHP == nil { curHP = hp }
                seenCP = []; seenBars = []
                Self.note(&seenCP, cpKey, time); Self.note(&seenBars, bars, time)
                reset(at: time); sameCard = false
            } else {
                if curName == nil { curName = name }
                if curHP == nil { curHP = hp }
                Self.note(&seenCP, cpKey, time); Self.note(&seenBars, bars, time)
            }
        }
        if sameCard, let p = previous, lastFrameWasCard, time - p <= Self.gapSeconds, time - p >= 0 {
            quiet += time - p
            let frac = quiet / (Self.quietPeriods * period / 3)
            let third = frac.isFinite ? min(2, max(0, Int(min(frac, 1e6)))) : 2
            thirds[third] += 1
        }
        lastFrameWasCard = true
        if armedAt != nil, quiet >= Self.quietPeriods * period, !thirds.contains(0), let last = lastNew { ended = (time, last) }
        return ended != nil
    }

    /// Values read on the current card, with when each was last read (a few: the set is bounded).
    private var seenCP: [(key: String, last: Double)] = []
    private var seenBars: [(key: String, last: Double)] = []
    /// A value counts as seen when it was read this recently, in expected periods.
    public static let seenWindowPeriods = 0.75
    private static let seenMax = 8

    private static func isSeen(_ seen: [(key: String, last: Double)], _ key: String, _ time: Double, window: Double, same: (String, String) -> Bool) -> Bool {
        seen.contains { same($0.key, key) && time - $0.last <= window }
    }
    private static func note(_ seen: inout [(key: String, last: Double)], _ key: String?, _ time: Double) {
        guard let key else { return }
        if let i = seen.firstIndex(where: { $0.key == key }) { seen[i].last = time } else { seen.append((key, time)); if seen.count > seenMax { seen.removeFirst() } }
    }

    private var lastFrameWasCard = false
}
