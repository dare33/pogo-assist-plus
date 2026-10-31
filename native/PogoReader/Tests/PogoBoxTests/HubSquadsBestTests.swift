import XCTest
@testable import PogoBox
import PogoReader

/// Phone feedback items 8, 9 and 10 (30 Oct 2026): Available offers only what the box has; Best lists the best Pokémon in the game for the slot from the tier
/// tables, owned or not, each with an availability line when the box lacks it; a slot and a squad are rated ready, nearly ready or not ready.
final class HubSquadsBestTests: XCTestCase {
    /// A fire boss is weak to Water, Ground and Rock (the bring types, in that order).
    private let fireBoss = P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("charizard", types: ["fire"])])

    private func raidTable() -> TierTable {
        P23.table([P23.tierEntry("raids", "Rock", "S", "rhyperior", obtain: "Hard. Past raid"),
                   P23.tierEntry("raids", "Ground", "S", "rhyperior"),
                   P23.tierEntry("raids", "Water", "S", "vaporeon", obtain: "Easy. Eevee"),
                   P23.tierEntry("raids", "Water", "S", "swampert_mega", mega: true, obtain: "Hard. Mega raids"),
                   P23.tierEntry("raids", "Water", "A", "swampert"), P23.tierEntry("raids", "Ground", "A", "swampert"),
                   P23.tierEntry("raids", "Ground", "A", "excadrill", obtain: "Medium. T5 raids"),
                   P23.tierEntry("raids", "Ground", "A", "garchomp"),
                   P23.tierEntry("raids", "Water", "B", "kingler"),
                   P23.tierEntry("raids", "Fire", "S", "charizard")])      // Fire is not a bring type
    }
    private func raidBuilds() -> [BoxAdvice.Build] {
        [P23.build("e1", "vaporeon", areas: ["Raids"]),
         P23.build("e2", "swampert", areas: ["Raids"], powerUp: false, viaMega: true),   // mega evolves: fills Mega Swampert, and Swampert too
         P23.build("e3", "kingler", areas: ["Raids"], built: false),
         P23.build("e4", "charizard", areas: ["Raids"])]
    }
    private let rotation = [P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("rhyperior", types: ["ground", "rock"])]),
                            P23.row("2026-11-02", "2026-11-02", .maxMonday, title: "Max Monday", bosses: [P23.boss("garchomp", types: ["dragon", "ground"])])]

    // MARK: Available

    func testAvailableNeverOffersAPokemonTheBoxLacks() {
        let ctx = P23.ctx(builds: raidBuilds(), entries: [], table: raidTable(), rotation: rotation)
        let owned = Set(raidBuilds().map(\.entryId))
        for c in HubSquads.raidCandidates(row: fireBoss, mode: .available, ctx: ctx) { XCTAssertTrue(owned.contains(c.entryId)) }
        let squad = HubSquads.raidSquad(candidates: HubSquads.raidCandidates(row: fireBoss, mode: .available, ctx: ctx), placeable: HubSquads.placeable(screen: .raids, mode: .available, ctx: ctx))
        XCTAssertTrue(squad.allSatisfy { $0.species == nil && ($0.entryId.map(owned.contains) ?? true) }, "no species-only slot under Available")
        // A species pick is not placed under Available: the slot shows the suggestion, and the pick stays in the store.
        let kept = HubSquads.raidSquad(slots: [SquadSlot(role: "Heavy hitter", species: "excadrill")], candidates: HubSquads.raidCandidates(row: fireBoss, mode: .available, ctx: ctx),
                                       placeable: HubSquads.placeable(screen: .raids, mode: .available, ctx: ctx))
        XCTAssertNil(kept[0].species)
        XCTAssertTrue(HubSquads.gymRows(mode: .available, ctx: P23.ctx(builds: [P23.build("g1", "snorlax", areas: ["Gym"])], table: P23.table([P23.tierEntry("gym", "Tiers", "S", "chansey")]))).allSatisfy { $0.build.entryId == "g1" })
    }

    // MARK: Best, raids

    func testBestRaidRowsListTheTableOwnedOrNotInRankOrder() {
        let ctx = P23.ctx(builds: raidBuilds(), table: raidTable(), rotation: rotation)
        let rows = HubSquads.bestRaidRows(row: fireBoss, ctx: ctx)
        // S first: Water entries (the strongest bring type) in table order, then Ground. A: Swampert is listed too, though its only copy is the one Mega Swampert shows
        // (every table row is listed, rule 6); Excadrill, Garchomp (Ground). B: Kingler. Rhyperior is listed under Rock and Ground: once, at its best place. Charizard
        // (Fire) is not a bring type.
        XCTAssertEqual(rows.map(\.key), ["vaporeon", "swampert_mega", "rhyperior", "swampert", "excadrill", "garchomp", "kingler"])
        XCTAssertEqual(rows.map(\.tier), ["S", "S", "S", "A", "A", "A", "B"])
        XCTAssertEqual(rows.map(\.ownedEntryId), ["e1", "e2", nil, "e2", nil, nil, "e3"])
        XCTAssertEqual(rows.map(\.sharedWith), [nil, nil, nil, "Swampert (Mega)", nil, nil, nil])
        XCTAssertEqual(rows.map(\.inBox), [true, true, false, true, false, false, true])
        XCTAssertEqual(rows.map(\.roles), [["Bulky hitter"], ["Mega"], ["Bulky hitter"], ["Bulky hitter"], ["Heavy hitter"], ["Heavy hitter"], ["Heavy hitter"]])
        // The ones the box lacks say when: the rotation first (a boss now; a Max Monday coming), else the table's obtain text, else that nothing is known.
        XCTAssertEqual(rows.map(\.availability), ["", "", "Raid boss now", "", "Medium. T5 raids", "Max Monday 2 Nov", ""])
        XCTAssertEqual(rows.map(\.rotationLine), [nil, nil, "Raid boss now", nil, nil, "Max Monday 2 Nov", nil], "a card shows the short rotation date only")
        XCTAssertEqual(rows[4].name, "Excadrill")
        XCTAssertEqual(rows.map(\.entryId), ["e1", "e2", "species:rhyperior", "species:swampert", "species:excadrill", "species:garchomp", "e3"], "a shared copy is picked as its species")
    }

    func testBestRaidRowsGiveAMegaSlotARealMegaEvenWhenTheBoxHasNone() {
        let ctx = P23.ctx(builds: [], table: raidTable(), rotation: [])
        let rows = HubSquads.bestRaidRows(row: fireBoss, ctx: ctx)
        XCTAssertTrue(rows.allSatisfy { !$0.inBox })
        let squad = HubSquads.bestSquad(slots: HubSquads.defaultRaidSlots(), rows: rows)
        XCTAssertEqual(squad.map(\.role), ["Mega", "Heavy hitter", "Heavy hitter", "Heavy hitter", "Bulky hitter", "Bulky hitter"])
        XCTAssertEqual(squad.map(\.species), ["swampert_mega", "excadrill", "garchomp", "kingler", "vaporeon", "rhyperior"], "owned or not; the Bulky slots take the best two Bulky")
        XCTAssertTrue(squad.allSatisfy { $0.entryId == nil && !$0.chosen })
    }

    func testBestSquadMayHoldANotOwnedPickAndShowsTheCopyOnceTheBoxHasIt() {
        let ctx = P23.ctx(builds: raidBuilds(), table: raidTable(), rotation: [])
        let rows = HubSquads.bestRaidRows(row: fireBoss, ctx: ctx)
        var slots = HubSquads.defaultRaidSlots()
        slots[1] = SquadSlot(role: "Heavy hitter", species: "garchomp")
        var squad = HubSquads.bestSquad(slots: slots, rows: rows)
        XCTAssertEqual(squad[1].species, "garchomp")
        XCTAssertNil(squad[1].entryId)
        XCTAssertTrue(squad[1].chosen)
        XCTAssertEqual(squad[1].pickId, "species:garchomp")
        // The box now has a Garchomp: the same stored pick reads as that copy.
        let later = P23.ctx(builds: raidBuilds() + [P23.build("e9", "garchomp", areas: ["Raids"])], table: raidTable())
        squad = HubSquads.bestSquad(slots: slots, rows: HubSquads.bestRaidRows(row: fireBoss, ctx: later))
        XCTAssertEqual(squad[1].entryId, "e9")
        XCTAssertEqual(squad[1].species, "garchomp", "the slot remembers the species the player chose")
        XCTAssertEqual(slots[1].species, "garchomp", "the stored pick is the player's choice of the species and is not rewritten")
    }

    // MARK: availability

    func testAvailabilityLines() {
        let rows = [P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("palkia", types: ["water", "dragon"])]),
                    P23.row("2026-10-26", "2026-10-26", .maxMonday, title: "Max Monday", bosses: [P23.boss("machop", types: ["fighting"])]),
                    P23.row("2026-11-09", "2026-11-24", bosses: [P23.boss("cresselia", types: ["psychic"]), P23.boss("darkrai", types: ["dark"])]),
                    P23.row("2026-11-16", "2026-11-23", .maxEvent, title: "Dynamax Trails", bosses: [P23.boss("snorlax", types: ["normal"])]),
                    P23.row("2026-10-07", "2026-11-03", .shadow, bosses: [P23.boss("landorus_incarnate_shadow", types: ["ground", "flying"])]),
                    P23.row("2026-10-01", "2026-10-02", bosses: [P23.boss("mewtwo", types: ["psychic"])]),
                    P23.row("2026-11-28", "2026-11-28", .battleDay, title: "Super Mega Raid Day", bosses: [P23.boss("chandelure", types: ["ghost", "fire"])]),
                    P23.row("2026-10-28", "2026-10-28", .raidHour, title: "Raid Hour", bosses: [P23.boss("blissey", types: ["normal"])])]
        let ctx = P23.ctx(today: "2026-10-26", rotation: rows)
        func line(_ id: String, obtain: String? = nil, shadow: Bool = false, in c: HubContext? = nil) -> String {
            HubSquads.availability(of: P23.tierEntry("raids", "Water", "S", id, shadow: shadow, obtain: obtain), ctx: c ?? ctx)
        }
        XCTAssertEqual(line("palkia", obtain: "Hard"), "Raid boss now", "the rotation wins over the obtain text")
        XCTAssertEqual(line("machop"), "Max Monday today", "a one-day event on today reads today, not now")
        XCTAssertEqual(line("darkrai"), "Raids from 9 Nov")
        XCTAssertEqual(line("snorlax"), "Max battles from 16 Nov")
        XCTAssertEqual(line("chandelure"), "Super Mega Raid Day 28 Nov")
        XCTAssertEqual(line("landorus_incarnate_shadow"), "Raid boss now")
        XCTAssertEqual(line("mewtwo", obtain: "Medium. T5 raids"), "Medium. T5 raids", "a boss whose run has ended falls back to the obtain text")
        XCTAssertEqual(line("mewtwo"), "")
        XCTAssertEqual(line("mewtwo", obtain: "  "), "")
        XCTAssertEqual(line("blissey"), "", "a Raid Hour is no boss row: it is never read")
        // The last day of a run still counts; the next day does not.
        XCTAssertEqual(line("palkia", in: P23.ctx(today: "2026-10-30", rotation: rows)), "Raid boss now")
        XCTAssertEqual(line("palkia", obtain: "Hard", in: P23.ctx(today: "2026-10-31", rotation: rows)), "Hard")
        XCTAssertEqual(line("machop", in: P23.ctx(today: "2026-10-27", rotation: rows)), "")
        XCTAssertEqual(line("machop", in: P23.ctx(today: "2026-10-20", rotation: rows)), "Max Monday 26 Oct")
    }

    func testAShadowEntryIsOnlyTheShadowBossAndTheReverse() {
        let rows = [P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("giratina_origin", types: ["ghost", "dragon"])]),
                    P23.row("2026-10-20", "2026-10-30", .shadow, bosses: [P23.boss("landorus_incarnate_shadow", types: ["ground", "flying"])])]
        let ctx = P23.ctx(today: "2026-10-26", rotation: rows)
        func line(_ id: String, shadow: Bool) -> String { HubSquads.availability(of: P23.tierEntry("raids", "Ghost", "S", id, shadow: shadow), ctx: ctx) }
        XCTAssertEqual(line("giratina_origin", shadow: false), "Raid boss now")
        XCTAssertEqual(line("giratina_origin", shadow: true), "", "Shadow Giratina is not the plain Giratina raid")
        XCTAssertEqual(line("giratina_origin_shadow", shadow: true), "")
        XCTAssertEqual(line("landorus_incarnate", shadow: false), "", "the plain Landorus is not the Shadow raid")
        XCTAssertEqual(line("landorus_incarnate", shadow: true), "Raid boss now", "a Shadow listed under the plain id")
        XCTAssertEqual(line("landorus_incarnate_shadow", shadow: true), "Raid boss now")
    }

    // MARK: ownership

    func testACopyNoBuildServesReadsInYourBoxNotNotInYourBox() {
        let table = P23.table([P23.tierEntry("gym", "Tiers", "S", "chansey"), P23.tierEntry("gym", "Tiers", "A", "lapras"), P23.tierEntry("gym", "Tiers", "B", "snorlax")])
        let ctx = P23.ctx(builds: [P23.build("g9", "snorlax", areas: ["Gym"])], entries: [P23.entry("c1", "lapras", level: 20, cp: 900), P23.entry("c2", "lapras", cp: 1500), P23.entry("g9", "snorlax")], table: table, rotation: [])
        let rows = HubSquads.bestGymRows(ctx: ctx)
        XCTAssertEqual(rows.map(\.key), ["chansey", "lapras", "snorlax"])
        XCTAssertEqual(rows.map(\.inBox), [false, true, true])
        XCTAssertEqual(rows.map(\.hasBuild), [false, false, true])
        XCTAssertEqual(rows[1].ownedEntryId, "c2", "the best copy: the higher CP")
        XCTAssertEqual(rows[1].availability, "", "a Pokémon the box has says nothing about when it might be had")
        XCTAssertEqual(rows[1].entryId, "c2")
    }

    func testAShadowCopyServesBothRowsAndAPlainOneOnlyThePlainRow() {
        let machamp = P23.boss("kangaskhan", types: ["normal"])
        let table = P23.table([P23.tierEntry("rocket", "Attacker tiers", "S", "machamp_shadow", shadow: true, name: "Shadow Machamp"), P23.tierEntry("rocket", "Attacker tiers", "A", "machamp")])
        let shadowCopy = P23.entry("s1", "machamp", shadow: 1), plainCopy = P23.entry("p1", "machamp")
        let withShadow = P23.ctx(builds: [P23.build("s1", "machamp", areas: ["Rocket"])], entries: [shadowCopy], table: table, rotation: [])
        XCTAssertEqual(HubSquads.bestRocketRows(options: [machamp], ctx: withShadow).map(\.ownedEntryId), ["s1", "s1"], "a Shadow copy serves the Shadow row and the plain row")
        XCTAssertEqual(HubSquads.bestRocketRows(options: [machamp], ctx: withShadow).map(\.sharedWith), [nil, "Shadow Machamp"], "the plain row shows the copy the Shadow row already shows")
        let plain = P23.ctx(builds: [P23.build("p1", "machamp", areas: ["Rocket"])], entries: [plainCopy], table: table, rotation: [])
        let rows = HubSquads.bestRocketRows(options: [machamp], ctx: plain)
        XCTAssertEqual(rows.map(\.key), ["machamp_shadow", "machamp"])
        XCTAssertEqual(rows.map(\.ownedEntryId), [nil, "p1"], "a plain Machamp is not a Shadow Machamp")
        XCTAssertEqual(HubSquads.rocketTableTier(P23.build("s1", "machamp", areas: ["Rocket"]), ctx: withShadow), "S", "a Shadow copy reads the Shadow entry")
        XCTAssertEqual(HubSquads.rocketTableTier(P23.build("p1", "machamp", areas: ["Rocket"]), ctx: plain), "A")
        XCTAssertEqual(HubSquads.rocketTableTier(P23.build("p1", "snorlax", areas: ["Rocket"]), ctx: plain), "", "not in the table")
    }

    func testASharedCopyIsListedAndAPickOfItResolvesToTheCopy() {
        let ctx = P23.ctx(builds: raidBuilds(), table: raidTable(), rotation: [])
        let rows = HubSquads.bestRaidRows(row: fireBoss, ctx: ctx)
        let swampert = rows.first { $0.key == "swampert" }!
        XCTAssertEqual(swampert.entryId, "species:swampert")
        XCTAssertEqual(swampert.ownedEntryId, "e2")
        XCTAssertEqual(HubSquads.equivalents(of: "species:swampert", rows: rows).sorted(), ["e2", "species:swampert", "species:swampert_mega"], "every row that shows the copy")
        let slots = [SquadSlot(role: "Bulky hitter", species: "swampert")]
        let squad = HubSquads.bestSquad(slots: slots, rows: rows)
        XCTAssertEqual(squad[0].entryId, "e2")
        XCTAssertEqual(squad[0].species, "swampert", "the slot remembers the row the player chose")
        XCTAssertTrue(squad[0].ids.contains("species:swampert") && squad[0].ids.contains("e2"))
    }

    // MARK: one copy per squad (confirmation round B1, B2)

    /// Primal Kyogre and Kyogre are two table rows of one copy.
    private func kyogreCtx(rotation: [HubData.RotationRow] = []) -> HubContext {
        let table = P23.table([P23.tierEntry("raids", "Water", "S", "kyogre_primal", mega: true), P23.tierEntry("raids", "Water", "S", "kyogre")])
        return P23.ctx(builds: [P23.build("k1", "kyogre", areas: ["Raids"], powerUp: false, viaMega: true)], entries: [P23.entry("k1", "kyogre")], table: table, rotation: rotation)
    }

    private func slotsUsing(_ squad: [FilledSlot], rows: [HubSquads.BestRow]) -> [String] {
        let copyOf = HubSquads.copyResolver(rows: rows)
        return squad.compactMap { $0.pickId.flatMap(copyOf) }
    }

    func testASuggestedRaidSquadNeverUsesOneCopyTwice() {
        let ctx = kyogreCtx()
        let rows = HubSquads.bestRaidRows(row: fireBoss, ctx: ctx)
        XCTAssertEqual(rows.map(\.key), ["kyogre_primal", "kyogre"])
        XCTAssertEqual(rows.map(\.entryId), ["k1", "species:kyogre"], "the second row shows the same copy under a species id")
        let squad = HubSquads.bestSquad(slots: HubSquads.defaultRaidSlots(), rows: rows)
        XCTAssertEqual(slotsUsing(squad, rows: rows), ["k1"], "one copy, one slot")
        XCTAssertEqual(squad.map(\.pickId), ["k1", nil, nil, nil, nil, nil])
        // A pick of the shared row first: the copy is then the picked row's, and the other row's suggestion is skipped.
        var slots = HubSquads.defaultRaidSlots(); slots[4] = SquadSlot(role: "Bulky hitter", species: "kyogre")
        let picked = HubSquads.bestSquad(slots: slots, rows: rows)
        XCTAssertEqual(slotsUsing(picked, rows: rows), ["k1"])
        XCTAssertEqual(picked[4].entryId, "k1")
        XCTAssertNil(picked[0].pickId, "the Mega slot cannot take the copy the Bulky slot holds")
    }

    func testThePickerDoesNotOfferARowWhoseCopyIsInAnotherSlot() {
        let ctx = kyogreCtx()
        let rows = HubSquads.bestRaidRows(row: fireBoss, ctx: ctx)
        let squad = HubSquads.bestSquad(slots: HubSquads.defaultRaidSlots(), rows: rows)
        let copyOf = HubSquads.copyResolver(rows: rows)
        let excluded = HubSquads.excluded(by: squad, editing: 4, onlyChosen: false, copyOf: copyOf)
        let listed = HubSquads.picker(candidates: rows.map(\.entryId), excluded: excluded, ownIds: [], copyOf: copyOf)
        XCTAssertEqual(listed.map(\.entryId), [], "neither row of the copy the Mega slot holds")
        // The slot holding it still lists its own row, ticked, and only that row.
        let own = HubSquads.tickIds(squad[0], rows: rows)
        XCTAssertEqual(own, ["k1"])
        XCTAssertEqual(HubSquads.picker(candidates: rows.map(\.entryId), excluded: HubSquads.excluded(by: squad, editing: 0, onlyChosen: false, copyOf: copyOf), ownIds: own, copyOf: copyOf).map(\.entryId), ["k1", "species:kyogre"])
        // A species pick that reads as the copy ticks the row the player picked, not the higher row.
        let viaSpecies = HubSquads.bestSquad(slots: [SquadSlot(role: "Bulky hitter", species: "kyogre")], rows: rows)
        XCTAssertEqual(HubSquads.tickIds(viaSpecies[0], rows: rows), ["species:kyogre"])
    }

    func testARocketLeadersSquadNeverUsesOneShadowCopyTwice() {
        let normal = P23.boss("kangaskhan", types: ["normal"])
        let leader = HubData.Leader(name: "Test", since: "2026-10", slots: [[normal], [normal], [normal]], source: "")
        let table = P23.table([P23.tierEntry("rocket", "Attacker tiers", "S", "machamp_shadow", shadow: true, name: "Shadow Machamp"), P23.tierEntry("rocket", "Attacker tiers", "A", "machamp")])
        let ctx = P23.ctx(builds: [P23.build("s1", "machamp", areas: ["Rocket"])], entries: [P23.entry("s1", "machamp", shadow: 1)], table: table, rotation: [])
        let squad = HubSquads.bestRocketSquad(leader: leader, ctx: ctx)
        XCTAssertEqual(squad.map(\.pickId), ["s1", nil, nil], "the Shadow row and the plain row show one copy: it fills one slot")
        // The plain row picked in slot 2 first (a species pick), then slot 1 cannot take the Shadow row's copy as well.
        let slots = [SquadSlot(role: "Counter"), SquadSlot(role: "Counter", species: "machamp"), SquadSlot(role: "Counter")]
        let picked = HubSquads.bestRocketSquad(leader: leader, slots: slots, ctx: ctx)
        XCTAssertEqual(picked.map(\.pickId), [nil, "s1", nil])
    }

    func testChoosingAClearsTheSameCopyOrSpeciesFromOtherSlots() {
        let rows = HubSquads.bestRaidRows(row: fireBoss, ctx: kyogreCtx())
        // A copy shown on two rows: every id of both rows stands for it.
        XCTAssertEqual(Set(HubSquads.equivalents(of: "k1", rows: rows)), ["k1", "species:kyogre", "species:kyogre_primal"])
        XCTAssertEqual(Set(HubSquads.equivalents(of: "species:kyogre", rows: rows)), ["k1", "species:kyogre", "species:kyogre_primal"])
        var s = SquadStore.Saved(slots: [SquadSlot(role: "Heavy hitter", species: "kyogre_primal"), SquadSlot(role: "Heavy hitter", species: "kyogre"), SquadSlot(role: "Heavy hitter")])
        s.choose("k1", at: 2, alsoClearing: HubSquads.equivalents(of: "k1", rows: rows))
        XCTAssertEqual(s.slots[0], SquadSlot(role: "Heavy hitter"), "a species pick of the other row that shows the copy")
        XCTAssertEqual(s.slots[1], SquadSlot(role: "Heavy hitter"))
        XCTAssertEqual(s.slots[2].pick, "k1")
        // Under Available there are no Best rows on screen: the stored species pick is still cleared, through the Best rows the caller reads.
        var t = SquadStore.Saved(slots: [SquadSlot(role: "Heavy hitter", species: "kyogre"), SquadSlot(role: "Heavy hitter")])
        t.choose("k1", at: 1, alsoClearing: HubSquads.equivalents(of: "k1", rows: HubSquads.bestRaidRows(row: fireBoss, ctx: kyogreCtx())))
        XCTAssertNil(t.slots[0].species)
        // The reverse: a species pick wins over an earlier copy pick.
        var u = SquadStore.Saved(slots: [SquadSlot(role: "Heavy hitter", pick: "k1"), SquadSlot(role: "Heavy hitter")])
        u.choose("species:kyogre", at: 1, alsoClearing: HubSquads.equivalents(of: "species:kyogre", rows: rows))
        XCTAssertNil(u.slots[0].pick)
        XCTAssertEqual(u.slots[1].species, "kyogre")
        // Across Rocket slots: a copy chosen in one slot clears the species pick of any slot's row for it.
        let machamp = P23.boss("kangaskhan", types: ["normal"])
        let table = P23.table([P23.tierEntry("rocket", "Attacker tiers", "S", "machamp_shadow", shadow: true), P23.tierEntry("rocket", "Attacker tiers", "A", "machamp")])
        let ctx = P23.ctx(builds: [P23.build("s1", "machamp", areas: ["Rocket"])], entries: [P23.entry("s1", "machamp", shadow: 1)], table: table, rotation: [])
        let all = HubSquads.bestRocketRows(options: [machamp], ctx: ctx) + HubSquads.bestRocketRows(options: [machamp, machamp], ctx: ctx)
        var r = SquadStore.Saved(slots: [SquadSlot(role: "Counter", species: "machamp"), SquadSlot(role: "Counter")])
        r.choose("s1", at: 1, alsoClearing: HubSquads.equivalents(of: "s1", rows: all))
        XCTAssertNil(r.slots[0].species)
    }

    // MARK: Shadow copies by area (S1), Max rotation (S3)

    func testAShadowCopyServesRaidsAndRocketPlainRowsButNotGymOrMax() {
        let shadowCopy = P23.entry("s1", "garchomp", shadow: 1)
        // Raids: a Shadow target (garchomp_shadow) also fills the plain Garchomp row.
        let raids = P23.ctx(builds: [P23.build("s1", "garchomp_shadow", areas: ["Raids"])], entries: [shadowCopy], table: P23.table([P23.tierEntry("raids", "Ground", "A", "garchomp")]), rotation: [])
        XCTAssertEqual(HubSquads.bestRaidRows(row: fireBoss, ctx: raids).map(\.ownedEntryId), ["s1"])
        XCTAssertEqual(HubRaidsModel.raidEntries(targetId: "garchomp_shadow", viaMega: false, table: raids.table, shadow: true).map(\.speciesId), ["garchomp"])
        // A copy with no build still serves the plain row in Raids.
        let bare = P23.ctx(entries: [shadowCopy], table: P23.table([P23.tierEntry("raids", "Ground", "A", "garchomp")]), rotation: [])
        XCTAssertEqual(HubSquads.bestRaidRows(row: fireBoss, ctx: bare).map(\.ownedEntryId), ["s1"])
        // Gym and Max: no.
        let gymTable = P23.table([P23.tierEntry("gym", "Tiers", "S", "garchomp")])
        let gym = P23.ctx(builds: [P23.build("s1", "garchomp", areas: ["Gym"])], entries: [shadowCopy], table: gymTable, rotation: [])
        XCTAssertEqual(HubSquads.bestGymRows(ctx: gym).map(\.inBox), [false], "a Shadow cannot defend a gym")
        let maxTable = P23.table([P23.tierEntry("max", "Attackers", "S", "garchomp")])
        let boss = P23.row("2026-10-26", "2026-10-26", .maxMonday, bosses: [P23.boss("charizard", types: ["fire"])])
        let max = P23.ctx(builds: [P23.build("s1", "garchomp", areas: ["Max"])], entries: [shadowCopy], table: maxTable, rotation: [])
        XCTAssertEqual(HubSquads.bestMaxRows(row: boss, ctx: max).map(\.inBox), [false], "a Shadow cannot go Dynamax")
        // A plain copy serves them.
        let plain = P23.entry("p1", "garchomp")
        XCTAssertEqual(HubSquads.bestGymRows(ctx: P23.ctx(builds: [P23.build("p1", "garchomp", areas: ["Gym"])], entries: [plain], table: gymTable, rotation: [])).map(\.ownedEntryId), ["p1"])
    }

    func testAHandMarkWinsOverTheShadowSpeciesId() {
        func copy(_ id: String, mark: Int?, species: String = "garchomp_shadow") -> BoxEntry {
            var e = P23.entry(id, "garchomp", shadow: mark)
            e.row.speciesId = species
            return e
        }
        XCTAssertTrue(HubRaidsModel.isShadow(copy("a", mark: nil)), "no mark: the species id decides")
        XCTAssertTrue(HubRaidsModel.isShadow(copy("a", mark: 1)))
        XCTAssertFalse(HubRaidsModel.isShadow(copy("a", mark: 2)), "Purified is not Shadow, whatever the species id says")
        XCTAssertFalse(HubRaidsModel.isShadow(copy("a", mark: 0)), "marked neither")
        XCTAssertTrue(HubRaidsModel.isShadow(copy("a", mark: 1, species: "garchomp")), "the mark makes a plain id Shadow")
        let build = P23.build("a", "garchomp_shadow", areas: ["Raids"])
        XCTAssertTrue(HubRaidsModel.isShadow(build, entries: [copy("a", mark: nil)]))
        XCTAssertFalse(HubRaidsModel.isShadow(build, entries: [copy("a", mark: 2)]), "a Purified copy whose target ends _shadow")
        XCTAssertTrue(HubRaidsModel.isShadow(build, entries: []), "no copy, no mark: the target decides")
        // A Purified `_shadow` copy fills the plain row only: a Shadow row of the table is not its row.
        let table = P23.table([P23.tierEntry("raids", "Ground", "S", "garchomp_shadow", shadow: true, name: "Shadow Garchomp"), P23.tierEntry("raids", "Ground", "A", "garchomp")])
        func rows(_ mark: Int?) -> [HubSquads.BestRow] {
            HubSquads.bestRaidRows(row: fireBoss, ctx: P23.ctx(builds: [build], entries: [copy("a", mark: mark)], table: table, rotation: []))
        }
        XCTAssertEqual(rows(2).map(\.key), ["garchomp_shadow", "garchomp"])
        XCTAssertEqual(rows(2).map(\.inBox), [false, true], "Purified: not the Shadow row")
        XCTAssertEqual(rows(1).map(\.inBox), [true, true], "Shadow: both")
        XCTAssertEqual(rows(1).map(\.sharedWith), [nil, "Shadow Garchomp"])
    }

    func testAMaxRowsRotationReadsMaxBattlesOnly() {
        let table = P23.table([P23.tierEntry("max", "Attackers", "S", "kingler")])
        let boss = P23.row("2026-10-26", "2026-10-26", .maxMonday, bosses: [P23.boss("charizard", types: ["fire"])])
        let raidBoss = [P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("kingler", types: ["water"])])]
        XCTAssertEqual(HubSquads.bestMaxRows(row: boss, ctx: P23.ctx(table: table, rotation: raidBoss)).map(\.availability), [""], "a raid boss is no Max battle")
        let maxBoss = [P23.row("2026-11-02", "2026-11-02", .maxMonday, title: "Max Monday", bosses: [P23.boss("kingler", types: ["water"])])]
        XCTAssertEqual(HubSquads.bestMaxRows(row: boss, ctx: P23.ctx(table: table, rotation: maxBoss)).map(\.availability), ["Max Monday 2 Nov"])
    }

    func testMaxAttackerTakesTheFirstThatHitsTheBossEvenOverAHigherTier() {
        let table = P23.table([P23.tierEntry("max", "Attackers", "S", "venusaur"), P23.tierEntry("max", "Attackers", "A", "kingler")])
        let boss = P23.row("2026-10-26", "2026-10-26", .maxMonday, bosses: [P23.boss("charizard", types: ["fire"])])
        let rows = HubSquads.bestMaxRows(row: boss, ctx: P23.ctx(table: table, rotation: []))
        XCTAssertEqual(rows.map(\.key), ["venusaur", "kingler"])
        XCTAssertEqual(rows.map(\.hitsBoss), [false, true])
        XCTAssertEqual(HubSquads.bestSquad(slots: HubSquads.defaultMaxSlots(), rows: rows).map(\.pickId), [nil, nil, "species:kingler"])
    }

    func testTeamStatusLine() {
        typealias S = HubSquads.SlotStatus
        XCTAssertEqual(HubSquads.teamStatus([.ready, .ready]), .init(level: .green, text: "Ready"))
        XCTAssertEqual(HubSquads.teamStatus([.ready, .needsWork]), .init(level: .amber, text: "Nearly ready: 1 needs work"))
        XCTAssertEqual(HubSquads.teamStatus([.empty, .ready]), .init(level: .red, text: "Not ready: 1 empty"))
        XCTAssertNil(HubSquads.teamStatus([]))
        XCTAssertEqual(S.empty.spoken, "empty")
    }

    func testStatusTiersAreTheTablesForTheAreaAndSlot() {
        let table = P23.table([P23.tierEntry("gym", "Tiers", "A", "snorlax"), P23.tierEntry("gl", "Tiers", "S", "medicham")])
        let ctx = P23.ctx(table: table)
        XCTAssertEqual(HubSquads.gymTableTier(P23.build("g", "snorlax", areas: ["Gym"], tier: "B"), ctx: ctx), "A", "the table's, not the build's")
        XCTAssertEqual(HubSquads.gymTableTier(P23.build("g", "lapras", areas: ["Gym"], tier: "S"), ctx: ctx), "", "not in the Gym table")
        let listed = try! TierTable.bundled().entries.first { $0.area == "gl" }!
        XCTAssertEqual(HubSquads.pvpTier(speciesId: listed.speciesId, league: "gl", score: 50), listed.tier, "the league table wins over the score")
        XCTAssertEqual(HubSquads.pvpTier(speciesId: "bunnelby", league: "gl", score: 93), "S")
        XCTAssertEqual(HubSquads.pvpTier(speciesId: "bunnelby", league: "gl", score: 89), "B")
        XCTAssertEqual(HubSquads.pvpTier(speciesId: "bunnelby", league: "gl", score: 70), "")
    }

    // MARK: Best, the other screens

    func testBestMaxRowsUseTheMaxTablesRolesAndSkipGigantamax() {
        let table = P23.table([P23.tierEntry("max", "Tanks and healers", "S", "blissey", role: "Tank and healer"),
                               P23.tierEntry("max", "Attackers", "S", "vaporeon"),
                               P23.tierEntry("max", "Attackers", "S", "gengar", max: true, name: "Gigantamax Gengar"),
                               P23.tierEntry("max", "Attackers", "A", "kingler"), P23.tierEntry("max", "Tanks and healers", "B", "snorlax", role: "Tank")])
        let boss = P23.row("2026-10-26", "2026-10-26", .maxMonday, bosses: [P23.boss("sableye", types: ["ghost", "fairy"])])
        let ctx = P23.ctx(builds: [P23.build("m1", "kingler", areas: ["Max"], built: false)], table: table, rotation: [])
        let rows = HubSquads.bestMaxRows(row: boss, ctx: ctx)
        XCTAssertEqual(rows.map(\.key), ["blissey", "vaporeon", "kingler", "snorlax"], "Gigantamax Gengar is never used (rule 12)")
        XCTAssertEqual(rows.map(\.roles), [["Tank", "Healer"], ["Attacker"], ["Attacker"], ["Tank"]])
        XCTAssertEqual(rows.map(\.inBox), [false, false, true, false])
        let squad = HubSquads.bestSquad(slots: HubSquads.defaultMaxSlots(), rows: rows)
        XCTAssertEqual(squad.map(\.pickId), ["species:blissey", nil, "species:vaporeon"], "Tank: Blissey; Healer: Blissey is the only healer and is used, so empty; Attacker: the first that hits the ghost boss's weak types, else the first")
    }

    func testBestGymRowsAreTheGymTableInOrder() {
        let table = P23.table([P23.tierEntry("gym", "Tiers", "A", "snorlax"), P23.tierEntry("gym", "Tiers", "S", "chansey", obtain: "Easy. Wild"),
                               P23.tierEntry("gym", "Tiers", "S", "blissey"), P23.tierEntry("gym", "Tiers", "B", "lapras")])
        let ctx = P23.ctx(builds: [P23.build("g1", "blissey", areas: ["Gym"]), P23.build("g2", "lapras", areas: ["Raids"])], table: table, rotation: [])
        let rows = HubSquads.bestGymRows(ctx: ctx)
        XCTAssertEqual(rows.map(\.key), ["chansey", "blissey", "snorlax", "lapras"], "S then A then B; the table's order within a tier")
        XCTAssertEqual(rows.map(\.ownedEntryId), [nil, "g1", nil, nil], "g2 has no Gym build")
        XCTAssertEqual(rows.map(\.availability), ["Easy. Wild", "", "", ""])
    }

    func testBestRocketRowsAreTheTableEntriesThatBeatTheSlot() {
        let machamp = P23.boss("machamp", types: ["fighting"])
        let table = P23.table([P23.tierEntry("rocket", "Attacker tiers", "S", "swampert"), P23.tierEntry("rocket", "Attacker tiers", "A", "togekiss"),
                               P23.tierEntry("rocket", "Attacker tiers", "S", "alakazam"), P23.tierEntry("rocket", "Attacker tiers", "B", "charizard")])
        let ctx = P23.ctx(builds: [P23.build("r1", "togekiss", areas: ["Rocket"]), P23.build("r2", "swampert", areas: ["Raids"])], table: table, rotation: [])
        let rows = HubSquads.bestRocketRows(options: [machamp], ctx: ctx)
        XCTAssertEqual(rows.map(\.key), ["alakazam", "togekiss", "charizard"], "Swampert does not beat Fighting")
        XCTAssertEqual(rows.map(\.ownedEntryId), [nil, "r1", nil])
        XCTAssertEqual(rows.map(\.hits), [1, 1, 1])
        XCTAssertEqual(rows.map(\.slotLine), [nil, nil, nil], "one option: no beats line")
        let two = HubSquads.bestRocketRows(options: [machamp, P23.boss("kangaskhan", types: ["normal"])], ctx: ctx)
        XCTAssertEqual(two.map(\.slotLine), ["beats 1 of 2", "beats 1 of 2", "beats 1 of 2"])
    }

    func testBestPvpRowsFollowTheTablesRankAndCarryTheBoxCopy() {
        let table = P23.table([P23.tierEntry("gl", "Tiers", "A", "registeel", role: "Switch / generalist", rank: 3),
                               P23.tierEntry("gl", "Tiers", "S", "medicham", role: "Lead 100, closer 95", rank: 2),
                               P23.tierEntry("gl", "Tiers", "S", "azumarill", role: "Safe swap 97.6", rank: 1),
                               P23.tierEntry("gl", "Tiers", "S", "lanturn", role: "Closer", rank: 4)])
        let ratings = ["c0": ["gl": P23.rating([P23.option("azumarill", score: 94)])], "c1": ["gl": P23.rating([P23.option("registeel", score: 90)])]]
        let ctx = P23.ctx(table: table, rotation: [], leagues: ratings)
        let rows = HubSquads.bestPvpRows(league: "gl", ctx: ctx)
        XCTAssertEqual(rows.map(\.key), ["azumarill", "medicham", "lanturn", "registeel"], "tier, then the table's #")
        XCTAssertEqual(rows.map(\.ownedEntryId), ["c0", nil, nil, "c1"])
        XCTAssertEqual(rows.map(\.roles), [["Safe swap"], ["Lead", "Closer"], ["Closer"], ["Safe swap"]])
        XCTAssertEqual(rows[1].availability, "")
        let squad = HubSquads.bestSquad(slots: HubSquads.defaultPvpSlots(), rows: rows, fallback: true)
        XCTAssertEqual(squad.map(\.pickId), ["species:medicham", "c0", "species:lanturn"])
    }

    // MARK: the store

    func testSpeciesPicksAreKeptAndOldDataStillLoads() throws {
        var s = SquadStore()
        s.gym.choose("species:chansey", at: 0)
        s.gym.choose("g1", at: 1)
        XCTAssertEqual(s.gym.slots[0], SquadSlot(role: "Defender", pick: nil, species: "chansey"))
        XCTAssertEqual(s.gym.slots[1].pick, "g1")
        // Choosing the same Pokémon elsewhere takes it out of the first slot; choosing a copy replaces a species pick.
        s.gym.choose("species:chansey", at: 2)
        XCTAssertNil(s.gym.slots[0].species)
        s.gym.choose("g1", at: 2)
        XCTAssertNil(s.gym.slots[2].species)
        XCTAssertEqual(s.gym.slots[2].pick, "g1")
        XCTAssertNil(s.gym.slots[1].pick)
        s.gym.choose("species:blissey", at: 3)
        // A copy leaving the box does not touch a species pick.
        XCTAssertEqual(s.reconciled(boxIds: []).gym.slots[3].species, "blissey")
        XCTAssertNil(s.reconciled(boxIds: []).gym.slots[2].pick)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(SquadStore.self, from: data), s)
        // A file written before species picks existed.
        let old = #"{"version":1,"modes":{"raids":"best"},"gym":{"slots":[{"role":"Defender","pick":"keep-me"},{"role":"Defender"}],"isSet":false}}"#
        let loaded = try JSONDecoder().decode(SquadStore.self, from: Data(old.utf8))
        XCTAssertEqual(loaded.gym.slots[0], SquadSlot(role: "Defender", pick: "keep-me"))
        XCTAssertNil(loaded.gym.slots[0].species)
        XCTAssertEqual(loaded.mode(for: .raids), .best)
    }

    func testAPickThatDoesNotFitUnderAModeStaysInTheStoreAndReturns() {
        // A species pick (a Pokémon the box lacks) is not placed under Available and is under Best; a copy whose build is gone is the other way round.
        let ctx = P23.ctx(builds: [P23.build("e6", "swampert", areas: ["Raids"], powerUp: false, viaMega: true)], entries: [P23.entry("e6", "swampert")], table: raidTable())
        let slots = [SquadSlot(role: "Heavy hitter", pick: "e6"), SquadSlot(role: "Heavy hitter", pick: "e9")]
        let available = HubSquads.placeable(screen: .raids, mode: .available, ctx: ctx)
        let best = HubSquads.placeable(screen: .raids, mode: .best, ctx: ctx)
        XCTAssertTrue(available("e6", "Heavy hitter"), "S1: a Mega build is placeable under Available")
        XCTAssertFalse(available("e9", "Heavy hitter"), "no build of the copy")
        XCTAssertTrue(best("e9", "Heavy hitter"))
        XCTAssertEqual(HubSquads.fill(slots: slots, pool: { _, _ in .init(preferred: []) }, placeable: available).map(\.entryId), ["e6", nil])
        XCTAssertEqual(HubSquads.fill(slots: slots, pool: { _, _ in .init(preferred: []) }, placeable: best).map(\.entryId), ["e6", "e9"])
        XCTAssertFalse(HubSquads.placeable(screen: .raids, mode: .available, ctx: ctx)("species:excadrill", "Heavy hitter"))
        // Changing the slot's role to one the species does not fit drops a species pick, as it does a copy.
        var s = [SquadSlot(role: "Heavy hitter", species: "excadrill")]
        HubSquads.changeRole(&s, at: 0, to: "Mega") { _ in false }
        XCTAssertEqual(s[0], SquadSlot(role: "Mega"))
    }

    // MARK: status

    func testSlotStatusIsGreenAmberOrRed() {
        typealias S = HubSquads.SlotStatus
        XCTAssertEqual(HubSquads.slotStatus(inBox: true, fullStrength: true, tier: "S"), S.ready)
        XCTAssertEqual(HubSquads.slotStatus(inBox: true, fullStrength: true, tier: "A"), S.ready)
        XCTAssertEqual(HubSquads.slotStatus(inBox: true, fullStrength: true, tier: "B"), S.needsWork)
        XCTAssertEqual(HubSquads.slotStatus(inBox: true, fullStrength: true, tier: ""), S.needsWork, "not in the table")
        XCTAssertEqual(HubSquads.slotStatus(inBox: true, fullStrength: false, tier: "S"), S.needsWork, "Upgrade available")
        XCTAssertEqual(HubSquads.slotStatus(inBox: false, fullStrength: false, tier: "S"), S.toGet)
        XCTAssertEqual([S.ready, .needsWork, .toGet, .empty].map(\.spoken), ["ready", "needs work", "not in your box, to get", "empty"])
    }

    func testTheTeamLine() {
        typealias S = HubSquads.SlotStatus
        XCTAssertEqual(HubSquads.teamStatus([.ready, .ready]), .init(level: .green, text: "Ready"))
        XCTAssertEqual(HubSquads.teamStatus([.ready, .needsWork]), .init(level: .amber, text: "Nearly ready: 1 needs work"))
        XCTAssertEqual(HubSquads.teamStatus([.needsWork, .ready, .needsWork]), .init(level: .amber, text: "Nearly ready: 2 need work"))
        XCTAssertEqual(HubSquads.teamStatus([.ready, .empty, .needsWork, .empty]), .init(level: .red, text: "Not ready: 2 empty"))
        XCTAssertEqual(HubSquads.teamStatus([.toGet, .toGet, .empty, .ready]), .init(level: .red, text: "Not ready: 2 to get, 1 empty"))
        XCTAssertEqual(HubSquads.teamStatus([.toGet, .ready]), .init(level: .red, text: "Not ready: 1 to get"))
        XCTAssertNil(HubSquads.teamStatus([]))
    }
}
