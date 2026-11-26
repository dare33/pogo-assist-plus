import XCTest
@testable import PogoReader

final class FrameSizeTests: XCTestCase {
    func testTheFirstCallRecordsAndTheSameSizeDoesNothing() {
        var s = FrameSize()
        XCTAssertNil(s.width); XCTAssertNil(s.changed)
        s.note(width: 1398, height: 2034)
        XCTAssertEqual(s, FrameSize(width: 1398, height: 2034, changed: nil))
        s.note(width: 1398, height: 2034)
        XCTAssertEqual(s, FrameSize(width: 1398, height: 2034, changed: nil))
    }
    func testADifferentSizeSetsTheFlagAndKeepsTheFirstSize() {
        var s = FrameSize()
        s.note(width: 1398, height: 2034); s.note(width: 2853, height: 2007)
        XCTAssertEqual(s, FrameSize(width: 1398, height: 2034, changed: true))
        s.note(width: 1398, height: 2034)
        XCTAssertEqual(s.changed, true, "the flag stays once set")
        var h = FrameSize(); h.note(width: 100, height: 200); h.note(width: 100, height: 201)
        XCTAssertEqual(h.changed, true, "a different height alone counts")
    }
    func testANewScanStartsEmpty() {
        var s = FrameSize(width: 1, height: 2, changed: true)
        s = FrameSize()
        s.note(width: 5, height: 6)
        XCTAssertEqual(s, FrameSize(width: 5, height: 6, changed: nil))
    }
}
