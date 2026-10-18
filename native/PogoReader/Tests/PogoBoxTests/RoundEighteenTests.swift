import XCTest
@testable import PogoBox
@testable import PogoReader

/// Round 18, merge: a Pokémon saved twice across its Mega state (W3), a part read resolved by its HP (W1), IVs that are not a clean read (W2), and the opening card (W4).
final class RoundEighteenTests: XCTestCase {
    let gm = try! GameMaster.bundled()
    func date(_ d: Int) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + Double(d) * 86_400) }
    func row(_ id: String, cp: Int, hp: Int?, ivs: IVs?, flags: [String] = [], status: String = "exact") -> ScanRow {
        let nf = GameMaster.nameAndForm(gm.byId[id]?.name ?? id)
        return ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: id, dex: gm.byId[id]?.dex, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil, level: ivs == nil ? nil : 20, levelMax: ivs == nil ? nil : 20,
                       dust: 1000, solveStatus: ivs == nil ? "unknown-ivs" : status, flags: flags, frames: [])
    }
    func entry(_ r: ScanRow, _ id: String, corrections: Corrections = Corrections()) -> BoxEntry { BoxEntry(id: id, row: r, firstSeen: date(0), lastSeen: date(0), corrections: corrections) }
    func plan(_ s: [ScanRow], _ v: [BoxEntry], _ k: BoxStore.Kind = .full) -> BoxMerge.Plan { BoxMerge.plan(scanned: s, into: v, kind: k, scanDate: date(5), gameMaster: gm) }
    func save(_ p: BoxMerge.Plan, _ res: [Int: BoxMerge.Resolution], _ v: [BoxEntry]) throws -> [BoxEntry] {
        try BoxMerge.apply(p, resolutions: res, keepGone: BoxMerge.keepSet(plan: p, resolutions: res, markedForRemoval: []), to: v)
    }

    // MARK: W3
    let sIV = IVs(atk: 15, def: 15, hp: 14)
    func staraptorBox() -> [BoxEntry] { [entry(row("staraptor", cp: 2819, hp: 167, ivs: sIV), "base"), entry(row("staraptor_mega", cp: 3970, hp: 167, ivs: sIV), "mega")] }

    func testW3TheSameStaraptorSavedAsBaseAndAsMegaIsOneQuestionNotAnUnseenEntry() throws {
        let box = staraptorBox()
        for scanned in [row("staraptor_mega", cp: 3970, hp: 167, ivs: sIV), row("staraptor", cp: 2819, hp: 167, ivs: sIV)] {
            let p = plan([scanned], box)
            XCTAssertEqual(p.unsure.count, 1); XCTAssertEqual(p.unsure[0].kind, .megaPair); XCTAssertEqual(p.unsure[0].candidates, ["base", "mega"])
            XCTAssertTrue(p.gone.isEmpty && p.new.isEmpty && p.same.isEmpty, "neither entry is paired quietly, neither is listed as not seen")
            XCTAssertTrue(BoxMerge.goneReport(p, resolutions: [0: .existing("base")]).gone.isEmpty)
        }
    }

    func testW3JoiningKeepsOneEntryWithBaseValuesAndTheMegaMark() throws {
        var box = staraptorBox()
        box[1].corrections = Corrections(ivs: Fix(was: IVs(atk: 14, def: 15, hp: 14)))
        let p = plan([row("staraptor_mega", cp: 3970, hp: 167, ivs: sIV)], box)
        let out = try save(p, [0: .existing("base")], box)
        XCTAssertEqual(out.map { $0.id }, ["base"]); XCTAssertEqual(out[0].row.cp, 2819, "base values")
        XCTAssertEqual(out[0].megaWhenScanned, true); XCTAssertNil(out[0].corrections.ivs, "round 21: joining never changes the base entry's hand corrections, so the Mega entry's are not copied in")
        // a base-form scan joins and refreshes the base entry, no Mega mark
        let q = plan([row("staraptor", cp: 2819, hp: 167, ivs: sIV)], box)
        let out2 = try save(q, [0: .existing("base")], box)
        XCTAssertEqual(out2.map { $0.id }, ["base"]); XCTAssertNil(out2[0].megaWhenScanned)
        // keeping both removes nothing
        XCTAssertEqual(try save(p, [0: .leaveOut], box).map { $0.id }, ["base", "mega"])
        // a different HP or different IVs is not the same Pokémon: no question
        XCTAssertTrue(plan([row("staraptor_mega", cp: 3970, hp: 167, ivs: sIV)], [box[0], entry(row("staraptor_mega", cp: 3970, hp: 160, ivs: sIV), "m2")]).unsure.allSatisfy { $0.kind != .megaPair })
    }

    // MARK: W1
    let cIV = IVs(atk: 10, def: 11, hp: 10)
    func partial(_ cp: Int, hp: Int?, id: String = "moltres") -> ScanRow {
        var r = row(id, cp: cp, hp: hp, ivs: nil, flags: ["no-level-fits"]); r.ivsRead = nil; r.solveStatus = "unknown-ivs"; return r
    }

    func testW1APartReadResolvedByItsHPIsMatchedWithoutAQuestion() throws {
        let saved = entry(row("moltres", cp: 1901, hp: 129, ivs: cIV), "m")
        let p = plan([partial(901, hp: 129)], [saved])
        XCTAssertTrue(p.unsure.isEmpty); XCTAssertEqual(p.same.map { $0.savedId }, ["m"]); XCTAssertEqual(p.partMatches.map { $0.savedId }, ["m"])
        XCTAssertTrue(p.gone.isEmpty && p.new.isEmpty)
        let out = try save(p, [:], [saved])
        XCTAssertEqual(out[0].row.cp, 1901, "nothing is written"); XCTAssertEqual(out[0].row.ivs, cIV)
        // HP one off still resolves; two off does not
        XCTAssertTrue(plan([partial(901, hp: 128)], [saved]).unsure.isEmpty)
        XCTAssertTrue(plan([partial(901, hp: 127)], [saved]).partMatches.isEmpty, "two off is not matched")
    }

    func testW1StaysAQuestionWhenAnyConditionIsMissing() {
        let a = entry(row("moltres", cp: 1901, hp: 129, ivs: cIV), "a"), b = entry(row("moltres", cp: 2901, hp: 129, ivs: IVs(atk: 1, def: 2, hp: 3)), "b")
        XCTAssertEqual(plan([partial(901, hp: 129)], [a, b]).unsure.count, 1, "two saved candidates")
        XCTAssertEqual(plan([partial(901, hp: nil)], [a]).unsure.count, 1, "HP unread")
        XCTAssertEqual(plan([partial(701, hp: 129)], [a]).new.count + plan([partial(701, hp: 129)], [a]).unsure.count, 1, "not a run of the candidate's digits")
        // the candidate is also read properly by another row of this scan: today's question, unchanged
        let both = plan([partial(901, hp: 129), row("moltres", cp: 1901, hp: 129, ivs: cIV)], [a])
        XCTAssertEqual(both.unsure.count, 1); XCTAssertTrue(both.partMatches.isEmpty)
        // a candidate that is itself flagged no-level-fits is not trusted
        var flagged = a; flagged.row.flags = ["no-level-fits"]
        XCTAssertEqual(plan([partial(901, hp: 129)], [flagged]).unsure.count, 1)
        // two part reads that could be the same entry
        XCTAssertEqual(plan([partial(901, hp: 129), partial(1901 - 1000, hp: 129)], [a]).unsure.count, 2)
    }

    // MARK: W2
    func testW2SolverCorrectedIVsAtTheSameCPAndHPAreSameWhenThereIsOneSavedEntry() throws {
        let saved = entry(row("tympole", cp: 623, hp: 108, ivs: IVs(atk: 6, def: 11, hp: 14)), "t")
        let guess = row("tympole", cp: 623, hp: 108, ivs: IVs(atk: 5, def: 10, hp: 13), flags: ["ivs-corrected-from-6/9/14"])
        let p = plan([guess], [saved], .partial)
        XCTAssertTrue(p.unsure.isEmpty); XCTAssertEqual(p.same.map { $0.savedId }, ["t"]); XCTAssertTrue(p.updated.isEmpty)
        let out = try save(p, [:], [saved])
        XCTAssertEqual(out[0].row.ivs, IVs(atk: 6, def: 11, hp: 14)); XCTAssertFalse(out[0].row.flags.contains(BoxMerge.ivsRescanFlag))
        // a CLEAN read of different IVs at the same CP and HP is still asked
        XCTAssertEqual(plan([row("tympole", cp: 623, hp: 108, ivs: IVs(atk: 5, def: 10, hp: 13))], [saved], .partial).unsure.count, 1)
        // two saved candidates are still asked
        let other = entry(row("tympole", cp: 623, hp: 108, ivs: IVs(atk: 1, def: 2, hp: 3)), "t2")
        XCTAssertEqual(plan([guess], [saved, other], .partial).unsure.count, 1)
    }

    func testW2TheOwnersFidoughPairIsStillAskedForCleanReads() {
        let a = IVs(atk: 15, def: 4, hp: 10), b = IVs(atk: 15, def: 11, hp: 12)
        func f(_ i: IVs) -> ScanRow { row("fidough", cp: 768, hp: 89, ivs: i) }
        let p = plan([f(a), f(a)], [entry(f(a), "a"), entry(f(b), "b")])
        XCTAssertEqual(p.unsure.count, 1); XCTAssertEqual(p.unsure[0].kind, .extraTwin)
    }

    // MARK: W4
    private let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)

    /// The first card of run15 (Rayquaza CP 4262 HP 190) is on screen while the appraisal opens: readings with no bars, one with unsettled bars (9/9/9), then the settled 13/12/14.
    /// It was two rows; it is one stay.
    func testW4TheFirstCardHeldWhileTheAppraisalOpensIsOneRow() throws {
        let out = try ScanPipeline.process(replay: Fixture.url("run15-opening-card.replay.jsonl"), engine: sharedEngine, paging: hint)
        let rayquaza = out.scan.rows.filter { $0.name == "Rayquaza" }
        XCTAssertEqual(rayquaza.count, 1, "was two rows")
        XCTAssertEqual(rayquaza[0].ivs, IVs(atk: 13, def: 12, hp: 14)); XCTAssertEqual(out.scan.rows.first?.name, "Rayquaza")
        XCTAssertTrue(rayquaza[0].flags.contains("absorbed-fragment:4262"))
        XCTAssertEqual(rayquaza[0].frames.count, 9)
    }
}
