import XCTest
@testable import PogoBox

/// Rule 32 (pass 2-5): the squad's slot figures over the Best squad's, whole percent, capped at 100%.
final class SquadStrengthTests: XCTestCase {
    private func d(_ now: Double?, _ after: Double? = nil) -> Strength { Strength(kind: .damage, now: now, after: after) }
    private func against(_ figures: [Strength?], _ reference: [Double?], kind: Strength.Kind = .damage) -> SquadStrength { SquadStrength.against(figures: figures, reference: reference, kind: kind) }

    func testTheValueIsTheSumOfTheSlotsOverTheSumOfTheReference() {
        let s = against([d(0.5), d(0.3), d(0.9)], [1, 0.8, 0.9])
        XCTAssertEqual(s.now!, (0.5 + 0.3 + 0.9) / (1 + 0.8 + 0.9), accuracy: 1e-9, "a sum over a sum, not a mean of ratios")
        XCTAssertEqual(s.text, "Squad strength 62% of best")
        XCTAssertFalse(s.matchesBest)
        XCTAssertNil(s.scoredText)
    }

    func testAfterUpgradesIsTheSameSumWithEachSlotsUpgradedFigure() {
        let s = against([d(0.5, 0.9), d(0.7)], [1, 1])
        XCTAssertEqual(s.now!, 0.6, accuracy: 1e-9)
        XCTAssertEqual(s.after!, 0.8, accuracy: 1e-9)
        XCTAssertEqual(s.text, "Squad strength 60% of best")
        XCTAssertEqual(s.afterText, "80% after upgrades")
        XCTAssertEqual(s.spoken, "Squad strength 60 percent of best, 80 percent after upgrades")
        XCTAssertTrue(s.strength.hasFaint)
    }

    func testAnUpgradeNeverLowersASlot() {
        XCTAssertEqual(against([d(0.6, 0.2)], [1]).after, 0.6)
    }

    func testAtOrOverTheReferenceReadsMatchesTheBestSquadAndIsCapped() {
        let over = against([d(1), d(0.9)], [0.8, 0.8])
        XCTAssertEqual(over.now, 1)
        XCTAssertTrue(over.matchesBest)
        XCTAssertEqual(over.text, "Squad strength 100% · Matches the best squad")
        XCTAssertNil(over.afterText, "nothing to gain above the reference")
        XCTAssertFalse(over.strength.hasFaint)
        let equal = against([d(0.8)], [0.8])
        XCTAssertTrue(equal.matchesBest)
        XCTAssertEqual(equal.spoken, "Squad strength 100 percent, Matches the best squad")
        // Just under does not match.
        XCTAssertFalse(against([d(0.79)], [0.8]).matchesBest)
    }

    func testTheUneditedBestTabIsTheBestSquad() {
        let s = SquadStrength.bestSquad(reference: Array(repeating: 0.8, count: 6))
        XCTAssertEqual(s.now, 1)
        XCTAssertEqual(s.text, "Squad strength 100% · the best squad")
        XCTAssertEqual(s.spoken, "Squad strength 100 percent, the best squad")
        XCTAssertNil(s.afterText)
        XCTAssertNil(s.scoredText)
    }

    func testAnEmptySlotCountsZeroAgainstItsReferenceSlot() {
        let s = against([d(1), nil], [1, 1])
        XCTAssertEqual(s.now, 0.5)
        XCTAssertEqual(s.scored, 2, "an empty slot is scored 0")
        XCTAssertNil(s.scoredText)
        XCTAssertEqual(against([nil, nil, nil], [1, 1, 1]).now, 0)
    }

    func testAnUnscoredSlotIsLeftOutTogetherWithTheReferencesSlotAtThatIndex() {
        // Slot 1 and 2 have no figure (IVs unread; level not read with an after figure only). Their reference slots (1.0 and 0.2) leave the sum too.
        let s = against([d(0.8), d(nil), d(nil, 0.6), d(0.4), nil, d(1)], [0.9, 1.0, 0.2, 0.8, 0.7, 1])
        XCTAssertEqual(s.now!, (0.8 + 0.4 + 0 + 1) / (0.9 + 0.8 + 0.7 + 1), accuracy: 1e-9)
        XCTAssertEqual(s.scored, 4)
        XCTAssertEqual(s.total, 6)
        XCTAssertEqual(s.scoredText, "4 of 6 slots scored")
        XCTAssertTrue(s.spoken.hasSuffix("4 of 6 slots scored"))
        let none = against([d(nil), Strength.scoreNotKnown], [1, 1])
        XCTAssertNil(none.now)
        XCTAssertEqual(none.text, "Squad strength not read")
        XCTAssertEqual(none.scoredText, "0 of 2 slots scored")
        XCTAssertNil(none.strength.now, "no bar")
    }

