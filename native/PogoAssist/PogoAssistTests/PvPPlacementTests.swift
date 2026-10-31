import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// A PvP pick under Available is placed by the option the screen shows for the ranking in use (Classic pick, or the experimental member under Pogo Assist).
final class PvPPlacementTests: XCTestCase {
    typealias R = BoxAdvice.LeagueRating
    private func ctx() throws -> HubContext {
        let me = R.Option(speciesId: "eevee", name: "Eevee", isSelf: true, strength: .init(score: 85, rank: 50, of: 1152), overCap: false)
        let evo = R.Option(speciesId: "flareon", name: "Flareon", isSelf: false, strength: .init(score: 91, rank: 5, of: 1152), overCap: false)
        var advice = BoxAdvice(builds: [], gaps: [], duplicates: [], unresolved: [])
        // Classic shows the copy itself; the Pogo Assist ranking moves to the evolution.
        advice.leagues = ["a": ["ul": R(options: [me, evo], pick: 0, experimental: 1)], "b": ["ul": R(options: [me], pick: 0)]]
        return HubContext(advice: advice, entries: [], gm: try GameMaster.bundled(), hub: try HubData.bundled(), table: try TierTable.bundled(), today: "2026-10-26")
    }

    func testAvailablePlacesAnyCopyTheLeagueRatesWhateverItNeeds() throws {
        let c = try ctx()
        let classic = PvPPlacement.placeable(league: "ul", mode: .available, pogoAssist: false, ctx: c)
        let assist = PvPPlacement.placeable(league: "ul", mode: .available, pogoAssist: true, ctx: c)
        XCTAssertTrue(classic("a", "Lead"), "Classic shows the copy itself")
        XCTAssertTrue(assist("a", "Lead"), "S1: the Pogo Assist ranking shows an evolution, which is work Available now takes")
        XCTAssertTrue(assist("b", "Lead"))
        XCTAssertFalse(classic("missing", "Lead"), "a copy with no rating is not placed")
        XCTAssertFalse(classic("species:flareon", "Lead"), "a Pokémon the box lacks is not placed")
    }

    func testBestPlacesAnything() throws {
        let c = try ctx()
        XCTAssertTrue(PvPPlacement.placeable(league: "ul", mode: .best, pogoAssist: true, ctx: c)("a", "Lead"))
    }

    private func candidate(_ id: String, _ species: String, score: Double, roles: [HubSquads.PvpRole]) -> HubSquads.PvpCandidate {
        let o = R.Option(speciesId: species, name: species.capitalized, isSelf: true, strength: .init(score: score, rank: 1, of: 1152), overCap: false)
        return HubSquads.PvpCandidate(candidate: HubTeams.Candidate(entryId: id, option: o, copyTitle: species, score: score, ivRank: 10, ivPct: 95, built: true), roles: roles)
    }

    /// GO Battle League allows one copy of a species in a squad.
    func testASquadNeverHoldsTwoCopiesOfOneSpecies() {
        let a = candidate("a", "azumarill", score: 95, roles: [.lead]), b = candidate("b", "azumarill", score: 94, roles: [.safeSwap, .closer])
        let c = candidate("c", "umbreon", score: 90, roles: [.safeSwap])
        let species = ["a": "azumarill", "b": "azumarill", "c": "umbreon"]
        let filled = PvPPlacement.squad(slots: HubSquads.defaultPvpSlots(), candidates: [a, b, c], placeable: { _, _ in true }, species: { species[$0] })
        XCTAssertEqual(filled.map(\.entryId), ["a", "c", nil], "the second Azumarill is neither a Closer nor a fallback")
        // A kept pick wins over a new suggestion of its species.
        var slots = HubSquads.defaultPvpSlots(); slots[2].pick = "b"
        let kept = PvPPlacement.squad(slots: slots, candidates: [a, b, c], placeable: { _, _ in true }, species: { species[$0] })
        XCTAssertEqual(kept.map(\.entryId), [nil, "c", "b"], "the kept Closer stays; the Safe swap takes its own role's Umbreon first and the Lead, left with no other species, stays empty: no second Azumarill")
        // The picker of another slot does not offer a species the squad holds.
        let ex = PvPPlacement.excluded(by: filled, editing: 2, candidates: [a, b, c], species: { species[$0] })
        XCTAssertTrue(ex.contains("b") && ex.contains("a") && ex.contains("c"))
        let ex1 = PvPPlacement.excluded(by: filled, editing: 0, candidates: [a, b, c], species: { species[$0] })
        XCTAssertFalse(ex1.contains("a"), "the slot's own Pokémon stays listed")
        XCTAssertTrue(ex1.contains("c"))
    }

