import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The report counts every time from the scan's first frame, whatever the stored log counts from (builds 1 to 4 stored device-start times).
final class ReportTimesTests: XCTestCase {
    private var sampleURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PogoAssist/PogoAssist/Resources/sample-scan.replay.jsonl")
    }
    private let app = ScanReport.AppInfo(version: "0.1", build: "7")
    private let device = ScanReport.DeviceInfo(model: "iPhone17,2", os: "26.5", screenWidth: 440, screenHeight: 956, locale: "en_AU")

    private func lines(_ text: String) throws -> [[String: Any]] {
        try text.split(separator: "\n").map { try XCTUnwrap(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    }
    /// Every frame time in a log (`t`, and `last` where a line has it).
    private func times(_ text: String) throws -> [Double] {
        try lines(text).flatMap { o in ["t", "last"].compactMap { (o[$0] as? NSNumber)?.doubleValue } }
    }
    private func input(log: String, result: ScanResult) -> ScanReportInput {
        ScanReportInput(replayLog: log, result: result, kind: .full, scanDate: Date(timeIntervalSince1970: 1_790_000_000), app: app, device: device)
    }
    private func sampleLog() throws -> String { try String(contentsOf: sampleURL, encoding: .utf8) }
    private func sampleResult() throws -> ScanResult { try ScanPipeline.process(replay: sampleURL, engine: CoreEngine()).scan }

    func testTheSampleLogIsBootBasedAndTheReportOfItStartsAtZeroWithEveryDifferenceKept() throws {
        let log = try sampleLog(), result = try sampleResult()
        let before = try times(log)
        XCTAssertGreaterThan(try XCTUnwrap(before.min()), 400, "the premise: the bundled log counts from device start")
        XCTAssertTrue(result.rows.flatMap(\.frames).contains { ($0.time ?? 0) > 400 }, "and so do the result's frame times")

        let built = try ScanReportBuilder.build(input(log: log, result: result))
        let doc = try ScanReportBuilder.decode(gzip: built.gzip)
        let after = try times(doc.replayLog)
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(try XCTUnwrap(after.min()), 0, accuracy: 1e-9)
        let origin = try XCTUnwrap(before.min())
        for (a, b) in zip(after, before) { XCTAssertEqual(a, b - origin, accuracy: 2e-9, "every difference is kept") }
        XCTAssertLessThan(try XCTUnwrap(after.max()), 400, "nothing boot-based is left in the log")
        // the line kinds, readings, ticks and drops, are all still there with their other fields
        let kinds = Set(try lines(doc.replayLog).compactMap { $0["k"] as? String })
        XCTAssertEqual(kinds, Set(try lines(log).compactMap { $0["k"] as? String }))
        XCTAssertEqual(try lines(doc.replayLog).count, try lines(log).count)

        // the result's frame times, in rows and review entries, shift by the same amount
        let frames = doc.result.rows.flatMap(\.frames).compactMap(\.time) + doc.result.review.flatMap(\.frames).compactMap(\.time)
        XCTAssertFalse(frames.isEmpty)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames.min()), -1e-9)
        XCTAssertLessThan(try XCTUnwrap(frames.max()), 400)
        let originalFrames = result.rows.flatMap(\.frames).compactMap(\.time)
        for (a, b) in zip(doc.result.rows.flatMap(\.frames).compactMap(\.time), originalFrames) { XCTAssertEqual(a, b - origin, accuracy: 2e-9) }
        // the row facts do not change
        XCTAssertEqual(doc.result.rows.map { "\($0.speciesId) \($0.cp)" }, result.rows.map { "\($0.speciesId) \($0.cp)" })
    }

    func testRebasingTwiceChangesNothing() throws {
        let log = try sampleLog(), result = try sampleResult()
        let once = ReportTimes.rebase(replayLog: log, result: result)
        XCTAssertNotEqual(once.replayLog, log, "the first pass does change this log")
        XCTAssertGreaterThan(once.shift, 400)
        let twice = ReportTimes.rebase(replayLog: once.replayLog, result: once.result)
        XCTAssertEqual(twice.shift, 0)
        XCTAssertEqual(twice.replayLog, once.replayLog)
        XCTAssertEqual(twice.result, once.result)
        // a log that is already scan-relative (the new extension's) is returned byte for byte, odd spacing and all
        let fresh = "{\"k\":\"t\", \"t\":0}\n{\"t\":1.5,\"k\":\"d\"}\n"
        XCTAssertEqual(ReportTimes.rebase(replayLog: fresh, result: ScanResult(rows: [], review: [], unmatched: [])).replayLog, fresh)
        // and the report built from either is the same document
        let a = try ScanReportBuilder.build(input(log: log, result: result)), b = try ScanReportBuilder.build(input(log: once.replayLog, result: once.result))
        XCTAssertEqual(a.contentHash, b.contentHash)
    }

    func testTheStoredInputIsNotChanged() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-times-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let stored = dir.appendingPathComponent("replay.jsonl")
        try FileManager.default.copyItem(at: sampleURL, to: stored)
        let bytes = try Data(contentsOf: stored)
        let log = try String(contentsOf: stored, encoding: .utf8), result = try sampleResult()
        let resultCopy = result
        let built = try ScanReportBuilder.build(input(log: log, result: result))
        XCTAssertGreaterThan(built.jsonBytes, 0)
        XCTAssertEqual(try Data(contentsOf: stored), bytes, "the stored log on disk is byte for byte what it was")
        XCTAssertEqual(log, try String(contentsOf: sampleURL, encoding: .utf8))
        XCTAssertEqual(result, resultCopy, "the input result is a value and is unchanged")
        XCTAssertEqual(ReportTimes.rebase(replayLog: log, result: result).shift, try XCTUnwrap(try times(log).min()), "the shift really was applied to the copy")
    }

    func testReplayingTheLogAndTheRebasedLogGivesTheSameRows() throws {
        let log = try sampleLog()
        let rebased = ReportTimes.rebase(replayLog: log, result: ScanResult(rows: [], review: [], unmatched: []))
        XCTAssertGreaterThan(rebased.shift, 400)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-times-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let second = dir.appendingPathComponent("rebased.replay.jsonl")
        try rebased.replayLog.write(to: second, atomically: true, encoding: .utf8)

        func shape(_ r: ScanResult) -> [String] { r.rows.map { "\($0.index) \($0.speciesId) \($0.cp) \($0.hp ?? -1) \($0.solveStatus) \($0.flags.joined(separator: ",")) \($0.frames.count)" } }
        let engine = CoreEngine()
        for hint in [nil, PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: 0.8)] {
            let a = try ScanPipeline.process(replay: sampleURL, engine: engine, paging: hint), b = try ScanPipeline.process(replay: second, engine: engine, paging: hint)
            XCTAssertGreaterThan(a.scan.rows.count, 40)
            XCTAssertEqual(shape(a.scan), shape(b.scan), "rows, hint \(String(describing: hint))")
            XCTAssertEqual(a.scan.review.count, b.scan.review.count); XCTAssertEqual(a.scan.unmatched.count, b.scan.unmatched.count)
            XCTAssertEqual(a.readings, b.readings); XCTAssertEqual(a.ticks, b.ticks); XCTAssertEqual(a.drops, b.drops)
            XCTAssertEqual(a.duration, b.duration, accuracy: 1e-6)
        }
        // the live grouper too
        let live = ReplayLog.replay(ReplayLog.lines(in: sampleURL), species: nil), liveRebased = ReplayLog.replay(ReplayLog.lines(in: second), species: nil)
        XCTAssertGreaterThan(live.rows.count, 40)
        XCTAssertEqual(live.rows.map { "\($0.name ?? "") \($0.cp ?? -1)" }, liveRebased.rows.map { "\($0.name ?? "") \($0.cp ?? -1)" })
    }

    func testEndPauseAndOtherLineKindsAllShiftAndUnreadableLinesAreLeftOutAndSaid() throws {
        let log = """
        {"k":"r","t":1000.5,"cpText":"","nameText":"","hpText":"","flags":[],"ivConfidence":0,"ms":3.5}
        {"k":"c","t":1001,"first":"A"}
        {"k":"p","t":1002,"last":1001.5,"read":3,"closed":true}
        {"k":"u","t":1003}
        {"k":"s","t":1004}
        {"k":"o","t":1005}
        {"k":"e","t":1006.25,"last":1004}
        {"k":"zz","t":1007,"last":1006,"x":5}
        {"k":"t","t":10
        """
        let r = ReportTimes.rebase(replayLog: log, result: ScanResult(rows: [], review: [], unmatched: []))
        XCTAssertEqual(r.droppedLines, 1)
        XCTAssertEqual(r.shift, 1000.5)
        let out = try lines(r.replayLog)
        XCTAssertEqual(out.map { ($0["t"] as! NSNumber).doubleValue }, [0, 0.5, 1.5, 2.5, 3.5, 4.5, 5.75, 6.5])
        XCTAssertEqual(out[2]["last"] as? Double, 1)          // pause: last
        XCTAssertEqual(out[6]["last"] as? Double, 3.5)        // end: last
        XCTAssertEqual(out[7]["last"] as? Double, 5.5)        // an unknown kind is shifted too
        XCTAssertEqual(out[2]["read"] as? Int, 3); XCTAssertEqual(out[0]["ms"] as? Double, 3.5); XCTAssertEqual(out[7]["x"] as? Int, 5)
        // and the report says a line was left out
        let doc = ScanReportBuilder.report(input(log: log, result: ScanResult(rows: [], review: [], unmatched: [])))
        XCTAssertTrue(doc.notIncluded.contains { $0.contains("1 replay log line") })
    }

    func testAScanWithNoLogStillStartsItsResultAtZero() throws {
        let result = try sampleResult()
        let doc = ScanReportBuilder.report(input(log: "", result: result))
        let frames = doc.result.rows.flatMap(\.frames).compactMap(\.time)
        XCTAssertEqual(try XCTUnwrap(frames.min()), 0, accuracy: 1e-9)
        XCTAssertEqual(doc.replayLog, "")
    }
}
