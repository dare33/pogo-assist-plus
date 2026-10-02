import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The automatic end of a command-paged scan (`EndOfListDetector`) against the device logs, and constructed cases. This path has not run in
/// the broadcast extension on a device: the logs are the evidence.
final class EndOfListTests: XCTestCase {
    private func lines(_ name: String) throws -> [ReplayLine] { ReplayLog.lines(in: try Fixture.url(name)) }

    private static let logs: [(name: String, period: Double, reachedEnd: Bool)] = [
        ("device-run-2026-10-02.replay.jsonl", 2.1, false), ("device-run3-2026-10-02.replay.jsonl", 2.1, false),
        ("device-run4-fast-swipe-2026-10-02.replay.jsonl", 1.6, true), ("device-run4-stretch.replay.jsonl", 1.6, false),
        ("device-run5-tap-1.2.replay.jsonl", 1.2, false), ("device-run6-tap-1.0.replay.jsonl", 1.0, false),
        ("device-run7-tap-1.2-phantom.replay.jsonl", 1.2, true), ("device-run8-tap-300.replay.jsonl", 1.2, false),
        ("device-run9-tap-300b.replay.jsonl", 1.2, true),
    ]

    private func readings(_ name: String) throws -> [ReplayReading] {
        ReplayLog.lines(in: try Fixture.url(name)).compactMap { if case .reading(let r) = $0 { return r } else { return nil } }.sorted { $0.t < $1.t }
    }
    private typealias Seq = [(FrameReading, Double)]
    private func seq(_ rs: [ReplayReading]) -> Seq { rs.map { ($0.frameReading, $0.t) } }

    private func run(_ s: Seq, period: Double) -> EndOfListDetector {
        var d = EndOfListDetector(period: period)
        for (r, t) in s { d.feed(r, time: t) }
        return d
    }

    /// The log with the person waiting `wait` seconds on the first Pokémon before the command pages: the first card's own readings repeat
    /// (variants and all) until the wait is over, then the rest of the log follows, shifted.
    private func withWait(_ rs: [ReplayReading], _ wait: Double) -> [ReplayReading] {
        guard let t0 = rs.first?.t else { return rs }
        let firstName = rs.first { $0.name != nil }?.name
        let firstPage = rs.first { $0.name != nil && $0.name != firstName }?.t ?? t0
        let part = rs.filter { $0.t < firstPage }, rest = rs.filter { $0.t >= firstPage }
        guard let first = part.first, let last = part.last, wait > 0 else { return rs }
        let cycle = last.t - first.t + 0.2
        var out = part, shift = cycle
        while shift < wait + cycle {
            for var r in part { r.t += shift; if r.t < firstPage + wait { out.append(r) } }
            shift += cycle
        }
        for var r in rest { r.t += wait; out.append(r) }
        return out
    }

    /// A perturbed run is EARLY when it ends before the plain run's last reset (the last card began): that is a premature end of the scan.
    private func early(_ s: Seq, period: Double, finalNew: Double) -> Bool {
        guard let e = run(s, period: period).ended else { return false }
        return e.at < finalNew - 0.01
    }

    // MARK: the device logs

    /// Arm time, end time and the longest in-scan quiet stretch (the most `quiet` reached before a later reset, once armed) on every log. Printed
    /// for the report, and asserted for the three logs that ran past the end of the list.
    func testWhereEachLogArmsAndEnds() throws {
        for (name, period, reached) in Self.logs {
            let rs = try readings(name), t0 = rs[0].t
            var d = EndOfListDetector(period: period)
            var worst = 0.0
            for r in rs {
                let before = d.lastNew, q = d.quiet
                d.feed(r.frameReading, time: r.t)
                if d.armed, d.lastNew != before, before != nil { worst = max(worst, q) }
            }
            let armed = try XCTUnwrap(d.armedAt, "\(name) never armed")
            print("EOL \(name) period \(period): armed +\(String(format: "%.1f", armed - t0)) s, \(d.ended.map { String(format: "ended +%.1f s", $0.at - t0) } ?? "no end"), last reset +\(String(format: "%.1f", (d.lastNew ?? t0) - t0)) s, longest in-scan quiet after arming \(String(format: "%.1f", worst)) s = \(String(format: "%.2f", worst / period)) periods, log ends +\(String(format: "%.1f", rs.last!.t - t0)) s")
            XCTAssertLessThan(armed - t0, 21, "\(name): the command is seen paging within the first 21 s")
            XCTAssertLessThan(worst, 0.85 * EndOfListDetector.quietPeriods * period, "\(name): the in-scan quiet stays clear of the end threshold")
            if reached {
                let e = try XCTUnwrap(d.ended, name)
                XCTAssertEqual(e.last, try XCTUnwrap(d.lastNew), accuracy: 0.001, name)
                XCTAssertGreaterThanOrEqual(e.at - e.last, EndOfListDetector.quietPeriods * period, name)
            } else {
                XCTAssertNil(d.ended, "\(name) did not run past the end of the list")
            }
        }
    }

