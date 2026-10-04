import Foundation

/// What to do when a command scan's quiet time is reached: FINISH (the list has ended) or PAUSE (the scan is clearly not at its end, a tap or the command stalled), and the state
/// machine around it that the broadcast extension drives. Pure, so it is tested on the device logs.
/// How a typed storage count is compared with the Pokémon read. The count is what the game's storage screen shows, which includes eggs; eggs are not paged. The Pokémon
/// expected are the count less the eggs the person typed (0 to `maxEggSlots`); with no egg count typed the flat allowance of `maxEggSlots` is used. The read total may be
/// that far below the count IN ADDITION to the 1% (at least 3) tolerance, and at most the tolerance above it. The one place these numbers live.
public enum StorageCountRules {
    /// The game's maximum number of egg slots (the owner: 1,698 shown, 8 eggs, 1,685 read on run15: 5 unexplained). The flat allowance when no egg count was typed.
    public static let maxEggSlots = 12
    /// The egg count made usable: 0 to `maxEggSlots`; nil when none was typed or it is out of range.
    public static func validEggs(_ eggs: Int?) -> Int? { eggs.flatMap { (0...maxEggSlots).contains($0) ? $0 : nil } }
    /// The Pokémon the game's count holds, less the eggs typed; nil when no usable egg count was typed.
    public static func expected(count: Int, eggs: Int?) -> Int? { validEggs(eggs).map { max(0, count - $0) } }
    /// 1% of the count, at least 3.
    public static func tolerance(_ count: Int) -> Int { max(3, Int((Double(count) * 0.01).rounded(.up))) }
    /// The fewest Pokémon read that still count as having reached the count.
    /// With the person's egg count: count - eggs - tolerance; without one: count - 12 - tolerance.
    public static func lowestRead(_ count: Int, eggs: Int? = nil) -> Int { count - (validEggs(eggs) ?? maxEggSlots) - tolerance(count) }
    /// The most read that is still the count (a little above it: a Pokémon counted twice).
    public static func highestRead(_ count: Int) -> Int { count + tolerance(count) }
}

public enum ScanEndDecision {
    public enum Verdict: Equatable { case finish, pause }

    /// A Full scan needs the storage count the game shows before it starts: without it the end of the list cannot be told from a stall.
    public static func fullScanNeedsCount(isFull: Bool, storageCount: Int?) -> Bool { isFull && (storageCount ?? 0) <= 0 }
    /// Whether a scan started with these settings may pause: Full, with a valid count. The extension's backstop for a broadcast started past the Scan screen (Control Centre): a
    /// Full scan with no count runs as an Add-and-update scan (no pause, never judged Full) instead of waiting out the pause at the real end of the list.
    public static func pausesAllowed(isFull: Bool, storageCount: Int?) -> Bool { isFull && !fullScanNeedsCount(isFull: isFull, storageCount: storageCount) }

    /// How long a pause waits for a new card before the scan finishes as it would have (seconds). One constant.
    public static let pauseTimeoutSeconds = 180.0
    /// The longest a scan may stay paused in all, however often the appraisal is reopened on the same card (each reopening restarts the 180 s, none can hold the pause beyond this).
    public static let pauseCapSeconds = 600.0

    /// How far the Pokémon read may fall short of the storage count for the scan to count as having reached it: 1% of it, at least 3 (also the full-scan tolerance).
    public static func tolerance(_ count: Int) -> Int { StorageCountRules.tolerance(count) }

    /// FINISH at once when a storage count is known and the Pokémon read so far are within the eggs allowance and tolerance of it (or above): read >= count - 12 - tolerance;
    /// otherwise PAUSE, and with no count known: PAUSE (a Full scan only: the controller never asks for any other kind).
    public static func decide(read: Int, storageCount: Int?, eggs: Int? = nil) -> Verdict {
        guard let count = storageCount, count > 0 else { return .pause }
        return read >= StorageCountRules.lowestRead(count, eggs: eggs) ? .finish : .pause
    }
}

