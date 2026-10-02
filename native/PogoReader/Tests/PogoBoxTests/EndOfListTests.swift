import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The automatic end of a command-paged scan (`EndOfListDetector`) against the device logs, and constructed cases. This path has not run in
/// the broadcast extension on a device: the logs are the evidence.
final class EndOfListTests: XCTestCase {
    private func lines(_ name: String) throws -> [ReplayLine] { ReplayLog.lines(in: try Fixture.url(name)) }

    /// Feed a log's readings through a detector; the detector, and the longest stretch inside the scan without a new Pokémon, in seconds.
    private func run(_ name: String, period: Double) throws -> (detector: EndOfListDetector, longestQuiet: Double, lastNew: Double?) {
        var d = EndOfListDetector(period: period)
        var probe = EndOfListDetector(period: 1e9)   // never ends: only tracks when a new Pokémon appears
        var longest = 0.0, previous: Double?
        for case .reading(let r) in try lines(name) {
            let f = r.frameReading
            let before = probe.lastNew
            probe.feed(f, time: r.t)
            if let now = probe.lastNew, now != before, let p = previous { longest = max(longest, now - p) }
            if let now = probe.lastNew, now != before { previous = now }
            d.feed(f, time: r.t)
        }
        return (d, longest, probe.lastNew)
    }

    // MARK: logs that ran past the end of the list

    func testRun7TapEndsSevenPointTwoSecondsAfterTheLastPokemon() throws {
        let r = try run("device-run7-tap-1.2-phantom.replay.jsonl", period: 1.2)
        let ended = try XCTUnwrap(r.detector.ended)
        XCTAssertEqual(ended.last, 11547.194467875, accuracy: 0.001, "the last new Pokémon (Oricorio 1844) first appeared here")
        XCTAssertEqual(ended.last, try XCTUnwrap(r.lastNew), accuracy: 0.001, "and it is the last new Pokémon of the whole log")
        XCTAssertEqual(ended.at - ended.last, 7.2, accuracy: 0.4)
    }

    func testRun9TapEndsAfterTheLastPokemonOfTheTail() throws {
        let r = try run("eol-run9-tap-300b-tail.replay.jsonl", period: 1.2)
        let ended = try XCTUnwrap(r.detector.ended)
        XCTAssertEqual(ended.last, 15338.992540916, accuracy: 0.001, "Fidough 690 is the last Pokémon")
        XCTAssertEqual(ended.at - ended.last, 7.2, accuracy: 0.4)
    }

    func testRun4SwipeEndsNineSecondsAfterTheLastPokemon() throws {
        let r = try run("device-run4-fast-swipe-2026-10-02.replay.jsonl", period: 1.6)
        let ended = try XCTUnwrap(r.detector.ended)
        XCTAssertEqual(ended.last, try XCTUnwrap(r.lastNew), accuracy: 0.001)
        XCTAssertEqual(ended.at - ended.last, 9.6, accuracy: 0.5, "a swipe stays on the last Pokémon: its readings continue unchanged")
    }

    // MARK: logs that did not reach it (a scan the person stopped at or before the end): the detector must never fire

    func testLogsThatDidNotRunPastTheEndNeverEnd() throws {
        for (name, period) in [("device-run8-tap-300.replay.jsonl", 1.2), ("device-run5-tap-1.2.replay.jsonl", 1.2), ("device-run6-tap-1.0.replay.jsonl", 1.0),
                               ("device-run3-2026-10-02.replay.jsonl", 2.1), ("device-run-2026-10-02.replay.jsonl", 2.1), ("device-run4-stretch.replay.jsonl", 1.6)] {
            let r = try run(name, period: period)
            XCTAssertNil(r.detector.ended, name)
        }
    }

