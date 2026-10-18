import Foundation
import XCTest
@testable import PogoBox

/// A rename killed at every point it can be killed at: a fresh start (a new `BoxStore` on the same folder, as after a relaunch) must leave the account either wholly under its old
/// name or wholly under the new one, with no leftovers, every version intact and the waiting scan following.
final class RenameJournalTests: XCTestCase {
    private var dir: URL!
    private var pendingDir: URL!
    private var pending: PendingScanStore!
    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-journal-\(UUID().uuidString)")
        dir = base.appendingPathComponent("boxes"); pendingDir = base.appendingPathComponent("pending-scan")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pending = PendingScanStore(directory: pendingDir)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

    private func seed(_ lib: BoxLibrary, _ name: String) throws {
        let entry = BoxEntry(id: "e1", row: ScanRow(index: 1, name: "Pidgey", display: "Pidgey", form: "", speciesId: "pidgey", dex: 16, cp: 100, hp: 30, ivs: nil, ivsRead: nil, ivsGuess: nil,
                                                    level: 5, levelMax: 5, dust: 200, solveStatus: "exact", flags: [], frames: []), firstSeen: Date(timeIntervalSince1970: 1_790_000_000), lastSeen: Date(timeIntervalSince1970: 1_790_000_000))
        let scan = try lib.store.save(ScanResult(rows: [entry.row], review: [], unmatched: []), account: name, source: "broadcast", replayLog: Data("{\"k\":\"t\",\"t\":1}\n".utf8))
        _ = try lib.commit(account: name, entries: [entry], reason: .scan, note: "x", scanId: scan.id)
        _ = try lib.commit(account: name, entries: [entry, entry], reason: .edit, note: "y")
        let shared = dir.deletingLastPathComponent().appendingPathComponent("replay.jsonl")
        try Data("abcd".utf8).write(to: shared)
        _ = pending.take(from: shared, meta: PendingScanMeta(signature: "4-1", account: name), currentSignature: { "4-1" })
    }

    private func check(_ lib: BoxLibrary, expecting names: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        let accounts = try lib.accounts()
        XCTAssertEqual(accounts.count, 1, "\(accounts)", file: file, line: line)
        let name = try XCTUnwrap(accounts.first, file: file, line: line)
        XCTAssertTrue(names.contains(name), "\(name) is neither \(names)", file: file, line: line)
        let folder = dir.appendingPathComponent(name)
        XCTAssertEqual(try lib.current(account: name)?.entries.count, 2, "versions intact", file: file, line: line)
        XCTAssertEqual(try lib.history(account: name).count, 2, file: file, line: line)
        for h in try lib.history(account: name) { XCTAssertEqual(try lib.load(account: name, seq: h.seq).account, name, "record names its account", file: file, line: line) }
        for scan in try lib.store.list(account: name).scans { XCTAssertEqual(try lib.store.load(account: name, id: scan.id).account, name, file: file, line: line) }
        let all = try FileManager.default.contentsOfDirectory(atPath: folder.path) + FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("box").path)
        XCTAssertFalse(all.contains { $0.contains(".renaming") }, "\(all)", file: file, line: line)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".rename-") && $0 != ".rename-history.json" && $0 != ".rename-journal.json" }, [], "no temporary folder", file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".rename-journal.json").path), "journal deleted", file: file, line: line)
        guard case .ready(let meta, _) = pending.load() else { return XCTFail("the waiting scan is gone", file: file, line: line) }
        XCTAssertEqual(meta.account, name, "the waiting scan follows the account", file: file, line: line)
    }

    private let points = ["journal", "staged", "retargeted", "moving", "caseTemp", "moved", "swap1", "swapped"]

    func testARenameKilledAtAnyPointIsFinishedOrUndoneByTheNextLoad() throws {
        for caseOnly in [false, true] {
            for point in points {
                try? FileManager.default.removeItem(at: dir); try? FileManager.default.removeItem(at: pendingDir)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let old = "Parents", new = caseOnly ? "PARENTS" : "darentas"
                let lib = BoxLibrary(root: dir)
                try seed(lib, old)
                lib.store.renameKill = point
                var killed = false
                do { try lib.renameAccount(from: old, to: new, pending: pending) } catch { killed = true }
                if !killed && (point == "caseTemp") && !caseOnly { continue }   // a plain rename has no temporary folder
                XCTAssertTrue(killed || point == "caseTemp", "\(point) did not stop the rename")
                // the relaunch: a new store on the same folder, recovery on startup
                let fresh = BoxLibrary(root: dir)
                _ = try fresh.recoverInterruptedRename(pending: pending)
                try check(fresh, expecting: [old, new])
                // a second recovery has nothing to do, and the account can be renamed again
                XCTAssertFalse(try fresh.recoverInterruptedRename(pending: pending))
                let final = try XCTUnwrap(try fresh.accounts().first)
                try fresh.renameAccount(from: final, to: final == new ? "Third" : new, pending: pending)
                try check(fresh, expecting: ["Third", new])
            }
        }
    }

    func testARenameKilledAfterTheFolderMovedIsFinishedNotUndone() throws {
        let lib = BoxLibrary(root: dir)
        try seed(lib, "Parents")
        lib.store.renameKill = "swap1"
        XCTAssertThrowsError(try lib.renameAccount(from: "Parents", to: "darentas", pending: pending))
        _ = try BoxLibrary(root: dir).recoverInterruptedRename(pending: pending)
        XCTAssertEqual(try lib.accounts(), ["darentas"])
        XCTAssertEqual(try lib.store.accountNamed("Parents"), "darentas", "the old name is followed to the new one")
    }

    func testARenameKilledBeforeTheFolderMovedIsUndone() throws {
        let lib = BoxLibrary(root: dir)
        try seed(lib, "Parents")
        lib.store.renameKill = "moving"
        XCTAssertThrowsError(try lib.renameAccount(from: "Parents", to: "darentas", pending: pending))
        guard case .ready(let during, _) = pending.load() else { return XCTFail() }
        XCTAssertEqual(during.account, "darentas", "the waiting scan had been retargeted before the folder was to move")
        _ = try BoxLibrary(root: dir).recoverInterruptedRename(pending: pending)
        XCTAssertEqual(try lib.accounts(), ["Parents"])
        guard case .ready(let after, _) = pending.load() else { return XCTFail() }
        XCTAssertEqual(after.account, "Parents", "and is pointed back at the account that still exists")
        XCTAssertEqual(try lib.store.accountNamed("Parents"), "Parents")
        XCTAssertNil(try lib.store.accountNamed("darentas"))
    }

    func testARecordedNameIsFollowedThroughSeveralRenamesAndGoneWhenNoneLeadsToAnAccount() throws {
        let lib = BoxLibrary(root: dir)
        try seed(lib, "A")
        try lib.renameAccount(from: "A", to: "B")
        try lib.renameAccount(from: "B", to: "C")
        XCTAssertEqual(try lib.store.accountNamed("A"), "C")
        XCTAssertEqual(try lib.store.accountNamed("C"), "C")
        XCTAssertNil(try lib.store.accountNamed("Nobody"))
        try lib.store.deleteAccount("C")
        XCTAssertNil(try lib.store.accountNamed("A"), "renamed and then removed: gone")
    }

    func testTheJournalAndItsHistoryAreNeverListedAsAccounts() throws {
        let lib = BoxLibrary(root: dir)
        try seed(lib, "A")
        try lib.renameAccount(from: "A", to: "B")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".rename-history.json").path))
        XCTAssertEqual(try lib.accounts(), ["B"])
    }
}
