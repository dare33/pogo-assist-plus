import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// What a person shares out of the app counts its times from the scan's first frame, whatever the stored files count from (builds 1 to 4 stored device-start
/// times). The stored files are untouched: `ShareTimes` takes bytes and returns bytes, and the test below reads the stored files again after it ran.
final class ShareTimesTests: XCTestCase {
    private let fixture = "run23-fidough-twin.replay.jsonl"
    private let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)

    private func lines(_ text: String) throws -> [[String: Any]] {
        try text.split(separator: "\n").map { try XCTUnwrap(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
    }
    private func logTimes(_ text: String) throws -> [Double] {
        try lines(text).flatMap { o in ["t", "last"].compactMap { (o[$0] as? NSNumber)?.doubleValue } }
    }
    private func numbers(in text: String) throws -> [Double] {
        try NSRegularExpression(pattern: "[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?").matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { m in Range(m.range, in: text).flatMap { Double(text[$0]) } }
    }
    private func decoded(_ data: Data) throws -> BoxStore.StoredScan {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try d.decode(BoxStore.StoredScan.self, from: data)
    }
    private func frameTimes(_ s: BoxStore.StoredScan) -> [Double] { (s.rows.flatMap(\.frames) + s.review.flatMap(\.frames)).compactMap(\.time) }

    /// A scan stored the way the app stores it (BoxStore.save), from a boot-timed device log; returns the two files' bytes.
    private func stored(_ name: String = "run23-fidough-twin.replay.jsonl", paging: PagingHint? = nil, refine: Bool = true) throws -> (result: Data, log: Data, root: URL, resultURL: URL, logURL: URL) {
        let url = try Fixture.url(name)
        let outcome = try ScanPipeline.process(replay: url, engine: sharedEngine, paging: paging)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("share-times-\(UUID().uuidString)", isDirectory: true)
        let store = BoxStore(root: root)
        let changes = outcome.changes.map { "\($0.kind.rawValue): \($0.detail)" }
        let summary = try store.save(outcome.scan, account: "T", source: "broadcast", replayLog: Data(contentsOf: url), refineChanges: refine ? changes : nil)
        let files = try store.files(account: "T", id: summary.id)
        return (try Data(contentsOf: files.result), try Data(contentsOf: XCTUnwrap(files.replay)), root, files.result, try XCTUnwrap(files.replay))
    }

    func testNoBootBasedNumberRemainsAnywhereInASharedBootTimedScan() throws {
        let s = try stored(paging: hint)
        defer { try? FileManager.default.removeItem(at: s.root) }
        let before = try decoded(s.result)
        let origin = try XCTUnwrap(try logTimes(String(decoding: s.log, as: UTF8.self)).min())
        XCTAssertGreaterThan(origin, 100_000, "premise: boot-based, far above any CP, HP or dust")
        let bars = try XCTUnwrap(before.refineChanges?.first { $0.hasPrefix("barsSplit") }, "premise: the scan has a bars split")
        XCTAssertTrue(bars.contains("at 1197"), "premise: the stored text holds a boot-based time: \(bars)")
        XCTAssertTrue(try numbers(in: String(decoding: s.result, as: UTF8.self)).contains { $0 >= origin }, "premise: the stored result holds boot times")

        let shared = ShareTimes.savedScan(result: s.result, replayLog: s.log)
        XCTAssertEqual(shared.unreadable, [])
        XCTAssertEqual(shared.droppedLines, 0)
        XCTAssertEqual(shared.shift, origin, accuracy: 1e-6)
        let resultText = String(decoding: try XCTUnwrap(shared.result), as: UTF8.self), logText = try XCTUnwrap(shared.replayLog)
        // the scan's id is its save time (digits of today's date, not a frame time), so it is taken out of the text first
        let all = try numbers(in: resultText.replacingOccurrences(of: before.id, with: "")) + numbers(in: logText)
        XCTAssertGreaterThan(all.count, 1000, "the scan really was scanned")
        XCTAssertEqual(all.filter { $0 >= origin }, [], "a boot-based number is in what is shared")
        // the bars time is there, counted from the first frame
        let after = try decoded(XCTUnwrap(shared.result))
        let sent = try XCTUnwrap(after.refineChanges?.first { $0.hasPrefix("barsSplit") })
        XCTAssertNotEqual(sent, bars)
        let m = try XCTUnwrap(try NSRegularExpression(pattern: " at ([0-9]+\\.[0-9]) s").firstMatch(in: sent, range: NSRange(sent.startIndex..., in: sent)))
        XCTAssertLessThan(try XCTUnwrap(Range(m.range(at: 1), in: sent).flatMap { Double(sent[$0]) }), 100)
        XCTAssertEqual(after.refineChanges?.count, before.refineChanges?.count)

        // every other field is as stored: rows without their frame times, the dates, the review answers, the paging, the hash
        func plain(_ x: BoxStore.StoredScan) -> BoxStore.StoredScan {
            var y = x; y.refineChanges = nil
            for i in y.rows.indices { y.rows[i].frames = y.rows[i].frames.map { var f = $0; f.time = nil; return f } }
            for i in y.review.indices { y.review[i].frames = y.review[i].frames.map { var f = $0; f.time = nil; return f } }
            return y
        }
        XCTAssertEqual(plain(after), plain(before))
        XCTAssertEqual(zip(frameTimes(after), frameTimes(before)).map { $0 - $1 + origin }.map { abs($0) }.max() ?? 0, 0, accuracy: 2e-9, "every difference is kept")
        // the stored files are not touched
        XCTAssertEqual(try Data(contentsOf: s.resultURL), s.result)
        XCTAssertEqual(try Data(contentsOf: s.logURL), s.log)
        // the log keeps every line kind and its other fields
        XCTAssertEqual(try lines(logText).count, try lines(String(decoding: s.log, as: UTF8.self)).count)
        XCTAssertEqual(try lines(logText).map { $0["k"] as? String }, try lines(String(decoding: s.log, as: UTF8.self)).map { $0["k"] as? String })
    }

    func testTheResultAndTheLogShareOneOrigin() throws {
        let s = try stored()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let before = try decoded(s.result)
        let logBefore = try logTimes(String(decoding: s.log, as: UTF8.self)), resultBefore = frameTimes(before)
        let shared = ShareTimes.savedScan(result: s.result, replayLog: s.log)
        let logAfter = try logTimes(XCTUnwrap(shared.replayLog)), resultAfter = frameTimes(try decoded(XCTUnwrap(shared.result)))
        let earliest = min(try XCTUnwrap(logBefore.min()), try XCTUnwrap(resultBefore.min()))
        XCTAssertEqual(shared.shift, earliest, accuracy: 1e-6)
        XCTAssertEqual(min(try XCTUnwrap(logAfter.min()), try XCTUnwrap(resultAfter.min())), 0, accuracy: 1e-9)
        // a time that is in both the log and the result is the same number in both after the shift
        let common = Set(logBefore).intersection(resultBefore)
        XCTAssertFalse(common.isEmpty, "premise: a result frame time is a log time")
        let afterLog = Set(logAfter.map { ($0 * 1e6).rounded() }), afterResult = Set(resultAfter.map { ($0 * 1e6).rounded() })
        for t in common.prefix(50) { XCTAssertTrue(afterLog.contains(((t - shared.shift) * 1e6).rounded()) && afterResult.contains(((t - shared.shift) * 1e6).rounded())) }
    }

    func testSharingWhatIsAlreadySharedChangesNothingAndAScanFromZeroComesOutAsStored() throws {
        let s = try stored(paging: hint)
        defer { try? FileManager.default.removeItem(at: s.root) }
        let once = ShareTimes.savedScan(result: s.result, replayLog: s.log)
        let twice = ShareTimes.savedScan(result: try XCTUnwrap(once.result), replayLog: once.replayLog.map { Data($0.utf8) })
        XCTAssertEqual(twice.shift, 0)
        XCTAssertEqual(twice.result, once.result, "the same bytes")
        XCTAssertEqual(twice.replayLog, once.replayLog)
        XCTAssertEqual(twice.droppedLines, 0)
        // shift 0: the bytes that came in, the log text as written
        let zeroLog = "{\"k\":\"t\",\"t\":0}\n{\"k\":\"t\",\"t\":1.25}\n"
        let zero = ShareTimes.savedScan(result: try XCTUnwrap(once.result), replayLog: Data(zeroLog.utf8))
        XCTAssertEqual(zero.result, once.result)
        XCTAssertEqual(zero.replayLog, zeroLog)
        let alone = try XCTUnwrap(ShareTimes.replayLog(Data(zeroLog.utf8)))
        XCTAssertEqual(alone.text, zeroLog); XCTAssertEqual(alone.shift, 0)
        // the result with no log: its own earliest frame is 0
        let noLog = ShareTimes.savedScan(result: s.result, replayLog: nil)
        XCTAssertNil(noLog.replayLog)
        XCTAssertEqual(try XCTUnwrap(frameTimes(try decoded(XCTUnwrap(noLog.result))).min()), 0, accuracy: 1e-9)
    }

    func testAScanWithNoRefineChangesKeepsNone() throws {
        let s = try stored(refine: false)
        defer { try? FileManager.default.removeItem(at: s.root) }
        XCTAssertNil(try decoded(s.result).refineChanges)
        XCTAssertNil(try decoded(XCTUnwrap(ShareTimes.savedScan(result: s.result, replayLog: s.log).result)).refineChanges)
    }

    func testAFileThatCannotBeReadIsNotSharedAndIsNamed() throws {
        let s = try stored()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let junk = ShareTimes.savedScan(result: Data("not json at all 119757.6".utf8), replayLog: s.log)
        XCTAssertNil(junk.result); XCTAssertEqual(junk.unreadable, [.result])
        XCTAssertNotNil(junk.replayLog, "the log is still shared, on its own origin")
        XCTAssertGreaterThan(try XCTUnwrap(try logTimes(XCTUnwrap(junk.replayLog)).min()), -1e-9)
        XCTAssertEqual(try XCTUnwrap(try logTimes(XCTUnwrap(junk.replayLog)).min()), 0, accuracy: 1e-9)

        var newer = try decoded(s.result); newer.schema = BoxStore.schemaVersion + 1
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let future = ShareTimes.savedScan(result: try e.encode(newer), replayLog: nil)
        XCTAssertNil(future.result); XCTAssertEqual(future.unreadable, [.result], "a newer file's unknown fields cannot be shifted, so it is not shared")

        let truncated = ShareTimes.savedScan(result: s.result.prefix(s.result.count / 2), replayLog: nil)
        XCTAssertNil(truncated.result); XCTAssertEqual(truncated.unreadable, [.result])

        let badLog = ShareTimes.savedScan(result: s.result, replayLog: Data([0xFF, 0xFE, 0x7B, 0x7D]))
        XCTAssertNil(badLog.replayLog); XCTAssertEqual(badLog.unreadable, [.replayLog])
        XCTAssertNotNil(badLog.result)
        XCTAssertNil(ShareTimes.replayLog(Data([0xFF, 0xFE])))

        let withHalfLine = ShareTimes.savedScan(result: s.result, replayLog: s.log + Data("{\"k\":\"t\",\"t\":1197".utf8))
        XCTAssertEqual(withHalfLine.droppedLines, 1)
        XCTAssertEqual(try lines(XCTUnwrap(withHalfLine.replayLog)).count, try lines(String(decoding: s.log, as: UTF8.self)).count)
    }

    // MARK: - diagnostics

    private func json(_ o: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) }
    private func row(_ index: Int, first: Double?, last: Double?) -> [String: Any] {
        var r: [String: Any] = ["index": index, "name": "Fidough", "cp": 768, "hp": 80, "frames": 4, "flags": [String](), "ivs": ["atk": 15, "def": 4, "hp": 10],
                                "firstFrame": "r\(index)", "lastFrame": "r\(index + 3)"]
        r["firstTime"] = first.map { $0 as Any } ?? NSNull(); r["lastTime"] = last.map { $0 as Any } ?? NSNull()
        return r
    }
    private func stateJSON(rows: [[String: Any]]) throws -> Data {
        try json(["rows": rows, "framesRead": 640, "framesDropped": 2, "meanMsPerFrame": 31.5, "started": "2026-11-20T01:02:03Z", "updated": "2026-11-20T01:09:03Z", "pausedAt": "2026-11-20T01:05:00Z",
                  "cpCoveredSince": "2026-11-20T01:06:00Z", "scanId": 1_795_000_000, "commandPeriod": 1.2, "pauseLimitSeconds": 90.0, "replayLines": 700, "finished": true, "mode": "fast"])
    }
    private func sampleLog() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PogoAssist/PogoAssist/Resources/sample-scan.replay.jsonl"), encoding: .utf8)
    }
    private func rowTimes(_ d: Data) throws -> [Double] {
        let o = try XCTUnwrap(try JSONSerialization.jsonObject(with: d) as? [String: Any])
        return ((o["rows"] as? [[String: Any]]) ?? []).flatMap { r in ["firstTime", "lastTime"].compactMap { (r[$0] as? NSNumber)?.doubleValue } }
    }

    func testTheStateAndSavedCropFilesShiftWithTheLogByOneOrigin() throws {
        let log = try sampleLog()
        let logMin = try XCTUnwrap(try logTimes(log).min())
        XCTAssertGreaterThan(logMin, 400, "premise: the bundled log is boot-based")
        // state rows inside the log's span, and a saved-crop row that starts EARLIER than the log: the origin is the earliest of all three
        let state = try stateJSON(rows: [row(1, first: logMin + 1.5, last: logMin + 3.1), row(2, first: nil, last: logMin + 9)])
        let deferred = try json(["rows": [row(1, first: logMin - 2.0, last: logMin + 4)], "frames": 12, "seconds": 3.5, "peakFootprintMB": 20.25])
        let r = ShareTimes.diagnostics(state: state, deferred: deferred, replayLog: Data(log.utf8))
        XCTAssertEqual(r.unreadable, [])
        XCTAssertEqual(r.shift, logMin - 2.0, accuracy: 1e-6)
        XCTAssertEqual(try rowTimes(XCTUnwrap(r.deferred)), [0, 6.0].map { $0 }, accuracy: 2e-9)
        XCTAssertEqual(try rowTimes(XCTUnwrap(r.state)), [3.5, 5.1, 11.0], accuracy: 2e-9)
        XCTAssertEqual(try XCTUnwrap(try logTimes(XCTUnwrap(r.replayLog)).min()), 2.0, accuracy: 2e-9, "the log's own first line is 2 s after the saved-crop row's")
        // every other field is as it was
        func rest(_ d: Data) throws -> [String: Any] {
            var o = try XCTUnwrap(try JSONSerialization.jsonObject(with: d) as? [String: Any])
            o["rows"] = ((o["rows"] as? [[String: Any]]) ?? []).map { var x = $0; x["firstTime"] = nil; x["lastTime"] = nil; return x }
            return o
        }
        XCTAssertEqual(NSDictionary(dictionary: try rest(XCTUnwrap(r.state))), NSDictionary(dictionary: try rest(state)))
        XCTAssertEqual(NSDictionary(dictionary: try rest(XCTUnwrap(r.deferred))), NSDictionary(dictionary: try rest(deferred)))
        let stateOut = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(r.state)) as? [String: Any])
        XCTAssertEqual(stateOut["scanId"] as? Int, 1_795_000_000); XCTAssertEqual(stateOut["started"] as? String, "2026-11-20T01:02:03Z")
        XCTAssertTrue((stateOut["rows"] as? [[String: Any]])?[1]["firstTime"] is NSNull, "a row with no time keeps none")
        // no boot-based number is left in any of the three
        let allTimes = try rowTimes(XCTUnwrap(r.state)) + rowTimes(XCTUnwrap(r.deferred)) + logTimes(XCTUnwrap(r.replayLog))
        XCTAssertLessThan(try XCTUnwrap(allTimes.max()), 400, "no boot-based time is left in any of the three")

        // again: nothing changes
        let again = ShareTimes.diagnostics(state: r.state, deferred: r.deferred, replayLog: r.replayLog.map { Data($0.utf8) })
        XCTAssertEqual(again.shift, 0)
        XCTAssertEqual(again.state, r.state); XCTAssertEqual(again.deferred, r.deferred); XCTAssertEqual(again.replayLog, r.replayLog)
    }

    func testDiagnosticsFromZeroComeOutAsTheyCameAndMissingFilesStayMissing() throws {
        let state = try stateJSON(rows: [row(1, first: 0, last: 3.1)])
        let log = "{\"k\":\"t\",\"t\":0.5}\n"
        let r = ShareTimes.diagnostics(state: state, deferred: nil, replayLog: Data(log.utf8))
        XCTAssertEqual(r.shift, 0)
        XCTAssertEqual(r.state, state); XCTAssertEqual(r.replayLog, log); XCTAssertNil(r.deferred)
        let none = ShareTimes.diagnostics(state: nil, deferred: nil, replayLog: nil)
        XCTAssertNil(none.state); XCTAssertNil(none.replayLog); XCTAssertEqual(none.unreadable, [])
        // a state with no rows, and one from an older build with only some fields
        let bare = try json(["framesRead": 3])
        XCTAssertEqual(ShareTimes.diagnostics(state: bare, deferred: nil, replayLog: nil).state, bare)
    }

    func testADiagnosticsFileThatCannotBeReadIsNotSharedAndTheOthersAre() throws {
        let log = "{\"k\":\"t\",\"t\":5000}\n{\"k\":\"t\",\"t\":5001}\n"
        let good = try json(["rows": [row(1, first: 5000.5, last: 5002)], "frames": 1, "seconds": 1.0, "peakFootprintMB": 1.0])
        func check(_ state: Data, file: StaticString = #filePath, line: UInt = #line) throws {
            let r = ShareTimes.diagnostics(state: state, deferred: good, replayLog: Data(log.utf8))
            XCTAssertNil(r.state, file: file, line: line); XCTAssertEqual(r.unreadable, [.state], file: file, line: line)
            XCTAssertNotNil(r.deferred, file: file, line: line); XCTAssertNotNil(r.replayLog, file: file, line: line)
            XCTAssertEqual(try rowTimes(XCTUnwrap(r.deferred)), [0.5, 2.0], accuracy: 2e-9, file: file, line: line)
        }
        try check(Data("{\"rows\": [".utf8))                                            // cut off
        try check(Data("[1,2,3]".utf8))                                                  // not an object
        try check(try json(["rows": "5000.5"]))                                          // rows is not a list
        try check(try json(["rows": [row(1, first: 1, last: 2), ["firstTime": "5000.5"]]])) // a time that is not a number
        try check(try json(["rows": [5000.5]]))
    }

    func testTheReviewsLogAloneStartsAtZero() throws {
        let log = try sampleLog()
        let r = try XCTUnwrap(ShareTimes.replayLog(Data(log.utf8)))
        XCTAssertEqual(try XCTUnwrap(try logTimes(r.text).min()), 0, accuracy: 1e-9)
        XCTAssertEqual(r.droppedLines, 0)
        let again = try XCTUnwrap(ShareTimes.replayLog(Data(r.text.utf8)))
        XCTAssertEqual(again.text, r.text); XCTAssertEqual(again.shift, 0)
        let cut = try XCTUnwrap(ShareTimes.replayLog(Data((log + "{\"k\":\"t\",\"t\":12").utf8)))
        XCTAssertEqual(cut.droppedLines, 1)
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
