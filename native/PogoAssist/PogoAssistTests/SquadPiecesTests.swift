import XCTest
import SwiftUI
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// Pass 2-6: the words and shapes the squad screens draw that can be read without a device: the status chips (rule 35), the Shadow naming, the strip's short names and the strength line's
/// runs.
final class SquadPiecesTests: XCTestCase {
    private static var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    /// Any build of Greg's real box of 22 Oct 2026 (a Best row only needs one to count as served by a build).
    private static let sampleBuild: BoxAdvice.Build = {
        let gm = try! GameMaster.bundled()
        let text = try! String(contentsOf: root.appendingPathComponent("fixtures/greg-2026-10-22.box.csv"), encoding: .utf8)
        let entries = BoxCSVReader.entries(csv: text, gm: gm)
        let rows = entries.enumerated().map { i, e in var r = e.row; r.index = i + 1; return r }
        return BoxAdvice.make(from: try! CoreEngine().advise(rows: rows, scanDate: Date(timeIntervalSince1970: 1_790_000_000)), entries: entries).builds[0]
    }()
    private func best(_ kind: HubSquads.BestStatus.Kind, needsUpgrade: Bool = false, detail: String? = nil, build: Bool = false, availability: String = "", rotation: String? = nil) -> HubSquads.BestRow {
        var r = HubSquads.BestRow(key: "x", name: "X", speciesId: "x", tier: "A", roles: [], types: [], availability: availability, rotationLine: rotation)
        r.status = .init(kind: kind, needsUpgrade: needsUpgrade, detail: detail)
        if build { r.build = Self.sampleBuild }
        return r
    }

    func testChipsCarryAStatusEachWithTheCostOrTheMeterOrTheMonth() {
        let today = "2026-11-07"
        let cost = MyPokemon.Cost(value: "206k", currency: .dust)
        // In the box: Ready at full strength, else the cost with its icon, else "Upgrade" with no cost, else "No build".
        XCTAssertEqual(StatusChipModel.chips(best: best(.inBox, build: true), mark: .fullStrength, today: today), [.ready])
        XCTAssertEqual(StatusChipModel.chips(best: best(.inBox, needsUpgrade: true, build: true), mark: .upgrade(cost: cost, label: "x"), today: today).map(\.text), ["↑ 206k"])
        XCTAssertEqual(StatusChipModel.chips(best: best(.inBox, needsUpgrade: true, build: true), mark: .upgrade(cost: cost, label: "x"), today: today).first?.currency, .dust)
        XCTAssertEqual(StatusChipModel.chips(best: nil, mark: .upgrade(cost: nil, label: "x"), today: today).map(\.text), ["↑ Upgrade"])
        XCTAssertEqual(StatusChipModel.chips(best: best(.inBox, needsUpgrade: true, detail: "no build for this"), mark: .none, today: today).map(\.text), ["↑ No build"])
        XCTAssertEqual(StatusChipModel.chips(best: nil, mark: .none, today: today), [])
        // The box lacks it: Get now with the meter when the obtain text gives one; Not now with the month.
        XCTAssertEqual(StatusChipModel.chips(best: best(.canGetNow, detail: "Easy. Wild", availability: "Easy. Wild"), mark: .none, today: today).map(\.text), ["◎ Get now", "▮▯▯ Easy"])
        XCTAssertEqual(StatusChipModel.chips(best: best(.canGetNow, detail: "Medium. T5 raids", availability: "Medium. T5 raids"), mark: .none, today: today).map(\.text), ["◎ Get now", "▮▮▯ Medium"])
        XCTAssertEqual(StatusChipModel.chips(best: best(.canGetNow, detail: "Raid boss now", availability: "Raid boss now", rotation: "Raid boss now"), mark: .none, today: today).map(\.text), ["◎ Get now"])
        XCTAssertEqual(StatusChipModel.chips(best: best(.notAvailableNow, detail: "Raids from 20 Dec", rotation: "Raids from 20 Dec"), mark: .none, today: today).map(\.text), ["◌ Not now · Dec"])
        XCTAssertEqual(StatusChipModel.chips(best: best(.notAvailableNow, detail: "not on the schedule"), mark: .none, today: today).map(\.text), ["◌ Not now"])
        // Swap chips.
        XCTAssertEqual(StatusChipModel.swap(slot: 5, moves: false).text, "⇄ Slot 5")
        XCTAssertEqual(StatusChipModel.swap(slot: 5, moves: true).text, "⇄ Empty slot")
        // Colour is never the only sign: every chip starts with its sign.
        for c in [StatusChipModel.ready, .noBuild, .getNow, .notNow(when: nil), .swap(slot: 1, moves: false)] { XCTAssertTrue("✓↑◎◌⇄".contains(c.text.first!), c.text) }
    }

