import XCTest
@testable import PogoBox
import PogoReader

/// Pass 3, the Pokémon page's own rules (CONCEPTS 8, 16, 17, 18): the edit each mark and chip makes, the moves a copy shows, and the sentences the cards use.
final class PokemonPageTests: XCTestCase {
    private let gm = P23.gm
    typealias Page = PokemonPage

    private func row(dynamax: Bool? = nil, shadow: Int? = nil, lucky: Bool? = nil, gigantamax: Bool? = nil, details: CopyDetails? = nil) -> ScanRow {
        var r = P23.entry("c", "eevee").row
        r.dynamax = dynamax; r.shadow = shadow; r.lucky = lucky; r.gigantamax = gigantamax; r.details = details
        return r
    }

    // MARK: marks

    func testTheDynamaxAndShadowMarksToggleBetweenOnAndOff() {
        XCTAssertEqual(Page.toggleDynamax(row()).dynamax, .on)
        XCTAssertEqual(Page.toggleDynamax(row(dynamax: true)).dynamax, .off)
        XCTAssertEqual(Page.toggleShadow(row()).shadow, .shadow)
        XCTAssertEqual(Page.toggleShadow(row(shadow: 2)).shadow, .shadow, "Purified becomes Shadow in one tap: one field")
        XCTAssertEqual(Page.toggleShadow(row(shadow: 1)).shadow, .neither)
    }

    func testShadowOnClearsPurifiedAndTheReverseThroughTheModel() throws {
        let e = P23.entry("c", "eevee")
        let shadow = try BoxMerge.correct(e, with: Page.toggleShadow(e.row), gameMaster: gm)
        XCTAssertEqual(shadow.row.shadow, 1)
        XCTAssertFalse(Page.isOn(.purified, shadow.row))
        let purified = try BoxMerge.correct(shadow, with: Page.toggle(.purified, shadow.row), gameMaster: gm)
        XCTAssertEqual(purified.row.shadow, 2)
        XCTAssertTrue(Page.isOn(.purified, purified.row))
        let back = try BoxMerge.correct(purified, with: Page.toggleShadow(purified.row), gameMaster: gm)
        XCTAssertEqual(back.row.shadow, 1, "Shadow on clears Purified")
        let off = try BoxMerge.correct(back, with: Page.toggleShadow(back.row), gameMaster: gm)
        XCTAssertEqual(off.row.shadow, 0, "off is marked neither by hand")
    }

    func testTheGigantamaxChipShowsOnlyWhileDynamaxIsOnAndImpliesIt() throws {
        XCTAssertEqual(Page.flags(for: row()), [.lucky, .purified, .bestBuddy, .weatherBoosted])
        XCTAssertEqual(Page.flags(for: row(dynamax: true)), [.lucky, .purified, .bestBuddy, .weatherBoosted, .gigantamax])
        let e = P23.entry("c", "eevee")
        let g = try BoxMerge.correct(e, with: Page.toggle(.gigantamax, e.row), gameMaster: gm)
        XCTAssertEqual(g.row.gigantamax, true)
        XCTAssertEqual(g.row.dynamax, true, "Gigantamax on implies Dynamax")
        let off = try BoxMerge.correct(g, with: Page.toggleDynamax(g.row), gameMaster: gm)
        XCTAssertNil(off.row.dynamax)
        XCTAssertNil(off.row.gigantamax, "Dynamax off clears Gigantamax")
    }

    func testTheOtherChipsStoreInTheRowAndCleanUpAfterThemselves() throws {
        var e = P23.entry("c", "eevee")
        for flag in [PokemonPage.Flag.lucky, .bestBuddy, .weatherBoosted] {
            XCTAssertFalse(Page.isOn(flag, e.row))
            e = try BoxMerge.correct(e, with: Page.toggle(flag, e.row), gameMaster: gm)
            XCTAssertTrue(Page.isOn(flag, e.row), flag.rawValue)
        }
        XCTAssertEqual(e.row.lucky, true)
        XCTAssertEqual(e.row.details, CopyDetails(bestBuddy: true, weatherBoosted: true))
        for flag in [PokemonPage.Flag.lucky, .bestBuddy, .weatherBoosted] { e = try BoxMerge.correct(e, with: Page.toggle(flag, e.row), gameMaster: gm) }
        XCTAssertNil(e.row.lucky)
        XCTAssertNil(e.row.details, "all cleared leaves no details stored")
    }

