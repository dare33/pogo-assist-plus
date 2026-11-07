import XCTest
@testable import PogoBox

/// Pass 2-5, rule 27: Current is the stored squad; Available and Best are drafts held by the screen; old files keep decoding; the Raids style.
final class SquadCurrentTests: XCTestCase {
    private func row(_ title: String = "Palkia") -> HubData.RotationRow {
        HubData.RotationRow(from: "2026-11-01", to: "2026-11-30", kind: .fiveStar, title: title, bosses: [], note: "", source: "", tba: nil)
    }
    private func picked(_ roles: [String] = ["X", "X"]) -> SquadStore.Saved {
        var s = SquadStore.Saved(slots: roles.map { SquadSlot(role: $0) })
        s.choose("c1", at: 0, shown: HubSquads.fill(slots: s.slots, pool: { _, _ in .init(preferred: ["a", "b"]) }))
        return s
    }

    // MARK: Current in the store

    func testASquadWithNothingKeptHasNoCurrent() {
        let store = SquadStore()
        XCTAssertNil(store.current(.gym))
        XCTAssertNil(store.current(.rocket(leader: "Arlo")))
        XCTAssertNil(store.current(.pvp(league: "gl")))
        XCTAssertNil(store.current(.event(row: row(), screen: .raids)))
        XCTAssertFalse(SquadStore.Saved(slots: HubSquads.defaultGymSlots()).hasCurrent)
    }

    func testSettingAndDeletingACurrentSquadOnEveryScreen() {
        var store = SquadStore()
        let ref: [SquadRef] = [.event(row: row(), screen: .raids), .event(row: row("Dialga"), screen: .max), .gym, .rocket(leader: "Arlo"), .pvp(league: "ul")]
        for r in ref {
            XCTAssertNil(store.current(r))
            store.setCurrent(picked(), r)
            XCTAssertEqual(store.current(r)?.slots.first?.pick, "c1", "\(r.key)")
        }
        // Each squad is its own.
        store.deleteCurrent(.gym)
        XCTAssertNil(store.current(.gym))
        XCTAssertEqual(store.gym, SquadStore.Saved(slots: HubSquads.defaultGymSlots()), "the Gym's six are the defaults again")
        XCTAssertNotNil(store.current(.rocket(leader: "Arlo")))
        for r in ref { store.deleteCurrent(r) }
        for r in ref { XCTAssertNil(store.current(r), r.key) }
        XCTAssertEqual(store, { var s = SquadStore(); s.raids = [:]; return s }(), "nothing is left behind")
    }

    func testDeletingCurrentLeavesTheTabAndStyleChoicesAlone() {
        var store = SquadStore()
        store.setMode(.best, for: .raids)
        store.raidStyle = .maxDamage
        store.setCurrent(picked(), .event(row: row(), screen: .raids))
        store.deleteCurrent(.event(row: row(), screen: .raids))
        XCTAssertEqual(store.mode(for: .raids), .best)
        XCTAssertEqual(store.raidStyle, .maxDamage)
    }

    func testTheSetMarkIsPartOfTheCurrentSquadAndGoesWithIt() {
        var store = SquadStore()
        var s = picked(); s.isSet = true
        store.setCurrent(s, .event(row: row(), screen: .raids))
        XCTAssertEqual(store.current(.event(row: row(), screen: .raids))?.isSet, true)
        store.deleteCurrent(.event(row: row(), screen: .raids))
        XCTAssertNil(store.current(.event(row: row(), screen: .raids)))
    }

    // MARK: old files

