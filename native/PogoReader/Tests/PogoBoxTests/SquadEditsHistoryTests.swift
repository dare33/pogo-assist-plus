import XCTest
@testable import PogoBox

/// Pass 2-6, rule 27: Available and Best edits are stored per squad, tab and (Raids) style; the history of earlier Current squads; "set" is "has a Current"; file version 2.
final class SquadEditsHistoryTests: XCTestCase {
    private func row(_ title: String = "Palkia", from: String = "2026-11-01", to: String = "2026-11-30", kind: HubData.Kind = .fiveStar) -> HubData.RotationRow {
        HubData.RotationRow(from: from, to: to, kind: kind, title: title, bosses: [], note: "", source: "", tba: nil)
    }
    private func squad(_ picks: [String?], changed: Bool = true) -> SquadStore.Saved {
        SquadStore.Saved(slots: picks.map { SquadSlot(role: "X", pick: $0) }, isSet: false, changed: changed)
    }
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ n: Int) -> Date { t0.addingTimeInterval(Double(n) * 60) }
    private var raids: SquadRef { .event(row: row(), screen: .raids) }

    // MARK: stored edits

    func testEditsAreKeptPerSquadTabAndRaidsStyle() throws {
        var store = SquadStore()
        store.setEdit(squad(["a"]), raids, .available, style: .balanced)
        store.setEdit(squad(["b"]), raids, .best, style: .balanced)
        store.setEdit(squad(["c"]), raids, .available, style: .maxDamage)
        store.setEdit(squad(["g"]), .gym, .best, style: .balanced)
        XCTAssertEqual(store.edit(raids, .available, style: .balanced)?.slots.first?.pick, "a")
        XCTAssertEqual(store.edit(raids, .best, style: .balanced)?.slots.first?.pick, "b")
        XCTAssertEqual(store.edit(raids, .available, style: .maxDamage)?.slots.first?.pick, "c")
        XCTAssertNil(store.edit(raids, .best, style: .maxDamage))
        XCTAssertNil(store.edit(.event(row: row("Dialga"), screen: .raids), .available, style: .balanced), "another event")
        XCTAssertNil(store.edit(raids, .current, style: .balanced), "Current has no edit")
        // The style is part of the key only on Raids.
        XCTAssertEqual(store.edit(.gym, .best, style: .maxDamage)?.slots.first?.pick, "g")
        XCTAssertTrue(store.edits.keys.contains("raids|2026-11-01|5star|Palkia|maxDamage|available"))
        XCTAssertTrue(store.edits.keys.contains("gym|best"))
        // They survive a write and a read.
        let back = try JSONDecoder().decode(SquadStore.self, from: JSONEncoder().encode(store))
        XCTAssertEqual(back, store)
        XCTAssertEqual(back.edit(raids, .available, style: .maxDamage)?.slots.first?.pick, "c")
    }

    func testDiffersAndReset() {
        var store = SquadStore()
        XCTAssertFalse(store.differs(.gym, .available, style: .balanced))
        store.setEdit(squad(["a"]), .gym, .available, style: .balanced)
        XCTAssertTrue(store.differs(.gym, .available, style: .balanced))
        XCTAssertFalse(store.differs(.gym, .best, style: .balanced))
        store.setEdit(squad(["a"], changed: false), .gym, .best, style: .balanced)
        XCTAssertFalse(store.differs(.gym, .best, style: .balanced), "an entry that is not changed does not differ")
        store.resetEdit(.gym, .available, style: .balanced)
        XCTAssertNil(store.edit(.gym, .available, style: .balanced))
        XCTAssertFalse(store.differs(.gym, .available, style: .balanced))
        XCTAssertNotNil(store.edit(.gym, .best, style: .balanced), "only that tab's edit goes")
    }

    func testReconciledEmptiesAnEditsLostPickButNeverAHistoryEntrys() {
        var store = SquadStore()
        store.setEdit(squad(["gone", "kept"]), .gym, .best, style: .balanced)
        store.setCurrent(squad(["x"]), .gym)
        store.replaceCurrent(with: squad(["y"]), .gym, source: .available, edited: false, strength: 50, date: at(1))
        store.history["gym"] = [HistoryEntry(date: at(0), slots: [SquadSlot(role: "X", pick: "gone")], source: .best, edited: true, strength: 70)]
        let out = store.reconciled(boxIds: ["kept", "y"])
        XCTAssertEqual(out.edit(.gym, .best, style: .balanced)?.slots.map(\.pick), [nil, "kept"])
        XCTAssertEqual(out.history["gym"]?.first?.slots.first?.pick, "gone", "history is drawn as gone, not emptied")
        XCTAssertEqual(out.current(.gym)?.slots.first?.pick, "y")
    }

    func testPruningDropsAnEventsEditsAndHistoryWithIt() {
        var store = SquadStore()
        let live = SquadRef.event(row: row("Dialga", to: "2026-12-10"), screen: .raids)
        let maxRef = SquadRef.event(row: row("Gmax", to: "2026-11-20", kind: .maxEvent), screen: .max)
        for r in [raids, live, maxRef] {
            store.setEdit(squad(["e"]), r, .available, style: .balanced)
            store.setEdit(squad(["e"]), r, .best, style: .maxDamage)
            store.setCurrent(squad(["c"]), r)
            store.replaceCurrent(with: squad(["d"]), r, source: .best, edited: true, strength: 40, date: at(1))
        }
        store.setEdit(squad(["g"]), .gym, .available, style: .balanced)
        store.pushHistory(squad(["g"]), .gym, source: .best, edited: false, strength: nil, date: at(2))
        let out = store.pruned(today: "2026-12-01", rotation: [])
        XCTAssertNil(out.edit(raids, .available, style: .balanced))
        XCTAssertNil(out.edit(maxRef, .best, style: .maxDamage))
        XCTAssertNil(out.history[raids.key]); XCTAssertNil(out.history[maxRef.key])
        XCTAssertNotNil(out.edit(live, .available, style: .balanced), "an event still running keeps its edits")
        XCTAssertNotNil(out.edit(live, .best, style: .maxDamage))
        XCTAssertNotNil(out.history[live.key])
        XCTAssertNotNil(out.edit(.gym, .available, style: .balanced), "the Gym has no end")
        XCTAssertNotNil(out.history["gym"])
        // The rotation's current last day wins over the stored one.
        let moved = store.pruned(today: "2026-12-01", rotation: [row(to: "2026-12-05")])
        XCTAssertNotNil(moved.edit(raids, .available, style: .balanced))
        XCTAssertNotNil(moved.history[raids.key])
    }

    // MARK: history

    func testHistoryPushOrderCapAndNoConsecutiveDuplicate() {
        var store = SquadStore()
        for i in 0..<12 { store.pushHistory(squad(["p\(i)"]), .gym, source: .available, edited: i % 2 == 0, strength: i, date: at(i)) }
        let list = store.history["gym"]!
        XCTAssertEqual(list.count, 10)
        XCTAssertEqual(list.first?.slots.first?.pick, "p11", "newest first")
        XCTAssertEqual(list.last?.slots.first?.pick, "p2", "the two oldest fell off")
        XCTAssertEqual(list.first?.strength, 11)
        XCTAssertEqual(list.first?.edited, false)
        store.pushHistory(squad(["p11"]), .gym, source: .best, edited: true, strength: 99, date: at(20))
        XCTAssertEqual(store.history["gym"]?.count, 10)
        XCTAssertEqual(store.history["gym"]?.first?.date, at(11), "the same squad as the newest entry is not added again")
        store.pushHistory(squad(["p5"]), .gym, source: .best, edited: true, strength: 99, date: at(21))
        XCTAssertEqual(store.history["gym"]?.count, 10, "an older duplicate is not consecutive, so it is added; the cap holds")
        XCTAssertEqual(store.history["gym"]?.first?.slots.first?.pick, "p5")
        XCTAssertNil(store.history["rocket|Arlo"], "each squad has its own list")
    }

    func testReplacingCurrentPushesTheOldOneOnlyWhenItDiffers() {
        var store = SquadStore()
        store.replaceCurrent(with: squad(["a"]), .gym, source: .available, edited: false, strength: 10, date: at(1))
        XCTAssertTrue(store.history.isEmpty, "nothing to push when there was no Current")
        XCTAssertEqual(store.current(.gym)?.isSet, true)
        store.replaceCurrent(with: squad(["a"]), .gym, source: .best, edited: false, strength: 10, date: at(2))
        XCTAssertTrue(store.history.isEmpty, "the same squad is not a replacement")
        store.replaceCurrent(with: squad(["b"]), .gym, source: .best, edited: true, strength: 60, date: at(3))
        XCTAssertEqual(store.history["gym"]?.map { $0.slots.first?.pick }, ["a"])
        XCTAssertEqual(store.history["gym"]?.first?.source, .best)
        XCTAssertEqual(store.history["gym"]?.first?.edited, true)
        XCTAssertEqual(store.history["gym"]?.first?.strength, 60)
        XCTAssertEqual(store.current(.gym)?.slots.first?.pick, "b")
    }

    func testRestoreMakesTheEntryCurrentAndTheOldCurrentTheNewest() {
        var store = SquadStore()
        store.replaceCurrent(with: squad(["a"]), .gym, source: .available, edited: false, strength: 1, date: at(1))
        store.replaceCurrent(with: squad(["b"]), .gym, source: .available, edited: false, strength: 2, date: at(2))
        store.replaceCurrent(with: squad(["c"]), .gym, source: .available, edited: false, strength: 3, date: at(3))
        XCTAssertEqual(store.history["gym"]?.map { $0.slots.first?.pick }, ["b", "a"])
        let previous = store.restoreFromHistory(.gym, index: 1, strength: 77, date: at(4))
        XCTAssertEqual(previous?.slots.first?.pick, "c", "the Current it replaced, for Undo")
        XCTAssertEqual(store.current(.gym)?.slots.first?.pick, "a")
        XCTAssertEqual(store.current(.gym)?.isSet, true)
        XCTAssertEqual(store.history["gym"]?.map { $0.slots.first?.pick }, ["c", "b"], "the entry left the list and the old Current is on top")
        XCTAssertEqual(store.history["gym"]?.first?.strength, 77)
        XCTAssertEqual(store.history["gym"]?.first?.source, .current)
        XCTAssertNil(store.restoreFromHistory(.gym, index: 9, strength: nil, date: at(5)), "out of range changes nothing")
        XCTAssertEqual(store.history["gym"]?.count, 2)
    }

    func testRestoreWithNoCurrentJustSetsIt() {
        var store = SquadStore()
        store.pushHistory(squad(["a"]), .gym, source: .best, edited: false, strength: 5, date: at(1))
        XCTAssertNil(store.restoreFromHistory(.gym, index: 0, strength: nil, date: at(2)))
        XCTAssertEqual(store.current(.gym)?.slots.first?.pick, "a")
        XCTAssertEqual(store.history["gym"]?.count, 0)
    }

    func testUnsetMovesCurrentToHistoryAndSetFollowsCurrent() {
        var store = SquadStore()
        let ref = SquadRef.rocket(leader: "Arlo")
        XCTAssertFalse(store.isSet(ref))
        store.replaceCurrent(with: squad(["a"]), ref, source: .available, edited: false, strength: nil, date: at(1))
        XCTAssertTrue(store.isSet(ref))
        store.unsetCurrent(ref, strength: 42, date: at(2))
        XCTAssertFalse(store.isSet(ref))
        XCTAssertNil(store.current(ref))
        XCTAssertEqual(store.history[ref.key]?.first?.slots.first?.pick, "a")
        XCTAssertEqual(store.history[ref.key]?.first?.strength, 42)
        store.unsetCurrent(ref, strength: nil, date: at(3))
        XCTAssertEqual(store.history[ref.key]?.count, 1, "unsetting nothing adds nothing")
        // A Current with the mark cleared but picks kept is still set.
        var s = squad(["z"]); s.isSet = false
        store.setCurrent(s, ref)
        XCTAssertTrue(store.isSet(ref))
        store.deleteCurrent(ref)
        XCTAssertFalse(store.isSet(ref))
        XCTAssertEqual(store.history[ref.key]?.first?.slots.first?.pick, "z", "deleteCurrent does what unsetCurrent does")
    }

    // MARK: file version 2

    func testAVersionOneFileDecodesWithEmptyEditsAndHistory() throws {
        let json = #"{"version":1,"gym":{"slots":[{"role":"Defender","pick":"k"}],"isSet":false},"raidStyle":"maxDamage"}"#
        let store = try JSONDecoder().decode(SquadStore.self, from: Data(json.utf8))
        XCTAssertTrue(store.edits.isEmpty); XCTAssertTrue(store.history.isEmpty); XCTAssertTrue(store.eventEnds.isEmpty)
        XCTAssertEqual(store.version, 2)
        XCTAssertEqual(store.current(.gym)?.slots.first?.pick, "k")
        XCTAssertEqual(store.raidStyle, .maxDamage)
    }

    func testTheNewFileKeepsEveryOldKey() throws {
        var store = SquadStore()
        store.setCurrent(squad(["a"]), .gym)
        store.setEdit(squad(["b"]), .gym, .best, style: .balanced)
        store.pushHistory(squad(["c"]), .gym, source: .best, edited: false, strength: 3, date: at(1))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(store)) as? [String: Any])
        for key in ["version", "raids", "max", "gym", "rocket", "pvp", "modes", "raidStyle"] { XCTAssertNotNil(obj[key], key) }
        XCTAssertEqual(obj["version"] as? Int, 2)
        let gym = try XCTUnwrap(obj["gym"] as? [String: Any])
        for key in ["slots", "isSet", "changed"] { XCTAssertNotNil(gym[key], key) }
    }

    func testAMarkOnlySquadBecomesACurrent() throws {
        let json = #"{"version":1,"gym":{"slots":[{"role":"Defender"}],"isSet":true},"rocket":{"Arlo":{"slots":[{"role":"Defender"}],"isSet":false}}}"#
        let store = try JSONDecoder().decode(SquadStore.self, from: Data(json.utf8)).migrated()
        XCTAssertTrue(store.isSet(.gym))
        XCTAssertEqual(store.gym.changed, true)
        XCTAssertFalse(store.isSet(.rocket(leader: "Arlo")), "nothing kept, no Current")
    }
}
