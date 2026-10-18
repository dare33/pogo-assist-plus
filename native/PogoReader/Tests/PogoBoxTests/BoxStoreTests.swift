import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class BoxStoreTests: XCTestCase {
    private var dir: URL!
    private var store: BoxStore!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-box-\(UUID().uuidString)")
        store = BoxStore(root: dir)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func result() throws -> ScanResult { try Fixture.expected() }
    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400) }

    func testSaveAndLoadRoundTrip() throws {
        let r = try result()
        let s = try store.save(r, account: "Greg main", scanDate: date(0), source: "replay marathon-phone.json")
        XCTAssertEqual(s.rows, 6)
        XCTAssertEqual(s.flagged, 1)
        let back = try store.load(account: "Greg main", id: s.id)
        XCTAssertEqual(back.rows, r.rows)
        XCTAssertEqual(back.review, r.review)
        XCTAssertEqual(back.unmatched, r.unmatched)
        XCTAssertEqual(back.scanDate, date(0))
        XCTAssertEqual(back.source, "replay marathon-phone.json")
        XCTAssertEqual(back.kind, .full)
        XCTAssertEqual(try store.accounts(), ["Greg main"])
    }

    func testCurrentBoxIsTheLatestFullScan() throws {
        let r = try result()
        var smaller = r; smaller.rows = Array(r.rows.prefix(2))
        let old = try store.save(r, account: "a", scanDate: date(0), source: "x")
        let newer = try store.save(smaller, account: "a", scanDate: date(5), source: "y")
        _ = try store.save(smaller, account: "a", scanDate: date(9), source: "partial run", kind: .partial)
        XCTAssertEqual(try store.currentBox(account: "a")?.id, newer.id)
        let listing = try store.list(account: "a")
        XCTAssertEqual(listing.scans.count, 3)
        XCTAssertEqual(listing.scans.map(\.scanDate), [date(9), date(5), date(0)])
        XCTAssertTrue(listing.scans.contains { $0.id == old.id })
        XCTAssertNil(try store.currentBox(account: "nobody"))
        XCTAssertEqual(try store.list(account: "nobody"), BoxStore.Listing(scans: [], unreadable: []))
    }

    func testAccountsAreSeparate() throws {
        _ = try store.save(try result(), account: "one", source: "x")
        _ = try store.save(try result(), account: "two", source: "x")
        XCTAssertEqual(try store.list(account: "one").scans.count, 1)
        XCTAssertEqual(try store.accounts(), ["one", "two"])
        try store.deleteAccount("one")
        XCTAssertEqual(try store.accounts(), ["two"])
    }

    func testAccountNameCannotEscapeTheRoot() throws {
        let s = try store.save(try result(), account: "../../evil", source: "x")
        XCTAssertEqual(try store.accounts(), ["../../evil"])
        XCTAssertEqual(try store.load(account: "../../evil", id: s.id).rows.count, 6)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.deletingLastPathComponent().appendingPathComponent("evil").path))
        XCTAssertThrowsError(try store.save(try result(), account: "  ", source: "x")) { XCTAssertEqual($0 as? BoxStore.Failure, .badAccountName) }
        XCTAssertThrowsError(try store.load(account: "../../evil", id: "../../../etc/passwd")) // a path id stays inside the account directory: not found
    }

    func testCorruptedFileIsReportedNotFatal() throws {
        let r = try result()
        let good = try store.save(r, account: "a", scanDate: date(0), source: "x")
        let bad = try store.save(r, account: "a", scanDate: date(3), source: "x")
        let badFile = dir.appendingPathComponent("a").appendingPathComponent("\(bad.id).json")
        // truncate it mid-file, as a crash during a non-atomic write would
        let whole = try Data(contentsOf: badFile)
        try whole.prefix(whole.count / 2).write(to: badFile)
        XCTAssertThrowsError(try store.load(account: "a", id: bad.id)) {
            guard case BoxStore.Failure.corrupt(let file, _) = $0 else { return XCTFail("wrong error \($0)") }
            XCTAssertEqual(file, "\(bad.id).json")
        }
        let listing = try store.list(account: "a")
        XCTAssertEqual(listing.scans.map(\.id), [good.id])
        XCTAssertEqual(listing.unreadable, ["\(bad.id).json"])
        XCTAssertEqual(try store.currentBox(account: "a")?.id, good.id, "falls back to the newest readable full scan; list() says what was skipped")
        // garbage and an empty file
        try Data("hello".utf8).write(to: badFile)
        XCTAssertThrowsError(try store.load(account: "a", id: bad.id))
        try Data().write(to: badFile)
        XCTAssertThrowsError(try store.load(account: "a", id: bad.id))
        // a file from a newer app version is unreadable, not misread
        var newer = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("a").appendingPathComponent("\(good.id).json"))) as! [String: Any]
        newer["schema"] = 99
        try JSONSerialization.data(withJSONObject: newer).write(to: badFile)
        XCTAssertThrowsError(try store.load(account: "a", id: bad.id)) { XCTAssertTrue("\($0)".contains("newer")) }
    }

    func testNoTemporaryFilesAreLeftBehind() throws {
        let s = try store.save(try result(), account: "a", source: "x")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("a").path), ["\(s.id).json"])
    }

    func testDelete() throws {
        let s = try store.save(try result(), account: "a", source: "x")
        try store.delete(account: "a", id: s.id)
        XCTAssertEqual(try store.list(account: "a").scans.count, 0)
        XCTAssertThrowsError(try store.delete(account: "a", id: s.id)) { XCTAssertEqual($0 as? BoxStore.Failure, .notFound(account: "a", id: s.id)) }
        XCTAssertThrowsError(try store.load(account: "a", id: s.id))
    }

    func testExportCSVMatchesTheEngine() throws {
        let s = try store.save(try result(), account: "a", scanDate: date(0), source: "x")
        let scan = try store.load(account: "a", id: s.id)
        let csv = try store.exportCSV(scan, using: sharedEngine)
        XCTAssertEqual(csv, try sharedEngine.csv(rows: scan.rows, scanDate: date(0)))
        let out = dir.appendingPathComponent("box.csv")
        try store.exportCSV(scan, using: sharedEngine, to: out)
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), csv)
    }

    func testStoredFileHoldsOnlyTheInventory() throws {
        let s = try store.save(try result(), account: "a", source: "x")
        let text = try String(contentsOf: dir.appendingPathComponent("a/\(s.id).json"), encoding: .utf8)
        XCTAssertFalse(text.contains(NSHomeDirectory()))
    }

    func testMergeIncrementalIsAStub() throws {
        let s = try store.save(try result(), account: "a", source: "x")
        XCTAssertThrowsError(try store.mergeIncremental(into: store.load(account: "a", id: s.id), with: try result())) {
            guard case BoxStore.Failure.notImplemented = $0 else { return XCTFail("wrong error \($0)") }
        }
    }
}
