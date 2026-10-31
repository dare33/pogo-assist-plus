import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The Pokémon page shows the edited copy's family's advice at once and the whole box's when it is ready. That is only allowed where the two are the same answer:
/// these tests work out both for Greg's box (about 2,100 Pokémon) after real mark edits and compare every field the page reads.
final class FamilyAdviceTests: XCTestCase {
    private static let gm = try! GameMaster.bundled()
    private static var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private static let when = Date(timeIntervalSince1970: 1_790_000_000)

    /// The box and its advice, worked out once for the whole class.
    private static let box: [BoxEntry] = {
        let text = try! String(contentsOf: root.appendingPathComponent("fixtures/greg-2026-10-22.box.csv"), encoding: .utf8)
        return BoxCSVReader.entries(csv: text, gm: gm)
    }()
    private static let baseAdvice: BoxAdvice = {
        let rows = box.enumerated().map { i, e in var r = e.row; r.index = i + 1; return r }
        return BoxAdvice.make(from: try! sharedEngine.advise(rows: rows, scanDate: when), entries: box)
    }()

    private func whole(_ entries: [BoxEntry]) throws -> BoxAdvice {
        let rows = entries.enumerated().map { i, e in var r = e.row; r.index = i + 1; return r }
        return BoxAdvice.make(from: try sharedEngine.advise(rows: rows, scanDate: Self.when), entries: entries)
    }

    private func edited(_ entries: [BoxEntry], _ id: String, _ edit: BoxMerge.Edit) throws -> [BoxEntry] {
        try entries.map { $0.id == id ? try BoxMerge.correct($0, with: edit, gameMaster: Self.gm) : $0 }
    }

    /// One copy of each family: the families with the most copies, and some chosen for their shape (an Eevee tree, a species with Alolan and Galarian forms, a
    /// Mega-capable line, a legendary that keeps two, a species with a Shadow form).
    private func chosenCopies() -> [BoxEntry] {
        let biggest = Dictionary(grouping: Self.box, by: { $0.row.dex ?? 0 }).values.sorted { ($0.count, $1[0].row.dex ?? 0) > ($1.count, $0[0].row.dex ?? 0) }.prefix(4).map { $0[0] }
        let wanted: Set<Int> = [133, 25, 448, 147, 384, 52]   // Eevee, Pikachu, Lucario, Dratini, Rayquaza, Meowth (the four biggest lines are added to these)
        var out = Array(biggest)
        for d in wanted.sorted() { if let e = Self.box.first(where: { $0.row.dex == d }), !out.contains(where: { $0.id == e.id }) { out.append(e) } }
        return out
    }

    private let edits: [(String, (ScanRow) -> BoxMerge.Edit)] = [
        ("Dynamax", { PokemonPage.toggleDynamax($0) }),
        ("Shadow", { PokemonPage.toggleShadow($0) }),
        ("Lucky", { PokemonPage.toggle(.lucky, $0) }),
        ("Purified", { PokemonPage.toggle(.purified, $0) }),
        ("Gigantamax", { PokemonPage.toggle(.gigantamax, $0) }),
    ]

    /// For several families and each kind of mark edit: the family's advice merged over the box's old advice equals the whole box's advice after the edit, on every list
    /// and every per-Pokémon table. The gaps (box-wide) are the one field not compared: they are kept as they were, and the page does not read them.
    func testFamilyAdviceEqualsTheWholeBoxAdviceForTheEditedFamily() throws {
        let copies = chosenCopies()
        XCTAssertGreaterThanOrEqual(copies.count, 8, "enough families to mean something")
        var gapsDiffered = [String]()
        var checked = 0
        for (n, copy) in copies.enumerated() {
            // One kind of edit per family, going round the five, so each kind is tried on more than one family (a whole-box advise takes seconds in a debug build).
            do {
                let (name, make) = edits[n % edits.count]
                let edit = make(copy.row)
                let after = try edited(Self.box, copy.id, edit)
                let wholeAfter = try whole(after)
                let family = BoxAdvice.family(of: copy, in: after, gm: Self.gm)
                let merged = try XCTUnwrap(try BoxAdvice.afterEdit(of: copy.id, base: Self.baseAdvice, entries: after, scanDate: Self.when, engine: sharedEngine, gm: Self.gm))
                let label = "\(copy.row.title) (\(family.count) in the family) after \(name)"
                XCTAssertEqual(merged.builds, wholeAfter.builds, "builds (verdicts, spares, IV ranks in the build lines): \(label)")
                XCTAssertEqual(merged.duplicates, wholeAfter.duplicates, "duplicates: \(label)")
                XCTAssertEqual(merged.unresolved, wholeAfter.unresolved, "unresolved: \(label)")
                XCTAssertEqual(merged.leagues, wholeAfter.leagues, "league ratings, ranks and IV ranks: \(label)")
                XCTAssertEqual(merged.fit, wholeAfter.fit, "fit tags (Summary rows): \(label)")
                XCTAssertEqual(merged.bestOf, wholeAfter.bestOf, "best-copy tags: \(label)")
                XCTAssertEqual(merged.spareBuilds, wholeAfter.spareBuilds, "spares: \(label)")
                XCTAssertEqual(merged.version, wholeAfter.version)
                // What the page reads for the edited copy and its family, one by one.
                for e in family {
                    XCTAssertEqual(merged.entries(for: e.id), wholeAfter.entries(for: e.id), "entries(for:) \(e.id): \(label)")
                    XCTAssertEqual(merged.leagues(for: e.id), wholeAfter.leagues(for: e.id), "leagues(for:) \(e.id): \(label)")
                    XCTAssertEqual(merged.fit(for: e.id), wholeAfter.fit(for: e.id), "fit(for:) \(e.id): \(label)")
                    XCTAssertEqual(merged.bestOf(for: e.id), wholeAfter.bestOf(for: e.id), "bestOf(for:) \(e.id): \(label)")
                }
                if merged.gaps != wholeAfter.gaps { gapsDiffered.append(label) }
                checked += 1
            }
        }
        print("family advice: \(checked) edits compared; gaps differ after: \(gapsDiffered)")
    }

