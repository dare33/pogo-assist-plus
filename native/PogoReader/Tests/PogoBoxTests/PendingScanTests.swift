import Foundation
import XCTest
@testable import PogoBox

final class PendingScanTests: XCTestCase {
    private var dir: URL!
    private var shared: URL!
    private var store: PendingScanStore!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-pending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        shared = dir.appendingPathComponent("replay.jsonl")
        store = PendingScanStore(directory: dir.appendingPathComponent("pending-scan"))
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    /// A shared log of `text` and its signature in the app's form: "<size>-<stamp>".
    private func log(_ text: String, stamp: Int = 1) throws -> String {
        try Data(text.utf8).write(to: shared)
        return "\(text.utf8.count)-\(stamp)"
    }
    private func meta(_ sig: String, account: String = "A") -> PendingScanMeta { PendingScanMeta(signature: sig, account: account, kind: .partial, scanDate: Date(timeIntervalSince1970: 1_790_000_000), doneFirst: true) }

    func testACopyIsKeptWithItsMetaAndLoadsAgain() throws {
        let sig = try log("{\"k\":\"t\"}\n")
        guard case .copied(let url) = store.take(from: shared, meta: meta(sig), currentSignature: { sig }) else { return XCTFail() }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{\"k\":\"t\"}\n")
        guard case .ready(let m, let copy) = store.load() else { return XCTFail() }
        XCTAssertEqual(m.signature, sig); XCTAssertEqual(m.kind, .partial); XCTAssertTrue(m.doneFirst); XCTAssertEqual(m.scanDate, Date(timeIntervalSince1970: 1_790_000_000)); XCTAssertEqual(copy, url)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["pending-scan", "replay.jsonl"], "no temporary folder is left")
    }

    func testALogRewrittenWhileCopyingIsNotCopied() throws {
        let sig = try log("aaaa")
        var calls = 0
        // the signature changes between the first look and the second: the shared log was rewritten during the read
        XCTAssertEqual(store.take(from: shared, meta: meta(sig), currentSignature: { calls += 1; return calls == 1 ? sig : "9-2" }), .replaced)
        XCTAssertEqual(store.take(from: shared, meta: meta("5-1"), currentSignature: { "5-1" }), .replaced, "the bytes must be as long as the signature says")
        XCTAssertEqual(store.load(), .none)
    }

    func testAWaitingScanIsNeverOverwrittenByALaterOne() throws {
        let first = try log("first")
        _ = store.take(from: shared, meta: meta(first), currentSignature: { first })
        let second = try log("second log", stamp: 2)
        XCTAssertEqual(store.take(from: shared, meta: meta(second), currentSignature: { second }), .occupied)
        guard case .ready(let m, let copy) = store.load() else { return XCTFail() }
        XCTAssertEqual(m.signature, first); XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "first")
        // the same scan again is the copy already kept
        try Data("first".utf8).write(to: shared)
        if case .copied = store.take(from: shared, meta: meta(first), currentSignature: { first }) {} else { XCTFail() }
        // clearing names a signature: another scan's clear does nothing
        store.clear(ifSignature: second)
        if case .ready = store.load() {} else { XCTFail("a clear for another scan removed it") }
        store.clear(ifSignature: first)
        XCTAssertEqual(store.load(), .none)
    }

    func testADamagedMetaKeepsTheLogAndIsReportedNotDeleted() throws {
        let sig = try log("some log")
        _ = store.take(from: shared, meta: meta(sig), currentSignature: { sig })
        try Data("{ not json".utf8).write(to: store.directory.appendingPathComponent("meta.json"))
        guard case .damaged = store.load() else { return XCTFail() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("replay.jsonl").path), "the log is still there")
        XCTAssertEqual(store.take(from: shared, meta: meta(sig), currentSignature: { sig }), .occupied, "a damaged one is not written over either")
        store.clear()   // the person's Discard
        XCTAssertEqual(store.load(), .none)
    }

    func testAMetaFromAnotherBuildStillLoads() throws {
        let sig = try log("some log")
        _ = store.take(from: shared, meta: meta(sig), currentSignature: { sig })
        // a newer build added a field and an older one lacked kind, attempts and the rest: both read
        let json = "{\"signature\":\"\(sig)\",\"account\":\"A\",\"futureField\":{\"x\":1}}"
        try Data(json.utf8).write(to: store.directory.appendingPathComponent("meta.json"))
        guard case .ready(let m, _) = store.load() else { return XCTFail() }
        XCTAssertEqual(m.kind, .full); XCTAssertEqual(m.attempts, 0); XCTAssertNil(m.scanDate); XCTAssertFalse(m.doneFirst); XCTAssertNil(m.state)
        // a field of the wrong type does not lose the scan either
        let odd = "{\"signature\":\"\(sig)\",\"account\":\"A\",\"attempts\":\"two\",\"kind\":\"weird\"}"
        try Data(odd.utf8).write(to: store.directory.appendingPathComponent("meta.json"))
        guard case .ready(let m2, _) = store.load() else { return XCTFail() }
        XCTAssertEqual(m2.attempts, 0); XCTAssertEqual(m2.kind, .full)
    }

    func testAttemptsAndTheAccountCanBeUpdatedInPlace() throws {
        let sig = try log("some log")
        _ = store.take(from: shared, meta: meta(sig), currentSignature: { sig })
        try store.update { $0.attempts += 1; $0.account = "B"; $0.doneFirst = false }
        guard case .ready(let m, _) = store.load() else { return XCTFail() }
        XCTAssertEqual(m.attempts, 1); XCTAssertEqual(m.account, "B"); XCTAssertFalse(m.doneFirst); XCTAssertEqual(m.signature, sig)
        store.clear()
        XCTAssertThrowsError(try store.update { $0.attempts = 0 })
    }

    func testALogOfAnotherLengthThanItsSignatureIsDamaged() throws {
        let sig = try log("some log")
        _ = store.take(from: shared, meta: meta(sig), currentSignature: { sig })
        try Data("short".utf8).write(to: store.directory.appendingPathComponent("replay.jsonl"))
        guard case .damaged = store.load() else { return XCTFail() }
    }
}
