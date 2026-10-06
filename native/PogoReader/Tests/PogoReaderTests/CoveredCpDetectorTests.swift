import XCTest
@testable import PogoReader

final class CoveredCpDetectorTests: XCTestCase {
    // MARK: helpers

    /// A reading as the extension gives it: a card with a name and HP, a CP or none.
    private func card(_ name: String, cp: Int?, hp: Int = 100, t: Double = 0) -> FrameReading {
        var r = FrameReading(frame: nil, time: t)
        r.name = name; r.nameText = name; r.cp = cp; r.cpText = cp.map { "CP\($0)" } ?? ""
        r.hp = HP(current: hp, max: hp); r.ivs = IVs(atk: 10, def: 10, hp: 10)
        if cp == nil { r.flags = ["no-cp-text"] }
        return r
    }
    private func blank(t: Double = 0) -> FrameReading { var r = FrameReading(frame: nil, time: t); r.flags = ["no-cp-text"]; return r }
    private func stationed(_ name: String, t: Double = 0) -> FrameReading {
        var r = FrameReading(frame: nil, time: t); r.name = name; r.nameText = name; r.ivs = IVs(atk: 5, def: 5, hp: 5); r.flags = ["no-cp-text", FrameReading.stationedFlag]
        return r
    }

    /// Feed one card the way a scan does: a few readings of the same card, a swipe before the next.
    private func feedCards(_ d: inout CoveredCpDetector, _ cards: [(String, Int?)], readings: Int = 3, from t0: Double = 0) -> [CoveredCpDetector.Event] {
        var events = [CoveredCpDetector.Event](); var t = t0
        for (i, c) in cards.enumerated() {
            d.swipe()
            for _ in 0..<readings { t += 0.2; if let e = d.feed(card(c.0, cp: c.1, hp: 100 + i, t: t)) { events.append(e) } }
        }
        return events
    }
    private func good(_ n: Int, _ from: Int = 0) -> [(String, Int?)] { (0..<n).map { ("Good\(from + $0)", 500 + $0) } }
    private func covered(_ n: Int, _ from: Int = 0) -> [(String, Int?)] { (0..<n).map { ("Cov\(from + $0)", nil) } }

    // MARK: rule

    func testFiresOnceAtTheFifthCoveredCardWithBothEndsReported() {
        var d = CoveredCpDetector()
        var ev = feedCards(&d, good(3))
        XCTAssertTrue(ev.isEmpty)
        ev = feedCards(&d, covered(4), from: 10)
        XCTAssertTrue(ev.isEmpty, "four covered cards are not enough")
        XCTAssertFalse(d.isCovered)
        ev = feedCards(&d, [("Cov4", nil)], from: 20)
        guard case .covered(let c)? = ev.first, ev.count == 1 else { return XCTFail("expected one firing: \(ev)") }
        XCTAssertEqual(c.firstName, "Cov0"); XCTAssertEqual(c.firstHpMax, 100)
        XCTAssertEqual(c.lastGoodName, "Good2"); XCTAssertEqual(c.lastGoodCp, 502)
        XCTAssertEqual(c.startCard, 4)
        XCTAssertTrue(d.isCovered)
        let more = feedCards(&d, covered(50, 5), from: 30)
        XCTAssertFalse(more.contains { if case .covered = $0 { return true } else { return false } }, "one long banner is one firing")
        XCTAssertEqual(more, (1...9).map { .stillCovered(cards: 5 * $0) }, "a reminder every five cards")
    }

    func testSingleAndShortRunsOfCpLessCardsNeverFire() {
        var d = CoveredCpDetector()
        for _ in 0..<10 {
            XCTAssertTrue(feedCards(&d, good(2)).isEmpty)
            XCTAssertTrue(feedCards(&d, covered(4)).isEmpty)     // four, then a card with a CP resets
        }
        XCTAssertFalse(d.isCovered)
    }

