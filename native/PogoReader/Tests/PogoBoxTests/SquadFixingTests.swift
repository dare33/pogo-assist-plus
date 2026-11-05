import XCTest
@testable import PogoBox

/// Rule 27 (5 Nov 2026): the suggestion is worked out once and the player edits from there; swap; Back to suggested squad.
final class SquadFixingTests: XCTestCase {
    private let ranked = ["a", "b", "c", "d", "e"]
    private func shown(_ saved: SquadStore.Saved, placeable: @escaping (String, String) -> Bool = { _, _ in true }, ranked: [String]? = nil) -> [FilledSlot] {
        let list = ranked ?? self.ranked
        return HubSquads.fill(slots: saved.slots, pool: { _, _ in .init(preferred: list) }, placeable: placeable)
    }

    func testANeverChangedSquadKeepsNothingAndFollowsTheRanking() {
        let saved = SquadStore.Saved(slots: [SquadSlot(role: "X"), SquadSlot(role: "X"), SquadSlot(role: "X")])
        XCTAssertEqual(shown(saved).map(\.entryId), ["a", "b", "c"])
        XCTAssertEqual(shown(saved, ranked: ["z"] + ranked).map(\.entryId), ["z", "a", "b"], "a box change moves every slot")
        XCTAssertFalse(saved.changed)
        XCTAssertFalse(saved.showsBackToSuggested)
    }

    func testTheFirstChangeKeepsEverySlotAsShownThenNothingMovesOnItsOwn() {
        var saved = SquadStore.Saved(slots: [SquadSlot(role: "X"), SquadSlot(role: "X"), SquadSlot(role: "X")])
        // Slot 0 shows "a" (Blissey in Greg's case); the player puts "d" in slot 0.
        saved.choose("d", at: 0, shown: shown(saved))
        XCTAssertTrue(saved.changed)
        XCTAssertEqual(saved.slots.map(\.pick), ["d", "b", "c"], "the other slots keep what they showed")
        XCTAssertEqual(shown(saved).map(\.entryId), ["d", "b", "c"], "the replaced Pokémon does not drop into another slot")
        XCTAssertEqual(shown(saved, ranked: ["z", "y"] + ranked).map(\.entryId), ["d", "b", "c"], "a box change moves nothing")
        // A second change does not keep the shown squad again.
        saved.choose("e", at: 2, shown: shown(saved, ranked: ["z"] + ranked))
        XCTAssertEqual(saved.slots.map(\.pick), ["d", "b", "e"])
    }

    func testChangingARoleIsAChangeToo() {
        var saved = SquadStore.Saved(slots: [SquadSlot(role: "Tank"), SquadSlot(role: "Healer")])
        saved.changeRole(at: 1, to: "Attacker", fits: { _ in true }, shown: shown(saved))
        XCTAssertTrue(saved.changed)
        XCTAssertEqual(saved.slots, [SquadSlot(role: "Tank", pick: "a"), SquadSlot(role: "Attacker", pick: "b")])
        var drops = SquadStore.Saved(slots: [SquadSlot(role: "Tank"), SquadSlot(role: "Healer")])
        drops.changeRole(at: 1, to: "Attacker", fits: { _ in false }, shown: shown(drops))
        XCTAssertEqual(drops.slots, [SquadSlot(role: "Tank", pick: "a"), SquadSlot(role: "Attacker")], "a pick that does not fit goes; only that slot refills")
        XCTAssertEqual(shown(drops).map(\.entryId), ["a", "b"])
    }

    func testChoosingAPokemonFromAnotherSlotSwaps() {
        var saved = SquadStore.Saved(slots: [SquadSlot(role: "X"), SquadSlot(role: "X"), SquadSlot(role: "X")])
        saved.choose("c", at: 0, shown: shown(saved))
        XCTAssertEqual(saved.slots.map(\.pick), ["c", "b", "a"], "slot 0 held a, which goes to c's old slot; nothing else moves")
        saved.choose("b", at: 2, shown: shown(saved))
        XCTAssertEqual(saved.slots.map(\.pick), ["c", "a", "b"])
        // Choosing the Pokémon a slot already holds changes nothing else.
        saved.choose("c", at: 0, shown: shown(saved))
        XCTAssertEqual(saved.slots.map(\.pick), ["c", "a", "b"])
    }

    func testSwappingWithAnEmptySlotEmptiesTheOtherAndItTakesTheNextBestUnused() {
        // Two slots shown, the third empty (a short list).
        var saved = SquadStore.Saved(slots: [SquadSlot(role: "X"), SquadSlot(role: "X"), SquadSlot(role: "X")])
        let two = ["a", "b"]
        let before = shown(saved, ranked: two)
        XCTAssertEqual(before.map(\.entryId), ["a", "b", nil])
        saved.choose("a", at: 2, shown: before)
        XCTAssertEqual(saved.slots.map(\.pick), [nil, "b", "a"], "slot 2 was empty, so slot 0 empties")
        XCTAssertEqual(shown(saved, ranked: ["a", "b", "q"]).map(\.entryId), ["q", "b", "a"], "the emptied slot takes the next best unused, that slot only")
    }

    func testSwapMovesSpeciesPicksToo() {
        var saved = SquadStore.Saved(slots: [SquadSlot(role: "X", species: "chansey"), SquadSlot(role: "X", pick: "g1")])
        saved.changed = true
        saved.choose("species:chansey", at: 1, alsoClearing: ["species:chansey", "c1"])
        XCTAssertEqual(saved.slots[0], SquadSlot(role: "X", pick: "g1"))
        XCTAssertEqual(saved.slots[1], SquadSlot(role: "X", species: "chansey"))
    }

