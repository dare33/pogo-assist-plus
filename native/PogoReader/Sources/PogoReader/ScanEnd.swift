import Foundation

/// What to do when a command scan's quiet time is reached: FINISH (the list has ended) or PAUSE (the scan is clearly not at its end, a tap or the command stalled), and the state
/// machine around it that the broadcast extension drives. Pure, so it is tested on the device logs.
/// How a typed storage count is compared with the Pokémon read. The count is what the game's storage screen shows, which includes eggs; eggs are not paged, so the read
/// total may be up to `maxEggSlots` below it IN ADDITION to the 1% (at least 3) tolerance, and at most the tolerance above it. The one place these numbers live.
public enum StorageCountRules {
    /// The game's maximum number of egg slots (the owner: 1,698 shown, about 1,688 pageable; 8 eggs and 2 unexplained).
    public static let maxEggSlots = 12
    /// 1% of the count, at least 3.
    public static func tolerance(_ count: Int) -> Int { max(3, Int((Double(count) * 0.01).rounded(.up))) }
    /// The fewest Pokémon read that still count as having reached the count.
    public static func lowestRead(_ count: Int) -> Int { count - maxEggSlots - tolerance(count) }
    /// The most read that is still the count (a little above it: a Pokémon counted twice).
    public static func highestRead(_ count: Int) -> Int { count + tolerance(count) }
}

public enum ScanEndDecision {
    public enum Verdict: Equatable { case finish, pause }

    /// How long a pause waits for a new card before the scan finishes as it would have (seconds). One constant.
    public static let pauseTimeoutSeconds = 180.0

    /// How far the Pokémon read may fall short of the storage count for the scan to count as having reached it: 1% of it, at least 3 (also the full-scan tolerance).
    public static func tolerance(_ count: Int) -> Int { StorageCountRules.tolerance(count) }

    /// FINISH at once when a storage count is known and the Pokémon read so far are within the eggs allowance and tolerance of it (or above): read >= count - 12 - tolerance;
    /// otherwise PAUSE, and with no count known: PAUSE.
    public static func decide(read: Int, storageCount: Int?) -> Verdict {
        guard let count = storageCount, count > 0 else { return .pause }
        return read >= StorageCountRules.lowestRead(count) ? .finish : .pause
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
        /// End the scan now, with the end marker at `at` (the original quiet time after a timeout) and `last` the card that began last.
        case finish(at: Double, last: Double)
    }

    public private(set) var detector: EndOfListDetector
    public var storageCount: Int?
    /// The pause in progress, if any.
    public private(set) var paused: (pause: Pause, since: Double, card: (name: String?, hp: String?))?
    /// Pauses so far in this scan.
    public private(set) var pauseCount = 0
    private var recentBars = [Bool]()   // for each of the last card readings: were the bars read

    public init?(period: Double?, storageCount: Int?) {
        guard let d = EndOfListDetector.make(pagedByCommand: period != nil, period: period) else { return nil }
        detector = d; self.storageCount = storageCount
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
        if r.cp != nil || r.name != nil {
            recentBars.append(r.ivs != nil); if recentBars.count > 8 { recentBars.removeFirst() }
            if r.name != nil { lastName = r.name }; if r.cp != nil { lastCP = r.cp }
        }
        detector.feed(r, time: time)
        if let p = paused {
            if detector.ended != nil { detector.rearm() }   // a repeated quiet during the pause is not news
            let now = detector.currentCard
            if now.name != p.card.name || now.hp != p.card.hp {
                paused = nil
                return .resume(at: time)
            }
            if time - p.since >= ScanEndDecision.pauseTimeoutSeconds { paused = nil; return .finish(at: p.pause.at, last: p.pause.last) }
            return .none
        }
        guard let e = detector.ended else { return .none }
        switch ScanEndDecision.decide(read: read, storageCount: storageCount) {
        case .finish: return .finish(at: e.at, last: e.last)
        case .pause:
            let pause = Pause(at: e.at, last: e.last, read: read, closed: appraisalClosed(), name: lastName, cp: lastCP)
            paused = (pause, time, detector.currentCard)
            pauseCount += 1
            detector.rearm()
            return .pause(pause)
        }
    }

    /// The person chose "Finish now" (or the notification action): end with the marker at `time`.
    public mutating func finishNow(at time: Double) -> Event {
        let last = paused?.pause.last ?? detector.lastNew ?? time
        paused = nil
        return .finish(at: time, last: last)
    }
}
