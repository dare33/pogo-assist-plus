import XCTest
@testable import PogoAssist

/// The A-Z index scrolls the list at most once every `JumpThrottle.gap` during a drag, with the latest letter; a tap goes at once; the last letter is always scrolled to.
@MainActor final class JumpThrottleTests: XCTestCase {
    func testATapScrollsAtOnce() {
        let t = JumpThrottle(); var went = [String]()
        t.request("M") { went.append($0) }
        XCTAssertEqual(went, ["M"], "no wait for the first jump of a touch")
        t.finish { went.append($0) }
        XCTAssertEqual(went, ["M"])
    }

    func testLettersCrossedInAHurryScrollOnceNowAndOnceWithTheLatestLater() async {
        let t = JumpThrottle(); var went = [String]()
        let scroll: (String) -> Void = { went.append($0) }
        for id in ["A", "B", "C", "D", "E"] { t.request(id, scroll: scroll) }
        XCTAssertEqual(went, ["A"], "the first now, the rest held")
        try? await Task.sleep(for: .seconds(JumpThrottle.gap + 0.15))
        XCTAssertEqual(went, ["A", "E"], "then once, with the latest letter")
    }

    func testTheLastLetterIsScrolledToWhenTheFingerLifts() {
        let t = JumpThrottle(); var went = [String]()
        let scroll: (String) -> Void = { went.append($0) }
        t.request("A", scroll: scroll); t.request("B", scroll: scroll); t.request("C", scroll: scroll)
        XCTAssertEqual(went, ["A"])
        t.finish(scroll)
        XCTAssertEqual(went, ["A", "C"], "B was skipped; C is where the finger lifted")
    }

    func testAFreshTapRightAfterADragJumpsAtOnce() {
        let t = JumpThrottle(); var went = [String]()
        let scroll: (String) -> Void = { went.append($0) }
        t.request("A", scroll: scroll); t.request("B", scroll: scroll)
        t.finish(scroll)
        XCTAssertEqual(went, ["A", "B"])
        t.request("Q", scroll: scroll)   // no wait: the throttle belongs to one touch
        XCTAssertEqual(went, ["A", "B", "Q"])
    }

    func testTheSameLetterAgainAfterTheTouchEndedJumpsAgain() async {
        let t = JumpThrottle(); var went = [String]()
        let scroll: (String) -> Void = { went.append($0) }
        t.request("M", scroll: scroll); t.finish(scroll)
        try? await Task.sleep(for: .seconds(JumpThrottle.gap + 0.05))   // the list may have been scrolled elsewhere by now
        t.request("M", scroll: scroll); t.finish(scroll)
        XCTAssertEqual(went, ["M", "M"])
    }

    func testBackToTheLetterJustScrolledToDoesNotScrollAgainInTheSameTouch() async {
        let t = JumpThrottle(); var went = [String]()
        let scroll: (String) -> Void = { went.append($0) }
        t.request("A", scroll: scroll); t.request("B", scroll: scroll); t.request("A", scroll: scroll)
        t.finish(scroll)
        XCTAssertEqual(went, ["A"], "the list is already at A")
    }
}