/// The extension's end logic: the detector, the decision and the pause. Fed every reading with the number of Pokémon read so far.
public struct ScanEndController {
    public struct Pause: Equatable {
        public var at: Double, last: Double, read: Int
        public var closed: Bool?
        public var name: String?, cp: Int?
    }
    public enum Event: Equatable {
        case none
        /// The quiet time was reached on a card that is not the end of the list: keep reading, tell the person.
        case pause(Pause)
        /// A new card was read after a pause.
        case resume(at: Double)
        /// The appraisal's bars appeared again on the paused card (the person reopened it): the 180 s window starts over, but the scan is NOT resumed, because nothing was paged.
        case windowRestarted(at: Double)
        /// End the scan now, with the end marker at `at` (the original quiet time after a timeout) and `last` the card that began last.
        case finish(at: Double, last: Double)
    }

    public private(set) var detector: EndOfListDetector
    public var storageCount: Int?
    /// The eggs the person typed for a Full scan (nil: none, the flat allowance applies).
    public var eggCount: Int?
    /// Only a Full scan may pause. An Add-and-update scan finishes at the end wait exactly as it always did: no pause, no count.
    public let pausesAllowed: Bool
    /// The pause in progress, if any.
    public private(set) var paused: (pause: Pause, since: Double, resets: Int)?
    /// When the current pause began (its first reading), for the cap on restarts.
    private var pauseBegan = 0.0
    /// The bars of the card the pause is on (read during its stay), if any: other settled bars on the same name, HP and CP are another card.
    private var pausedBars: IVs?
    private var stayBars: (resets: Int, ivs: IVs)?
    /// The bars of the previous card reading (nil when it read none): two card readings in a row with the same other bars are what settles a look-alike next card.
    private var lastCardBars: IVs?
    /// The previous pause's read count and cap clock: a new pause with no Pokémon read since continues the same cap, so a resume that read nothing cannot start the cap over.
    private var lastPause: (read: Int, began: Double)?
    /// Evidence since the pause that ANOTHER card was shown although the detector saw nothing new and the live row count did not grow: a paging tick, then a card read with the CP hidden, or
    /// bars other than the card's own (beyond a notch) even once. A finish then keeps everything read after the pause (see `finishDating`).
    private var otherCardEvidence = false, swipeSincePause = false, pauseFedAt = 0.0
    /// The CPs read during the paused card's stay (its own and the misreads of them), the paused card's name and HP, and, since the pause, the run of consecutive readings of that name and
    /// HP in which none of those CPs appears: a twin with the same name and HP and another CP is such a run (a stalled card keeps showing its own CP between its misreads).
    private var stayCPs: (resets: Int, cps: Set<Int>)?
    private var pausedCPs = Set<Int>(), pausedCard: (name: String?, hp: String?)?
    private var twinLength = 0, twinCounts = [Int: Int]()
    /// Consecutive readings without the card's own CP, and one other CP read this many times, make a run that is evidence of a twin.
    static let twinRunLength = 6, twinCPReads = 3
    /// The scan finished because a pause went unanswered (the 180 s, or the cap), not because the list ended.
    public private(set) var timedOut = false
    private var lastRead = 0, lastFeedTime = 0.0
    /// Pauses so far in this scan.
    public private(set) var pauseCount = 0
    private var recentBars = [Bool]()   // for each of the last card readings: were the bars read

    public init?(period: Double?, storageCount: Int?, eggCount: Int? = nil, pausesAllowed: Bool = true) {
        guard let d = EndOfListDetector.make(pagedByCommand: period != nil, period: period) else { return nil }
        detector = d; self.storageCount = pausesAllowed ? storageCount : nil; self.eggCount = pausesAllowed ? eggCount : nil; self.pausesAllowed = pausesAllowed
    }

    /// Whether the appraisal looked closed: of the last 8 card readings, at least 6 had no bars (closed) or at least 6 had them (open); nil otherwise.
    private func appraisalClosed() -> Bool? {
        guard recentBars.count >= 8 else { return nil }
        let without = recentBars.filter { !$0 }.count
        if without >= 6 { return true }
        if recentBars.count - without >= 6 { return false }
        return nil
    }

