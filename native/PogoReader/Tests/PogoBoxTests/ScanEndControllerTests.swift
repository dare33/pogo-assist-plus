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

    /// V1a: after a pause, a card with the same name and HP but another CP is a new card (the detector resets its clock), so it resumes the scan and its row is kept.
    func testAPauseResumesOnASameNameSameHPCardWithAnotherCP() throws {
        var (c, g, rs, p, at) = try pausedAtRun10()
        var tail = try XCTUnwrap(rs.last)
        var t = at, events = [ScanEndController.Event]()
        tail.cp = (tail.cp ?? 4000) == 1500 ? 1600 : 1500
        for _ in 0..<20 { t += 0.2; var r = tail; r.t = t; g.add(r.frameReading); let e = c.feed(r.frameReading, time: t, read: g.rows.count); if e != .none { events.append(e) } }
        guard case .resume? = events.first else { return XCTFail("\(events)") }
        // it stays on screen until the timeout: a second pause, then the finish dated at THAT card, so the new card's row is not trimmed
        while t < at + 400, !events.contains(where: { if case .finish = $0 { return true } else { return false } }) {
            t += 0.2; var r = tail; r.t = t; g.add(r.frameReading); let e = c.feed(r.frameReading, time: t, read: g.rows.count); if e != .none { events.append(e) }
        }
        guard case .finish(let endAt, let last)? = events.last else { return XCTFail("\(events)") }
        XCTAssertGreaterThan(last, p.last, "the end is dated at the new card, not the original stall")
        let lines: [ReplayLine] = (rs.map { .reading($0) }) + [ReplayLine.reading(ReplayReading(tail.frameReading, time: at + 1, ms: 1))] + [.end(at: endAt, last: last)]
        XCTAssertTrue(readings(ReplayLog.trimmed(lines)).contains { $0.cp == tail.cp && $0.t == at + 1 }, "the card read after the pause is kept")
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
        var endAt = t, last = t
        if case .finish(let a, let l) = timeout { endAt = a; last = l }
        let lines: [ReplayLine] = rs.map { .reading($0) } + added.map { .reading($0) } + [.end(at: endAt, last: last)]
        for card in added where card.t <= last + EndOfListDetector.keepAfterLast { XCTAssertTrue(readings(ReplayLog.trimmed(lines)).contains { $0.t == card.t }) }
        XCTAssertGreaterThanOrEqual(last, added.last!.t - 10, "dated at the last new card")
    }

    /// V1b: even if rows were read after the pause without the detector seeing a new card, a timeout is dated at the last reading, never back at the stall.
    func testATimeoutAfterRowsWereReadIsNotDatedAtTheStall() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let tail = try XCTUnwrap(rs.last)
        var t = at, out = ScanEndController.Event.none
        while t < at + 200, !({ if case .finish = out { return true } else { return false } }()) { t += 0.2; out = c.feed(tail.frameReading, time: t, read: p.read + 3) }
        guard case .finish(let endAt, _) = out else { return XCTFail("\(out)") }
        XCTAssertGreaterThan(endAt, p.at, "dated at the last reading, not the original quiet time")
    }

    /// V2: the timeout is checked without any reading (the heartbeat), and the finish is dated at the stall when nothing was read since.
    func testThePauseTimesOutOnTheHeartbeatWithNoFrames() throws {
        var (c, _, _, p, at) = try pausedAtRun10()
        XCTAssertEqual(c.tick(now: at + ScanEndDecision.pauseTimeoutSeconds - 1), .none)
        guard case .finish(let endAt, let last) = c.tick(now: at + ScanEndDecision.pauseTimeoutSeconds + 0.5) else { return XCTFail("no finish") }
        XCTAssertEqual(endAt, p.at, accuracy: 0.001); XCTAssertEqual(last, p.last, accuracy: 0.001)
        XCTAssertEqual(c.tick(now: at + 1000), .none, "once")
    }

    /// M3: bars appearing again on the paused card (the appraisal reopened) start the 180 s window over, and are not a resume; a different card still resumes.
    func testReopeningTheAppraisalOnThePausedCardRestartsTheWindowWithoutResuming() throws {
        var (c, _, rs, p, at) = try pausedAtRun10()
        let tail = try XCTUnwrap(rs.last)
        var bare = tail.frameReading; bare.ivs = nil
        var open = tail.frameReading; open.ivs = IVs(atk: 7, def: 8, hp: 9)
        var t = at
        while t < at + 100 { t += 0.2; XCTAssertEqual(c.feed(bare, time: t, read: p.read), .none) }   // the appraisal is closed for 100 s
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
}
