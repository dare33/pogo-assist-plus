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

    // MARK: Available | Best | Current (pass 2-6, rule 27): the workspace routes an edit to Current or to the store's kept edit

    /// A squad of three slots filled the way a screen fills it, for the workspace tests.
    private func shown(_ saved: SquadStore.Saved, _ ranked: [String] = ["a", "b", "c", "d"]) -> [FilledSlot] {
        HubSquads.fill(slots: saved.slots, pool: { _, _ in .init(preferred: ranked) })
    }

    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// The pill's test as the screens make it: the tab's squad as drawn against the stored Current as drawn.
    private func isCurrent(_ s: SquadSurface) -> Bool {
        s.isCurrent(filled: shown(s.squad), currentFilled: { self.shown(s.current ?? SquadStore.Saved(slots: s.defaults)) })
    }

    func testAnEditOnAvailableOrBestIsKeptInTheStoreAndNeverSwitchesTheTab() {
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
        XCTAssertTrue(s.kept, "an edit is drawn as kept, like Current (rule 27.4)")
        XCTAssertNil(keeper.store.current(ref), "an edit is not a Current")
        XCTAssertEqual(keeper.store.edit(ref, .available, style: .balanced)?.slots[0].pick, "d", "it is stored")
        XCTAssertEqual(SquadKeeper.load(account).edit(ref, .available, style: .balanced)?.slots[0].pick, "d", "and written at once")
        // Switching tabs keeps it; the other tab starts from the suggestion.
        ws.select(.best, ref: ref, keeper: keeper)
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertEqual(s.tab, .best)
        XCTAssertFalse(s.differs)
        XCTAssertTrue(s.isBestSuggestion)
        XCTAssertFalse(s.kept)
        ws.select(.available, ref: ref, keeper: keeper)
        XCTAssertEqual(ws.surface(ref, store: keeper.store, defaults: defaults).squad.slots[0].pick, "d", "the Available edit is still there")
        XCTAssertEqual(keeper.store.mode(for: .rocket), .available, "Available and Best are remembered per screen")
        // Reset to suggestion drops it at once.
        ws.reset(ws.surface(ref, store: keeper.store, defaults: defaults), keeper: keeper)
        XCTAssertNil(ws.surface(ref, store: keeper.store, defaults: defaults).edit)
        XCTAssertNil(SquadKeeper.load(account).edit(ref, .available, style: .balanced))
    }

    func testAnEditSurvivesLeavingTheScreenAndTheApp() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c"])
        let s = ws.surface(.gym, store: keeper.store, defaults: HubSquads.defaultGymSlots())
        ws.edit(s, keeper: keeper) { $0.choose("c", at: 0, shown: self.shown($0)) }
        // A new screen: a new keeper (read from the phone's defaults) and a new workspace.
        let later = SquadKeeper(), ws2 = makeWS()
        attach(later, account, ids: ["a", "b", "c"])
        XCTAssertEqual(ws2.surface(.gym, store: later.store, defaults: HubSquads.defaultGymSlots()).squad.slots[0].pick, "c")
    }

    func testRaidsKeepsEachStylesEditsAndASwitchLeavesCurrentAlone() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let r = row("2026-10-20", "2026-10-27"), ref = SquadRef.event(row: r, screen: .raids)
        let balanced = HubSquads.defaultRaidSlots(style: .balanced), maxDamage = HubSquads.defaultRaidSlots(style: .maxDamage)
        var s = ws.surface(ref, store: keeper.store, defaults: balanced)
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 0, shown: self.shown($0)) }
        keeper.update { $0.raidStyle = .maxDamage }
        s = ws.surface(ref, store: keeper.store, defaults: maxDamage)
        XCTAssertNil(s.edit, "the other style starts from its own suggestion")
        ws.edit(s, keeper: keeper) { $0.choose("c", at: 1, shown: self.shown($0)) }
        keeper.update { $0.raidStyle = .balanced }
        XCTAssertEqual(ws.surface(ref, store: keeper.store, defaults: balanced).squad.slots[0].pick, "d", "switching back shows the Balanced edit again")
        XCTAssertEqual(keeper.store.edits.count, 2)
    }

    func testSetThisSquadReplacesWithNoQuestionKeepsTheTabAndUndoPutsTheOldOneBack() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultRocketSlots(), ref = SquadRef.rocket(leader: "Arlo")
        var s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertFalse(isCurrent(s), "no Current: the pill reads Set this squad")
        // The first set: nothing is replaced, the player stays on Available and the Current segment appears.
        XCTAssertFalse(ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: 41, date: t0))
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertEqual(s.tab, .available, "the player stays on the tab")
        XCTAssertTrue(s.hasCurrent)
        XCTAssertTrue(keeper.store.isSet(ref))
        XCTAssertTrue(isCurrent(s), "the pill reads Squad set")
        XCTAssertEqual(keeper.store.current(ref)?.strength, 41)
        XCTAssertEqual(keeper.store.current(ref)?.source, .available)
        // An edit makes it a different squad: the pill reads Set this squad again; setting replaces, with the old one in the history.
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 1, shown: self.shown($0)) }
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertFalse(isCurrent(s))
        XCTAssertTrue(ws.setCurrent(s.with(edited: true), keeper: keeper, filled: shown(s.squad), strength: 55, date: t0.addingTimeInterval(60)), "a different Current was replaced")
        XCTAssertEqual(keeper.store.current(ref)?.slots[1].pick, "d")
        XCTAssertEqual(keeper.store.current(ref)?.edited, true)
        XCTAssertEqual(keeper.store.history[ref.key]?.count, 1)
        XCTAssertEqual(keeper.store.history[ref.key]?.first?.strength, 41, "the old Current keeps the figure it had")
        XCTAssertEqual(keeper.store.history[ref.key]?.first?.slots[1].pick, "b")
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertTrue(isCurrent(s))
        // Undo: the replaced squad is the Current again and the one just set is dropped.
        ws.undo(s, keeper: keeper)
        XCTAssertEqual(keeper.store.current(ref)?.slots[1].pick, "b")
        XCTAssertEqual(keeper.store.history[ref.key] ?? [], [], "the pushed row is gone")
        XCTAssertEqual(SquadKeeper.load(account).current(ref)?.slots[1].pick, "b", "written")
    }

    func testTappingSquadSetUnsetsAndUndoRestoresIt() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        ws.select(.best, ref: .gym, keeper: keeper)
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: 77, date: t0)
        ws.select(.current, ref: .gym, keeper: keeper)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertEqual(s.tab, .current)
        ws.unsetCurrent(s, keeper: keeper, date: t0.addingTimeInterval(5))
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertNil(keeper.store.current(.gym))
        XCTAssertFalse(s.hasCurrent)
        XCTAssertEqual(s.tab, .best, "the screen shows the remembered tab again")
        XCTAssertEqual(keeper.store.history["gym"]?.first?.strength, 77, "the entry keeps the figure the stored Current holds")
        ws.undo(s, keeper: keeper)
        XCTAssertNotNil(keeper.store.current(.gym), "Undo of an unset puts it back")
        XCTAssertEqual(keeper.store.history["gym"] ?? [], [])
    }

    func testSetSquadFromTheHistoryReplacesWithNoQuestionAndTheReplacedOneGoesToTheTop() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: 10, date: t0)                                   // a b c ...
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: 20, date: t0.addingTimeInterval(60))            // d ... ; history: a ...
        ws.select(.current, ref: .gym, keeper: keeper)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertTrue(ws.restore(s, keeper: keeper, index: 0, date: t0.addingTimeInterval(120)), "a different Current was replaced")
        XCTAssertEqual(keeper.store.current(.gym)?.slots[0].pick, "a")
        XCTAssertEqual(keeper.store.history["gym"]?.first?.slots[0].pick, "d", "the replaced squad is at the top")
        XCTAssertEqual(keeper.store.history["gym"]?.first?.strength, 20, "the replaced squad is recorded with the figure it holds")
        XCTAssertTrue(ws.undo(s, keeper: keeper))
        XCTAssertEqual(keeper.store.current(.gym)?.slots[0].pick, "d", "Undo puts the replaced Current back")
        XCTAssertEqual(keeper.store.history["gym"]?.first?.slots[0].pick, "a", "and the entry is back at its place (H1)")
        XCTAssertFalse(ws.undo(s, keeper: keeper), "the record is cleared")
    }

    func testAnEditOnCurrentIsStoredAtOnceAndLeavesTheEditsAlone() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultPvpSlots(), ref = SquadRef.pvp(league: "gl")
        var s = ws.surface(ref, store: keeper.store, defaults: defaults)
        ws.edit(s, keeper: keeper) { $0.choose("c", at: 0, shown: self.shown($0)) }
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: 30, date: t0)
        ws.select(.current, ref: ref, keeper: keeper)
        s = ws.surface(ref, store: keeper.store, defaults: defaults)
        XCTAssertEqual(s.tab, .current)
        XCTAssertTrue(s.kept)
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 2, shown: self.shown($0, ["c", "a", "b", "d"])) }
        XCTAssertEqual(keeper.store.current(ref)?.slots[2].pick, "d", "Current saves straight away")
        XCTAssertNil(keeper.store.current(ref)?.strength, "and the figure it was set with no longer describes it")
        XCTAssertEqual(SquadKeeper.load(account).current(ref)?.slots[2].pick, "d")
        XCTAssertEqual(ws.surface(ref, store: keeper.store, defaults: defaults).tab, .current, "and stays on Current")
        XCTAssertEqual(keeper.store.mode(for: .pvp), .available, "choosing Current does not change the remembered Available | Best")
        XCTAssertEqual(keeper.store.edit(ref, .available, style: .balanced)?.slots[0].pick, "c", "the Available edit is untouched")
        XCTAssertTrue(keeper.store.history.isEmpty, "edits on Current make no history row")
    }

    /// H6: a player's edit on Current clears the figure and the strength task writes the new one back (edited stays); an automatic refill does neither.
    func testTheStrengthTaskWritesTheCurrentsFigureBackAndARefillIsNotAnEdit() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: 30, date: t0)
        ws.select(.current, ref: .gym, keeper: keeper)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        // An automatic refill: a slot with no kept Pokémon takes what the screen shows, and the Current keeps its figure and is not marked edited.
        keeper.update { $0.gym.slots[0].pick = nil }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.adopt(s, keeper: keeper, filled: shown(s.squad))
        XCTAssertEqual(keeper.store.current(.gym)?.slots[0].pick, "a")
        XCTAssertEqual(keeper.store.current(.gym)?.strength, 30, "a refill does not clear the figure")
        XCTAssertNotEqual(keeper.store.current(.gym)?.edited, true, "and is not the player's edit")
        // The player's edit clears the figure; the task then writes it back, edited stays true.
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 1, shown: self.shown($0)) }
        XCTAssertNil(keeper.store.current(.gym)?.strength)
        XCTAssertEqual(keeper.store.current(.gym)?.edited, true)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.record(s, keeper: keeper, strength: 64)
        XCTAssertEqual(keeper.store.current(.gym)?.strength, 64)
        XCTAssertEqual(keeper.store.current(.gym)?.edited, true)
        // Replacing it now records that figure, not "—".
        ws.select(.available, ref: .gym, keeper: keeper)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.record(s, keeper: keeper, strength: 99)
        XCTAssertEqual(keeper.store.current(.gym)?.strength, 64, "only the Current tab writes the Current's figure")
        ws.edit(s, keeper: keeper) { $0.choose("c", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: 70, date: t0.addingTimeInterval(60))
        XCTAssertEqual(keeper.store.history["gym"]?.first?.strength, 64)
        // Delete records the same way.
        ws.unsetCurrent(ws.surface(.gym, store: keeper.store, defaults: defaults), keeper: keeper, date: t0.addingTimeInterval(120))
        XCTAssertEqual(keeper.store.history["gym"]?.first?.strength, 70)
    }

    /// H1: through the workspace, Undo reverses the last change exactly and a change that left nothing to undo gives a toast with no Undo.
    func testUndoThroughTheWorkspaceReversesTheLastChangeAndNoRecordMeansNoUndoAction() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        func surface() -> SquadSurface { ws.surface(.gym, store: keeper.store, defaults: defaults) }
        func set(_ pick: String, _ n: Int) {
            let s = surface()
            ws.edit(s, keeper: keeper) { $0.choose(pick, at: 0, shown: self.shown($0)) }
            let e = surface()
            ws.setCurrent(e, keeper: keeper, filled: shown(e.squad), strength: n, date: t0.addingTimeInterval(Double(n)))
            ws.reset(surface(), keeper: keeper)
        }
        set("a", 1); set("b", 2); set("c", 3)           // Current c; history [b, a]
        func history() -> [String?] { (keeper.store.history["gym"] ?? []).map { $0.slots[0].pick } }
        XCTAssertEqual(history(), ["b", "a"])
        XCTAssertNotNil(ws.undoAction(surface(), keeper: keeper))
        ws.select(.current, ref: .gym, keeper: keeper)
        XCTAssertTrue(ws.restore(surface(), keeper: keeper, index: 1, date: t0.addingTimeInterval(10)))
        XCTAssertEqual(keeper.store.current(.gym)?.slots[0].pick, "a")
        XCTAssertEqual(history(), ["c", "b"])
        let action = ws.undoAction(surface(), keeper: keeper)
        XCTAssertNotNil(action)
        action?.perform()
        XCTAssertEqual(keeper.store.current(.gym)?.slots[0].pick, "c")
        XCTAssertEqual(history(), ["b", "a"], "Undo gives back Current C and history [B, A]")
        XCTAssertNil(ws.undoAction(surface(), keeper: keeper), "the record is cleared: the toast carries no Undo")
        XCTAssertFalse(ws.undo(surface(), keeper: keeper))
        XCTAssertEqual(history(), ["b", "a"])
    }

    /// H8: a squad brought back from the history or by Undo is reconciled with the box: a copy that was transferred is emptied, so its slot refills.
    func testRestoringARowHoldingATransferredCopyEmptiesItsSlot() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: 1, date: t0)                       // a b c ...
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: 2, date: t0.addingTimeInterval(1)) // d ...; history [a ...]
        // The copy "a" is transferred while the screen is open: the box no longer holds it. The history keeps naming it.
        attach(keeper, account, ids: ["b", "c", "d"])
        XCTAssertEqual(keeper.store.history["gym"]?.first?.slots[0].pick, "a")
        ws.select(.current, ref: .gym, keeper: keeper)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertTrue(ws.restore(s, keeper: keeper, index: 0, date: t0.addingTimeInterval(2)))
        XCTAssertNil(keeper.store.current(.gym)?.slots[0].pick, "the transferred copy is dropped, so the slot refills by the rules")
        XCTAssertEqual(keeper.store.history["gym"]?.first?.slots[0].pick, "d")
        // Undo reconciles too: D came back from the history; transfer it, then undo the restore.
        attach(keeper, account, ids: ["b", "c"])
        XCTAssertTrue(ws.undo(ws.surface(.gym, store: keeper.store, defaults: defaults), keeper: keeper))
        XCTAssertNil(keeper.store.current(.gym)?.slots[0].pick, "an undone squad never names a copy that left")
    }

    // MARK: fold round 1

    /// H1: another account starts with no edit, and a surface drawn for one account cannot set into another's store.
    func testAnotherAccountShowsNoEditAndASurfaceFromTheFirstCannotSetIntoIt() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c"])
        ws.attach(account: account, boxIds: ["a", "b", "c"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.edit(s, keeper: keeper) { $0.choose("c", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertNotNil(s.edit)
        attach(keeper, other, ids: ["a", "b", "c"])
        ws.attach(account: other, boxIds: ["a", "b", "c"])
        XCTAssertNil(ws.surface(.gym, store: keeper.store, defaults: defaults).edit, "the new account's screen starts as on first open")
        XCTAssertFalse(ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: nil))
        XCTAssertNil(keeper.store.current(.gym), "the first account's squad was not written into the second account's store")
        XCTAssertNil(SquadKeeper.load(other).current(.gym))
    }

    /// H2 and J3: an edit follows the box: a pick whose copy left is emptied (by the store's refresh), that slot alone refills with a copy that is in the attached box, and the exact
    /// adopted id is kept; an id that is not in the box is refused (J1).
    func testAnEditPickWhoseCopyLeftTheBoxIsEmptiedAndTheRefillIsKept() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        ws.attach(account: account, boxIds: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 0, shown: self.shown($0)) }
        let before = ws.surface(.gym, store: keeper.store, defaults: defaults).squad.slots.map(\.pick)
        attach(keeper, account, ids: ["a", "b", "c", "e"])
        ws.attach(account: account, boxIds: ["a", "b", "c", "e"])
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertNil(s.squad.slots[0].pick, "no ghost id")
        XCTAssertEqual(Array(s.squad.slots.map(\.pick).dropFirst()), Array(before.dropFirst()), "no other slot changed")
        // A refill with an id that is not in the box is refused.
        let ghost = shown(s.squad, ["a", "b", "c", "z"])
        XCTAssertTrue(s.squad.needsAdopting(ghost))
        ws.adopt(s, keeper: keeper, filled: ghost)
        XCTAssertNil(ws.surface(.gym, store: keeper.store, defaults: defaults).squad.slots[0].pick, "an id that is not in the box adopts nothing")
        // A refill with the copy that is in the box is adopted, exactly.
        let filled = shown(s.squad, ["a", "b", "c", "e"])
        XCTAssertTrue(s.squad.needsAdopting(filled))
        ws.adopt(s, keeper: keeper, filled: filled)
        XCTAssertEqual(ws.surface(.gym, store: keeper.store, defaults: defaults).squad.slots[0].pick, "e", "and the refill is kept in the edit")
    }

    /// J1: every write is guarded by the account: an edit, a set, a reset or an adopt captured under one account and run after attaching another writes nothing.
    func testAnEditSetOrAdoptCapturedUnderAnotherAccountWritesNothing() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        ws.attach(account: account, boxIds: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.edit(s, keeper: keeper) { $0.choose("d", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: nil)
        ws.select(.current, ref: .gym, keeper: keeper)
        let currentSurface = ws.surface(.gym, store: keeper.store, defaults: defaults)    // on Current, drawn for account A
        ws.select(.available, ref: .gym, keeper: keeper)
        let availableSurface = ws.surface(.gym, store: keeper.store, defaults: defaults)
        attach(keeper, other, ids: ["a", "b", "c", "d"])
        ws.attach(account: other, boxIds: ["a", "b", "c", "d"])
        let storeB = keeper.store
        ws.edit(currentSurface, keeper: keeper) { $0.choose("c", at: 1, shown: self.shown($0)) }
        ws.edit(availableSurface, keeper: keeper) { $0.choose("c", at: 1, shown: self.shown($0)) }
        ws.reset(availableSurface, keeper: keeper)
        ws.unsetCurrent(currentSurface, keeper: keeper)
        ws.undo(currentSurface, keeper: keeper)
        XCTAssertFalse(ws.restore(currentSurface, keeper: keeper, index: 0))
        var empty = availableSurface.squad; empty.slots[0].pick = nil
        ws.adopt(availableSurface, keeper: keeper, filled: shown(empty, ["x"]))
        XCTAssertEqual(keeper.store, storeB, "the second account's store is untouched")
        XCTAssertNil(ws.surface(.gym, store: keeper.store, defaults: defaults).edit, "and so are its edits")
        XCTAssertNil(SquadKeeper.load(other).current(.gym))
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

    /// H6 and H17: an edit that is drawn the same as the suggestion is not edited, however it got there; "Set this squad" on an unedited Best tab leaves it unedited and the pill reads set.
    func testAnEditDrawnLikeTheSuggestionIsNotEdited() {
        let keeper = SquadKeeper(), ws = makeWS()
        attach(keeper, account, ids: ["a", "b", "c", "d"])
        ws.attach(account: account, boxIds: ["a", "b", "c", "d"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        let suggestion = { self.shown(SquadStore.Saved(slots: defaults)) }
        // Re-choosing the ticked Pokemon: the squad is drawn as the suggestion, so it is not an edit (H2): the stored edit is dropped.
        ws.edit(s, keeper: keeper) { $0.choose("a", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertNotNil(s.edit, "stored by the tap")
        XCTAssertFalse(s.isEdited(filled: shown(s.squad), suggested: suggestion))
        let stale = s.with(edited: false)
        XCTAssertTrue(stale.editIsStale)
        ws.dropUneditedEdit(stale, keeper: keeper)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertNil(s.edit, "an edit drawn like the suggestion is not an edit")
        XCTAssertFalse(keeper.store.differs(.gym, .available, style: .balanced))
        ws.edit(s, keeper: keeper) { $0.choose("a", at: 0, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        // A role flipped and flipped back.
        ws.edit(s, keeper: keeper) { $0.changeRole(at: 1, to: "Other", fits: { _ in true }, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertTrue(s.isEdited(filled: shown(s.squad), suggested: suggestion), "a role differs")
        ws.edit(s, keeper: keeper) { $0.changeRole(at: 1, to: HubSquads.gymSlotRole, fits: { _ in true }, shown: self.shown($0)) }
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        XCTAssertFalse(s.isEdited(filled: shown(s.squad), suggested: suggestion))
        ws.reset(s, keeper: keeper)
        ws.select(.best, ref: .gym, keeper: keeper)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: 100)
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        let edited = s.with(edited: s.isEdited(filled: shown(s.squad), suggested: suggestion))
        XCTAssertFalse(edited.differs)
        XCTAssertTrue(edited.isBestSuggestion)
        XCTAssertTrue(isCurrent(edited), "the pill reads Squad set")
        XCTAssertEqual(keeper.store.current(.gym)?.isSet, true)
        XCTAssertEqual(keeper.store.current(.gym)?.source, .best)
        XCTAssertEqual(keeper.store.current(.gym)?.edited, false)
    }

    /// Names are remembered while a copy is in the box, so a history row can name one that left (CONCEPTS rule 27.10).
    func testTheKeeperRemembersTheNamesOfCopiesASquadHoldsAndKeepsThemAfterTheCopyLeaves() {
        let keeper = SquadKeeper(), ws = makeWS()
        keeper.attach(account: account, today: "2026-10-26", rotation: [], boxIds: ["a", "b", "c"], names: ["a": "Alpha", "b": "Beta", "c": "Gamma"])
        let defaults = HubSquads.defaultGymSlots()
        var s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.setCurrent(s, keeper: keeper, filled: shown(s.squad), strength: nil, date: t0)
        XCTAssertEqual(keeper.store.pickNames["a"], "Alpha")
        s = ws.surface(.gym, store: keeper.store, defaults: defaults)
        ws.unsetCurrent(s, keeper: keeper, date: t0.addingTimeInterval(1))
        // A re-scan: copy a is gone from the box.
        keeper.attach(account: account, today: "2026-10-26", rotation: [], boxIds: ["b", "c"], names: ["b": "Beta", "c": "Gamma"])
        XCTAssertEqual(keeper.store.pickNames["a"], "Alpha", "the history entry still names it")
        XCTAssertEqual(SquadKeeper.load(account).pickNames["a"], "Alpha")
    }

    // MARK: the history rows

    func testTheHistoryDateReadsTodayYesterdayOrTheDay() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let locale = Locale(identifier: "en_AU")
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12, minute: 0))!
        func at(_ d: Int, _ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))! }
        let today = HistoryRowModel.when(at(7, 10, 16), now: now, calendar: cal, locale: locale)
        let yesterday = HistoryRowModel.when(at(6, 18, 40), now: now, calendar: cal, locale: locale)
        let older = HistoryRowModel.when(at(5, 9, 12), now: now, calendar: cal, locale: locale)
        XCTAssertTrue(today.hasPrefix("Today ") && today.contains("10:16"), today)
        XCTAssertTrue(yesterday.hasPrefix("Yesterday ") && yesterday.contains("6:40"), yesterday)
        XCTAssertTrue(older.hasPrefix("5 Nov ") && older.contains("9:12"), older)
    }

    func testAHistoryRowSpeaksTheDateEachPokemonAndTheFigureAndMarksWhatLeftTheBox() {
        let p = SquadPalette.grey
        let discs = [HistoryDisc(name: "Gardevoir", palette: p), HistoryDisc(name: "Xerneas", palette: p), HistoryDisc(name: "Zacian", palette: p, present: false),
                     HistoryDisc(name: "Shadow Granbull", palette: p), HistoryDisc(name: nil, palette: p)]
        let row = HistoryRowModel(index: 0, when: "Today 10:16", discs: discs, percent: "41%")
        XCTAssertEqual(row.spoken, "Today 10:16, Gardevoir, Xerneas, Zacian not in your box, Granbull (Shadow), empty slot, 41% of best")
        XCTAssertEqual(discs[0].letter, "G"); XCTAssertEqual(discs[3].letter, "G", "the letter of the box name"); XCTAssertNil(discs[4].letter)
        // H14: a departed Pokémon nothing remembers the name of is a hollow disc with "?", not a grey empty one.
        let unknown = HistoryDisc(name: nil, palette: p, present: false)
        XCTAssertEqual(unknown.letter, "?"); XCTAssertEqual(unknown.spoken, "a Pokémon not in your box")
        XCTAssertTrue(HistoryRowModel(index: 1, when: "x", discs: [], percent: "—").spoken.hasSuffix("no figure"))
        XCTAssertTrue(HistoryRowModel(index: 1, when: "x", discs: [], percent: "100%").spoken.hasSuffix(", 100%"))
        let rows = HistoryRowModel.rows([HistoryEntry(date: t0, slots: [SquadSlot(role: "X", pick: "a")], source: .best, edited: false, strength: nil)], now: t0) { _ in HistoryDisc(name: "A", palette: p) }
        XCTAssertEqual(rows.first?.percent, "—", "a figure that was not worked out reads —")
    }
}
