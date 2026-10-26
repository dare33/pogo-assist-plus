import XCTest
@testable import PogoBox
import PogoReader

/// Pass 3's activity-tab rules (CONCEPTS rules 10 to 16), on hand-made boxes, tier tables and rotations.
final class PokemonActivitiesTests: XCTestCase {
    private typealias A = PokemonActivities

    // MARK: rule 10: reach

    func testReachIsTheSpeciesAndTheEvolutionsBelowItBreadthFirst() {
        let gm = P23.gm
        XCTAssertEqual(PogoRules.reach(of: "charmander", gm: gm), ["charmander", "charmeleon", "charizard"])
        XCTAssertEqual(PogoRules.reach(of: "charmeleon", gm: gm), ["charmeleon", "charizard"], "never back up the family")
        XCTAssertEqual(PogoRules.reach(of: "charizard", gm: gm), ["charizard"])
        XCTAssertEqual(PogoRules.reach(of: "vaporeon", gm: gm), ["vaporeon"])
        XCTAssertEqual(PogoRules.reach(of: "kyogre", gm: gm), ["kyogre"], "a one-copy species with no family")
        XCTAssertEqual(PogoRules.reach(of: "eevee", gm: gm).first, "eevee")
        XCTAssertEqual(PogoRules.reach(of: "eevee", gm: gm).count, 1 + gm.byId["eevee"]!.evolutions.filter { gm.byId[$0] != nil }.count)
        XCTAssertEqual(PogoRules.reach(of: "not_a_species", gm: gm), ["not_a_species"], "an unknown species reaches itself")
        XCTAssertEqual(PogoRules.reach(of: "bulbasaur", gm: gm), ["bulbasaur", "ivysaur", "venusaur"])
    }

    // MARK: rule 11: Raids tab

    private func boss(_ id: String, _ types: [String]) -> HubData.Boss { P23.boss(id, types: types) }
    private var raidRows: [HubData.RotationRow] {
        [P23.row("2026-10-20", "2026-10-30", bosses: [boss("charizard", ["fire"])]),
         P23.row("2026-11-05", "2026-11-10", bosses: [boss("golem", ["ground"])]),
         P23.row("2026-10-22", "2026-10-28", bosses: [boss("blastoise", ["water"])]),
         P23.row("2026-11-12", "2026-11-15", bosses: [boss("venusaur", ["grass"])])]
    }
    private var raidTable: TierTable {
        P23.table([P23.tierEntry("raids", "Water", "S", "vaporeon"), P23.tierEntry("raids", "Fire", "A", "flareon"), P23.tierEntry("raids", "Electric", "B", "jolteon"),
                   P23.tierEntry("raids", "Dark", "B", "umbreon", shadow: true), P23.tierEntry("raids", "Tiers", "S", "leafeon")])
    }
    private func raidCtx(extra: [BoxAdvice.Build] = [], rotation: [HubData.RotationRow]? = nil) -> HubContext {
        let builds = [P23.build("ev", "vaporeon", areas: ["Raids"], tier: "S"), P23.build("o1", "flareon", areas: ["Raids"], tier: "A")] + extra
        return P23.ctx(builds: builds, entries: [P23.entry("ev", "eevee"), P23.entry("o1", "flareon")], table: raidTable, rotation: rotation ?? raidRows)
    }

    func testRaidCardsAreOnePerMemberAndAttackingTypeBestTierFirst() {
        let ctx = raidCtx()
        let cards = A.raidCards(copy: ctx.entry("ev")!, ctx: ctx)
        // Umbreon's entry is Shadow. Leafeon's section ("Tiers") is not a type, so it stands for the species' own type, as `typesCounted` reads it.
        XCTAssertEqual(cards.map(\.member.name), ["Vaporeon", "Leafeon", "Flareon", "Jolteon"])
        XCTAssertEqual(cards.map(\.type), ["water", "grass", "fire", "electric"])
        XCTAssertEqual(cards.map(\.tier), ["S", "S", "A", "B"])
        XCTAssertEqual(cards.map(\.role), [.bulky, .bulky, .heavy, .bulky])
        // Water: the fire and ground bosses (the first now, the second coming). Fire: the grass boss. Electric: the water boss.
        XCTAssertEqual(cards[0].counters.map { HubRaidsModel.name($0.entry.row) }, ["Charizard", "Golem"])
        XCTAssertEqual(cards[0].counters.map(\.isNow), [true, false])
        XCTAssertEqual(cards[0].counters.map(\.when), ["now", "in 11 d"])
        XCTAssertEqual(cards.map(\.counterCount), [2, 2, 1, 1])
        XCTAssertEqual(cards[2].counters.map { HubRaidsModel.name($0.entry.row) }, ["Venusaur"])
        XCTAssertEqual(cards[3].counters.map { HubRaidsModel.name($0.entry.row) }, ["Blastoise"])
    }