    func testAMarkedRowInAnotherSlotGainsASwapChip() {
        let row = PickerRowModel(id: "a", name: "A", ticked: false, chips: [.ready], spoken: "A")
        let marked = PickerRowModel.marking([row]) { _ in 5 }
        XCTAssertEqual(marked[0].chips.map(\.text), ["✓ Ready", "⇄ Slot 5"])
        XCTAssertTrue(marked[0].spoken.hasSuffix("in slot 5, choosing it swaps the two"), "VoiceOver keeps the words")
        XCTAssertEqual(PickerRowModel.marking([row], moves: true) { _ in 2 }[0].chips.last?.text, "⇄ Empty slot")
    }

    func testAShadowIsNamedAsTheBoxNamesItEverywhere() {
        XCTAssertEqual(SquadWords.boxName("Shadow Gardevoir"), "Gardevoir (Shadow)")
        XCTAssertEqual(SquadWords.boxName("Gardevoir (Shadow)"), "Gardevoir (Shadow)")
        XCTAssertEqual(SquadWords.boxName("Mega Gardevoir"), "Mega Gardevoir", "a name already in front stays")
        XCTAssertEqual(SquadWords.boxName("Rayquaza (Mega)"), "Mega Rayquaza", "the game master's bracket goes in front (H3)")
        XCTAssertEqual(SquadWords.boxName("Charizard (Mega X)"), "Mega Charizard X")
        XCTAssertEqual(SquadWords.boxName("Groudon (Primal)"), "Primal Groudon")
        XCTAssertEqual(SquadWords.boxName("Shadowy Thing"), "Shadowy Thing")
        XCTAssertEqual(SquadWords.spokenBox("Slot 2 of 6, Heavy hitter, Shadow Reshiram, Dark and Fire"), "Slot 2 of 6, Heavy hitter, Reshiram (Shadow), Dark and Fire")
    }

    /// J14 (H3): the chip drops only the "(Shadow)" bracket; every other form stays, so two forms of one species never both read the same.
    func testTheStripChipDropsOnlyTheShadowBracketAndKeepsEveryOtherForm() {
        // The names the app produces: the game master's, through `boxName`, then the chip's own cut.
        func chip(_ gameMasterName: String) -> String { SquadStripChip.shortName(SquadWords.boxName(gameMasterName)) }
        XCTAssertEqual(chip("Gardevoir (Shadow)"), "Gardevoir")
        XCTAssertEqual(chip("Shadow Gardevoir"), "Gardevoir")
        XCTAssertEqual(chip("Zamazenta (Crowned Shield)"), "Zamazenta (Crowned Shield)")
        XCTAssertEqual(chip("Giratina (Origin)"), "Giratina (Origin)")
        XCTAssertEqual(chip("Giratina (Altered)"), "Giratina (Altered)")
        XCTAssertNotEqual(chip("Giratina (Origin)"), chip("Giratina (Altered)"), "two forms of one species stay apart")
        XCTAssertEqual(chip("Rayquaza (Mega)"), "Mega Rayquaza")
        XCTAssertEqual(chip("Groudon (Primal)"), "Primal Groudon")
        XCTAssertEqual(chip("Charizard (Mega X)"), "Mega Charizard X")
        XCTAssertEqual(chip("Charizard (Mega Y)"), "Mega Charizard Y")
        XCTAssertNotEqual(chip("Charizard (Mega X)"), chip("Charizard (Mega Y)"), "Mega X and Mega Y never both read Charizard")
        XCTAssertEqual(SquadStripChip.shortName("Empty"), "Empty")
    }

