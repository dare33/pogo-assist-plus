import XCTest
@testable import PogoBox

/// Pass 2-5, rule 27: Current is the stored squad; the tab a squad shows; old files keep decoding; the Raids style. (The kept edits and the history are SquadEditsHistoryTests.)
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
        // Pass 2-6: deleting moves the Current to the history (rule 27.7), so the history and the event days it recorded are all that is left.
        store.history = [:]; store.eventEnds = [:]; store.undoRecords = [:]   // (the last Delete's undo record is memory only)
        XCTAssertEqual(store, { var s = SquadStore(); s.raids = [:]; return s }(), "nothing else is left behind")
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

    // MARK: tab choice

    func testASquadOpensOnCurrentWhenItHasOneElseOnTheRememberedChoice() {
        let d = SquadTabChoices()
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .best), .current)
        XCTAssertEqual(d.tab("k", hasCurrent: false, mode: .best), .best)
        XCTAssertEqual(d.tab("k", hasCurrent: false, mode: .available), .available)
    }

    func testAChosenTabStaysUntilCurrentGoesAway() {
        var d = SquadTabChoices()
        d.select(.available, for: "k")
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .best), .available, "the choice holds when Current appears")
        d.select(.current, for: "k")
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .best), .current)
        XCTAssertEqual(d.tab("k", hasCurrent: false, mode: .best), .best, "Current is gone: back to the remembered choice")
        d.clearTab(for: "k")
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .available), .current)
    }

    /// H1: another account's tab choices are dropped.
    func testAnotherAccountStartsWithNoTabChoice() {
        var d = SquadTabChoices()
        d.switchAccount("A")
        d.select(.best, for: "a")
        d.switchAccount("A")
        XCTAssertEqual(d.tab("a", hasCurrent: false, mode: .available), .best, "the same account keeps its choice")
        d.switchAccount("B")
        XCTAssertEqual(d.account, "B")
        XCTAssertEqual(d.tab("a", hasCurrent: false, mode: .available), .available)
    }

    // MARK: the tab a squad was last on survives a relaunch (D74)

    func testTheStoredTabRoundTripsAndAnOldFileWithoutItDecodes() throws {
        var store = SquadStore()
        store.setTab(.available, .gym)
        store.setTab(.best, .pvp(league: "gl"))
        let again = try JSONDecoder().decode(SquadStore.self, from: JSONEncoder().encode(store))
        XCTAssertEqual(again, store)
        XCTAssertEqual(again.storedTab(.gym), .available)
        XCTAssertEqual(again.storedTab(.pvp(league: "gl")), .best)
        XCTAssertNil(again.storedTab(.rocket(leader: "Arlo")))
        let old = try JSONDecoder().decode(SquadStore.self, from: Data(#"{"version":2,"modes":{"raids":"best"}}"#.utf8))
        XCTAssertEqual(old.tabs, [:], "a version-2 file written before the tabs were kept")
        XCTAssertEqual(old.version, 2)
        var cleared = store
        cleared.clearTab(.gym)
        XCTAssertNil(cleared.storedTab(.gym))
    }

    func testAStoredTabGoesWithItsEvent() {
        var store = SquadStore()
        func r(_ from: String, _ to: String, _ title: String) -> HubData.RotationRow { HubData.RotationRow(from: from, to: to, kind: .fiveStar, title: title, bosses: [], note: "", source: "", tba: nil) }
        let ended = r("2026-10-01", "2026-10-10", "Palkia"), later = r("2026-10-20", "2026-12-01", "Dialga")
        store.setTab(.available, .event(row: ended, screen: .raids))
        store.setTab(.best, .event(row: later, screen: .max))
        store.setTab(.available, .gym)
        let pruned = store.pruned(today: "2026-11-01", rotation: [])
        XCTAssertNil(pruned.storedTab(.event(row: ended, screen: .raids)), "the event ended")
        XCTAssertEqual(pruned.storedTab(.event(row: later, screen: .max)), .best)
        XCTAssertEqual(pruned.storedTab(.gym), .available, "a squad that is not an event's stays")
    }

    func testTheStoredTabIsReadAfterTheChoiceAndBeforeTheDefault() {
        var d = SquadTabChoices()
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .best, stored: .available), .available, "stored Available with a Current present")
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .best, stored: .current), .current)
        XCTAssertEqual(d.tab("k", hasCurrent: false, mode: .best, stored: .current), .best, "stored Current with no Current: the mode's tab")
        XCTAssertEqual(d.tab("k", hasCurrent: false, mode: .available, stored: .best), .best)
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .best, stored: nil), .current, "never chosen: Current")
        d.select(.best, for: "k")
        XCTAssertEqual(d.tab("k", hasCurrent: true, mode: .available, stored: .available), .best, "a fresh choice wins over the stored one")
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