    func testOldFilesBecomeTheSquadsCurrentWhenTheyKeptAnything() throws {
        // A pass 2-4 file: one squad changed (no picks left on it but changed), one with a pick and no `changed` key, one with nothing kept, one set with nothing else.
        let json = """
        {"version":1,"gym":{"slots":[{"role":"Defender","pick":"keep-me"}],"isSet":false},
         "rocket":{"Arlo":{"slots":[{"role":"Counter"}],"isSet":false,"changed":true},"Sierra":{"slots":[{"role":"Counter"}],"isSet":false,"changed":false}},
         "pvp":{"gl":{"slots":[{"role":"Lead","species":"medicham"}],"isSet":false}},
         "raids":{"k":{"squad":{"slots":[{"role":"Mega"}],"isSet":true},"endsOn":"2026-12-01"}},
         "modes":{"raids":"best"}}
        """
        let store = try JSONDecoder().decode(SquadStore.self, from: Data(json.utf8))
        XCTAssertNotNil(store.current(.gym), "a pick of the player's")
        XCTAssertNotNil(store.current(.rocket(leader: "Arlo")), "changed")
        XCTAssertNil(store.current(.rocket(leader: "Sierra")), "nothing kept")
        XCTAssertNotNil(store.current(.pvp(league: "gl")), "a species pick")
        XCTAssertEqual(store.raids["k"]?.squad.hasCurrent, true, "the Squad set mark alone is kept too, so the mark is not lost")
        XCTAssertEqual(store.mode(for: .raids), .best)
        XCTAssertEqual(store.raidStyle, .balanced, "an old file has no style")
        let again = try JSONDecoder().decode(SquadStore.self, from: JSONEncoder().encode(store))
        XCTAssertEqual(again, store)
    }

    func testTheRaidStyleIsStored() throws {
        var store = SquadStore()
        store.raidStyle = .maxDamage
        XCTAssertEqual(try JSONDecoder().decode(SquadStore.self, from: JSONEncoder().encode(store)).raidStyle, .maxDamage)
    }

    // MARK: drafts

