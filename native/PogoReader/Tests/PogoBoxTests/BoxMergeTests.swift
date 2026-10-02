import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class BoxMergeTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ day: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400) }

    private func row(_ speciesId: String = "pidgey", cp: Int = 300, ivs: IVs? = IVs(atk: 10, def: 11, hp: 12), hp: Int? = 50, flags: [String] = []) -> ScanRow {
        let sp = gm.byId[speciesId]
        let nf = GameMaster.nameAndForm(sp?.name ?? speciesId)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: speciesId, dex: sp?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: 10, levelMax: 10, dust: 1000, solveStatus: "exact", flags: flags, frames: [])
    }
    private func entry(_ r: ScanRow, id: String = UUID().uuidString, corrections: Corrections = Corrections()) -> BoxEntry {
        BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0), corrections: corrections)
    }
    private func plan(_ scanned: [ScanRow], _ saved: [BoxEntry], _ kind: BoxStore.Kind = .full) -> BoxMerge.Plan {
        BoxMerge.plan(scanned: scanned, into: saved, kind: kind, scanDate: date(10), gameMaster: gm)
    }

    // MARK: rule 1 unchanged

    func testUnchangedMatchesOnSpeciesIVsAndCP() {
        let v = entry(row(), id: "a")
        let p = plan([row()], [v])
        XCTAssertEqual(p.same, [BoxMerge.Pair(scanned: 0, savedId: "a")])
        XCTAssertTrue(p.new.isEmpty && p.updated.isEmpty && p.unsure.isEmpty && p.gone.isEmpty)
    }

    func testUnchangedNegatives() {
        let v = entry(row(), id: "a")
        for other in [row("rattata"), row(ivs: IVs(atk: 10, def: 11, hp: 13)), row(cp: 299)] {
            let p = plan([other], [v])
            XCTAssertTrue(p.same.isEmpty, "\(other.name) \(other.cp)")
        }
        // a different species with the same everything else is new, and the saved one is gone in a full scan
        let p = plan([row("rattata")], [v])
        XCTAssertEqual(p.new, [0]); XCTAssertEqual(p.gone, ["a"])
    }

    // MARK: rule 2 powered up

    func testPoweredUpUpdatesTheSavedEntry() {
        let v = entry(row(cp: 300), id: "a")
        let p = plan([row(cp: 450)], [v])
        XCTAssertEqual(p.updated, [BoxMerge.Update(scanned: 0, savedId: "a", reason: .poweredUp)])
        XCTAssertTrue(p.new.isEmpty && p.gone.isEmpty)
        let box = try! BoxMerge.apply(p, to: [v])
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(box[0].id, "a")
        XCTAssertEqual(box[0].row.cp, 450)
        XCTAssertEqual(box[0].firstSeen, date(0)); XCTAssertEqual(box[0].lastSeen, date(10))
    }

    func testLowerCPIsNotAPowerUp() {
        let v = entry(row(cp: 300), id: "a")
        let p = plan([row(cp: 250)], [v])
        XCTAssertTrue(p.updated.isEmpty)
        XCTAssertEqual(p.new, [0]); XCTAssertEqual(p.gone, ["a"])
    }

    func testPowerUpNeedsTheSameIVs() {
        let v = entry(row(cp: 300), id: "a")
        let p = plan([row(cp: 450, ivs: IVs(atk: 1, def: 1, hp: 1))], [v])
        XCTAssertTrue(p.updated.isEmpty)
        XCTAssertEqual(p.new, [0])
    }

    // MARK: rule 3 evolved

    func testEvolvedMatchesADescendantWithTheSameIVs() {
        let v = entry(row("pidgey", cp: 300), id: "a")
        for target in ["pidgeotto", "pidgeot"] {
            let p = plan([row(target, cp: 900)], [v])
            XCTAssertEqual(p.updated, [BoxMerge.Update(scanned: 0, savedId: "a", reason: .evolved)], target)
            let box = try! BoxMerge.apply(p, to: [v])
            XCTAssertEqual(box[0].row.speciesId, target); XCTAssertEqual(box[0].row.name, gm.byId[target]!.name); XCTAssertEqual(box[0].id, "a")
        }
    }

    func testEvolutionNegatives() {
        let v = entry(row("pidgeotto", cp: 600), id: "a")
        // an earlier stage is not an evolution of a later one; a stranger species is not; same species is rule 1 or 2 only
        XCTAssertTrue(plan([row("pidgey", cp: 900)], [v]).updated.isEmpty)
        XCTAssertTrue(plan([row("rattata", cp: 900)], [v]).updated.isEmpty)
        XCTAssertTrue(plan([row("pidgeot", cp: 900, ivs: IVs(atk: 0, def: 0, hp: 0))], [v]).updated.isEmpty)
        XCTAssertTrue(gm.isDescendant("pidgeot", of: "pidgey"))
        XCTAssertFalse(gm.isDescendant("pidgey", of: "pidgeot"))
        XCTAssertFalse(gm.isDescendant("pidgey", of: "pidgey"))
        XCTAssertTrue(gm.isDescendant("vaporeon", of: "eevee"))
    }

    // MARK: rule 4 no IVs

    func testNoIVsMatchesOnSpeciesCPAndHP() {
        let v = entry(row(ivs: nil, hp: 50), id: "a")
        let p = plan([row(ivs: nil, hp: 50)], [v])
        XCTAssertEqual(p.same, [BoxMerge.Pair(scanned: 0, savedId: "a")])
    }

    func testNoIVsNegatives() {
        let v = entry(row(ivs: nil, hp: 50), id: "a")
        XCTAssertTrue(plan([row(ivs: nil, hp: 51)], [v]).same.isEmpty, "HP differs")
        XCTAssertTrue(plan([row(cp: 301, ivs: nil, hp: 50)], [v]).same.isEmpty, "CP differs")
        XCTAssertTrue(plan([row("rattata", ivs: nil, hp: 50)], [v]).same.isEmpty, "species differs")
        XCTAssertTrue(plan([row(ivs: nil, hp: nil)], [v]).same.isEmpty, "HP unknown")
        // both sides have IVs and they differ: rule 4 does not apply
        let w = entry(row(ivs: IVs(atk: 1, def: 1, hp: 1)), id: "b")
        XCTAssertTrue(plan([row(ivs: IVs(atk: 2, def: 2, hp: 2))], [w]).same.isEmpty)
    }

    func testIVsNowReadFillsInAnEntryThatHadNone() {
        let v = entry(row(ivs: nil), id: "a")
        let p = plan([row(ivs: IVs(atk: 5, def: 5, hp: 5))], [v])
        XCTAssertEqual(p.updated, [BoxMerge.Update(scanned: 0, savedId: "a", reason: .ivsNowRead)])
        XCTAssertEqual(try! BoxMerge.apply(p, to: [v])[0].row.ivs, IVs(atk: 5, def: 5, hp: 5))
    }

    // MARK: rule 5 twins

    func testTwinsMatchByCount() {
        let a = entry(row(), id: "a"), b = entry(row(), id: "b")
        let two = plan([row(), row()], [a, b])
        XCTAssertEqual(two.same.count, 2); XCTAssertTrue(two.new.isEmpty && two.gone.isEmpty && two.unsure.isEmpty)
        XCTAssertEqual(Set(two.same.map { $0.savedId }), ["a", "b"])
        let three = plan([row(), row(), row()], [a, b])
        XCTAssertEqual(three.same.count, 2); XCTAssertEqual(three.new.count, 1)
        let one = plan([row()], [a, b])
        XCTAssertEqual(one.same.count, 1); XCTAssertEqual(one.gone.count, 1)
        let oneAdd = plan([row()], [a, b], .partial)
        XCTAssertTrue(oneAdd.gone.isEmpty)
    }

    func testPoweredUpTwinsPairByCountAndLeftoverCopyIsNew() {
        let a = entry(row(cp: 300), id: "a"), b = entry(row(cp: 300), id: "b")
        let p = plan([row(cp: 400), row(cp: 400)], [a, b])
        XCTAssertEqual(p.updated.count, 2); XCTAssertTrue(p.unsure.isEmpty && p.new.isEmpty)
        // one twin powered up, the other not: the unchanged one is rule 1, the other is rule 2
        let q = plan([row(cp: 300), row(cp: 400)], [a, b])
        XCTAssertEqual(q.same.count, 1); XCTAssertEqual(q.updated.count, 1); XCTAssertTrue(q.unsure.isEmpty)
    }

    // MARK: rule 6 ambiguity

    func testOneScannedWithTwoDifferentCandidatesIsUnsure() {
        let a = entry(row(cp: 300), id: "a"), b = entry(row(cp: 350), id: "b")
        let p = plan([row(cp: 500)], [a, b])
        XCTAssertEqual(p.unsure, [BoxMerge.Unsure(scanned: 0, candidates: ["a", "b"])])
        XCTAssertTrue(p.updated.isEmpty && p.new.isEmpty)
        XCTAssertTrue(p.gone.isEmpty, "candidates are not proposed as gone")
    }

    func testTwoDifferentScannedForOneSavedIsUnsure() {
        let a = entry(row(cp: 300), id: "a")
        let p = plan([row(cp: 500), row(cp: 600)], [a])
        XCTAssertEqual(p.unsure.map { $0.scanned }, [0, 1])
        XCTAssertEqual(p.unsure[0].candidates, ["a"])
    }

    func testResolvingUnsure() throws {
        let a = entry(row(cp: 300), id: "a"), b = entry(row(cp: 350), id: "b")
        let p = plan([row(cp: 500)], [a, b])
        XCTAssertThrowsError(try BoxMerge.apply(p, to: [a, b]))   // unanswered
        XCTAssertThrowsError(try BoxMerge.apply(p, resolutions: [0: .existing("zzz")], to: [a, b]))   // not a candidate
        let picked = try BoxMerge.apply(p, resolutions: [0: .existing("b")], to: [a, b])
        XCTAssertEqual(picked.map { $0.id }, ["a", "b"]); XCTAssertEqual(picked[1].row.cp, 500); XCTAssertEqual(picked[0].row.cp, 300)
        let asNew = try BoxMerge.apply(p, resolutions: [0: .new], to: [a, b], makeID: { "n1" })
        XCTAssertEqual(asNew.map { $0.id }, ["a", "b", "n1"])
    }

    func testTwoUnsureCannotPickTheSameSaved() {
        let a = entry(row(cp: 300), id: "a")
        let p = plan([row(cp: 500), row(cp: 600)], [a])
        XCTAssertThrowsError(try BoxMerge.apply(p, resolutions: [0: .existing("a"), 1: .existing("a")], to: [a])) { XCTAssertEqual($0 as? BoxMerge.Failure, .chosenTwice(savedId: "a")) }
        XCTAssertNoThrow(try BoxMerge.apply(p, resolutions: [0: .existing("a"), 1: .new], to: [a]))
    }

    // MARK: full vs add and update

    func testFullScanProposesGoneAddAndUpdateKeeps() throws {
        let a = entry(row("pidgey"), id: "a"), b = entry(row("rattata", cp: 200), id: "b")
        let full = plan([row("pidgey")], [a, b], .full)
        XCTAssertEqual(full.gone, ["b"])
        XCTAssertEqual(try BoxMerge.apply(full, to: [a, b]).map { $0.id }, ["a"])
        let add = plan([row("pidgey"), row("zubat", cp: 100)], [a, b], .partial)
        XCTAssertTrue(add.gone.isEmpty)
        let out = try BoxMerge.apply(add, to: [a, b], makeID: { "z" })
        XCTAssertEqual(out.map { $0.id }, ["a", "b", "z"])
        XCTAssertEqual(out[2].firstSeen, date(10)); XCTAssertEqual(out[1].lastSeen, date(0), "an unseen entry keeps its last seen date")
        XCTAssertEqual(out[0].lastSeen, date(10))
    }

    func testIntoAnEmptyBoxEverythingIsNew() throws {
        let p = plan([row(), row("rattata")], [])
        XCTAssertEqual(p.new, [0, 1])
        XCTAssertEqual(try BoxMerge.apply(p, to: []).count, 2)
    }

    // MARK: hand corrections

    func testCorrectionClearsTheFlagAndRemembersTheRead() throws {
        let v = entry(row(cp: 1960, flags: ["cp-chosen-1960-over-60", "bars-unsettled", "same-as-previous"]), id: "a")
        let fixed = try BoxMerge.correct(v, with: BoxMerge.Edit(cp: 1906), gameMaster: gm)
        XCTAssertEqual(fixed.row.cp, 1906); XCTAssertEqual(fixed.corrections.cp, Fix(was: 1960))
        XCTAssertEqual(fixed.row.flags, ["bars-unsettled", "same-as-previous"], "only the CP flag is answered")
        XCTAssertTrue(fixed.isHandCorrected)
        let twice = try BoxMerge.correct(fixed, with: BoxMerge.Edit(cp: 1907), gameMaster: gm)
        XCTAssertEqual(twice.corrections.cp, Fix(was: 1960), "the first read is the one remembered")
        let unchanged = try BoxMerge.correct(v, with: BoxMerge.Edit(cp: 1960), gameMaster: gm)
        XCTAssertFalse(unchanged.isHandCorrected)
    }

    func testCorrectionsValidate() {
        let v = entry(row())
        XCTAssertThrowsError(try BoxMerge.correct(v, with: BoxMerge.Edit(cp: 5), gameMaster: gm))
        XCTAssertThrowsError(try BoxMerge.correct(v, with: BoxMerge.Edit(ivs: IVs(atk: 16, def: 0, hp: 0)), gameMaster: gm))
        XCTAssertThrowsError(try BoxMerge.correct(v, with: BoxMerge.Edit(speciesName: "Notamon"), gameMaster: gm))
        XCTAssertEqual(try BoxMerge.correct(v, with: BoxMerge.Edit(speciesName: "rattata"), gameMaster: gm).row.speciesId, "rattata")
    }

    func testCorrectedValueSurvivesARescanThatReadsTheOldWrongValue() throws {
        let v = entry(row(cp: 1960, ivs: IVs(atk: 1, def: 2, hp: 3), flags: ["ambiguous-ivs:3-fit"]), id: "a")
        let fixed = try BoxMerge.correct(v, with: BoxMerge.Edit(cp: 1906, ivs: IVs(atk: 15, def: 14, hp: 13)), gameMaster: gm)
        // the scan reads the old wrong values again, with the flag back
        let again = row(cp: 1960, ivs: IVs(atk: 1, def: 2, hp: 3), flags: ["ambiguous-ivs:3-fit", "cp-chosen-1960-over-60"])
        let p = plan([again], [fixed])
        XCTAssertEqual(p.same, [BoxMerge.Pair(scanned: 0, savedId: "a")], "the wrong read still pairs with the corrected entry")
        let box = try BoxMerge.apply(p, to: [fixed])
        XCTAssertEqual(box[0].row.cp, 1906); XCTAssertEqual(box[0].row.ivs, IVs(atk: 15, def: 14, hp: 13))
        // Same leaves the entry as it is, flags included
        XCTAssertEqual(box[0].row.flags, [])
        // when the scan counts as an update (a later power up) it still keeps what it did not contradict
        let up = BoxMerge.updated(fixed, with: again, date: date(11))
        XCTAssertEqual(up.row.cp, 1906); XCTAssertEqual(up.row.ivs, IVs(atk: 15, def: 14, hp: 13)); XCTAssertEqual(up.row.flags, [], "the scan's flags for corrected values are dropped")
        XCTAssertTrue(up.isHandCorrected)
    }

    func testCorrectionIsReplacedWhenTheScanReadsSomethingNew() throws {
        let v = entry(row(cp: 1960), id: "a")
        let fixed = try BoxMerge.correct(v, with: BoxMerge.Edit(cp: 1906), gameMaster: gm)
        let up = BoxMerge.updated(fixed, with: row(cp: 2100), date: date(11))
        XCTAssertEqual(up.row.cp, 2100)
        XCTAssertNil(up.corrections.cp, "the correction is dropped when the Pokémon really changed")
    }

    func testCorrectedSpeciesKeepsAgainstTheOldNameButEvolves() throws {
        let v = entry(row("rattata", cp: 300), id: "a")
        let fixed = try BoxMerge.correct(v, with: BoxMerge.Edit(speciesName: "Pidgey"), gameMaster: gm)
        XCTAssertEqual(fixed.row.speciesId, "pidgey")
        // the scan reads "rattata" again: pairs, and the corrected name stays
        let p = plan([row("rattata", cp: 300)], [fixed])
        XCTAssertEqual(p.same.count, 1)
        XCTAssertEqual(BoxMerge.updated(fixed, with: row("rattata", cp: 300), date: date(11)).row.speciesId, "pidgey")
        // a real evolution of the corrected species is taken
        let q = plan([row("pidgeotto", cp: 800)], [fixed])
        XCTAssertEqual(q.updated.first?.reason, .evolved)
        XCTAssertNil(BoxMerge.updated(fixed, with: row("pidgeotto", cp: 800), date: date(11)).corrections.species)
    }

    func testMarkCheckedClearsFlagsOnly() {
        let v = entry(row(flags: ["ivs-unread", "hp-computed"]))
        let c = BoxMerge.markChecked(v)
        XCTAssertTrue(c.row.flags.isEmpty); XCTAssertFalse(c.isHandCorrected); XCTAssertFalse(c.needsCheck)
    }

    // MARK: flags

    func testEveryKnownFlagHasASentenceAndAFallbackExists() {
        let flags = ["cp-computed:1994", "cp-recovered:1966-from-966", "cp-chosen-1960-over-60", "same-as-previous", "ivs-unread", "ambiguous-ivs:3-fit", "ivs-corrected-from-1/2/3",
                     "bars-unsettled", "no-level-fits", "name-low-confidence", "level-ambiguous:20|20.5", "form-ambiguous:a|b", "hp-computed", "hp-unread", "sex-from-stats", "ivs-disagree"]
        var seen = Set<String>()
        for f in flags {
            let s = FlagInfo.explain(f)
            XCTAssertFalse(s.contains("marked this Pokémon for a check"), "\(f) fell through to the generic sentence")
            XCTAssertTrue(seen.insert(s).inserted, "\(f) shares a sentence")
            XCTAssertFalse(s.contains("!"))
        }
        XCTAssertTrue(FlagInfo.explain("something-new:7").contains("something-new:7"))
    }
}