    func testACardThatShowsACpLaterIsNotCovered() {
        // The first seconds of every card read with no CP, then the CP appears: never a stretch, however many cards.
        var d = CoveredCpDetector()
        var events = [CoveredCpDetector.Event]()
        for i in 0..<30 {
            d.swipe()
            if let e = d.feed(card("P\(i)", cp: nil, hp: 100 + i, t: Double(i))) { events.append(e) }
            if let e = d.feed(card("P\(i)", cp: 400 + i, hp: 100 + i, t: Double(i) + 0.4)) { events.append(e) }
        }
        XCTAssertTrue(events.isEmpty)
    }

    func testCpInAnyReadingOfACounterCardResetsTheCount() {
        var d = CoveredCpDetector()
        _ = feedCards(&d, covered(3))
        d.swipe(); XCTAssertNil(d.feed(card("Cov3", cp: nil, hp: 103)))     // counted as the fourth...
        XCTAssertNil(d.feed(card("Cov3", cp: 777, hp: 103)))      // ...but it shows its CP after all
        XCTAssertFalse(d.isCovered)
        XCTAssertTrue(feedCards(&d, covered(4, 5)).isEmpty, "the count started again from zero")
    }

    func testBlankAndStationedReadingsNeitherCountNorReset() {
        var d = CoveredCpDetector()
        var ev = [CoveredCpDetector.Event]()
        // Four covered cards with blanks and stationed cards between them: not yet five.
        for i in 0..<4 {
            d.swipe()
            if let e = d.feed(card("Cov\(i)", cp: nil, hp: 100 + i)) { ev.append(e) }
            if let e = d.feed(blank()) { ev.append(e) }
            if let e = d.feed(stationed("Stat\(i)")) { ev.append(e) }
        }
        XCTAssertTrue(ev.isEmpty)
        // They do not reset: the fifth covered card fires.
        d.swipe(); ev = [d.feed(blank()), d.feed(stationed("Stat")), d.feed(card("Cov4", cp: nil, hp: 104))].compactMap { $0 }
        XCTAssertEqual(ev.count, 1)
        // Stationed cards alone, however many, never fire.
        var s = CoveredCpDetector()
        for i in 0..<50 { s.swipe(); XCTAssertNil(s.feed(stationed("Stat\(i)"))); XCTAssertNil(s.feed(blank())) }
    }

    func testACardWithANameButNoHpOrBarsIsNotACoveredCard() {
        var d = CoveredCpDetector()
        for i in 0..<20 { d.swipe(); var r = FrameReading(frame: nil, time: Double(i)); r.name = "Name\(i)"; r.nameText = r.name!; XCTAssertNil(d.feed(r)) }
        XCTAssertFalse(d.isCovered)
    }

    func testWithoutASwipeACardIsTheChangeOfNameOrHp() {
        var d = CoveredCpDetector()
        var ev = [CoveredCpDetector.Event]()
        for i in 0..<20 { if let e = d.feed(card("Same", cp: nil, hp: 100, t: Double(i))) { ev.append(e) } }
        XCTAssertTrue(ev.isEmpty, "twenty readings of one card are one card")
        for i in 0..<4 { if let e = d.feed(card("Next\(i)", cp: nil, hp: 100, t: 30 + Double(i))) { ev.append(e) } }
        XCTAssertEqual(ev.count, 1, "the fifth distinct card fires")
    }

    func testASwipeSeparatesTwoIdenticalCards() {
        var d = CoveredCpDetector()
        var ev = [CoveredCpDetector.Event]()
        for i in 0..<5 { d.swipe(); if let e = d.feed(card("Twin", cp: nil, hp: 100, t: Double(i))) { ev.append(e) } }
        XCTAssertEqual(ev.count, 1)
    }

