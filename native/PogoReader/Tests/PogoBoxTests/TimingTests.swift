import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Opt-in timing of the app's post-scan work on a large box: POGO_TIMING=1 swift test --filter TimingTests
final class TimingTests: XCTestCase {
    func testLargeBoxTimings() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["POGO_TIMING"] != nil, "set POGO_TIMING=1")
        let url = URL(fileURLWithPath: "/Users/greg-mb/Developer/personal/pogo-frames/_out/darentas-02.swift.readings.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "large readings file not on this machine")
        let loaded = try ReplayReadings.load(url: url)
        let engine = CoreEngine()
        try engine.prepare()
        func time<T>(_ label: String, _ f: () throws -> T) rethrows -> T { let t = Date(); let r = try f(); print(String(format: "TIMING %@: %.2f s", label, Date().timeIntervalSince(t))); return r }
        let base = try time("finish") { try engine.finish(readings: loaded.readings) }
        let refined = try time("refine") { try Refine.apply(to: base, readings: loaded.readings, ticks: loaded.ticks, engine: engine) }
        let gm = try GameMaster.bundled()
        let date = Date()
        let plan = time("merge into empty box") { BoxMerge.plan(scanned: refined.scan.rows, into: [], kind: .full, scanDate: date, gameMaster: gm) }
        let entries = try BoxMerge.apply(plan, to: [])
        let again = time("merge same scan again") { BoxMerge.plan(scanned: refined.scan.rows, into: entries, kind: .full, scanDate: date, gameMaster: gm) }
        print("TIMING rows \(refined.scan.rows.count), second merge: same \(again.same.count) updated \(again.updated.count) unsure \(again.unsure.count) new \(again.new.count) gone \(again.gone.count)")
        let rows = entries.enumerated().map { i, e -> ScanRow in var r = e.row; r.index = i + 1; return r }
        let report = try time("advise") { try engine.advise(rows: rows, scanDate: date) }
        _ = time("advice model") { BoxAdvice.make(from: report, entries: entries) }
    }
}
