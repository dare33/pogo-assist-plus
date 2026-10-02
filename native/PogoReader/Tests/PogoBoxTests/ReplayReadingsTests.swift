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

    func testJsonLinesKeepReadingsAndSkipOtherLineKinds() throws {
        let d = try lines([
            ["kind": "header", "version": 1],
            ["kind": "reading", "reading": reading(0)],
            ["kind": "tick", "time": 0.3],
            reading(1),                                  // a bare reading line
            ["kind": "dropped", "time": 0.5, "count": 2],
            ["reading": reading(2)],
        ])
        let r = try ReplayReadings.parse(d)
        XCTAssertEqual(r.readings.map(\.frame), ["f0", "f1", "f2"])
        XCTAssertEqual(r.skippedLines, 2, "the header and the dropped-frame marker; the tick line is a tick")
        XCTAssertEqual(r.ticks, [0.3])
        XCTAssertEqual(r.malformedLines, 0)
    }

    func testMalformedLinesAreCountedNotFatal() throws {
        var d = try lines([reading(0)])
        d.append(Data("\n{not json\n\n   \n".utf8))
        d.append(try data(["reading": ["frame": 7, "cpText": "x", "name": ["not", "a", "string"]]]))
        let r = try ReplayReadings.parse(d)
        XCTAssertEqual(r.readings.count, 1)
        XCTAssertEqual(r.malformedLines, 2)
    }

    func testSingleLineReplayIsNotMistakenForAReadingsFile() throws {
        let r = try ReplayReadings.parse(lines([["reading": reading(0)]]))
        XCTAssertEqual(r.readings.count, 1)
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
    func testTickLinesAreCollectedAndNotCountedAsSkipped() throws {
        let reading: [String: Any] = ["frame": "f0", "time": 0.0, "cpText": "CP1", "nameText": "x", "cp": 1]
        let objs: [Any] = [["kind": "tick", "time": 1.5], reading, ["type": "tick", "t": 2.5], ["tick": 3.5], ["kind": "dropped", "time": 4.0], ["kind": "tick"]]
        let text = try objs.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n")
        let r = try ReplayReadings.parse(Data(text.utf8))
        XCTAssertEqual(r.ticks, [1.5, 2.5, 3.5])
        XCTAssertEqual(r.readings.count, 1)
        XCTAssertEqual(r.skippedLines, 2, "the dropped marker and a tick line with no time")
        XCTAssertTrue(r.hasTicks)
    }

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
