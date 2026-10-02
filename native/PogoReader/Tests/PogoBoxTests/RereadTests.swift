import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class RereadTests: XCTestCase {
    private var dir: URL!
    private var lib: BoxLibrary!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-reread-\(UUID().uuidString)")
        lib = BoxLibrary(root: dir)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func date(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 3600) }
    private func entry(_ id: String, cp: Int) -> BoxEntry {
        BoxEntry(id: id, row: ScanRow(index: 1, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: cp, hp: 40, ivs: IVs(atk: cp % 16, def: 1, hp: 2), ivsRead: nil,
                                      ivsGuess: nil, level: 5, levelMax: 5, dust: 200, solveStatus: "exact", flags: [], frames: []), firstSeen: date(0), lastSeen: date(0))
    }
    /// Save a scan (with a replay log) and the box version it makes.
    @discardableResult
    private func saveScan(_ account: String, _ entries: [BoxEntry], at n: Int, log: Bool = true, kind: BoxStore.Kind = .full, paging: StoredPaging? = nil) throws -> (scan: String, seq: Int) {
        let s = try lib.store.save(ScanResult(rows: entries.map { $0.row }, review: [], unmatched: []), account: account, scanDate: date(n), source: "broadcast", kind: kind,
                                   replayLog: log ? Data("{\"k\":\"t\",\"t\":1}\n".utf8) : nil, paging: paging)
        let v = try lib.commit(account: account, entries: entries, reason: .scan, note: "scan \(n)", scanId: s.id, scanKind: kind, scanDate: date(n), now: date(n))
        return (s.id, v.seq)
    }

    func testRereadOfTheLatestScanIsAgainstTheBoxBeforeIt() throws {
        let a = entry("a", cp: 100), b = entry("b", cp: 200)
        let one = try saveScan("x", [a], at: 1)
        let two = try saveScan("x", [a, b], at: 2, paging: StoredPaging(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: 0.8))
        let plan = try lib.prepareReread(account: "x", scanId: two.scan)
        XCTAssertEqual(plan.baseSeq, one.seq); XCTAssertEqual(plan.baseEntries.map { $0.id }, ["a"]); XCTAssertEqual(plan.scanSeq, two.seq)
        XCTAssertEqual([plan.laterScans, plan.laterEdits], [0, 0]); XCTAssertFalse(plan.hasLaterChanges)
        XCTAssertEqual(plan.paging, PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: 0.8))
        XCTAssertEqual(plan.scan.kind, .full)
        XCTAssertNil(plan.scan.lastReread)
        // saving: a new version built from the earlier box plus the new read; the history only grows
        let merged = try BoxMerge.apply(BoxMerge.plan(scanned: [a.row, b.row], into: plan.baseEntries, kind: .full, scanDate: plan.scan.scanDate, gameMaster: try .bundled()), to: plan.baseEntries)
        let snap = try lib.commitReread(plan, entries: merged, account: "x", now: date(9))
        XCTAssertEqual(snap.seq, 3); XCTAssertEqual(snap.scanId, two.scan); XCTAssertEqual(try lib.current(account: "x")?.entries.count, 2)
        XCTAssertEqual(try lib.history(account: "x").map { $0.seq }, [3, 2, 1])
        XCTAssertEqual(try lib.store.load(account: "x", id: two.scan).lastReread, date(9))
    }

    func testRereadOfAnEarlierScanWithLaterChangesSaysSoAndKeepsTheHistory() throws {
        let a = entry("a", cp: 100), b = entry("b", cp: 200)
        let one = try saveScan("x", [a], at: 1)
        let two = try saveScan("x", [a, b], at: 2)
        let edit = try lib.commit(account: "x", entries: [a, b], reason: .edit, note: "corrected", now: date(3))
        // the first scan: no box before it; one later scan and one later correction
        let p1 = try lib.prepareReread(account: "x", scanId: one.scan)
        XCTAssertNil(p1.baseSeq); XCTAssertTrue(p1.baseEntries.isEmpty); XCTAssertEqual([p1.laterScans, p1.laterEdits], [1, 1]); XCTAssertTrue(p1.hasLaterChanges)
        // the second: the box is the first scan's version; only the correction is later
        let p2 = try lib.prepareReread(account: "x", scanId: two.scan)
        XCTAssertEqual(p2.baseSeq, one.seq); XCTAssertEqual(p2.baseEntries.map { $0.id }, ["a"]); XCTAssertEqual([p2.laterScans, p2.laterEdits], [0, 1])
        // save the first scan's re-read: the current box becomes that version, the old versions are all still there and restorable
        let snap = try lib.commitReread(p1, entries: [a], account: "x", now: date(10))
        XCTAssertEqual(snap.seq, edit.seq + 1); XCTAssertEqual(try lib.current(account: "x")?.entries.map { $0.id }, ["a"])
        XCTAssertEqual(try lib.history(account: "x").count, 4)
        XCTAssertEqual(try lib.restore(account: "x", seq: two.seq, now: date(11)).entries.map { $0.id }, ["a", "b"], "restore still works afterwards")
        XCTAssertEqual(try lib.load(account: "x", seq: edit.seq).entries.count, 2)
        // reading the first scan again still points at the box before its first version, and the re-read version is not "a later scan"
        let again = try lib.prepareReread(account: "x", scanId: one.scan)
        XCTAssertEqual(again.scanSeq, one.seq); XCTAssertNil(again.baseSeq); XCTAssertEqual(again.laterScans, 1)
    }

    func testRestorePreviousStillWorksAfterAReread() throws {
        let a = entry("a", cp: 100), b = entry("b", cp: 200)
        _ = try saveScan("x", [a], at: 1)
        let two = try saveScan("x", [a, b], at: 2)
        let plan = try lib.prepareReread(account: "x", scanId: two.scan)
        try lib.commitReread(plan, entries: [a, b, entry("c", cp: 300)], account: "x", now: date(5))
        let back = try lib.restorePrevious(account: "x", now: date(6))
        XCTAssertEqual(back.reason, .restore)
        XCTAssertEqual(try lib.current(account: "x")?.entries.count, back.entries.count)
    }

    func testAScanWithoutALogCannotBeReadAgain() throws {
        let s = try saveScan("x", [entry("a", cp: 100)], at: 1, log: false)
        XCTAssertThrowsError(try lib.prepareReread(account: "x", scanId: s.scan)) { XCTAssertEqual($0 as? BoxLibrary.RereadFailure, .noReplayLog) }
        XCTAssertThrowsError(try lib.prepareReread(account: "x", scanId: "scan-nope")) 
    }

    /// Through the real pipeline: the sample scan saved, then read again against the empty box before it.
    func testTheSampleScanReadAgainGivesTheSameBox() throws {
        let sample = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PogoAssist/PogoAssist/Resources/sample-scan.replay.jsonl")
        let engine = CoreEngine(), gm = try GameMaster.bundled()
        let first = try ScanPipeline.process(replay: sample, engine: engine)
        let entries = try BoxMerge.apply(BoxMerge.plan(scanned: first.scan.rows, into: [], kind: .full, scanDate: date(1), gameMaster: gm), to: [], makeID: { UUID().uuidString })
        let s = try lib.store.save(first.scan, account: "x", scanDate: date(1), source: "broadcast", kind: .full, replayLog: try Data(contentsOf: sample), paging: StoredPaging(pagedByCommand: false))
        try lib.commit(account: "x", entries: entries, reason: .scan, note: "scan", scanId: s.id, scanKind: .full, scanDate: date(1), now: date(1))
        let plan = try lib.prepareReread(account: "x", scanId: s.id)
        XCTAssertTrue(plan.baseEntries.isEmpty)
        let second = try ScanPipeline.process(replay: plan.replayURL, engine: engine, paging: plan.paging)
        let p = BoxMerge.plan(scanned: second.scan.rows, into: plan.baseEntries, kind: plan.scan.kind, scanDate: plan.scan.scanDate, gameMaster: gm)
        XCTAssertEqual(p.new.count, second.scan.rows.count); XCTAssertEqual(second.scan.rows.count, first.scan.rows.count)
        let snap = try lib.commitReread(plan, entries: try BoxMerge.apply(p, to: plan.baseEntries), account: "x", now: date(2))
        XCTAssertEqual(snap.entries.count, 51)
        XCTAssertNotNil(try lib.store.load(account: "x", id: s.id).lastReread)
    }
}