    /// The evidence for 6 periods: inside a scan the longest stretch with no new Pokémon is under half the quiet time, on every log, at
    /// every pace (tap 1.2 and 1.0, swipe 1.6, 1.7 and 2.1), with batch joins, dropped frames and slow reads in them.
    func testTheLongestQuietStretchInsideAScanIsWellUnderSixPeriods() throws {
        for (name, period) in [("device-run8-tap-300.replay.jsonl", 1.2), ("device-run5-tap-1.2.replay.jsonl", 1.2), ("device-run6-tap-1.0.replay.jsonl", 1.0),
                               ("device-run3-2026-10-02.replay.jsonl", 2.1), ("device-run-2026-10-02.replay.jsonl", 2.1), ("device-run4-fast-swipe-2026-10-02.replay.jsonl", 1.6),
                               ("device-run7-tap-1.2-phantom.replay.jsonl", 1.2), ("eol-run9-tap-300b-tail.replay.jsonl", 1.2)] {
            let r = try run(name, period: period)
            XCTAssertLessThan(r.longestQuiet, 3.5 * period + 0.5, "\(name): \(r.longestQuiet) s")
        }
    }

    // MARK: constructed

    private func card(_ name: String, _ cp: Int) -> FrameReading { var r = FrameReading(); r.name = name; r.cp = cp; r.hp = HP(current: 50, max: 50); return r }

    /// Feeds one frame every 0.2 s from `from`; returns the time of each frame fed.
    private func hold(_ d: inout EndOfListDetector, _ r: FrameReading, from: Double, seconds: Double) -> Double {
        var t = from
        while t < from + seconds { d.feed(r, time: t); t += 0.2 }
        return t
    }

    func testThreeIdenticalTwinsInARowDoNotEndIt() {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        for (i, n) in ["A", "B", "C"].enumerated() { t = hold(&d, card(n, 100 + i), from: t, seconds: 1.2) }
        t = hold(&d, card("D", 400), from: t, seconds: 3 * 1.2)          // three twins: three periods on one card
        XCTAssertNil(d.ended)
        t = hold(&d, card("D", 400), from: t, seconds: 2.0 * 1.2)       // even five periods in all
        XCTAssertNil(d.ended)
        t = hold(&d, card("E", 500), from: t, seconds: 1.2)
        XCTAssertNil(d.ended)
    }

    func testSixPeriodsOfTheSamePokemonEndsIt() {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        for (i, n) in ["A", "B", "C"].enumerated() { t = hold(&d, card(n, 100 + i), from: t, seconds: 1.2) }
        _ = hold(&d, card("C", 102), from: t, seconds: 10)
        let ended = d.ended
        XCTAssertNotNil(ended); XCTAssertEqual(ended!.at - ended!.last, 7.2, accuracy: 0.25)
    }

    func testAClosedAppraisalAfterTheLastPokemonEndsItToo() {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        for (i, n) in ["A", "B", "C"].enumerated() { t = hold(&d, card(n, 100 + i), from: t, seconds: 1.2) }
        while t < 20 { d.feed(FrameReading(), time: t); t += 0.2 }   // no card read at all
        XCTAssertNotNil(d.ended)
    }

    func testFewerThanThreePokemonNeverEnd() {
        var d = EndOfListDetector(period: 1.2)
        var t = hold(&d, card("A", 100), from: 0, seconds: 1.2)
        t = hold(&d, card("B", 200), from: t, seconds: 60)
        XCTAssertNil(d.ended, "two Pokémon and a long wait")
        var e = EndOfListDetector(period: 1.2)
        _ = hold(&e, card("A", 100), from: 0, seconds: 120)
        XCTAssertNil(e.ended, "one Pokémon and a long wait")
    }

    func testHandPagingNeverEnds() {
        XCTAssertNil(EndOfListDetector.make(pagedByCommand: false, period: 1.2))
        XCTAssertNil(EndOfListDetector.make(pagedByCommand: true, period: nil))
        XCTAssertNil(EndOfListDetector.make(pagedByCommand: true, period: 0))
        XCTAssertNotNil(EndOfListDetector.make(pagedByCommand: true, period: 1.2))
    }

    func testAMisreadThatFlipsBetweenTwoValuesDoesNotKeepRestartingTheClock() {
        var d = EndOfListDetector(period: 1.2)
        var t = 0.0
        for (i, n) in ["A", "B", "C"].enumerated() { t = hold(&d, card(n, 100 + i), from: t, seconds: 1.2) }
        var flip = false
        while t < 30 && d.ended == nil { d.feed(card("C", flip ? 102 : 162), time: t); flip.toggle(); t += 0.2 }
        XCTAssertNotNil(d.ended, "162 and 102 alternate: neither is new after the first time")
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