    func testTheStripSaysNotInYourBoxOnlyForAPokemonTheBoxLacks() {
        var lacking = SlotCardModel(id: 2, role: "Heavy hitter", palette: .violet, emptyOutline: .clear, disc: "+", name: "Zacian", status: .toGet, spoken: "", identifier: "s")
        lacking.notInBox = true
        let owned = SlotCardModel(id: 3, role: "Heavy hitter", palette: .violet, emptyOutline: .clear, disc: "+", name: "Xerneas", status: .ready, spoken: "", identifier: "s")
        let chips = [lacking, owned].map { SquadStripChip(card: $0, selected: 3) }
        XCTAssertTrue(chips[0].notInBox); XCTAssertFalse(chips[1].notInBox)
        XCTAssertTrue(chips[0].spoken.hasSuffix("not in your box"), chips[0].spoken)
        XCTAssertTrue(chips[1].spoken.hasSuffix("editing") && !chips[1].spoken.contains("not in your box"), chips[1].spoken)
    }

    /// H7: an empty slot's strip chip is grey, never the role or the screen's palette.
    func testAnEmptySlotsStripChipIsGrey() {
        let empty = SlotCardModel(id: 4, role: "Bulky hitter", palette: .teal, emptyOutline: .clear, disc: "+", name: nil, status: .empty, spoken: "", identifier: "s")
        let filled = SlotCardModel(id: 5, role: "Bulky hitter", palette: .teal, emptyOutline: .clear, disc: "+", name: "Blissey", status: .ready, spoken: "", identifier: "s")
        let chips = [empty, filled].map { SquadStripChip(card: $0, selected: 0) }
        XCTAssertTrue(chips[0].empty); XCTAssertFalse(chips[1].empty)
        XCTAssertEqual(chips[0].name, "Empty")
    }

    /// H5: each status once on a picker row, as the panel: an upgrade keeps the cost at the head and its chip reads "↑ Upgrade"; a Ready row has the chip and no tick at the head.
    func testAPickerRowShowsEachStatusOnce() {
        let cost = MyPokemon.Cost(value: "206k", currency: .dust)
        let up = PickerRowModel(id: "u", name: "Xerneas", ticked: false, mark: .upgrade(cost: cost, label: "Power up"), chips: [.upgrade(cost)], spoken: "")
        XCTAssertEqual(up.headMark, up.mark, "the cost badge stays at the head")
        XCTAssertEqual(up.pickerChips.map(\.text), ["↑ Upgrade"], "and the chip does not repeat the figure")
        let ready = PickerRowModel(id: "r", name: "Staraptor", ticked: false, mark: .fullStrength, chips: [.ready], spoken: "")
        XCTAssertEqual(ready.headMark, SquadMark.none, "no tick where the chip says Ready")
        XCTAssertEqual(ready.pickerChips.map(\.text), ["✓ Ready"])
        let noChip = PickerRowModel(id: "n", name: "Gym row", ticked: false, mark: .fullStrength, spoken: "")
        XCTAssertEqual(noChip.headMark, .fullStrength, "a row with no Ready chip keeps its tick")
        let noBuild = PickerRowModel(id: "b", name: "Copy", ticked: false, mark: .upgrade(cost: nil, label: "x"), chips: [.noBuild], spoken: "")
        XCTAssertEqual(noBuild.pickerChips.map(\.text), ["↑ No build"])
    }

