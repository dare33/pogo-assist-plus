import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The no-level-fits check that answering a part-read question clears (`BoxMerge.clearedChecks`, `rowsToCheck`).
final class ClearedChecksTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400) }
    private let ivA = IVs(atk: 13, def: 12, hp: 15)
    private func row(_ id: String, cp: Int, hp: Int? = 142, ivs: IVs? = IVs(atk: 13, def: 12, hp: 15), flags: [String] = []) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: 20, levelMax: 20, dust: 1000, solveStatus: "exact", flags: flags, frames: [])
    }
    /// A part read that the merge asks about rather than pairing itself: its bars (1/1/1) clearly disagree with the saved ones (13/12/15), see `autoPartMatch`.
    private func part(_ id: String, cp: Int, hp: Int? = 142) -> ScanRow { row(id, cp: cp, hp: hp, ivs: IVs(atk: 1, def: 1, hp: 1), flags: ["no-level-fits"]) }
    private func entry(_ r: ScanRow, _ id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)) }
    private func plan(_ s: [ScanRow], _ v: [BoxEntry]) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: .partial, scanDate: date(5), gameMaster: gm) }
    private func groups(_ p: BoxMerge.Plan, _ v: [BoxEntry]) -> [BoxMerge.QuestionGroup] { BoxMerge.questionGroups(p, saved: v, gameMaster: gm) }

    /// Three saved Pokémon of different species, each with a part read of its CP (951 of 1951, ...), as in run 15.
    private func threePartReads() -> (BoxMerge.Plan, [BoxEntry]) {
        let saved = [entry(row("staraptor", cp: 1951), "s1"), entry(row("dragonite", cp: 2951, hp: 150), "s2"), entry(row("garchomp", cp: 3951, hp: 160), "s3")]
        let scanned = [part("staraptor", cp: 951), part("dragonite", cp: 951, hp: 150), part("garchomp", cp: 951, hp: 160)]
        return (plan(scanned, saved), saved)
    }

    func testPartReadAnsweredAsTheSavedOneOrLeftOutClearsItsCheckAndNewDoesNot() throws {
        let (p, saved) = threePartReads()
        XCTAssertEqual(BoxMerge.rowsToCheck(p, resolutions: [:]), [0, 1, 2], "unanswered: still to check")
        XCTAssertTrue(BoxMerge.clearedChecks(p, resolutions: [:]).isEmpty)
        let answers: [Int: BoxMerge.Resolution] = [0: .existing("s1"), 1: .leaveOut, 2: .new]
        XCTAssertEqual(BoxMerge.clearedChecks(p, resolutions: answers), [0, 1])
        XCTAssertEqual(BoxMerge.rowsToCheck(p, resolutions: answers), [2], "added with the bad CP: still to check")
        // what is saved: the added row keeps its flag, the others leave no flag in the box
        let out = try BoxMerge.apply(p, resolutions: answers, to: saved, makeID: { "n" })
        XCTAssertEqual(out.filter { $0.row.flags.contains("no-level-fits") }.map { $0.id }, ["n"])
    }

    func testAllAnsweredAsTheSavedOneLeaveNothingToCheckAndApplyWritesNoFlag() throws {
        let (p, saved) = threePartReads()
        let g = groups(p, saved)[0]
        XCTAssertEqual(BoxMerge.clearedChecks(p, resolutions: g.primary), [0, 1, 2])
        XCTAssertTrue(BoxMerge.rowsToCheck(p, resolutions: g.primary).isEmpty)
        let out = try BoxMerge.apply(p, resolutions: g.primary, to: saved)
        XCTAssertEqual(out.map { $0.row }, saved.map { $0.row }, "a seen-only answer writes none of the row's values or flags")
        XCTAssertTrue(out.allSatisfy { !$0.needsCheck })
    }

    func testAnAnswerThatIsNotACandidateClearsNothing() {
        let (p, _) = threePartReads()
        XCTAssertTrue(BoxMerge.clearedChecks(p, resolutions: [0: .existing("s2")]).isEmpty)
    }

    func testOtherCheckFlagsOnTheRowStayAfterTheNoLevelFitsCheckIsCleared() {
        let saved = [entry(row("staraptor", cp: 1951), "s1")]
        var r = part("staraptor", cp: 951); r.flags.append("hp-unread")
        let p = plan([r], saved)
        XCTAssertEqual(p.unsure.map { $0.kind }, [.partialRead])
        XCTAssertEqual(BoxMerge.clearedChecks(p, resolutions: [0: .existing("s1")]), [0])
        XCTAssertEqual(BoxMerge.rowsToCheck(p, resolutions: [0: .existing("s1")]), [0], "hp-unread is its own check")
    }

    func testOnlyPartReadQuestionsClearAndRowsWithoutTheFlagAreUntouched() {
        // a powered-up question on a row without no-level-fits: nothing to clear; a part read of another row does not clear this one
        let saved = [entry(row("dragonite", cp: 1500, hp: 150), "d1"), entry(row("staraptor", cp: 1951), "s1")]
        let p = plan([row("dragonite", cp: 1600, hp: 150), part("staraptor", cp: 951)], saved)
        let answers: [Int: BoxMerge.Resolution] = [0: .existing("d1"), 1: .existing("s1")]
        XCTAssertEqual(BoxMerge.clearedChecks(p, resolutions: answers), [1])
        XCTAssertEqual(BoxMerge.rowsToCheck(p, resolutions: answers), p.scanned.indices.filter { p.scanned[$0].needsCheck && $0 != 1 })
    }
}
