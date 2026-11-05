import XCTest
@testable import PogoBox
import PogoReader

/// Pass 2's shared squad rules (CONCEPTS rules 1 to 6, 15) and the persistence model (rule 27).
final class HubSquadsTests: XCTestCase {
    private typealias B = BoxAdvice.Build

    // MARK: rule 1

    func testFullStrengthIsStricterOnRaidsAndMax() {
        var raid = P23.build("a", "vaporeon", areas: ["Raids", "Gym"]); raid.steps = nil
        let ctx = P23.ctx(builds: [raid])
        XCTAssertFalse(HubSquads.isFullStrength(raid, screen: .gym, ctx: ctx), "a report without steps is not known to be finished (HubTeams.isBuilt alone would say built)")
        XCTAssertFalse(HubSquads.isFullStrength(raid, screen: .raids, ctx: ctx), "HubRaidsModel.isBuilt: without steps there is no proof it is finished")
        var done = raid; done.steps = []
        XCTAssertTrue(HubSquads.isFullStrength(done, screen: .raids, ctx: P23.ctx(builds: [done])))
        var todo = done; todo.steps = [.init(kind: "powerUp", toLevel: 40)]
        XCTAssertFalse(HubSquads.isFullStrength(todo, screen: .gym, ctx: ctx))
        XCTAssertFalse(HubSquads.isFullStrength(todo, screen: .raids, ctx: ctx))
        // The Dynamax requirement alone does not stop a Gym or Rocket build being built.
        var dyn = done; dyn.steps = [.init(kind: "needsDynamaxCopy")]
        XCTAssertTrue(HubSquads.isFullStrength(dyn, screen: .rocket, ctx: ctx))
    }

    func testMaxNeedsTheCopyMarkedDynamax() {
        let b = P23.build("a", "blissey", areas: ["Max"])
        let unmarked = P23.ctx(builds: [b], entries: [P23.entry("a", "blissey")])
        XCTAssertFalse(HubSquads.isFullStrength(b, screen: .max, ctx: unmarked), "no Dynamax mark: Upgrade available (read-back Q7)")
        let marked = P23.ctx(builds: [b], entries: [P23.entry("a", "blissey", dynamax: true)])
        XCTAssertTrue(HubSquads.isFullStrength(b, screen: .max, ctx: marked))
        let off = P23.ctx(builds: [b], entries: [P23.entry("a", "blissey", dynamax: false)])
        XCTAssertFalse(HubSquads.isFullStrength(b, screen: .max, ctx: off))
        XCTAssertFalse(HubSquads.isFullStrength(P23.build("a", "blissey", areas: ["Raids"]), screen: .max, ctx: marked), "a build without the Max area is not a Max build")
    }

    // MARK: rule 2

    func testCostSplitsIntoValueAndCurrency() {
        XCTAssertEqual(HubSquads.cost(of: P23.build("a", "vaporeon", areas: ["Gym"], dust: 19_000, candy: 50)), .init(value: "19k", currency: .dust), "dust wins over candy")
        XCTAssertEqual(HubSquads.cost(of: P23.build("a", "vaporeon", areas: ["Gym"], dust: 6_600)), .init(value: "6,600", currency: .dust))
        XCTAssertEqual(HubSquads.cost(of: P23.build("a", "vaporeon", areas: ["Gym"], candy: 100)), .init(value: "100", currency: .candy))
        XCTAssertEqual(HubSquads.cost(of: P23.build("a", "vaporeon", areas: ["Gym"])), .init(value: nil, currency: .free), "nothing beside the arrow when free")
        XCTAssertEqual(HubSquads.cost(dust: 0, candy: 0).currency, .free)
    }

    func testUpgradeLabelNamesTheWork() {
        let b = P23.build("a", "vaporeon", areas: ["Raids"], built: false, targetLevel: 30)
        XCTAssertEqual(HubSquads.upgradeLabel(b), "Upgrade available: power up to level 30")
    }

    // MARK: rule 3

    func testAvailableTakesEveryBuildWhateverUpgradeItNeeds() {
        // S1: nothing is filtered by the kind of upgrade (power up, evolve, form change, Mega Evolve); the box must hold the copy and a build of the area.
        let c = P23.ctx(builds: [P23.build("a", "eevee", areas: ["Raids"]), P23.build("b", "vaporeon", areas: ["Raids"], powerUp: false),
                                 P23.build("c", "eevee", areas: ["Raids"], formChange: true), P23.build("d", "lucario", areas: ["Raids"], viaMega: true),
                                 P23.build("x", "eevee", areas: ["Gym"])],
                        entries: [P23.entry("a", "eevee"), P23.entry("b", "eevee"), P23.entry("c", "eevee"), P23.entry("d", "riolu"), P23.entry("x", "eevee")])
        let place = HubSquads.placeable(screen: .raids, mode: .available, ctx: c)
        XCTAssertEqual(["a", "b", "c", "d", "x", "nobody"].map { place($0, "Heavy hitter") }, [true, true, true, true, false, false], "x has no Raids build")
        XCTAssertFalse(place("species:lucario", "Heavy hitter"))
        XCTAssertTrue(HubSquads.placeable(screen: .raids, mode: .best, ctx: c)("species:lucario", "Heavy hitter"))
    }

