import Foundation

/// Knows when a command-paged scan has run past the end of the list, from the same per-frame readings and times the extension already
/// produces. A few stored values, nothing that grows with the scan.
///
/// What counts as a Pokémon is what was read of the card, not the CP alone: a reading's key is built from the name, the HP, the appraisal
/// bars and, only when none of those was read, the CP (a hidden CP, or a CP misread such as Rayquaza 4262/1262/262/4260 on one card, must not
/// look like several Pokémon). A key is a NEW Pokémon only once it is stable (seen in two keyed readings in a row, an unkeyed frame in
/// between does not break that), so a single-reading OCR variant never counts, and a recently seen stable key does not count again, so a
/// card cycling through a few variants does not keep restarting the clock.
///
/// It is ARMED only after the command has been seen paging: at least `armCount` stable new Pokémon whose last `armChanges` changes were each
/// between `armMinPeriods` and `armMaxPeriods` expected periods after the one before. Until then it never ends, however long the wait before
/// the command was said (the first page came 3.8 to 12.7 s after the broadcast started on the device logs).
///
/// Once armed, the list has ended when `quietPeriods` expected periods pass with no new stable Pokémon: after the last Pokémon a tap closes
/// the appraisal (no card read) and a swipe stays on it (the same readings continue). Time with no frames processed (a gap of more than
/// `gapSeconds` between two frames: low-memory skipping, a stretch of dropped frames) does not count toward the quiet time. A run of real
/// identical twins at the very end is indistinguishable from the end: the last of them can be cut (a documented limit).
///
/// Only for a scan paged by a command: `make(pagedByCommand:period:)` returns nil for a person paging by hand, who may pause on a Pokémon.
public struct EndOfListDetector: Equatable {
    public static let quietPeriods = 6.0
    public static let armCount = 5
    public static let armChanges = 3
    public static let armMinPeriods = 0.5, armMaxPeriods = 2.5
    public static let gapSeconds = 2.0
    /// What follows the last new Pokémon by this many seconds is cut from a log that has an end marker.
    public static let keepAfterLast = 3.0
    private static let recentKeys = 6

    public let period: Double
    private var recent: [String] = []                // the last stable keys: seen, not new again
    private var pending: (key: String, since: Double)?   // the key of the last keyed reading and when its run began
    private var newTimes: [Double] = []              // when the last few stable new Pokémon began (armChanges + 1 of them)
    private var lastFed: Double?
    private var skipped = 0.0                        // seconds with no frames since the last new Pokémon
    /// Stable new Pokémon seen so far.
    public private(set) var distinct = 0
    /// When the last stable new Pokémon began.
    public private(set) var lastNew: Double?
    /// When the command was first seen paging, once.
    public private(set) var armedAt: Double?
    public var armed: Bool { armedAt != nil }
    /// Set once: when the end was seen, and the time the last new Pokémon began.
    public private(set) var ended: (at: Double, last: Double)?

    public init(period: Double) { self.period = period }

    /// nil unless the scan is paged by a command with a usable period (hand paging never ends by itself).
    public static func make(pagedByCommand: Bool, period: Double?) -> EndOfListDetector? {
        guard pagedByCommand, let period, period.isFinite, period > 0 else { return nil }
        return EndOfListDetector(period: period)
    }

    public static func == (a: EndOfListDetector, b: EndOfListDetector) -> Bool {
        a.period == b.period && a.recent == b.recent && a.pending?.key == b.pending?.key && a.distinct == b.distinct && a.lastNew == b.lastNew && a.armedAt == b.armedAt && a.ended?.at == b.ended?.at
    }

    /// The identity of what the frame shows, or nil when no card was read at all.
    static func key(_ r: FrameReading) -> String? {
        let hp = r.hp.map { "\($0.current)/\($0.max)" }
        let bars = r.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" }
        if r.name == nil && hp == nil && bars == nil { return r.cp.map { "cp\($0)" } }
        return "\(r.name ?? "?")|\(hp ?? "-")|\(bars ?? "-")"
    }

    /// A key made from the CP alone (no name, HP or bars were read) is the same card as a recent one whose digits it matches the way a CP
    /// misread does: one is a run of the other's digits (262 in 4262) or they differ in one digit (4260 and 4262, 263 and 262).
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

    /// One frame's reading at `time`. True once the end has been seen (and on every call after).
    @discardableResult
    public mutating func feed(_ r: FrameReading, time: Double) -> Bool {
        if ended != nil { return true }
        guard time.isFinite else { return false }
        if let last = lastFed, time - last > Self.gapSeconds { skipped += time - last }
        lastFed = time
        if var key = Self.key(r) {
            if key.hasPrefix("cp") { key = canonical(key) }
            if pending?.key != key { pending = (key, time) }
            else if !recent.contains(key), let since = pending?.since {
                recent.append(key)
                if recent.count > Self.recentKeys { recent.removeFirst() }
                distinct += 1; lastNew = since; skipped = 0
                newTimes.append(since)
                if newTimes.count > Self.armChanges + 1 { newTimes.removeFirst() }
                if armedAt == nil, distinct >= Self.armCount, newTimes.count == Self.armChanges + 1,
                   zip(newTimes, newTimes.dropFirst()).allSatisfy({ ($1 - $0) >= Self.armMinPeriods * period && ($1 - $0) <= Self.armMaxPeriods * period }) { armedAt = time }
            }
        }
        if armedAt != nil, let last = lastNew, time - last - skipped >= Self.quietPeriods * period { ended = (time, last) }
        return ended != nil
    }
}
