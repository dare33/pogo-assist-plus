import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// The files the app shares count their times from the scan's first frame. The shifting itself is tested in the package (`ShareTimesTests`); these tests check it on the
/// app's own file shapes (`BroadcastState`, `DeferredResult`) and the temporary files `ShareFiles` writes.
final class ShareFilesTests: XCTestCase {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("share-files-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }
    private func liveRow(_ i: Int, _ first: Double?, _ last: Double?) throws -> LiveRow {
        var o: [String: Any] = ["index": i, "name": "Fidough", "cp": 768, "hp": 80, "frames": 4, "flags": ["check"], "firstFrame": "r\(i)", "lastFrame": "r\(i + 3)"]
        if let first { o["firstTime"] = first }; if let last { o["lastTime"] = last }
        return try JSONDecoder().decode(LiveRow.self, from: JSONSerialization.data(withJSONObject: o))
    }
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    func testTheStateFileAndTheSavedCropResultKeepEveryFieldButTheFrameTimes() throws {
        var state = BroadcastState()
        state.rows = [try liveRow(1, 119_757.5, 119_760.1), try liveRow(2, nil, 119_800)]
        state.framesRead = 640; state.commandPeriod = 1.2; state.pauseLimitSeconds = 90; state.scanId = 1_795_000_000
        state.started = Date(timeIntervalSince1970: 1_795_000_000); state.updated = Date(timeIntervalSince1970: 1_795_000_420); state.pausedAt = Date(timeIntervalSince1970: 1_795_000_100)
        state.cpCoveredSince = Date(timeIntervalSince1970: 1_795_000_200); state.finished = true
        let deferred = DeferredResult(rows: [try liveRow(1, 119_750.25, 119_751)], frames: 12, seconds: 3.5, peakFootprintMB: 20.25)
        let log = "{\"k\":\"t\",\"t\":119760}\n{\"k\":\"t\",\"t\":119761.2}\n"

        let r = ShareTimes.diagnostics(state: try encoder.encode(state), deferred: try JSONEncoder().encode(deferred), replayLog: Data(log.utf8))
        XCTAssertEqual(r.unreadable, [])
        XCTAssertEqual(r.shift, 119_750.25, accuracy: 1e-6)
        let s = try decoder.decode(BroadcastState.self, from: XCTUnwrap(r.state))
        var expected = state
        expected.rows = [try liveRow(1, 7.25, 9.85), try liveRow(2, nil, 49.75)]
        XCTAssertEqual(s.rows.map(\.firstTime), expected.rows.map(\.firstTime))
        XCTAssertEqual(s.rows.compactMap(\.lastTime).map { ($0 * 100).rounded() }, expected.rows.compactMap(\.lastTime).map { ($0 * 100).rounded() })
        var sameRest = s; sameRest.rows = state.rows
        XCTAssertEqual(sameRest, state, "every field other than the rows' times is as it was")
        let d = try JSONDecoder().decode(DeferredResult.self, from: XCTUnwrap(r.deferred))
        XCTAssertEqual(d.rows.first?.firstTime ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(d.rows.first?.lastTime ?? -1, 0.75, accuracy: 1e-9)
        XCTAssertEqual(d.seconds, 3.5); XCTAssertEqual(d.frames, 12); XCTAssertEqual(d.peakFootprintMB, 20.25)
    }

    func testASavedScanIsWrittenToTheTemporaryFolderShiftedAndAnUnreadableResultIsLeftOut() throws {
        let replay = try XCTUnwrap(Bundle.main.url(forResource: "sample-scan", withExtension: "replay.jsonl"), "the bundled sample log")
        let root = tempDir(), tmp = tempDir()
        let store = BoxStore(root: root)
        let outcome = try ScanPipeline.process(replay: replay, engine: CoreEngine())
        let summary = try store.save(outcome.scan, account: "T", source: "broadcast", replayLog: Data(contentsOf: replay), refineChanges: [])
        let files = try store.files(account: "T", id: summary.id)

        let ok = try XCTUnwrap(ShareFiles.savedScan(store: store, account: "T", id: summary.id, into: tmp))
        XCTAssertNil(ok.message)
        XCTAssertEqual(ok.urls.map(\.lastPathComponent), ["\(summary.id).result.json", "\(summary.id).replay.jsonl"])
        let shared = try decoder.decode(BoxStore.StoredScan.self, from: Data(contentsOf: ok.urls[0]))
        XCTAssertLessThan(try XCTUnwrap(shared.rows.flatMap(\.frames).compactMap(\.time).max()), 400)
        XCTAssertLessThan(try XCTUnwrap(String(contentsOf: ok.urls[1], encoding: .utf8).split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["t"] as? Double }.max()), 400)
        XCTAssertGreaterThan(try XCTUnwrap(try decoder.decode(BoxStore.StoredScan.self, from: Data(contentsOf: files.result)).rows.flatMap(\.frames).compactMap(\.time).max()), 400, "the stored file is untouched")

        // a damaged result file: not shared as it is, the log still is, and the person is told
        try Data("{ damaged".utf8).write(to: files.result)
        let bad = try XCTUnwrap(ShareFiles.savedScan(store: store, account: "T", id: summary.id, into: tmp))
        XCTAssertEqual(bad.urls.map(\.lastPathComponent), ["\(summary.id).replay.jsonl"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("\(summary.id).result.json").path), "no earlier copy is left")
        XCTAssertEqual(bad.message, "The scan's results could not be read, so they were left out.")
        XCTAssertNil(ShareFiles.savedScan(store: store, account: "T", id: "no-such-scan", into: tmp))

        // the review's own log
        let review = ShareFiles.reviewLog(replay, into: tmp)
        XCTAssertEqual(review.urls.count, 1); XCTAssertNil(review.message)
        XCTAssertTrue(try String(contentsOf: review.urls[0], encoding: .utf8).hasPrefix("{"))
        XCTAssertNotNil(ShareFiles.reviewLog(tmp.appendingPathComponent("missing.jsonl"), into: tmp).message)
    }
}
