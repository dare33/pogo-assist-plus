import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// Where the squad screens keep a player's squads (CONCEPTS rule 27): one store per account in the phone's defaults, read back by a later screen, with the keeping
/// rules applied when the box is loaded and left alone when it is not.
@MainActor
final class SquadKeeperTests: XCTestCase {
    private let account = "Squad Keeper Test A", other = "Squad Keeper Test B", renamed = "Squad Keeper Test C"

    override func setUp() { clean() }
    override func tearDown() { clean() }
    private func clean() { for a in [account, other, renamed] { UserDefaults.standard.removeObject(forKey: SquadKeeper.key(a)) } }

    private func row(_ from: String, _ to: String, title: String = "Palkia") -> HubData.RotationRow {
        HubData.RotationRow(from: from, to: to, kind: .fiveStar, title: title, bosses: [], note: "", source: "", tba: nil)
    }

    /// Attaches as the screens do: `ids` are the loaded box's copies, nil a box that is not loaded yet.
    private func attach(_ k: SquadKeeper, _ account: String, ids: [String]?, today: String = "2026-10-26", rotation: [HubData.RotationRow] = []) {
        k.attach(account: account, today: today, rotation: rotation, boxIds: ids.map(Set.init))
    }

    /// A screen's workspace as the screens attach it: on the test account.
    private func makeWS() -> SquadWorkspace { let w = SquadWorkspace(); w.attach(account: account, boxIds: nil); return w }

    func testWhatOneScreenKeepsAnotherReadsBack() {
        let first = SquadKeeper()
        attach(first, account, ids: ["a", "b"])
        first.update { $0.gym.choose("b", at: 1); $0.setMode(.best, for: .gym) }

        let later = SquadKeeper()
        attach(later, account, ids: ["a", "b"])
        XCTAssertEqual(later.store.gym.slots[1].pick, "b", "a distinct pick survives leaving and re-entering a screen")
        XCTAssertEqual(later.store.mode(for: .gym), .best, "Available | Best is remembered per screen")

        let elsewhere = SquadKeeper()
        attach(elsewhere, other, ids: ["a", "b"])
        XCTAssertNil(elsewhere.store.gym.slots[1].pick, "another account has its own squads")
        XCTAssertEqual(elsewhere.store.mode(for: .gym), .available, "and the default mode")
    }

    func testEveryScreensPicksAreKeptAsChosen() {
        let r = row("2026-10-20", "2026-10-27")
        let k = SquadKeeper()
        attach(k, account, ids: ["a", "b", "c"], rotation: [r])
        k.update { s in
            var raid = s.eventSquad(r, screen: .raids); raid.choose("c", at: 2); s.saveEventSquad(raid, row: r, screen: .raids)
            var max = s.eventSquad(r, screen: .max); max.choose("b", at: 0); max.isSet = true; s.saveEventSquad(max, row: r, screen: .max)
            var rocket = s.rocketSquad(leader: "Giovanni"); rocket.choose("b", at: 2); s.rocket["Giovanni"] = rocket
            var pvp = s.pvpSquad(league: "ul"); pvp.choose("a", at: 1); pvp.changeRole(at: 1, to: "All") { _ in true }; s.pvp["ul"] = pvp
        }
        let later = SquadKeeper()
        attach(later, account, ids: ["a", "b", "c"], rotation: [r])
        XCTAssertEqual(later.store.eventSquad(r, screen: .raids).slots[2].pick, "c")
        XCTAssertEqual(later.store.eventSquad(r, screen: .max).slots[0].pick, "b")
        XCTAssertTrue(later.store.eventSquad(r, screen: .max).isSet)
        XCTAssertEqual(later.store.rocketSquad(leader: "Giovanni").slots[2].pick, "b")
        XCTAssertEqual(later.store.pvpSquad(league: "ul").slots[1].pick, "a")
        XCTAssertEqual(later.store.pvpSquad(league: "ul").slots[1].role, "All")
    }