    func testTheEndIsAtTheLastPokemonOfRun7Run9AndRun4() throws {
        XCTAssertEqual(try XCTUnwrap(run(seq(try readings("device-run7-tap-1.2-phantom.replay.jsonl")), period: 1.2).ended).last, 11547.19, accuracy: 3)
        XCTAssertEqual(try XCTUnwrap(run(seq(try readings("device-run9-tap-300b.replay.jsonl")), period: 1.2).ended).last, 15338.99, accuracy: 3)
    }

    /// The person waits before saying the command. Whatever the wait up to 30 s, the scan is not ended before it starts, and every log still
    /// ends (or not) at the same Pokémon.
    func testAWaitBeforeTheFirstPageNeverEndsTheScanEarly() throws {
        for (name, period, reached) in Self.logs {
            let rs = try readings(name), plain = run(seq(rs), period: period)
            for wait in [0.0, 2.0, 5.0, 8.0, 12.0, 20.0, 30.0] {
                let d = run(seq(withWait(rs, wait)), period: period)
                if reached {
                    let e = try XCTUnwrap(d.ended, "\(name) wait \(wait)")
                    XCTAssertEqual(e.last - wait, try XCTUnwrap(plain.ended).last, accuracy: 2.0, "\(name) wait \(wait): it ends at the same Pokémon")
                } else {
                    XCTAssertNil(d.ended, "\(name) wait \(wait) ended the scan early")
                }
            }
        }
    }

    /// The first card alone, however long it stays, never arms it.
    func testTheFirstCardAloneNeverArmsItHoweverLongItStays() throws {
        for (name, period, _) in Self.logs {
            let rs = try readings(name)
            let firstName = rs.first { $0.name != nil }?.name
            let firstPage = rs.first { $0.name != nil && $0.name != firstName }?.t ?? rs[0].t
            var d = EndOfListDetector(period: period)
            let part = rs.filter { $0.t < firstPage }
            var t = rs[0].t, i = 0
            while t < rs[0].t + 120, !part.isEmpty { d.feed(part[i % part.count].frameReading, time: t); i += 1; t += 0.2 }
            XCTAssertFalse(d.armed, name); XCTAssertNil(d.ended, name)
        }
    }

    // MARK: a slow or lossy reader

    /// A phone that reads one frame in 0.6 s or 0.8 s (older, hot, Low Power Mode): the clock still runs, nothing ends early, and the logs that
    /// reached the end still end at the last Pokémon.
    func testSlowReadsNeverEndEarlyAndTheEndIsStillFound() throws {
        for (name, period, reached) in Self.logs {
            let rs = try readings(name)
            let plain = run(seq(rs), period: period), finalNew = try XCTUnwrap(plain.lastNew)
            for slow in [0.6, 0.8] {
                var kept = Seq(), lastKept = -1e9
                for r in rs where r.t - lastKept >= slow { kept.append((r.frameReading, r.t)); lastKept = r.t }
                XCTAssertFalse(early(kept, period: period, finalNew: finalNew), "\(name) at one read per \(slow) s")
                if reached {
                    let e = try XCTUnwrap(run(kept, period: period).ended, "\(name) at one read per \(slow) s never ended")
                    // With a slow reader a value that recurs on the last card can be older than the window and reset the clock once more: the end
                    // comes later, never earlier and never missed (erring toward not ending).
                    print("SLOW \(name) one read per \(slow) s: ends at the last card, its clock last reset \(String(format: "%.1f", e.last - finalNew)) s after the card began, ended \(String(format: "%.1f", e.at - finalNew)) s after")
                    XCTAssertGreaterThanOrEqual(e.last, finalNew - 0.01, name)
                    XCTAssertLessThan(e.at - finalNew, 30, name)
                }
            }
        }
    }

