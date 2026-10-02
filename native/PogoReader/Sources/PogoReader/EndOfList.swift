import Foundation

/// Knows when a command-paged scan has run past the end of the list, from the same per-frame readings and times the extension already
/// produces. A few stored values, nothing that grows with the scan.
///
/// After the last Pokémon a tap closes the appraisal and a swipe stays on the last one: either way no NEW Pokémon appears. The list has
/// ended when, after at least `minimumPokemon` different Pokémon have been read, `quietPeriods` expected periods in a row pass with no new
/// Pokémon (a frame with no card read counts as no new Pokémon, and so does the same Pokémon's readings continuing). A run of real
/// identical twins lasts a few periods at most, which is why the quiet time is 6 periods: on the device logs the longest stretch without a
/// new Pokémon inside a scan was 3.0 periods (a tap, a swipe and a batch join included; see EndOfListTests), so there is room for dropped
/// frames and slow reads. A premature end only shortens a scan (rescan with Add and update), but it must be rare.
///
/// Only for a scan paged by a command: `make(pagedByCommand:period:)` returns nil for a person paging by hand, who may pause on a Pokémon.
public struct EndOfListDetector: Equatable {
    public static let quietPeriods = 6.0
    public static let minimumPokemon = 3
    /// The Pokémon of the last new reading keeps this many seconds of readings; what follows (the same Pokémon repeated, the closed
    /// appraisal) is cut from a log that has an end marker, so it cannot add a row or a false twin.
    public static let keepAfterLast = 3.0

    public let period: Double
    /// The last three different card keys: a misread that flips between two values does not count as a new Pokémon each time.
    private var recent: [String] = []
    public private(set) var distinct = 0
    /// When the last new Pokémon first appeared.
    public private(set) var lastNew: Double?
    /// Set once: when the end was seen, and the time of the last new Pokémon.
    public private(set) var ended: (at: Double, last: Double)?

    public init(period: Double) { self.period = period }

    /// nil unless the scan is paged by a command with a usable period (hand paging never ends by itself).
    public static func make(pagedByCommand: Bool, period: Double?) -> EndOfListDetector? {
        guard pagedByCommand, let period, period.isFinite, period > 0 else { return nil }
        return EndOfListDetector(period: period)
    }

    public static func == (a: EndOfListDetector, b: EndOfListDetector) -> Bool {
        a.period == b.period && a.recent == b.recent && a.distinct == b.distinct && a.lastNew == b.lastNew && a.ended?.at == b.ended?.at
    }

    /// One frame's reading at `time`. True once the end has been seen (and on every call after).
    @discardableResult
    public mutating func feed(_ r: FrameReading, time: Double) -> Bool {
        if ended != nil { return true }
        guard time.isFinite else { return false }
        if let cp = r.cp {
            let key = "\(r.name ?? "?")|\(cp)|\(r.hp.map { String($0.current) } ?? "-")"
            if !recent.contains(key) {
                recent.append(key)
                if recent.count > 3 { recent.removeFirst() }
                distinct += 1
                lastNew = time
            }
        }
        if distinct >= Self.minimumPokemon, let last = lastNew, time - last >= Self.quietPeriods * period { ended = (time, last) }
        return ended != nil
    }
}
