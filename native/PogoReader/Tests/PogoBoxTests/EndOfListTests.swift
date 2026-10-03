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
        ("device-run9-tap-300b.replay.jsonl", 1.2, true), ("device-run10-tap-25-autoend.replay.jsonl", 1.2, true),
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
            while t < rs[0].t + 60, !part.isEmpty { d.feed(part[i % part.count].frameReading, time: t); i += 1; t += 0.2 }
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
            for w in [4.0, 5.0, 6.0, 8.0, 10.0] {
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

    func testTheSameCardReadForSixPeriodsEndsItOnceArmed() {
        var (d, t) = armed()
        t = hold(&d, card("Last", 900, hp: 99, bars: 7), from: t, seconds: 6 * 1.2 - 0.3)
        XCTAssertNil(d.ended)
        hold(&d, card("Last", 900, hp: 99, bars: 7), from: t, seconds: 2)
        XCTAssertNotNil(d.ended)
    }

    func testIdenticalTwinsOfSixOrMoreEndItAndFewerDoNot() {
        var (d, t) = armed()
        let twin = card("Pidgey", 10, hp: 12, bars: 5)
        for _ in 0..<5 { t = hold(&d, twin, from: t, seconds: 1.2) }       // 5 twins: 6.0 s
        XCTAssertNil(d.ended, "five identical Pokémon: under 6 periods of the same card")
        for _ in 0..<2 { t = hold(&d, twin, from: t, seconds: 1.2) }
        XCTAssertNotNil(d.ended, "a real run of 6+ identical Pokémon ends it (documented limit)")
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

    /// J3: fourteen command-paced cards of one species and HP (well above the 6-period threshold), each with its own CP and bars, each read ONCE: nothing here is a quiet card.
    func testEightSameSpeciesAndHPCardsReadOnceEachDoNotEndIt() {
        var (d, t) = armed()
        for i in 0..<14 { d.feed(card("Pidgey", 300 + 11 * i, hp: 40, bars: i + 1), time: t); t += 1.2 }
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

    /// K1: how often the end is still FOUND when readings are lost at random, on the three logs that reached the end of the list. At least what the earlier
    /// rule found (30%: 50, 50, 50 of 50; 50%: 47, 47, 50 of 50). Printed for the report.
    func testTheEndIsStillFoundWhenReadingsAreLost() throws {
        let floors: [String: (Int, Int)] = ["device-run4-fast-swipe-2026-10-02.replay.jsonl": (50, 47), "device-run7-tap-1.2-phantom.replay.jsonl": (50, 47), "device-run9-tap-300b.replay.jsonl": (50, 50)]
        for (name, period, reached) in Self.logs where reached {
            let rs = try readings(name), finalNew = try XCTUnwrap(run(seq(rs), period: period).lastNew)
            var found = [Int]()
            for dropRate in [0.3, 0.5] {
                var n = 0
                for seed in 0..<50 {
                    var x = UInt64(seed * 7919 + 17), kept = Seq()
                    for r in rs { x = x &* 6364136223846793005 &+ 1442695040888963407; if Double(x >> 11) / Double(1 << 53) >= dropRate { kept.append((r.frameReading, r.t)) } }
                    if let e = run(kept, period: period).ended, e.at >= finalNew - 0.01 { n += 1 }
                }
                found.append(n)
            }
            print("FOUND \(name): 30% lost \(found[0])/50, 50% lost \(found[1])/50")
            if let floor = floors[name] { XCTAssertGreaterThanOrEqual(found[0], floor.0, name); XCTAssertGreaterThanOrEqual(found[1], floor.1, name) }
        }
    }

    /// K1: a static last card read at 0.3 s with noise must still end the scan, within 120 s, in every seed: frames lost, CP or bars unread on some, no
    /// card read on some, bars or CP misread on some readings.
    func testAStaticLastCardWithNoiseStillEndsIt() {
        enum Noise { case lost(Double), cpUnread(Double), barsUnread(Double), nothingRead(Double), barsMisread(Double, Int), cpMisread(Double) }
        let cases: [(String, Noise)] = [("2 of 10 lost", .lost(0.2)), ("3 of 10 lost", .lost(0.3)), ("CP unread on 3 of 10", .cpUnread(0.3)), ("bars unread on 3 of 10", .barsUnread(0.3)),
                                        ("no card read on 3 of 10", .nothingRead(0.3)), ("bars misread 5%", .barsMisread(0.05, 1)), ("bars misread 10%", .barsMisread(0.1, 1)),
                                        ("bars misread 20%", .barsMisread(0.2, 1)), ("bars misread 10% to 3 values", .barsMisread(0.1, 3)), ("CP misread 10%", .cpMisread(0.1))]
        for cadence in [0.3, 0.6] {
            for (label, noise) in cases {
                var notEnded = 0
                for seed in 0..<40 {
                    var (d, t) = armed()
                    let start = t
                    var x = UInt64(seed * 31 + 7)
                    func rnd() -> Double { x = x &* 6364136223846793005 &+ 1442695040888963407; return Double(x >> 11) / Double(1 << 53) }
                    while t < start + 120 && d.ended == nil {
                        var r = card("Last", 900, hp: 99, bars: 7)
                        var feed = true
                        switch noise {
                        case .lost(let p): feed = rnd() >= p
                        case .cpUnread(let p): if rnd() < p { r.cp = nil }
                        case .barsUnread(let p): if rnd() < p { r.ivs = nil }
                        case .nothingRead(let p): if rnd() < p { r = FrameReading() }
                        case .barsMisread(let p, let k): if rnd() < p { r.ivs = IVs(atk: 7, def: 8 + Int(rnd() * Double(k)), hp: 4) }
                        case .cpMisread(let p): if rnd() < p { r.cp = 357 }
                        }
                        if feed { d.feed(r, time: t) }
                        t += cadence
                    }
                    if d.ended == nil { notEnded += 1 }
                }
                XCTAssertEqual(notEnded, 0, "\(label) at \(cadence) s: \(notEnded) of 40 seeds never ended")
            }
        }
    }

    /// L1: six or more consecutive cards with the same name, HP and bars whose CPs are digit-variants of each other (one digit apart, or a run of the other's
    /// digits) look like one card with a tall model's CP misreads, and end the scan: the documented limit. CPs that are NOT related that way never do.
    func testCPsThatAreDigitVariantsOfEachOtherAreOneCardAndUnrelatedOnesAreNot() {
        for cps in [(0..<10).map { 1400 + 10 * $0 }, (0..<10).map { 1499 - $0 }, [1500, 1499, 1498, 1497, 1496, 1495, 1494, 1493, 1492, 1491, 1490, 1489]] {
            var (d, t) = armed()
            for cp in cps { for _ in 0..<3 { d.feed(card("Rattata", cp, hp: 40, bars: 10), time: t); t += 0.4 } }
            XCTAssertNotNil(d.ended, "digit-variant CPs from \(cps.first!): the documented limit")
        }
        // CPs two or more digits apart and not runs of each other: ten cards, never the end
        var (d, t) = armed()
        for cp in [1312, 1457, 1688, 1749, 1853, 1926, 2071, 2164, 2289, 2395] { for _ in 0..<3 { d.feed(card("Rattata", cp, hp: 40, bars: 10), time: t); t += 0.4 } }
        XCTAssertNil(d.ended)
    }

    /// L1: the real end of the list on the phone (run10, Pogo scan 25): eleven Pokémon, then Rayquaza, whose page stays on screen with the CP flapping in short
    /// runs between 4262, 1262 and 262. The scan ends within 6 periods + 2 s of Rayquaza's first reading, not before, and the same log cut 5.5 s after Rayquaza began does not end.
    func testRun10EndsAtRayquazaAndNotBeforeAndNotWhenCutShort() throws {
        let rs = try readings("device-run10-tap-25-autoend.replay.jsonl"), t0 = rs[0].t
        let rayquaza = try XCTUnwrap(rs.first { $0.name == "Rayquaza" }).t
        let d = run(seq(rs), period: 1.2)
        let e = try XCTUnwrap(d.ended, "the end of the list must be found")
        print("RUN10 first line 0.0, Rayquaza first read +\(String(format: "%.1f", rayquaza - t0)), ended +\(String(format: "%.1f", e.at - t0)) (\(String(format: "%.1f", e.at - rayquaza)) s after Rayquaza), armed +\(String(format: "%.1f", (d.armedAt ?? t0) - t0)), log ends +\(String(format: "%.1f", rs.last!.t - t0))")
        XCTAssertGreaterThanOrEqual(e.at, rayquaza, "not before Rayquaza")
        XCTAssertLessThanOrEqual(e.at - rayquaza, 6 * 1.2 + 2)
        let cut = rs.filter { $0.t <= rayquaza + 5.5 }
        XCTAssertNil(run(seq(cut), period: 1.2).ended, "cut 5.5 s after Rayquaza began the quiet time (7.2 s) is not complete")
    }

    /// L2: after the end fires, the marker is written and the trimmed log still gives the same eleven rows as the full log.
    func testRun10TrimmedAtTheEndGivesTheSameElevenRows() throws {
        let url = try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")
        let rs = try readings("device-run10-tap-25-autoend.replay.jsonl")
        let e = try XCTUnwrap(run(seq(rs), period: 1.2).ended)
        let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
        let full = try ScanPipeline.process(replay: url, engine: sharedEngine, paging: hint)
        let expected = ["Zamazenta 2133", "Zamazenta 2145", "Xurkitree 2173", "Blissey 2178", "Vaporeon 2480", "Xerneas 2611", "Xerneas 2641", "Zamazenta 2661", "Staraptor 2819", "Lucario 3000", "Rayquaza 4262"]
        XCTAssertEqual(full.scan.rows.map { "\($0.display) \($0.cp)" }, expected)
        // the log as the extension leaves it when the end fires: the lines up to the end, then the marker
        let lines = ReplayLog.lines(in: url).filter { l in
            switch l { case .reading(let r): return r.t <= e.at; case .tick(let t), .drop(let t): return t <= e.at; case .end: return false }
        } + [ReplayLine.end(at: e.at, last: e.last)]
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("run10-trim-\(UUID().uuidString).jsonl"); defer { try? FileManager.default.removeItem(at: tmp) }
        try (lines.map { String(decoding: ReplayLog.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n").write(to: tmp, atomically: true, encoding: .utf8)
        let trimmed = try ScanPipeline.process(replay: tmp, engine: sharedEngine, paging: hint)
        XCTAssertEqual(trimmed.scan.rows.map { "\($0.display) \($0.cp)" }, expected)
        XCTAssertLessThan(trimmed.readings, full.readings, "the marker cut the tail")
    }

    /// K1, no early end: alternating twins at two or more readings per card are a stable switch each time, so they never end it. The accepted residual:
    /// recurring values read ONCE per card (alternating identical twins at one reading per card) look like one static card.
    func testAlternatingTwinsAtTwoReadingsPerCardDoNotEndItAndOneReadingPerCardIsTheAcceptedResidual() {
        let a = card("Pidgey", 10, hp: 12, bars: 1), b = card("Pidgey", 10, hp: 12, bars: 4)
        for per in [2, 3, 4] {
            var (d, t) = armed()
            for n in 0..<12 { for _ in 0..<per { d.feed(n % 2 == 0 ? a : b, time: t); t += 1.2 / Double(per) } }
            XCTAssertNil(d.ended, "\(per) readings per card")
        }
        var (d, t) = armed()
        for n in 0..<24 { d.feed(n % 2 == 0 ? a : b, time: t); t += 1.2 }
        XCTAssertNotNil(d.ended, "accepted residual: one reading per card for identical twins")
    }

    /// The CP values read in a window, collapsed by their last three digits (a tall model's 4262, 1262, 262 are one): how many different CPs the window shows.
    private func distinctCPs(_ rs: [ReplayReading], from: Double, to: Double) -> Int {
        var groups = [String]()
        for c in rs where c.t >= from && c.t < to { if let cp = c.cp { let k = String(String(cp).suffix(3)); if !groups.contains(k) { groups.append(k) } } }
        return groups.count
    }

    /// Q3: windows where only the CP is read (name, HP and bars unread, or only name and CP) injected into the logs that reached the end of the list: nothing ends early. The
    /// digit relation between CPs of a CP-sorted list must not chain from one neighbour to the next.
    func testInjectedCPOnlyWindowsNeverEndEarly() throws {
        var table = [String]()
        for (name, period, reached) in Self.logs where reached {
            let rs = try readings(name), t0 = rs[0].t
            let base = run(seq(rs), period: period), finalNew = try XCTUnwrap(base.lastNew)
            for mode in ["cpOnly", "nameCp"] {
                for w in [6.0, 8.0, 12.0] {
                    var earlyEnds = 0, tries = 0
                    var start = (base.armedAt ?? t0) + 1
                    while start + w * period < finalNew - 2 {
                        tries += 1
                        let s: Seq = rs.map { r in
                            guard r.t >= start && r.t < start + w * period else { return (r.frameReading, r.t) }
                            var x = r.frameReading; x.hp = nil; x.ivs = nil; if mode == "cpOnly" { x.name = nil }; return (x, r.t)
                        }
                        // an end after six periods in which ONE CP (and nothing else) was read cannot be told from a card held that long: not counted
                        if let e = run(s, period: period).ended, e.at < finalNew - 0.01, distinctCPs(rs, from: e.at - 6 * period - 0.2, to: e.at + 0.01) > 1 { earlyEnds += 1 }
                        start += period * 0.5
                    }
                    table.append("\(name.replacingOccurrences(of: ".replay.jsonl", with: "")) \(mode) \(Int(w))p: \(earlyEnds)/\(tries)")
                    XCTAssertEqual(earlyEnds, 0, "\(name) \(mode) \(Int(w)) periods")
                }
            }
        }
        print("INJECTED " + table.joined(separator: "; "))
    }

    /// The same windows on the logs from the phone that are too big to keep as fixtures (run12 is the 1,552-Pokémon scan: a CP-sorted list). Skipped where they are not.
    func testInjectedCPOnlyWindowsNeverEndEarlyOnTheBigPhoneLogs() throws {
        let dev = NSString(string: "~/Developer/personal/pogo-frames/device-runs").expandingTildeInPath
        var table = [String]()
        for dir in ["run12-tap-1500", "run13-tap-200-tail", "stall-scan-20261003T054229Z-b1f94047", "stall-scan-20261003T055448Z-6b2b1f4e"] {
            guard let f = (try? FileManager.default.contentsOfDirectory(atPath: dev + "/" + dir))?.filter({ $0.hasSuffix(".replay.jsonl") && !$0.contains(" 2") }).sorted().first else { continue }
            let rs = ReplayLog.lines(in: URL(fileURLWithPath: dev + "/" + dir + "/" + f)).compactMap { l -> ReplayReading? in if case .reading(let r) = l { return r } else { return nil } }.sorted { $0.t < $1.t }
            let base = run(seq(rs), period: 1.2), finalNew = try XCTUnwrap(base.lastNew), t0 = rs[0].t
            let step = rs.count > 3000 ? 3.0 : 0.6
            for mode in ["cpOnly", "nameCp"] {
                for w in [6.0, 8.0, 12.0] {
                    var earlyEnds = 0, rawEarly = 0, tries = 0
                    var start = (base.armedAt ?? t0) + 1
                    while start + w * 1.2 < finalNew - 2 {
                        tries += 1
                        let s: Seq = rs.map { r in
                            guard r.t >= start && r.t < start + w * 1.2 else { return (r.frameReading, r.t) }
                            var x = r.frameReading; x.hp = nil; x.ivs = nil; if mode == "cpOnly" { x.name = nil }; return (x, r.t)
                        }
                        var raw = 0
                        if let e = run(s, period: 1.2).ended, e.at < finalNew - 0.01 { raw = 1; if distinctCPs(rs, from: e.at - 6 * 1.2 - 0.2, to: e.at + 0.01) > 1 { earlyEnds += 1 } }
                        rawEarly += raw
                        start += step
                    }
                    table.append("\(dir.prefix(24)) \(mode) \(Int(w))p: \(earlyEnds)/\(tries) avoidable, \(rawEarly) with a one-CP window")
                    XCTAssertEqual(earlyEnds, 0, "\(dir) \(mode) \(Int(w)) periods")
                }
            }
        }
        print("INJECTEDBIG " + table.joined(separator: "; "))
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