    /// Random losses of readings, 50 seeds each. At 30% nothing ends early; the 50% count is reported.
    func testRandomlyLostReadingsNeverEndEarly() throws {
        var summary = [String]()
        for (name, period, _) in Self.logs {
            let rs = try readings(name), finalNew = try XCTUnwrap(run(seq(rs), period: period).lastNew)
            var fails50 = 0
            for dropRate in [0.3, 0.5] {
                for seed in 0..<50 {
                    var x = UInt64(seed * 7919 + 17), kept = Seq()
                    for r in rs { x = x &* 6364136223846793005 &+ 1442695040888963407; if Double(x >> 11) / Double(1 << 53) >= dropRate { kept.append((r.frameReading, r.t)) } }
                    if early(kept, period: period, finalNew: finalNew) {
                        if dropRate == 0.3 { XCTFail("\(name) seed \(seed) ended early with 30% of readings lost") } else { fails50 += 1 }
                    }
                }
            }
            summary.append("\(name.replacingOccurrences(of: ".replay.jsonl", with: "")): \(fails50)/50")
        }
        print("LOSS 50% of readings dropped, seeds ending early: " + summary.joined(separator: "; "))
    }

    /// Windows with no card read (fainted Pokémon, a closed appraisal), of 4, 5, 6 and 8 periods, at every position: the clock does not run
    /// through them and nothing ends early.
    func testUnreadWindowsNeverEndEarly() throws {
        for (name, period, _) in Self.logs {
            let rs = try readings(name), t0 = rs[0].t
            let base = run(seq(rs), period: period), finalNew = try XCTUnwrap(base.lastNew)
            for w in [4.0, 5.0, 6.0, 8.0] {
                var start = (base.armedAt ?? t0) + 1
                while start + w * period < finalNew - 2 {
                    let s: Seq = rs.map { ($0.t >= start && $0.t < start + w * period) ? (FrameReading(), $0.t) : ($0.frameReading, $0.t) }
                    XCTAssertFalse(early(s, period: period, finalNew: finalNew), "\(name): \(w) periods unread from +\(start - t0)")
                    start += period * 0.5
                }
            }
        }
    }

    // MARK: constructed

    private func card(_ name: String, _ cp: Int?, hp: Int = 50, bars: Int = 1) -> FrameReading {
        var r = FrameReading(); r.name = name; r.cp = cp; r.hp = HP(current: hp, max: hp); r.ivs = IVs(atk: bars % 16, def: 3, hp: 4); return r
    }

    /// One reading every `every` seconds from `from` for `seconds`; returns the time after.
    @discardableResult
    private func hold(_ d: inout EndOfListDetector, _ r: FrameReading, from: Double, seconds: Double, every: Double = 0.2) -> Double {
        var t = from
        while t < from + seconds - 1e-9 { d.feed(r, time: t); t += every }
        return t
    }

    /// A detector that has seen the command page eight Pokémon at 1.2 s, and the time after.
    private func armed() -> (EndOfListDetector, Double) {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        for i in 0..<8 { t = hold(&d, card("P\(i)", 100 + i, hp: 50 + i, bars: i), from: t, seconds: 1.2) }
        XCTAssertTrue(d.armed)
        return (d, t)
    }

    func testTheSameCardReadForEightPeriodsEndsItOnceArmed() {
        var (d, t) = armed()
        t = hold(&d, card("Last", 900, hp: 99, bars: 7), from: t, seconds: 8 * 1.2 - 0.3)
        XCTAssertNil(d.ended)
        hold(&d, card("Last", 900, hp: 99, bars: 7), from: t, seconds: 2)
        XCTAssertNotNil(d.ended)
    }

