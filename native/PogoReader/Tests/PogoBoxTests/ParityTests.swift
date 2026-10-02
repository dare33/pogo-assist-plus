import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class ParityTests: XCTestCase {
    /// Always on: ~60 readings cut from marathon-phone (tools/make-core-fixture.mjs) give exactly the rows,
    /// review list and unmatched list the JavaScript gave under Node, field for field.
    func testFixtureMatchesNodeOutput() throws {
        let result = try sharedEngine.finish(readings: try Fixture.readings())
        let expected = try Fixture.expected()
        XCTAssertEqual(result.rows.count, 6)
        XCTAssertEqual(result.rows.map(RowKey.init), expected.rows.map(RowKey.init))
        XCTAssertEqual(result.rows, expected.rows)
        XCTAssertEqual(result.review, expected.review)
        XCTAssertEqual(result.unmatched, expected.unmatched)
        XCTAssertTrue(result.rows.contains { $0.flags == ["no-level-fits"] }, "the fixture should hold a flagged row")
    }

    /// Opt-in (POGO_PARITY=1): every real readings file under pogo-frames/_out gives the rows `finish-readings.mjs`
    /// gives under Node. Needs node on PATH and the reference checkout (POGO_REF, default below). Slow: the JS is
    /// quadratic-ish and darentas-02 alone takes about half a minute.
    func testRealReadingsMatchNode() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["POGO_PARITY"] == "1", "set POGO_PARITY=1 to run the real-readings parity check")
        let ref = env["POGO_REF"] ?? "/Users/greg-mb/Developer/personal/pogo-assist-plus-ref"
        let framesOut = URL(fileURLWithPath: env["POGO_FRAMES_OUT"] ?? "/Users/greg-mb/Developer/personal/pogo-frames/_out")
        // .../native/PogoReader/Tests/PogoBoxTests/ParityTests.swift -> .../native
        let native = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let tool = native.appendingPathComponent("tools/finish-readings.mjs").path
        let names = ["marathon-phone", "marathon-ipad-mini", "v3", "pogo-test-fast", "pogo-test-phone", "pogo-test-tablet", "darentas-01", "darentas-02", "darentas-03", "screenrec-2149"]
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-parity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        var ran = 0
        for name in names {
            let file = framesOut.appendingPathComponent("\(name).swift.readings.json")
            guard FileManager.default.fileExists(atPath: file.path) else { print("PARITY \(name): SKIPPED (file missing)"); continue }
            let out = tmp.appendingPathComponent("\(name).json")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["node", tool, "--repo", ref, file.path, "--out", out.path]
            p.standardError = FileHandle.nullDevice
            try p.run(); p.waitUntilExit()
            XCTAssertEqual(p.terminationStatus, 0, "node failed on \(name)")
            let expected = try JSONDecoder().decode(ScanResult.self, from: Data(contentsOf: out))
            let readings = try ReplayReadings.load(url: file).readings
            let t = Date()
            let got = try sharedEngine.finish(readings: readings)
            let secs = Date().timeIntervalSince(t)
            let a = got.rows.map(RowKey.init), b = expected.rows.map(RowKey.init)
            let same = a == b
            XCTAssertEqual(a.count, b.count, "\(name): row count")
            if !same, let i = zip(a, b).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset { XCTFail("\(name): first difference at row \(i + 1): \(a[i]) vs \(b[i])") }
            XCTAssertEqual(got.review.count, expected.review.count, "\(name): review count")
            XCTAssertEqual(got.unmatched.count, expected.unmatched.count, "\(name): unmatched count")
            print("PARITY \(name): \(same ? "IDENTICAL" : "DIFFERS") \(got.rows.count) rows vs node \(expected.rows.count), review \(got.review.count)/\(expected.review.count), unmatched \(got.unmatched.count)/\(expected.unmatched.count), finish \(String(format: "%.1f", secs)) s")
            ran += 1
        }
        XCTAssertGreaterThan(ran, 0, "no readings files found under \(framesOut.path)")
    }
}
