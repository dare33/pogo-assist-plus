import XCTest
@testable import PogoImport

/// The reader loop's decision about which batches to look at, as plain values.
final class ReadPlannerTests: XCTestCase {
    private func batch(_ id: String, pending: [String], account: String? = "Main") -> ImportManifest {
        let items = pending.map { ImportItem(id: $0, file: $0, sourceHash: $0, stagedHash: $0, width: 1, height: 1, state: .pending) }
            + [ImportItem(id: id + "-done", file: "d", sourceHash: id, stagedHash: id, width: 1, height: 1, state: .read)]
        return ImportManifest(batchId: id, createdAt: Date(timeIntervalSince1970: 1), origin: .photoPicker, account: account, items: items)
    }

    func testABatchIsOfferedOncePerWaitingSetSoAnUnfinishableBatchDoesNotSpin() {
        var p = ReadPlanner()
        let b = batch("a", pending: ["1", "2"])
        XCTAssertEqual(p.next(from: [b]), ["a"])
        XCTAssertEqual(p.next(from: [b]), [], "the same waiting set is not offered again")
    }

    /// The old loop kept a set of batches done for the life of the task and never offered one again.
    func testABatchMadeReadableAgainIsOfferedAgainInTheSameRun() {
        var p = ReadPlanner()
        XCTAssertEqual(p.next(from: [batch("a", pending: ["1"]), batch("b", pending: [])]), ["a"])
        // "b" was all copies of "a"'s; "a" was discarded; preparing turned b's screenshot back to pending
        XCTAssertEqual(p.next(from: [batch("b", pending: ["9"])]), ["b"])
        XCTAssertEqual(p.next(from: [batch("b", pending: ["9"])]), [])
    }

    func testAFinishedBatchIsNotACandidateButOneWithNoAccountYetIs() {
        var p = ReadPlanner()
        XCTAssertEqual(p.next(from: [batch("a", pending: [])]), [])
        XCTAssertEqual(p.next(from: [batch("n", pending: [], account: nil)]), ["n"])
    }

    func testARescanAskedForWhileBusyIsTakenOnce() {
        var p = ReadPlanner()
        XCTAssertFalse(p.takeRescan())
        p.requestRescan()
        XCTAssertTrue(p.takeRescan())
        XCTAssertFalse(p.takeRescan())
    }
}