    func testTheRaidPlanIsThisCopysBuildElseTheBoxsBestForTheType() {
        let ctx = raidCtx()
        let cards = A.raidCards(copy: ctx.entry("ev")!, ctx: ctx)
        guard case .mine(let mine) = cards[0].plan else { return XCTFail("the copy's own Vaporeon build") }
        XCTAssertEqual(mine.build.entryId, "ev"); XCTAssertTrue(mine.built)
        guard case .best(let best, let tier) = cards[2].plan else { return XCTFail("another copy's Flareon") }
        XCTAssertEqual(best.build.entryId, "o1"); XCTAssertEqual(tier, "A"); XCTAssertTrue(best.built)
        XCTAssertEqual(cards[3].plan, .none, "nobody is planned as an Electric attacker")
        // An unbuilt own build reads not built.
        let todo = raidCtx(extra: []).advice.builds.map { b -> BoxAdvice.Build in var v = b; if b.entryId == "ev" { v.steps = [.init(kind: "powerUp", toLevel: 40)] }; return v }
        let ctx2 = P23.ctx(builds: todo, entries: ctx.entries, table: raidTable, rotation: raidRows)
        guard case .mine(let p) = A.raidCards(copy: ctx2.entry("ev")!, ctx: ctx2)[0].plan else { return XCTFail() }
        XCTAssertFalse(p.built)
    }

    /// A copy whose Raids build is a Mega route (Scyther to Mega Scizor) shows that card on the Raids tab, and the Summary agrees; a Shadow copy cannot Mega evolve.
    func testTheRaidsTabListsTheMegaEntriesOfAMemberForANonShadowCopy() {
        var mega = P23.build("sc", "scizor", areas: ["Raids"], tier: "B", built: false, viaMega: true)
        mega.steps = [.init(kind: "evolve", to: "Scizor"), .init(kind: "megaEvolve")]
        let table = P23.table([P23.tierEntry("raids", "Bug", "B", "scizor_mega", mega: true)])
        func ctx(_ shadow: Int?) -> HubContext { P23.ctx(builds: [mega], entries: [P23.entry("sc", "scyther", shadow: shadow)], table: table, rotation: []) }
        let c = ctx(nil)
        let cards = A.raidCards(copy: c.entry("sc")!, ctx: c)
        XCTAssertEqual(cards.map(\.member.id), ["scizor_mega"])
        XCTAssertEqual(cards.map(\.type), ["bug"])
        XCTAssertEqual(cards[0].role, .mega)
        guard case .mine(let plan) = cards[0].plan else { return XCTFail("the copy's own Mega-route build is its plan") }
        XCTAssertEqual(plan.build.targetId, "scizor")
        let raids = A.summary(copy: c.entry("sc")!, ctx: c).first { $0.activity == .raids }!
        XCTAssertEqual(raids.verdict, .planned)
        XCTAssertEqual(raids.lines.first?.plain, "\(cards[0].member.name), B Bug attacker", "the Summary's line is the tab's card")
        let s = ctx(1)
        XCTAssertEqual(A.raidCards(copy: s.entry("sc")!, ctx: s), [], "a Shadow copy cannot Mega evolve")
    }

    func testRaidBestPrefersTierThenBuiltThenTheAdvisorsOrder() {
        let table = P23.table([P23.tierEntry("raids", "Fire", "A", "flareon"), P23.tierEntry("raids", "Fire", "S", "charizard"), P23.tierEntry("raids", "Fire", "A", "arcanine")])
        let builds = [P23.build("a", "flareon", areas: ["Raids"], built: false), P23.build("b", "arcanine", areas: ["Raids"]), P23.build("c", "charizard", areas: ["Raids"], built: false),
                      P23.build("d", "charizard", areas: ["Raids"])]
        let best = A.bestRaidBuilds(ctx: P23.ctx(builds: builds, table: table))
        XCTAssertEqual(best["fire"]?.build.entryId, "d", "tier S beats A; of two S, the built one")
        let none = A.bestRaidBuilds(ctx: P23.ctx(builds: [builds[0], builds[1]], table: table))
        XCTAssertEqual(none["fire"]?.build.entryId, "b", "equal tier: the built one")
        XCTAssertEqual(A.bestRaidBuilds(ctx: P23.ctx(table: table)).count, 0, "an empty box")
    }

