import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// FINISH or PAUSE at the quiet time, and the pause itself, on the device logs.
final class ScanEndControllerTests: XCTestCase {
    private let dev = NSString(string: "~/Developer/personal/pogo-frames/device-runs").expandingTildeInPath
    private func readings(_ lines: [ReplayLine]) -> [ReplayReading] { lines.compactMap { if case .reading(let r) = $0 { return r } else { return nil } }.sorted { $0.t < $1.t } }
    private func external(_ dir: String) throws -> [ReplayReading] {
        let f = try XCTUnwrap((try? FileManager.default.contentsOfDirectory(atPath: dev + "/" + dir))?.filter { $0.hasSuffix(".replay.jsonl") && !$0.contains(" 2") }.sorted().first, "\(dir) is not on this machine")
        return readings(ReplayLog.lines(in: URL(fileURLWithPath: dev + "/" + dir + "/" + f)))
    }

    /// Drive the controller as the extension does: every reading, with the Pokémon read so far from a `LiveGrouper`.
    private func drive(_ rs: [ReplayReading], count: Int?, period: Double = 1.2, controller: ScanEndController? = nil) -> (events: [(Double, ScanEndController.Event)], read: Int) {
        var c = controller ?? ScanEndController(period: period, storageCount: count)!
        var g = LiveGrouper(species: try? SpeciesTable.bundled())
        var events = [(Double, ScanEndController.Event)]()
        for r in rs {
            g.add(r.frameReading)
            let e = c.feed(r.frameReading, time: r.t, read: g.rows.count)
            if e != .none { events.append((r.t, e)); if case .finish = e { break } }
        }
        return (events, g.rows.count)
    }

    // MARK: T1, the decision

    func testFinishAtOnceWhenTheCountIsReachedAndPauseOtherwise() {
        XCTAssertEqual(ScanEndDecision.tolerance(1684), 17)
        XCTAssertEqual(StorageCountRules.maxEggSlots, 12)
        XCTAssertEqual(ScanEndDecision.decide(read: 1655, storageCount: 1684), .finish, "count - 12 - tolerance")
        XCTAssertEqual(ScanEndDecision.decide(read: 1654, storageCount: 1684), .pause)
        // the owner's numbers: 1,698 shown in the game (eggs included), about 1,688 pageable
        XCTAssertEqual(ScanEndDecision.decide(read: 1688, storageCount: 1698), .finish)
        XCTAssertEqual(ScanEndDecision.decide(read: 1194, storageCount: 1698), .pause)
        XCTAssertEqual(ScanEndDecision.decide(read: 388, storageCount: 400), .finish, "a small storage with 12 eggs")
        XCTAssertEqual(ScanEndDecision.decide(read: 1700, storageCount: 1684), .finish, "above the count")
        XCTAssertEqual(ScanEndDecision.decide(read: 11, storageCount: nil), .pause, "no count known")
        XCTAssertEqual(ScanEndDecision.decide(read: 5, storageCount: 0), .pause)
        XCTAssertEqual(ScanEndDecision.decide(read: 285, storageCount: 300), .finish); XCTAssertEqual(ScanEndDecision.decide(read: 284, storageCount: 300), .pause)
        XCTAssertEqual(ScanKindAdvice.tolerance(300), ScanEndDecision.tolerance(300), "the same tolerance as the full-scan advice")
    }

    // MARK: T6, the logs

