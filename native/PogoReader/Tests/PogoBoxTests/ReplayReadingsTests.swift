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
        XCTAssertEqual(r.skippedLines, 3)
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