    private var lastName: String?, lastCP: Int?

    public mutating func feed(_ r: FrameReading, time: Double, read: Int) -> Event {
        let before = detector
        let prevBars = lastCardBars
        // The appraisal must have LOOKED closed (see `appraisalClosed`) before bars coming back count as reopening it: one dropped reading on an open appraisal is not.
        let wasClosed = appraisalClosed() == true
        var barsAppeared = false   // a card reading with bars straight after one without
        if r.cp != nil || r.name != nil {
            barsAppeared = r.ivs != nil && recentBars.last == false && wasClosed
            recentBars.append(r.ivs != nil); if recentBars.count > 8 { recentBars.removeFirst() }
            if r.name != nil { lastName = r.name }; if r.cp != nil { lastCP = r.cp }
            lastCardBars = r.ivs
        }
        detector.feed(r, time: time)
        if let ivs = r.ivs { stayBars = (detector.resets, ivs) }
        if let cp = r.cp { if let s = stayCPs, s.resets == detector.resets { stayCPs?.cps.insert(cp) } else { stayCPs = (detector.resets, [cp]) } }
        lastRead = read; lastFeedTime = time
        if let p = paused {
            if let was = pausedBars, let now = r.ivs, !Self.sameBars(was, now) { otherCardEvidence = true }
            if let card = pausedCard, r.name != nil || r.cp != nil, r.name == card.name, r.hp.map(\.identity) == card.hp {
                if let cp = r.cp, pausedCPs.contains(cp) { twinLength = 0; twinCounts.removeAll() }
                else {
                    twinLength += 1; if let cp = r.cp { twinCounts[cp, default: 0] += 1 }
                    if twinLength >= Self.twinRunLength, twinCounts.values.contains(where: { $0 >= Self.twinCPReads }) { otherCardEvidence = true }
                }
            }
            if swipeSincePause, r.cp == nil, r.name != nil || r.hp != nil { otherCardEvidence = true }
            if detector.ended != nil { detector.rearm() }   // a repeated quiet during the pause is not news
            // A RESUME needs a different name or a different HP: the same name and HP is the stalled card, whatever CP a tap leaves readable and with or without bars (run17: a closed
            // appraisal read Staraptor 1999 as 1299, 1099, 199, 1209, 29 ... for 75 s, and each new CP value used to be taken for a new card; run17's Charizard 1632 read as 63 with its own
            // bars). The detector's reset is only the question "is anything new", so the same reading without its CP and bars is asked: it moves only for a name or an HP change.
            var barsOnly = false
            if detector.resets != p.resets {
                var probe = before; var bare = r; bare.ivs = nil; bare.cp = nil
                probe.feed(bare, time: time)
                if probe.resets != before.resets {
                    paused = nil
                    return .resume(at: time)
                }
                // Not a name or HP change: the CP and/or the bars. Did the bars alone make the detector reset (the person reopened the appraisal on the same card)?
                if r.ivs != nil {
                    var probe2 = before; var noBars = r; noBars.ivs = nil
                    probe2.feed(noBars, time: time)
                    barsOnly = probe2.resets == before.resets
                }
            }
            // A look-alike next card (same name, HP and CP) has other bars than the card's own, beyond a notch on a stat, HELD by two card readings in a row (the rule the bars split
            // uses). One such reading is not enough: the appraisal animates when it opens (run15's Rayquaza read 9/9/9, then 13/12/14), so a first reading is at most a window
            // restart (below, for a closed appraisal).
            if let was = pausedBars, let now = r.ivs, !Self.sameBars(was, now), let prev = prevBars, Self.sameBars(prev, now) {
                paused = nil
                return .resume(at: time)
            }
            if detector.resets != p.resets || barsAppeared {
                // The detector's reset by bars alone (or bars back after a closed appraisal) is absorbed into the pause either way; it restarts the 180 s only for a closed appraisal.
                paused = (p.pause, p.since, detector.resets)   // a CP-only reset (a tap covering part of the number) is absorbed and restarts nothing
                if wasClosed, barsOnly || barsAppeared, time - pauseBegan < ScanEndDecision.pauseCapSeconds {
                    paused = (p.pause, time, detector.resets)
                    return .windowRestarted(at: time)
                }
            }
            return timeoutEvent(now: time)
        }
        guard let e = detector.ended else { return .none }
        switch pausesAllowed ? ScanEndDecision.decide(read: read, storageCount: storageCount, eggs: eggCount) : .finish {
        case .finish: return .finish(at: e.at, last: e.last)
        case .pause:
            let pause = Pause(at: e.at, last: e.last, read: read, closed: appraisalClosed(), name: lastName, cp: lastCP)
            detector.rearm()
            paused = (pause, time, detector.resets)
            otherCardEvidence = false; swipeSincePause = false; pauseFedAt = time
            pausedCPs = stayCPs.flatMap { $0.resets == detector.resets ? $0.cps : nil } ?? []; pausedCard = detector.currentCard; twinLength = 0; twinCounts.removeAll()
            pauseBegan = (lastPause?.read == read ? lastPause!.began : time); lastPause = (read, pauseBegan); pausedBars = stayBars.flatMap { $0.resets == detector.resets ? $0.ivs : nil }
            pauseCount += 1
            return .pause(pause)
        }
    }

