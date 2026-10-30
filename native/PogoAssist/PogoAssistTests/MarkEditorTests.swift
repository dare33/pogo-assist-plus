import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// The Pokémon page's marks answer a tap at once and save behind (`MarkEditor`): rapid taps settle on the last state, at most one save is in flight, and a failed
/// save puts the marks back. The box is a stand-in that applies each saved edit as the data model would.
@MainActor final class MarkEditorTests: XCTestCase {
    private final class Store {
        var entry: BoxEntry
        var edits = [BoxMerge.Edit]()
        var inFlight = 0, mostInFlight = 0
        var delay: Duration = .milliseconds(150)
        var fail = false
        init(_ e: BoxEntry) { entry = e }
        func save(_ edit: BoxMerge.Edit) async -> Bool {
            inFlight += 1; mostInFlight = max(mostInFlight, inFlight)
            defer { inFlight -= 1 }
            try? await Task.sleep(for: delay)
            if fail { return false }
            edits.append(edit)
            entry = try! BoxMerge.correct(entry, with: edit, gameMaster: try! GameMaster.bundled())
            return true
        }
    }

    private func store() -> Store {
        let gm = try! GameMaster.bundled(), sp = gm.byId["scyther"]!
        let nf = GameMaster.nameAndForm(sp.name)
        let r = ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: sp.id, dex: sp.dex, cp: 1500, hp: 120, ivs: IVs(atk: 10, def: 11, hp: 12), ivsRead: nil, ivsGuess: nil,
                        level: 20, levelMax: 20, dust: 2500, solveStatus: "exact", flags: [], frames: [])
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        return Store(BoxEntry(id: "e", row: r, firstSeen: d, lastSeen: d))
    }

    private func tap(_ editor: MarkEditor, _ store: Store, _ make: @escaping (ScanRow) -> BoxMerge.Edit) {
        editor.apply(make, entry: { store.entry }, save: { await store.save($0) })
    }

    private func settled(_ editor: MarkEditor) async {
        let end = Date().addingTimeInterval(5)
        while editor.wanted != nil, Date() < end { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func testAMarkShowsItsNewStateAtOnceBeforeAnythingIsSaved() async {
        let s = store(), editor = MarkEditor(settle: 0.05)
        tap(editor, s) { PokemonPage.toggleDynamax($0) }
        XCTAssertEqual(editor.wanted?.dynamax, true, "drawn on the tap")
        XCTAssertNil(s.entry.row.dynamax); XCTAssertTrue(s.edits.isEmpty, "nothing saved yet")
        await settled(editor)
        XCTAssertEqual(s.edits, [BoxMerge.Edit(dynamax: .on)])
        XCTAssertEqual(s.entry.row.dynamax, true)
    }

    func testADoubleTapLeavesTheMarkAsItWasAndSavesNothing() async {
        let s = store(), editor = MarkEditor(settle: 0.1)
        tap(editor, s) { PokemonPage.toggleDynamax($0) }
        tap(editor, s) { PokemonPage.toggleDynamax($0) }
        XCTAssertNotEqual(editor.wanted?.dynamax, true, "off again, drawn at once")
        await settled(editor)
        XCTAssertTrue(s.edits.isEmpty, "an even number of taps saves nothing")
        XCTAssertNil(s.entry.row.dynamax)
    }

    func testABurstOfTapsIsOneSaveInTheLastState() async {
        let s = store(), editor = MarkEditor(settle: 0.1)
        for _ in 0..<5 { tap(editor, s) { PokemonPage.toggleDynamax($0) } }
        tap(editor, s) { PokemonPage.toggleShadow($0) }
        await settled(editor)
        XCTAssertEqual(s.edits.count, 1)
        XCTAssertEqual(s.entry.row.dynamax, true); XCTAssertEqual(s.entry.row.shadow, 1)
    }

    func testTapsDuringASaveGoAsOneLaterSaveBuiltFromTheLatestValuesWithOnlyOneInFlight() async {
        let s = store(), editor = MarkEditor(settle: 0.05)
        s.delay = .milliseconds(400)
        tap(editor, s) { PokemonPage.toggleDynamax($0) }
        try? await Task.sleep(for: .milliseconds(200))   // the first save is under way
        XCTAssertTrue(s.edits.isEmpty); XCTAssertEqual(s.inFlight, 1)
        // While it is in flight: Lucky on, then off, then on; Shadow on then Purified on (which clears Shadow).
        tap(editor, s) { PokemonPage.toggle(.lucky, $0) }
        tap(editor, s) { PokemonPage.toggle(.lucky, $0) }
        tap(editor, s) { PokemonPage.toggle(.lucky, $0) }
        tap(editor, s) { PokemonPage.toggleShadow($0) }
        tap(editor, s) { PokemonPage.toggle(.purified, $0) }
        XCTAssertEqual(editor.wanted?.shadow, 2, "Purified on clears Shadow, drawn at once")
        await settled(editor)
        XCTAssertEqual(s.mostInFlight, 1, "never two saves at once")
        XCTAssertEqual(s.edits.count, 2)
        XCTAssertEqual(s.edits[0], BoxMerge.Edit(dynamax: .on))
        XCTAssertEqual(s.edits[1], BoxMerge.Edit(lucky: true, shadow: .purified), "one edit from the latest values")
        XCTAssertEqual(s.entry.row.lucky, true); XCTAssertEqual(s.entry.row.shadow, 2); XCTAssertEqual(s.entry.row.dynamax, true)
    }

    func testAChipTappedWhileItIsAlreadyChosenSavesNothing() async {
        let s = store(), editor = MarkEditor(settle: 0.05)
        tap(editor, s) { PokemonPage.toggle(.bestBuddy, $0) }
        await settled(editor)
        XCTAssertEqual(s.edits.count, 1)
        // Choosing a Mega level that is already stored is no change.
        tap(editor, s) { BoxMerge.Edit(details: PokemonPage.setting(megaLevel: .base, $0.details)) }
        await settled(editor)
        tap(editor, s) { BoxMerge.Edit(details: PokemonPage.setting(megaLevel: .base, $0.details)) }
        XCTAssertNil(editor.wanted, "the chip already chosen: nothing waits")
        await settled(editor)
        XCTAssertEqual(s.edits.count, 2)
    }

    func testAFailedSaveBringsTheMarksBackToTheSavedRow() async {
        let s = store(), editor = MarkEditor(settle: 0.05)
        s.fail = true
        tap(editor, s) { PokemonPage.toggleDynamax($0) }
        XCTAssertEqual(editor.wanted?.dynamax, true)
        await settled(editor)
        XCTAssertNil(editor.wanted, "the shown state is the saved row again")
        XCTAssertNil(s.entry.row.dynamax)
        // And the next tap starts from the saved row.
        s.fail = false
        tap(editor, s) { PokemonPage.toggleDynamax($0) }
        await settled(editor)
        XCTAssertEqual(s.entry.row.dynamax, true)
    }
}
