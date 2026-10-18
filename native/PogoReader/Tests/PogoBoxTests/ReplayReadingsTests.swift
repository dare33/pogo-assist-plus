import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class ReplayReadingsTests: XCTestCase {
    private func reading(_ i: Int, cp: Int = 1000) -> [String: Any] {
        ["frame": "f\(i)", "time": Double(i) * 0.2, "cp": cp, "cpText": "CP\(cp)", "name": "Zapdos", "nameText": "Zapdos", "nameConfidence": 90.0, "hpText": "129 / 129 HP", "ivConfidence": 0.0, "sharpness": 1.0, "flags": [String]()]
    }
    private func data(_ o: Any) throws -> Data { try JSONSerialization.data(withJSONObject: o) }
    private func lines(_ objs: [Any]) throws -> Data { Data(try objs.map { String(decoding: try data($0), as: UTF8.self) }.joined(separator: "\n").utf8) }

    func testPogoReadOutputAndBareArray() throws {
        let a = try ReplayReadings.parse(data(["frames": 2, "readings": [reading(0), reading(1)]]))
        XCTAssertEqual(a.readings.map(\.frame), ["f0", "f1"])
        let b = try ReplayReadings.parse(data([reading(0), reading(1), reading(2)]))
        XCTAssertEqual(b.readings.count, 3)
    }

    private func rline(_ t: Double, cp: Int? = 1000) -> [String: Any] {
        var o: [String: Any] = ["k": "r", "t": t, "cpText": "", "nameText": "Zapdos", "hpText": "", "ivConfidence": 0.0, "ms": 5.0, "flags": [String](), "name": "Zapdos"]
        if let cp { o["cp"] = cp }
        return o
    }

    func testReplayLogLines() throws {
        let d = try lines([rline(1.0), ["k": "t", "t": 1.3], ["k": "d", "t": 1.4], rline(1.6), ["k": "x", "t": 2.0]])
        let r = try ReplayReadings.parse(d)
        XCTAssertEqual(r.readings.map(\.frame), ["r1", "r2"])
        XCTAssertEqual(r.readings.map(\.time), [1.0, 1.6])
        XCTAssertEqual(r.readings.first?.cp, 1000)
        XCTAssertEqual(r.ticks, [1.3])
        XCTAssertEqual(r.drops, 1)
        XCTAssertEqual(r.skippedLines, 1)
        XCTAssertEqual(r.malformedLines, 0)
    }

    func testMalformedLinesAreCountedNotFatal() throws {
        var d = try lines([rline(1.0)])
        d.append(Data("\n{not json\n\n   \n".utf8))
        let r = try ReplayReadings.parse(d)
        XCTAssertEqual(r.readings.count, 1)
        XCTAssertEqual(r.malformedLines, 1)
    }

    func testSingleLineReplayIsNotMistakenForAReadingsFile() throws {
        XCTAssertEqual(try ReplayReadings.parse(lines([rline(1.0)])).readings.count, 1)
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try ReplayReadings.parse(Data()))
        XCTAssertThrowsError(try ReplayReadings.parse(Data("\n\n".utf8)))
    }

    func testRealFixtureLoads() throws {
        XCTAssertEqual(try Fixture.readings().count, 60)
    }
}

final class ReplayTickTests: XCTestCase {
    func testPogoReadOutputDerivesTicksFromSignatureDiffs() throws {
        // 3 consecutive frames above the threshold complete a swipe event; the tick is stamped on the third.
        var readings = [[String: Any]]()
        var diffs = [Any]()
        for i in 0..<12 {
            readings.append(["frame": "f\(i)", "time": Double(i) * 0.2, "cpText": "", "nameText": "", "flags": [String]()])
            diffs.append(i == 0 ? NSNull() : (i >= 4 && i <= 7 ? 30.0 : 1.0))
        }
        let json = try JSONSerialization.data(withJSONObject: ["readings": readings, "signatureDiffs": diffs])
        let r = try ReplayReadings.parse(json)
        XCTAssertEqual(r.ticks.count, 1)
        XCTAssertEqual(r.ticks[0], 6 * 0.2, accuracy: 1e-9)
    }

    func testNoSignatureDiffsNoTicks() throws {
        XCTAssertFalse(try ReplayReadings.parse(Data(#"{"readings":[]}"#.utf8)).hasTicks)
    }
}