    func testAShadowCopyAlsoGetsTheShadowEntries() {
        let shadow = P23.entry("sh", "eevee", shadow: 1)
        let ctx = P23.ctx(entries: [shadow], table: raidTable, rotation: raidRows)
        let cards = A.raidCards(copy: shadow, ctx: ctx)
        XCTAssertEqual(cards.map(\.member.name), ["Vaporeon", "Leafeon", "Flareon", "Jolteon", "Umbreon"])
        XCTAssertEqual(cards.last?.counterCount, 0, "nothing on or coming is weak to Dark attackers")
        XCTAssertEqual(cards.last?.role, .heavy, "a Shadow copy is Heavy")
    }

    func testRaidCountersAreCappedAtSixAndNeedARotation() {
        let many = (0..<8).map { i in P23.row("2026-10-2\(i % 10)", "2026-10-30", bosses: [boss("charizard", ["fire"])]) }
        let ctx = P23.ctx(entries: [P23.entry("v", "vaporeon")], table: raidTable, rotation: many)
        let card = A.raidCards(copy: ctx.entry("v")!, ctx: ctx)
        XCTAssertEqual(card.count, 1, "a Vaporeon reaches only itself")
        XCTAssertEqual(card[0].counters.count, 6)
        XCTAssertEqual(card[0].counterCount, 8)
        let empty = P23.ctx(entries: [P23.entry("v", "vaporeon")], table: raidTable, rotation: [])
        XCTAssertEqual(A.raidCards(copy: empty.entry("v")!, ctx: empty)[0].counters, [])
        XCTAssertEqual(A.raidCards(copy: empty.entry("v")!, ctx: P23.ctx(entries: [P23.entry("v", "vaporeon")])), [], "a species the Raids table does not list")
        let noBoss = P23.ctx(entries: [P23.entry("v", "vaporeon")], table: raidTable, rotation: [P23.row("2026-10-28", "2026-10-28", .raidHour, bosses: [])])
        XCTAssertEqual(A.raidCards(copy: noBoss.entry("v")!, ctx: noBoss)[0].counterCount, 0, "a Raid Hour has no boss to counter")
    }

    // MARK: rule 12: Gym tab

    private var gymTable: TierTable { P23.table([P23.tierEntry("gym", "Tiers", "S", "blissey"), P23.tierEntry("gym", "Tiers", "B", "chansey")]) }
    private func gymCtx(copy: BoxEntry, topBuild: Bool = true, extra: [BoxAdvice.Build] = []) -> HubContext {
        let top = P23.entry("t1", "blissey", ivs: IVs(atk: 15, def: 15, hp: 15), level: 30)
        return P23.ctx(builds: (topBuild ? [P23.build("t1", "blissey", areas: ["Gym"], level: 30)] : []) + extra, entries: [top, copy], table: gymTable)
    }

    func testGymCardsShowBulkAgainstTheTopDefender() {
        let copy = P23.entry("ch", "chansey", ivs: IVs(atk: 10, def: 10, hp: 10), level: 30)
        let ctx = gymCtx(copy: copy)
        let top = A.topDefender(ctx: ctx)
        XCTAssertEqual(top?.name, "Blissey")
        let cards = A.gymCards(copy: copy, ctx: ctx, top: top)
        XCTAssertEqual(cards.map(\.member.name), ["Blissey", "Chansey"], "tier S before B")
        XCTAssertEqual(cards.map(\.share), [97, 73], "48,460 and 36,654 of 50,218")
        XCTAssertEqual(cards.map(\.barFraction), [0.97, 0.73])
        XCTAssertEqual(cards.map(\.isTop), [false, false], "97% is not the top")
        XCTAssertEqual(cards.map(\.tier), ["S", "B"])
        XCTAssertEqual(cards[0].bulk, PogoRules.bulk(target: "blissey", ivs: IVs(atk: 10, def: 10, hp: 10), level: 30, gm: P23.gm), "the copy's own IVs at its current level")
    }

