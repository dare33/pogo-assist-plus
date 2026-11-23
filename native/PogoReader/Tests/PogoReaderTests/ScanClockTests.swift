import XCTest
@testable import PogoReader

final class ScanClockTests: XCTestCase {
    func testTheFirstFrameIsZeroAndLaterFramesAreRelativeToIt() {
        var c = ScanClock()
        XCTAssertEqual(c.time(for: 488.72), 0)
        XCTAssertEqual(try XCTUnwrap(c.time(for: 488.92)), 0.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(c.time(for: 600.72)), 112, accuracy: 1e-9)
        XCTAssertEqual(c.origin, 488.72)
    }

    func testANonFiniteStampIsRefusedAndDoesNotSetTheOrigin() {
        var c = ScanClock()
        XCTAssertNil(c.time(for: .nan)); XCTAssertNil(c.time(for: .infinity)); XCTAssertNil(c.time(for: -.infinity))
        XCTAssertNil(c.origin)
        XCTAssertEqual(c.time(for: 1000), 0, "the first finite stamp is the origin, after the refused ones")
        XCTAssertNil(c.time(for: .nan))
        XCTAssertEqual(try XCTUnwrap(c.time(for: 1001)), 1, accuracy: 1e-9, "a refused stamp later changes nothing")
    }

    func testResetStartsANewOriginForTheNextBroadcast() {
        var c = ScanClock()
        _ = c.time(for: 500); _ = c.time(for: 510)
        c.reset()
        XCTAssertNil(c.origin)
        XCTAssertEqual(c.time(for: 9000), 0)
        XCTAssertEqual(try XCTUnwrap(c.time(for: 9000.4)), 0.4, accuracy: 1e-9)
    }

    func testDifferencesBetweenFramesAreThoseOfTheStamps() {
        var c = ScanClock()
        let stamps = [3601.25, 3601.45, 3601.85, 3603.0]
        let times = stamps.compactMap { c.time(for: $0) }
        XCTAssertEqual(times.count, 4)
        for i in 1..<4 { XCTAssertEqual(times[i] - times[i - 1], stamps[i] - stamps[i - 1], accuracy: 1e-9) }
    }
}
