import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class BoxLibraryTests: XCTestCase {
    private var dir: URL!
    private var lib: BoxLibrary!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-lib-\(UUID().uuidString)")
        lib = BoxLibrary(root: dir)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func date(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 3600) }
    private func entries(_ cps: [Int]) -> [BoxEntry] {
        cps.enumerated().map { i, cp in
            BoxEntry(id: "e\(i)", row: ScanRow(index: i, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: cp, hp: 40, ivs: IVs(atk: 1, def: 2, hp: 3), ivsRead: nil,
                                              ivsGuess: nil, level: 5, levelMax: 5, dust: 200, solveStatus: "exact", flags: [], frames: []), firstSeen: date(0), lastSeen: date(0))
        }
    }

    func testAccountsAreMadeAndVersionsAccumulate() throws {
        XCTAssertEqual(try lib.accounts(), [])
        try lib.createAccount("Greg main")
        XCTAssertEqual(try lib.accounts(), ["Greg main"])
        XCTAssertNil(try lib.current(account: "Greg main"))
        let v1 = try lib.commit(account: "Greg main", entries: entries([100]), reason: .scan, note: "one", now: date(1))
        let v2 = try lib.commit(account: "Greg main", entries: entries([100, 200]), reason: .scan, note: "two", now: date(2))
        XCTAssertEqual([v1.seq, v2.seq], [1, 2])
        XCTAssertEqual(try lib.current(account: "Greg main")?.entries.count, 2)
        XCTAssertEqual(try lib.history(account: "Greg main").map { $0.seq }, [2, 1])
        XCTAssertEqual(try lib.load(account: "Greg main", seq: 1).entries.count, 1, "an earlier version is untouched")
    }

    func testRestorePreviousBringsBackTheEarlierBoxAsANewVersion() throws {
        _ = try lib.commit(account: "a", entries: entries([100]), reason: .scan, note: "one", now: date(1))
        _ = try lib.commit(account: "a", entries: entries([100, 200, 300]), reason: .scan, note: "two", now: date(2))
        XCTAssertEqual(try lib.previousVersion(account: "a")?.seq, 1)
        let r = try lib.restorePrevious(account: "a", now: date(3))
        XCTAssertEqual(r.seq, 3); XCTAssertEqual(r.reason, .restore); XCTAssertEqual(r.restoredFrom, 1)
        XCTAssertEqual(try lib.current(account: "a")?.entries.count, 1)
        XCTAssertEqual(try lib.load(account: "a", seq: 2).entries.count, 3, "the box that was undone is still there")
        // pressing it again goes back to what the restore replaced (the content of version 2)
        XCTAssertEqual(try lib.previousVersion(account: "a")?.seq, 2)
        XCTAssertEqual(try lib.restorePrevious(account: "a", now: date(3)).entries.count, 3)
        try lib.commit(account: "solo", entries: entries([1]), reason: .scan, note: "only", now: date(1))
        XCTAssertThrowsError(try lib.restorePrevious(account: "solo")) { XCTAssertEqual($0 as? BoxLibrary.Failure, .nothingToRestore) }
        // any version can be restored by number, which is how the undone one comes back
        XCTAssertEqual(try lib.restore(account: "a", seq: 2, now: date(4)).entries.count, 3)
        XCTAssertThrowsError(try lib.restore(account: "a", seq: 99)) { XCTAssertEqual($0 as? BoxLibrary.Failure, .noSuchVersion(99)) }
    }

    func testRestoreAfterAScanThatRemovedPokemon() throws {
        let gm = try GameMaster.bundled()
        let first = BoxMerge.plan(scanned: entries([100, 200]).map { $0.row }, into: [], kind: .full, scanDate: date(1), gameMaster: gm)
        let box1 = try BoxMerge.apply(first, to: [])
        try lib.commit(account: "a", entries: box1, reason: .scan, note: "first", now: date(1))
        // a full scan that sees only one of them proposes the other as gone; saving removes it ...
        let second = BoxMerge.plan(scanned: [box1[0].row], into: box1, kind: .full, scanDate: date(2), gameMaster: gm)
        XCTAssertEqual(second.gone, [box1[1].id])
        try lib.commit(account: "a", entries: try BoxMerge.apply(second, to: box1), reason: .scan, note: "second", now: date(2))
        XCTAssertEqual(try lib.current(account: "a")?.entries.count, 1)
        // ... and restoring brings it back with its id and dates
        let back = try lib.restorePrevious(account: "a", now: date(3))
        XCTAssertEqual(back.entries.map { $0.id }, box1.map { $0.id })
        XCTAssertEqual(back.entries[1].firstSeen, date(1))
    }

    func testAdviceIsCachedPerVersion() throws {
        try lib.commit(account: "a", entries: entries([100]), reason: .scan, note: "one", now: date(1))
        XCTAssertNil(lib.loadAdvice(account: "a", seq: 1))
        let advice = BoxAdvice(builds: [], gaps: [BoxAdvice.Gap(area: "Raids", section: nil, tier: "S", name: "X", obtain: nil, haveBase: false)], duplicates: [], unresolved: [])
        try lib.saveAdvice(advice, account: "a", seq: 1)
        XCTAssertEqual(lib.loadAdvice(account: "a", seq: 1), advice)
        XCTAssertNil(lib.loadAdvice(account: "a", seq: 2))
        XCTAssertEqual(try lib.history(account: "a").count, 1, "the advice file is not a version")
    }

    func testReplayLogIsKeptBesideTheScanAndAScanFileWithoutOneStillLoads() throws {
        let store = lib.store
        let result = ScanResult(rows: [], review: [], unmatched: [])
        let log = Data("{\"k\":\"t\",\"t\":1}\n".utf8)
        let s = try store.save(result, account: "a", source: "broadcast", kind: .partial, storageCount: 120, replayLog: log)
        XCTAssertEqual(try store.replayLog(account: "a", id: s.id), log)
        XCTAssertEqual(try store.load(account: "a", id: s.id).storageCount, 120)
        XCTAssertEqual(try store.list(account: "a").scans.count, 1, "the log is not listed as a scan")
        let bare = try store.save(result, account: "a", source: "x")
        XCTAssertNil(try store.replayLog(account: "a", id: bare.id))
        try store.delete(account: "a", id: s.id)
        XCTAssertNil(try store.replayLog(account: "a", id: s.id))
    }
}
