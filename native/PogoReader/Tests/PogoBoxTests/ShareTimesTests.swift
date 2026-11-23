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

        XCTAssertEqual(zip(frameTimes(after), frameTimes(before)).map { $0 - $1 + origin }.map { abs($0) }.max() ?? 0, 0, accuracy: 2e-9, "every difference is kept")
        // the stored files are not touched
        XCTAssertEqual(try Data(contentsOf: s.resultURL), s.result)
        XCTAssertEqual(try Data(contentsOf: s.logURL), s.log)
        // the log keeps every line kind and its other fields
        XCTAssertEqual(try lines(logText).count, try lines(String(decoding: s.log, as: UTF8.self)).count)
        XCTAssertEqual(try lines(logText).map { $0["k"] as? String }, try lines(String(decoding: s.log, as: UTF8.self)).map { $0["k"] as? String })
    }

    /// The result is shifted as JSON: nothing but the frame times and the bars-split texts differs, in a file that holds what the model types would normalise away.
    func testOnlyTheFrameTimesAndBarsTextsOfTheStoredJSONChange() throws {
        let s = try stored(paging: hint)
        defer { try? FileManager.default.removeItem(at: s.root) }
        var tree = try XCTUnwrap(try JSONSerialization.jsonObject(with: s.result) as? [String: Any])
        var rows = try XCTUnwrap(tree["rows"] as? [[String: Any]])
        rows[0]["dynamax"] = false                       // the model's decoder would turn this into absent
        rows[0]["gigantamax"] = true                     // and would infer dynamax from this
        rows[0]["lucky"] = NSNull()                      // an explicit null optional
        rows[0]["futureRowKey"] = ["a": 1]               // an unknown key
        tree["rows"] = rows
        tree["futureKey"] = "kept"
        // strings with escapes: JSONSerialization writes "15\/15\/14" with an escaped slash, which a rewrite by Foundation would not keep
        let bars = try XCTUnwrap((tree["refineChanges"] as? [String])?.first { $0.hasPrefix("barsSplit") })
        tree["refineChanges"] = ["timingSplit: Fidough CP 768: IVs 15/15/14 stayed 14.0 s", bars, "twinSplit: caf\u{e9} \"q\" 15/15/14 at a swipe tick"]
        tree["reviewActions"] = ["Unsure (same) Fidough, CP 768: said it is new.", "3 saved Pokémon the scan did not see were kept in the box."]
        tree["reportHash"] = "abc123"; tree["reportSentAt"] = "2026-11-01T01:02:03Z"; tree["sourceSignature"] = "1234-1795000000000"
        let file = try JSONSerialization.data(withJSONObject: tree, options: [.sortedKeys])
        XCTAssertNotNil(try? decoded(file), "premise: it still decodes")

        let base = try XCTUnwrap(try JSONSerialization.jsonObject(with: file) as? [String: Any]), shared = ShareTimes.savedScan(result: file, replayLog: nil)
        let out = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(shared.result)) as? [String: Any])
        XCTAssertGreaterThan(shared.shift, 100_000)
        func masked(_ t: [String: Any]) -> NSDictionary {
            var m = t
            for list in ["rows", "review"] {
                m[list] = ((t[list] as? [[String: Any]]) ?? []).map { e in
                    var e = e
                    e["frames"] = ((e["frames"] as? [[String: Any]]) ?? []).map { var f = $0; f["time"] = nil; return f }
                    return e
                }
            }
            m["refineChanges"] = ((t["refineChanges"] as? [String]) ?? []).filter { !$0.contains("bars change") }   // only the bars-split text is allowed to differ
            return NSDictionary(dictionary: m)
        }
        let mo = masked(out), mt = masked(base)
        XCTAssertEqual(mo, mt, "every other key and value is as stored")
        // and on the file exactly as the store wrote it (its own number text), not only on one this test serialised
        let stored = try XCTUnwrap(try JSONSerialization.jsonObject(with: s.result) as? [String: Any])
        let fromStore = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(ShareTimes.savedScan(result: s.result, replayLog: nil).result)) as? [String: Any])
        XCTAssertEqual(masked(fromStore), masked(stored), "the stored file's numbers come back as the same values")
        // the strings that do not change keep their bytes; the bars-split one is rewritten
        func rawChanges(_ d: Data) throws -> [String] {
            let t = String(decoding: d, as: UTF8.self)
            let start = try XCTUnwrap(t.range(of: "\"refineChanges\":["))
            let rest = String(t[start.upperBound...])
            let re = try NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"")
            return re.matches(in: rest, range: NSRange(rest.startIndex..., in: rest)).prefix(3).map { String(rest[Range($0.range, in: rest)!]) }
        }
        let rawBefore = try rawChanges(file), rawAfter = try rawChanges(XCTUnwrap(shared.result))
        XCTAssertTrue(rawBefore[0].contains("\\/"), "premise: the stored text has an escaped slash: \(rawBefore[0])")
        XCTAssertEqual(rawAfter[0], rawBefore[0]); XCTAssertEqual(rawAfter[2], rawBefore[2]); XCTAssertNotEqual(rawAfter[1], rawBefore[1])
        let outRows = try XCTUnwrap(out["rows"] as? [[String: Any]])
        XCTAssertEqual(outRows[0]["dynamax"] as? Bool, false); XCTAssertTrue(outRows[0]["lucky"] is NSNull); XCTAssertEqual(out["futureKey"] as? String, "kept")
        XCTAssertEqual((base["refineChanges"] as? [String])?.count, (out["refineChanges"] as? [String])?.count)
        XCTAssertNotEqual(base["refineChanges"] as? [String], out["refineChanges"] as? [String], "the bars text did change")
        // a frame time that is a string, or a number that is not finite, is not shared
        for bad: Any in ["119757.5", [1], true] {
            var t = tree; var r = try XCTUnwrap(t["rows"] as? [[String: Any]]); var f = try XCTUnwrap(r[0]["frames"] as? [[String: Any]])
            f[0]["time"] = bad; r[0]["frames"] = f; t["rows"] = r
            let res = ShareTimes.savedScan(result: try JSONSerialization.data(withJSONObject: t), replayLog: nil)
            XCTAssertNil(res.result, "\(bad)"); XCTAssertEqual(res.unreadable, [.result])
        }
    }

    func testTheTextEditorChangesOnlyTheNamedValuesAndKeepsEveryOtherByte() throws {
        let text = "{ \"a\" : [ {\"time\": 100.5, \"x\":0.01756636106177467, \"s\":\"caf\\u00e9 \\\"q\\\" \\/\"} , {\"time\":null} ],\n \"note\":\"at 100 s\", \"time\": 7,\"c\":[\"keep\",\"drop\"] }"
        let edit = JSONTextEdit(numbers: [[.key("a"), .element, .key("time")]], transform: { $0 - 100 }, strings: [[.key("c"), .element]], rewrite: { $0 == "drop" ? "dropped" : $0 })
        let out = String(decoding: try XCTUnwrap(edit.apply(to: Data(text.utf8))), as: UTF8.self)
        XCTAssertEqual(out, text.replacingOccurrences(of: "100.5", with: "0.5").replacingOccurrences(of: "\"drop\"", with: "\"dropped\""))
        XCTAssertNil(JSONTextEdit(numbers: [[.key("a")]]).apply(to: Data("{\"a\":\"5\"}".utf8)), "a string where a time should be")
        XCTAssertNil(JSONTextEdit().apply(to: Data("{\"a\":".utf8)))
    }

    func testAReplayLineWhoseTimeIsNotANumberIsLeftOutAndCounted() throws {
        let empty = ScanResult(rows: [], review: [], unmatched: [])
        let bad = ["\"t\":\"1000\"", "\"t\":null", "\"t\":true", "\"t\":[1000]", "\"t\":{\"a\":1}", "\"t\":1000,\"last\":\"999\"", "\"t\":1000,\"last\":null"]
        for fields in bad {
            let log = "{\"k\":\"t\",\"t\":5000}\n{\"k\":\"e\",\(fields)}\n{\"k\":\"t\",\"t\":5001}\n"
            let r = ReportTimes.rebase(replayLog: log, result: empty)
            XCTAssertEqual(r.droppedLines, 1, fields); XCTAssertEqual(r.shift, 5000, fields)
            XCTAssertEqual(try lines(r.replayLog).count, 2, fields)
            XCTAssertFalse(r.replayLog.contains("1000"), fields)
            // the upload report says so too
            let doc = ScanReportBuilder.report(ScanReportInput(replayLog: log, result: empty, kind: .full, scanDate: Date(), app: .init(version: "1", build: "1"), device: .init(model: "m", os: "o", screenWidth: 1, screenHeight: 1, locale: "en")))
            XCTAssertTrue(doc.notIncluded.contains { $0.contains("1 replay log line") }, fields)
            XCTAssertFalse(doc.replayLog.contains("1000"), fields)
            // and so does a share
            let shared = try XCTUnwrap(ShareTimes.replayLog(Data(log.utf8)))
            XCTAssertEqual(shared.droppedLines, 1, fields); XCTAssertFalse(shared.text.contains("1000"), fields)
        }
        // a line with no time at all is kept, as before
        let none = ReportTimes.rebase(replayLog: "{\"k\":\"t\",\"t\":5000}\n{\"k\":\"x\"}\n", result: empty)
        XCTAssertEqual(none.droppedLines, 0)
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

    func testEachDiagnosticsFileCountsFromItsOwnFirstTime() throws {
        let log = try sampleLog()
        let logMin = try XCTUnwrap(try logTimes(log).min())
        XCTAssertGreaterThan(logMin, 400, "premise: the bundled log is boot-based")
        let state = try stateJSON(rows: [row(1, first: logMin + 1.5, last: logMin + 3.1), row(2, first: nil, last: logMin + 9)])
        let deferred = try json(["rows": [row(1, first: logMin - 2.0, last: logMin + 4)], "frames": 12, "seconds": 3.5, "peakFootprintMB": 20.25])
        let r = ShareTimes.diagnostics(state: state, deferred: deferred, replayLog: Data(log.utf8))
        XCTAssertEqual(r.unreadable, []); XCTAssertEqual(r.notPrepared, [])
        XCTAssertEqual(try XCTUnwrap(r.shifts[.state]), logMin + 1.5, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(r.shifts[.deferred]), logMin - 2.0, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(r.shifts[.replayLog]), logMin, accuracy: 1e-6)
        XCTAssertEqual(try rowTimes(XCTUnwrap(r.state)), [0, 1.6, 7.5], accuracy: 2e-9)
        XCTAssertEqual(try rowTimes(XCTUnwrap(r.deferred)), [0, 6.0], accuracy: 2e-9)
        XCTAssertEqual(try XCTUnwrap(try logTimes(XCTUnwrap(r.replayLog)).min()), 0, accuracy: 2e-9)
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
        // again: nothing changes
        let again = ShareTimes.diagnostics(state: r.state, deferred: r.deferred, replayLog: r.replayLog.map { Data($0.utf8) })
        XCTAssertEqual(again.shifts, [.state: 0, .deferred: 0, .replayLog: 0])
        XCTAssertEqual(again.state, r.state); XCTAssertEqual(again.deferred, r.deferred); XCTAssertEqual(again.replayLog, r.replayLog)
    }

    /// Files from different runs and builds beside each other, in every pairing: whichever is boot-timed leaves with no boot-based number, whatever the others count from.
    func testMixedClocksInEveryPairingLeaveNoBootBasedNumberInAnyOutput() throws {
        let boot = 119_735.0
        let bootLog = "{\"k\":\"t\",\"t\":\(boot + 0.4)}\n{\"k\":\"t\",\"t\":\(boot + 9.8)}\n{\"k\":\"e\",\"t\":\(boot + 12),\"last\":\(boot + 11)}\n"
        let bootState = try stateJSON(rows: [row(1, first: boot + 1, last: boot + 4)])
        let bootDeferred = try json(["rows": [row(1, first: boot + 2, last: boot + 5)], "frames": 3, "seconds": 1.5, "peakFootprintMB": 2.0])
        for (name, origin) in [("exactly zero", 0.0), ("small positive", 0.4), ("small positive, later", 3.25)] {
            let zeroLog = "{\"k\":\"t\",\"t\":\(origin)}\n{\"k\":\"t\",\"t\":\(origin + 7)}\n"
            let zeroState = try stateJSON(rows: [row(1, first: origin, last: origin + 3)])
            let zeroDeferred = try json(["rows": [row(1, first: origin, last: origin + 2)], "frames": 3, "seconds": 1.5, "peakFootprintMB": 2.0])
            let cases: [(String, Data?, Data?, String?)] = [
                ("old deferred beside a current state and log", zeroState, bootDeferred, zeroLog),
                ("old log beside a current state and deferred", zeroState, zeroDeferred, bootLog),
                ("old state beside a current deferred and log", bootState, zeroDeferred, zeroLog),
                ("old state and deferred beside a current log", bootState, bootDeferred, zeroLog),
                ("old state and log beside a current deferred", bootState, zeroDeferred, bootLog),
                ("old deferred and log beside a current state", zeroState, bootDeferred, bootLog),
                ("all old", bootState, bootDeferred, bootLog),
            ]
            for (label, state, deferred, log) in cases {
                let r = ShareTimes.diagnostics(state: state, deferred: deferred, replayLog: log.map { Data($0.utf8) })
                XCTAssertEqual(r.unreadable, [], "\(name): \(label)")
                let times = try rowTimes(XCTUnwrap(r.state)) + rowTimes(XCTUnwrap(r.deferred)) + logTimes(XCTUnwrap(r.replayLog))
                XCTAssertLessThan(try XCTUnwrap(times.max()), 100, "\(name): \(label): a boot-based time is left")
                XCTAssertEqual(try XCTUnwrap(times.min()), 0, accuracy: 1e-9, "\(name): \(label)")
                // and no boot-based number in the text of any file
                let text = String(decoding: try XCTUnwrap(r.state), as: UTF8.self) + String(decoding: try XCTUnwrap(r.deferred), as: UTF8.self) + (try XCTUnwrap(r.replayLog))
                XCTAssertEqual(try numbers(in: text).filter { $0 >= boot && $0 != 1_795_000_000 }, [], "\(name): \(label)")
            }
        }
    }

    func testDiagnosticsFromZeroComeOutAsTheyCameAndMissingFilesStayMissing() throws {
        let state = try stateJSON(rows: [row(1, first: 0, last: 3.1)])
        let log = "{\"k\":\"t\",\"t\":0}\n"
        let r = ShareTimes.diagnostics(state: state, deferred: nil, replayLog: Data(log.utf8))
        XCTAssertEqual(r.shifts[.state], 0); XCTAssertEqual(r.shifts[.replayLog], 0)
        XCTAssertEqual(r.state, state); XCTAssertEqual(r.replayLog, log); XCTAssertNil(r.deferred); XCTAssertNil(r.shifts[.deferred])
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
            XCTAssertEqual(try rowTimes(XCTUnwrap(r.deferred)), [0, 1.5], accuracy: 2e-9, file: file, line: line)
        }
        try check(Data("{\"rows\": [".utf8))                                            // cut off
        try check(Data("[1,2,3]".utf8))                                                  // not an object
        try check(try json(["rows": "5000.5"]))                                          // rows is not a list
        try check(try json(["rows": [row(1, first: 1, last: 2), ["firstTime": "5000.5"]]])) // a time that is not a number
        try check(try json(["rows": [5000.5]]))
        let badLog = ShareTimes.diagnostics(state: nil, deferred: nil, replayLog: Data([0xFF, 0xFE]))
        XCTAssertNil(badLog.replayLog); XCTAssertEqual(badLog.unreadable, [.replayLog])
    }

    // MARK: - repeated keys, odd keys, depth

    func testAFileWithARepeatedKeyAnywhereIsNotShared() throws {
        let s = try stored()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let text = String(decoding: s.result, as: UTF8.self)
        func inject(_ marker: String, _ with: String, in t: String) throws -> Data {
            let r = try XCTUnwrap(t.range(of: marker)); return Data(t.replacingCharacters(in: r, with: with).utf8)
        }
        // a frame time 0 and then a boot time: the parsers keep the first, so a check that read 0 would never see the second
        let frame = try inject("\"time\":", "\"time\":0,\"time\":", in: text)
        let r = ShareTimes.savedScan(result: frame, replayLog: nil)
        XCTAssertNil(r.result); XCTAssertEqual(r.unreadable, [.result])
        // also on the path that would send the original bytes (every time is 0 already)
        let zeroFile = try XCTUnwrap(ShareTimes.savedScan(result: s.result, replayLog: nil).result)
        XCTAssertEqual(ShareTimes.savedScan(result: zeroFile, replayLog: nil).shift, 0)
        let zeroDup = ShareTimes.savedScan(result: try inject("\"time\":", "\"time\":0,\"time\":119000.5,\"x\":", in: String(decoding: zeroFile, as: UTF8.self)), replayLog: nil)
        XCTAssertNil(zeroDup.result); XCTAssertEqual(zeroDup.unreadable, [.result])
        // a repeated key elsewhere in the document, and one written with an escape
        XCTAssertNil(ShareTimes.savedScan(result: try inject("\"kind\":", "\"kind\":\"full\",\"kind\":", in: text), replayLog: nil).result)
        XCTAssertNil(ShareTimes.savedScan(result: try inject("\"time\":", "\"time\":0,\"tim\\u0065\":", in: text), replayLog: nil).result)

        // state and saved-crop rows
        for bad in ["{\"rows\":[{\"firstTime\":0,\"firstTime\":119735,\"lastTime\":2}]}",
                    "{\"rows\":[{\"firstTime\":0,\"firstTime\":{\"a\":1},\"lastTime\":2}]}",
                    "{\"rows\":[{\"firstTime\":5,\"lastTime\":2}],\"rows\":[]}",
                    "{\"framesRead\":1,\"framesRead\":2}"] {
            let d = ShareTimes.diagnostics(state: Data(bad.utf8), deferred: Data(bad.utf8), replayLog: nil)
            XCTAssertNil(d.state, bad); XCTAssertNil(d.deferred, bad); XCTAssertEqual(d.unreadable, [.state, .deferred], bad)
        }

        // replay lines: dropped and counted, in the report and in a share, also when the file is already from 0
        let empty = ScanResult(rows: [], review: [], unmatched: [])
        for line in ["{\"k\":\"t\",\"t\":0,\"t\":119000.5}", "{\"k\":\"t\",\"t\":0,\"t\":\"119735\"}", "{\"k\":\"t\",\"t\":0,\"\\u0074\":119000.5}", "{\"k\":\"t\",\"t\":1,\"k\":\"d\"}"] {
            let log = "{\"k\":\"t\",\"t\":0}\n\(line)\n{\"k\":\"t\",\"t\":2}\n"
            let r = ReportTimes.rebase(replayLog: log, result: empty)
            XCTAssertEqual(r.droppedLines, 1, line); XCTAssertEqual(r.shift, 0, line)
            XCTAssertEqual(try lines(r.replayLog).count, 2, line); XCTAssertFalse(r.replayLog.contains("119"), line)
            let doc = ScanReportBuilder.report(ScanReportInput(replayLog: log, result: empty, kind: .full, scanDate: Date(), app: .init(version: "1", build: "1"), device: .init(model: "m", os: "o", screenWidth: 1, screenHeight: 1, locale: "en")))
            XCTAssertTrue(doc.notIncluded.contains { $0.contains("1 replay log line") }, line); XCTAssertFalse(doc.replayLog.contains("119"), line)
            let shared = try XCTUnwrap(ShareTimes.replayLog(Data(log.utf8)))
            XCTAssertEqual(shared.droppedLines, 1, line); XCTAssertFalse(shared.text.contains("119"), line)
        }
    }

    func testAKeyThatLooksLikeAPathIsNotShifted() throws {
        let state = Data("{\"rows/[]/firstTime\":7,\"rows\":[{\"firstTime\":5000,\"lastTime\":5002}],\"a\":{\"rows\":[{\"firstTime\":9000}]}}".utf8)
        let r = ShareTimes.diagnostics(state: state, deferred: nil, replayLog: nil)
        let out = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(r.state)) as? [String: Any])
        XCTAssertEqual(out["rows/[]/firstTime"] as? Int, 7)
        XCTAssertEqual(try rowTimes(XCTUnwrap(r.state)), [0, 2])
        XCTAssertEqual(((out["a"] as? [String: Any])?["rows"] as? [[String: Any]])?.first?["firstTime"] as? Int, 9000, "the same key names at another depth are not the rows")
        // the same through the editor with an element key that is literally "[]"
        let edit = JSONTextEdit(numbers: [[.key("a"), .element]], transform: { $0 + 1 })
        XCTAssertEqual(String(decoding: try XCTUnwrap(edit.apply(to: Data("{\"a\":[1],\"a/[]\":5,\"[]\":[7]}".utf8))), as: UTF8.self), "{\"a\":[2.0],\"a/[]\":5,\"[]\":[7]}")
    }

    /// Nesting is capped, and the check runs on a small stack (512 KB, as a task's) without overflowing it.
    func testNestingDeeperThanTheCapIsRefusedOnASmallStack() throws {
        func nested(_ n: Int) -> String { String(repeating: "[", count: n) + String(repeating: "]", count: n) }
        var results = [String: Bool]()
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            results["256 levels"] = JSONTextEdit().apply(to: Data(nested(256).utf8)) != nil
            results["257 levels"] = JSONTextEdit().apply(to: Data(nested(257).utf8)) != nil
            results["258 levels"] = JSONTextEdit().apply(to: Data(nested(258).utf8)) != nil
            results["100000 levels"] = JSONTextEdit().apply(to: Data(nested(100_000).utf8)) != nil
            let deep = "{\"rows\":[{\"firstTime\":5,\"x\":" + nested(5000) + "}]}"
            let d = ShareTimes.diagnostics(state: Data(deep.utf8), deferred: nil, replayLog: Data(("{\"k\":\"t\",\"t\":5}\n{\"k\":\"t\",\"t\":6,\"x\":" + nested(5000) + "}\n").utf8))
            results["state refused"] = d.state == nil && d.unreadable == [.state]
            results["line dropped"] = d.droppedLines == 1
            let saved = ShareTimes.savedScan(result: Data(("{\"schema\":1,\"x\":" + nested(5000) + "}").utf8), replayLog: nil)
            results["result refused"] = saved.result == nil && saved.unreadable == [.result]
            var edit = JSONTextEdit(); edit.numbers = [[.key("t")]]; edit.strings = [[.key("s")]]
            results["a list or an object where a time or a text should be"] = ["{\"t\":{}}", "{\"t\":[]}", "{\"t\":[1]}", "{\"t\":{\"x\":1}}", "{\"s\":[]}", "{\"s\":{\"x\":\"y\"}}"]
                .allSatisfy { edit.apply(to: Data($0.utf8)) == nil }
            done.signal()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        XCTAssertEqual(done.wait(timeout: .now() + 60), .success)
        XCTAssertEqual(results, ["256 levels": true, "257 levels": false, "258 levels": false, "100000 levels": false, "state refused": true, "line dropped": true, "result refused": true,
                                 "a list or an object where a time or a text should be": true])
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