    // MARK: moves

    func testMovesShowTheDefaultsUntilOneIsStored() {
        let none = Page.moves(nil, speciesId: "eevee", gm: gm)
        XCTAssertEqual(none, AdvancedDetails.Defaults(fast: "QUICK_ATTACK", charged1: "DIG", charged2: nil))
        let stored = Page.moves(CopyDetails(fastMove: "TACKLE", chargedMove: "SWIFT", chargedMove2: "DIG"), speciesId: "eevee", gm: gm)
        XCTAssertEqual(stored, AdvancedDetails.Defaults(fast: "TACKLE", charged1: "SWIFT", charged2: "DIG"))
    }

    func testChoosingAMoveKeepsTheRulesOfTheSecondChargedMove() {
        // Picking does not save the defaults of the other slots.
        let fast = Page.choosing("TACKLE", for: .fast, details: nil, speciesId: "eevee", gm: gm)
        XCTAssertEqual(fast, CopyDetails(fastMove: "TACKLE"))
        // The second charged move cannot equal the first (the shown default counts as the first).
        XCTAssertEqual(Page.choosing("DIG", for: .charged2, details: nil, speciesId: "eevee", gm: gm), CopyDetails(), "Dig is the default first move")
        let second = Page.choosing("SWIFT", for: .charged2, details: nil, speciesId: "eevee", gm: gm)
        XCTAssertEqual(second.chargedMove2, "SWIFT")
        // Making the first equal to the second sends the second back to Not unlocked.
        let moved = Page.choosing("SWIFT", for: .charged, details: second, speciesId: "eevee", gm: gm)
        XCTAssertEqual(moved.chargedMove, "SWIFT")
        XCTAssertNil(moved.chargedMove2)
        // "Not unlocked" clears it.
        XCTAssertNil(Page.choosing(nil, for: .charged2, details: second, speciesId: "eevee", gm: gm).chargedMove2)
        // A move the species cannot learn changes nothing.
        XCTAssertEqual(Page.choosing("BLAST_BURN", for: .charged, details: nil, speciesId: "eevee", gm: gm), CopyDetails())
        XCTAssertEqual(Page.choosing("AIR_SLASH", for: .fast, details: nil, speciesId: "eevee", gm: gm), CopyDetails())
    }

    func testMaxMoveLevelsStartAtOneAndDashAndAnImpossibleLevelChangesNothing() {
        XCTAssertEqual(Page.level(of: .attack, nil), 1)
        XCTAssertEqual(Page.level(of: .guardMove, nil), 0)
        XCTAssertEqual(Page.levels(of: .attack), [1, 2, 3])
        XCTAssertEqual(Page.levels(of: .spirit), [0, 1, 2, 3])
        var d = Page.setting(3, of: .attack, nil)
        d = Page.setting(2, of: .guardMove, d)
        XCTAssertEqual(d, CopyDetails(maxAttack: 3, maxGuard: 2))
        XCTAssertEqual(Page.setting(0, of: .attack, d), d, "Max Attack has no dash")
        XCTAssertNil(Page.setting(0, of: .guardMove, d).maxGuard, "the dash stores nothing")
        XCTAssertEqual(Page.setting(4, of: .spirit, d), d)
    }

    func testTheMegaLevelStartsOnNotYetAndStoresNothingForIt() {
        XCTAssertEqual(Page.megaLevel(nil), .notYet)
        let d = Page.setting(megaLevel: .high, nil)
        XCTAssertEqual(Page.megaLevel(d), .high)
        XCTAssertEqual(CopyDetails.MegaLevel.allCases.map(\.title), ["Not yet", "Base", "High", "Max"])
        XCTAssertTrue(Page.setting(megaLevel: .notYet, d).isEmpty)
    }