    func testAPickWhoseCopyLeftTheBoxEmptiesItsSlot() {
        let keeper = SquadKeeper()
        attach(keeper, account, ids: ["a", "b"])
        keeper.update { $0.gym.choose("a", at: 0); $0.gym.choose("b", at: 1) }

        let afterRescan = SquadKeeper()
        attach(afterRescan, account, ids: ["b"])
        XCTAssertNil(afterRescan.store.gym.slots[0].pick, "the copy that left empties the slot, which refills with the suggestion")
        XCTAssertEqual(afterRescan.store.gym.slots[1].pick, "b", "the copy still in the box keeps its slot")
        XCTAssertNil(SquadKeeper.load(account).gym.slots[0].pick, "and the emptied slot is what is kept")
    }

    func testABoxNotLoadedYetLeavesThePicksAloneButALoadedEmptyBoxDropsThem() {
        let keeper = SquadKeeper()
        attach(keeper, account, ids: ["a"])
        keeper.update { $0.gym.choose("a", at: 0) }

        let early = SquadKeeper()
        attach(early, account, ids: nil)
        XCTAssertEqual(early.store.gym.slots[0].pick, "a", "a box that is not loaded yet says nothing about the copies")
        XCTAssertEqual(SquadKeeper.load(account).gym.slots[0].pick, "a", "and nothing is written")

        let emptied = SquadKeeper()
        attach(emptied, account, ids: [])
        XCTAssertNil(emptied.store.gym.slots[0].pick, "a loaded box whose last copy was deleted empties the slot")
        XCTAssertNil(SquadKeeper.load(account).gym.slots[0].pick)
    }

    func testAnEndedEventSquadIsDroppedAndOneWhoseEndMovedIsKept() {
        let moved = row("2026-10-20", "2026-10-25", title: "Moved"), ended = row("2026-10-18", "2026-10-25", title: "Ended"), later = row("2026-10-28", "2026-11-04", title: "Later")
        let k = SquadKeeper()
        attach(k, account, ids: ["a"], today: "2026-10-24", rotation: [moved, ended, later])
        k.update { s in
            for r in [moved, ended, later] {
                var sq = s.eventSquad(r, screen: .raids); sq.choose("a", at: 0); s.saveEventSquad(sq, row: r, screen: .raids)
                var mx = s.eventSquad(r, screen: .max); mx.isSet = true; s.saveEventSquad(mx, row: r, screen: .max)
            }
        }
        // Two days on: "Ended" is gone from the rotation (its stored last day, the 25th, has passed); "Moved" was extended to the 30th in the rotation.
        let extended = row("2026-10-20", "2026-10-30", title: "Moved")
        let reopened = SquadKeeper()
        attach(reopened, account, ids: ["a"], today: "2026-10-27", rotation: [extended, later])
        XCTAssertNil(reopened.store.raids[SquadStore.eventKey(ended)], "a raid squad whose event has ended is dropped")
        XCTAssertNil(reopened.store.max[SquadStore.eventKey(ended)], "and a Max squad")
        XCTAssertEqual(reopened.store.raids[SquadStore.eventKey(extended)]?.squad.slots[0].pick, "a", "an event whose last day moved is judged by the new day")
        XCTAssertEqual(reopened.store.raids[SquadStore.eventKey(extended)]?.endsOn, "2026-10-30")
        XCTAssertTrue(reopened.store.max[SquadStore.eventKey(later)]?.squad.isSet == true, "an event still to come is kept")
    }

    func testARenamedAccountTakesItsSquadsWithIt() {
        let keeper = SquadKeeper()
        attach(keeper, account, ids: ["a"])
        keeper.update { $0.gym.choose("a", at: 2) }
        AppModel.moveAccountKeys(from: account, to: renamed)
        XCTAssertEqual(SquadKeeper.load(renamed).gym.slots[2].pick, "a")
        XCTAssertNil(UserDefaults.standard.data(forKey: SquadKeeper.key(account)), "the old name keeps nothing")
    }

    // MARK: Current | Available | Best (pass 2-5, rule 27): the workspace routes an edit to Current or to a draft

    /// A squad of three slots filled the way a screen fills it, for the workspace tests.
    private func shown(_ saved: SquadStore.Saved, _ ranked: [String] = ["a", "b", "c", "d"]) -> [FilledSlot] {
        HubSquads.fill(slots: saved.slots, pool: { _, _ in .init(preferred: ranked) })
    }

