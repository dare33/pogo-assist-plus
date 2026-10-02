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

    private func run(_ rs: [ReplayReading], period: Double) -> EndOfListDetector {
        var d = EndOfListDetector(period: period)
        for r in rs { d.feed(r.frameReading, time: r.t) }
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

    // MARK: the device logs

    /// E1: arm time and end time on every log (printed, and asserted for the three logs that ran past the end of the list).
    func testWhereEachLogArmsAndEnds() throws {
        for (name, period, reached) in Self.logs {
            let rs = try readings(name), t0 = rs[0].t
            let d = run(rs, period: period)
            let armed = try XCTUnwrap(d.armedAt, "\(name) never armed")
            print("EOL \(name) period \(period): armed +\(String(format: "%.1f", armed - t0)) s, last new +\(String(format: "%.1f", (d.lastNew ?? t0) - t0)) s, \(d.ended.map { String(format: "ended +%.1f s", $0.at - t0) } ?? "no end"), log ends +\(String(format: "%.1f", rs.last!.t - t0)) s")
            XCTAssertLessThan(armed - t0, 21, "\(name): the command is seen paging within the first 21 s")
            if reached {
                let e = try XCTUnwrap(d.ended, name)
                XCTAssertEqual(e.last, try XCTUnwrap(d.lastNew), accuracy: 0.001, name)
                XCTAssertEqual(e.at - e.last, EndOfListDetector.quietPeriods * period, accuracy: 0.6, name)
            } else {
                XCTAssertNil(d.ended, "\(name) did not run past the end of the list")
            }
        }
    }

    func testTheEndIsAtTheLastPokemonOfRun7Run9AndRun4() throws {
        XCTAssertEqual(try XCTUnwrap(run(try readings("device-run7-tap-1.2-phantom.replay.jsonl"), period: 1.2).ended).last, 11547.19, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(run(try readings("device-run9-tap-300b.replay.jsonl"), period: 1.2).ended).last, 15338.99, accuracy: 0.5)
        XCTAssertNotNil(run(try readings("eol-run9-tap-300b-tail.replay.jsonl"), period: 1.2).ended, "the tail alone has too few paging steps to arm")
    }

    /// E1 (the blocker): the person waits before saying the command. Whatever the wait up to 30 s, the scan is not ended before it starts, and
    /// every log still ends (or not) where it did.
    func testAWaitBeforeTheFirstPageNeverEndsTheScanEarly() throws {
        for (name, period, reached) in Self.logs {
            let rs = try readings(name), plain = run(rs, period: period)
            for wait in [0.0, 2.0, 5.0, 8.0, 12.0, 20.0, 30.0] {
                let d = run(withWait(rs, wait), period: period)
                if reached {
                    let e = try XCTUnwrap(d.ended, "\(name) wait \(wait)")
                    XCTAssertEqual(e.last - wait, try XCTUnwrap(plain.ended).last, accuracy: 1.0, "\(name) wait \(wait): it ends at the same Pokémon")
                } else {
                    XCTAssertNil(d.ended, "\(name) wait \(wait) ended the scan early")
                }
            }
        }
    }

    /// The old detector counted CP misreads of the first card as Pokémon: the first card alone, however long it stays, never arms it.
    func testTheFirstCardAloneNeverArmsItHoweverLongItStays() throws {
        for (name, period, _) in Self.logs {
            let rs = try readings(name)
            let firstName = rs.first { $0.name != nil }?.name
            let firstPage = rs.first { $0.name != nil && $0.name != firstName }?.t ?? rs[0].t
            var d = EndOfListDetector(period: period)
            let part = rs.filter { $0.t < firstPage }
            var t = rs[0].t, i = 0
            while t < rs[0].t + 120, !part.isEmpty { var r = part[i % part.count].frameReading; r.time = t; d.feed(r, time: t); i += 1; t += 0.2 }
            XCTAssertFalse(d.armed, name); XCTAssertNil(d.ended, name)
        }
    }

    func testTheLongestQuietStretchInsideAScanIsWellUnderSixPeriods() throws {
        for (name, period, _) in Self.logs {
            let rs = try readings(name)
            var d = EndOfListDetector(period: 1e9)   // never arms: only tracks when a stable new Pokémon begins
            var previous: Double?, longest = 0.0
            for r in rs {
                let before = d.lastNew
                d.feed(r.frameReading, time: r.t)
                if let now = d.lastNew, now != before { if let p = previous { longest = max(longest, now - p) }; previous = now }
            }
            XCTAssertLessThan(longest, 4.2 * period + 0.3, "\(name): \(longest) s = \(longest / period) periods")
        }
    }

    // MARK: constructed

    private func card(_ name: String, _ cp: Int?, hp: Int = 50, bars: Int = 1) -> FrameReading {
        var r = FrameReading(); r.name = name; r.cp = cp; r.hp = HP(current: hp, max: hp); r.ivs = IVs(atk: bars % 16, def: 3, hp: 4); return r
    }

    /// One reading every 0.2 s from `from` for `seconds`; returns the time after.
    @discardableResult
    private func hold(_ d: inout EndOfListDetector, _ r: FrameReading, from: Double, seconds: Double) -> Double {
        var t = from
        while t < from + seconds - 1e-9 { d.feed(r, time: t); t += 0.2 }
        return t
    }

    /// A detector that has seen the command page six Pokémon at 1.2 s, and the time after.
    private func armed() -> (EndOfListDetector, Double) {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        for i in 0..<6 { t = hold(&d, card("P\(i)", 100 + i, hp: 50 + i, bars: i), from: t, seconds: 1.2) }
        XCTAssertTrue(d.armed)
        return (d, t)
    }

    func testThreeIdenticalTwinsInARowDoNotEndIt() {
        var (d, t) = armed()
        t = hold(&d, card("D", 400, hp: 90, bars: 7), from: t, seconds: 3 * 1.2)   // three twins: three periods on one card
        t = hold(&d, card("D", 400, hp: 90, bars: 7), from: t, seconds: 2.0 * 1.2)
        XCTAssertNil(d.ended)
        t = hold(&d, card("E", 500, hp: 95, bars: 8), from: t, seconds: 1.2)
        XCTAssertNil(d.ended)
    }

    func testSixPeriodsOfTheSamePokemonEndsItOnceArmed() {
        var (d, t) = armed()
        hold(&d, card("P5", 105, hp: 55, bars: 5), from: t, seconds: 10)
        let e = d.ended
        XCTAssertNotNil(e); XCTAssertEqual(e!.at - e!.last, 7.2, accuracy: 0.3)
    }

    func testAClosedAppraisalAfterTheLastPokemonEndsItToo() {
        var (d, t) = armed()
        while t < 30 { d.feed(FrameReading(), time: t); t += 0.2 }
        XCTAssertNotNil(d.ended)
    }

    func testNothingEndsItBeforeItIsArmedHoweverLongTheWait() {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        t = hold(&d, card("A", 100), from: t, seconds: 1.2); t = hold(&d, card("B", 200, hp: 60, bars: 2), from: t, seconds: 1.2)
        t = hold(&d, card("B", 200, hp: 60, bars: 2), from: t, seconds: 300)
        XCTAssertFalse(d.armed); XCTAssertNil(d.ended, "two Pokémon and a five-minute wait")
        // five Pokémon seen at the wrong rhythm (a person paging by hand, 10 s apart) do not arm it either
        var e = EndOfListDetector(period: 1.2)
        var u = 0.0
        for i in 0..<8 { u = hold(&e, card("H\(i)", 100, hp: 50 + i, bars: i), from: u, seconds: 10) }
        XCTAssertFalse(e.armed); XCTAssertNil(e.ended)
    }

    func testARunOfHiddenCPPokemonCountsAsPagingAndDoesNotEndIt() {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        for i in 0..<8 { t = hold(&d, card("Hidden\(i)", nil, hp: 50 + i, bars: i), from: t, seconds: 1.2) }
        XCTAssertTrue(d.armed, "no CP, but name, HP and bars change every step"); XCTAssertNil(d.ended)
        for i in 8..<16 { t = hold(&d, card("Hidden\(i)", nil, hp: 50 + i, bars: i), from: t, seconds: 1.2) }
        XCTAssertNil(d.ended)
    }

    func testAMisreadThatFlipsBetweenValuesAtTheEndStillEndsIt() {
        // four CP variants of the last card
        var (d, t) = armed()
        var i = 0
        while t < 40 && d.ended == nil { d.feed(card("P5", [105, 1105, 5, 185][i % 4], hp: 55, bars: 5), time: t); i += 1; t += 0.2 }
        XCTAssertNotNil(d.ended, "CP variants of one card are one Pokémon")
        // four bar variants, each held for two readings in a row (each is stable once, then none is new)
        var (e, u) = armed()
        var j = 0
        while u < 60 && e.ended == nil { let v = card("P5", 105, hp: 55, bars: 5 + (j / 2) % 4 + 1); e.feed(v, time: u); j += 1; u += 0.2 }
        XCTAssertNotNil(e.ended, "four variants restart the clock four times, not for ever")
    }

    func testAFrameGapInTheMiddleOfAScanDoesNotCountTowardTheQuietTime() {
        var (d, t) = armed()
        t = hold(&d, card("P6", 106, hp: 56, bars: 6), from: t, seconds: 1.2)
        t += 10        // ten seconds with no frame processed (low memory, dropped stretch)
        t = hold(&d, card("P6", 106, hp: 56, bars: 6), from: t, seconds: 1.0)
        XCTAssertNil(d.ended, "the gap is not quiet time")
        t = hold(&d, card("P7", 107, hp: 57, bars: 7), from: t, seconds: 1.2)
        XCTAssertNil(d.ended)
        // quiet time that has frames still counts
        hold(&d, card("P7", 107, hp: 57, bars: 7), from: t, seconds: 10)
        XCTAssertNotNil(d.ended)
    }

    func testASingleReadingOCRVariantIsNotAPokemon() {
        var (d, t) = armed()
        let before = d.distinct
        d.feed(card("Zzz", 999, hp: 77, bars: 9), time: t); t += 0.2
        d.feed(card("P5", 105, hp: 55, bars: 5), time: t)
        XCTAssertEqual(d.distinct, before)
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