    func testTheWeaknessLineReadsTheMembersShown() throws {
        let hub = try HubData.bundled()
        // Two members hit by Rock (Fire and Flying), one that is not: a kept pick outside the candidates counts like the others.
        XCTAssertEqual(PvPPlacement.sharedWeakness(memberTypes: [["fire"], ["flying"], ["water"]], hub: hub).hasPrefix("Weak to"), true)
        XCTAssertEqual(PvPPlacement.sharedWeakness(memberTypes: [["fire"]], hub: hub), "No shared weakness.")
    }

    /// Best: a squad may hold Pokémon the box lacks (a `squadSpeciesPrefix` id), and the one-species rule still holds across copies and species ids.
    func testABestSquadMayHoldPokemonTheBoxLacks() {
        let owned = ["a": "azumarill", "b": "medicham"]
        // The closure the screen passes knows only copies (`speciesId(_:)` reads a copy's league rating): the placement itself reads a species id's own species.
        let species: (String) -> String? = { owned[$0] }
        let roles = ["Lead": ["species:medicham", "b"], "Safe swap": ["a"], "Closer": ["species:lanturn", "species:medicham"]]
        let all = ["species:medicham", "a", "species:lanturn"]
        let filled = PvPPlacement.squad(slots: HubSquads.defaultPvpSlots(), pool: { roles[$0] ?? [] }, all: all, placeable: { _, _ in true }, species: species)
        XCTAssertEqual(filled.map(\.pickId), ["species:medicham", "a", "species:lanturn"])
        XCTAssertEqual(filled.map(\.species), ["medicham", nil, "lanturn"])
        XCTAssertEqual(filled.map(\.entryId), [nil, "a", nil])
        // A kept species pick wins; a copy of the same species is then not suggested for another slot.
        var slots = HubSquads.defaultPvpSlots(); slots[2] = SquadSlot(role: "Closer", species: "medicham")
        let kept = PvPPlacement.squad(slots: slots, pool: { roles[$0] ?? [] }, all: all, placeable: { _, _ in true }, species: species)
        XCTAssertEqual(kept.map(\.pickId), ["species:lanturn", "a", "species:medicham"], "no Lead is listed that is not Medicham: the Safe swap takes its own role's Azumarill, then the Lead falls back")
        XCTAssertEqual(kept.map(\.chosen), [false, false, true])
        // The picker of another slot does not offer a species the squad holds, whether it is listed as a copy or as a species.
        let ex = PvPPlacement.excluded(by: kept, editing: 1, ids: ["b", "species:medicham", "species:lanturn", "a"], species: species)
        XCTAssertTrue(ex.contains("b") && ex.contains("species:medicham") && ex.contains("species:lanturn"))
        XCTAssertFalse(ex.contains("a"), "the edited slot's own Pokémon stays listed")
    }

    /// Phone feedback item 10: an Available picker lists the Pokémon at Full strength first and the ones that need work under "Available upgrades:".
    func testAvailablePickerListsUpgradesLast() {
        func row(_ id: String, _ mark: SquadMark) -> PickerRowModel { PickerRowModel(id: id, name: id, ticked: false, mark: mark, spoken: id) }
        let up = SquadMark.upgrade(cost: nil, label: "Upgrade available: power up")
        let rows = PickerRowModel.availableUpgradesLast([row("a", up), row("b", .fullStrength), row("c", up), row("d", .fullStrength)])
        XCTAssertEqual(rows.map(\.id), ["b", "d", "a", "c"], "each group keeps the slot's order")
        XCTAssertEqual(rows.map(\.sectionHeading), [nil, nil, "Available upgrades:", nil])
        XCTAssertEqual(PickerRowModel.availableUpgradesLast([row("b", .fullStrength)]).map(\.sectionHeading), [nil], "no heading without upgrades")
        XCTAssertEqual(PickerRowModel.availableUpgradesLast([row("a", up)]).map(\.sectionHeading), ["Available upgrades:"])
        XCTAssertEqual(PickerRowModel.availableUpgradesLast([]).count, 0)
    }

    /// S1 and the manager's ruling: the slot's own role's options (Full strength first, then "Available upgrades:"), then "Other roles:" with every other unused one.
    func testAvailablePickerListsOtherRolesLast() {
        func row(_ id: String, _ mark: SquadMark) -> PickerRowModel { PickerRowModel(id: id, name: id, ticked: false, mark: mark, role: "Heavy hitter", spoken: id) }
        let up = SquadMark.upgrade(cost: nil, label: "Upgrade available: power up")
        let rows = PickerRowModel.availableGroups(own: [row("a", up), row("b", .fullStrength)], other: [row("x", up), row("y", .fullStrength)])
        XCTAssertEqual(rows.map(\.id), ["b", "a", "x", "y"], "the other roles keep the order the squad is filled in")
        XCTAssertEqual(rows.map(\.sectionHeading), [nil, "Available upgrades:", "Other roles:", nil])
        XCTAssertEqual(PickerRowModel.availableGroups(own: [], other: [row("x", up)]).map(\.sectionHeading), ["Other roles:"])
        XCTAssertEqual(PickerRowModel.availableGroups(own: [row("b", .fullStrength)], other: []).map(\.sectionHeading), [nil], "no heading without other roles")
    }

