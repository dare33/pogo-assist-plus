import XCTest
@testable import PogoBox

final class SquadStrengthTests: XCTestCase {
    private func d(_ now: Double?, _ after: Double? = nil) -> Strength { Strength(kind: .damage, now: now, after: after) }

    func testAllFullStrengthIsOneHundredPercentWithNoFaintPart() {
        let s = SquadStrength.of(figures: Array(repeating: d(1), count: 6))
        XCTAssertEqual(s.now, 1)
        XCTAssertFalse(s.hasAfter)
        XCTAssertEqual(s.text, "Squad strength 100%")
        XCTAssertNil(s.afterText)
        XCTAssertNil(s.scoredText)
    }

    func testMixedIsTheMeanNowAndAfter() {
        let s = SquadStrength.of(figures: [d(0.5, 0.9), d(0.7), d(0.9, 1.0)])
        XCTAssertEqual(s.now!, 0.7, accuracy: 1e-9)
        XCTAssertEqual(s.after!, (0.9 + 0.7 + 1.0) / 3, accuracy: 1e-9)
        XCTAssertEqual(s.text, "Squad strength 70%")
        XCTAssertEqual(s.afterText, "87% after upgrades")
        XCTAssertEqual(s.spoken, "Squad strength 70 percent, 87 percent after upgrades")
        XCTAssertEqual(s.strength.barSolid, 0.7, accuracy: 1e-9)
        XCTAssertTrue(s.strength.hasFaint)
    }

    func testAnEmptySlotCountsZero() {
        let s = SquadStrength.of(figures: [d(1), nil])
        XCTAssertEqual(s.now, 0.5)
        XCTAssertEqual(s.scored, 2, "an empty slot is scored 0")
        XCTAssertNil(s.scoredText)
        XCTAssertEqual(SquadStrength.of(figures: [nil, nil, nil]).now, 0)
    }

    func testAnUnscoredSlotIsLeftOutOfTheMeanAndTheLabelSaysSo() {
        // IVs unread: a row with no solid part. Level not read with an after figure only is also unscored.
        let s = SquadStrength.of(figures: [d(0.8), d(nil), d(nil, 0.6), d(0.4), nil, d(1)])
        XCTAssertEqual(s.now!, (0.8 + 0.4 + 0 + 1) / 4, accuracy: 1e-9)
        XCTAssertEqual(s.scored, 4)
        XCTAssertEqual(s.total, 6)
        XCTAssertEqual(s.scoredText, "4 of 6 slots scored")
        XCTAssertTrue(s.spoken.hasSuffix("4 of 6 slots scored"))
        let none = SquadStrength.of(figures: [d(nil), Strength.scoreNotKnown])
        XCTAssertNil(none.now)
        XCTAssertEqual(none.text, "Squad strength not read")
        XCTAssertEqual(none.scoredText, "0 of 2 slots scored")
        XCTAssertNil(none.strength.now)
    }

    func testAGainThatRoundsToTheSamePercentShowsNoAfterText() {
        let s = SquadStrength.of(figures: [d(0.700, 0.703)])
        XCTAssertNil(s.afterText)
        XCTAssertFalse(s.strength.hasFaint)
    }

    func testPvPReadsTheMeanScore() {
        let s = SquadStrength.of(figures: [.score(90), .score(70), Strength.scoreNotKnown], kind: .score)
        XCTAssertEqual(s.text, "Squad strength: score 80")
        XCTAssertNil(s.afterText)
        XCTAssertEqual(s.scoredText, "2 of 3 slots scored")
        XCTAssertEqual(s.spoken, "Squad strength, score 80, 2 of 3 slots scored")
    }

    func testAnUpgradeNeverLowersASlot() {
        let s = SquadStrength.of(figures: [d(0.6, 0.2)])
        XCTAssertEqual(s.after, 0.6)
    }
}
