import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The whole path the app takes after a broadcast, without the extension: replay file -> rows -> merge into an empty box ->
/// save -> reload, then the advisor and the CSV on what was saved.
final class ScanPipelineTests: XCTestCase {
    /// The owner's own device log, kept once as the app's sample scan.
    private var sample: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PogoAssist/PogoAssist/Resources/sample-scan.replay.jsonl")
    }

    func testReplayToSavedBoxAndBack() throws {
        let engine = CoreEngine()
        let out = try ScanPipeline.process(replay: sample, engine: engine)
        print("TIMING sample scan: \(out.timings), \(out.scan.rows.count) rows")
        XCTAssertGreaterThan(out.scan.rows.count, 40)
        XCTAssertGreaterThan(out.readings, 300)
        XCTAssertGreaterThan(out.duration, 30)
        XCTAssertEqual(out.scan.rows.count, out.scan.review.count + out.scan.rows.filter { $0.flags.isEmpty }.count)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-pipe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = BoxLibrary(root: dir)
        let log = try Data(contentsOf: sample)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let plan = BoxMerge.plan(scanned: out.scan.rows, into: [], kind: .full, scanDate: date, gameMaster: try .bundled())
        XCTAssertEqual(plan.new.count, out.scan.rows.count)
        let entries = try BoxMerge.apply(plan, to: [])
        let scan = try lib.store.save(out.scan, account: "Test", scanDate: date, source: "broadcast", kind: .full, storageCount: 51, replayLog: log)
        let snap = try lib.commit(account: "Test", entries: entries, reason: .scan, note: "Full scan", scanId: scan.id, scanKind: .full, scanDate: date, now: date)

        let reloaded = try XCTUnwrap(lib.current(account: "Test"))
        XCTAssertEqual(reloaded, snap)
        XCTAssertEqual(reloaded.entries.count, out.scan.rows.count)
        XCTAssertTrue(reloaded.entries.allSatisfy { $0.row.frames.isEmpty })
        XCTAssertEqual(try lib.store.replayLog(account: "Test", id: scan.id), log)

        // the same scan again changes nothing: every Pokémon is Same
        let again = BoxMerge.plan(scanned: out.scan.rows, into: reloaded.entries, kind: .full, scanDate: date.addingTimeInterval(86_400), gameMaster: try .bundled())
        XCTAssertEqual(again.same.count + again.unsure.count + again.updated.count + again.new.count, out.scan.rows.count)
        XCTAssertTrue(again.gone.isEmpty && again.new.isEmpty, "gone \(again.gone.count) new \(again.new.count) unsure \(again.unsure.count)")

        // the advisor and the CSV on the saved box, with each build tied back to an entry
        let rows = reloaded.entries.enumerated().map { i, e -> ScanRow in var r = e.row; r.index = i + 1; return r }
        let report = try engine.advise(rows: rows, scanDate: date)
        let advice = BoxAdvice.make(from: report, entries: reloaded.entries)
        XCTAssertFalse(advice.builds.isEmpty)
        XCTAssertTrue(advice.builds.allSatisfy { b in reloaded.entries.contains { $0.id == b.entryId } })
        XCTAssertFalse(advice.gaps.isEmpty)
        let first = try XCTUnwrap(advice.builds.first)
        XCTAssertFalse(advice.entries(for: first.entryId).builds.isEmpty)
        XCTAssertTrue(try engine.csv(rows: rows, scanDate: date).hasPrefix("Index,Name"))
    }

    func testAnEmptyLogIsAPlainError() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).jsonl")
        try Data("{\"k\":\"d\",\"t\":1}\n".utf8).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        XCTAssertThrowsError(try ScanPipeline.process(replay: f, engine: CoreEngine())) { XCTAssertTrue($0 is ScanPipeline.Failure || $0 is ReplayReadings.Failure) }
    }
}
