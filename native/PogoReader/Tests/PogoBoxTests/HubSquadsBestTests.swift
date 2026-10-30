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
        XCTAssertEqual(line("mewtwo"), "Last available not known")
        XCTAssertEqual(line("mewtwo", obtain: "  "), "Last available not known")
        XCTAssertEqual(line("blissey"), "Last available not known", "a Raid Hour is no boss row: it is never read")
        // The last day of a run still counts; the next day does not.
        XCTAssertEqual(line("palkia", in: P23.ctx(today: "2026-10-30", rotation: rows)), "Raid boss now")
        XCTAssertEqual(line("palkia", obtain: "Hard", in: P23.ctx(today: "2026-10-31", rotation: rows)), "Hard")
        XCTAssertEqual(line("machop", in: P23.ctx(today: "2026-10-27", rotation: rows)), "Last available not known")
        XCTAssertEqual(line("machop", in: P23.ctx(today: "2026-10-20", rotation: rows)), "Max Monday 26 Oct")
    }

    func testAShadowEntryIsOnlyTheShadowBossAndTheReverse() {
        let rows = [P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("giratina_origin", types: ["ghost", "dragon"])]),
                    P23.row("2026-10-20", "2026-10-30", .shadow, bosses: [P23.boss("landorus_incarnate_shadow", types: ["ground", "flying"])])]
        let ctx = P23.ctx(today: "2026-10-26", rotation: rows)
        func line(_ id: String, shadow: Bool) -> String { HubSquads.availability(of: P23.tierEntry("raids", "Ghost", "S", id, shadow: shadow), ctx: ctx) }
        XCTAssertEqual(line("giratina_origin", shadow: false), "Raid boss now")
        XCTAssertEqual(line("giratina_origin", shadow: true), "Last available not known", "Shadow Giratina is not the plain Giratina raid")
        XCTAssertEqual(line("giratina_origin_shadow", shadow: true), "Last available not known")
        XCTAssertEqual(line("landorus_incarnate", shadow: false), "Last available not known", "the plain Landorus is not the Shadow raid")
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
        XCTAssertEqual(HubSquads.equivalents(of: "species:swampert", rows: rows).sorted(), ["e2", "species:swampert"])
        let slots = [SquadSlot(role: "Bulky hitter", species: "swampert")]
        let squad = HubSquads.bestSquad(slots: slots, rows: rows)
        XCTAssertEqual(squad[0].entryId, "e2")
        XCTAssertEqual(squad[0].species, "swampert", "the slot remembers the row the player chose")
        XCTAssertTrue(squad[0].ids.contains("species:swampert") && squad[0].ids.contains("e2"))
    }

    func testChoosingAClearsTheSameCopyOrSpeciesFromOtherSlots() {
        var s = SquadStore.Saved(slots: [SquadSlot(role: "Heavy hitter", species: "garchomp"), SquadSlot(role: "Heavy hitter")])
        s.choose("e9", at: 1, alsoClearing: ["species:garchomp", "e9"])
        XCTAssertEqual(s.slots[0], SquadSlot(role: "Heavy hitter"), "the copy chosen later wins over the species pick")
        XCTAssertEqual(s.slots[1].pick, "e9")
        var t = SquadStore.Saved(slots: [SquadSlot(role: "Heavy hitter", pick: "e9"), SquadSlot(role: "Heavy hitter")])
        t.choose("species:garchomp", at: 1, alsoClearing: ["e9"])
        XCTAssertNil(t.slots[0].pick)
        XCTAssertEqual(t.slots[1].species, "garchomp")
    }

    func testMaxAttackerTakesTheFirstThatHitsTheBossEvenOverAHigherTier() {
        let table = P23.table([P23.tierEntry("max", "Attackers", "S", "venusaur"), P23.tierEntry("max", "Attackers", "A", "kingler")])
        let boss = P23.row("2026-10-26", "2026-10-26", .maxMonday, bosses: [P23.boss("charizard", types: ["fire"])])
        let rows = HubSquads.bestMaxRows(row: boss, ctx: P23.ctx(table: table, rotation: []))
        XCTAssertEqual(rows.map(\.key), ["venusaur", "kingler"])
        XCTAssertEqual(rows.map(\.hitsBoss), [false, true])
        XCTAssertEqual(HubSquads.bestSquad(slots: HubSquads.defaultMaxSlots(), rows: rows).map(\.pickId), [nil, nil, "species:kingler"])
    }

    func testAMegaSlotUnderAvailableIsNotCounted() {
        XCTAssertTrue(HubSquads.slotNotCounted(screen: .raids, mode: .available, role: "Mega", filled: false))
        XCTAssertFalse(HubSquads.slotNotCounted(screen: .raids, mode: .best, role: "Mega", filled: false))
        XCTAssertFalse(HubSquads.slotNotCounted(screen: .raids, mode: .available, role: "Heavy hitter", filled: false), "a slot changed from Mega counts as empty")
        XCTAssertFalse(HubSquads.slotNotCounted(screen: .max, mode: .available, role: "Mega", filled: false))
        typealias S = HubSquads.SlotStatus
        XCTAssertEqual(HubSquads.teamStatus([.notCounted, .ready, .ready]), .init(level: .green, text: "Ready"))
        XCTAssertEqual(HubSquads.teamStatus([.notCounted, .needsWork]), .init(level: .amber, text: "Nearly ready: 1 needs work"))
        XCTAssertEqual(HubSquads.teamStatus([.notCounted, .empty, .ready]), .init(level: .red, text: "Not ready: 1 empty"))
        XCTAssertNil(HubSquads.teamStatus([.notCounted]))
        XCTAssertEqual(S.notCounted.spoken, "not counted under Available")
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
        XCTAssertEqual(rows.map(\.availability), ["Easy. Wild", "", "Last available not known", "Last available not known"])
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
        XCTAssertEqual(rows[1].availability, "Last available not known")
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
        // An evolution pick is not placed under Available, and is under Best; the species pick is the other way round.
        let ctx = P23.ctx(builds: [P23.build("e6", "swampert", areas: ["Raids"], powerUp: false, viaMega: true)], table: raidTable())
        let slots = [SquadSlot(role: "Mega", pick: "e6")]
        let available = HubSquads.placeable(screen: .raids, mode: .available, ctx: ctx)
        let best = HubSquads.placeable(screen: .raids, mode: .best, ctx: ctx)
        XCTAssertFalse(available("e6", "Mega"))
        XCTAssertTrue(best("e6", "Mega"))
        XCTAssertNil(HubSquads.fill(slots: slots, pool: { _, _ in .init(preferred: []) }, placeable: available)[0].entryId)
        XCTAssertEqual(HubSquads.fill(slots: slots, pool: { _, _ in .init(preferred: []) }, placeable: best)[0].entryId, "e6")
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
