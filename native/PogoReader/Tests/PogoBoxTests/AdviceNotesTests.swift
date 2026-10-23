import XCTest
@testable import PogoBox

/// The Advice panel's message about being a spare and its keep / transfer verdict (`BoxAdvice.adviceNotes`).
final class AdviceNotesTests: XCTestCase {
    private func build(_ entry: String, _ target: String) -> BoxAdvice.Build {
        BoxAdvice.Build(entryId: entry, title: "Eevee", cp: 300, level: 20, ivs: nil, targetId: target.lowercased(), targetName: target, powerUp: false, formChange: false,
                        viaMega: false, needsDynamax: false, spares: 0, areas: ["Raids"], tier: "B", targetLevel: nil, dust: 0, candy: 0, xl: 0, pvp: nil, score: 1, steps: [])
    }
    /// Hygiene's lines are "CP n, a/d/h" or "CP n, IVs unknown".
    private func dup(count: Int = 65, name: String = "Eevee", keep: [String], transfer: [String], keepIds: [String], transferIds: [String] = ["t"]) -> BoxAdvice.Duplicate {
        BoxAdvice.Duplicate(name: name, count: count, keep: keep, transfer: transfer, keepIds: keepIds, transferIds: transferIds)
    }
    private func entry(builds: [BoxAdvice.Build] = [], spareFor: [BoxAdvice.Build] = [], dup: BoxAdvice.Duplicate? = nil, id: String) -> BoxAdvice.ForEntry {
        BoxAdvice.ForEntry(builds: builds, spareFor: spareFor, duplicateOf: dup, keep: dup?.keepIds.contains(id) ?? false, keepIndex: dup?.keepIds.firstIndex(of: id))
    }

    func testSpareSentenceJoinsOneTwoAndThreeTargets() {
        func spare(_ targets: [String]) -> String? { BoxAdvice.adviceNotes(entry(spareFor: targets.map { build("x", $0) }, id: "me"), name: "Eevee").spare }
        XCTAssertEqual(spare(["Umbreon"]), "No build for this copy: you already have another Eevee planned for Umbreon.")
        XCTAssertEqual(spare(["Umbreon", "Vaporeon"]), "No build for this copy: you already have another Eevee planned for Umbreon and Vaporeon.")
        XCTAssertEqual(spare(["Umbreon", "Vaporeon", "Glaceon"]), "No build for this copy: you already have another Eevee planned for Umbreon, Vaporeon and Glaceon.")
        XCTAssertEqual(spare(["Umbreon", "Umbreon"]), "No build for this copy: you already have another Eevee planned for Umbreon.", "a target named twice is named once")
        // A target that is the Pokémon itself (a power-up) is not named.
        XCTAssertEqual(BoxAdvice.adviceNotes(entry(spareFor: [build("x", "Moltres")], id: "me"), name: "Moltres").spare, "No build for this copy: you already have another Moltres planned.")
        XCTAssertEqual(BoxAdvice.adviceNotes(entry(spareFor: [build("x", "Moltres"), build("x", "Umbreon")], id: "me"), name: "Moltres").spare,
                       "No build for this copy: you already have another Moltres planned for Umbreon.")
        XCTAssertNil(spare([]))
    }

    func testUnderItsOwnBuildsTheSpareLineIsSingularOrPluralAndThereIsNoVerdict() {
        let mine = [build("me", "Blastoise")]
        // The hygiene rule would transfer this copy, but it carries a build: no verdict at all.
        let d = dup(keep: ["CP 1, 15/15/15"], transfer: ["CP 2, 1/1/1"], keepIds: ["other"], transferIds: ["me"])
        let n1 = BoxAdvice.adviceNotes(entry(builds: mine, spareFor: [build("x", "Umbreon")], dup: d, id: "me"), name: "Eevee")
        XCTAssertEqual(n1.spare, "Also a spare for Umbreon: a better copy is already planned.")
        XCTAssertNil(n1.verdict)
        let n2 = BoxAdvice.adviceNotes(entry(builds: mine, spareFor: [build("x", "Umbreon"), build("x", "Glaceon")], dup: d, id: "me"), name: "Eevee")
        XCTAssertEqual(n2.spare, "Also a spare for Umbreon and Glaceon: better copies are already planned.")
        XCTAssertNil(n2.verdict)
        XCTAssertEqual(BoxAdvice.adviceNotes(entry(builds: mine, spareFor: [build("x", "Eevee")], id: "me"), name: "Eevee").spare, "Also a spare: a better copy is already planned.")
        XCTAssertNil(BoxAdvice.adviceNotes(entry(builds: mine, id: "me"), name: "Eevee").spare)
    }