    /// A paging tick (a swipe seen by the cheap signature) at `time`. While paused, one after the pause began is evidence that another card may have been shown.
    public mutating func noteSwipe(at time: Double) { if paused != nil, time > pauseFedAt { swipeSincePause = true } }

    /// Seconds left before this pause finishes the scan if nothing new is read at `now`: the 180 s window or what is left of the 600 s cap, whichever is less (nil when not paused).
    public func remainingPauseSeconds(now: Double) -> Double? {
        guard let p = paused else { return nil }
        return max(0, min(ScanEndDecision.pauseTimeoutSeconds - (now - p.since), ScanEndDecision.pauseCapSeconds - (now - pauseBegan)))
    }

    /// The 180 s timeout (and the cap on restarts), checked from the one-second heartbeat as well as on every reading (a paused broadcast with no frames, or with Vision skipped,
    /// must still finish). `now` is in the same clock as the readings' times. The end is dated at the stall (so the repeated card after it is trimmed) only if no Pokémon has been
    /// read since the pause; if rows were, nothing read after the pause is trimmed (`finishDating`).
    public mutating func tick(now: Double) -> Event { paused == nil ? .none : timeoutEvent(now: now) }

    private mutating func timeoutEvent(now: Double) -> Event {
        guard let p = paused, now - p.since >= ScanEndDecision.pauseTimeoutSeconds || now - pauseBegan >= ScanEndDecision.pauseCapSeconds else { return .none }
        timedOut = true
        return finishDating(p.pause, at: nil)
    }

    /// The end marker after a pause, whichever way the scan finishes (timeout, cap or the person). Nothing read after the pause that belongs to a new card may be trimmed, and the
    /// detector's own last-new time is not evidence of that (a card the detector did not count as new can still have been a Pokémon the grouper read). So: no Pokémon read since the
    /// pause, then the marker is the stall's (the repeated card is trimmed); any read since, the marker is at the last reading with the last reading as the last card.
    private mutating func finishDating(_ pause: Pause, at time: Double?) -> Event {
        paused = nil
        if lastRead > pause.read || otherCardEvidence { return .finish(at: time ?? lastFeedTime, last: lastFeedTime) }
        return .finish(at: time ?? pause.at, last: pause.last)
    }

    /// Bars within one notch on every stat are the same card's bars read again.
    private static func sameBars(_ a: IVs, _ b: IVs) -> Bool { abs(a.atk - b.atk) <= 1 && abs(a.def - b.def) <= 1 && abs(a.hp - b.hp) <= 1 }

    /// The person chose "Finish now" (or the notification action): end with the marker at `time`.
    public mutating func finishNow(at time: Double) -> Event {
        guard let p = paused else { return .finish(at: time, last: detector.lastNew ?? time) }
        return finishDating(p.pause, at: time)
    }
}