    func testAReferenceSlotWithNoFigureLeavesThatIndexOutOfBothSides() {
        let s = against([d(0.5), d(0.5), nil], [1, nil, 1])
        XCTAssertEqual(s.now!, 0.25, accuracy: 1e-9, "(0.5 + 0) / (1 + 1); slot 2 is out, slot 3 empty counts 0")
        XCTAssertEqual(s.scored, 2)
        XCTAssertEqual(s.scoredText, "2 of 3 slots scored")
    }

    func testNoReferenceFigureAtAllIsNoBar() {
        let s = against([d(0.5), d(0.5)], [nil, nil])
        XCTAssertNil(s.now)
        XCTAssertEqual(s.text, "Squad strength not read")
        XCTAssertNil(s.strength.now)
        XCTAssertNil(against([d(0.5)], [0]).now, "a reference of nothing is no bar")
    }

    func testAGainThatRoundsToTheSamePercentShowsNoAfterText() {
        let s = against([d(0.700, 0.703)], [1])
        XCTAssertNil(s.afterText)
        XCTAssertFalse(s.strength.hasFaint)
    }

    func testPvPIsTheMeanScoreOverTheReferencesMeanWithNoAfterPart() {
        let s = against([.score(90), .score(70), Strength.scoreNotKnown], [0.95, 0.9, 0.8], kind: .score)
        XCTAssertEqual(s.now!, (0.9 + 0.7) / (0.95 + 0.9), accuracy: 1e-9)
        XCTAssertEqual(s.text, "Squad strength 86% of best")
        XCTAssertNil(s.afterText)
        XCTAssertEqual(s.scoredText, "2 of 3 slots scored")
    }

    func testTheAfterWordsShowExactlyWhenTheBarDrawsAFaintPart() {
        for (n, a) in [(0.700, 0.704), (0.700, 0.7049), (0.699, 0.705), (0.700, 0.710), (0.5, 0.5), (0.994, 1.0)] {
            let s = against([d(n, a)], [1])
            XCTAssertEqual(s.afterText != nil, s.strength.hasFaint, "\(n) to \(a)")
        }
    }

    /// H7: the unedited Best tab goes through the same safeguards.
    func testTheUneditedBestTabLeavesOutAReferenceSlotWithNoFigureAndDrawsNoBarWithoutOne() {
        let some = SquadStrength.bestSquad(reference: [0.9, nil, 0.7, 0.8, nil, 0.6])
        XCTAssertEqual(some.now, 1)
        XCTAssertEqual(some.scored, 4)
        XCTAssertEqual(some.scoredText, "4 of 6 slots scored")
        XCTAssertEqual(some.text, "Squad strength 100% · the best squad")
        let none = SquadStrength.bestSquad(reference: [nil, nil, nil])
        XCTAssertNil(none.now)
        XCTAssertEqual(none.text, "Squad strength not read")
        XCTAssertNil(none.strength.now, "no bar")
        XCTAssertEqual(none.scoredText, "0 of 3 slots scored")
    }

    /// H9: the percent is rounded down; 100% reads only at or over the reference.
    func testThePercentIsRoundedDownAndOneHundredNeedsTheReference() {
        let s = against([d(0.998)], [1])
        XCTAssertEqual(s.text, "Squad strength 99% of best", "99.8% is not 100%")
        XCTAssertFalse(s.matchesBest)
        XCTAssertEqual(against([d(0.789)], [1]).text, "Squad strength 78% of best")
        XCTAssertEqual(against([d(0.70)], [1]).text, "Squad strength 70% of best", "no floating point loss at a whole percent")
        XCTAssertEqual(against([d(0.5, 0.998)], [1]).afterText, "99% after upgrades")
        XCTAssertNil(against([d(0.504, 0.509)], [1]).afterText, "the same whole percent after rounding down shows no after words")
        XCTAssertEqual(against([d(1.0)], [1]).text, "Squad strength 100% · Matches the best squad")
    }

    /// H17: owned figures below the reference (not the reference fed back in): the value is the owned sum over the reference sum.
    func testOwnedFiguresBelowTheReferenceReadBelowIt() {
        let s = against([d(0.6, 0.7), d(0.5), d(0.4, 0.9)], [0.9, 0.9, 0.9])
        XCTAssertEqual(s.now!, 1.5 / 2.7, accuracy: 1e-9)
        XCTAssertEqual(s.text, "Squad strength 55% of best")
        XCTAssertEqual(s.afterText, "77% after upgrades")
        XCTAssertFalse(s.matchesBest)
    }
}
