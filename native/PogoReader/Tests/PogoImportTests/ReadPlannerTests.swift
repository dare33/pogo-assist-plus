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
        XCTAssertEqual(p.next(from: [b]), ["a"], "offering alone records nothing: a batch the reader never got to is still waiting")
        p.markTried(b)
        XCTAssertEqual(p.next(from: [b]), [], "the same waiting set is not offered again once it was dealt with")
    }

    /// The old loop kept a set of batches done for the life of the task and never offered one again.
    func testABatchMadeReadableAgainIsOfferedAgainInTheSameRun() {
        var p = ReadPlanner()
        let a = batch("a", pending: ["1"])
        XCTAssertEqual(p.next(from: [a, batch("b", pending: [])]), ["a"]); p.markTried(a)
        // "b" was all copies of "a"'s; "a" was discarded; preparing turned b's screenshot back to pending
        let b = batch("b", pending: ["9"])
        XCTAssertEqual(p.next(from: [b]), ["b"]); p.markTried(b)
        XCTAssertEqual(p.next(from: [b]), [])
    }

    func testAFinishedBatchIsNotACandidateButOneWithNoAccountYetIs() {
        var p = ReadPlanner()
        XCTAssertEqual(p.next(from: [batch("a", pending: [])]), [])
        XCTAssertEqual(p.next(from: [batch("n", pending: [], account: nil)]), ["n"])
    }

    /// The reviewer's case: b is offered, its copies get marked read, then are reset to pending with the SAME ids when a is discarded.
    func testACopyBatchResetToTheSameIdsIsOfferedAgain() {
        var p = ReadPlanner()
        let b0 = batch("b", pending: ["9"])
        XCTAssertEqual(p.next(from: [b0]), ["b"])
        p.markTried(b0)
        XCTAssertEqual(p.next(from: [b0]), [], "not twice for the same waiting set")
        let finished = batch("b", pending: [])   // its copies marked read: not waiting
        XCTAssertEqual(p.next(from: [finished]), [])
        XCTAssertEqual(p.next(from: [batch("b", pending: ["9"])]), ["b"], "the same ids waiting again are a new wait")
    }

    func testARescanForgetsWhatWasTried() {
        var p = ReadPlanner()
        let b = batch("b", pending: ["9"])
        _ = p.next(from: [b]); p.markTried(b)
        p.requestRescan()
        XCTAssertEqual(p.next(from: [b]), ["b"])
    }

    /// A batch the reader never got to (it stopped first) is not marked as tried.
    func testBatchesAfterAStopAreStillOffered() {
        var p = ReadPlanner()
        let a = batch("a", pending: ["1"]), c = batch("c", pending: ["2"])
        XCTAssertEqual(p.next(from: [a, c]), ["a", "c"])
        p.markTried(a)   // the reader stopped at a
        XCTAssertEqual(p.next(from: [a, c]), ["c"])
    }

    func testAPartlyReadBatchIsOfferedAgainBecauseItsWaitingSetChanged() {
        var p = ReadPlanner()
        let first = batch("a", pending: ["1", "2"]); p.markTried(first)
        XCTAssertEqual(p.next(from: [batch("a", pending: ["2"])]), ["a"])
    }

    func testARescanAskedForWhileBusyIsTakenOnce() {
        var p = ReadPlanner()
        XCTAssertFalse(p.takeRescan())
        p.requestRescan()
        XCTAssertTrue(p.takeRescan())
        XCTAssertFalse(p.takeRescan())
    }
}