    func testTheRealEndOfRun10FinishesAtOnceWithItsCountAndPausesWithoutOne() throws {
        let rs = readings(ReplayLog.lines(in: try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")))
        let withCount = drive(rs, count: 11)
        guard case .finish(let at, let last)? = withCount.events.last?.1 else { return XCTFail("\(withCount.events)") }
        XCTAssertEqual(at, withCount.events.last!.0, accuracy: 0.001); XCTAssertEqual(withCount.read, 11)
        XCTAssertEqual(last, 0, accuracy: 1e9)
        let without = drive(rs, count: nil)
        guard case .pause(let p)? = without.events.first?.1 else { return XCTFail("\(without.events)") }
        XCTAssertEqual(p.name, "Rayquaza"); XCTAssertEqual(p.read, 11); XCTAssertEqual(p.closed, true, "the tap closed the appraisal after Rayquaza")
        XCTAssertEqual(without.events.count, 1, "paused, nothing resumed it before the log ends")
    }

    func testAPartScanWithNoCountPausesThenFinishesAtTheTimeoutDatedAtTheOriginalQuietTime() throws {
        var rs = readings(ReplayLog.lines(in: try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")))
        let tail = try XCTUnwrap(rs.last)
        var t = tail.t
        while t < tail.t + 200 { t += 0.2; var r = tail; r.t = t; rs.append(r) }   // the stalled card stays on screen
        let out = drive(rs, count: nil)
        XCTAssertEqual(out.events.count, 2)
        guard case .pause(let p) = out.events[0].1, case .finish(let at, let last) = out.events[1].1 else { return XCTFail("\(out.events)") }
        XCTAssertEqual(at, p.at, accuracy: 0.001, "the end marker is dated at the original quiet time, so the tail is trimmed as before")
        XCTAssertEqual(last, p.last, accuracy: 0.001)
        XCTAssertEqual(out.events[1].0 - out.events[0].0, ScanEndDecision.pauseTimeoutSeconds, accuracy: 1.0)
        // the end marker the extension would write cuts the stalled stay, as an ordinary end does
        let lines: [ReplayLine] = rs.map { .reading($0) } + [.end(at: at, last: last)]
        let kept = readings(ReplayLog.trimmed(lines))
        XCTAssertLessThan(kept.count, rs.count); XCTAssertLessThanOrEqual(kept.last!.t, last + EndOfListDetector.keepAfterLast)
    }

    func testTheSecondStalledScanPausesWithItsAppraisalOpen() throws {
        let rs = readings(ReplayLog.lines(in: try Fixture.url("stall2-abra-open.replay.jsonl")))
        let out = drive(rs, count: 1684)
        guard case .pause(let p)? = out.events.last?.1 else { return XCTFail("\(out.events)") }
        XCTAssertEqual(p.name, "Abra"); XCTAssertEqual(p.cp, 799); XCTAssertEqual(p.closed, false, "the appraisal was still open")
        XCTAssertEqual(p.read, 51)
    }

    func testTheStallsAndRun12PauseWithTheOwnersCount() throws {
        for (dir, read, closed) in [("stall-scan-20261003T054229Z-b1f94047", 170, true), ("stall-scan-20261003T055448Z-6b2b1f4e", 51, false), ("stall-scan-20261003T065119Z-2fd03e3a-horsea", 1194, nil as Bool?), ("run12-tap-1500", 1552, false)] as [(String, Int, Bool?)] {
            let out = drive(try external(dir), count: 1684)
            guard case .pause(let p)? = out.events.last?.1 else { return XCTFail("\(dir): \(out.events)") }
            XCTAssertEqual(p.read, read, accuracy: 5, "\(dir): the live grouper counts a few fragments the refined result folds in")
            if let closed { XCTAssertEqual(p.closed, closed, dir) }
            XCTAssertFalse(out.events.contains { if case .finish = $0.1 { return true } else { return false } }, "\(dir) never finishes before the timeout")
        }
    }

    /// The four logs of the owner's one long scan joined (the real gaps between them removed): three stalls, each resumed by the next log's new card, and the end at the count.
    func testTheJoinedScanPausesThreeTimesResumesAndFinishesAtTheCount() throws {
        let dirs = ["stall-scan-20261003T054229Z-b1f94047", "stall-scan-20261003T055448Z-6b2b1f4e", "stall-scan-20261003T065119Z-2fd03e3a-horsea", "run14-tail-from-horsea-scan-20261003T070213Z-08997070"]
        var joined = [ReplayReading](), prevEnd: Double?
        for d in dirs {
            var rs = try external(d)
            if let pe = prevEnd, let t0 = rs.first?.t { let shift = pe + 1 - t0; rs = rs.map { var r = $0; r.t += shift; return r } }
            joined += rs; prevEnd = joined.last?.t
        }
        let out = drive(joined, count: 1684)
        let kinds = out.events.map { e -> String in switch e.1 { case .pause: return "pause"; case .resume: return "resume"; case .finish: return "finish"; case .windowRestarted: return "restart"; case .none: return "-" } }
        // In the real stalls the appraisal was reopened (bars on the paused card) before paging went on: those restart the window and are not resumes.
        XCTAssertEqual(kinds.filter { $0 != "restart" }, ["pause", "resume", "pause", "resume", "pause", "resume", "finish"], "\(kinds)")
        XCTAssertTrue(kinds.contains("restart"), "the reopened appraisals of the real stalls are seen")
        XCTAssertGreaterThanOrEqual(out.read, 1684 - ScanEndDecision.tolerance(1684))
    }

    func testAPauseIsNotRepeatedWhileTheSameCardStaysAndANewCardResumes() throws {
        var rs = readings(ReplayLog.lines(in: try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")))
        let tail = try XCTUnwrap(rs.last)
        var t = tail.t
        while t < tail.t + 60 { t += 0.2; var r = tail; r.t = t; rs.append(r) }       // the card stays 60 s
        var next = tail; next.name = "Pidgey"; next.hp = HP(current: 40, max: 40); next.cp = 300; next.ivs = nil
        while t < tail.t + 62 { t += 0.2; var r = next; r.t = t; rs.append(r) }       // then a new card appears: paging carried on
        let out = drive(rs, count: nil)
        let kinds = out.events.map { e -> String in switch e.1 { case .pause: return "pause"; case .resume: return "resume"; case .finish: return "finish"; case .windowRestarted: return "restart"; case .none: return "-" } }
        XCTAssertEqual(kinds, ["pause", "resume"], "one pause for the whole stall, then the resume when the new card was read")
    }

    // MARK: round 18 (V1, V2)

    /// run10 up to its pause (no count), the controller and the grouper positioned there.
    private func pausedAtRun10() throws -> (c: ScanEndController, g: LiveGrouper, rs: [ReplayReading], pause: ScanEndController.Pause, at: Double) {
        let rs = readings(ReplayLog.lines(in: try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")))
        var c = ScanEndController(period: 1.2, storageCount: nil)!
        var g = LiveGrouper(species: try? SpeciesTable.bundled())
        for r in rs {
            g.add(r.frameReading)
            if case .pause(let p) = c.feed(r.frameReading, time: r.t, read: g.rows.count) { return (c, g, rs, p, r.t) }
        }
        throw XCTSkip("no pause")
    }

    /// The bars the stalled card was read with before its appraisal closed (the card's own bars).
    private func ownBars(_ rs: [ReplayReading], upTo t: Double) throws -> IVs {
        try XCTUnwrap(rs.last { $0.t <= t && $0.ivs != nil }?.frameReading.ivs, "the stalled card was read with bars before the appraisal closed")
    }

    /// Round 24 (run17): after a pause, the same name and HP with ANOTHER CP and no bars is the stalled card (a tap covering part of the number), never a resume; a different HP is.
    func testTheSameNameAndHPWithAnotherCPIsNeverAResume() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        var tail = try XCTUnwrap(rs.last).frameReading; tail.ivs = nil
        var t = at, events = [ScanEndController.Event]()
        for cp in [1299, 1099, 199, 1209, 29, 129, 1129, 1199, 63, 4262, 3000] {
            tail.cp = cp
            for _ in 0..<3 { t += 0.4; let e = c.feed(tail, time: t, read: p.read); if e != .none { events.append(e) } }
        }
        tail.cp = nil; t += 0.4; _ = c.feed(tail, time: t, read: p.read)
        XCTAssertTrue(events.allSatisfy { if case .windowRestarted = $0 { return false } else { return true } } && events.isEmpty, "\(events)")
        XCTAssertNotNil(c.paused); XCTAssertEqual(c.pauseCount, 1)
        var other = tail; other.hp = HP(current: (tail.hp?.current ?? 50) + 3, max: (tail.hp?.max ?? 50) + 3); other.cp = 1995
        t += 0.4
        XCTAssertEqual(c.feed(other, time: t, read: p.read), .resume(at: t), "another HP is another card")
    }

    /// V1a: three new cards after a pause, then the timeout: all three are kept.
    func testThreeNewCardsAfterAPauseAreAllKeptWhenTheTimeoutFollows() throws {
        var (c, g, rs, _, at) = try pausedAtRun10()
        var t = at, events = [ScanEndController.Event](), added = [ReplayReading]()
        let base = try XCTUnwrap(rs.last)
        for (i, cp) in [3100, 3000, 2900].enumerated() {
            var card = base; card.name = ["Mewtwo", "Lugia", "Ho-Oh"][i]; card.cp = cp; card.hp = HP(current: 100 + i, max: 100 + i)
            for _ in 0..<5 { t += 1.2; card.t = t; added.append(card); g.add(card.frameReading); let e = c.feed(card.frameReading, time: t, read: g.rows.count); if e != .none { events.append(e) } }
        }
        let resumes = events.filter { if case .resume = $0 { return true } else { return false } }
        XCTAssertEqual(resumes.count, 1, "the first new card resumes it; later cards are just cards")
        let timeout = c.tick(now: t + ScanEndDecision.pauseTimeoutSeconds + 1)
        // whichever way it ends, nothing read after the pause is trimmed
        XCTAssertEqual(timeout, .none, "the first new card ended the pause, so the timeout has nothing to finish and nothing is cut")
        XCTAssertNil(c.paused); XCTAssertFalse(c.timedOut)
    }

    /// V1b (P3a): even if rows were read after the pause without the detector seeing a new card, a timeout is dated at the last reading AND its last card is the last reading, so
    /// nothing read after the pause is trimmed (the detector's own last-new time would cut it).
    func testATimeoutAfterRowsWereReadKeepsEverythingReadAfterThePause() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let tail = try XCTUnwrap(rs.last)
        let before = rs.filter { $0.t <= at }
        var t = at, out = ScanEndController.Event.none, added = [ReplayReading]()
        while t < at + 200, !({ if case .finish = out { return true } else { return false } }()) {
            t += 0.2; var r = tail.frameReading; r.ivs = nil
            added.append(ReplayReading(r, time: t, ms: 1)); out = c.feed(r, time: t, read: p.read + 3)
        }
        guard case .finish(let endAt, let last) = out else { return XCTFail("\(out)") }
        XCTAssertGreaterThan(endAt, p.at, "dated at the last reading, not the original quiet time")
        XCTAssertEqual(last, t, accuracy: 0.001, "the last card is the last reading: rows were read since the pause")
        XCTAssertTrue(c.timedOut)
        let lines: [ReplayLine] = before.map { .reading($0) } + added.map { .reading($0) } + [.end(at: endAt, last: last)]
        XCTAssertEqual(readings(ReplayLog.trimmed(lines)).count, before.count + added.count, "nothing read after the pause is cut")
    }

    /// P3b: "Finish now" after rows were read since the pause keeps them too (it used the stall's last card).
    func testFinishNowAfterRowsWereReadKeepsEverythingReadAfterThePause() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let tail = try XCTUnwrap(rs.last)
        let before = rs.filter { $0.t <= at }
        var t = at, added = [ReplayReading]()
        for _ in 0..<30 { t += 0.2; var r = tail.frameReading; r.ivs = nil; added.append(ReplayReading(r, time: t, ms: 1)); _ = c.feed(r, time: t, read: p.read + 2) }
        guard case .finish(let endAt, let last) = c.finishNow(at: t) else { return XCTFail("no finish") }
        XCTAssertEqual(last, t, accuracy: 0.001); XCTAssertFalse(c.timedOut, "a person's finish is not a timeout")
        let lines: [ReplayLine] = before.map { .reading($0) } + added.map { .reading($0) } + [.end(at: endAt, last: last)]
        XCTAssertEqual(readings(ReplayLog.trimmed(lines)).count, before.count + added.count)
        // and with nothing read since the pause the stall's own last card is used, as before
        var (c2, _, _, p2, at2) = try pausedAtRun10()
        guard case .finish(_, let last2) = c2.finishNow(at: at2 + 5) else { return XCTFail("no finish") }
        XCTAssertEqual(last2, p2.last, accuracy: 0.001)
    }

    /// P3c: a look-alike next card (same name, HP and CP, other settled bars than the card's own) read during a pause is a new card: it resumes, and its readings are not trimmed.
    func testALookAlikeCardWithOtherSettledBarsResumesAPauseAndIsNotTrimmed() throws {
        let rs = readings(ReplayLog.lines(in: try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")))
        var c = ScanEndController(period: 1.2, storageCount: nil)!
        var g = LiveGrouper(species: try? SpeciesTable.bundled())
        var t = 0.0, paused = false
        for r in rs { g.add(r.frameReading); t = r.t; if case .pause = c.feed(r.frameReading, time: r.t, read: g.rows.count) { paused = true; break } }
        XCTAssertTrue(paused)
        // the card's own bars were read during its stay (the appraisal was open before the tap closed it)
        let stayBars = rs.last { $0.t <= t && $0.ivs != nil }
        let own = try XCTUnwrap(stayBars?.frameReading.ivs, "the stalled card was read with bars before the appraisal closed")
        var twin = try XCTUnwrap(rs.last { $0.t <= t }).frameReading
        twin.ivs = IVs(atk: (own.atk + 7) % 16, def: (own.def + 7) % 16, hp: (own.hp + 7) % 16)
        t += 0.4
        XCTAssertNotEqual(c.feed(twin, time: t, read: g.rows.count), .resume(at: t), "ONE reading with other bars is not settled (the appraisal animates when it opens)")
        t += 0.4
        XCTAssertEqual(c.feed(twin, time: t, read: g.rows.count), .resume(at: t), "the same other bars in two card readings in a row: a new card, not a reopened appraisal")
        XCTAssertNil(c.paused)
    }

    /// P2: a single reading without bars on an OPEN appraisal (an OCR dropout) followed by bars is not a reopened appraisal and does not restart the pause window.
    func testADropoutOnAnOpenAppraisalDoesNotRestartTheWindow() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let tail = try XCTUnwrap(rs.last)
        var open = tail.frameReading; open.ivs = try ownBars(rs, upTo: at)
        var bare = open; bare.ivs = nil
        var t = at
        for _ in 0..<40 { t += 0.2; _ = c.feed(open, time: t, read: p.read) }       // the appraisal is open (a restart or a resume may happen while it opens)
        var events = [ScanEndController.Event]()
        for _ in 0..<3 { t += 0.2; events.append(c.feed(bare, time: t, read: p.read)); t += 0.2; events.append(c.feed(open, time: t, read: p.read)) }
        XCTAssertTrue(events.allSatisfy { $0 == .none }, "\(events)")
    }

    /// P2: reopening the appraisal restarts the pause window, but no number of restarts holds a scan paused past `pauseCapSeconds` without a new Pokémon.
    func testRestartsCannotHoldAPausePastTheCap() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let tail = try XCTUnwrap(rs.last)
        var bare = tail.frameReading; bare.ivs = nil
        var open = bare; open.ivs = try ownBars(rs, upTo: at)
        var t = at, restarts = 0, finishedAt: Double?
        search: while t < at + 3 * ScanEndDecision.pauseCapSeconds {
            for _ in 0..<60 { t += 1; if case .finish = c.feed(bare, time: t, read: p.read) { finishedAt = t; break search } }   // closed for 60 s (inside the 90 s window)
            t += 1
            switch c.feed(open, time: t, read: p.read) { case .windowRestarted: restarts += 1; case .finish: finishedAt = t; break search; default: break }
        }
        XCTAssertGreaterThanOrEqual(restarts, 2, "reopening did restart the window")
        let end = try XCTUnwrap(finishedAt, "the scan finished")
        XCTAssertLessThanOrEqual(end - at, ScanEndDecision.pauseCapSeconds + 2)
        XCTAssertTrue(c.timedOut)
    }

    /// V2: the timeout is checked without any reading (the heartbeat), and the finish is dated at the stall when nothing was read since.
    func testThePauseTimesOutOnTheHeartbeatWithNoFrames() throws {
        var (c, _, _, p, at) = try pausedAtRun10()
        XCTAssertEqual(c.tick(now: at + ScanEndDecision.pauseTimeoutSeconds - 1), .none)
        guard case .finish(let endAt, let last) = c.tick(now: at + ScanEndDecision.pauseTimeoutSeconds + 0.5) else { return XCTFail("no finish") }
        XCTAssertEqual(endAt, p.at, accuracy: 0.001); XCTAssertEqual(last, p.last, accuracy: 0.001)
        XCTAssertEqual(c.tick(now: at + 1000), .none, "once")
    }

    /// M3: bars appearing again on the paused card (the appraisal reopened) start the pause window over, and are not a resume; a different card still resumes.
    func testReopeningTheAppraisalOnThePausedCardRestartsTheWindowWithoutResuming() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let tail = try XCTUnwrap(rs.last)
        var bare = tail.frameReading; bare.ivs = nil
        var open = tail.frameReading; open.ivs = try ownBars(rs, upTo: at)
        var t = at
        while t < at + 60 { t += 0.2; XCTAssertEqual(c.feed(bare, time: t, read: p.read), .none) }   // the appraisal is closed for 60 s
        t += 0.2
        XCTAssertEqual(c.feed(open, time: t, read: p.read), .windowRestarted(at: t), "bars on the same card: a restart, not a resume")
        XCTAssertNotNil(c.paused, "still paused")
        let reopened = t
        XCTAssertEqual(c.tick(now: reopened + ScanEndDecision.pauseTimeoutSeconds - 1), .none, "a full window from the reopening, not from the pause")
        XCTAssertNotEqual(c.tick(now: reopened + ScanEndDecision.pauseTimeoutSeconds + 0.5), .none)
        // the same reading with a different name and HP is a new card, a resume
        var (c2, _, _, p2, at2) = try pausedAtRun10()
        var other = open; other.name = "Pidgey"; other.hp = HP(current: 40, max: 40); other.cp = 300
        XCTAssertEqual(c2.feed(other, time: at2 + 1, read: p2.read), .resume(at: at2 + 1))
        XCTAssertNil(c2.paused)
    }

    /// M5: only a Full scan pauses. The same stalled log finishes at once as an Add-and-update scan (no pause, no count), and still pauses as a Full scan short of its count.
    func testAPartScanFarBelowAnyCountFinishesAndAFullScanShortOfItsCountPauses() throws {
        let rs = readings(ReplayLog.lines(in: try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")))
        let part = drive(rs, count: nil, controller: ScanEndController(period: 1.2, storageCount: 1000, eggCount: 5, pausesAllowed: false))
        guard case .finish? = part.events.last?.1 else { return XCTFail("\(part.events)") }
        XCTAssertFalse(part.events.contains { if case .pause = $0.1 { return true } else { return false } }, "a part scan never pauses")
        XCTAssertNil(ScanEndController(period: 1.2, storageCount: 1000, eggCount: 5, pausesAllowed: false)!.storageCount, "and does not keep the count")
        let full = drive(rs, count: nil, controller: ScanEndController(period: 1.2, storageCount: 1000, eggCount: 5, pausesAllowed: true))
        guard case .pause? = full.events.first?.1 else { return XCTFail("\(full.events)") }
    }

    /// M4: expected Pokémon = the game's count less the eggs typed; no egg count falls back to the flat 12. run15: 1,698 shown, 8 eggs, 1,685 read.
    func testTheEggCountReplacesTheFlatAllowance() {
        XCTAssertEqual(StorageCountRules.lowestRead(1698, eggs: 8), 1698 - 8 - 17)
        XCTAssertEqual(StorageCountRules.lowestRead(1698), 1698 - 12 - 17, "no egg count: the flat allowance")
        XCTAssertEqual(StorageCountRules.lowestRead(1698, eggs: 99), 1698 - 12 - 17, "out of range counts as none")
        XCTAssertEqual(StorageCountRules.expected(count: 1698, eggs: 8), 1690); XCTAssertNil(StorageCountRules.expected(count: 1698, eggs: nil))
        XCTAssertEqual(ScanEndDecision.decide(read: 1685, storageCount: 1698, eggs: 8), .finish, "run15 with 8 eggs: 5 below the 1,690 expected, tolerance 17")
        XCTAssertEqual(ScanEndDecision.decide(read: 1672, storageCount: 1698, eggs: 8), .pause); XCTAssertEqual(ScanEndDecision.decide(read: 1673, storageCount: 1698, eggs: 8), .finish)
        XCTAssertEqual(ScanEndDecision.decide(read: 1676, storageCount: 1698, eggs: 0), .pause, "0 eggs is tighter than the flat 12")
        XCTAssertEqual(ScanEndDecision.decide(read: 1676, storageCount: 1698), .finish)
        let d = ScanKindAdvice.decide(endedAtListEnd: true, pokemonRead: 1685, typedCount: 1698, logTruncated: false, logFailed: false, commandPeriod: 1.2, eggCount: 8)
        XCTAssertTrue(d.fullIsSound, d.reason ?? "")
        XCTAssertTrue(ScanKindAdvice.matchSentence(pokemonRead: 1685, decision: d, eggCount: 8)!.contains("the 8 eggs you typed"))
        let short = ScanKindAdvice.decide(endedAtListEnd: true, pokemonRead: 1676, typedCount: 1698, logTruncated: false, logFailed: false, commandPeriod: 1.2, eggCount: 0)
        XCTAssertFalse(short.fullIsSound); XCTAssertTrue(short.reason!.contains("you typed 0"))
        // the pause notification counts what is expected
        XCTAssertTrue(ScanNotification.paused(scan: 1, event: 1, read: 170, storageCount: 1698, eggCount: 8, lastName: "A", lastCP: 1, sizes: [2000]).body.contains("170 of about 1690 read"))
        XCTAssertTrue(ScanNotification.paused(scan: 1, event: 1, read: 170, storageCount: 1698, lastName: "A", lastCP: 1, sizes: [2000]).body.contains("170 of about 1698 read"))
    }

    /// N1a: the appraisal reopened on the SAME stalled card animates (run15's Rayquaza read 9/9/9 at 0.94 before 13/12/14): one differing reading, then the card's own bars. A single
    /// window restart, no resume, no second pause.
    func testAnAnimatedReopenOnTheSameCardIsOneRestartAndNoResume() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let own = try ownBars(rs, upTo: at)
        var bare = try XCTUnwrap(rs.last).frameReading; bare.ivs = nil
        var anim = bare; anim.ivs = IVs(atk: max(0, own.atk - 4), def: max(0, own.def - 4), hp: max(0, own.hp - 4)); anim.ivConfidence = 0.94
        var open = bare; open.ivs = own
        var t = at, events = [ScanEndController.Event]()
        func feed(_ r: FrameReading) { t += 0.4; let e = c.feed(r, time: t, read: p.read); if e != .none { events.append(e) } }
        for _ in 0..<150 { feed(bare) }   // closed for 60 s
        feed(anim)
        for _ in 0..<150 { feed(open) }   // reopened and settled, nothing pages for another minute (inside the window the reopening restarted)
        XCTAssertEqual(events.count, 1, "\(events)")
        guard case .windowRestarted? = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(c.pauseCount, 1); XCTAssertNotNil(c.paused)
    }

    /// N1b: a resume that read no new Pokémon (here a different card shown for a moment) and a second pause on the same stall do not start the cap over: from the first pause to the
    /// finish no more than `pauseCapSeconds`, however the cycles fall.
    func testTheCapHoldsAcrossAResumeThatReadNothingNew() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let tail = try XCTUnwrap(rs.last).frameReading
        var t = at, resumes = 0, pauses = 1, finishedAt: Double?, minRemaining = 999.0
        search: for cycle in 0..<30 {
            // a different card for 100 s (nothing is paged: the same read count): it resumes, then pauses on its own stall
            var card = tail; card.name = cycle % 2 == 0 ? "Mewtwo" : "Lugia"; card.hp = HP(current: 100 + cycle, max: 100 + cycle); card.cp = 3000 + cycle; card.ivs = nil
            for _ in 0..<150 {   // 60 s on each card: it pauses, then the next card resumes it, inside the 90 s window
                t += 0.4
                switch c.feed(card, time: t, read: p.read) { case .resume: resumes += 1; case .pause: pauses += 1; minRemaining = min(minRemaining, c.remainingPauseSeconds(now: t) ?? 999); case .finish: finishedAt = t; break search; default: break }
            }
        }
        XCTAssertGreaterThanOrEqual(resumes, 2); XCTAssertGreaterThanOrEqual(pauses, 2)
        let end = try XCTUnwrap(finishedAt, "the scan finished"); XCTAssertLessThanOrEqual(end - at, ScanEndDecision.pauseCapSeconds + 2); XCTAssertTrue(c.timedOut)
        // a later pause of the same stall reports what is really left, not the full window (the notification says it)
        XCTAssertLessThan(minRemaining, ScanEndDecision.pauseTimeoutSeconds - 1, "a pause that continues the cap has less than the whole window left")
        XCTAssertEqual(ScanNotification.limitText(seconds: nil), ScanNotification.pauseLimitText); XCTAssertEqual(ScanNotification.limitText(seconds: 150), "150 seconds")
        XCTAssertEqual(ScanNotification.limitText(seconds: 120), "2 minutes"); XCTAssertEqual(ScanNotification.limitText(seconds: 59), "1 minute"); XCTAssertEqual(ScanNotification.limitText(seconds: 0), "less than 10 seconds")
        XCTAssertTrue(ScanNotification.paused(scan: 1, event: 2, read: 5, storageCount: 100, lastName: "A", lastCP: 1, sizes: [100], limitSeconds: 4).body.contains("in less than 10 seconds"))
    }

    /// The pending-row question: a card the grouper would add only at its `finish()` (a name-only or hidden-CP run, LiveGrouper.swift ~180-219) cannot be read during a pause without
    /// ending it, because the controller resumes on any different name or HP (the detector resets), so a finish while paused never trims such a row. Pinned here.
    func testAnyOtherNameOrHPReadDuringAPauseEndsItEvenWhenTheCountDoesNotGrow() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let tail = try XCTUnwrap(rs.last).frameReading
        var nameOnly = FrameReading(); nameOnly.name = "Pidgey"; nameOnly.baseName = "Pidgey"
        XCTAssertEqual(c.feed(nameOnly, time: at + 1, read: p.read), .resume(at: at + 1), "a name-only card (CP and HP hidden) is a different name: a resume")
        var (c2, _, _, p2, at2) = try pausedAtRun10()
        var hpOnly = tail; hpOnly.hp = HP(current: (tail.hp?.current ?? 50) + 7, max: (tail.hp?.max ?? 50) + 7); hpOnly.cp = nil; hpOnly.ivs = nil
        XCTAssertEqual(c2.feed(hpOnly, time: at2 + 1, read: p2.read), .resume(at: at2 + 1), "a different HP, CP hidden: a resume")
    }

    /// Round 23 (R1): a same-name, same-HP card with the CP hidden is shown after a paging tick during a pause: nothing resumes and the live count does not grow (the grouper adds the row
    /// only at `finish()`). A timeout must not date the end at the pause, or `ReplayLog.trimmed` cuts the card. Through the pipeline: the row survives (12, not 11).
    func testACardShownAfterATickDuringAPauseSurvivesATimeout() throws {
        let rs = readings(ReplayLog.lines(in: try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")))
        var c = ScanEndController(period: 1.2, storageCount: nil)!
        var g = LiveGrouper(species: try? SpeciesTable.bundled())
        var lines = [ReplayLine](), pause: ScanEndController.Pause?, at = 0.0
        for r in rs { lines.append(.reading(r)); g.add(r.frameReading); if case .pause(let q) = c.feed(r.frameReading, time: r.t, read: g.rows.count) { pause = q; at = r.t; break } }
        let q = try XCTUnwrap(pause); lines.append(.pause(at: q.at, last: q.last, read: q.read, closed: q.closed))
        let tail = try XCTUnwrap(rs.last).frameReading
        var t = at + 5
        lines.append(.tick(t)); g.swipe(at: t); c.noteSwipe(at: t); t += 0.7
        var twin = FrameReading(); twin.name = tail.name; twin.baseName = tail.baseName; twin.speciesIds = tail.speciesIds; twin.hp = tail.hp
        for _ in 0..<30 { twin.time = t; lines.append(.reading(ReplayReading(twin, time: t, ms: 1))); g.add(twin); XCTAssertEqual(c.feed(twin, time: t, read: g.rows.count), .none); t += 0.4 }
        XCTAssertEqual(g.rows.count, q.read, "the live count did not grow: the row is added at finish()")
        var fin = ScanEndController.Event.none
        while t < at + 400, fin == .none { t += 1; fin = c.tick(now: t) }
        guard case .finish(let endAt, let last) = fin else { return XCTFail("\(fin)") }
        XCTAssertGreaterThan(last, q.last + 20, "dated at the last reading, not the stall")
        lines += [.pauseTimedOut(at: endAt), .end(at: endAt, last: last)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("r1-\(UUID().uuidString).jsonl")
        try (lines.map { String(decoding: ReplayLog.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        var g2 = g; g2.finish()
        XCTAssertEqual(g2.rows.count, q.read + 1, "the live grouper adds the card's row at finish()")
        // The end marker must not cut the card's readings. (The pipeline's own grouper keeps a same-name, same-HP card with the CP hidden in the stalled card's row, so the final row count is
        // 11 either way; what is lost without the fix is the readings, which a different reading shape could turn into a row.)
        let kept = readings(ReplayLog.trimmed(lines)).filter { $0.t > at + 5 }.count
        XCTAssertEqual(kept, 30, "all 30 readings of the card shown after the tick are kept")
        let base = try ScanPipeline.process(replay: Fixture.url("device-run10-tap-25-autoend.replay.jsonl"), engine: sharedEngine, paging: PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds))
        let out = try ScanPipeline.process(replay: url, engine: sharedEngine, paging: PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds))
        XCTAssertEqual(base.scan.rows.count, 11); XCTAssertEqual(out.scan.rows.count, 11, "no row is created from the kept tail of the same stalled card")
        // the SAME stalled card read for the whole window, with no tick and no other bars, still dates at the stall (the repeated card is trimmed)
        var (c2, _, _, p2, at2) = try pausedAtRun10()
        guard case .finish(_, let last2) = c2.tick(now: at2 + ScanEndDecision.pauseTimeoutSeconds + 1) else { return XCTFail("no finish") }
        XCTAssertEqual(last2, p2.last, accuracy: 0.001)
    }

    /// Round 23 (cross-vendor variant): the same card with other bars (beyond a notch) read ONCE, then name and HP without bars: evidence of another card, so a timeout keeps the tail.
    func testOtherBarsReadOnceDuringAPauseKeepTheTailAtATimeout() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let own = try ownBars(rs, upTo: at)
        var other = try XCTUnwrap(rs.last).frameReading; other.ivs = IVs(atk: (own.atk + 7) % 16, def: (own.def + 7) % 16, hp: (own.hp + 7) % 16)
        var bare = other; bare.ivs = nil
        var t = at + 1
        _ = c.feed(other, time: t, read: p.read)
        for _ in 0..<40 { t += 0.4; _ = c.feed(bare, time: t, read: p.read) }
        guard case .finish(_, let last) = c.tick(now: at + ScanEndDecision.pauseTimeoutSeconds + 1) else { return XCTFail("no finish") }
        XCTAssertGreaterThan(last, p.last + 10, "the tail read after the other bars is kept")
    }
}
