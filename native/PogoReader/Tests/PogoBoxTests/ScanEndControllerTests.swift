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
        XCTAssertEqual(ScanEndDecision.decide(read: 1667, storageCount: 1684), .finish)
        XCTAssertEqual(ScanEndDecision.decide(read: 1666, storageCount: 1684), .pause)
        XCTAssertEqual(ScanEndDecision.decide(read: 1700, storageCount: 1684), .finish, "above the count")
        XCTAssertEqual(ScanEndDecision.decide(read: 11, storageCount: nil), .pause, "no count known")
        XCTAssertEqual(ScanEndDecision.decide(read: 5, storageCount: 0), .pause)
        XCTAssertEqual(ScanEndDecision.decide(read: 297, storageCount: 300), .finish); XCTAssertEqual(ScanEndDecision.decide(read: 296, storageCount: 300), .pause)
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
        let kinds = out.events.map { e -> String in switch e.1 { case .pause: return "pause"; case .resume: return "resume"; case .finish: return "finish"; case .none: return "-" } }
        XCTAssertEqual(kinds, ["pause", "resume", "pause", "resume", "pause", "resume", "finish"], "\(kinds)")
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
        let kinds = out.events.map { e -> String in switch e.1 { case .pause: return "pause"; case .resume: return "resume"; case .finish: return "finish"; case .none: return "-" } }
        XCTAssertEqual(kinds, ["pause", "resume"], "one pause for the whole stall, then the resume when the new card was read")
    }
}
