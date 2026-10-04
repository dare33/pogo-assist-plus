import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Grouping of unsure questions for bulk answers, and the part-read check that an answer clears (`BoxMerge.questionGroups`, `clearedChecks`, `rowsToCheck`).
final class QuestionGroupsTests: XCTestCase {
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

    func testThreePartReadsAreOneBulkGroupAndAnswerLikeOneByOne() throws {
        let (p, saved) = threePartReads()
        XCTAssertEqual(p.unsure.map { $0.kind }, [.partialRead, .partialRead, .partialRead])
        let g = groups(p, saved)
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].kind, .partialRead); XCTAssertEqual(g[0].effect, .seenOnly); XCTAssertEqual(g[0].members, [0, 1, 2]); XCTAssertTrue(g[0].canBulk)
        XCTAssertEqual(g[0].primary, [0: .existing("s1"), 1: .existing("s2"), 2: .existing("s3")])
        let bulk = try BoxMerge.apply(p, resolutions: g[0].primary, to: saved)
        var oneByOne = [Int: BoxMerge.Resolution]()
        for (i, id) in [(0, "s1"), (1, "s2"), (2, "s3")] { oneByOne[i] = .existing(id) }
        XCTAssertEqual(bulk, try BoxMerge.apply(p, resolutions: oneByOne, to: saved))
    }

    func testMixedKindsAndEveryUnsureIsInExactlyOneGroup() {
        // a part read, a powered-up row, an extra twin (two identical rows, one saved) and a part read with two candidates
        let saved = [entry(row("staraptor", cp: 1951), "s1"), entry(row("dragonite", cp: 1500, hp: 150), "d1"), entry(row("pidgeot", cp: 1000, hp: 120), "t1"),
                     entry(row("garchomp", cp: 1951, hp: 160, ivs: IVs(atk: 1, def: 2, hp: 3)), "g1"), entry(row("garchomp", cp: 1851, hp: 160, ivs: IVs(atk: 4, def: 5, hp: 6)), "g2")]
        let scanned = [part("staraptor", cp: 951), row("dragonite", cp: 1600, hp: 150), row("pidgeot", cp: 1000, hp: 120), row("pidgeot", cp: 1000, hp: 120), part("garchomp", cp: 951, hp: 160)]
        let p = plan(scanned, saved)
        let kinds = p.unsure.map { $0.kind }
        XCTAssertTrue(kinds.contains(.partialRead)); XCTAssertTrue(kinds.contains(.poweredUp)); XCTAssertTrue(kinds.contains(.extraTwin))
        let g = groups(p, saved)
        XCTAssertEqual(g.flatMap { $0.members }.sorted(), p.unsure.map { $0.scanned }.sorted(), "each unsure exactly once")
        XCTAssertEqual(g.flatMap { $0.members }, p.unsure.map { $0.scanned }, "groups follow plan order when no two share a group")
        for grp in g {
            let u = p.unsure.first { $0.scanned == grp.members[0] }!
            if u.kind == .extraTwin || u.candidates.count > 1 { XCTAssertNil(grp.effect); XCTAssertTrue(grp.primary.isEmpty); XCTAssertFalse(grp.canBulk); XCTAssertEqual(grp.members.count, 1) }
            else { XCTAssertNotNil(grp.effect); XCTAssertFalse(grp.canBulk, "a single member is never a bulk group") }
        }
    }

    func testPoweredUpRowsAreOneGroupAndAPartReadIsAnother() {
        // two powered-up rows (each would update its own entry) and a part read (marks seen only): same plan, two groups by kind and effect
        let saved = [entry(row("dragonite", cp: 1500, hp: 150), "d1"), entry(row("pidgeot", cp: 1000, hp: 120), "t1"), entry(row("staraptor", cp: 1951), "s1")]
        let scanned = [row("dragonite", cp: 1600, hp: 150), row("pidgeot", cp: 1100, hp: 120), part("staraptor", cp: 951)]
        let p = plan(scanned, saved)
        let g = groups(p, saved)
        XCTAssertEqual(g.map { $0.kind }, [.poweredUp, .partialRead]); XCTAssertEqual(g[1].effect, .seenOnly)
        let poweredUp = g.filter { $0.kind == .poweredUp }
        XCTAssertEqual(poweredUp.count, 1); XCTAssertEqual(poweredUp[0].members.count, 2); XCTAssertEqual(poweredUp[0].effect, .replacesValues); XCTAssertTrue(poweredUp[0].canBulk)
        XCTAssertEqual(g.flatMap { $0.members }.sorted(), p.unsure.map { $0.scanned }.sorted())
    }

    func testTwoRowsThatWouldWriteToTheSameSavedEntryCannotBulk() {
        let saved = [entry(row("dragonite", cp: 1500, hp: 150), "d1")]
        let p = plan([row("dragonite", cp: 1600, hp: 150), row("dragonite", cp: 1700, hp: 150)], saved)
        XCTAssertEqual(p.unsure.count, 2)
        let g = groups(p, saved)
        XCTAssertEqual(g.count, 1); XCTAssertEqual(g[0].members.count, 2); XCTAssertEqual(g[0].primary.count, 2)
        XCTAssertFalse(g[0].canBulk)
        XCTAssertThrowsError(try BoxMerge.apply(p, resolutions: g[0].primary, to: saved)) { XCTAssertEqual($0 as? BoxMerge.Failure, .chosenTwice(savedId: "d1")) }
    }

    func testTwoPartReadsOfOneSavedEntryMayBulkBecauseTheyOnlyMarkItSeen() throws {
        let saved = [entry(row("staraptor", cp: 1951), "s1")]
        let p = plan([part("staraptor", cp: 951), part("staraptor", cp: 195)], saved)
        XCTAssertEqual(p.unsure.count, 2)
        let g = groups(p, saved)
        XCTAssertEqual(g.count, 1); XCTAssertTrue(g[0].canBulk)
        XCTAssertNoThrow(try BoxMerge.apply(p, resolutions: g[0].primary, to: saved))
    }

    func testMembersWithSeveralCandidatesAreNeverBulkAnswerable() {
        let saved = [entry(row("garchomp", cp: 1951, hp: 160, ivs: IVs(atk: 1, def: 2, hp: 3)), "g1"), entry(row("garchomp", cp: 1851, hp: 160, ivs: IVs(atk: 4, def: 5, hp: 6)), "g2")]
        let p = plan([part("garchomp", cp: 951, hp: 160), part("garchomp", cp: 185, hp: 160)], saved)
        let g = groups(p, saved)
        XCTAssertEqual(p.unsure.map { $0.candidates.count }, [2, 2])
        XCTAssertEqual(g.count, 2)
        for grp in g { XCTAssertNil(grp.effect); XCTAssertTrue(grp.primary.isEmpty); XCTAssertFalse(grp.canBulk); XCTAssertEqual(grp.members.count, 1) }
    }

    func testPlanAndApplyAreUnchangedByGrouping() throws {
        let (p, saved) = threePartReads()
        let before = p
        _ = groups(p, saved)
        XCTAssertEqual(p, before)
    }
}