    /// H10, J6: a toast goes when the screen that showed it disappears, a plain message as well as one with an Undo; another screen's toast stays; "Undone" belongs to the screen of the
    /// action it undid.
    @MainActor
    func testAToastGoesWithItsScreen() {
        final class Owner {}
        let mine = Owner(), other = Owner()
        let presenter = ToastPresenter()
        var undone = 0
        presenter.show("Current squad replaced", owner: ObjectIdentifier(mine), action: ToastAction(label: "Undo", perform: { undone += 1; return true }))
        presenter.dismiss(owner: ObjectIdentifier(other))
        XCTAssertEqual(presenter.message, "Current squad replaced", "another screen's disappearing leaves it")
        presenter.dismiss(owner: ObjectIdentifier(mine))
        XCTAssertNil(presenter.message); XCTAssertNil(presenter.action, "its own screen's takes it away, Undo and all")
        presenter.perform()
        XCTAssertEqual(undone, 0, "and its Undo can no longer run")
        // A plain message with an owner goes too (the skipped-duplicate message).
        presenter.show("Squad unset", owner: ObjectIdentifier(mine))
        presenter.dismiss(owner: ObjectIdentifier(other))
        XCTAssertEqual(presenter.message, "Squad unset")
        presenter.dismiss(owner: ObjectIdentifier(mine))
        XCTAssertNil(presenter.message)
        // Undo: "Undone" inherits the owner, so it leaves with the screen as well.
        presenter.show("Current squad replaced", owner: ObjectIdentifier(mine), action: ToastAction(label: "Undo", perform: { undone += 1; return true }))
        presenter.perform()
        XCTAssertEqual(undone, 1)
        XCTAssertEqual(presenter.message, "Undone")
        presenter.dismiss(owner: ObjectIdentifier(other))
        XCTAssertEqual(presenter.message, "Undone", "another screen leaves it")
        presenter.dismiss(owner: ObjectIdentifier(mine))
        XCTAssertNil(presenter.message, "the screen's own takes the Undone toast away too")
    }

    /// J9: an Undo that undid nothing says nothing: the toast just goes.
    @MainActor
    func testAFailedUndoSaysNothing() {
        let presenter = ToastPresenter()
        presenter.show("Current squad replaced", action: ToastAction(label: "Undo", perform: { false }))
        presenter.perform()
        XCTAssertNil(presenter.message, "no \"Undone\" when nothing was undone")
        XCTAssertNil(presenter.action)
    }

    /// H11: the title's (i) says where the earlier squads are shown and promises no way back after a Delete.
    func testTheTitleInfoDoesNotPromiseAWayBackAfterDelete() {
        let current = SquadInfo.tabs(noun: "squads").first { $0.term == "Current" }?.text ?? ""
        XCTAssertTrue(current.contains("earlier current squads are listed under it"), current)
        XCTAssertFalse(current.contains("Delete current squad"), current)
        XCTAssertFalse(current.contains("brings it back"), current)
    }

    func testTheStrengthLineIsOneLabelWithTheFiguresBold() {
        let s = SquadStrength(kind: .damage, now: 0.41, after: 0.87, scored: 6, total: 6)
        let runs = SquadStrengthLine.runs(s)
        XCTAssertEqual(runs.map(\.text).joined(), "Squad strength 41% of best · 87% after upgrades")
        XCTAssertEqual(runs.filter(\.bold).map(\.text), ["41%", "87%"])
        let noAfter = SquadStrength(kind: .damage, now: 0.41, after: 0.41, scored: 6, total: 6)
        XCTAssertEqual(SquadStrengthLine.runs(noAfter).map(\.text).joined(), "Squad strength 41% of best", "the after part only when the bar draws its faint part")
        let best = SquadStrength.bestSquad(reference: [0.5, 0.5])
        XCTAssertEqual(SquadStrengthLine.runs(best).map(\.text).joined(), "Squad strength 100%")
        XCTAssertEqual(s.percent, 41)
    }
}