    /// The family result is for the page only: it leaves the old advice untouched and takes nothing from outside the family.
    func testTheFamilyPartChangesNothingOutsideTheFamily() throws {
        let copy = try XCTUnwrap(Self.box.first { $0.row.dex == 448 })
        let after = try edited(Self.box, copy.id, PokemonPage.toggleShadow(copy.row))
        let family = Set(BoxAdvice.family(of: copy, in: after, gm: Self.gm).map(\.id))
        let merged = try XCTUnwrap(try BoxAdvice.afterEdit(of: copy.id, base: Self.baseAdvice, entries: after, scanDate: Self.when, engine: sharedEngine, gm: Self.gm))
        XCTAssertLessThan(family.count, 60, "a family is a small part of the box")
        XCTAssertEqual(merged.gaps, Self.baseAdvice.gaps)
        for e in Self.box where !family.contains(e.id) {
            XCTAssertEqual(merged.leagues(for: e.id), Self.baseAdvice.leagues(for: e.id))
            XCTAssertEqual(merged.fit(for: e.id), Self.baseAdvice.fit(for: e.id))
            XCTAssertEqual(merged.bestOf(for: e.id), Self.baseAdvice.bestOf(for: e.id))
        }
        XCTAssertEqual(merged.builds.filter { !family.contains($0.entryId) }, Self.baseAdvice.builds.filter { !family.contains($0.entryId) })
        XCTAssertNil(try BoxAdvice.afterEdit(of: "not-there", base: Self.baseAdvice, entries: after, scanDate: Self.when, engine: sharedEngine, gm: Self.gm))
    }

    func testTheFamilyHoldsTheEvolutionLine() throws {
        let ids = { (dex: Int) -> Set<Int> in
            let copy = Self.box.first { $0.row.dex == dex }!   // the fixture box holds every line asked about here
            return Set(BoxAdvice.family(of: copy, in: Self.box, gm: Self.gm).map { $0.row.dex ?? 0 })
        }
        XCTAssertTrue(ids(133).isSuperset(of: [133, 134, 135]), "an Eevee tree: Eevee, Vaporeon, Jolteon")
        XCTAssertEqual(ids(448), [448], "Lucario, with no Riolu in the box")
        XCTAssertLessThan(ids(4).count, 5, "Charmander's line only")
    }

