import XCTest
import SwiftUI
@testable import PogoAssist

/// The Duo's control rail shows the controls of the screen the person is looking at: of the screens that have published, the one that appeared last.
@MainActor final class RailEntriesTests: XCTestCase {
    private func entry(_ sequence: Int, _ name: String) -> RailEntry { RailEntry(sequence: sequence, view: AnyView(Text(name))) }
    private func sequences(_ entries: [RailEntry]) -> [Int] { entries.map(\.sequence) }

    func testNothingPublishedGivesAnEmptyRail() {
        XCTAssertTrue(RailEntries.visible([]).isEmpty)
    }

    func testTheScreenThatAppearedLastWins() {
        // A pushed screen over its parent: both are alive and both publish, in either tree order.
        XCTAssertEqual(sequences(RailEntries.visible([entry(3, "parent"), entry(7, "pushed")])), [7])
        XCTAssertEqual(sequences(RailEntries.visible([entry(7, "pushed"), entry(3, "parent")])), [7])
    }

    func testAScreensButtonsKeepTheOrderTheyWerePublishedIn() {
        // Back first, then the screen's other buttons: all carry the screen's one sequence, so all stay, in order, and an older screen's entries go.
        let shown = RailEntries.visible([entry(2, "old"), entry(5, "back"), entry(5, "search"), entry(5, "fix")])
        XCTAssertEqual(sequences(shown), [5, 5, 5])
    }

    func testSequencesOnlyGoUp() {
        let a = RailEntries.nextSequence(), b = RailEntries.nextSequence()
        XCTAssertLessThan(a, b)
    }

    func testClearanceFollowsTheRail() {
        XCTAssertEqual(Rail.clearance(active: false), FloatingTabBar.clearance)
        XCTAssertEqual(Rail.clearance(active: true), 0)
    }
}