    func testASquadOpensOnCurrentWhenItHasOneElseOnTheRememberedChoice() {
        let d = SquadDrafts()
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .best), .current)
        XCTAssertEqual(d.tab("k", hasCurrent: false, mode: .best), .best)
        XCTAssertEqual(d.tab("k", hasCurrent: false, mode: .available), .available)
    }

    func testAChosenTabStaysUntilCurrentGoesAway() {
        var d = SquadDrafts()
        d.select(.available, for: "k")
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .best), .available, "the choice holds when Current appears")
        d.select(.current, for: "k")
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .best), .current)
        XCTAssertEqual(d.tab("k", hasCurrent: false, mode: .best), .best, "Current is gone: back to the remembered choice")
        d.clearTab(for: "k")
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .available), .current)
    }

    func testADraftIsKeptPerTabAndPerSquadAndDiffersOnceEdited() {
        var d = SquadDrafts()
        XCTAssertNil(d.draft("a", .available))
        XCTAssertFalse(d.differs("a", .available))
        let edited = picked()
        d.setDraft(edited, "a", .available)
        XCTAssertTrue(d.differs("a", .available))
        XCTAssertFalse(d.differs("a", .best), "each tab has its own draft")
        XCTAssertFalse(d.differs("b", .available), "and each squad")
        XCTAssertEqual(d.draft("a", .available), edited)
        d.select(.best, for: "a")
        XCTAssertEqual(d.draft("a", .available), edited, "switching tabs keeps the draft")
        d.setDraft(SquadStore.Saved(slots: [SquadSlot(role: "X")]), "c", .best)
        XCTAssertFalse(d.differs("c", .best), "an unedited draft does not differ")
    }

    func testResetDropsTheDraftAtOnce() {
        var d = SquadDrafts()
        d.setDraft(picked(), "a", .available)
        d.setDraft(picked(), "a", .best)
        d.reset("a", .available)
        XCTAssertNil(d.draft("a", .available))
        XCTAssertTrue(d.differs("a", .best))
        d.resetAll("a")
        XCTAssertNil(d.draft("a", .best))
    }

    func testSavingKeepsTheTabAndSaysSavedWhileTheStoredCurrentIsThatSquad() {
        var d = SquadDrafts()
        let s = picked()
        d.setDraft(s, "a", .best)
        XCTAssertFalse(d.justSaved("a", .best, current: s))
        d.didSave(s, "a", .best)
        var store = SquadStore(); store.setCurrent(s, .gym)
        let current = store.current(.gym)
        XCTAssertEqual(d.tab("a", hasCurrent: true, mode: .available), .best, "the player stays where they are")
        XCTAssertTrue(d.justSaved("a", .best, current: current))
        var withMark = s; withMark.isSet = true
        XCTAssertTrue(d.justSaved("a", .best, current: withMark), "the set mark is not part of the squad")
        var more = s
        more.choose("c2", at: 1)
        d.setDraft(more, "a", .best)
        XCTAssertFalse(d.justSaved("a", .best, current: current), "a further edit is not saved")
        d.reset("a", .best)
        XCTAssertFalse(d.justSaved("a", .best, current: current))
    }

    /// H5: Delete, a replacement from another tab and an edit of Current all end "Saved to Current", and Save shows again for that draft.
    func testSavedToCurrentEndsWhenTheStoredCurrentStopsBeingThatSquad() {
        var d = SquadDrafts()
        let s = picked()
        d.didSave(s, "a", .available)
        XCTAssertFalse(d.justSaved("a", .available, current: nil), "Current was deleted")
        d.clearSaved("a")
        XCTAssertFalse(d.justSaved("a", .available, current: s), "clearSaved forgets the save (Delete current squad)")
        d.didSave(s, "a", .available)
        var other = s; other.choose("z", at: 1)
        XCTAssertFalse(d.justSaved("a", .available, current: other), "another squad replaced Current")
        var edited = s; edited.changeRole(at: 0, to: "Y", fits: { _ in true })
        XCTAssertFalse(d.justSaved("a", .available, current: edited), "Current was edited")
        XCTAssertTrue(d.justSaved("a", .available, current: s))
    }

    /// H1: another account's drafts, tabs and notes are dropped.
    func testAnotherAccountStartsWithNothing() {
        var d = SquadDrafts()
        d.switchAccount("A")
        d.setDraft(picked(), "a", .available); d.select(.best, for: "a"); d.didSave(picked(), "b", .best)
        d.switchAccount("A")
        XCTAssertNotNil(d.draft("a", .available), "the same account keeps its drafts")
        d.switchAccount("B")
        XCTAssertEqual(d.account, "B")
        XCTAssertNil(d.draft("a", .available)); XCTAssertNil(d.draft("b", .best))
        XCTAssertEqual(d.tab("a", hasCurrent: false, mode: .available), .available)
        XCTAssertFalse(d.justSaved("b", .best, current: picked()))
    }

    /// H2: a draft pick whose copy left the box is emptied; species picks, other slots and roles stay.
    func testADraftFollowsTheBoxLikeTheStore() {
        var d = SquadDrafts()
        var s = SquadStore.Saved(slots: [SquadSlot(role: "X", pick: "gone"), SquadSlot(role: "Y", pick: "here"), SquadSlot(role: "Z", species: "medicham"), SquadSlot(role: "W", pick: "gone2", fallback: true)], changed: true)
        s.changed = true
        d.setDraft(s, "k", .best)
        let r = d.reconciled(boxIds: ["here"])
        let slots = r.draft("k", .best)!.slots
        XCTAssertEqual(slots.map(\.pick), [nil, "here", nil, nil])
        XCTAssertEqual(slots[2].species, "medicham")
        XCTAssertEqual(slots.map(\.role), ["X", "Y", "Z", "W"])
        XCTAssertNil(slots[3].fallback)
        XCTAssertEqual(r.draft("k", .best)?.changed, true, "still an edited draft")
    }

    // MARK: old files, migrated for good (H4)

    func testAnOldFilesCurrentSurvivesTheCopyLeavingTheBox() throws {
        let json = #"{"version":1,"gym":{"slots":[{"role":"Defender","pick":"gone"},{"role":"Defender"}],"isSet":false}}"#
        let old = try JSONDecoder().decode(SquadStore.self, from: Data(json.utf8))
        XCTAssertFalse(old.gym.changed)
        let refreshed = old.refreshed(today: "2026-11-06", rotation: [], boxIds: ["other"])
        XCTAssertTrue(refreshed.gym.changed, "migrated: the squad is marked changed")
        XCTAssertNil(refreshed.gym.slots[0].pick, "the copy left")
        XCTAssertNotNil(refreshed.current(.gym), "Current remains")
        XCTAssertTrue(refreshed.gym.needsAdopting(HubSquads.fill(slots: refreshed.gym.slots, pool: { _, _ in .init(preferred: ["x"]) })), "so the slot refills and the refill is kept")
        // A squad with nothing kept is not migrated into a Current.
        let none = try JSONDecoder().decode(SquadStore.self, from: Data(#"{"version":1,"gym":{"slots":[{"role":"Defender"}],"isSet":false}}"#.utf8))
        XCTAssertNil(none.migrated().current(.gym))
        XCTAssertFalse(none.migrated().gym.changed)
    }

    func testSameSquadComparesSlotsAndIgnoresTheSetMark() {
        var a = picked(), b = picked()
        XCTAssertTrue(a.sameSquad(as: b))
        b.isSet = true
        XCTAssertTrue(a.sameSquad(as: b))
        a.changeRole(at: 1, to: "Q", fits: { _ in true })
        XCTAssertFalse(a.sameSquad(as: b))
    }

    /// H6: the drawn squads are compared slot by slot.
    func testDrawnSquadsAreTheSameWhenEverySlotHoldsTheSamePokemonInTheSameRole() {
        func drawn(_ roles: [String], _ ranked: [String]) -> [FilledSlot] { HubSquads.fill(slots: roles.map { SquadSlot(role: $0) }, pool: { _, _ in .init(preferred: ranked) }) }
        XCTAssertTrue(HubSquads.sameSquad(drawn(["A", "B"], ["x", "y"]), drawn(["A", "B"], ["x", "y"])))
        XCTAssertFalse(HubSquads.sameSquad(drawn(["A", "B"], ["x", "y"]), drawn(["A", "B"], ["y", "x"])))
        XCTAssertFalse(HubSquads.sameSquad(drawn(["A", "B"], ["x", "y"]), drawn(["A", "C"], ["x", "y"])), "a role differs")
    }

    func testAChangeOfRaidStyleDropsEveryRaidDraftAndNothingElse() {
        var d = SquadDrafts()
        let raid = SquadRef.event(row: row(), screen: .raids).key, max = SquadRef.event(row: row(), screen: .max).key
        for k in [raid, max, SquadRef.gym.key] { d.setDraft(picked(), k, .available); d.setDraft(picked(), k, .best) }
        d.didSave(picked(), raid, .best)
        d.resetAll(keyPrefix: "raids|")
        XCTAssertNil(d.draft(raid, .available)); XCTAssertNil(d.draft(raid, .best))
        XCTAssertFalse(d.justSaved(raid, .best, current: picked()))
        XCTAssertNotNil(d.draft(max, .available), "Max has no style")
        XCTAssertNotNil(d.draft(SquadRef.gym.key, .best))
    }

    func testTheRefOfASquadNamesItsScreen() {
        XCTAssertEqual(SquadRef.event(row: row(), screen: .max).screen, .max)
        XCTAssertEqual(SquadRef.gym.screen, .gym)
        XCTAssertEqual(SquadRef.rocket(leader: "Arlo").screen, .rocket)
        XCTAssertEqual(SquadRef.pvp(league: "gl").screen, .pvp)
    }

    func testTheKeyNamesTheSquad() {
        XCTAssertNotEqual(SquadRef.event(row: row(), screen: .raids).key, SquadRef.event(row: row(), screen: .max).key)
        XCTAssertNotEqual(SquadRef.event(row: row(), screen: .raids).key, SquadRef.event(row: row("Dialga"), screen: .raids).key)
        XCTAssertEqual(SquadTab.best.mode, .best)
        XCTAssertEqual(SquadTab.current.mode, .available)
    }

    // MARK: Raids style

    func testBalancedIsTodaysSquadAndMaxDamageIsAMegaAndFiveHeavyHitters() {
        XCTAssertEqual(HubSquads.defaultRaidSlots(style: .balanced), HubSquads.defaultRaidSlots())
        XCTAssertEqual(HubSquads.defaultRaidSlots(style: .balanced).map(\.role), ["Mega", "Heavy hitter", "Heavy hitter", "Heavy hitter", "Bulky hitter", "Bulky hitter"])
        XCTAssertEqual(HubSquads.defaultRaidSlots(style: .maxDamage).map(\.role), ["Mega"] + Array(repeating: "Heavy hitter", count: 5))
        XCTAssertEqual(RaidStyle.maxDamage.title, "Max damage")
        XCTAssertEqual(RaidStyle.balanced.title, "Balanced")
        XCTAssertEqual(RaidStyle.allCases.count, 2)
    }
}