    /// Each role's own slots fill across the whole squad before any slot takes another role's Pokémon.
    func testPvPRoleSlotsFillBeforeAnyFallback() {
        let roles = ["Lead": ["a"], "Closer": ["c", "d"]]
        let out = PvPPlacement.squad(slots: [SquadSlot(role: "Lead"), SquadSlot(role: "Lead"), SquadSlot(role: "Closer")], pool: { roles[$0] ?? [] }, all: ["c", "a", "d"],
                                     placeable: { _, _ in true }, species: { $0 })
        XCTAssertEqual(out.map(\.entryId), ["a", "d", "c"], "the second Lead slot takes the Closer left over, not the one the Closer slot is about to take")
        XCTAssertEqual(out.map(\.fallback), [false, true, false])
    }

    /// Phone feedback items 8 and 10: what an empty picker says is true to what the box has, and a Best row says what the box has of the Pokémon.
    func testEmptyPickerTextAndBestNotes() {
        XCTAssertEqual(SquadWords.emptyPicker(mode: .available, boxHasOptions: true, none: "No Gym build in your box."), "Everything in your box for this slot is already in your squad.")
        XCTAssertEqual(SquadWords.emptyPicker(mode: .available, boxHasOptions: false, none: "No Gym build in your box."), "No Gym build in your box.")
        XCTAssertEqual(SquadWords.emptyPicker(mode: .best, boxHasOptions: true, none: "No Gym defender listed."), "No Gym defender listed.")
        var row = HubSquads.BestRow(key: "excadrill", name: "Excadrill", speciesId: "excadrill", tier: "A", roles: [], types: ["ground", "steel"], availability: "Raids from 9 Nov", rotationLine: "Raids from 9 Nov")
        row.status = .init(kind: .notAvailableNow, needsUpgrade: false, detail: "Raids from 9 Nov")
        XCTAssertEqual(PickerRowModel.bestNote(row).text, "Not available now · Raids from 9 Nov", "S1: one of three statuses")
        XCTAssertEqual(PickerRowModel.bestNote(row).amber, false)
        row.status = .init(kind: .canGetNow, needsUpgrade: false, detail: "Raid boss now")
        XCTAssertEqual(PickerRowModel.bestNote(row).text, "Can get now · Raid boss now")
        row.status = .init(kind: .notAvailableNow, needsUpgrade: false, detail: "Raids from 9 Nov")
        XCTAssertEqual(PickerRowModel(best: row, ticked: false).id, "species:excadrill")
        row.sharedWith = "Mega Swampert"
        XCTAssertEqual(row.entryId, "species:excadrill")
        let card = SlotCardModel(id: 0, role: nil, palette: .grey, emptyOutline: .clear, disc: "1", best: HubSquads.BestRow(key: "x", name: "X", speciesId: "x", tier: "S", roles: [], types: [], availability: "Medium. T5 raids"), head: "Slot 1", identifier: "s")
        XCTAssertEqual(card.lines, ["Not available now · not on the schedule"], "no date known: the reason says so, and no date is made up")
        XCTAssertEqual(card.status, .toGet)
        XCTAssertTrue(card.spoken.contains("Not available now") && card.spoken.hasSuffix("not in your box, to get"), card.spoken)
        var owned = HubSquads.BestRow(key: "y", name: "Y", speciesId: "y", tier: "S", roles: [], types: [], availability: "")
        owned.status = .init(kind: .inBox, needsUpgrade: true, detail: nil)
        owned.sharedWith = "Z"
        XCTAssertEqual(owned.statusLine, "In your box · needs upgrade · same copy as Z")
        XCTAssertEqual(HubSquads.SlotStatus.allWords, ["Ready", "Needs work", "To get", "Empty"])
        XCTAssertEqual(SquadWords.otherRoleLine(["Bulky hitter"]), "Its role: Bulky hitter")
        XCTAssertEqual(SquadWords.otherRoleLine([]), "No listed role")
    }
}

extension HubSquads.SlotStatus { static var allWords: [String] { [HubSquads.SlotStatus.ready, .needsWork, .toGet, .empty].map(\.word) } }
