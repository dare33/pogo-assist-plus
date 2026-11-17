import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The report counts every time from the scan's first frame, whatever the stored log counts from (builds 1 to 4 stored device-start times).
/// That the stored scan on disk is untouched holds by construction: `ReportTimes.rebase` and the builder take values and return new ones, and never see a file.
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

    private func tmpFile(_ text: String, _ name: String) throws -> (URL, () -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-times-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent(name)
        try text.write(to: u, atomically: true, encoding: .utf8)
        return (u, { try? FileManager.default.removeItem(at: dir) })
    }
    private func micro(_ x: Double) -> Double { (x * 1e6).rounded() }
    /// The row with its frame times as whole microseconds after subtracting `shift`, so two rows can be compared in full.
    private func normalised(_ r: ScanRow, shift: Double) -> ScanRow { var r = r; r.frames = r.frames.map { var f = $0; f.time = f.time.map { micro($0 - shift) }; return f }; return r }
    private func normalised(_ e: ReviewEntry, shift: Double) -> ReviewEntry { var e = e; e.frames = e.frames.map { var f = $0; f.time = f.time.map { micro($0 - shift) }; return f }; return e }
    /// "at 12.3 s" and "12.3 s" times blanked: notices are not reported, and only their numbers may differ.
    private func blanked(_ s: String) -> String { s.replacingOccurrences(of: "[0-9]+\\.[0-9] s", with: "# s", options: .regularExpression) }

    /// The pipeline's whole outcome on a log and on the same log rebased must agree: only the times differ, by the shift.
    private func assertSameOutcome(_ fixture: String, hint: PagingHint?, expectPauses: Bool) throws {
        let log = try String(contentsOf: Fixture.url(fixture), encoding: .utf8)
        let rebased = ReportTimes.rebase(replayLog: log, result: ScanResult(rows: [], review: [], unmatched: []))
        XCTAssertGreaterThan(rebased.shift, 1000, "premise: \(fixture) is boot-based")
        let (second, clean) = try tmpFile(rebased.replayLog, "rebased.replay.jsonl"); defer { clean() }
        let engine = sharedEngine
        let a = try ScanPipeline.process(replay: Fixture.url(fixture), engine: engine, paging: hint), b = try ScanPipeline.process(replay: second, engine: engine, paging: hint)
        let shift = rebased.shift
        XCTAssertGreaterThan(a.scan.rows.count, 0)
        XCTAssertEqual(a.scan.rows.map { normalised($0, shift: shift) }, b.scan.rows.map { normalised($0, shift: 0) }, "every field of every row")
        XCTAssertEqual(a.scan.review.map { normalised($0, shift: shift) }, b.scan.review.map { normalised($0, shift: 0) }, "review entries")
        XCTAssertEqual(a.scan.unmatched, b.scan.unmatched)
        XCTAssertEqual(a.changes.map(\.kind), b.changes.map(\.kind)); XCTAssertEqual(a.changes.map(\.rowIndex), b.changes.map(\.rowIndex))
        XCTAssertEqual(a.changes.map { ReportTimes.barsChange($0.detail, shift: shift) }, b.changes.map(\.detail), "refine changes, the bars time compared after shifting")
        XCTAssertEqual(a.notices.map(blanked), b.notices.map(blanked))
        XCTAssertEqual(a.readings, b.readings); XCTAssertEqual(a.ticks, b.ticks); XCTAssertEqual(a.drops, b.drops)
        XCTAssertEqual(a.duration, b.duration, accuracy: 1e-6)
        // pace is a median of differences: equal up to the float noise of subtracting the origin first (about 1e-9 s)
        XCTAssertEqual(a.pace == nil, b.pace == nil)
        if let p = a.pace, let q = b.pace {
            XCTAssertEqual(p.medianPeriod, q.medianPeriod, accuracy: 1e-6); XCTAssertEqual(p.regularity, q.regularity, accuracy: 1e-6)
            XCTAssertEqual(p.isRegular, q.isRegular); XCTAssertEqual(p.periodsObserved, q.periodsObserved); XCTAssertEqual(p.staysMeasured, q.staysMeasured)
        }
        XCTAssertEqual(a.pauses.count, b.pauses.count)
        if expectPauses { XCTAssertFalse(a.pauses.isEmpty, "premise: the log has a pause") }
        for (x, y) in zip(a.pauses, b.pauses) {
            XCTAssertEqual(x.at - shift, y.at, accuracy: 1e-6); XCTAssertEqual(x.last - shift, y.last, accuracy: 1e-6)
            XCTAssertEqual(x.read, y.read); XCTAssertEqual(x.closed, y.closed)
            XCTAssertEqual(x.resumedAt.map { $0 - shift } == nil, y.resumedAt == nil)
            if let r = x.resumedAt, let r2 = y.resumedAt { XCTAssertEqual(r - shift, r2, accuracy: 1e-6) }
        }
    }

    func testReplayingTheLogAndTheRebasedLogGivesTheSameResult() throws {
        let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
        // pause and resume lines, with and without the command's hint
        try assertSameOutcome("run17-closed-stall.replay.jsonl", hint: nil, expectPauses: true)
        try assertSameOutcome("run17-closed-stall.replay.jsonl", hint: hint, expectPauses: true)
        // a bars split on the beat (its change text holds a time)
        try assertSameOutcome("run23-fidough-twin.replay.jsonl", hint: hint, expectPauses: false)
        try assertSameOutcome("run23-fidough-twin.replay.jsonl", hint: nil, expectPauses: false)
        // an end line, with and without the hint
        try assertSameOutcome("stall1-stunfisk-closed-tail.replay.jsonl", hint: hint, expectPauses: false)
        try assertSameOutcome("stall1-stunfisk-closed-tail.replay.jsonl", hint: nil, expectPauses: false)
        // the bundled sample (readings, ticks and drops only), and the live grouper over it
        let log = try sampleLog()
        let rebased = ReportTimes.rebase(replayLog: log, result: ScanResult(rows: [], review: [], unmatched: []))
        let (second, clean) = try tmpFile(rebased.replayLog, "rebased.replay.jsonl"); defer { clean() }
        let a = try ScanPipeline.process(replay: sampleURL, engine: sharedEngine), b = try ScanPipeline.process(replay: second, engine: sharedEngine)
        XCTAssertEqual(a.scan.rows.map { normalised($0, shift: rebased.shift) }, b.scan.rows.map { normalised($0, shift: 0) })
        let live = ReplayLog.replay(ReplayLog.lines(in: sampleURL), species: nil), liveRebased = ReplayLog.replay(ReplayLog.lines(in: second), species: nil)
        XCTAssertGreaterThan(live.rows.count, 40)
        XCTAssertEqual(live.rows.map { "\($0.name ?? "") \($0.cp ?? -1)" }, liveRebased.rows.map { "\($0.name ?? "") \($0.cp ?? -1)" })
    }

    /// The whole uploaded document, as text, from a boot-based log whose scan has a bars split: no number at or above the log's origin may appear anywhere,
    /// in a numeric field or inside a string (the bars-split text in `refineChanges` printed "at 119757.6 s" before this was rebased).
    func testNoBootBasedNumberAppearsAnywhereInTheUploadedText() throws {
        let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
        let fixture = "run23-fidough-twin.replay.jsonl"
        let log = try String(contentsOf: Fixture.url(fixture), encoding: .utf8)
        let outcome = try ScanPipeline.process(replay: Fixture.url(fixture), engine: sharedEngine, paging: hint)
        let changes = outcome.changes.map { "\($0.kind.rawValue): \($0.detail)" }
        let origin = try XCTUnwrap(try times(log).min())
        XCTAssertGreaterThan(origin, 100_000, "premise: boot-based, far above any CP, HP or dust")
        let bars = try XCTUnwrap(changes.first { $0.hasPrefix("barsSplit") }, "premise: the scan has a bars split")
        XCTAssertTrue(bars.contains("at 1197"), "premise: the stored text holds a boot-based time: \(bars)")

        let built = try ScanReportBuilder.build(ScanReportInput(replayLog: log, result: outcome.scan, kind: .full, scanDate: Date(timeIntervalSince1970: 1_790_000_000), pace: outcome.pace,
                                                               refineChanges: changes, review: [], app: app, device: device))
        let text = String(decoding: try Gzip.decompress(built.gzip), as: UTF8.self)
        let numbers = try NSRegularExpression(pattern: "[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?").matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { m in Range(m.range, in: text).flatMap { Double(text[$0]) } }
        XCTAssertGreaterThan(numbers.count, 1000, "the scan really was scanned")
        XCTAssertEqual(numbers.filter { $0 >= origin }, [], "a boot-based number is in the uploaded document")
        // the bars time is there, rebased: the same text with the cut time counted from the first frame
        let doc = try ScanReportBuilder.decode(gzip: built.gzip)
        let sent = try XCTUnwrap(doc.refineChanges.first { $0.hasPrefix("barsSplit") })
        XCTAssertNotEqual(sent, bars)
        let m = try XCTUnwrap(try NSRegularExpression(pattern: " at ([0-9]+\\.[0-9]) s").firstMatch(in: sent, range: NSRange(sent.startIndex..., in: sent)))
        let first = try XCTUnwrap(Range(m.range(at: 1), in: sent).flatMap { Double(sent[$0]) })
        XCTAssertLessThan(first, 100, "a cut time inside the scan, counted from its first frame")
        XCTAssertEqual(doc.refineChanges.count, changes.count)
    }

    func testOnlyTheBarsSplitTextHasItsTimeShiftedAndASecondPassChangesNothing() {
        let bars = "barsSplit: Fidough CP 768: bars change 15/4/10 to 15/11/12 at 119757.6 s, then 1/2/3 to 4/5/6 at 119760.1 s, each held by two or more readings: 2 Pokemon"
        XCTAssertEqual(ReportTimes.barsChange(bars, shift: 119735.0), "barsSplit: Fidough CP 768: bars change 15/4/10 to 15/11/12 at 22.6 s, then 1/2/3 to 4/5/6 at 25.1 s, each held by two or more readings: 2 Pokemon")
        let timing = "timingSplit: Fidough CP 768: stayed 14.0 s, 3 periods of 1.20 s plus a batch join"
        XCTAssertEqual(ReportTimes.barsChange(timing, shift: 5), timing, "a duration is not a time")
        let tail = "barsSplit: Fidough CP 768: bars change 1/2/3 to 4/5/6 at 10.0 s, each held by two or more readings: stayed at 99.0 s"
        XCTAssertTrue(ReportTimes.barsChange(tail, shift: 4).hasSuffix("stayed at 99.0 s"), "only the span between the cuts is touched")
        XCTAssertTrue(ReportTimes.barsChange(tail, shift: 4).contains("at 6.0 s,"))
        let log = "{\"k\":\"t\",\"t\":100}\n"
        let empty = ScanResult(rows: [], review: [], unmatched: [])
        let once = ReportTimes.rebase(replayLog: log, result: empty, refineChanges: ["barsSplit: X CP 1: bars change 1/2/3 to 4/5/6 at 104.0 s, each held by two or more readings: 2 Pokemon", timing])
        XCTAssertTrue(once.refineChanges[0].contains("at 4.0 s"))
        XCTAssertEqual(once.refineChanges[1], timing)
        let twice = ReportTimes.rebase(replayLog: once.replayLog, result: empty, refineChanges: once.refineChanges)
        XCTAssertEqual(twice.refineChanges, once.refineChanges)
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
