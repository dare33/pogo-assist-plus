import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class MegaMergeTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let ivs = IVs(atk: 15, def: 15, hp: 14)
    private func row(_ id: String, cp: Int, hp: Int? = 167, ivs: IVs? = IVs(atk: 15, def: 15, hp: 14), flags: [String] = []) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: 50, levelMax: 50, dust: 0, solveStatus: "exact", flags: flags, frames: [])
    }
    private func entry(_ r: ScanRow, _ id: String) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0)) }
    private func plan(_ s: [ScanRow], _ v: [BoxEntry], _ k: BoxStore.Kind = .partial) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: k, scanDate: date(5), gameMaster: gm) }

    func testTheMegaFormIdsAreRecognised() {
        XCTAssertEqual(BoxMerge.megaBase("staraptor_mega", gm), "staraptor")
        XCTAssertEqual(BoxMerge.megaBase("charizard_mega_x", gm), "charizard")
        XCTAssertEqual(BoxMerge.megaBase("charizard_mega_y", gm), "charizard")
        XCTAssertEqual(BoxMerge.megaBase("groudon_primal", gm), "groudon")
        XCTAssertNil(BoxMerge.megaBase("staraptor", gm)); XCTAssertNil(BoxMerge.megaBase("meganium", gm)); XCTAssertNil(BoxMerge.megaBase("yanmega", gm))
    }

    /// The owner's case: saved Staraptor CP 2819, IVs 15/15/14, scanned as Mega Staraptor CP 3970 with the same IVs.
    func testAMegaScanOfASavedPokemonIsSameAndKeepsItsOwnValues() throws {
        let saved = entry(row("staraptor", cp: 2819), "a")
        let p = plan([row("staraptor_mega", cp: 3970, hp: 190)], [saved], .full)
        XCTAssertEqual(p.same, [BoxMerge.Pair(scanned: 0, savedId: "a", mega: true)])
        XCTAssertTrue(p.new.isEmpty && p.updated.isEmpty && p.gone.isEmpty && p.unsure.isEmpty)
        let out = try BoxMerge.apply(p, to: [saved])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].row.speciesId, "staraptor"); XCTAssertEqual(out[0].row.cp, 2819); XCTAssertEqual(out[0].row.hp, 167); XCTAssertEqual(out[0].row.level, 50)
        XCTAssertEqual(out[0].lastSeen, date(5)); XCTAssertEqual(out[0].megaWhenScanned, true)
        // the next ordinary scan of it clears the note
        let again = try BoxMerge.apply(plan([row("staraptor", cp: 2819)], out), to: out)
        XCTAssertNil(again[0].megaWhenScanned)
    }

    func testAMegaScanNeedsTheSameIVsAndTheBaseSpecies() {
        let saved = entry(row("staraptor", cp: 2819), "a")
        XCTAssertTrue(plan([row("staraptor_mega", cp: 3970, ivs: IVs(atk: 1, def: 1, hp: 1))], [saved]).same.isEmpty, "different IVs")
        XCTAssertTrue(plan([row("charizard_mega_x", cp: 3970)], [saved]).same.isEmpty, "a different species' Mega")
        // a Mega scan is not an "evolved" or "powered up" update of the base entry
        let p = plan([row("staraptor_mega", cp: 3970)], [saved])
        XCTAssertTrue(p.updated.isEmpty)
    }

    func testTheReverseABaseScanUpdatesAnEntryFirstSavedAsMega() throws {
        let megaEntry = entry(row("staraptor_mega", cp: 3970, hp: 190), "m")
        let p = plan([row("staraptor", cp: 2819)], [megaEntry])
        XCTAssertEqual(p.unsure, [BoxMerge.Unsure(scanned: 0, candidates: ["m"], kind: .megaToBase)], "never applied automatically")
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("m")], to: [megaEntry])
        XCTAssertEqual(out[0].row.speciesId, "staraptor"); XCTAssertEqual(out[0].row.cp, 2819); XCTAssertEqual(out[0].row.hp, 167)
        XCTAssertTrue(plan([row("staraptor", cp: 2819, ivs: IVs(atk: 0, def: 0, hp: 0))], [megaEntry]).updated.isEmpty, "different IVs")
    }

    func testTwoSavedBaseCandidatesAreUnsureAndTwinsPairByCount() throws {
        let a = entry(row("staraptor", cp: 2819), "a"), b = entry(row("staraptor", cp: 2500, hp: 160), "b")
        let p = plan([row("staraptor_mega", cp: 3970)], [a, b])
        XCTAssertEqual(p.unsure, [BoxMerge.Unsure(scanned: 0, candidates: ["a", "b"])])
        // choosing one marks it seen and Mega when scanned; the Mega values are not copied
        let picked = try BoxMerge.apply(p, resolutions: [0: .existing("b")], to: [a, b])
        XCTAssertEqual(picked[1].row.cp, 2500); XCTAssertEqual(picked[1].megaWhenScanned, true); XCTAssertEqual(picked[1].lastSeen, date(5)); XCTAssertNil(picked[0].megaWhenScanned)
        // "new" saves it under the base species without CP
        let asNew = try BoxMerge.apply(p, resolutions: [0: .new], to: [a, b], makeID: { "n" })
        XCTAssertEqual(asNew[2].row.speciesId, "staraptor"); XCTAssertEqual(asNew[2].row.cp, 0)
        // identical twins on both sides pair by count
        let t1 = entry(row("staraptor", cp: 2819), "t1"), t2 = entry(row("staraptor", cp: 2819), "t2")
        let twins = plan([row("staraptor_mega", cp: 3970), row("staraptor_mega", cp: 3970)], [t1, t2])
        XCTAssertEqual(twins.same.count, 2); XCTAssertTrue(twins.unsure.isEmpty && twins.new.isEmpty)
    }

    func testAMegaScanWithNoBaseEntryIsNewUnderTheBaseSpeciesWithoutTheTemporaryValues() throws {
        let p = plan([row("staraptor_mega", cp: 3970, hp: 190)], [])
        XCTAssertEqual(p.new, [0]); XCTAssertEqual(p.megaBases[0], "staraptor")
        let out = try BoxMerge.apply(p, to: [], makeID: { "n" })
        let r = out[0].row
        XCTAssertEqual(r.speciesId, "staraptor"); XCTAssertEqual(r.name, "Staraptor"); XCTAssertEqual(r.form, "")
        XCTAssertEqual(r.cp, 0); XCTAssertNil(r.hp); XCTAssertNil(r.level); XCTAssertNil(r.levelMax); XCTAssertNil(r.dust)
        XCTAssertEqual(r.ivs, ivs, "the IVs do not change with Mega evolution")
        XCTAssertEqual(r.flags, ["mega-when-scanned"]); XCTAssertEqual(out[0].megaWhenScanned, true)
        XCTAssertTrue(FlagInfo.explain("mega-when-scanned").contains("Mega evolved"))
        // an ordinary scan of it later fills the values in (a power-up from the unknown CP 0)
        let laterPlan = plan([row("staraptor", cp: 2819)], out)
        XCTAssertEqual(laterPlan.unsure.first?.kind, .poweredUp, "asked, like every apparent power-up")
        let later = try BoxMerge.apply(laterPlan, resolutions: [0: .existing("n")], to: out)
        XCTAssertEqual(later.count, 1); XCTAssertEqual(later[0].row.cp, 2819); XCTAssertEqual(later[0].row.hp, 167); XCTAssertFalse(later[0].row.flags.contains("mega-when-scanned"))
        // the engine still advises on a box that holds such a row
        let rows = out.enumerated().map { i, e -> ScanRow in var r = e.row; r.index = i + 1; return r }
        XCTAssertNoThrow(try CoreEngine().advise(rows: rows, scanDate: date(5)))
    }
}