    func testIdenticalTwinsOfEightOrMoreEndItAndFewerDoNot() {
        var (d, t) = armed()
        let twin = card("Pidgey", 10, hp: 12, bars: 5)
        for _ in 0..<7 { t = hold(&d, twin, from: t, seconds: 1.2) }       // 7 twins: 8.4 s
        XCTAssertNil(d.ended, "seven identical Pokémon: under 8 periods of the same card... ")
        for _ in 0..<2 { t = hold(&d, twin, from: t, seconds: 1.2) }
        XCTAssertNotNil(d.ended, "a real run of 8+ identical Pokémon ends it (documented limit)")
    }

    func testAlternatingTwinsAreNotTheEnd() {
        var (d, t) = armed()
        let a = card("Pidgey", 10, hp: 12, bars: 1), b = card("Pidgey", 10, hp: 12, bars: 4)
        for n in 0..<12 { t = hold(&d, n % 2 == 0 ? a : b, from: t, seconds: 1.2) }
        XCTAssertNil(d.ended, "A,B,A,B for 12 cards: each is stable and differs from the one before")
    }

    func testARunOfUnreadCardsNeverEndsItHoweverLong() {
        var (d, t) = armed()
        t = hold(&d, card("Last", 900, hp: 99, bars: 7), from: t, seconds: 3)
        while t < 400 { d.feed(FrameReading(), time: t); t += 0.2 }
        XCTAssertNil(d.ended, "nothing readable: the scan does not end by itself")
        for i in 0..<10 { t = hold(&d, card("After\(i)", 500 + i, hp: 70 + i, bars: i), from: t, seconds: 1.2) }
        XCTAssertNil(d.ended)
    }

    func testACardHeldNineSecondsAcrossAFrameGapDoesNotEnd() {
        var (d, t) = armed()
        let last = card("Last", 900, hp: 99, bars: 7)
        t = hold(&d, last, from: t, seconds: 1.0)
        t += 9
        t = hold(&d, last, from: t, seconds: 1.0)
        XCTAssertNil(d.ended, "a card read once on each side of a nine second gap")
        var (e, u) = armed()
        e.feed(last, time: u); u += 9; e.feed(last, time: u)
        XCTAssertNil(e.ended)
    }

    /// J3: eight command-paced cards of one species and HP, each with its own CP and bars, each read ONCE: nothing here is a quiet card.
    func testEightSameSpeciesAndHPCardsReadOnceEachDoNotEndIt() {
        var (d, t) = armed()
        for i in 0..<8 { d.feed(card("Pidgey", 300 + 11 * i, hp: 40, bars: i + 1), time: t); t += 1.2 }
        XCTAssertNil(d.ended)
        for i in 0..<12 { d.feed(card("Pidgey", 500 + 7 * i, hp: 40, bars: i + 2), time: t); t += 1.2 }
        XCTAssertNil(d.ended)
    }

    /// J3: one named card, then eight command-paced CP-only cards with different CPs.
    func testOneNamedCardThenEightCPOnlyDifferentCardsDoesNotEndIt() {
        var (d, t) = armed()
        t = hold(&d, card("Named", 900, hp: 99, bars: 7), from: t, seconds: 1.2)
        for i in 0..<10 { var r = FrameReading(); r.cp = 100 + 37 * i; t = hold(&d, r, from: t, seconds: 1.2) }
        XCTAssertNil(d.ended)
    }

    func testAnAbsurdQuietValueDoesNotCrash() {
        var d = EndOfListDetector(period: 1e-300)
        for i in 0..<20 { d.feed(card("A", 100, hp: 50, bars: 1), time: Double(i) * 0.1) }
        var e = EndOfListDetector(period: .infinity)
        for i in 0..<20 { e.feed(card("A", 100, hp: 50, bars: 1), time: Double(i) * 0.1) }
        XCTAssertNil(e.ended)
    }

    func testHiddenCPPokemonCountAsPagingAndDoNotEndIt() {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        for i in 0..<16 { t = hold(&d, card("Hidden\(i)", nil, hp: 50 + i, bars: i), from: t, seconds: 1.2) }
        XCTAssertTrue(d.armed); XCTAssertNil(d.ended)
    }