    func testEveryKeepVerdictSaysWhy() {
        func verdict(_ d: BoxAdvice.Duplicate, id: String = "me") -> String? { BoxAdvice.adviceNotes(entry(dup: d, id: id), name: "Eevee").verdict }
        // Won on IVs: known and strictly above every copy it did not keep.
        XCTAssertEqual(verdict(dup(keep: ["CP 1960, 13/15/14"], transfer: ["CP 2500, 10/10/10", "CP 900, 15/15/9"], keepIds: ["me"])),
                       "One of 65 Eevee in your box. **Keep it:** it has your best IVs of the 65.")
        // Two kept (legendary), won on IVs.
        XCTAssertEqual(verdict(dup(count: 6, keep: ["CP 1, 15/15/15", "CP 2, 14/15/15"], transfer: ["CP 3, 1/1/1"], keepIds: ["me", "you"])),
                       "One of 6 Eevee in your box. **Keep it:** it has one of your two best IV sets of the 6.")
        // Unknown IVs: it won on CP.
        XCTAssertEqual(verdict(dup(keep: ["CP 3000, IVs unknown"], transfer: ["CP 2500, IVs unknown"], keepIds: ["me"])),
                       "One of 65 Eevee in your box. **Keep it:** it is your strongest of the 65.")
        // A tie on IVs goes to CP in the rule, but a transferred copy may have the higher CP: it still reads "best IVs", never "strongest".
        XCTAssertEqual(verdict(dup(keep: ["CP 2000, 15/15/15"], transfer: ["CP 1000, 15/15/15"], keepIds: ["me"])),
                       "One of 65 Eevee in your box. **Keep it:** it has your best IVs of the 65.")
        XCTAssertEqual(verdict(dup(keep: ["CP 1000, 15/15/15"], transfer: ["CP 3000, 15/15/15"], keepIds: ["me"])),
                       "One of 65 Eevee in your box. **Keep it:** it has your best IVs of the 65.")
        // A transferred copy with the higher CP and lower IVs: the kept one still has the best IVs.
        XCTAssertEqual(verdict(dup(keep: ["CP 1000, 15/15/15"], transfer: ["CP 3000, 10/10/10"], keepIds: ["me"])),
                       "One of 65 Eevee in your box. **Keep it:** it has your best IVs of the 65.")
        // Unknown IVs on the kept copy: it can only be the strongest.
        XCTAssertEqual(verdict(dup(keep: ["CP 1000, IVs unknown"], transfer: ["CP 500, IVs unknown"], keepIds: ["me"])),
                       "One of 65 Eevee in your box. **Keep it:** it is your strongest of the 65.")
        // Two kept, won on CP.
        XCTAssertEqual(verdict(dup(keep: ["CP 2000, IVs unknown", "CP 1900, IVs unknown"], transfer: ["CP 100, IVs unknown"], keepIds: ["me", "you"])),
                       "One of 65 Eevee in your box. **Keep it:** it is one of your two strongest of the 65.")
        // The second of two kept reads its own line.
        XCTAssertEqual(verdict(dup(keep: ["CP 2000, 15/15/15", "CP 1900, IVs unknown"], transfer: ["CP 100, 1/1/1"], keepIds: ["you", "me"])),
                       "One of 65 Eevee in your box. **Keep it:** it is one of your two strongest of the 65.")
        // Never the bare "Keep this one."
        XCTAssertFalse(verdict(dup(keep: ["CP 1, 1/1/1"], transfer: ["CP 2, 1/1/1"], keepIds: ["me"]))!.contains("Keep this one"))
    }

    func testTransferAndNoDuplicateAndABuiltCopyThatIsKept() {
        let d = dup(keep: ["CP 1, 15/15/15"], transfer: ["CP 2, 1/1/1"], keepIds: ["best"], transferIds: ["me"])
        XCTAssertEqual(BoxAdvice.adviceNotes(entry(dup: d, id: "me"), name: "Eevee").verdict, "One of 65 Eevee in your box. **The advisor would transfer this one.**")
        XCTAssertTrue(entry(dup: d, id: "me").transfersWithNoBuild)
        XCTAssertFalse(entry(builds: [build("me", "Blastoise")], dup: d, id: "me").transfersWithNoBuild, "a built copy is never told to transfer")
        XCTAssertFalse(entry(dup: d, id: "best").transfersWithNoBuild)
        XCTAssertEqual(BoxAdvice.adviceNotes(entry(id: "me"), name: "Eevee"), BoxAdvice.AdviceNotes(spare: nil, verdict: nil))
        XCTAssertNil(BoxAdvice.adviceNotes(entry(builds: [build("best", "Blastoise")], dup: d, id: "best"), name: "Eevee").verdict, "the kept copy with its build shows the build only")
    }
}