    // MARK: sentences

    private func build(_ steps: [BoxAdvice.Build.Step]?) -> BoxAdvice.Build {
        var b = P23.build("c", "glaceon", areas: ["Raids"])
        b.steps = steps
        return b
    }

    func testTheWorkLineIsOneLineOfTheStepsLeft() {
        let s = BoxAdvice.Build.Step.self
        XCTAssertEqual(Page.workLine(build([s.init(kind: "evolve", to: "Glaceon"), s.init(kind: "powerUp", toLevel: 35)])), "Evolve, power up to level 35")
        XCTAssertEqual(Page.workLine(build([s.init(kind: "powerUp", toLevel: 27.5), s.init(kind: "secondMove"), s.init(kind: "eliteTM", count: 2)])),
                       "Power up to level 27.5, second move, 2 Elite TMs")
        XCTAssertEqual(Page.workLine(build([])), "Already built")
        XCTAssertEqual(Page.workLine(build([s.init(kind: "needsDynamaxCopy")])), "Needs a Dynamax copy")
        XCTAssertEqual(Page.workLine(build([s.init(kind: "powerUp", toLevel: 40), s.init(kind: "needsDynamaxCopy")])), "Power up to level 40, needs a Dynamax copy")
    }

    func testAPlansMarkIsFullStrengthWhenBuiltAndTheCostWhenWorkIsLeft() {
        let b = P23.build("c", "glaceon", areas: ["Raids"], built: false, dust: 62_000, candy: 89)
        let open = Page.planMark(b, built: false)
        XCTAssertEqual(open.mark, .upgrade(cost: MyPokemon.Cost(value: "62k", currency: .dust), builds: 1))
        XCTAssertNotNil(open.label)
        XCTAssertEqual(Page.planMark(b, built: true).mark, .fullStrength)
        var dynamaxOnly = b; dynamaxOnly.steps = [.init(kind: "needsDynamaxCopy")]
        XCTAssertEqual(Page.planMark(dynamaxOnly, built: false).mark, .none, "waiting on the Dynamax mark alone is not upgrade work")
    }

    func testPlanTitles() {
        let b = P23.build("c", "glaceon", areas: ["Raids"])
        XCTAssertEqual(Page.planTitle(.init(build: b, built: false)), "Planned for this copy")
        XCTAssertEqual(Page.planTitle(.init(build: b, built: true)), "This copy, full strength")
        XCTAssertEqual(Page.gymPlanTitle(.init(build: b, built: false)), "Planned as a defender")
        XCTAssertEqual(Page.gymPlanTitle(.init(build: b, built: true)), "Defender, full strength")
    }

    func testTheRaidsCardsMutedLine() {
        let m = PokemonActivities.Member(id: "glaceon", name: "Glaceon", types: ["ice"])
        func card(_ plan: PokemonActivities.RaidPlan, type: String = "ice") -> PokemonActivities.RaidCard {
            .init(member: m, type: type, tier: "B", role: .bulky, plan: plan, counters: [], counterCount: 0)
        }
        let own = P23.build("other", "glaceon", areas: ["Raids"], built: false)
        XCTAssertEqual(Page.raidsOtherLine(card(.best(.init(build: own, built: false), tier: "B"))), "Another copy (CP 1000) is planned as your Glaceon.")
        XCTAssertEqual(Page.raidsOtherLine(card(.best(.init(build: own, built: true), tier: "B"))), "Another copy (CP 1000) is planned as your Glaceon, at full strength.")
        let mamo = P23.build("x", "mamoswine", areas: ["Raids"])
        XCTAssertEqual(Page.raidsOtherLine(card(.best(.init(build: mamo, built: false), tier: "S"))), "Your best Ice attacker is Mamoswine (S), still to build.")
        XCTAssertEqual(Page.raidsOtherLine(card(.best(.init(build: mamo, built: true), tier: "S"))), "Your best Ice attacker is Mamoswine (S), at full strength.")
        XCTAssertEqual(Page.raidsOtherLine(card(.none)), "Nothing in your box is planned as an Ice attacker yet.")
        XCTAssertEqual(Page.raidsOtherLine(card(.none, type: "fire")), "Nothing in your box is planned as a Fire attacker yet.")
    }