    func testCPVariantsThatFlipSinglyAtTheEndStillEndIt() {
        var (d, t) = armed()
        var i = 0
        while t < 60 && d.ended == nil { d.feed(card("P7", [105, 1105, 5, 185][i % 4], hp: 57, bars: 7), time: t); i += 1; t += 0.2 }
        XCTAssertNotNil(d.ended, "single-reading CP misreads of a static card are not a new Pokémon")
    }

    func testNothingEndsItBeforeItIsArmedHoweverLongTheWait() {
        var d = EndOfListDetector(period: 1.2)
        var t = hold(&d, card("A", 100), from: 0, seconds: 1.2)
        t = hold(&d, card("B", 200, hp: 60, bars: 2), from: t, seconds: 300)
        XCTAssertFalse(d.armed); XCTAssertNil(d.ended, "two Pokémon and a five-minute wait")
        var e = EndOfListDetector(period: 1.2)
        var u = 0.0
        for i in 0..<8 { u = hold(&e, card("H\(i)", 100, hp: 50 + i, bars: i), from: u, seconds: 10) }   // paged by hand, 10 s apart
        XCTAssertFalse(e.armed); XCTAssertNil(e.ended)
    }

    func testHandPagingNeverEnds() {
        XCTAssertNil(EndOfListDetector.make(pagedByCommand: false, period: 1.2))
        XCTAssertNil(EndOfListDetector.make(pagedByCommand: true, period: nil))
        XCTAssertNil(EndOfListDetector.make(pagedByCommand: true, period: 0))
        XCTAssertNotNil(EndOfListDetector.make(pagedByCommand: true, period: 1.2))
    }

    // MARK: the end marker in the log

    func testTheEndMarkerRoundTripsAndCutsTheTail() throws {
        let marker = ReplayLine.end(at: 11554.4, last: 11547.194467875)
        XCTAssertEqual(ReplayLog.decode(ReplayLog.encode(marker)), marker)
        let all = try lines("device-run7-tap-1.2-phantom.replay.jsonl")
        let cut = ReplayLog.trimmed(all + [marker])
        XCTAssertEqual(ReplayLog.trimmed(all), all, "no marker, nothing cut")
        XCTAssertLessThan(cut.count, all.count)
        let times: [Double] = cut.compactMap { if case .reading(let r) = $0 { return r.t } else { return nil } }
        XCTAssertLessThanOrEqual(times.max() ?? 0, 11547.194467875 + EndOfListDetector.keepAfterLast)
    }

    /// The readings after the end of the list (the same last Pokémon for 38 s) add no row and no false twin, with or without the marker.
    func testTheTailAfterTheEndOfTheListAddsNoRows() throws {
        let src = try Fixture.url("device-run7-tap-1.2-phantom.replay.jsonl")
        var data = try Data(contentsOf: src)
        if data.last != UInt8(ascii: "\n") { data.append(UInt8(ascii: "\n")) }
        let plain = FileManager.default.temporaryDirectory.appendingPathComponent("eol-plain-\(UUID().uuidString).jsonl")
        let marked = FileManager.default.temporaryDirectory.appendingPathComponent("eol-marked-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: plain); try? FileManager.default.removeItem(at: marked) }
        try data.write(to: plain)
        try (data + Data(String(decoding: ReplayLog.encode(.end(at: 11554.4, last: 11547.194467875)), as: UTF8.self).utf8) + Data("\n".utf8)).write(to: marked)
        let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
        let a = try ScanPipeline.process(replay: plain, engine: sharedEngine, paging: hint)
        let b = try ScanPipeline.process(replay: marked, engine: sharedEngine, paging: hint)
        XCTAssertEqual(a.scan.rows.count, 51); XCTAssertEqual(b.scan.rows.count, 51)
        XCTAssertEqual(a.scan.rows.map { "\($0.display) \($0.cp)" }, b.scan.rows.map { "\($0.display) \($0.cp)" })
        XCTAssertEqual(a.scan.rows.last?.display, "Oricorio"); XCTAssertEqual(a.scan.rows.filter { $0.display == "Oricorio" }.count, 1, "no false twin of the last Pokémon")
        XCTAssertLessThan(b.readings, a.readings, "the marker cuts the tail")
        // the app's other reader sees the same
        let loaded = try ReplayReadings.load(url: marked)
        XCTAssertEqual(loaded.readings.count, b.readings)
    }
}
