import Foundation

/// Knows when a command-paged scan has run past the end of the list, from the same per-frame readings and times the extension already
/// produces. A few stored values, nothing that grows with the scan.
///
/// The end is declared POSITIVELY: the same card has been read, again and again, for the whole quiet time. "Nothing new was counted" is never
/// enough, because a reader that is slow, drops frames, or cannot read a card (a fainted Pokémon) counts nothing new either.
///
/// - The CURRENT card is the one on screen since its name or HP last changed. The quiet clock resets on ANY reading whose name or HP differs from the current
///   card's (one reading is enough; a part that was not read is not a difference). A bars value (compared exactly) or a CP value that was never read during
///   this stay resets it on a SINGLE reading. A value already read resets it only on a STABLE SWITCH: read in two readings in a row (a frame that did not
///   read that kind breaks the chain) and different from the value that was stable before it, which is paging between two real cards that recur (alternating
///   twins at two or more readings per card). A recurring value that reappears after unread frames, or a one-reading blip, does not reset it. CP values that
///   are the same card by the digit relation (one is a run of the other's digits, or they differ in one digit: 4262, 1262, 262, 4260 of a tall model's
///   misreads) are ONE value, so neither a first reading nor a switch between them resets it. The values read on the card are remembered for the whole stay,
///   a bounded list (12 per kind; an old one dropped counts as never read, which errs toward not ending). A reset is dated at the reading that caused it.
/// - `quiet` only grows across consecutive processed frames that both read the current card, at most `gapSeconds` apart. A frame with no card
///   read, and a gap between processed frames (low-memory skipping, dropped stretches), add nothing and do not reset it: a run of unread
///   cards, however long, can never end the scan. If the appraisal closes and nothing is readable the scan does not end by itself; the person stops it.
/// - The end needs the detector ARMED, `quietPeriods` expected periods of `quiet`, and readings of the current card in each third of that time (and,
///   by construction, the one that completes it). Arming keeps its evidence rule: at least `armCount` stable new Pokémon (name and HP, two
///   readings in a row) whose last `armChanges` changes were each `armMinPeriods` to `armMaxPeriods` expected periods after the one before: the
///   command is seen paging at its pace. Until then it never ends, however long the wait before the command was said.
///
/// Accepted limits, documented: a real run of 6 or more identical Pokémon (same name, HP, CP, bars) ends it, so the last of them can be cut; fewer
/// than 5 readable Pokémon never arm it; persistent flapping of the last card's name or HP read delays or prevents the end; recurring values read
/// ONCE per card (alternating identical twins, one reading per card, for 6 cards) look like one static card and end it; and so do six or more
/// consecutive cards with the same name, the same HP, the same bars (or bars unread) and CPs that are digit-variants of each other.
///
/// Only for a scan paged by a command: `make(pagedByCommand:period:)` returns nil for a person paging by hand, who may pause on a Pokémon.
public struct EndOfListDetector {
    public static let quietPeriods = 6.0
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
        let cp = r.cp.map(String.init)
        if lastNew == nil {
            curName = name; curHP = hp
            cpTrack = ValueTrack(same: Self.sameCPValue); barsTrack = ValueTrack()
            _ = cpTrack.read(cp); _ = barsTrack.read(bars)
            reset(at: time)
        } else {
            let nameDiffers = name != nil && curName != nil && name != curName
            let hpDiffers = hp != nil && curHP != nil && hp != curHP
            if nameDiffers || hpDiffers {
                curName = name; curHP = hp
                cpTrack = ValueTrack(same: Self.sameCPValue); barsTrack = ValueTrack()
                _ = cpTrack.read(cp); _ = barsTrack.read(bars)
                reset(at: time); sameCard = false
            } else {
                if curName == nil { curName = name }
                if curHP == nil { curHP = hp }
                // A CP or bars value (compared EXACTLY) never read during this stay is another Pokémon of the same species and HP, on a SINGLE
                // reading. A value already read during the stay resets only on a STABLE SWITCH: read twice in a row and different from the value that
                // was stable before it (paging between two real cards that recur). A recurring value that reappears after unread frames, or a
                // one-reading blip, does not.
                let c = cpTrack.read(cp), b = barsTrack.read(bars)
                if c || b { reset(at: time); sameCard = false }
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

    /// What has been read of one kind of value (the CP, or the bars) during the current stay. Bounded.
    private struct ValueTrack {
        /// Whether two values are the same value: equal text, or for the CP the same card by `sameCard` (4262, 1262 and 262 of a tall model's misreads).
        var same: (String, String) -> Bool = { $0 == $1 }
        var seen: [String] = []
        var last: String?        // the value of the previous frame, nil when that frame did not read this kind
        var stable: String?      // the value that was read twice in a row most recently
        static let maxSeen = 12

        /// True when this reading resets the clock.
        mutating func read(_ value: String?) -> Bool {
            defer { last = value }
            guard let value else { return false }
            var resets = false
            if !seen.contains(where: { same($0, value) }) {
                seen.append(value); if seen.count > Self.maxSeen { seen.removeFirst() }
                resets = true
            }
            if let l = last, same(l, value) {                    // two readings in a row
                if let s = stable, !same(s, value) { resets = true }  // a stable switch
                stable = value
            }
            return resets
        }
    }
    private var cpTrack = ValueTrack(same: EndOfListDetector.sameCPValue), barsTrack = ValueTrack()
    private static func sameCPValue(_ a: String, _ b: String) -> Bool { sameCard("cp" + a, "cp" + b) }

    private var lastFrameWasCard = false
}