    func testLeaderSlotsReadOneLeaderAfterAnother() {
        let slots: [PokemonActivities.LeaderSlotBeat] = [
            .init(leader: "Giovanni", slot: 2, beats: ["Rhyperior"], of: 3), .init(leader: "Giovanni", slot: 3, beats: ["Persian"], of: 3),
            .init(leader: "Sierra", slot: 2, beats: ["Slowbro"], of: 2),
        ]
        XCTAssertEqual(Page.leaderSlotsText(slots), "Giovanni slots 2, 3 · Sierra slot 2")
        XCTAssertEqual(Page.leaderSlotsText([]), "")
    }

    func testTheFamilyRowAndTheDynamaxLine() {
        XCTAssertEqual(Page.familyLabel(key: "gl", more: 8), "Great League family and details (8 more)")
        XCTAssertEqual(Page.familyLabel(key: "ml", more: 0), "Master League family and details")
        XCTAssertEqual(Page.dynamaxLine(row()), "Dynamax: not marked.")
        XCTAssertEqual(Page.dynamaxLine(row(dynamax: true)), "Marked as Dynamax.")
    }

    func testSummaryRowsMapToTheirNamesAndTabs() {
        XCTAssertEqual(PokemonActivities.Activity.allCases.map(Page.name), ["PvP leagues", "Raids", "Gym battles", "Team GO Rocket", "Max battles"])
        XCTAssertEqual(PokemonActivities.Activity.allCases.map(Page.tab), [.pvp, .raids, .gym, .rocket, .max])
    }

    func testTheSummaryMarkMapsToTheSharedBuildMark() {
        let b = P23.build("c", "glaceon", areas: ["Raids"], built: false, dust: 25_000)
        let up = PokemonActivities.Mark.upgrade(b, cost: HubSquads.cost(of: b), label: "Upgrade available: power up")
        XCTAssertEqual(Page.buildMark(up), .upgrade(cost: MyPokemon.Cost(value: "25k", currency: .dust), builds: 1))
        XCTAssertEqual(Page.upgradeLabel(up), "Upgrade available: power up")
        XCTAssertEqual(Page.buildMark(.fullStrength), .fullStrength)
        XCTAssertEqual(Page.buildMark(.none), .none)
        XCTAssertNil(Page.upgradeLabel(.fullStrength))
        let free = PokemonActivities.Mark.upgrade(b, cost: HubSquads.Cost(value: nil, currency: .free), label: "x")
        XCTAssertEqual(Page.buildMark(free), .upgrade(cost: nil, builds: 1), "a second move costs no dust or candy: the arrow alone")
    }

    func testTheShortNotesAreOneLine() {
        let spare = P23.build("other", "umbreon", areas: ["Raids"])
        let a = BoxAdvice.ForEntry(builds: [], spareFor: [spare, P23.build("other", "vaporeon", areas: ["Raids"])], duplicateOf: nil, keep: false, keepIndex: nil)
        XCTAssertEqual(Page.shortNotes(a, name: "Eevee"), "Spare: Umbreon, Vaporeon planned")
        XCTAssertNil(Page.shortNotes(BoxAdvice.ForEntry(builds: [], spareFor: [], duplicateOf: nil, keep: false, keepIndex: nil), name: "Eevee"))
        let self_ = BoxAdvice.ForEntry(builds: [], spareFor: [P23.build("o", "eevee", areas: ["Raids"])], duplicateOf: nil, keep: false, keepIndex: nil)
        XCTAssertEqual(Page.shortNotes(self_, name: "Eevee"), "Spare: another Eevee planned")
    }

    func testEmptyStatesSayNothingThisCopyCanBecomeIsInTheTable() {
        XCTAssertEqual(Page.emptyLine(.raids), "Nothing this copy can become is in our raid tables.")
        XCTAssertEqual(Page.emptyLine(.summary), "")
    }
}
