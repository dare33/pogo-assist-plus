import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// A row whose IVs were not solved is matched as one with no IVs, but its bars were read: a saved entry whose IVs those bars clearly contradict is not offered as
/// "maybe this one, powered up" (`BoxMerge.barsContradict`). The numbers are Greg's Darentas scan of 23 Nov 2026: Meowth CP 445 / HP 80, bars read 15/11/15 (38 other
/// triples fit, none of them the bars), against a saved Meowth CP 121 / HP 42 with 6/6/3.
final class BarsContradictTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private func iv(_ a: Int, _ d: Int, _ h: Int) -> IVs { IVs(atk: a, def: d, hp: h) }

    private func row(_ id: String, cp: Int, hp: Int?, ivs: IVs? = nil, read: IVs? = nil, guess: IVs? = nil, status: String? = nil, flags: [String] = []) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: read ?? ivs, ivsGuess: guess,
                       level: nil, levelMax: nil, dust: nil, solveStatus: status ?? (ivs == nil ? "ambiguous" : "exact"), flags: flags, frames: [])
    }
    private func entry(_ r: ScanRow, _ id: String, was: IVs? = nil) -> BoxEntry {
        BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0), corrections: was.map { Corrections(ivs: Fix(was: $0)) } ?? Corrections())
    }
    private func plan(_ s: [ScanRow], _ v: [BoxEntry]) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: .partial, scanDate: date(5), gameMaster: gm) }

    private var savedMeowth: ScanRow { row("meowth", cp: 121, hp: 42, ivs: iv(6, 6, 3)) }
    private let ambiguous = ["ambiguous-ivs:38-fit", "bars-unsettled"]

    func testTheMeowthWhoseBarsContradictTheSavedIVsIsNewNotAQuestion() {
        let read = row("meowth", cp: 445, hp: 80, read: iv(15, 11, 15), guess: iv(14, 11, 9), flags: ambiguous)
        let p = plan([read], [entry(savedMeowth, "m")])
        XCTAssertTrue(p.unsure.isEmpty, "bars 15/11/15 cannot be a 6/6/3 Meowth")
        XCTAssertEqual(p.new, [0])
    }

    func testWithNoBarsReadTheSameRowIsStillAsked() {
        // The question this rule removes exists only because the bars are ignored: with none read there is nothing to contradict, and it is asked as before.
        let p = plan([row("meowth", cp: 445, hp: 80, flags: ["ambiguous-ivs:38-fit"])], [entry(savedMeowth, "m")])
        XCTAssertEqual(p.unsure.map(\.candidates), [["m"]])
        XCTAssertEqual(p.unsure.first?.kind, .ambiguous)
    }

    func testBarsWithinANotchOfTheSavedIVsAreStillAsked() {
        let p = plan([row("meowth", cp: 445, hp: 80, read: iv(7, 5, 4), flags: ambiguous)], [entry(savedMeowth, "m")])
        XCTAssertEqual(p.unsure.map(\.candidates), [["m"]])
    }

    func testTwoNotchesOffOnOneStatIsAContradiction() {
        let p = plan([row("meowth", cp: 445, hp: 80, read: iv(6, 6, 5), flags: ambiguous)], [entry(savedMeowth, "m")])
        XCTAssertTrue(p.unsure.isEmpty)
        XCTAssertEqual(p.new, [0])
    }

    func testTheSolversGuessNearTheSavedIVsKeepsTheQuestion() {
        let p = plan([row("meowth", cp: 445, hp: 80, read: iv(15, 11, 15), guess: iv(6, 7, 3), flags: ambiguous)], [entry(savedMeowth, "m")])
        XCTAssertEqual(p.unsure.map(\.candidates), [["m"]])
    }

    func testASolverCorrectedRowIsJudgedByItsCorrectedIVsToo() {
        let read = row("meowth", cp: 445, hp: 80, ivs: iv(6, 6, 3), read: iv(6, 11, 3), status: "corrected", flags: ["ivs-corrected-from-6/11/3"])
        XCTAssertFalse(BoxMerge.cleanIVs(read))
        XCTAssertFalse(BoxMerge.barsContradict(read, entry(savedMeowth, "m")))
    }

    func testAHandCorrectedEntryIsComparedWithItsIVsBeforeTheCorrectionToo() {
        let read = row("meowth", cp: 445, hp: 80, read: iv(15, 11, 15), flags: ambiguous)
        XCTAssertTrue(BoxMerge.barsContradict(read, entry(savedMeowth, "m")))
        XCTAssertFalse(BoxMerge.barsContradict(read, entry(savedMeowth, "m", was: iv(15, 10, 15))))
    }

    func testCleanIVsAndEntriesWithoutIVsAreNeverJudged() {
        let clean = row("meowth", cp: 445, hp: 80, ivs: iv(15, 11, 15))
        XCTAssertFalse(BoxMerge.barsContradict(clean, entry(savedMeowth, "m")))
        let unread = row("meowth", cp: 445, hp: 80, read: iv(15, 11, 15), flags: ambiguous)
        XCTAssertFalse(BoxMerge.barsContradict(unread, entry(row("meowth", cp: 121, hp: 42), "m")))
    }

    func testTheSameCPAndHPOutweighTheBars() {
        // run12: a Weezing CP 883 / HP 85 whose bars read 8/10/3 against the saved Weezing CP 883 / HP 85 with 2/15/3. One Pokémon, bars misread.
        let read = row("weezing", cp: 883, hp: 85, read: iv(8, 10, 3), guess: iv(9, 10, 5), flags: ["ambiguous-ivs:16-fit", "bars-unsettled"])
        XCTAssertFalse(BoxMerge.barsContradict(read, entry(row("weezing", cp: 883, hp: 85, ivs: iv(2, 15, 3)), "w")))
        XCTAssertTrue(BoxMerge.barsContradict(read, entry(row("weezing", cp: 700, hp: 76, ivs: iv(2, 15, 3)), "w")))
    }

    func testARowWhoseCPFitsNoLevelIsNotJudged() {
        // Its CP is what was misread: it keeps its own ranked list (rule 7), which the bars only order.
        let read = row("meowth", cp: 9445, hp: 80, read: iv(15, 11, 15), status: "none", flags: ["no-level-fits"])
        XCTAssertFalse(BoxMerge.barsContradict(read, entry(savedMeowth, "m")))
    }

    func testOneOfTwoCandidatesContradictedLeavesTheOther() {
        let read = row("meowth", cp: 445, hp: 80, read: iv(7, 5, 4), flags: ambiguous)
        let other = row("meowth", cp: 228, hp: 59, ivs: iv(12, 4, 8))
        let p = plan([read], [entry(savedMeowth, "m"), entry(other, "o")])
        XCTAssertEqual(p.unsure.map(\.candidates), [["m"]])
    }
}
