import XCTest
@testable import PogoBox
import PogoReader

/// Pass 2's per-screen rules: Raids (8 to 10), Max (12), Gym (13, 14), Rocket (16 to 21), PvP (22, 23), each on a hand-made box and tier table so the
/// rule is pinned on exactly the data it reads. A fire boss is weak to Water, Ground and Rock (the bring types, in that order).
final class HubSquadsAreasTests: XCTestCase {
    private let fireBoss = P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("charizard", types: ["fire"])])

    // MARK: Raids

    private func raidTable() -> TierTable {
        P23.table([P23.tierEntry("raids", "Water", "S", "vaporeon"),
                   P23.tierEntry("raids", "Water", "A", "swampert"), P23.tierEntry("raids", "Ground", "A", "swampert"),
                   P23.tierEntry("raids", "Water", "B", "kingler"),
                   P23.tierEntry("raids", "Ground", "A", "excadrill"),
                   P23.tierEntry("raids", "Ground", "S", "rhyperior"), P23.tierEntry("raids", "Rock", "S", "rhyperior"),
                   P23.tierEntry("raids", "Water", "A", "blastoise"),
                   P23.tierEntry("raids", "Water", "S", "swampert_mega", mega: true),
                   P23.tierEntry("raids", "Fire", "S", "charizard")])
    }
    private func raidBuilds() -> [BoxAdvice.Build] {
        [P23.build("e1", "vaporeon", areas: ["Raids"]),
         P23.build("e2", "swampert", areas: ["Raids"]),
         P23.build("e3", "kingler", areas: ["Raids"], built: false),
         P23.build("e1", "kingler", areas: ["Raids"]),                       // a second build of copy e1: one entry per copy
         P23.build("e4", "excadrill", areas: ["Raids"]),
         P23.build("e5", "rhyperior", areas: ["Raids"]),
         P23.build("e6", "swampert", areas: ["Raids"], powerUp: false, viaMega: true),
         P23.build("e7", "blastoise", areas: ["Raids"], built: false),
         P23.build("e8", "vaporeon", areas: ["Gym"]),                        // no Raids area
         P23.build("e9", "charizard", areas: ["Raids"])]                     // Fire is not a bring type
    }

    func testTheBossBringsWaterGroundRock() {
        XCTAssertEqual(HubRaidsModel.bring(row: fireBoss, hub: P23.hub), ["water", "ground", "rock"])
    }

    func testRaidCandidatesAreOrderedByTierThenBuiltThenCoverage() {
        let ctx = P23.ctx(builds: raidBuilds(), table: raidTable())
        let best = HubSquads.raidCandidates(row: fireBoss, mode: .best, ctx: ctx)
        // S: rhyperior (covers Ground and Rock) and the Mega swampert (Water and Ground) tie on coverage, so the advisor's order; vaporeon covers one.
        // A: built swampert (two), built excadrill (one), blastoise not built. B: kingler (copy e3; e1's second build is dropped for the copy).
        XCTAssertEqual(best.map(\.entryId), ["e5", "e6", "e1", "e2", "e4", "e7", "e3"])
        XCTAssertEqual(best.map(\.tier), ["S", "S", "S", "A", "A", "A", "B"])
        XCTAssertEqual(best.map(\.covers), [2, 2, 1, 2, 1, 1, 1])
        XCTAssertEqual(best.map(\.built), [true, true, true, true, true, false, false])
        XCTAssertEqual(best.map(\.role), [.bulky, .mega, .bulky, .bulky, .heavy, .bulky, .heavy])
        let available = HubSquads.raidCandidates(row: fireBoss, mode: .available, ctx: ctx)
        // S1: Available takes every build and judges e6 as the plain Swampert (A, tied with e2, behind it in the advisor's order); its Mega build is for the Mega slot only.
        XCTAssertEqual(available.map(\.entryId), ["e5", "e1", "e2", "e6", "e4", "e7", "e3"])
        XCTAssertEqual(available.map(\.role), [.bulky, .bulky, .bulky, .bulky, .heavy, .bulky, .heavy], "no Mega role under Available outside the Mega slot")
    }

    func testRaidRolesFollowRule8() {
        let gm = P23.gm
        XCTAssertEqual(PogoRules.raidRole(targetId: "lucario", viaMega: true, shadow: false, gm: gm), .mega)
        XCTAssertEqual(PogoRules.raidRole(targetId: "kyogre_primal", viaMega: false, shadow: false, gm: gm), .mega)
        XCTAssertEqual(PogoRules.raidRole(targetId: "vaporeon", viaMega: false, shadow: true, gm: gm), .heavy, "a Shadow copy is always Heavy")
        XCTAssertEqual(PogoRules.raidRole(targetId: "kingler", viaMega: false, shadow: false, gm: gm), .heavy, "240 / 181 is 1.33")
        XCTAssertEqual(PogoRules.raidRole(targetId: "vaporeon", viaMega: false, shadow: false, gm: gm), .bulky, "205 / 161 is 1.27, under 1.3")
        XCTAssertEqual(PogoRules.raidRole(targetId: "not_a_species", viaMega: false, shadow: false, gm: gm), .bulky, "no stats: Bulky")
    }

    func testSuggestedRaidSquadIsOneMegaThreeHeavyTwoBulky() {
        let ctx = P23.ctx(builds: raidBuilds(), table: raidTable())
        let best = HubSquads.raidSquad(candidates: HubSquads.raidCandidates(row: fireBoss, mode: .best, ctx: ctx), placeable: P23.anyone)
        XCTAssertEqual(best.map(\.role), ["Mega", "Heavy hitter", "Heavy hitter", "Heavy hitter", "Bulky hitter", "Bulky hitter"])
        XCTAssertEqual(best.map(\.entryId), ["e6", "e4", "e3", nil, "e5", "e1"], "two Heavy exist; the third slot stays empty")
        // e6 is a Swampert, which can Mega Evolve: under Available only a copy the box holds as one takes the Mega slot.
        let megaCtx = P23.ctx(builds: raidBuilds(), entries: [P23.entry("e6", "swampert")], table: raidTable())
        let available = HubSquads.raidSquad(candidates: HubSquads.raidCandidates(row: fireBoss, mode: .available, ctx: megaCtx), placeable: P23.anyone)
        XCTAssertEqual(available.map(\.entryId), ["e6", "e4", "e3", nil, "e5", "e1"], "S1: the Mega slot takes the Mega build under Available too")
        // Fill with any role: the empty third Heavy slot takes the strongest unused candidate, and the Bulky slots then take what is left.
        let any = HubSquads.raidSquad(candidates: HubSquads.raidCandidates(row: fireBoss, mode: .available, ctx: megaCtx), fillAnyRole: true, placeable: P23.anyone)
        XCTAssertEqual(any.map(\.entryId), ["e6", "e4", "e3", "e2", "e5", "e1"], "the Bulky slots keep the Bulky Pokémon; the empty Heavy slot takes the next strongest")
        XCTAssertEqual(any.map(\.fallback), [false, false, false, true, false, false])
        // A pick the player made stays, and the suggestion skips that copy.
        let picked = HubSquads.raidSquad(slots: [SquadSlot(role: "Mega"), SquadSlot(role: "Heavy hitter"), SquadSlot(role: "Bulky hitter", pick: "e4")],
                                         candidates: HubSquads.raidCandidates(row: fireBoss, mode: .best, ctx: ctx), placeable: P23.anyone)
        XCTAssertEqual(picked.map(\.entryId), ["e6", "e3", "e4"])
        XCTAssertEqual(picked.map(\.chosen), [false, false, true])
    }

    func testRaidSquadForABossWithNoCounterOrNoBossIsEmpty() {
        let ctx = P23.ctx(builds: raidBuilds(), table: raidTable())
        let noBoss = P23.row("2026-10-28", "2026-10-28", .raidHour, bosses: [])
        XCTAssertEqual(HubSquads.raidCandidates(row: noBoss, mode: .best, ctx: ctx), [])
        XCTAssertTrue(HubSquads.raidSquad(candidates: [], placeable: P23.anyone).allSatisfy { $0.entryId == nil })
        XCTAssertEqual(HubSquads.raidCandidates(row: fireBoss, mode: .best, ctx: P23.ctx()), [], "an empty box")
    }


    // MARK: Max

    private func maxTable() -> TierTable {
        P23.table([P23.tierEntry("max", "Tanks and healers", "S", "blissey", role: "Tank and healer"),
                   P23.tierEntry("max", "Tanks and healers", "A", "snorlax", role: "Tank"),
                   P23.tierEntry("max", "Tanks and healers", "B", "chansey", role: "Healer"),
                   P23.tierEntry("max", "Attackers", "S", "vaporeon"),
                   P23.tierEntry("max", "Attackers", "A", "gengar"),
                   P23.tierEntry("max", "Attackers", "B", "kingler"),
                   P23.tierEntry("max", "Attackers", "S", "lapras", max: true, name: "Gigantamax Lapras")])
    }
    private func maxBuilds() -> [BoxAdvice.Build] {
        ["blissey", "snorlax", "vaporeon", "gengar", "kingler", "lapras", "chansey"].enumerated().map { i, s in P23.build("m\(i)", s, areas: ["Max"]) }
    }

    func testMaxRolesComeFromTheMaxTable() {
        let t = maxTable()
        XCTAssertEqual(PogoRules.maxRoles(of: "blissey", table: t), [.tank, .healer], "Blissey is both")
        XCTAssertEqual(PogoRules.maxRoles(of: "snorlax", table: t), [.tank])
        XCTAssertEqual(PogoRules.maxRoles(of: "chansey", table: t), [.healer])
        XCTAssertEqual(PogoRules.maxRoles(of: "vaporeon", table: t), [.attacker])
        XCTAssertEqual(PogoRules.maxRoles(of: "lapras", table: t), [], "Gigantamax entries are never used")
        XCTAssertEqual(PogoRules.maxRoles(of: "pikachu", table: t), [], "not in the table")
        let odd = P23.tierEntry("max", "Tanks and healers", "A", "snorlax", role: "Cinderace-specific tanks")
        XCTAssertEqual(PogoRules.maxRoles(odd), [.tank])
        XCTAssertEqual(PogoRules.maxRoles(P23.tierEntry("max", "Tanks and healers", "A", "snorlax", role: nil)), [])
    }

    func testMaxCandidatesAreOrderedByTierThenHittingTheBoss() {
        let ctx = P23.ctx(builds: maxBuilds(), table: maxTable())
        let c = HubSquads.maxCandidates(row: fireBoss, mode: .best, ctx: ctx)
        // S: Vaporeon hits a fire boss, Blissey does not. A: Snorlax before Gengar (advisor order; neither hits). B: Kingler hits, Chansey (later) does not.
        XCTAssertEqual(c.map { $0.build.targetId }, ["vaporeon", "blissey", "snorlax", "gengar", "kingler", "chansey"], "Gigantamax Lapras has no usable entry")
        XCTAssertEqual(c.map(\.hitsBoss), [true, false, false, false, true, false])
        XCTAssertEqual(c.map(\.tier), ["S", "S", "A", "A", "B", "B"])
    }

    func testSuggestedMaxSquadIsTankHealerAttackerThatHitsTheBoss() {
        let ctx = P23.ctx(builds: maxBuilds(), table: maxTable())
        let squad = HubSquads.maxSquad(candidates: HubSquads.maxCandidates(row: fireBoss, mode: .best, ctx: ctx), placeable: P23.anyone)
        XCTAssertEqual(squad.map(\.role), ["Tank", "Healer", "Attacker"])
        XCTAssertEqual(squad.map(\.entryId), ["m0", "m6", "m2"], "Blissey tanks, so Chansey heals; Vaporeon attacks")
        // A boss no attacker hits: the first Attacker in the order.
        let steel = P23.row("2026-10-20", "2026-10-30", .maxMonday, bosses: [P23.boss("registeel", types: ["steel"])])
        let none = HubSquads.maxSquad(candidates: HubSquads.maxCandidates(row: steel, mode: .best, ctx: ctx), placeable: P23.anyone)
        XCTAssertEqual(none.last?.entryId, "m2")
        // Order matters: a lower attacker that hits is preferred to a higher one that does not.
        let ghost = P23.row("2026-10-20", "2026-10-30", .maxMonday, bosses: [P23.boss("gengar", types: ["ghost", "poison"])])   // weak to ghost, dark, ground, psychic
        let g = HubSquads.maxCandidates(row: ghost, mode: .best, ctx: ctx)
        XCTAssertEqual(HubSquads.maxSquad(candidates: g, placeable: P23.anyone).last?.entryId, "m3", "Gengar (ghost) is the only attacker that hits")
        XCTAssertEqual(HubSquads.maxSquad(candidates: [], placeable: P23.anyone).map(\.entryId), [nil, nil, nil])
    }

    func testMaxBuiltNeedsTheDynamaxMarkAndAvailableTakesEveryBuild() {
        let marked = P23.ctx(builds: maxBuilds(), entries: [P23.entry("m0", "blissey", dynamax: true), P23.entry("m2", "vaporeon")], table: maxTable())
        let c = HubSquads.maxCandidates(row: fireBoss, mode: .best, ctx: marked)
        XCTAssertEqual(c.first { $0.entryId == "m0" }?.built, true)
        XCTAssertEqual(c.first { $0.entryId == "m2" }?.built, false, "not marked Dynamax: reads Upgrade available")
        var builds = maxBuilds(); builds[2].powerUp = false
        let avail = HubSquads.maxCandidates(row: fireBoss, mode: .available, ctx: P23.ctx(builds: builds, table: maxTable()))
        XCTAssertTrue(avail.map(\.entryId).contains("m2"), "S1: an evolution to do is still a Max candidate under Available")
    }


    // MARK: Gym

    private func gymTable() -> TierTable {
        P23.table([P23.tierEntry("gym", "Tiers", "S", "blissey"), P23.tierEntry("gym", "Tiers", "S", "snorlax"), P23.tierEntry("gym", "Tiers", "A", "registeel"),
                   P23.tierEntry("gym", "Tiers", "A", "lapras")])
    }
    private func gymFixture() -> HubContext {
        let builds = [P23.build("b1", "blissey", areas: ["Gym"], level: 30),
                      P23.build("s1", "snorlax", areas: ["Gym"], level: 30),
                      P23.build("s2", "snorlax", areas: ["Gym"], built: false, level: 25, targetLevel: 35),
                      P23.build("r1", "registeel", areas: ["Gym"], level: 20, targetLevel: 30),
                      P23.build("l1", "lapras", areas: ["Gym"], level: 20),
                      P23.build("s3", "snorlax", areas: ["Gym"], level: 20, targetLevel: 30),
                      P23.build("b1", "blissey", areas: ["Gym"], score: 1, level: 30),                           // the same copy again
                      P23.build("x1", "snorlax", areas: ["Gym"], powerUp: false, level: 30),                      // an evolution or form change still to do: counts too (S1)
                      P23.build("o1", "pikachu", areas: ["Raids"], level: 30)]                                   // not a Gym build
        let entries = [P23.entry("b1", "blissey", ivs: IVs(atk: 0, def: 10, hp: 10), cp: 100), P23.entry("s1", "snorlax", ivs: IVs(atk: 15, def: 15, hp: 15), cp: 1),
                       P23.entry("s2", "snorlax", ivs: IVs(atk: 5, def: 5, hp: 5), cp: 3000), P23.entry("r1", "registeel", ivs: IVs(atk: 1, def: 1, hp: 1), level: nil),
                       P23.entry("l1", "lapras", ivs: IVs(atk: 1, def: 1, hp: 1), level: 20), P23.entry("s3", "snorlax", ivs: IVs(atk: 15, def: 15, hp: 15), level: nil),
                       P23.entry("x1", "snorlax", ivs: IVs(atk: 15, def: 15, hp: 15)), P23.entry("o1", "pikachu")]
        return P23.ctx(builds: builds, entries: entries, table: gymTable())
    }

    func testBulkIsDefenceTimesFlooredHPWithTheCopysIVs() {
        let m = PogoReader.cpm(30)
        // Blissey: base 169 Defence and 496 HP, IVs 10 and 10, level 30.
        let b = PogoRules.bulk(target: "blissey", ivs: IVs(atk: 0, def: 10, hp: 10), level: 30, gm: P23.gm)
        XCTAssertEqual(b, .known(179 * m * (506 * m).rounded(.down)))
        XCTAssertEqual(PogoRules.bulk(target: "blissey", ivs: IVs(atk: 0, def: 10, hp: 10), level: nil, gm: P23.gm), .levelNotRead, "no level assumed")
        XCTAssertEqual(PogoRules.bulk(target: "blissey", ivs: nil, level: 30, gm: P23.gm), .ivsNotRead)
        XCTAssertEqual(PogoRules.bulk(target: "nope", ivs: IVs(atk: 0, def: 0, hp: 0), level: 30, gm: P23.gm), .unknownSpecies)
        XCTAssertEqual(PogoRules.bulk(target: "blissey", ivs: IVs(atk: 0, def: 0, hp: 0), level: 30.25, gm: P23.gm), .levelNotRead, "a level the table does not have")
        XCTAssertEqual(PogoRules.bulk(target: "blissey", ivs: IVs(atk: 0, def: 0, hp: 0), level: 52, gm: P23.gm), .levelNotRead)
        XCTAssertNotNil(PogoRules.cpm(1)); XCTAssertNotNil(PogoRules.cpm(51)); XCTAssertNil(PogoRules.cpm(0.5))
        // A higher level or better IVs never lowers the figure.
        let low = PogoRules.bulk(target: "snorlax", ivs: IVs(atk: 0, def: 0, hp: 0), level: 20, gm: P23.gm).value!
        let high = PogoRules.bulk(target: "snorlax", ivs: IVs(atk: 0, def: 15, hp: 15), level: 40, gm: P23.gm).value!
        XCTAssertGreaterThan(high, low)
    }

    func testGymOrderIsTierThenBulkAndAnUnreadLevelRanksLastInItsTier() {
        let rows = HubSquads.gymRows(mode: .available, ctx: gymFixture())
        // S: Blissey (bulk about 48k), Snorlax s1 (about 34k) and x1 (the same, so the advisor's order; S1: a build that is not a power-up counts), Snorlax s2 at its
        // target level 35 (a little less), then s3 with no level.
        // A: Lapras (level 20 known) before Registeel (no level), although Registeel's tier is the same.
        XCTAssertEqual(rows.map { $0.build.entryId }, ["b1", "s1", "x1", "s2", "s3", "l1", "r1"])
        XCTAssertEqual(rows.map(\.tier), ["S", "S", "S", "S", "S", "A", "A"])
        XCTAssertEqual(rows.map(\.levelNotRead), [false, false, false, false, true, false, true])
        XCTAssertEqual(rows.map(\.bulk.isKnown), [true, true, true, true, false, true, false])
        XCTAssertEqual(rows[3].level, 35, "an unbuilt row is worked at its target level")
        XCTAssertEqual(rows[1].level, 30, "a built row at the copy's level")
        XCTAssertGreaterThan(rows[0].bulk.value!, rows[1].bulk.value!)
        XCTAssertGreaterThan(rows[1].bulk.value!, rows[3].bulk.value!)
        XCTAssertEqual(rows.map(\.built), [true, true, true, false, true, true, true])
    }

    func testGymOrderIgnoresCPAndBothModesIncludeFormChanges() {
        let ctx = gymFixture()
        XCTAssertEqual(ctx.entry("s2")?.row.cp, 3000, "s2 has the highest CP and still ranks below s1")
        let best = HubSquads.gymRows(mode: .best, ctx: ctx)
        XCTAssertTrue(best.map { $0.build.entryId }.contains("x1"))
        XCTAssertEqual(best.map { $0.build.entryId }.filter { $0 == "b1" }.count, 1, "one row per copy")
    }

    func testGymTiesAndMissingIVsKeepTheAdvisorsOrder() {
        let builds = [P23.build("a", "snorlax", areas: ["Gym"], level: 30), P23.build("b", "snorlax", areas: ["Gym"], level: 30), P23.build("c", "snorlax", areas: ["Gym"], level: 30)]
        let same = IVs(atk: 5, def: 5, hp: 5)
        let ctx = P23.ctx(builds: builds, entries: [P23.entry("a", "snorlax", ivs: same), P23.entry("b", "snorlax", ivs: nil), P23.entry("c", "snorlax", ivs: same)], table: gymTable())
        let rows = HubSquads.gymRows(mode: .best, ctx: ctx)
        XCTAssertEqual(rows.map { $0.build.entryId }, ["a", "c", "b"], "equal bulk: advisor order; unread IVs after")
        XCTAssertEqual(rows.last?.bulk, .ivsNotRead)
        XCTAssertEqual(HubSquads.gymRows(mode: .best, ctx: P23.ctx()), [], "empty box")
    }

    func testTheGymSquadIsSixSlotsFilledInOrder() {
        let rows = HubSquads.gymRows(mode: .available, ctx: gymFixture())
        let squad = HubSquads.gymSquad(rows: rows, placeable: P23.anyone)
        XCTAssertEqual(squad.map(\.entryId), ["b1", "s1", "x1", "s2", "s3", "l1"])
        var slots = HubSquads.defaultGymSlots()
        slots[0].pick = "r1"
        XCTAssertEqual(HubSquads.gymSquad(slots: slots, rows: rows, placeable: P23.anyone).map(\.entryId), ["r1", "b1", "s1", "x1", "s2", "s3"])
        XCTAssertEqual(HubSquads.gymSquad(rows: Array(rows.prefix(2)), placeable: P23.anyone).map(\.entryId), ["b1", "s1", nil, nil, nil, nil])
        XCTAssertEqual(HubSquads.defaultGymSlots().count, 6)
    }


    // MARK: Rocket

    private let machamp = P23.boss("machamp", types: ["fighting"])
    private let rhyperior = P23.boss("rhyperior", types: ["ground", "rock"])
    private let kangaskhan = P23.boss("kangaskhan", types: ["normal"])

    private func rocketBuilds() -> [BoxAdvice.Build] {
        [P23.build("r1", "lucario", areas: ["Raids"], tier: "S", built: false),
         P23.build("r2", "vaporeon", areas: ["Raids"], tier: "A"),
         P23.build("r3", "togekiss", areas: ["Raids"], tier: "S"),
         P23.build("r4", "gyarados", areas: ["Rocket"], tier: "B"),
         P23.build("r5", "snorlax", areas: ["Rocket"], tier: "S"),
         P23.build("r6", "machamp", areas: ["Raids"], tier: "A"),
         P23.build("r7", "medicham", areas: ["Raids"], tier: "B", built: false),
         P23.build("r2", "lapras", areas: ["Rocket"], tier: "S")]               // a second build of copy r2
    }

    func testRocketPickerOrdersByHitsThenBuiltThenRocketThenTier() {
        let ctx = P23.ctx(builds: rocketBuilds())
        let rows = HubSquads.rocketPicker(options: [kangaskhan, rhyperior, machamp], mode: .best, ctx: ctx)
        // Medicham (Fighting and Psychic) hits all three; Gyarados (Water, Flying) two, built and Rocket; Machamp two, built; Lucario two, not built;
        // then the one-hit rows: copy r2's Lapras build (Rocket area) before Togekiss. Snorlax hits none. Copy r2 appears once, as the build that ranks first.
        XCTAssertEqual(rows.map(\.entryId), ["r7", "r4", "r6", "r1", "r2", "r3"])
        XCTAssertEqual(rows.first { $0.entryId == "r2" }?.build.targetId, "lapras")
        XCTAssertEqual(rows.map(\.hits), [3, 2, 2, 2, 1, 1])
        XCTAssertEqual(rows.map(\.slotLine), ["beats all 3", "beats 2 of 3", "beats 2 of 3", "beats 2 of 3", "beats 1 of 3", "beats 1 of 3"])
    }

    func testSlotLinesFollowRule21() {
        XCTAssertNil(HubSquads.slotLine(hits: 1, of: 1), "one option: no beats line")
        XCTAssertEqual(HubSquads.slotLine(hits: 3, of: 3), "beats all 3")
        XCTAssertEqual(HubSquads.slotLine(hits: 1, of: 3), "beats 1 of 3")
        XCTAssertEqual(HubSquads.slotLine(hits: 2, of: 4), "beats 2 of 4")
        XCTAssertNil(HubSquads.slotLine(hits: 0, of: 3))
        let rows = HubSquads.rocketPicker(options: [machamp], mode: .best, ctx: P23.ctx(builds: rocketBuilds()))
        XCTAssertTrue(rows.allSatisfy { $0.slotLine == nil })
    }

    func testPickerRowIconsAreColouredOnlyForTypesThatHit() {
        let rows = HubSquads.rocketPicker(options: [machamp], mode: .best, ctx: P23.ctx(builds: rocketBuilds()))
        let gyarados = rows.first { $0.entryId == "r4" }!
        XCTAssertEqual(gyarados.typeFlags, [.init(type: "water", hits: false), .init(type: "flying", hits: true)], "Flying hits Fighting; Water does not")
        let medicham = rows.first { $0.entryId == "r7" }!
        XCTAssertEqual(medicham.typeFlags, [.init(type: "fighting", hits: false), .init(type: "psychic", hits: true)])
    }

    func testRocketPickerUnderAvailableKeepsFormChanges() {
        var b = rocketBuilds(); b[6].powerUp = false
        let rows = HubSquads.rocketPicker(options: [machamp], mode: .available, ctx: P23.ctx(builds: b))
        XCTAssertTrue(rows.map(\.entryId).contains("r7"), "S1: a form change to do is still a Rocket counter under Available")
        XCTAssertEqual(HubSquads.rocketPicker(options: [machamp], mode: .best, ctx: P23.ctx()), [])
    }

    func testNextBestWhenNothingBeatsTheSlot() {
        let steel = P23.boss("registeel", types: ["steel"])
        let builds = [P23.build("n1", "vaporeon", areas: ["Raids"], tier: "A"), P23.build("n2", "snorlax", areas: ["Rocket"], tier: "B", built: false),
                      P23.build("n3", "togekiss", areas: ["Rocket"], tier: "S"), P23.build("n4", "vaporeon", areas: ["Raids"], tier: "A"),
                      P23.build("n5", "blissey", areas: ["Raids"], tier: "B", built: false), P23.build("n6", "pikachu", areas: ["Gym"], tier: "S")]
        let ctx = P23.ctx(builds: builds)
        XCTAssertTrue(HubSquads.rocketPicker(options: [steel], mode: .best, ctx: ctx).isEmpty, "nothing hits a steel option here")
        let next = HubSquads.rocketNextBest(options: [steel], mode: .best, ctx: ctx)
        // Not weak first (built first, then Rocket, tier): Vaporeon n1 (one per species, n4 dropped), Snorlax (Rocket), Blissey; Togekiss is hit by Steel
        // (Fairy) so it comes after them and the cap of three cuts it.
        XCTAssertEqual(next.map { $0.build.entryId }, ["n1", "n2", "n5"])
        XCTAssertEqual(next.map(\.notWeak), [true, true, true])
        XCTAssertEqual(next.map(\.weakTo), [0, 0, 0])
        let two = HubSquads.rocketNextBest(options: [steel], mode: .best, ctx: P23.ctx(builds: [builds[2]]))
        XCTAssertEqual(two.map(\.weakTo), [1], "weak to the slot: no 'not weak' state")
        XCTAssertFalse(two[0].notWeak)
        XCTAssertEqual(HubSquads.rocketNextBest(options: [steel], mode: .best, ctx: P23.ctx()), [], "an empty box")
        XCTAssertEqual(HubSquads.rocketNextBest(options: [machamp], mode: .best, ctx: P23.ctx(builds: rocketBuilds())), [], "only when nothing beats the slot")
    }

    func testALeadersSquadTakesPicksFirstAndLeavesAnUnbeatableSlotEmpty() {
        let leader = HubData.Leader(name: "Test", since: "2026-01-01", slots: [[machamp], [rhyperior], [kangaskhan]], source: "")
        let builds = [P23.build("a", "togekiss", areas: ["Rocket"], tier: "S"), P23.build("b", "lucario", areas: ["Rocket"], tier: "S"), P23.build("c", "gyarados", areas: ["Rocket"], tier: "A")]
        let ctx = P23.ctx(builds: builds)
        // Slot 1 (Machamp): Togekiss (Fairy and Flying hit Fighting) and Gyarados (Flying). Slot 2 (Rhyperior): Lucario (Fighting, Steel) and Gyarados (Water).
        // Slot 3 (Kangaskhan): Lucario only. Slot 2 takes Lucario first (tier S), so slot 3 has nobody left.
        let auto = HubSquads.rocketSquad(leader: leader, mode: .best, ctx: ctx)
        XCTAssertEqual(auto.map(\.entryId), ["a", "b", nil])
        // The player picks Lucario for slot 3: slot 2 now suggests Gyarados, and slot 2's picker no longer lists Lucario (a chosen pick leaves the list).
        var slots = HubSquads.defaultRocketSlots(); slots[2].pick = "b"
        let chosen = HubSquads.rocketSquad(leader: leader, slots: slots, mode: .best, ctx: ctx)
        XCTAssertEqual(chosen.map(\.entryId), ["a", "c", "b"])
        let picker = HubSquads.rocketPicker(options: [rhyperior], mode: .best, ctx: ctx).map(\.entryId)
        XCTAssertEqual(HubSquads.picker(candidates: picker, excluded: HubSquads.excluded(by: chosen, editing: 1, onlyChosen: true), own: "c").map(\.entryId), ["c"])
        // A suggestion in another slot does not leave the list.
        XCTAssertEqual(HubSquads.excluded(by: auto, editing: 1, onlyChosen: true), [])
    }

    func testGruntCountersAreBuiltFirstOnePerSpeciesUpToEight() {
        // Fighting grunts are hit by Flying, Psychic and Fairy.
        let species = ["togekiss", "gyarados", "charizard", "dragonite", "mewtwo", "medicham", "azumarill", "skarmory", "alakazam", "sylveon", "espeon"]
        var builds = species.enumerated().map { i, s in P23.build("g\(i)", s, areas: i % 3 == 0 ? ["Rocket"] : ["Raids"], tier: ["S", "A", "B"][i % 3], score: Double(100 - i), built: i != 1) }
        builds.append(P23.build("dup", "togekiss", areas: ["Rocket"], tier: "S", score: 1))   // a second Togekiss
        builds.append(P23.build("none", "snorlax", areas: ["Rocket"]))                         // does not hit Fighting
        let counters = HubSquads.gruntCounters(type: "fighting", mode: .best, ctx: P23.ctx(builds: builds))
        XCTAssertFalse(counters.anyAttacker)
        XCTAssertEqual(counters.builds.count, 8, "up to eight")
        XCTAssertEqual(Set(counters.builds.map(\.targetId)).count, 8, "one per species")
        XCTAssertEqual(counters.best?.targetId, "togekiss", "built, Rocket area, tier S, highest score")
        // Built Rocket-area ones first (by score), then built Raids-area ones by tier A then B; the one unbuilt counter (Gyarados) is cut by the cap.
        XCTAssertEqual(counters.builds.map(\.targetId), ["togekiss", "dragonite", "azumarill", "sylveon", "mewtwo", "skarmory", "espeon", "charizard"])
        XCTAssertTrue(counters.builds.allSatisfy { HubTeams.isBuilt($0) })
        let few = HubSquads.gruntCounters(type: "fighting", mode: .best, ctx: P23.ctx(builds: Array(builds.prefix(2))))
        XCTAssertEqual(few.builds.map(\.targetId), ["togekiss", "gyarados"], "an unbuilt counter is listed when there are few")
        // The app's own pick (`HubTeams.gruntCounter`) is the first of the list.
        let pick = HubTeams.gruntCounter(type: "fighting", builds: builds, gm: P23.gm, hub: P23.hub)
        XCTAssertEqual(pick.build?.entryId, counters.best?.entryId)
    }

    func testMixedAndDecoyGruntsTakeAnyStrongAttacker() {
        let c = HubSquads.gruntCounters(type: "", mode: .best, ctx: P23.ctx(builds: rocketBuilds()))
        XCTAssertTrue(c.anyAttacker)
        XCTAssertEqual(c.builds, [])
        XCTAssertNil(c.best)
        XCTAssertEqual(HubSquads.gruntCounters(type: "fighting", mode: .best, ctx: P23.ctx()), .init(anyAttacker: false, builds: []), "an empty box")
    }

    func testBeatenByIsTheTypesThatHitTheGrunt() {
        XCTAssertEqual(HubSquads.beatenBy(gruntType: "fighting", hub: P23.hub), ["flying", "psychic", "fairy"])
        XCTAssertEqual(HubSquads.beatenBy(gruntType: "", hub: P23.hub), [])
        XCTAssertEqual(HubSquads.beatenBy(gruntType: "water", hub: P23.hub), ["electric", "grass"])
    }


    // MARK: PvP

    func testPvpRolesComeFromTheTablesRoleText() {
        XCTAssertEqual(HubSquads.pvpRoles("Safe swap, bulky generalist"), [.safeSwap])
        XCTAssertEqual(HubSquads.pvpRoles("Lead 100, closer 100"), [.lead, .closer])
        XCTAssertEqual(HubSquads.pvpRoles("Switch / generalist"), [.safeSwap])
        XCTAssertEqual(HubSquads.pvpRoles("LEAD"), [.lead])
        XCTAssertEqual(HubSquads.pvpRoles("Consistency 100"), [])
        XCTAssertEqual(HubSquads.pvpRoles(""), [])
        XCTAssertEqual(HubSquads.pvpRoles("Closer, safe swap, lead"), [.lead, .safeSwap, .closer], "always in Lead, Safe swap, Closer order")
    }

    private func leagueTable(closers: Bool = true) -> TierTable {
        var e = [P23.tierEntry("gl", "Tiers", "S", "medicham", role: closers ? "Lead 100, closer 95" : "Lead 100"),
                 P23.tierEntry("gl", "Tiers", "S", "azumarill", role: "Safe swap 97.6"),
                 P23.tierEntry("gl", "Tiers", "A", "registeel", role: "Switch / generalist"),
                 P23.tierEntry("gl", "Tiers", "A", "skarmory", role: "Generalist")]
        if closers { e.append(P23.tierEntry("gl", "Tiers", "B", "lapras", role: "Closer")) }
        return P23.table(e)
    }
    private func leagueRatings(extra: [String: BoxAdvice.LeagueRating] = [:]) -> [String: [String: BoxAdvice.LeagueRating]] {
        var out = [String: [String: BoxAdvice.LeagueRating]]()
        for (i, (s, score)) in [("medicham", 95.0), ("azumarill", 94), ("registeel", 93), ("skarmory", 92), ("lapras", 85), ("gengar", 82)].enumerated() {
            out["c\(i)"] = ["gl": P23.rating([P23.option(s, score: score, ivRank: 10 + i)])]
        }
        for (k, v) in extra { out[k] = ["gl": v] }
        return out
    }

    func testPvpCandidatesCarryTheirRoles() {
        let ctx = P23.ctx(table: leagueTable(), leagues: leagueRatings())
        let c = HubSquads.pvpCandidates(league: "gl", mode: .best, ctx: ctx)
        XCTAssertEqual(c.map(\.candidate.speciesId), ["medicham", "azumarill", "registeel", "skarmory", "lapras", "gengar"])
        XCTAssertEqual(c.map(\.roles), [[.lead, .closer], [.safeSwap], [.safeSwap], [], [.closer], []])
    }

    func testSuggestedPvpSquadPicksByRoleThenBestUnused() {
        let ctx = P23.ctx(table: leagueTable(), leagues: leagueRatings())
        let c = HubSquads.pvpCandidates(league: "gl", mode: .best, ctx: ctx)
        let squad = HubSquads.pvpSquad(candidates: c, placeable: P23.anyone)
        XCTAssertEqual(squad.map(\.role), ["Lead", "Safe swap", "Closer"])
        XCTAssertEqual(squad.map(\.entryId), ["c0", "c1", "c4"], "Lead: Medicham; Safe swap: the best listed (Azumarill); Closer: Medicham is used, so Lapras, not the higher-scoring Registeel")
        XCTAssertEqual(squad.map(\.fallback), [false, false, false])
        // Nothing listed for Closer once Lapras is not a closer: the best unused candidate overall, marked as a fallback.
        let noCloser = HubSquads.pvpSquad(candidates: HubSquads.pvpCandidates(league: "gl", mode: .best, ctx: P23.ctx(table: leagueTable(closers: false), leagues: leagueRatings())), placeable: P23.anyone)
        XCTAssertEqual(noCloser.map(\.entryId), ["c0", "c1", "c2"])
        XCTAssertEqual(noCloser.map(\.fallback), [false, false, true])
    }

    func testPvpWithNoRoleTextFallsBackToTheBestScoring() {
        let ctx = P23.ctx(table: P23.table([]), leagues: leagueRatings())
        let squad = HubSquads.pvpSquad(candidates: HubSquads.pvpCandidates(league: "gl", mode: .best, ctx: ctx), placeable: P23.anyone)
        XCTAssertEqual(squad.map(\.entryId), ["c0", "c1", "c2"])
        XCTAssertEqual(squad.map(\.fallback), [true, true, true])
        XCTAssertEqual(HubSquads.pvpSquad(candidates: [], placeable: P23.anyone).map(\.entryId), [nil, nil, nil], "no candidate")
        XCTAssertEqual(HubSquads.pvpSquad(candidates: Array(HubSquads.pvpCandidates(league: "gl", mode: .best, ctx: ctx).prefix(2)), placeable: P23.anyone).map(\.entryId), ["c0", "c1", nil], "fewer than three")
    }

    func testAPvpPickThatFitsTheRoleStaysAndTheOthersRefill() {
        let ctx = P23.ctx(table: leagueTable(), leagues: leagueRatings())
        let c = HubSquads.pvpCandidates(league: "gl", mode: .best, ctx: ctx)
        var slots = HubSquads.defaultPvpSlots(); slots[1].pick = "c0"      // Medicham as the Safe swap: the player's choice
        let squad = HubSquads.pvpSquad(slots: slots, candidates: c, placeable: P23.anyone)
        XCTAssertEqual(squad.map(\.entryId), ["c1", "c0", "c4"], "no other Lead is listed, so the Lead slot takes the best unused one")
        XCTAssertEqual(squad.map(\.chosen), [false, true, false])
        XCTAssertEqual(squad.map(\.fallback), [true, false, false])
        // Changing that slot's role to Lead: Medicham fits Lead, so the pick stays.
        HubSquads.changeRole(&slots, at: 1, to: "Lead") { HubSquads.fits($0, role: "Lead", in: c) }
        XCTAssertEqual(slots[1].pick, "c0")
        HubSquads.changeRole(&slots, at: 1, to: "Safe swap") { HubSquads.fits($0, role: "Safe swap", in: c) }
        XCTAssertNil(slots[1].pick, "Medicham is no Safe swap in the table")
    }

    func testAvailableTakesTheBestCopyEvenWhenItIsAnEvolution() {
        // Two Medicham copies: the better one's pick is an evolution, the other is itself. S1: both count, the better wins; still one per species.
        var l = leagueRatings()
        l["m1"] = ["gl": P23.rating([P23.option("medicham", isSelf: false, score: 99)])]
        l["m2"] = ["gl": P23.rating([P23.option("medicham", isSelf: true, score: 90)])]
        let ctx = P23.ctx(table: leagueTable(), leagues: l)
        let best = HubSquads.pvpCandidates(league: "gl", mode: .best, ctx: ctx)
        XCTAssertEqual(best.first?.entryId, "m1")
        let available = HubSquads.pvpCandidates(league: "gl", mode: .available, ctx: ctx)
        XCTAssertEqual(available.filter { $0.candidate.speciesId == "medicham" }.map(\.entryId), ["m1"], "the best Medicham copy, evolution or not; never two of one species")
    }

    func testCoverageIsReturnedAndNeverUsedToPick() {
        let ctx = P23.ctx(table: leagueTable(), leagues: leagueRatings())
        let c = HubSquads.pvpCandidates(league: "gl", mode: .best, ctx: ctx)
        let squad = HubSquads.pvpSquad(candidates: c, placeable: P23.anyone)
        let cov = HubSquads.pvpCoverage(of: squad, candidates: c, ctx: ctx)
        XCTAssertEqual(cov.count, cov.types.count)
        // Medicham (Fighting, Psychic), Azumarill (Water, Fairy), Lapras (Water, Ice) hit these types for more than normal damage.
        XCTAssertTrue(cov.types.isSuperset(of: ["normal", "rock", "ice", "dark", "steel", "fighting", "poison", "fire", "ground", "dragon"]))
        XCTAssertFalse(cov.types.contains("water"))
        XCTAssertEqual(HubSquads.pvpCoverage(of: [FilledSlot(role: "Lead", entryId: nil, chosen: false, fallback: false)], candidates: c, ctx: ctx).count, 0, "an empty squad covers nothing")
        // The old coverage-first team still exists for the old screens.
        XCTAssertEqual(HubTeams.suggestedTeam(candidates: c.map(\.candidate), gm: P23.gm, hub: P23.hub).count, 3)
    }

}
