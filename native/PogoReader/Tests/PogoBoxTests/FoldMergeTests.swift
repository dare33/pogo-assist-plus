import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Review findings folded in (M1 to M11, L1): written before the fixes, to fail first.
final class FoldMergeTests: XCTestCase {
    private let gm = try! GameMaster.bundled()
    private func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    private let x = IVs(atk: 15, def: 15, hp: 15), y = IVs(atk: 10, def: 14, hp: 13)

    private func row(_ id: String = "pikachu", cp: Int, hp: Int? = 60, ivs: IVs?, level: Double? = 20, dust: Int? = 1000, flags: [String] = []) -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                       level: level, levelMax: level, dust: dust, solveStatus: ivs == nil ? "unknown-ivs" : "exact", flags: flags, frames: [])
    }
    private func entry(_ r: ScanRow, _ id: String, corrections: Corrections = Corrections()) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0), corrections: corrections) }
    private func plan(_ s: [ScanRow], _ v: [BoxEntry], _ k: BoxStore.Kind = .full) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: k, scanDate: date(5), gameMaster: gm) }

    // M1: a field the scan did not read never replaces a saved one
    func testM1ChoosingASavedPokemonForAnIVlessReadKeepsItsIVsAndOtherValues() throws {
        let a = entry(row(cp: 500, ivs: x), "A"), b = entry(row(cp: 500, ivs: y), "B")
        var scanned = row(cp: 500, ivs: nil, level: nil, dust: nil); scanned.ivsRead = nil
        let p = plan([scanned], [a, b])
        XCTAssertEqual(p.unsure.first?.candidates.sorted(), ["A", "B"])
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("A")], to: [a, b])
        XCTAssertEqual(out[0].row.ivs, x); XCTAssertEqual(out[0].row.ivsRead, x); XCTAssertEqual(out[0].row.hp, 60)
        XCTAssertEqual(out[0].row.level, 20); XCTAssertEqual(out[0].row.dust, 1000)
    }

    // M11 (and M1 for the update path)
    func testM11APowerUpWithHPUnreadKeepsTheSavedHP() throws {
        let saved = entry(row("machamp", cp: 2500, hp: 150, ivs: x), "m")
        var s = row("machamp", cp: 2600, hp: nil, ivs: x); s.level = nil; s.dust = nil
        let p = plan([s], [saved])
        XCTAssertEqual(p.unsure.first?.kind, .poweredUp); XCTAssertTrue(p.updated.isEmpty)
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("m")], to: [saved])
        XCTAssertEqual(out[0].row.cp, 2600); XCTAssertEqual(out[0].row.hp, 150); XCTAssertEqual(out[0].row.level, 20); XCTAssertEqual(out[0].row.dust, 1000)
    }

    // M3
    func testM3AMegaRowWithoutIVsAsksAgainstTheBaseEntries() {
        let a = entry(row("staraptor", cp: 2819, hp: 167, ivs: x), "a"), b = entry(row("staraptor", cp: 2500, hp: 160, ivs: y), "b")
        let p = plan([row("staraptor_mega", cp: 3970, hp: 190, ivs: nil)], [a, b])
        XCTAssertEqual(p.unsure.first?.candidates.sorted(), ["a", "b"]); XCTAssertTrue(p.new.isEmpty); XCTAssertTrue(p.gone.isEmpty)
        // no saved base entry: New under the base species, as before
        XCTAssertEqual(plan([row("staraptor_mega", cp: 3970, hp: 190, ivs: nil)], []).new, [0])
    }

    // M4
    func testM4ThePlausibleCandidatesAreAskedAboutNotAddedAndRemoved() {
        // powered up, IVs unread this time
        let machamp = entry(real("machamp", level: 30, ivs: x), "m")
        let p1 = plan([real("machamp", level: 31, ivs: x, read: false)], [machamp])
        XCTAssertEqual(p1.unsure.first?.candidates, ["m"]); XCTAssertTrue(p1.new.isEmpty && p1.gone.isEmpty)
        // the reverse: the saved one has no IVs, the scan has them and the CP differs
        let noIVs = entry(real("machamp", level: 30, ivs: x, read: false), "n")
        let p2 = plan([real("machamp", level: 31, ivs: x)], [noIVs])
        XCTAssertEqual(p2.unsure.first?.candidates, ["n"]); XCTAssertTrue(p2.new.isEmpty && p2.gone.isEmpty)
        // a LOWER CP with the same IVs
        let p3 = plan([real("machamp", level: 29, ivs: x)], [machamp])
        XCTAssertEqual(p3.unsure.first?.candidates, ["m"]); XCTAssertTrue(p3.new.isEmpty && p3.gone.isEmpty)
    }

    // M5
    func testM5APowerUpNeverLowersHPOrLevel() {
        let saved = entry(real("machamp", level: 20, ivs: x), "m")
        var lowerHPRow = real("machamp", level: 21, ivs: x); lowerHPRow.hp = lowerHPRow.hp! - 10
        let lowerHP = plan([lowerHPRow], [saved])
        // a CP and an HP that no level gives for these IVs are not the saved Pokémon powered up: it is a new row, not a question
        XCTAssertTrue(lowerHP.updated.isEmpty); XCTAssertTrue(lowerHP.unsure.isEmpty); XCTAssertEqual(lowerHP.new, [0])
        var lowerLevelRow = real("machamp", level: 21, ivs: x); lowerLevelRow.level = 18; lowerLevelRow.levelMax = 18
        let lowerLevel = plan([lowerLevelRow], [saved])
        XCTAssertTrue(lowerLevel.updated.isEmpty); XCTAssertEqual(lowerLevel.unsure.count, 1)
        // a consistent power-up is still a power-up
        XCTAssertEqual(plan([real("machamp", level: 21, ivs: x)], [saved]).unsure.first?.kind, .poweredUp, "a consistent power-up is a question (kind poweredUp), never automatic")
    }

    // M6
    func testM6TwoSavedWithTheSameIVsBothPoweredUpIsAskedNotPairedGreedily() {
        let a = entry(row(cp: 300, hp: 50, ivs: x), "a"), b = entry(row(cp: 400, hp: 60, ivs: x), "b")
        // scanned 400 and 500: b may be unchanged and a powered up to 500, or a to 400 and b to 500: two consistent answers
        let p = plan([row(cp: 400, hp: 60, ivs: x), row(cp: 500, hp: 70, ivs: x)], [a, b])
        XCTAssertTrue(p.same.isEmpty && p.updated.isEmpty, "no greedy pairing")
        XCTAssertEqual(p.unsure.count, 2); XCTAssertTrue(p.unsure.allSatisfy { $0.candidates.sorted() == ["a", "b"] })
        XCTAssertTrue(p.new.isEmpty && p.gone.isEmpty)
        // 1000/1200 saved, 1200/1500 scanned: the same trap
        let c = entry(row(cp: 1000, hp: 80, ivs: x), "c"), d = entry(row(cp: 1200, hp: 90, ivs: x), "d")
        XCTAssertEqual(plan([row(cp: 1200, hp: 90, ivs: x), row(cp: 1500, hp: 100, ivs: x)], [c, d]).unsure.count, 2)
        // all exact: pairs by count as before
        let ex = plan([row(cp: 300, hp: 50, ivs: x), row(cp: 400, hp: 60, ivs: x)], [a, b])
        XCTAssertEqual(ex.same.count, 2)
        // one consistent assignment only (300 -> 350, 400 -> 500): paired
        let u = plan([row(cp: 350, hp: 55, ivs: x), row(cp: 500, hp: 70, ivs: x)], [a, b])
        XCTAssertEqual(u.unsure.count, 2); XCTAssertTrue(u.updated.isEmpty, "never applied automatically, even when only one assignment is consistent")
        XCTAssertEqual(u.unsure.first { $0.candidates == ["a"] }.map { u.scanned[$0.scanned].cp }, 350)
    }

    // M7
    func testM7IdenticalSavedOneHandCorrectedKeepsTheCorrectedOne() throws {
        let plain = entry(row(cp: 1000, ivs: x), "plain")
        let fixed = entry(row(cp: 1000, ivs: x), "fixed", corrections: Corrections(ivs: Fix(was: IVs(atk: 1, def: 1, hp: 1))))
        for order in [[plain, fixed], [fixed, plain]] {
            let p = plan([row(cp: 1000, ivs: x)], order)
            XCTAssertEqual(p.same, [BoxMerge.Pair(scanned: 0, savedId: "fixed")], "the corrected one survives whatever the saved order")
            XCTAssertEqual(p.gone, ["plain"])
            XCTAssertEqual(try BoxMerge.apply(p, to: order).map { $0.id }, ["fixed"])
        }
        XCTAssertTrue(plan([row(cp: 1000, ivs: x)], [plain, fixed], .partial).gone.isEmpty)
    }

    /// A row whose CP and HP are what the game gives for these IVs at this level.
    private func real(_ id: String, level: Double, ivs: IVs, read: Bool = true) -> ScanRow {
        let b = gm.byId[id]!.baseStats!
        var r = row(id, cp: cpAt(b, ivs, level), hp: hpAt(b, ivs, level), ivs: read ? ivs : nil, level: level); r.levelMax = level
        return r
    }

    // M12: a saved entry that was misread (no IVs, no level fits) meets a correctly read row of the same Pokémon
    private func misread(_ id: String = "heatmor", cp: Int = 64, hp: Int? = 92, flags: [String] = ["no-level-fits"]) -> ScanRow {
        var r = row(id, cp: cp, hp: hp, ivs: nil, level: nil, dust: nil, flags: flags); r.solveStatus = "none"; r.ivsRead = nil; return r
    }

    func testM12AMisreadSavedEntryIsOfferedAndTheGoodReadReplacesItsValues() throws {
        let bad = entry(misread(), "h")
        let good = row("heatmor", cp: 764, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2), level: 30, dust: 5000)
        let p = plan([good], [bad])
        XCTAssertEqual(p.unsure.first?.candidates, ["h"]); XCTAssertTrue(p.new.isEmpty); XCTAssertEqual(p.unsure.first?.kind, .misreadSaved)
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("h")], to: [bad])
        XCTAssertEqual(out.count, 1); XCTAssertEqual(out[0].id, "h"); XCTAssertEqual(out[0].firstSeen, date(0))
        XCTAssertEqual(out[0].row.cp, 764); XCTAssertEqual(out[0].row.ivs, IVs(atk: 7, def: 14, hp: 2)); XCTAssertEqual(out[0].row.level, 30); XCTAssertEqual(out[0].row.dust, 5000)
        XCTAssertTrue(out[0].row.flags.isEmpty, "the no-level-fits flag is cleared")
        XCTAssertEqual(out[0].row.solveStatus, "exact")
    }

    func testM12AlsoWhenTheGoodReadsCPIsLowerAndOnlyReadValuesAreCopied() throws {
        let bad = entry(misread(cp: 800), "h")
        let good = row("heatmor", cp: 764, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2), level: 30, dust: 5000)
        let p = plan([good], [bad])
        XCTAssertEqual(p.unsure.first?.candidates, ["h"], "a lower CP does not hide it")
        // a part of the good read that is missing does not wipe the saved value (M1): here the HP was not read this time
        var noHP = good; noHP.hp = nil
        let p2 = plan([noHP], [bad])
        XCTAssertEqual(p2.unsure.first?.candidates, ["h"], "an HP not read counts as the same HP")
        let out = try BoxMerge.apply(p2, resolutions: [0: .existing("h")], to: [bad])
        XCTAssertEqual(out[0].row.hp, 92); XCTAssertEqual(out[0].row.cp, 764)
    }

    func testM12KeepsHandCorrectionsOnFieldsThePersonSet() throws {
        var fixed = entry(misread(), "h")
        fixed.row.hp = 92; fixed.corrections = Corrections(hp: Fix(was: 91))
        let good = row("heatmor", cp: 764, hp: 91, ivs: IVs(atk: 7, def: 14, hp: 2), level: 30, dust: 5000)   // the scan reads the old wrong HP again
        let p = plan([good], [fixed])
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("h")], to: [fixed])
        XCTAssertEqual(out[0].row.hp, 92, "the corrected HP stays"); XCTAssertEqual(out[0].corrections.hp, Fix(was: 91)); XCTAssertEqual(out[0].row.cp, 764)
    }

    func testM12ItIsNewAddsTheRowAndLeavesTheSavedEntryEvenInAFullScan() throws {
        let bad = entry(misread(), "h")
        let good = row("heatmor", cp: 764, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2), level: 30, dust: 5000)
        let p = plan([good], [bad], .full)
        let out = try BoxMerge.apply(p, resolutions: [0: .new], to: [bad], makeID: { "n" })
        XCTAssertEqual(out.map { $0.id }, ["h", "n"], "the saved entry is left alone")
        XCTAssertEqual(out[0].row.cp, 64)
    }

    func testM12TwoSavedCandidatesAreBothListed() {
        let a = entry(misread(), "a"), b = entry(misread(cp: 66), "b")
        let good = row("heatmor", cp: 764, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2), level: 30, dust: 5000)
        XCTAssertEqual(plan([good], [a, b]).unsure.first?.candidates.sorted(), ["a", "b"])
    }

    func testM12NeedsTheSameSpeciesAndHPAndAnIVlessMisreadEntry() {
        let good = row("heatmor", cp: 764, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2), level: 30, dust: 5000)
        // another HP, another species, or a saved entry that was read properly: not offered
        XCTAssertEqual(plan([good], [entry(misread(hp: 100), "h")]).new, [0], "a different HP, and a power-up never lowers it")
        XCTAssertEqual(plan([good], [entry(misread("charmander"), "h")]).new, [0])
        let proper = entry(row("heatmor", cp: 900, hp: 92, ivs: IVs(atk: 1, def: 1, hp: 1)), "h")   // has IVs, different ones: another Pokémon
        XCTAssertEqual(plan([good], [proper]).new, [0])
    }

    // Review fold 2: leftover rows, M12 per candidate, same CP and HP with other IVs, evolutions with unread IVs

    func testTwoLeftoverRowsThatCouldBeOneSavedEntryAreBothAsked() throws {
        let s = entry(real("pikachu", level: 20, ivs: x), "S")
        let p = plan([real("pikachu", level: 21, ivs: x, read: false), real("pikachu", level: 22, ivs: x, read: false)], [s])
        XCTAssertEqual(p.unsure.map { $0.candidates }, [["S"], ["S"]]); XCTAssertTrue(p.new.isEmpty)
        XCTAssertThrowsError(try BoxMerge.apply(p, resolutions: [0: .existing("S"), 1: .existing("S")], to: [s]), "one saved entry cannot be taken by two rows") {
            XCTAssertEqual($0 as? BoxMerge.Failure, .chosenTwice(savedId: "S"))
        }
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("S"), 1: .new], to: [s], makeID: { "n" })
        XCTAssertEqual(out.map { $0.id }, ["S", "n"])
    }

    func testAPartReadAndAPowerUpOfOneSavedEntryAreBothAsked() throws {
        let b = gm.byId["pikachu"]!.baseStats!
        let ivsS = IVs(atk: 15, def: 14, hp: 15)
        let s = entry(real("pikachu", level: 30, ivs: ivsS), "S")
        let up = real("pikachu", level: 31, ivs: ivsS, read: false)
        let part = Int(String(s.row.cp).dropFirst())!   // a run of the saved CP's digits
        let p = plan([row(cp: part, hp: s.row.hp, ivs: nil), up], [s])
        _ = b
        XCTAssertEqual(p.unsure.map { $0.scanned }, [0, 1]); XCTAssertEqual(p.unsure.map { $0.candidates }, [["S"], ["S"]]); XCTAssertTrue(p.new.isEmpty)
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("S"), 1: .existing("S")], to: [s])
        XCTAssertEqual(out.count, 1); XCTAssertEqual(out[0].row.cp, up.cp, "the part read only marks it seen; the real read updates it")
    }

    func testItIsNewLeavesAMisreadCandidateWhenOtherCandidatesWerePresent() throws {
        let iv = IVs(atk: 7, def: 14, hp: 2)
        let plain = entry(real("heatmor", level: 30, ivs: iv), "P")
        let good = real("heatmor", level: 25, ivs: iv)
        let bad = entry(misread(hp: good.hp), "M")
        let p = plan([good], [plain, bad])
        XCTAssertEqual(p.unsure.first?.kind, .ambiguous); XCTAssertEqual(p.unsure.first?.candidates.sorted(), ["M", "P"])
        let out = try BoxMerge.apply(p, resolutions: [0: .new], to: [plain, bad], makeID: { "n" })
        XCTAssertEqual(out.map { $0.id }, ["M", "n"], "the misread entry stays; the plausible one follows M9 and goes")
    }

    func testItIsNewLeavesAMisreadCandidateOfAPartialRead() throws {
        let s = entry(row("heatmor", cp: 1982, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2)), "S")
        let bad = entry(misread(), "M")
        var partRead = row("heatmor", cp: 182, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2), flags: ["no-level-fits"]); partRead.solveStatus = "none"
        let p = plan([partRead], [s, bad])
        XCTAssertEqual(p.unsure.first?.kind, .partialRead); XCTAssertEqual(p.unsure.first?.misread, ["M"])
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [0: .new], to: [s, bad], makeID: { "n" }).map { $0.id }, ["M", "n"])
        let kept = try BoxMerge.apply(p, resolutions: [0: .new], to: [s, bad], makeID: { "n" })
        XCTAssertEqual(kept.first { $0.id == "M" }?.row.cp, 64, "the misread entry is left exactly as it was")
    }

    func testChoosingAMisreadCandidateReplacesItsUnreadValuesWhateverTheKind() throws {
        let plain = entry(row("heatmor", cp: 900, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2)), "P")
        let bad = entry(misread(), "M")
        let good = row("heatmor", cp: 764, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2), level: 30, dust: 5000)
        let out = try BoxMerge.apply(plan([good], [plain, bad]), resolutions: [0: .existing("M")], to: [plain, bad])
        XCTAssertEqual(out.first { $0.id == "M" }?.row.ivs, IVs(atk: 7, def: 14, hp: 2)); XCTAssertEqual(out.first { $0.id == "M" }?.row.cp, 764)
        // a part read with a misread candidate: whichever is chosen, the untrusted row only marks it seen
        let s = entry(row("heatmor", cp: 1982, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2)), "S")
        var partRead = row("heatmor", cp: 182, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2), flags: ["no-level-fits"]); partRead.solveStatus = "none"
        let p = plan([partRead], [s, bad])
        let m = try BoxMerge.apply(p, resolutions: [0: .existing("M")], to: [s, bad])
        XCTAssertNil(m.first { $0.id == "M" }?.row.ivs, "an untrusted row writes nothing: it only marks the entry seen")
        XCTAssertEqual(m.first { $0.id == "M" }?.row.cp, 64, "a part read never writes its CP")
        XCTAssertEqual(m.first { $0.id == "M" }?.lastSeen, date(5))
        let seen = try BoxMerge.apply(p, resolutions: [0: .existing("S")], to: [s, bad])
        XCTAssertEqual(seen.first { $0.id == "S" }?.row.cp, 1982)
    }

    func testSameCPAndHPWithOtherIVsIsAskedAboutNotNewPlusGone() throws {
        let a = entry(row(cp: 500, hp: 60, ivs: x), "A")
        let other = IVs(atk: 15, def: 15, hp: 14)
        let p = plan([row(cp: 500, hp: 60, ivs: other)], [a])
        XCTAssertEqual(p.unsure.first?.candidates, ["A"]); XCTAssertTrue(p.new.isEmpty); XCTAssertTrue(p.gone.isEmpty)
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("A")], to: [a])
        XCTAssertEqual(out.count, 1); XCTAssertEqual(out[0].row.ivs, x, "IVs never change in the game: neither read is guessed, the saved IVs are kept")
        XCTAssertEqual(out[0].lastSeen, date(5)); XCTAssertTrue(out[0].row.flags.contains(BoxMerge.ivsRescanFlag))
        XCTAssertTrue(out[0].row.needsCheck, "and it shows under to check")
    }

    func testSavedIVsThatWereNotAnExactReadAreReplacedByACleanRead() throws {
        var shaky = row(cp: 500, hp: 60, ivs: IVs(atk: 15, def: 15, hp: 14), flags: ["bars-unsettled"]); shaky.solveStatus = "corrected"
        let a = entry(shaky, "A")
        let p = plan([row(cp: 500, hp: 60, ivs: x)], [a])
        XCTAssertEqual(p.unsure.first?.candidates, ["A"])
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [0: .existing("A")], to: [a])[0].row.ivs, x)
    }

    func testSameCPAndHPWithOtherIVsOnAHandCorrectedEntryIsAskedAbout() throws {
        let corrected = try BoxMerge.correct(entry(row(cp: 500, hp: 60, ivs: IVs(atk: 15, def: 15, hp: 14)), "A"), with: .init(ivs: x), gameMaster: gm)
        let p = plan([row(cp: 500, hp: 60, ivs: IVs(atk: 14, def: 15, hp: 15))], [corrected])
        XCTAssertEqual(p.unsure.first?.candidates, ["A"]); XCTAssertTrue(p.gone.isEmpty)
        let kept = try BoxMerge.apply(p, resolutions: [0: .existing("A")], to: [corrected])
        XCTAssertEqual(kept[0].row.ivs, x, "a hand correction is never overwritten by a read that disagrees with it")
        XCTAssertNotNil(kept[0].corrections.ivs); XCTAssertTrue(kept[0].row.flags.contains(BoxMerge.ivsRescanFlag))
        // a different CP or HP is still something else
        XCTAssertEqual(plan([row(cp: 500, hp: 61, ivs: IVs(atk: 1, def: 1, hp: 1))], [entry(row(cp: 500, hp: 60, ivs: x), "A")]).new, [0])
    }

    func testAnEvolutionWithUnreadIVsIsAskedAboutItsPrecursor() throws {
        let machop = entry(real("machop", level: 15, ivs: x), "m")
        let machoke = real("machoke", level: 20, ivs: x, read: false)
        let p = plan([machoke], [machop])
        XCTAssertEqual(p.unsure.first?.candidates, ["m"]); XCTAssertTrue(p.new.isEmpty); XCTAssertTrue(p.gone.isEmpty)
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("m")], to: [machop])
        XCTAssertEqual(out.count, 1); XCTAssertEqual(out[0].row.speciesId, "machoke"); XCTAssertEqual(out[0].row.ivs, x, "unread IVs keep the saved ones")
        var lowHP = machoke; lowHP.hp = machop.row.hp! - 5
        XCTAssertEqual(plan([lowHP], [machop]).new, [0], "an HP lower than the saved one is not a power-up")
        XCTAssertEqual(plan([real("pikachu", level: 20, ivs: x, read: false)], [machop]).new, [0], "not an evolution of it")
    }

    // Second fold round: R1, R1b

    private func fragment(_ id: String = "heatmor", cp: Int, hp: Int? = 92, ivs: IVs? = IVs(atk: 7, def: 14, hp: 2)) -> ScanRow {
        var r = row(id, cp: cp, hp: hp, ivs: ivs, flags: ["no-level-fits"]); r.solveStatus = "none"; return r
    }

    func testAPartReadChosenForAMisreadEntryNeverWritesItsCP() throws {
        let bad = entry(misread(cp: 1982), "X")
        let p = plan([fragment(cp: 182)], [bad])
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("X")], to: [bad])
        XCTAssertEqual(out[0].row.cp, 1982, "the CP 182 is a fragment, not a read")
        XCTAssertNil(out[0].row.ivs, "an untrusted row writes nothing, not even the IVs it read"); XCTAssertEqual(out[0].lastSeen, date(5))
        XCTAssertNil(out[0].row.level); XCTAssertNil(out[0].row.dust)
    }

    func testAnEntryAlreadyUpdatedByAnotherRowIsOnlyMarkedSeenByAPartRead() throws {
        let bad = entry(misread(cp: 1982), "X")
        let real = row("heatmor", cp: 1982, hp: 92, ivs: IVs(atk: 7, def: 14, hp: 2), level: 30, dust: 5000)
        let p = plan([real, fragment(cp: 182)], [bad])
        XCTAssertEqual(p.updated.first?.reason, .ivsNowRead); XCTAssertEqual(p.unsure.map { $0.scanned }, [1])
        let out = try BoxMerge.apply(p, resolutions: [1: .existing("X")], to: [bad])
        XCTAssertEqual(out.count, 1); XCTAssertEqual(out[0].row.cp, 1982); XCTAssertEqual(out[0].row.level, 30)
    }

    func testTwoPartReadsMayShareOneEntryButTwoWritersMayNot() throws {
        let bad = entry(misread(cp: 1982), "X")
        let p = plan([fragment(cp: 182), fragment(cp: 198)], [bad])
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("X"), 1: .existing("X")], to: [bad])
        XCTAssertEqual(out.count, 1); XCTAssertEqual(out[0].row.cp, 1982)
        // two trusted rows that would each write to one entry are refused, with a message that does not steer to a duplicate
        let s = entry(row(cp: 500, hp: 60, ivs: x), "S")
        let q = plan([real("pikachu", level: 21, ivs: x, read: false), real("pikachu", level: 22, ivs: x, read: false)], [entry(real("pikachu", level: 20, ivs: x), "S")])
        XCTAssertThrowsError(try BoxMerge.apply(q, resolutions: [0: .existing("S"), 1: .existing("S")], to: [s])) {
            XCTAssertEqual($0.localizedDescription, "Two scanned Pokémon were matched to the same saved one. Change one of the answers.")
        }
    }


    // Third fold round: T1 to T5

    func testTwoFragmentsWithDifferentIVsGiveTheSameResultInEitherOrder() throws {
        let bad = entry(misread(cp: 1982), "X")
        let a = fragment(cp: 182, ivs: IVs(atk: 7, def: 14, hp: 2)), b = fragment(cp: 198, ivs: IVs(atk: 1, def: 2, hp: 3))
        let o1 = try BoxMerge.apply(plan([a, b], [bad]), resolutions: [0: .existing("X"), 1: .existing("X")], to: [bad])
        let o2 = try BoxMerge.apply(plan([b, a], [bad]), resolutions: [0: .existing("X"), 1: .existing("X")], to: [bad])
        XCTAssertEqual(o1, o2); XCTAssertNil(o1[0].row.ivs); XCTAssertEqual(o1[0].row.cp, 1982)
    }

    func testARowFlaggedNoLevelFitsIsNeverAutoPairedAsAPowerUpAnEvolutionOrIVsNowRead() throws {
        // powered up: a higher CP with the same IVs
        let s = entry(row(cp: 500, hp: 60, ivs: x), "S")
        let p = plan([fragment("pikachu", cp: 900, hp: 70, ivs: x)], [s])
        XCTAssertTrue(p.updated.isEmpty); XCTAssertEqual(p.unsure.map { $0.candidates }, [["S"]])
        XCTAssertEqual(try BoxMerge.apply(p, resolutions: [0: .existing("S")], to: [s])[0].row.cp, 500, "seen only")
        // IVs now read on a saved entry with none
        let none = entry(misread(cp: 500), "N")
        let q = plan([fragment(cp: 500, hp: 92, ivs: x)], [none])
        XCTAssertTrue(q.updated.isEmpty); XCTAssertEqual(q.unsure.map { $0.candidates }, [["N"]])
        XCTAssertNil(try BoxMerge.apply(q, resolutions: [0: .existing("N")], to: [none])[0].row.ivs)
        // an evolution
        let machop = entry(row("machop", cp: 400, hp: 70, ivs: x), "m")
        let e = plan([fragment("machoke", cp: 900, hp: 90, ivs: x)], [machop])
        XCTAssertTrue(e.updated.isEmpty); XCTAssertEqual(e.unsure.map { $0.candidates }, [["m"]])
        // Same (identical values, nothing written) stays automatic
        XCTAssertEqual(plan([fragment("pikachu", cp: 500, hp: 60, ivs: x)], [s]).same.count, 1)
    }

    func testTheCardAndApplyAgreeOnWhatAnAnswerDoes() throws {
        typealias E = BoxMerge.Effect
        // untrusted row, other IVs at the same CP and HP: seen only (it used to say "keeps the IVs")
        let s = entry(row(cp: 500, hp: 60, ivs: x), "S")
        var r = row(cp: 500, hp: 60, ivs: y, flags: ["no-level-fits"]); r.solveStatus = "none"
        let p = plan([r], [s])
        XCTAssertEqual(BoxMerge.effect(p, try XCTUnwrap(p.unsure.first), candidate: s, gameMaster: gm), E.seenOnly)
        let out = try BoxMerge.apply(p, resolutions: [0: .existing("S")], to: [s])
        XCTAssertEqual(out[0].row.ivs, x); XCTAssertFalse(out[0].row.flags.contains(BoxMerge.ivsRescanFlag), "seen only: no flag either")
        // trusted row, other IVs: keeps and flags
        let q = plan([row(cp: 500, hp: 60, ivs: y)], [s])
        XCTAssertEqual(BoxMerge.effect(q, q.unsure[0], candidate: s, gameMaster: gm), E.keepsIVsAndFlags)
        XCTAssertTrue(try BoxMerge.apply(q, resolutions: [0: .existing("S")], to: [s])[0].row.flags.contains(BoxMerge.ivsRescanFlag))
        // trusted row, ordinary candidate: writes
        let hidden = IVs(atk: 9, def: 10, hp: 11)
        let t = entry(real("pikachu", level: 20, ivs: hidden, read: false), "T")
        let u = plan([real("pikachu", level: 21, ivs: hidden, read: false), real("pikachu", level: 22, ivs: hidden, read: false)], [t])
        XCTAssertEqual(BoxMerge.effect(u, u.unsure[0], candidate: t, gameMaster: gm), E.replacesValues)
        // an extra twin and a part read: seen only
        let two = plan([row(cp: 500, hp: 60, ivs: x), row(cp: 500, hp: 60, ivs: x)], [s])
        XCTAssertEqual(two.unsure.map { $0.kind }, [.extraTwin]); XCTAssertEqual(BoxMerge.effect(two, two.unsure[0], candidate: s, gameMaster: gm), E.seenOnly)
    }

    func testACleanReadThatReplacedAGuessStopsCountingAsAGuess() throws {
        var g = row(cp: 500, hp: 60, ivs: y); g.ivsGuess = y; g.solveStatus = "guess"
        let a = entry(g, "A")
        let z = IVs(atk: 3, def: 4, hp: 5)
        let p = plan([row(cp: 500, hp: 60, ivs: x)], [a])
        XCTAssertEqual(BoxMerge.effect(p, p.unsure[0], candidate: a, gameMaster: gm), .replacesIVs)
        let o = try BoxMerge.apply(p, resolutions: [0: .existing("A")], to: [a])
        XCTAssertEqual(o[0].row.ivs, x); XCTAssertNil(o[0].row.ivsGuess)
        let p2 = plan([row(cp: 500, hp: 60, ivs: z)], [o[0]])
        XCTAssertEqual(BoxMerge.effect(p2, p2.unsure[0], candidate: o[0], gameMaster: gm), .keepsIVsAndFlags, "a later disagreeing clean read keeps the saved IVs and flags it")
        XCTAssertEqual(try BoxMerge.apply(p2, resolutions: [0: .existing("A")], to: [o[0]])[0].row.ivs, x)
    }

    func testTheRescanFlagGoesOnAHandCorrectionAndSurvivesAnAutomaticUpdate() throws {
        let s = entry(row(cp: 500, hp: 60, ivs: x), "S")
        let flagged = try BoxMerge.apply(plan([row(cp: 500, hp: 60, ivs: y)], [s]), resolutions: [0: .existing("S")], to: [s])[0]
        XCTAssertTrue(flagged.row.flags.contains(BoxMerge.ivsRescanFlag))
        XCTAssertFalse(try BoxMerge.correct(flagged, with: .init(ivs: y), gameMaster: gm).row.flags.contains(BoxMerge.ivsRescanFlag), "a hand correction of the IVs decides them")
        XCTAssertFalse(BoxMerge.markChecked(flagged).row.flags.contains(BoxMerge.ivsRescanFlag))
        // a power-up rescan with the saved IVs updates the entry and does not resolve the disagreement
        let p = plan([row(cp: 600, hp: 65, ivs: x, level: 22)], [flagged])
        XCTAssertEqual(p.unsure.first?.kind, .poweredUp)
        let after = try BoxMerge.apply(p, resolutions: [0: .existing("S")], to: [flagged])[0]
        XCTAssertEqual(after.row.cp, 600); XCTAssertTrue(after.row.flags.contains(BoxMerge.ivsRescanFlag))
    }

    // Fourth fold round: E9

    func testAnUntrustedRowPairedAsSameWritesNothingButLastSeen() throws {
        var e = entry(row("pikachu", cp: 500, hp: 60, ivs: x), "S")
        e.megaWhenScanned = true
        let p = plan([fragment("pikachu", cp: 500, hp: 60, ivs: x)], [e])
        XCTAssertEqual(p.same.count, 1)
        let out = try BoxMerge.apply(p, to: [e])
        XCTAssertEqual(out[0].megaWhenScanned, true, "no Mega mark change"); XCTAssertEqual(out[0].lastSeen, date(5))
        XCTAssertEqual(out[0].row, e.row)
    }
}

final class FoldLibraryTests: XCTestCase {
    private var dir: URL!
    private var lib: BoxLibrary!
    override func setUpWithError() throws { dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-fold-\(UUID().uuidString)"); lib = BoxLibrary(root: dir) }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    private func date(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 3600) }

    // L1
    func testL1PreviousIsTheContentCurrentBeforeTheLatestChange() throws {
        try lib.commit(account: "a", entries: [], reason: .scan, note: "scan", now: date(1))           // 1
        try lib.commit(account: "a", entries: [], reason: .edit, note: "edit", now: date(2))           // 2
        try lib.commit(account: "a", entries: [], reason: .restore, note: "Restored version 1", restoredFrom: 1, now: date(3))   // 3
        try lib.commit(account: "a", entries: [], reason: .scan, note: "scan 2", now: date(4))         // 4
        XCTAssertEqual(try lib.previousVersion(account: "a")?.seq, 3, "version 3 holds the content that was current before version 4")
    }
}