    func testAPickWhoseCopyLeftTheBoxRefillsThatSlotOnly() {
        var s = SquadStore()
        s.gym.choose("gone", at: 0, shown: [])
        s.gym.fixing([])   // already changed: a no-op
        s.gym.slots[1].pick = "b"; s.gym.slots[2].pick = "c"
        let kept = s.reconciled(boxIds: ["b", "c"]).gym
        XCTAssertEqual(kept.slots.prefix(3).map(\.pick), [nil, "b", "c"])
        XCTAssertTrue(kept.changed, "still the player's squad")
        let out = HubSquads.fill(slots: kept.slots, pool: { _, _ in .init(preferred: ["b", "z", "c"]) })
        XCTAssertEqual(out.prefix(3).map(\.entryId), ["z", "b", "c"], "only the emptied slot refills, with the next best unused")
    }

    func testBackToSuggestedSquadForgetsPicksRolesAndTheSetMark() {
        var saved = SquadStore.Saved(slots: HubSquads.defaultMaxSlots(), isSet: true)
        saved.changeRole(at: 0, to: "Attacker", fits: { _ in true }, shown: shown(saved))
        saved.choose("d", at: 1)
        XCTAssertTrue(saved.showsBackToSuggested)
        saved.backToSuggested(defaults: HubSquads.defaultMaxSlots())
        XCTAssertEqual(saved, SquadStore.Saved(slots: HubSquads.defaultMaxSlots()))
        XCTAssertFalse(saved.showsBackToSuggested)
        XCTAssertEqual(shown(saved).map(\.entryId), ["a", "b", "c"], "the suggestion again")
    }

    func testOldFilesLoadAsUnchangedAndKeepTheirPicksUntilTheNextChange() throws {
        let old = #"{"slots":[{"role":"Defender","pick":"keep-me"},{"role":"Defender"}],"isSet":false}"#
        var saved = try JSONDecoder().decode(SquadStore.Saved.self, from: Data(old.utf8))
        XCTAssertFalse(saved.changed)
        XCTAssertTrue(saved.showsBackToSuggested, "it holds a pick of the player's")
        // Their pick is kept as shown; the next change keeps the rest.
        saved.choose("e", at: 1, shown: shown(saved, ranked: ["keep-me", "a", "e"]))
        XCTAssertEqual(saved.slots.map(\.pick), ["keep-me", "e"])
        XCTAssertTrue(saved.changed)
        let again = try JSONDecoder().decode(SquadStore.Saved.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(again, saved)
    }

    func testFixingKeepsASpeciesRowAndAnEmptySlot() {
        var saved = SquadStore.Saved(slots: [SquadSlot(role: "X"), SquadSlot(role: "X"), SquadSlot(role: "X")])
        let filled = HubSquads.fill(slots: saved.slots, pool: { _, _ in .init(preferred: ["species:medicham", "c0"]) })
        XCTAssertEqual(filled.map(\.pickId), ["species:medicham", "c0", nil])
        saved.fixing(filled)
        XCTAssertEqual(saved.slots, [SquadSlot(role: "X", species: "medicham"), SquadSlot(role: "X", pick: "c0"), SquadSlot(role: "X")])
        XCTAssertTrue(saved.changed)
    }

    func testModeSwitchOfAKeptSquad() {
        // Fixed under Best: a species pick the box lacks. Under Available it is not placed, so that slot shows the suggestion; back under Best it returns (rule 27).
        var saved = SquadStore.Saved(slots: [SquadSlot(role: "X"), SquadSlot(role: "X")])
        saved.fixing(HubSquads.fill(slots: saved.slots, pool: { _, _ in .init(preferred: ["species:medicham", "c0"]) }))
        let available: (String, String) -> Bool = { id, _ in !id.hasPrefix(squadSpeciesPrefix) }
        XCTAssertEqual(shown(saved, placeable: available, ranked: ["c0", "c1", "c2"]).map(\.entryId), ["c1", "c0"], "the species slot refills on its own under Available")
        XCTAssertEqual(saved.slots[0].species, "medicham", "but the pick is still kept")
        XCTAssertEqual(shown(saved, ranked: ["c0", "c1"]).map(\.pickId), ["species:medicham", "c0"])
        // Fixed under Available (copies): every copy is placeable under Best, so nothing moves.
        var avail = SquadStore.Saved(slots: [SquadSlot(role: "X"), SquadSlot(role: "X")])
        avail.fixing(shown(avail, ranked: ["c0", "c1"]))
        XCTAssertEqual(shown(avail, ranked: ["q", "c0", "c1"]).map(\.entryId), ["c0", "c1"])
    }

    func testSlotNumbersNameTheOtherSlotsPokemonUnderEveryIdTheyGoBy() {
        let filled = HubSquads.fill(slots: [SquadSlot(role: "X", pick: "a"), SquadSlot(role: "X", species: "chansey"), SquadSlot(role: "X", pick: "c")],
                                    pool: { _, _ in .init(preferred: []) })
        XCTAssertEqual(HubSquads.slotNumbers(of: filled, editing: 1), ["a": 1, "c": 3])
        XCTAssertEqual(HubSquads.slotNumbers(of: filled, editing: 0), ["species:chansey": 2, "c": 3])
        // A species id that reads as a copy is also held under the copy.
        XCTAssertEqual(HubSquads.slotNumbers(of: filled, editing: 0, copyOf: { $0 == "species:chansey" ? "c9" : nil })["c9"], 2)
        XCTAssertEqual(HubSquads.slotNumbers(of: filled, editing: 9).count, 3, "an index outside the squad edits no slot")
    }
}