    /// A row with no dex number falls back to the game master's for its species, so its family still holds the other copies of that number.
    func testARowWithNoDexNumberStillFindsItsFamily() throws {
        var copy = try XCTUnwrap(Self.box.first { $0.row.dex == 133 })   // Eevee
        copy.row.dex = nil
        var box = Self.box
        box[box.firstIndex { $0.id == copy.id }!] = copy
        let family = BoxAdvice.family(of: copy, in: box, gm: Self.gm)
        XCTAssertGreaterThan(family.count, 30, "the 65 Eevee in the fixture box")
        // And the other way round: a copy whose own dex is missing is found by the others' number.
        let other = try XCTUnwrap(Self.box.first { $0.row.dex == 133 && $0.id != copy.id })
        XCTAssertTrue(BoxAdvice.family(of: other, in: box, gm: Self.gm).contains { $0.id == copy.id })
        // And the advice itself: with no dex number on any Eevee or Pikachu row, the family result after an edit still equals the whole box's.
        for i in box.indices where [133, 25].contains(box[i].row.dex) { box[i].row.dex = nil }
        let base = try whole(box)
        let target = try XCTUnwrap(box.first { Self.gm.byId[$0.row.speciesId]?.dex == 133 })
        let after = try edited(box, target.id, BoxMerge.Edit(lucky: true))
        let merged = try XCTUnwrap(try BoxAdvice.afterEdit(of: target.id, base: base, entries: after, scanDate: Self.when, engine: sharedEngine, gm: Self.gm))
        let truth = try whole(after)
        XCTAssertEqual(merged.builds, truth.builds); XCTAssertEqual(merged.duplicates, truth.duplicates); XCTAssertEqual(merged.leagues, truth.leagues)
        XCTAssertEqual(merged.fit, truth.fit); XCTAssertEqual(merged.bestOf, truth.bestOf); XCTAssertEqual(merged.spareBuilds, truth.spareBuilds)
    }

    /// Marks already on several families (Shadow, Purified, Lucky, Dynamax), then edits that turn them off and swap them, each family result chained on the one
    /// before (as the app chains its jobs), the whole box's advice compared after every step.
    func testMarkedFamiliesTurnedOffAndSwappedInAChain() throws {
        let pick = [448, 25, 147, 384].compactMap { d in Self.box.first { $0.row.dex == d } }   // Lucario, Pikachu, Dratini, Rayquaza
        XCTAssertEqual(pick.count, 4)
        var box = Self.box
        func set(_ id: String, _ edit: BoxMerge.Edit) throws { box = try edited(box, id, edit) }
        try set(pick[0].id, BoxMerge.Edit(shadow: .shadow))
        try set(pick[1].id, BoxMerge.Edit(shadow: .purified))
        try set(pick[2].id, BoxMerge.Edit(lucky: true))
        try set(pick[3].id, BoxMerge.Edit(dynamax: .on))
        var base = try whole(box)     // the box as it stands with the marks on
        let steps: [(Int, BoxMerge.Edit, String)] = [
            (0, BoxMerge.Edit(shadow: .neither), "Shadow turned off"),
            (1, BoxMerge.Edit(shadow: .shadow), "Purified swapped for Shadow"),
            (2, BoxMerge.Edit(lucky: false), "Lucky turned off"),
            (3, BoxMerge.Edit(dynamax: .off), "Dynamax turned off"),
        ]
        for (n, edit, name) in steps {
            let id = pick[n].id
            box = try edited(box, id, edit)
            let copy = try XCTUnwrap(box.first { $0.id == id })
            let merged = try XCTUnwrap(try BoxAdvice.afterEdit(of: id, base: base, entries: box, scanDate: Self.when, engine: sharedEngine, gm: Self.gm))
            let truth = try whole(box)
            let label = "\(copy.row.title): \(name) (step \(n + 1) of the chain)"
            XCTAssertEqual(merged.builds, truth.builds, "builds: \(label)")
            XCTAssertEqual(merged.duplicates, truth.duplicates, "duplicates: \(label)")
            XCTAssertEqual(merged.leagues, truth.leagues, "leagues: \(label)")
            XCTAssertEqual(merged.fit, truth.fit, "fit: \(label)")
            XCTAssertEqual(merged.bestOf, truth.bestOf, "bestOf: \(label)")
            XCTAssertEqual(merged.spareBuilds, truth.spareBuilds, "spares: \(label)")
            XCTAssertEqual(merged.unresolved, truth.unresolved, "unresolved: \(label)")
            base = merged   // the next family job is chained on this one, not on the whole box's advice
        }
    }

    /// The policy that keeps a family result from showing on a box it was not made for.
    func testTheHeldFamilyAdviceShowsOnlyForItsAccountAndBoxVersion() {
        var hold = FamilyAdviceHold()
        let advice = BoxAdvice(builds: [], gaps: [], duplicates: [], unresolved: ["x"])
        hold.set(advice, account: "a", seq: 5)
        XCTAssertEqual(hold.advice(account: "a", seq: 5), advice)
        XCTAssertNil(hold.advice(account: "a", seq: 6), "the box was replaced by a later version (a scan, a restore)")
        XCTAssertNil(hold.advice(account: "b", seq: 5), "another account")
        XCTAssertNil(hold.advice(account: nil, seq: nil), "no account")
        hold.clear()   // a failed whole-box advise, a switch of account, a box with no account
        XCTAssertNil(hold.advice(account: "a", seq: 5))
    }
}