    // MARK: rule 4: one slot at a time

    func testPicksAreKeptThenSuggestionsFillTheRestWithoutRepeats() {
        let slots = [SquadSlot(role: "X", pick: "c"), SquadSlot(role: "X"), SquadSlot(role: "X", pick: "c"), SquadSlot(role: "X")]
        let out = HubSquads.fill(slots: slots) { _, _ in .init(preferred: ["a", "b", "c", "d"]) }
        XCTAssertEqual(out.map(\.entryId), ["c", "a", "b", "d"], "the same copy picked twice keeps its first slot; the other slot takes the suggestion")
        XCTAssertEqual(out.map(\.chosen), [true, false, false, false])
        let short = HubSquads.fill(slots: slots) { _, _ in .init(preferred: ["a"]) }
        XCTAssertEqual(short.map(\.entryId), ["c", "a", nil, nil], "an empty pool leaves the slot empty")
        XCTAssertEqual(HubSquads.fill(slots: [], pool: { _, _ in .init(preferred: ["a"]) }), [])
    }

    func testPickerHidesOtherSlotsCopiesAndTicksItsOwn() {
        let filled = [FilledSlot(role: "X", entryId: "a", chosen: true, fallback: false), FilledSlot(role: "X", entryId: "b", chosen: false, fallback: false),
                      FilledSlot(role: "X", entryId: "c", chosen: false, fallback: false)]
        let ex = HubSquads.excluded(by: filled, editing: 1, onlyChosen: false)
        XCTAssertEqual(ex, ["a", "c"])
        XCTAssertEqual(HubSquads.picker(candidates: ["a", "b", "c", "d"], excluded: ex, own: "b"), [.init(entryId: "b", ticked: true), .init(entryId: "d", ticked: false)])
        // Rocket: only copies the player chose leave the list.
        let rocket = HubSquads.excluded(by: filled, editing: 1, onlyChosen: true)
        XCTAssertEqual(rocket, ["a"])
        XCTAssertEqual(HubSquads.picker(candidates: ["a", "b", "c"], excluded: rocket, own: "b").map(\.entryId), ["b", "c"])
        XCTAssertEqual(HubSquads.picker(candidates: ["a"], excluded: ["a"], own: nil), [], "everything else in use: an empty list")
        XCTAssertEqual(HubSquads.picker(candidates: ["a", "b"], excluded: [], own: nil).map(\.ticked), [false, false])
    }

    // MARK: rule 5