    func testAnEditOnAvailableOrBestIsADraftNeverStoredAndNeverSwitchesTheTab() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultRocketSlots(), ref = SquadRef.rocket(leader: "Arlo")
        var s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertEqual(s.tab, .available)
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 0, shown: self.shown($0)) }
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertEqual(s.tab, .available, "editing never switches tabs")
        XCTAssertTrue(s.isEdited(filled: shown(s.squad), suggested: { self.shown(SquadStore.Saved(slots: defaults)) }), "the squad as drawn differs from the suggestion")
        XCTAssertEqual(s.squad.slots[0].pick, "d")
        XCTAssertNil(keeper.store.current(ref), "nothing is stored")
        XCTAssertNil(SquadKeeper.load(account).current(ref), "and nothing is written")
        // Switching tabs keeps the draft; the other tab starts from the suggestion.
        ws.select(.best, ref: ref, keeper: keeper)
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertEqual(s.tab, .best)
        XCTAssertFalse(s.differs, "Best starts from the suggestion")
        XCTAssertTrue(s.isBestSuggestion)
        ws.select(.available, ref: ref, keeper: keeper)
        XCTAssertEqual(ws.surface(ref, store: keeper.store, defaults: defaults).squad.slots[0].pick, "d", "the Available draft is still there")
        XCTAssertEqual(keeper.store.mode(for: .rocket), .available, "Available and Best are remembered per screen")
        // Reset drops the draft at once.
        ws.reset(ws.surface(ref, store: keeper.store, defaults: defaults))
        XCTAssertNil(ws.surface(ref, store: keeper.store, defaults: defaults).draft)
    }

    func testAnotherScreenInstanceStartsFromTheSuggestionAgain() {
        // Leaving the screen drops its workspace: a new one holds no draft.
        let keeper = SquadKeeper()
        attach(keeper, account, ids: ["a", "b", "c"])
        let first = makeWS()
        let s = first.surface(.gym, store: keeper.store, defaults: HubSquads.defaultGymSlots())
        first.edit(s, keeper: keeper) { $0.choose("c", at: 0, shown: self.shown($0)) }
        XCTAssertNotNil(first.surface(.gym, store: keeper.store, defaults: HubSquads.defaultGymSlots()).draft)
        let later = makeWS()
        XCTAssertNil(later.surface(.gym, store: keeper.store, defaults: HubSquads.defaultGymSlots()).draft)
    }

    func testSaveToCurrentStoresTheDraftKeepsTheTabAndReplacesAnExistingCurrent() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultRocketSlots(), ref = SquadRef.rocket(leader: "Arlo")
        var s = ws.surface(ref, store: keeper.store, defaults: defaults)
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 1, shown: self.shown($0)) }
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        ws.saveToCurrent(s, keeper: keeper, filled: shown(s.squad), setMark: false)
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertEqual(s.tab, .available, "the player stays on the tab they are on")
        XCTAssertTrue(s.hasCurrent, "and the Current tab appears")
        XCTAssertTrue(s.justSaved, "the squad says Saved to Current")
        XCTAssertEqual(keeper.store.current(ref)?.slots.map(\.pick), ["a", "d", "c"].map { Optional($0) }, "the draft as shown, every slot kept")
        XCTAssertEqual(SquadKeeper.load(account).current(ref)?.slots[1].pick, "d", "written at once")
        // A further edit of the draft is not saved; saving again replaces Current.
        ws.edit(s, keeper: keeper) { $0.choose("b", at: 2, shown: self.shown($0, ["a", "d", "c", "b"])) }
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertFalse(s.justSaved)
        XCTAssertEqual(keeper.store.current(ref)?.slots[2].pick, "c", "Current is unchanged until saved")
        ws.saveToCurrent(s, keeper: keeper, filled: shown(s.squad, ["a", "d", "c", "b"]), setMark: false)
        XCTAssertEqual(keeper.store.current(ref)?.slots[2].pick, "b")
    }

    func testAnEditOnCurrentIsStoredAtOnceAndLeavesTheDraftsAlone() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultPvpSlots(), ref = SquadRef.pvp(league: "gl")
        var s = ws.surface(ref, store: keeper.store, defaults: defaults)
        ws.edit(s, keeper: keeper) { $0.choose("c", at: 0, shown: self.shown($0)) }
        ws.saveToCurrent(ws.surface(ref, store: keeper.store, defaults: defaults), keeper: keeper, filled: shown(ws.surface(ref, store: keeper.store, defaults: defaults).squad), setMark: false)
        ws.select(.current, ref: ref, keeper: keeper)
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertEqual(s.tab, .current)
        XCTAssertTrue(s.kept)
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 2, shown: self.shown($0, ["c", "a", "b", "d"])) }
        XCTAssertEqual(keeper.store.current(ref)?.slots[2].pick, "d", "Current saves straight away")
        XCTAssertEqual(SquadKeeper.load(account).current(ref)?.slots[2].pick, "d")
        XCTAssertEqual(ws.surface(ref, store: keeper.store, defaults: defaults).tab, .current, "and stays on Current")
        XCTAssertEqual(keeper.store.mode(for: .pvp), .available, "choosing Current does not change the remembered Available | Best")
    }

    func testDeleteCurrentSquadRemovesItAndShowsTheRememberedTab() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        ws.select(.best, ref: .gym, keeper: keeper)
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.saveToCurrent(s, keeper: keeper, filled: shown(s.squad), setMark: true)
        ws.select(.current, ref: .gym, keeper: keeper)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertEqual(s.current?.isSet, true, "Set this squad on Best saved it and set the mark")
        ws.deleteCurrent(s, keeper: keeper)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertNil(keeper.store.current(.gym))
        XCTAssertEqual(s.tab, .best, "back to the remembered tab")
        XCTAssertTrue(s.draft != nil, "Available and Best are not changed")
    }

    // MARK: fold round 1

    /// H1: another account starts with no drafts, and a surface drawn for one account cannot save into another's store.
    func testAnotherAccountShowsNoDraftAndASurfaceFromTheFirstCannotSaveIntoIt() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c"])
        ws.attach(account: account, boxIds: ["a", "b", "c"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.edit(s, keeper: keeper) { $0.choose("c", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertNotNil(s.draft)
        attach(keeper, other, ids: ["a", "b", "c"])
        ws.attach(account: other, boxIds: ["a", "b", "c"])
        XCTAssertNil(ws.surface(.gym, store: keeper.store, defaults: defaults).draft, "the new account's screen starts as on first open")
        ws.saveToCurrent(s, keeper: keeper, filled: shown(s.squad), setMark: false)
        XCTAssertNil(keeper.store.current(.gym), "the first account's draft was not written into the second account's store")
        XCTAssertNil(SquadKeeper.load(other).current(.gym))
    }

    /// H2: a draft follows the box: a pick whose copy left is emptied and the refill is kept in the draft (through the workspace).
    func testADraftPickWhoseCopyLeftTheBoxIsEmptiedAndTheRefillIsKept() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        ws.attach(account: account, boxIds: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 0, shown: self.shown($0)) }
        ws.attach(account: account, boxIds: ["a", "b", "c"])
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertNil(s.squad.slots[0].pick, "no ghost id")
        let filled = shown(s.squad, ["a", "b", "c", "e"])
        XCTAssertTrue(s.squad.needsAdopting(filled), "that slot alone refills")
        ws.edit(s, keeper: keeper) { $0.adoptRefills(filled) }
        XCTAssertNotNil(ws.surface(.gym, store: keeper.store, defaults: defaults).squad.slots[0].pick, "and the refill is kept in the draft")
    }

    /// H4: an old file's squad becomes a durable Current: after its copy leaves the box it remains, and the migration is written back.
    func testAnOldFilesSquadSurvivesItsCopyLeavingTheBoxAndIsWrittenBackChanged() {
        let old = #"{"version":1,"gym":{"slots":[{"role":"Defender","pick":"gone"},{"role":"Defender"}],"isSet":false}}"#
        UserDefaults.standard.set(Data(old.utf8), forKey: SquadKeeper.key(account))
        let keeper = SquadKeeper()
        attach(keeper, account, ids: ["other"])
        XCTAssertNotNil(keeper.store.current(.gym), "Current remains")
        XCTAssertNil(keeper.store.gym.slots[0].pick, "the slot refills")
        XCTAssertTrue(keeper.store.gym.changed)
        XCTAssertTrue(SquadKeeper.load(account).gym.changed, "the migration is stored")
        let again = SquadKeeper()
        attach(again, account, ids: ["other", "x"])
        XCTAssertNotNil(again.store.current(.gym), "a later box change refills instead of dropping Current")
    }

    /// H5 and H17: after Delete, Save shows again for the draft and "Saved to Current" does not; replacing Current from another tab also ends it.
    func testDeleteCurrentEndsSavedToCurrentAndSaveShowsAgain() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        ws.attach(account: account, boxIds: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.saveToCurrent(s, keeper: keeper, filled: shown(s.squad), setMark: false)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertTrue(s.justSaved)
        ws.select(.best, ref: .gym, keeper: keeper)
        var best = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.edit(best, keeper: keeper) { $0.choose("c", at: 1, shown: self.shown($0)) }
        best = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.saveToCurrent(best, keeper: keeper, filled: shown(best.squad), setMark: false)
        ws.select(.available, ref: .gym, keeper: keeper)
        XCTAssertFalse(ws.surface(.gym, store: keeper.store, defaults: defaults).justSaved, "Current was replaced from another tab")
        ws.deleteCurrent(ws.surface(.gym, store: keeper.store, defaults: defaults), keeper: keeper)
        ws.select(.best, ref: .gym, keeper: keeper)
        let after = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertFalse(after.justSaved, "after Delete the squad does not say Saved to Current")
        XCTAssertNotNil(after.draft, "and the draft is still there to be saved again")
    }

    /// H12: the replace question is for a Current that is a different squad; the set mark is not part of the squad.
    func testReplacingIsAskedOnlyWhenTheShownSquadDiffersFromCurrent() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        ws.attach(account: account, boxIds: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertFalse(s.replaces(filled: shown(s.squad)), "no Current: nothing to replace")
        ws.saveToCurrent(s, keeper: keeper, filled: shown(s.squad), setMark: false)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertFalse(s.replaces(filled: shown(s.squad)), "the unedited suggestion is the Current already")
        keeper.update { var c = $0.current(.gym)!; c.isSet = true; $0.setCurrent(c, .gym) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertFalse(s.replaces(filled: shown(s.squad)), "the set mark is ignored")
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertTrue(s.replaces(filled: shown(s.squad)), "a different squad would be replaced")
    }

    /// H6 and H17: a draft that is drawn the same as the suggestion is not edited, however it got there; "Set this squad" on an unedited tab leaves it unedited.
    func testADraftDrawnLikeTheSuggestionIsNotEdited() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        ws.attach(account: account, boxIds: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        let suggestion = { self.shown(SquadStore.Saved(slots: defaults)) }
        // Re-choosing the ticked Pokemon: a draft exists (the store's keeping flag is set) but the squad is drawn as the suggestion.
        ws.edit(s, keeper: keeper) { $0.choose("a", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertNotNil(s.draft)
        XCTAssertFalse(s.isEdited(filled: shown(s.squad), suggested: suggestion))
        // A role flipped and flipped back.
        ws.edit(s, keeper: keeper) { $0.changeRole(at: 1, to: "Other", fits: { _ in true }, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertTrue(s.isEdited(filled: shown(s.squad), suggested: suggestion), "a role differs")
        ws.edit(s, keeper: keeper) { $0.changeRole(at: 1, to: HubSquads.gymSlotRole, fits: { _ in true }, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertFalse(s.isEdited(filled: shown(s.squad), suggested: suggestion))
        // "Set this squad" on an unedited Best tab saves it and leaves it unedited, so it still reads as the best squad.
        ws.reset(s)
        ws.select(.best, ref: .gym, keeper: keeper)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.saveToCurrent(s, keeper: keeper, filled: shown(s.squad), setMark: true)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        let edited = s.with(edited: s.isEdited(filled: shown(s.squad), suggested: suggestion))
        XCTAssertFalse(edited.differs)
        XCTAssertTrue(edited.isBestSuggestion)
        XCTAssertTrue(edited.justSaved, "it still says Saved to Current")
        XCTAssertEqual(keeper.store.current(.gym)?.isSet, true)
    }
}
