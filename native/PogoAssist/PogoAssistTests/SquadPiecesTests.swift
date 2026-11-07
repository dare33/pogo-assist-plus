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
        XCTAssertEqual(SquadWords.boxName("Mega Gardevoir"), "Mega Gardevoir", "a Mega keeps the game's name")
        XCTAssertEqual(SquadWords.boxName("Shadowy Thing"), "Shadowy Thing")
        XCTAssertEqual(SquadWords.spokenBox("Slot 2 of 6, Heavy hitter, Shadow Reshiram, Dark and Fire"), "Slot 2 of 6, Heavy hitter, Reshiram (Shadow), Dark and Fire")
    }

    func testTheStripChipDropsTheBracketedFormButKeepsAMega() {
        XCTAssertEqual(SquadStripChip.shortName("Gardevoir (Shadow)"), "Gardevoir")
        XCTAssertEqual(SquadStripChip.shortName("Zamazenta (Crowned Shield)"), "Zamazenta")
        XCTAssertEqual(SquadStripChip.shortName("Mega Gardevoir"), "Mega Gardevoir")
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
