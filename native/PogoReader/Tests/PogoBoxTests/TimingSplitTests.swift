import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class TimingSplitTests: XCTestCase {
    // MARK: hand-built beats

    /// Rows whose stays are `stays` seconds, one after the other (card readings every 0.2 s inside each stay).
    /// `hp` and `ivs` can differ per row to build a change inside a stay.
    private func scan(stays: [Double], names: [String]? = nil, start: Double = 100) -> ScanResult {
        var t = start
        var rows = [ScanRow]()
        for (i, stay) in stays.enumerated() {
            let name = names?[i] ?? "Mon\(i)"
            var frames = [FrameLabel]()
            var x = t + 0.1
            while x < t + stay - 0.05 {
                frames.append(FrameLabel(frame: "f\(i)-\(frames.count)", time: x, cp: 500 + i, cpText: "\\(500 + i)", name: name, hp: "100/100", ivs: "1/2/3", ivConfidence: 0.9, sharpness: 1, clip: nil))
                x += 0.2
            }
            rows.append(ScanRow(index: i + 1, name: name, display: name, form: "", speciesId: name.lowercased(), dex: 1, cp: 500 + i, hp: 100, ivs: IVs(atk: 1, def: 2, hp: 3),
                                ivsRead: IVs(atk: 1, def: 2, hp: 3), ivsGuess: nil, level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: [], frames: frames))
            t += stay
        }
        return ScanResult(rows: rows, review: [], unmatched: [])
    }

    private func steady(_ n: Int, period: Double = 1.7, jitter: [Double] = [0, 0.1, -0.1, 0.05, -0.05]) -> [Double] {
        (0..<n).map { period + jitter[$0 % jitter.count] }
    }

    private func counts(_ r: (scan: ScanResult, changes: [Refine.Change], notices: [String], indexMap: [Int: Int])) -> (rows: Int, changes: Int) { (r.scan.rows.count, r.changes.count) }

    func testATwinOnASteadyBeatIsSplit() {
        var stays = steady(20)
        stays[10] = 3.4   // two periods
        let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.7)
        let r = Refine.splitByTiming(scan(stays: stays), readings: [], paging: hint)
        XCTAssertEqual(r.scan.rows.count, 21)
        XCTAssertEqual(r.changes.map(\.kind), [.timingSplit])
        XCTAssertEqual(r.changes.map(\.rowIndex), [12])
        let (a, b) = (r.scan.rows[10], r.scan.rows[11])
        XCTAssertEqual(a.name, b.name); XCTAssertEqual(a.cp, b.cp)
        XCTAssertEqual(b.flags, ["same-as-previous", "split-by-timing"])
        XCTAssertEqual(a.flags, [])
        XCTAssertEqual(a.frames.count + b.frames.count, scan(stays: stays).rows[10].frames.count)
        XCTAssertTrue(a.frames.map { $0.time! }.max()! < b.frames.map { $0.time! }.min()!)
        XCTAssertEqual(r.scan.rows.map(\.index), Array(1...21))
        XCTAssertEqual(r.scan.review.map(\.index), [12])
        XCTAssertEqual(r.indexMap[11], 11)
        XCTAssertEqual(r.indexMap[12], 13, "later rows move down by one")
    }

    func testNeverTheFirstOrLastRow() {
        var stays = steady(20)
        stays[0] = 3.4; stays[19] = 3.4
        let r = Refine.splitByTiming(scan(stays: stays), readings: [], paging: PagingHint())
        XCTAssertTrue(r.changes.isEmpty)
        XCTAssertEqual(r.scan.rows.count, 20)
    }

    func testNotWithAnIrregularBeatOnEitherSide() {
        // hand paging: stays all over the place
        let irregular: [Double] = [0.9, 2.6, 1.1, 4.0, 1.5, 0.8, 3.4, 2.2, 1.2, 1.9, 0.7, 2.8, 1.4, 3.1, 1.0, 2.0]
        XCTAssertTrue(Refine.splitByTiming(scan(stays: irregular), readings: [], paging: PagingHint()).changes.isEmpty)
        // a steady beat on the left only (a pause, then hand paging)
        var oneSided = steady(8) + [3.4] + [0.9, 2.6, 1.1, 4.0, 1.5, 0.8, 2.2, 1.2]
        XCTAssertTrue(Refine.splitByTiming(scan(stays: oneSided), readings: [], paging: PagingHint()).changes.isEmpty)
        oneSided = [0.9, 2.6, 1.1, 4.0, 1.5, 0.8, 2.2, 1.2] + [3.4] + steady(8)
        XCTAssertTrue(Refine.splitByTiming(scan(stays: oneSided), readings: [], paging: PagingHint()).changes.isEmpty)
        // too few stays on a side to call it a beat
        XCTAssertTrue(Refine.splitByTiming(scan(stays: steady(2) + [3.4] + steady(10)), readings: [], paging: PagingHint()).changes.isEmpty)
    }

    func testOnlyWholePeriodsAndOnlyPairs() {
        for stay in [2.55, 2.1, 4.7, 5.1, 6.8] {   // 1.5, 1.2, 2.8, 3 and 4 periods
            var stays = steady(20); stays[10] = stay
            XCTAssertTrue(Refine.splitByTiming(scan(stays: stays), readings: [], paging: PagingHint()).changes.isEmpty, "\(stay)")
        }
        var stays = steady(20); stays[10] = 3.5
        XCTAssertEqual(Refine.splitByTiming(scan(stays: stays), readings: [], paging: PagingHint()).changes.count, 1, "3.5 s is two periods within the tolerance")
    }

    func testAReadingThatChangesInsideTheRowIsNotATwin() {
        var stays = steady(20); stays[10] = 3.4
        var s = scan(stays: stays)
        s.rows[10].frames[s.rows[10].frames.count / 2 + 1].hp = "90/100"
        XCTAssertTrue(Refine.splitByTiming(s, readings: [], paging: PagingHint()).changes.isEmpty)
        var s2 = scan(stays: stays)
        for k in s2.rows[10].frames.indices where k > 4 { s2.rows[10].frames[k].ivs = "4/5/6" }
        XCTAssertTrue(Refine.splitByTiming(s2, readings: [], paging: PagingHint()).changes.isEmpty)
    }

    func testAMenuOpenInsideTheStayIsNotABeat() {
        var stays = steady(20); stays[10] = 3.4
        let s = scan(stays: stays)
        let mid = s.rows[10].frames.compactMap(\.time)
        var readings = [FrameReading]()
        for k in 0..<4 { readings.append(FrameReading(frame: "m\(k)", time: (mid.min()! + mid.max()!) / 2 + Double(k) * 0.2 - 0.3)) }   // no CP, no HP
        XCTAssertTrue(Refine.splitByTiming(s, readings: readings, paging: PagingHint()).changes.isEmpty)
        XCTAssertEqual(Refine.splitByTiming(s, readings: Array(readings.prefix(2)), paging: PagingHint()).changes.count, 1, "one or two unreadable frames (a fast swipe) are allowed")
    }

    func testABatchJoinIsNotATwinAndATwinAtAJoinIsFound() {
        // a 1.0 s beat; a join adds 0.8 s, so the stay across it is 1.8 s, which is not two periods
        var stays = steady(20, period: 1.0, jitter: [0, 0.03, -0.03])
        stays[10] = 1.8
        let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.0, joinExtraSeconds: 0.8)
        XCTAssertTrue(Refine.splitByTiming(scan(stays: stays), readings: [], paging: hint).changes.isEmpty, "a join")
        XCTAssertTrue(Refine.splitByTiming(scan(stays: stays), readings: [], paging: PagingHint(pagedByCommand: true)).changes.isEmpty, "a join, with the default join length")
        // a twin across a join is 2 periods + 0.8 s
        stays[10] = 2.8
        let r = Refine.splitByTiming(scan(stays: stays), readings: [], paging: hint)
        XCTAssertEqual(r.changes.count, 1)
        XCTAssertEqual(r.scan.rows.count, 21)
        XCTAssertTrue(r.changes[0].detail.contains("batch join"))
        // a plain twin at the same beat
        stays[10] = 2.0
        XCTAssertEqual(Refine.splitByTiming(scan(stays: stays), readings: [], paging: hint).changes.count, 1)
        // with no joins in the scan (joinExtraSeconds 0), 1.8 s is nearest to two periods but too far (0.2 of a period is the limit)
        stays[10] = 1.75
        XCTAssertTrue(Refine.splitByTiming(scan(stays: stays), readings: [], paging: PagingHint(pagedByCommand: true, joinExtraSeconds: 0)).changes.isEmpty)
    }

    func testTheHintTurnsItOffOrChecksThePeriod() {
        var stays = steady(20); stays[10] = 3.4
        let s = scan(stays: stays)
        XCTAssertTrue(Refine.splitByTiming(s, readings: [], paging: PagingHint(pagedByCommand: false)).changes.isEmpty, "paged by hand")
        XCTAssertTrue(Refine.splitByTiming(s, readings: [], paging: PagingHint(pagedByCommand: true, expectedPeriod: 1.0)).changes.isEmpty, "measured 1.7 s against 1.0 s written")
        XCTAssertEqual(Refine.splitByTiming(s, readings: [], paging: PagingHint(pagedByCommand: true, expectedPeriod: 1.6)).changes.count, 1, "1.7 s against 1.6 s: Voice Control runs a few percent slow")
    }

    func testWithNoHintItIsStricter() {
        var stays = steady(20); stays[10] = 3.4
        // this jitter is a regularity of about 0.06: fine locally, but the scan as a whole must be steadier with no hint
        let rough = steady(20, jitter: [0, 0.2, -0.2, 0.1, -0.15, 0.05]); var rough2 = rough; rough2[10] = 3.4
        XCTAssertTrue(Refine.splitByTiming(scan(stays: rough2), readings: [], paging: nil).changes.isEmpty)
        XCTAssertEqual(Refine.splitByTiming(scan(stays: rough2), readings: [], paging: PagingHint()).changes.count, 1)
        // a beat faster than the fastest generated one is not a command's, however regular
        var fast = steady(20, period: 0.8, jitter: [0]); fast[10] = 1.6
        XCTAssertTrue(Refine.splitByTiming(scan(stays: fast), readings: [], paging: nil).changes.isEmpty)
        XCTAssertEqual(Refine.splitByTiming(scan(stays: stays), readings: [], paging: nil).changes.count, 1, "steady and 1.7 s: split with no hint")
    }

    func testAPieceWithNoReadingsIsNotSplit() {
        var stays = steady(20); stays[10] = 3.4
        var s = scan(stays: stays)
        // the row's readings all fall in its first period, and the next row's come late, so the change to the next Pokemon is where it was
        let frames = s.rows[10].frames
        let oldLast = frames.last!.time!
        s.rows[10].frames = Array(frames.prefix(5))
        let delta = oldLast - s.rows[10].frames.last!.time!
        for k in s.rows[11].frames.indices { s.rows[11].frames[k].time! += delta }
        let r = Refine.splitByTiming(s, readings: [], paging: PagingHint())
        XCTAssertTrue(r.changes.isEmpty)
        XCTAssertEqual(r.notices.count, 1)
    }

    func testTooFewRowsAndMissingTimes() {
        XCTAssertTrue(Refine.splitByTiming(scan(stays: steady(6)), readings: [], paging: PagingHint()).changes.isEmpty)
        var s = scan(stays: steady(20)); s.rows[5].frames = []
        XCTAssertTrue(Refine.splitByTiming(s, readings: [], paging: PagingHint()).changes.isEmpty)
    }

    // MARK: ScanPace

    func testScanPaceMeasuresTheBeat() throws {
        let p = try XCTUnwrap(ScanPace.measure(rows: scan(stays: steady(20)).rows))
        XCTAssertEqual(p.medianPeriod, 1.7, accuracy: 0.06)
        XCTAssertTrue(p.isRegular)
        XCTAssertLessThan(p.regularity, 0.1)
        XCTAssertEqual(p.staysMeasured, 18)
        XCTAssertEqual(p.periodsObserved, 18)
        var withTwin = steady(20); withTwin[10] = 3.4
        let q = try XCTUnwrap(ScanPace.measure(rows: scan(stays: withTwin).rows))
        XCTAssertEqual(q.periodsObserved, 17, "the twin's stay is not a single period")
        XCTAssertEqual(q.medianPeriod, p.medianPeriod, accuracy: 0.06)
        let hand = try XCTUnwrap(ScanPace.measure(rows: scan(stays: [0.9, 2.6, 1.1, 4.0, 1.5, 0.8, 3.4, 2.2, 1.2, 1.9, 0.7, 2.8]).rows))
        XCTAssertFalse(hand.isRegular)
        XCTAssertNil(ScanPace.measure(rows: scan(stays: [1, 1, 1]).rows), "three rows have one stay")
        XCTAssertNil(ScanPace.measure(rows: []))
    }

    // MARK: the device logs

    private func refine(_ fixture: String, paging: PagingHint? = nil) throws -> Refine.Refined {
        let l = try ReplayReadings.load(url: Fixture.url(fixture))
        let base = try sharedEngine.finish(readings: l.readings)
        return try Refine.apply(to: base, readings: l.readings, ticks: l.ticks, engine: sharedEngine, paging: paging)
    }

    /// The fast-swipe run (1.7 s beat): the identical Staraptor pair (CP 1986, HP 139, 15/13/11) leaves no swipe in the readings
    /// (every other frame was dropped), so only the beat shows it: 3.4 s is two periods.
    func testFastSwipeLogGivesFiftyOne() throws {
        for paging in [nil, PagingHint(pagedByCommand: true, expectedPeriod: 1.6)] as [PagingHint?] {
            let r = try refine("device-run4-fast-swipe-2026-10-02.replay.jsonl", paging: paging)
            XCTAssertEqual(r.scan.rows.count, 51)
            XCTAssertEqual(r.changes.filter { $0.kind == .timingSplit }.count, 1)
            let pair = r.scan.rows.filter { $0.display == "Staraptor" && $0.cp == 1986 && $0.hp == 139 }
            XCTAssertEqual(pair.count, 2)
            XCTAssertEqual(pair.map(\.ivs), [IVs(atk: 15, def: 13, hp: 11), IVs(atk: 15, def: 13, hp: 11)])
            XCTAssertEqual(pair.map { $0.flags.contains("split-by-timing") }, [false, true])
            XCTAssertTrue(pair[1].flags.contains("same-as-previous"))
        }
        let byHand = try refine("device-run4-fast-swipe-2026-10-02.replay.jsonl", paging: PagingHint(pagedByCommand: false))
        XCTAssertEqual(byHand.scan.rows.count, 50, "the timing step is off when the player paged by hand")
        let pace = try XCTUnwrap(ScanPace.measure(rows: try refine("device-run4-fast-swipe-2026-10-02.replay.jsonl").scan.rows))
        XCTAssertEqual(pace.medianPeriod, 1.7, accuracy: 0.1)
        XCTAssertTrue(pace.isRegular)
    }

    func testTheHintedRuleAlsoWorksOnAStretchOfTheLog() throws {
        let r = try refine("device-run4-stretch.replay.jsonl", paging: PagingHint(pagedByCommand: true, expectedPeriod: 1.6))
        XCTAssertEqual(r.changes.filter { $0.kind == .timingSplit }.count, 1)
        XCTAssertEqual(r.scan.rows.filter { $0.display == "Staraptor" && $0.cp == 1986 && $0.hp == 139 }.count, 2)
        // with no hint the stretch alone is not steady enough over the scan as a whole (0.115 against 0.07): no timing split
        XCTAssertEqual(try refine("device-run4-stretch.replay.jsonl").changes.filter { $0.kind == .timingSplit }.count, 0)
    }

    /// The normal-pace run with two fainted Pokemon unread at the start: 49 rows, and the timing step adds nothing (its twin is
    /// split by the swipe evidence already).
    func testNormalPaceLogsAreUnchanged() throws {
        let run3 = try refine("device-run3-2026-10-02.replay.jsonl")
        XCTAssertEqual(run3.scan.rows.count, 49)
        XCTAssertEqual(run3.changes.filter { $0.kind == .timingSplit }.count, 0)
        let run1 = try refine("device-run-2026-10-02.replay.jsonl")
        XCTAssertEqual(run1.scan.rows.map { "\($0.display) \($0.cp)" }, DeviceRunTests.phone)
        XCTAssertEqual(run1.changes.filter { $0.kind == .timingSplit }.count, 0)
        // even told that it was command-paged, nothing new is split on either
        XCTAssertEqual(try refine("device-run-2026-10-02.replay.jsonl", paging: PagingHint()).scan.rows.count, 51)
        XCTAssertEqual(try refine("device-run3-2026-10-02.replay.jsonl", paging: PagingHint()).scan.rows.count, 49)
    }

    // MARK: real clips (opt-in)

    /// Hand-tapped and mixed clips gain no timing split with no hint, and the counts are what they were before the timing step.
    func testRealClipsGainNoTimingSplit() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["POGO_PARITY"] == "1", "set POGO_PARITY=1 to run the real-data checks")
        let dir = ProcessInfo.processInfo.environment["POGO_FRAMES_OUT"] ?? "/Users/greg-mb/Developer/personal/pogo-frames/_out"
        let expected: [(String, Int)] = [("marathon-phone", 47), ("marathon-ipad-mini", 46), ("v3", 109), ("pogo-test-fast", 21), ("darentas-01", 449), ("darentas-02", 771), ("darentas-03", 144), ("screenrec-2149", 578)]
        for (name, rows) in expected {
            let url = URL(fileURLWithPath: "\(dir)/\(name).swift.readings.json")
            guard FileManager.default.fileExists(atPath: url.path) else { print("TIMING \(name): SKIPPED"); continue }
            let l = try ReplayReadings.load(url: url)
            let base = try sharedEngine.finish(readings: l.readings)
            let r = try Refine.apply(to: base, readings: l.readings, ticks: l.ticks, engine: sharedEngine)
            let t = r.changes.filter { $0.kind == .timingSplit }.count
            print("TIMING \(name): base \(base.rows.count) refined \(r.scan.rows.count) timing splits \(t)")
            XCTAssertEqual(r.scan.rows.count, rows, name)
            XCTAssertEqual(t, 0, name)
        }
    }
}