    func testChangingARoleKeepsAFittingPickAndDropsOneThatDoesNot() {
        struct C: SquadCandidate { var entryId: String; var roleNames: [String] }
        let cands = [C(entryId: "a", roleNames: ["Tank"]), C(entryId: "b", roleNames: ["Healer", "Tank"]), C(entryId: "c", roleNames: ["Attacker"])]
        var slots = [SquadSlot(role: "Tank", pick: "b"), SquadSlot(role: "Tank", pick: "a")]
        HubSquads.changeRole(&slots, at: 0, to: "Healer") { HubSquads.fits($0, role: "Healer", in: cands) }
        XCTAssertEqual(slots[0], SquadSlot(role: "Healer", pick: "b"), "Blissey-like: fits both, kept")
        HubSquads.changeRole(&slots, at: 1, to: "Healer") { HubSquads.fits($0, role: "Healer", in: cands) }
        XCTAssertEqual(slots[1], SquadSlot(role: "Healer", pick: nil), "does not fit: the pick goes and the slot refills")
        let refilled = HubSquads.fill(slots: slots) { _, role in .init(preferred: HubSquads.pool(role: role, in: cands)) }
        XCTAssertEqual(refilled.map(\.entryId), ["b", nil], "no unused Healer: empty")
        HubSquads.changeRole(&slots, at: 1, to: squadRoleAll) { HubSquads.fits($0, role: squadRoleAll, in: cands) }
        XCTAssertEqual(HubSquads.fill(slots: slots) { _, role in .init(preferred: HubSquads.pool(role: role, in: cands)) }.map(\.entryId), ["b", "a"], "All allows anyone")
        var none = [SquadSlot]()
        HubSquads.changeRole(&none, at: 3, to: "Tank") { _ in true }
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: rule 15

    func testBuiltRowsDropTheCostAndFree() {
        let built = P23.build("a", "vaporeon", areas: ["Gym", "Max"])
        let row = HubSquads.buildRow(built)
        XCTAssertTrue(row.showsFullStrength)
        XCTAssertEqual(row.subLine, "Gym, Max", "no \" · Free\"")
        XCTAssertEqual(row.cost.currency, .free)
        let todo = HubSquads.buildRow(P23.build("a", "vaporeon", areas: ["Gym", "Max"], built: false, dust: 10_000))
        XCTAssertFalse(todo.showsFullStrength)
        XCTAssertEqual(todo.subLine, "Gym, Max · 10k dust")
        XCTAssertEqual(todo.cost, .init(value: "10k", currency: .dust))
        XCTAssertEqual(HubSquads.buildRow(P23.build("a", "vaporeon", areas: ["Gym"], built: false)).subLine, "Gym · Free", "an unbuilt free build keeps Free")
    }

    func testABuildReadWithoutStepsIsNotShownAsFullStrength() {
        var b = P23.build("a", "vaporeon", areas: ["Gym"], dust: 10_000)
        b.steps = nil
        let row = HubSquads.buildRow(b)
        XCTAssertFalse(row.showsFullStrength, "unknown steps are not known to be finished")
        XCTAssertEqual(row.cost, .init(value: "10k", currency: .dust))
        XCTAssertEqual(row.subLine, "Gym · 10k dust")
        XCTAssertTrue(HubTeams.isBuilt(b), "HubTeams.isBuilt itself is unchanged")
        let ctx = P23.ctx()
        for screen in SquadScreen.allCases { XCTAssertFalse(HubSquads.isFullStrength(b, screen: screen, ctx: ctx), "unknown steps are never Full strength on \(screen)") }
        var known = b; known.steps = []
        XCTAssertTrue(HubSquads.isFullStrength(known, screen: .gym, ctx: ctx), "known steps with nothing left are")
    }

    // MARK: rule 6



    // MARK: rule 27: the store

    private func row(_ from: String, _ to: String, title: String = "5-star raid", kind: HubData.Kind = .fiveStar) -> HubData.RotationRow {
        P23.row(from, to, kind, title: title, bosses: [])
    }

    func testEventSquadsAreDroppedOnceTheEventHasEnded() {
        var s = SquadStore()
        let ended = row("2026-10-01", "2026-10-10"), lastDay = row("2026-10-20", "2026-10-25"), later = row("2026-11-01", "2026-11-05")
        for r in [ended, lastDay, later] {
            var saved = SquadStore.Saved(slots: HubSquads.defaultRaidSlots(), isSet: true)
            saved.choose("a", at: 1)
            s.saveEventSquad(saved, row: r, screen: .raids)
            s.saveEventSquad(saved, row: r, screen: .max)
        }
        let pruned = s.pruned(today: "2026-10-25", rotation: [])
        XCTAssertNil(pruned.raids[SquadStore.eventKey(ended)])
        XCTAssertNotNil(pruned.raids[SquadStore.eventKey(lastDay)], "the last day still counts")
        XCTAssertNotNil(pruned.raids[SquadStore.eventKey(later)])
        XCTAssertEqual(pruned.max.count, 2)
        XCTAssertEqual(s.pruned(today: "2027-01-01", rotation: []).raids.count, 0)
        XCTAssertEqual(SquadStore().pruned(today: "2026-10-25", rotation: []), SquadStore(), "an empty store stays empty")
        XCTAssertEqual(pruned.eventSquad(ended, screen: .raids), SquadStore.Saved(slots: HubSquads.defaultRaidSlots()), "a dropped squad reads as the default")
    }

    func testAPickWhoseCopyLeftTheBoxEmptiesTheSlotAndTheSuggestionRefills() {
        var s = SquadStore()
        var gym = s.gym; gym.choose("gone", at: 0); gym.choose("stays", at: 1); s.gym = gym
        var pvp = s.pvpSquad(league: "gl"); pvp.choose("gone", at: 2); s.pvp["gl"] = pvp
        var rocket = s.rocketSquad(leader: "Giovanni"); rocket.choose("stays", at: 0); s.rocket["Giovanni"] = rocket
        let r = row("2026-11-01", "2026-11-05")
        var raid = SquadStore.Saved(slots: HubSquads.defaultRaidSlots(), isSet: true); raid.choose("gone", at: 2); s.saveEventSquad(raid, row: r, screen: .raids)
        let kept = s.reconciled(boxIds: ["stays", "other"])
        XCTAssertEqual(kept.gym.slots.map(\.pick), [nil, "stays", nil, nil, nil, nil])
        XCTAssertEqual(kept.pvpSquad(league: "gl").slots.map(\.pick), [nil, nil, nil])
        XCTAssertEqual(kept.rocketSquad(leader: "Giovanni").slots.map(\.pick), ["stays", nil, nil])
        XCTAssertEqual(kept.eventSquad(r, screen: .raids).slots[2].pick, nil)
        XCTAssertTrue(kept.eventSquad(r, screen: .raids).isSet, "the set mark is the player's own and stays")
        // An empty slot refills with the suggestion: the filler sees no pick.
        let filled = HubSquads.gymSquad(slots: kept.gym.slots, rows: [], placeable: P23.anyone)
        XCTAssertEqual(filled.map(\.chosen), [false, true, false, false, false, false])
        XCTAssertEqual(SquadStore().reconciled(boxIds: []), SquadStore(), "an empty box and an empty store")
        XCTAssertEqual(s.reconciled(boxIds: []).gym.slots.compactMap(\.pick), [], "an empty box empties every pick")
    }

    func testChoosingACopyTakesItOutOfTheSquadsOtherSlots() {
        var saved = SquadStore.Saved(slots: HubSquads.defaultPvpSlots())
        saved.choose("a", at: 0); saved.choose("b", at: 1)
        saved.choose("a", at: 2)
        XCTAssertEqual(saved.slots.map(\.pick), [nil, "b", "a"])
        saved.choose(nil, at: 2)
        XCTAssertEqual(saved.slots.map(\.pick), [nil, "b", nil], "clearing a slot")
        saved.choose("z", at: 9)
        XCTAssertEqual(saved.slots.count, 3, "an index out of range changes nothing")
        saved.changeRole(at: 1, to: "Closer") { _ in false }
        XCTAssertEqual(saved.slots[1], SquadSlot(role: "Closer", pick: nil))
    }

    func testModesAreRememberedPerScreenAndDefaultToAvailable() {
        var s = SquadStore()
        XCTAssertEqual(SquadScreen.allCases.map { s.mode(for: $0) }, Array(repeating: .available, count: 5))
        s.setMode(.best, for: .gym)
        XCTAssertEqual(s.mode(for: .gym), .best)
        XCTAssertEqual(s.mode(for: .raids), .available)
    }

    func testTheStoreRoundTripsAndReadsAnOlderFile() throws {
        var s = SquadStore()
        s.setMode(.best, for: .pvp)
        s.gym.choose("a", at: 0)
        s.pvp["ul"] = SquadStore.Saved(slots: HubSquads.defaultPvpSlots(), isSet: false)
        s.saveEventSquad(SquadStore.Saved(slots: HubSquads.defaultMaxSlots(), isSet: true), row: row("2026-11-01", "2026-11-05"), screen: .max)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(SquadStore.self, from: data), s)
        let old = try JSONDecoder().decode(SquadStore.self, from: Data(#"{"version":1,"modes":{"gym":"best"}}"#.utf8))
        XCTAssertEqual(old.mode(for: .gym), .best)
        XCTAssertEqual(old.gym.slots.count, 6, "a missing section reads as its default")
        XCTAssertTrue(old.raids.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(SquadStore.self, from: Data("{}".utf8)), SquadStore())
    }

    func testPicksSurviveARescanBecauseTheEntryIdIsStable() throws {
        let gm = P23.gm
        let first = P23.entry("keep-me", "pidgey", ivs: IVs(atk: 10, def: 11, hp: 12), level: 10, cp: 300)
        var scanned = first.row; scanned.cp = 301
        let plan = BoxMerge.plan(scanned: [scanned], into: [first], kind: .full, scanDate: Date(timeIntervalSince1970: 1_790_100_000), gameMaster: gm)
        // Where the merge asks "is it this one?", the answer is yes (the first candidate), as the automatic update does.
        let yes = Dictionary(uniqueKeysWithValues: plan.unsure.map { ($0.scanned, BoxMerge.Resolution.existing($0.candidates[0])) })
        let after = try BoxMerge.apply(plan, resolutions: yes, to: [first])
        XCTAssertEqual(after.map(\.id), ["keep-me"], "the merge keeps the entry's id")
        var s = SquadStore()
        s.gym.choose("keep-me", at: 0)
        XCTAssertEqual(s.refreshed(today: "2026-10-25", rotation: [], boxIds: Set(after.map(\.id))).gym.slots[0].pick, "keep-me")
    }
}