    func testRearmsAfterThreeCardsWithACpThenASecondBannerAlertsAgain() {
        var d = CoveredCpDetector()
        var ev = feedCards(&d, good(2))
        ev += feedCards(&d, covered(6), from: 10)
        XCTAssertEqual(ev.count, 1)
        // Two cards with a CP, then a CP-less card: the count of good cards starts over, no re-arm.
        ev = feedCards(&d, good(2, 10), from: 20)
        ev += feedCards(&d, covered(1, 20), from: 25)
        ev += feedCards(&d, good(2, 20), from: 30)
        XCTAssertTrue(ev.isEmpty); XCTAssertTrue(d.isCovered, "two good cards twice are not three in a row")
        ev = feedCards(&d, [("Good30", 300)], from: 40)
        XCTAssertEqual(ev, [.cleared(at: ev.first.flatMap { if case .cleared(let t) = $0 { return t } else { return nil } })])
        XCTAssertFalse(d.isCovered)
        ev = feedCards(&d, good(1, 40), from: 50)
        ev += feedCards(&d, covered(5, 30), from: 60)
        guard case .covered(let c)? = ev.first, ev.count == 1 else { return XCTFail("second banner should alert: \(ev)") }
        XCTAssertEqual(c.firstName, "Cov30"); XCTAssertEqual(c.lastGoodName, "Good40")
    }

    /// Cards that end with no CP count towards a reminder only once they have ended, so a reminder comes with the first reading of the card after the fifth.
    func testStillCoveredEveryFiveCardsAfterTheFiringUntilCleared() {
        var d = CoveredCpDetector()
        var ev = feedCards(&d, covered(5))
        XCTAssertEqual(ev.count, 1); XCTAssertTrue(d.isCovered)
        ev = feedCards(&d, covered(5, 5), from: 10)
        XCTAssertTrue(ev.isEmpty, "five cards after the firing have not all ended yet")
        ev = feedCards(&d, covered(1, 10), from: 20)
        XCTAssertEqual(ev, [.stillCovered(cards: 5)])
        ev = feedCards(&d, covered(4, 11), from: 30)
        XCTAssertTrue(ev.isEmpty)
        ev = feedCards(&d, covered(1, 15), from: 40)
        XCTAssertEqual(ev, [.stillCovered(cards: 10)])
        // Cleared: nothing more, however many cards follow.
        ev = feedCards(&d, good(3), from: 50)
        XCTAssertEqual(ev.count, 1); if case .cleared? = ev.first {} else { XCTFail("\(ev)") }
        XCTAssertTrue(feedCards(&d, good(20, 10), from: 60).isEmpty)
    }

    /// Every card's first reading lacks the CP and a later one has it (the top of the card is still animating): the CP is visible, so the stretch clears after `rearm` such cards and no reminder is sent.
    func testCardsWhoseCpShowsAFrameLateClearTheStretchAndSendNoReminder() {
        var d = CoveredCpDetector()
        _ = feedCards(&d, covered(5))
        XCTAssertTrue(d.isCovered)
        var ev = [CoveredCpDetector.Event](); var t = 10.0
        for i in 0..<20 {
            d.swipe()
            t += 0.2; if let e = d.feed(card("Late\(i)", cp: nil, hp: 200 + i, t: t)) { ev.append(e) }
            t += 0.2; if let e = d.feed(card("Late\(i)", cp: 400 + i, hp: 200 + i, t: t)) { ev.append(e) }
        }
        XCTAssertEqual(ev.count, 1, "\(ev)")
        if case .cleared? = ev.first {} else { XCTFail("\(ev)") }
        XCTAssertFalse(d.isCovered)
    }

    func testARearmedStretchStartsItsReminderCountOver() {
        var d = CoveredCpDetector()
        var ev = feedCards(&d, covered(5)) + feedCards(&d, covered(6, 5), from: 10)
        XCTAssertEqual(ev.count, 2)
        ev = feedCards(&d, good(3), from: 20)
        XCTAssertEqual(ev.count, 1)
        ev = feedCards(&d, covered(5, 20), from: 30)
        guard case .covered? = ev.first, ev.count == 1 else { return XCTFail("a new stretch fires: \(ev)") }
        ev = feedCards(&d, covered(5, 25), from: 40) + feedCards(&d, covered(1, 30), from: 50)
        XCTAssertEqual(ev, [.stillCovered(cards: 5)], "counted from the new firing, not the old")
    }