    func testTheTopDefendersOwnCopyIsTheTop() {
        let top = P23.entry("t1", "blissey", ivs: IVs(atk: 15, def: 15, hp: 15), level: 30)
        let ctx = gymCtx(copy: top)
        let cards = A.gymCards(copy: top, ctx: ctx, top: A.topDefender(ctx: ctx))
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].share, 100)
        XCTAssertTrue(cards[0].isTop)
        XCTAssertEqual(cards[0].barFraction, 1)
        XCTAssertEqual(cards[0].plan?.built, true)
    }

    func testAnUnreadLevelOrNoTopDefenderGivesNoShare() {
        let noLevel = P23.entry("ch", "chansey", ivs: IVs(atk: 10, def: 10, hp: 10), level: nil)
        let ctx = gymCtx(copy: noLevel)
        let cards = A.gymCards(copy: noLevel, ctx: ctx, top: A.topDefender(ctx: ctx))
        XCTAssertEqual(cards.map(\.bulk), [.levelNotRead, .levelNotRead])
        XCTAssertEqual(cards.map(\.share), [nil, nil])
        XCTAssertEqual(cards.map(\.barFraction), [nil, nil])
        XCTAssertEqual(cards.map(\.member.name), ["Blissey", "Chansey"], "unknown bulks keep the table's tier order")
        let read = P23.entry("ch", "chansey", ivs: IVs(atk: 10, def: 10, hp: 10), level: 30)
        let none = gymCtx(copy: read, topBuild: false)
        XCTAssertNil(A.topDefender(ctx: none))
        let cards2 = A.gymCards(copy: read, ctx: none, top: nil)
        XCTAssertEqual(cards2.map(\.share), [nil, nil], "no Gym build in the box: nothing to compare with")
        XCTAssertTrue(cards2.allSatisfy { $0.bulk.isKnown && !$0.isTop })
        let noIVs = P23.entry("ch", "chansey", ivs: nil, level: 30)
        XCTAssertEqual(A.gymCards(copy: noIVs, ctx: gymCtx(copy: noIVs), top: nil)[0].bulk, .ivsNotRead)
        XCTAssertEqual(A.gymCards(copy: read, ctx: P23.ctx(entries: [read]), top: nil), [], "a species the Gym table does not list")
    }

    func testTheYardstickSkipsAFirstDefenderWhoseBulkIsNotWorkedOut() {
        // The tier S Blissey has no level read, so it ranks first but has no figure; the B-tier Chansey after it does.
        let a = P23.entry("t1", "blissey", ivs: IVs(atk: 1, def: 1, hp: 1), level: nil), b = P23.entry("t2", "chansey", ivs: IVs(atk: 1, def: 1, hp: 1), level: 30)
        let ctx = P23.ctx(builds: [P23.build("t1", "blissey", areas: ["Gym"], level: nil), P23.build("t2", "chansey", areas: ["Gym"], level: 30)], entries: [a, b], table: gymTable)
        XCTAssertEqual(HubSquads.gymRows(mode: .available, ctx: ctx).map { $0.build.entryId }, ["t1", "t2"])
        XCTAssertEqual(A.topDefender(ctx: ctx)?.build.entryId, "t2")
    }

    // MARK: rule 13: Rocket tab

    private func rocketCtx(builds: [BoxAdvice.Build] = [], copy: BoxEntry, grunts: [String] = ["grass", "fighting", "water", ""]) -> HubContext {
        P23.ctx(builds: builds, entries: [copy], table: P23.table([P23.tierEntry("rocket", "Attacker tiers", "S", "charizard")])) { h in
            h.grunts = grunts.map { HubData.Grunt(type: $0, quote: "", label: $0.isEmpty ? "Mixed team" : "") }
            h.leaders = [HubData.Leader(name: "L", since: "2026-01-01", slots: [
                [HubData.Boss(name: "Shadow Alpha", speciesId: "alpha", types: ["grass"], shadow: nil), HubData.Boss(name: "Beta", speciesId: "beta", types: ["steel"], shadow: nil)],
                [HubData.Boss(name: "Gamma", speciesId: "gamma", types: ["water"], shadow: nil)],
                [HubData.Boss(name: "Delta", speciesId: "delta", types: ["rock", "ground"], shadow: nil)]], source: "")]
        }
    }

    func testRocketCardsBeatGruntTypesAndLeaderOptionsByTheMembersOwnTypes() {
        let copy = P23.entry("cm", "charmander")
        let ctx = rocketCtx(copy: copy)
        let cards = A.rocketCards(copy: copy, ctx: ctx)
        XCTAssertEqual(cards.map(\.member.name), ["Charizard", "Charmeleon", "Charmander"], "most grunt types first, then most leader options, then the later evolution")
        XCTAssertEqual(cards[0].gruntTypes, ["grass", "fighting"], "Fire hits Grass and Flying hits Fighting; the Mixed grunt has no type")
        XCTAssertEqual(cards[2].gruntTypes, ["grass"])
        // Fire hits Grass and Steel in slot 1; nothing of the Fire and Flying pair hits Water or Rock/Ground.
        XCTAssertEqual(cards[0].leaderSlots, [A.LeaderSlotBeat(leader: "L", slot: 1, beats: ["Alpha", "Beta"], of: 2)], "\"Shadow \" is dropped from the name")
        XCTAssertNil(cards[0].plan)
        XCTAssertEqual(cards[0].tier, "S"); XCTAssertNil(cards[1].tier)
    }

    func testRocketShowsUpToFourMembersAndNoneWhenNoTypeHits() {
        let eevee = P23.entry("ev", "eevee")
        let cards = A.rocketCards(copy: eevee, ctx: P23.ctx(entries: [eevee]))
        XCTAssertLessThanOrEqual(cards.count, 4)
        XCTAssertEqual(cards.map(\.gruntTypes.count), cards.map(\.gruntTypes.count).sorted(by: >))
        XCTAssertFalse(cards.map(\.member.name).contains("Eevee"), "a Normal type hits nothing")
        let snorlax = P23.entry("sn", "snorlax")
        XCTAssertEqual(A.rocketCards(copy: snorlax, ctx: P23.ctx(entries: [snorlax])), [])
        XCTAssertEqual(A.rocketCards(copy: snorlax, ctx: rocketCtx(copy: snorlax, grunts: [])), [], "no grunts")
    }

    // MARK: rule 14: Max tab

    private var maxTable: TierTable {
        P23.table([P23.tierEntry("max", "Tanks and healers", "S", "blissey", role: "Tank and healer"), P23.tierEntry("max", "Tanks and healers", "B", "chansey", role: "Healer"),
                   P23.tierEntry("max", "Attackers", "S", "vaporeon"), P23.tierEntry("max", "Attackers", "A", "vaporeon", max: true, name: "Gigantamax Vaporeon")])
    }
    private var maxRows: [HubData.RotationRow] {
        [P23.row("2026-10-20", "2026-10-30", .maxMonday, bosses: [boss("charizard", ["fire"])]),
         P23.row("2026-11-05", "2026-11-05", .maxMonday, bosses: [boss("venusaur", ["grass"])]),
         P23.row("2026-11-10", "2026-11-10", .maxMonday, bosses: [boss("golem", ["rock"])]),
         P23.row("2026-11-16", "2026-11-23", .maxEvent, bosses: [])]
    }

    func testMaxCardsListTheMembersTheMaxTableListsAndNeedDynamax() {
        let copy = P23.entry("ch", "chansey", dynamax: nil)
        let ctx = P23.ctx(builds: [P23.build("ch", "blissey", areas: ["Max"])], entries: [copy], table: maxTable, rotation: maxRows)
        let cards = A.maxCards(copy: copy, ctx: ctx).cards
        XCTAssertEqual(cards.map(\.member.name), ["Chansey", "Blissey"])
        XCTAssertEqual(cards.map(\.tier), ["B", "S"])
        XCTAssertEqual(cards.map(\.roleText), ["Healer", "Tank and healer"])
        XCTAssertEqual(cards.map(\.roles), [[.healer], [.tank, .healer]])
        XCTAssertEqual(cards.map(\.needsDynamax), [true, true])
        XCTAssertNil(cards[0].plan)
        XCTAssertEqual(cards[1].plan?.built, false, "planned, but not built until the copy is marked Dynamax")
        var marked = copy; marked.row.dynamax = true
        let ctx2 = P23.ctx(builds: [P23.build("ch", "blissey", areas: ["Max"])], entries: [marked], table: maxTable, rotation: maxRows)
        let c2 = A.maxCards(copy: marked, ctx: ctx2).cards
        XCTAssertEqual(c2.map(\.needsDynamax), [false, false])
        XCTAssertEqual(c2[1].plan?.built, true)
        var off = copy; off.row.dynamax = false
        XCTAssertEqual(A.maxCards(copy: off, ctx: ctx).cards.map(\.needsDynamax), [true, true], "marked off: still needs it")
    }

    func testMaxBattlesAreTheOnesTheMembersTypesHit() {
        let copy = P23.entry("v", "vaporeon")
        let ctx = P23.ctx(entries: [copy], table: maxTable, rotation: maxRows)
        let m = A.maxCards(copy: copy, ctx: ctx)
        XCTAssertEqual(m.cards.count, 1, "the Gigantamax entry is not used")
        XCTAssertEqual(m.battles.map { HubRaidsModel.name($0.row.entry.row) }, ["Charizard", "Golem"], "Water hits Fire and Rock, not Grass; the Dynamax Trails row has no boss")
        XCTAssertEqual(m.battles.map(\.by), [["Vaporeon"], ["Vaporeon"]])
        XCTAssertEqual(m.battles.map(\.row.isNow), [true, false])
        let normal = P23.entry("sn", "snorlax")
        XCTAssertEqual(A.maxCards(copy: normal, ctx: P23.ctx(entries: [normal], table: maxTable, rotation: maxRows)).battles, [], "a Normal type hits nothing")
        let none = A.maxCards(copy: normal, ctx: P23.ctx(entries: [normal]))
        XCTAssertTrue(none.cards.isEmpty)
    }

    // MARK: rule 15: verdicts

    func testVerdictWords() {
        XCTAssertEqual([A.Verdict.fullStrength, .planned, .spare, .option, .notPicked, .needsDynamax, .notUsed].map(\.text),
                       ["FULL STRENGTH", "PLANNED", "SPARE", "OPTION", "NOT PICKED", "NEEDS DYNAMAX", "NOT USED"])
        XCTAssertEqual(A.Verdict.beatsGrunts(1).text, "BEATS 1 GRUNT")
        XCTAssertEqual(A.Verdict.beatsGrunts(4).text, "BEATS 4 GRUNTS")
        // The app's worth words are Top, Good and Weak; the design's Strong, OK and Weak are not used.
        XCTAssertEqual([A.Verdict.pvp(.strong), .pvp(.ok), .pvp(.weak)].map(\.text), ["TOP", "GOOD", "WEAK"])
        XCTAssertEqual([A.Verdict.fullStrength, .planned, .spare, .pvp(.strong), .pvp(.weak), .beatsGrunts(2)].map(\.tone), [.positive, .action, .neutral, .positive, .neutral, .positive])
        XCTAssertEqual(A.Tab.allCases.map(\.title), ["Summary", "PvP", "Raids", "Gym", "Rocket", "Max"])
        XCTAssertEqual(A.Activity.allCases.map(\.rawValue), ["pvp", "raids", "gym", "rocket", "max"], "Summary's rows start with PvP")
    }

    private func row(_ rows: [A.SummaryRow], _ a: A.Activity) -> A.SummaryRow { rows.first { $0.activity == a }! }

    func testRaidsVerdictsAndLines() {
        let ev = P23.entry("ev", "eevee")
        func rows(_ builds: [BoxAdvice.Build], table: TierTable? = nil, rotation: [HubData.RotationRow]? = nil) -> A.SummaryRow {
            let ctx = P23.ctx(builds: builds, entries: [ev], table: table ?? raidTable, rotation: rotation ?? raidRows)
            return row(A.summary(copy: ev, ctx: ctx), .raids)
        }
        let other = P23.build("o1", "vaporeon", areas: ["Raids"])
        // The copy's own build: planned with work left, full strength when done.
        let planned = rows([P23.build("ev", "vaporeon", areas: ["Raids"], built: false)])
        XCTAssertEqual(planned.verdict, .planned)
        XCTAssertEqual(planned.lines.map(\.plain), ["Vaporeon, S Water attacker", "Counters Charizard now +1 more"])
        guard case .upgrade(_, let cost, let label) = planned.mark else { return XCTFail("an unbuilt build offers the upgrade") }
        XCTAssertEqual(cost.currency, .free); XCTAssertEqual(label, "Upgrade available: power up to level 40")
        XCTAssertEqual(rows([P23.build("ev", "vaporeon", areas: ["Raids"])]).verdict, .fullStrength)
        XCTAssertEqual(rows([P23.build("ev", "vaporeon", areas: ["Raids"])]).mark, .fullStrength)
        // No build of its own: SPARE when another copy is the box's best for the type, OPTION when nobody is.
        XCTAssertEqual(rows([other]).verdict, .spare)
        XCTAssertEqual(rows([]).verdict, .option)
        XCTAssertEqual(rows([]).mark, A.Mark.none)
        // Not in the table at all.
        let none = rows([], table: P23.table([]))
        XCTAssertEqual(none.verdict, .notUsed); XCTAssertEqual(none.lines.map(\.plain), ["Not in our raid tables"])
        // Nothing on or coming needs it.
        XCTAssertEqual(rows([], rotation: []).lines.map(\.plain), ["Vaporeon, S Water attacker", "No raid on or coming needs it"])
    }

    func testGymVerdictsAndLines() {
        let copy = P23.entry("ch", "chansey", ivs: IVs(atk: 10, def: 10, hp: 10), level: 30)
        let ctx = gymCtx(copy: copy)
        let g = row(A.summary(copy: copy, ctx: ctx), .gym)
        XCTAssertEqual(g.verdict, .notPicked)
        XCTAssertEqual(g.lines.map(\.plain), ["As Blissey, bulk 48k", "97% of your top defender, Blissey"])
        let top = P23.entry("t1", "blissey", ivs: IVs(atk: 15, def: 15, hp: 15), level: 30)
        let t = row(A.summary(copy: top, ctx: gymCtx(copy: top)), .gym)
        XCTAssertEqual(t.verdict, .fullStrength)
        XCTAssertEqual(t.lines.map(\.plain), ["As Blissey, bulk 50k", "Your top defender"])
        let unread = P23.entry("ch", "chansey", ivs: IVs(atk: 10, def: 10, hp: 10), level: nil)
        XCTAssertEqual(row(A.summary(copy: unread, ctx: gymCtx(copy: unread)), .gym).lines.map(\.plain), ["As Blissey, level not read"], "no bulk, so no share")
        let unplanned = gymCtx(copy: copy, extra: [P23.build("ch", "blissey", areas: ["Gym"], built: false, level: 30, targetLevel: 35)])
        XCTAssertEqual(row(A.summary(copy: copy, ctx: unplanned), .gym).verdict, .planned)
        let eevee = P23.entry("ev", "eevee")
        let nothing = row(A.summary(copy: eevee, ctx: P23.ctx(entries: [eevee], table: gymTable)), .gym)
        XCTAssertEqual(nothing.verdict, .notUsed); XCTAssertEqual(nothing.lines.map(\.plain), ["Not in our gym table"])
    }

    func testRocketVerdictsAndLines() {
        let cm = P23.entry("cm", "charmander")
        let r = row(A.summary(copy: cm, ctx: rocketCtx(copy: cm)), .rocket)
        XCTAssertEqual(r.verdict, .beatsGrunts(2))
        XCTAssertEqual(r.lines, [A.Line(lead: nil, text: "As Charizard", score: nil, icons: ["grass", "fighting"])])
        // The member with a Rocket build is the one shown, and the build's state is the verdict.
        let planned = rocketCtx(builds: [P23.build("cm", "charmeleon", areas: ["Rocket"], built: false)], copy: cm)
        let p = row(A.summary(copy: cm, ctx: planned), .rocket)
        XCTAssertEqual(p.verdict, .planned)
        XCTAssertEqual(p.lines.map(\.plain), ["As Charmeleon"])
        // A tie on grunt types goes to the later evolution; one grunt type reads in the singular.
        let one = row(A.summary(copy: cm, ctx: rocketCtx(copy: cm, grunts: ["grass"])), .rocket)
        XCTAssertEqual(one.verdict, .beatsGrunts(1)); XCTAssertEqual(one.verdict.text, "BEATS 1 GRUNT")
        XCTAssertEqual(one.lines.map(\.plain), ["As Charizard"])
        let sn = P23.entry("sn", "snorlax")
        let none = row(A.summary(copy: sn, ctx: rocketCtx(copy: sn)), .rocket)
        XCTAssertEqual(none.verdict, .notUsed); XCTAssertEqual(none.lines.map(\.plain), ["No type advantage on any grunt"])
    }

    func testMaxVerdictsAndLines() {
        func summary(dynamax: Bool?, builds: [BoxAdvice.Build], species: String = "chansey", table: TierTable? = nil) -> A.SummaryRow {
            let copy = P23.entry("ch", species, dynamax: dynamax)
            return row(A.summary(copy: copy, ctx: P23.ctx(builds: builds, entries: [copy], table: table ?? maxTable, rotation: maxRows)), .max)
        }
        let blissey = P23.build("ch", "blissey", areas: ["Max"])
        XCTAssertEqual(summary(dynamax: nil, builds: [blissey]).verdict, .needsDynamax, "listed, not marked Dynamax: even with a build")
        XCTAssertEqual(summary(dynamax: false, builds: []).verdict, .needsDynamax)
        XCTAssertEqual(summary(dynamax: true, builds: []).verdict, .option)
        XCTAssertEqual(summary(dynamax: true, builds: [blissey]).verdict, .fullStrength)
        XCTAssertEqual(summary(dynamax: true, builds: [P23.build("ch", "blissey", areas: ["Max"], built: false)]).verdict, .planned)
        XCTAssertEqual(summary(dynamax: nil, builds: []).lines.map(\.plain), ["Chansey, B tier", "Healer"])
        // A member whose types hit a Max battle on now adds that line.
        let v = summary(dynamax: true, builds: [], species: "vaporeon")
        XCTAssertEqual(v.lines.map(\.plain), ["Vaporeon, S tier", "Attackers", "Hits Charizard now"])
        // Not in the table: the first battle its types hit, else nothing more.
        let off = summary(dynamax: true, builds: [], species: "vaporeon", table: P23.table([]))
        XCTAssertEqual(off.verdict, .notUsed)
        XCTAssertEqual(off.lines.map(\.plain), ["Not in our Max table", "Its types hit Charizard now"])
        XCTAssertEqual(summary(dynamax: true, builds: [], species: "snorlax", table: P23.table([])).lines.map(\.plain), ["Not in our Max table"])
    }

    // MARK: rules 15 and 16: PvP

    private func pvp(_ ratings: [String: BoxAdvice.LeagueRating], builds: [BoxAdvice.Build] = []) -> A.SummaryRow {
        let copy = P23.entry("ev", "eevee")
        return row(A.summary(copy: copy, ctx: P23.ctx(builds: builds, entries: [copy], leagues: ["ev": ratings])), .pvp)
    }

    func testPvpLinesAreOneLeaguePerLineAndTheVerdictIsTheBestLeaguesTag() {
        let r = pvp(["gl": P23.rating([P23.option("eevee", score: 54.9)]),
                     "ul": P23.rating([P23.option("eevee", score: 80, overCap: true)]),
                     "ml": P23.rating([P23.option("pidgey", score: 95)])])
        XCTAssertEqual(r.lines.map(\.plain), ["GL Eevee 54.9", "UL over the cap", "ML Pidgey 95.0"])
        XCTAssertEqual(r.lines.map(\.lead), ["GL", "UL", "ML"])
        XCTAssertEqual(r.lines.map(\.score), ["54.9", nil, "95.0"])
        XCTAssertEqual(r.verdict, .pvp(.strong))
        XCTAssertEqual(r.verdict.text, "TOP")
        XCTAssertEqual(r.mark, A.Mark.none)
    }

    func testPvpVerdictOrdersTheTagsAndFallsBackToTheScoreOnATie() {
        XCTAssertEqual(pvp(["gl": P23.rating([P23.option("eevee", score: 54.9)])]).verdict, .pvp(.weak), "weak is still shown, not NOT USED")
        XCTAssertEqual(pvp(["gl": P23.rating([P23.option("eevee", score: 54.9)]), "ul": P23.rating([P23.option("rattata", score: 89)])]).verdict, .pvp(.ok), "B tier with a good roll")
        XCTAssertEqual(pvp(["gl": P23.rating([P23.option("rattata", score: 89)]), "ml": P23.rating([P23.option("pidgey", score: 93)])]).verdict, .pvp(.strong))
        let allOver = pvp(["gl": P23.rating([P23.option("eevee", score: 80, overCap: true)])])
        XCTAssertEqual(allOver.verdict, .notUsed, "no league fits")
        XCTAssertEqual(allOver.lines.map(\.plain), ["GL over the cap"])
        XCTAssertEqual(pvp([:]).verdict, .notUsed)
        XCTAssertEqual(pvp([:]).lines, [])
    }

    func testPvpBuildsDecideFullStrengthOrPlanned() {
        let ratings = ["gl": P23.rating([P23.option("eevee", score: 54.9)])]
        XCTAssertEqual(pvp(ratings, builds: [P23.build("ev", "vaporeon", areas: ["GL"], built: false)]).verdict, .planned)
        XCTAssertEqual(pvp(ratings, builds: [P23.build("ev", "vaporeon", areas: ["GL"])]).verdict, .fullStrength)
        XCTAssertEqual(pvp(ratings, builds: [P23.build("ev", "vaporeon", areas: ["GL"]), P23.build("ev", "umbreon", areas: ["UL"], built: false)]).verdict, .planned, "one still to do")
        XCTAssertEqual(pvp(ratings, builds: [P23.build("other", "vaporeon", areas: ["GL"], built: false)]).verdict, .pvp(.weak), "another copy's build is not this copy's")
    }

    // MARK: rule 16: names

    func testABossesBracketedFormIsDroppedUnlessTwoBossesShareTheName() {
        func r(_ names: [String]) -> HubData.RotationRow { P23.row("2026-10-20", "2026-10-30", bosses: names.map { HubData.Boss(name: $0, speciesId: $0, types: ["normal"], shadow: nil) }) }
        let origin = r(["Giratina (Origin)"]), altered = r(["Giratina (Altered)"]), palkia = r(["Palkia"])
        XCTAssertEqual(A.shortName(origin, among: [origin, palkia]), "Giratina")
        XCTAssertEqual(A.shortName(origin, among: [origin, altered]), "Giratina (Origin)", "two Giratinas: the form tells them apart")
        XCTAssertEqual(A.shortName(altered, among: [origin, altered]), "Giratina (Altered)")
        XCTAssertEqual(A.shortName(r(["Mega Charizard X", "Mega Charizard Y"]), among: []), "Mega Charizard X · Mega Charizard Y")
        XCTAssertEqual(A.shortName(r(["Deoxys", "Deoxys (Speed)", "Deoxys (Attack)", "Deoxys (Defense)"]), among: []), "Deoxys · Deoxys (Speed) · Deoxys (Attack) · Deoxys (Defense)", "four formes in one row tell each other apart")
        XCTAssertEqual(A.shortName(r(["Shadow Landorus (Incarnate)"]), among: []), "Shadow Landorus")
        XCTAssertEqual(A.shortName(P23.row("2026-10-28", "2026-10-28", .raidHour, title: "Raid Hour", bosses: []), among: []), "Raid Hour")
    }
}