    func testConfiguredThreshold() {
        var d = CoveredCpDetector(threshold: 2, rearm: 1)
        XCTAssertEqual(feedCards(&d, covered(2)).count, 1)
        XCTAssertEqual(feedCards(&d, good(1), from: 10).count, 1)   // cleared
        XCTAssertFalse(d.isCovered)
    }

    // MARK: the log note

    func testTheNoteIsSkippedByEveryReaderThatDoesNotKnowIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("covered-\(UUID().uuidString).jsonl")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let w = try XCTUnwrap(ReplayWriter(url: url))
        func r(_ t: Double) -> ReplayLine { .reading(ReplayReading(card("Moltres", cp: 2409, t: t), time: t, ms: 80)) }
        w.append(r(0)); w.append(CpCoveredNote(t: 0.5, first: "Smoliv", lastGood: "Snorlax", lastGoodCp: 133)); w.append(.tick(0.8)); w.append(r(1.4)); w.close()
        let raw = try String(contentsOf: url).split(separator: "\n")
        XCTAssertEqual(raw.count, 4)
        XCTAssertNil(ReplayLog.decode(Data(raw[1].utf8)), "an unknown kind decodes to nil")
        let lines = ReplayLog.lines(in: url)
        XCTAssertEqual(lines.count, 3, "lines(in:) skips it")
        XCTAssertEqual(ReplayLog.replay(lines, species: table).readings, 2)
        XCTAssertEqual(ReplayLog.cpCoveredNotes(in: url), [CpCoveredNote(t: 0.5, first: "Smoliv", lastGood: "Snorlax", lastGoodCp: 133)])
    }

    // MARK: real device runs

    /// Feed a replay log's lines in file order (ticks as swipes) and return where it fires, with the card names.
    private func firings(in lines: [ReplayLine], threshold: Int = CoveredCpDetector.defaultThreshold) -> [(Double, CoveredCpDetector.Covered)] {
        var d = CoveredCpDetector(threshold: threshold)
        var out = [(Double, CoveredCpDetector.Covered)]()
        for line in lines {
            switch line {
            case .tick: d.swipe()
            case .reading(let r): if case .covered(let c)? = d.feed(r.frameReading) { out.append((r.t, c)) }
            default: break
            }
        }
        return out
    }

    func testRun25AlarmStretchFiresOnceAtSmolivAfterSnorlax() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/run25-alarm-stretch.replay.jsonl")
        let fired = firings(in: ReplayLog.lines(in: url))
        XCTAssertEqual(fired.count, 1, "\(fired.map { $0.1.firstName })")
        let c = try XCTUnwrap(fired.first?.1)
        XCTAssertEqual(c.firstName, "Smoliv")
        XCTAssertEqual(c.lastGoodName, "Snorlax"); XCTAssertEqual(c.lastGoodCp, 133)
    }

    /// POGO_DEVICE_RUNS=<folder>: every replay log under it; prints where the detector fires. The evidence for the threshold; it asserts nothing.
    func testWalkEveryDeviceRunReplayLog() throws {
        guard let dir = ProcessInfo.processInfo.environment["POGO_DEVICE_RUNS"] else { throw XCTSkip("set POGO_DEVICE_RUNS to the device-runs folder to walk the real logs") }
        let files = try XCTUnwrap(FileManager.default.enumerator(atPath: dir)).compactMap { $0 as? String }.filter { $0.hasSuffix("replay.jsonl") }.sorted()
        XCTAssertGreaterThan(files.count, 0)
        for f in files {
            let lines = ReplayLog.lines(in: URL(fileURLWithPath: dir + "/" + f))
            let fired = firings(in: lines)
            let readings = lines.filter { if case .reading = $0 { return true } else { return false } }.count
            print("COVERED-WALK \(f): \(readings) readings, fires \(fired.count)" + fired.map { "\n    at t=\(String(format: "%.1f", $0.0)) first \($0.1.firstName) (from t=\(String(format: "%.1f", $0.1.startedAt ?? -1))), last good \($0.1.lastGoodName ?? "-") CP \($0.1.lastGoodCp ?? 0)" }.joined())
        }
    }
}
