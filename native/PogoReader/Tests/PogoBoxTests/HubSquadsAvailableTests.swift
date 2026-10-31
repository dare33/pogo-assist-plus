import XCTest
@testable import PogoBox
import PogoReader

/// S1 (31 Oct 2026 eyeball check) and the manager's rulings after its review: Available is the app's suggested squad from the box as it is now. Every slot is filled with the
/// strongest Pokémon the player owns for it, whatever upgrade it needs. A copy is judged twice: as the plain Pokémon (every slot but the Mega slot) and, when it is a Mega
/// candidate, on its Mega build (the Mega slot only). Each role's own slots fill first, then the empty slots take another role's Pokémon.
final class HubSquadsAvailableTests: XCTestCase {
    private let giratina = P23.row("2026-10-28", "2026-11-03", bosses: [P23.boss("giratina_origin", types: ["ghost", "dragon"])])

    private func table() -> TierTable {
        P23.table([P23.tierEntry("raids", "Ice", "S", "abomasnow_mega", mega: true), P23.tierEntry("raids", "Ice", "A", "mamoswine"),
                   P23.tierEntry("raids", "Ghost", "S", "gengar_mega", mega: true), P23.tierEntry("raids", "Ghost", "A", "chandelure"),
                   P23.tierEntry("raids", "Dragon", "A", "garchomp"),
                   P23.tierEntry("raids", "Dark", "A", "hydreigon"), P23.tierEntry("raids", "Dark", "A", "weavile"), P23.tierEntry("raids", "Dark", "B", "umbreon")])
    }

    private func steps(_ kinds: String...) -> [BoxAdvice.Build.Step] { kinds.map { $0 == "powerUp" ? .init(kind: $0, toLevel: 40, areas: ["raids"]) : .init(kind: $0) } }

    /// A box like Greg's: one Umbreon that only needs power-up, the rest evolutions or Megas still to do. The Gastly is not Mega-capable yet; its build ends in Mega Gengar.
    private func box() -> (builds: [BoxAdvice.Build], entries: [BoxEntry]) {
        let builds = [
            P23.build("um", "umbreon", areas: ["Raids"], built: false),
            P23.build("ab", "abomasnow", areas: ["Raids"], built: false, powerUp: false, viaMega: true, steps: steps("megaEvolve", "powerUp")),
            P23.build("ge", "gengar", areas: ["Raids"], built: false, powerUp: false, viaMega: true, steps: steps("evolve", "megaEvolve", "powerUp")),
            P23.build("sw", "mamoswine", areas: ["Raids"], built: false, powerUp: false),
            P23.build("zw", "hydreigon", areas: ["Raids"], built: false, powerUp: false),
            P23.build("gb", "garchomp", areas: ["Raids"], built: false, powerUp: false),
            P23.build("sn", "weavile", areas: ["Raids"], built: false, powerUp: false),
            P23.build("lm", "chandelure", areas: ["Raids"], built: false, powerUp: false),
        ]
        let entries = [P23.entry("um", "umbreon"), P23.entry("ab", "abomasnow"), P23.entry("ge", "gastly"), P23.entry("sw", "swinub"), P23.entry("zw", "zweilous"),
                       P23.entry("gb", "gabite"), P23.entry("sn", "sneasel"), P23.entry("lm", "lampent")]
        return (builds, entries)
    }

    private func squad(_ c: HubContext, slots: [SquadSlot] = HubSquads.defaultRaidSlots(), fillAnyRole: Bool = true) -> [FilledSlot] {
        HubSquads.raidSquad(slots: slots, candidates: HubSquads.raidCandidates(row: giratina, mode: .available, ctx: c), fillAnyRole: fillAnyRole,
                            placeable: HubSquads.placeable(screen: .raids, mode: .available, ctx: c))
    }

    // MARK: Greg's case

    func testGiratinaOriginFillsEverySlotNotOne() {
        let b = box()
        let c = P23.ctx(builds: b.builds, entries: b.entries, table: table())
        let slots = squad(c)
        XCTAssertTrue(slots.allSatisfy { $0.entryId != nil }, "every slot filled: \(slots.map(\.entryId))")
        XCTAssertEqual(Set(slots.compactMap(\.entryId)).count, 6, "one copy per squad")
        // The Mega slot: the best Mega view, Abomasnow (Ice S) before the Gastly (Ghost S) by the advisor's order. Each role's own slots fill before any fallback:
        // three Heavy hitters, the one Bulky hitter, then the last Bulky slot takes the strongest Heavy left (Weavile).
        XCTAssertEqual(slots.map(\.entryId), ["ab", "sw", "zw", "gb", "um", "sn"])
        XCTAssertEqual(slots.map(\.fallback), [false, false, false, false, false, true])
    }

    func testAMegaCandidateAsAPlainPokemonRanksBelowEveryListedCounter() {
        let b = box()
        let c = P23.ctx(builds: b.builds, entries: b.entries, table: table())
        let cands = HubSquads.raidCandidates(row: giratina, mode: .available, ctx: c)
        let ge = try! XCTUnwrap(cands.first { $0.entryId == "ge" })
        XCTAssertEqual(ge.tier, "", "plain Gengar is not listed against Giratina's weak types")
        XCTAssertEqual(ge.role, .heavy)
        XCTAssertEqual(ge.mega?.tier, "S", "its Mega build is")
        let order = cands.map(\.entryId)
        XCTAssertGreaterThan(order.firstIndex(of: "ge")!, order.firstIndex(of: "lm")!, "below an A-tier Heavy hitter")
        XCTAssertGreaterThan(order.firstIndex(of: "ge")!, order.firstIndex(of: "um")!, "and below the B-tier Umbreon")
        // In a fallback slot the Gastly is the plain Gengar: no Mega Evolve step, no Mega role.
        XCTAssertFalse(ge.build.viaMega)
        XCTAssertFalse((ge.build.steps ?? []).contains { $0.kind == "megaEvolve" })
        XCTAssertTrue(ge.mega!.build.viaMega)
    }

    func testAMegaCapableCopyInAPlainSlotIsTieredAndCostedAsPlain() {
        // Abomasnow: Mega Abomasnow is S, plain Abomasnow B. Its build has Mega Evolve and a power up still to do.
        let tbl = P23.table([P23.tierEntry("raids", "Ice", "S", "abomasnow_mega", mega: true), P23.tierEntry("raids", "Ice", "B", "abomasnow")])
        let ice = giratina
        func cand(_ s: [BoxAdvice.Build.Step], dust: Int) -> HubSquads.RaidCandidate {
            let c = P23.ctx(builds: [P23.build("ab", "abomasnow", areas: ["Raids"], built: false, powerUp: false, viaMega: true, dust: dust, steps: s)], entries: [P23.entry("ab", "abomasnow")], table: tbl)
            return HubSquads.raidCandidates(row: ice, mode: .available, ctx: c)[0]
        }
        let both = cand(steps("megaEvolve", "powerUp"), dust: 9000)
        XCTAssertEqual(both.tier, "B"); XCTAssertEqual(both.mega?.tier, "S")
        XCTAssertEqual(both.build.dust, 9000, "the plain cost is the build's cost: Mega Evolve costs no dust")
        XCTAssertFalse(both.built); XCTAssertEqual(both.build.action, "Power up to level 40 (Raids)")
        // Only Mega Evolve left: as a plain Pokémon it is at Full strength; on its Mega build it is not, and the Mega slot never shows it as ready.
        let onlyMega = cand(steps("megaEvolve"), dust: 0)
        XCTAssertTrue(onlyMega.built)
        XCTAssertEqual(onlyMega.mega?.built, false)
        XCTAssertTrue(HubModel.needsSomething(onlyMega.mega!.build))
        XCTAssertFalse(HubModel.needsSomething(onlyMega.build))
    }

    // MARK: the Mega slot

    func testMegaCandidatesAreCopiesThatCanMegaEvolveNowOrReachAMega() {
        var b = box()
        let c = P23.ctx(builds: b.builds, entries: b.entries, table: table())
        XCTAssertTrue(HubSquads.megaCapable(entryId: "ab", ctx: c))
        XCTAssertFalse(HubSquads.megaCapable(entryId: "ge", ctx: c), "a Gastly cannot Mega Evolve yet")
        XCTAssertTrue(HubSquads.megaCandidate(entryId: "ge", ctx: c), "but its build ends in Mega Gengar")
        XCTAssertFalse(HubSquads.megaCandidate(entryId: "gb", ctx: c), "Gabite: no build of it Mega Evolves, and a Gabite is not Mega-capable")
        // A Shadow copy never Mega Evolves; a Pokémon with no Mega form cannot either.
        b.entries = b.entries.map { $0.id == "ge" ? P23.entry("ge", "gengar", shadow: 1) : $0.id == "ab" ? P23.entry("ab", "mamoswine") : $0 }
        let plain = b.builds.map { var x = $0; x.viaMega = false; x.steps = x.steps?.filter { $0.kind != "megaEvolve" }; return x }
        let none = P23.ctx(builds: plain, entries: b.entries, table: table())
        XCTAssertFalse(HubSquads.megaCapable(entryId: "ge", ctx: none), "a Shadow copy")
        XCTAssertFalse(HubSquads.megaCapable(entryId: "ab", ctx: none), "mamoswine has no Mega")
        XCTAssertTrue(HubSquads.megaCapable(entryId: "k", ctx: P23.ctx(entries: [P23.entry("k", "kyogre")])), "Primal counts")
        let slots = squad(none)
        XCTAssertNil(slots[0].entryId, "no Mega candidate in the box: the Mega slot is empty, it does not take a non-Mega")
        XCTAssertEqual(slots.dropFirst().compactMap(\.entryId).count, 5)
        let place = HubSquads.placeable(screen: .raids, mode: .available, ctx: none)
        XCTAssertFalse(place("ge", "Mega")); XCTAssertTrue(place("ge", "Heavy hitter"))
        XCTAssertFalse(place("species:gengar", "Heavy hitter"), "a Pokémon the box lacks is never placed under Available")
    }

    func testACopyThatCanMegaEvolveWithNoBuildThatDoesTakesTheMegaSlotWithMegaEvolveToDo() {
        let builds = [P23.build("g", "garchomp", areas: ["Raids"], built: false), P23.build("a", "abomasnow", areas: ["Raids"], built: false, powerUp: false, viaMega: true, steps: steps("megaEvolve"))]
        let entries = [P23.entry("g", "garchomp"), P23.entry("a", "abomasnow")]
        let tbl = P23.table([P23.tierEntry("raids", "Dragon", "A", "garchomp"), P23.tierEntry("raids", "Ice", "S", "abomasnow_mega", mega: true)])
        let c = P23.ctx(builds: builds, entries: entries, table: tbl)
        let cands = HubSquads.raidCandidates(row: giratina, mode: .available, ctx: c)
        let g = try! XCTUnwrap(cands.first { $0.entryId == "g" }?.mega)
        XCTAssertEqual(g.tier, ""); XCTAssertFalse(g.built)
        XCTAssertTrue((g.build.steps ?? []).contains { $0.kind == "megaEvolve" }, "Mega Evolve is still to do")
        XCTAssertEqual(HubSquads.raidPool(role: "Mega", in: cands), ["a", "g"], "the Mega build the tables list first")
        XCTAssertEqual(squad(c, slots: [SquadSlot(role: "Mega")]).map(\.entryId), ["a"])
    }

    func testASquadHoldsOneMegaOnly() {
        let b = box()
        let c = P23.ctx(builds: b.builds, entries: b.entries, table: table())
        let two = squad(c, slots: [SquadSlot(role: "Mega"), SquadSlot(role: "Mega"), SquadSlot(role: "Heavy hitter")])
        XCTAssertEqual(two.map(\.entryId), ["ab", nil, "sw"], "a second Mega slot stays empty")
    }

    // MARK: fill order and the picker

    func testEachRolesOwnSlotsFillBeforeAnyFallback() {
        // Two Heavy slots, one Bulky slot; one Heavy and two Bulky in the box, the first Bulky the strongest of all. A Heavy slot that ran out must not take the Bulky
        // slot's Pokémon.
        let slots = [SquadSlot(role: "H"), SquadSlot(role: "H"), SquadSlot(role: "B")]
        let roles = ["h1": "H", "b1": "B", "b2": "B"]
        let all = ["b1", "h1", "b2"]
        let out = HubSquads.fill(slots: slots, pool: { _, role in .init(preferred: all.filter { roles[$0] == role }, fallback: all) })
        XCTAssertEqual(out.map(\.pickId), ["h1", "b2", "b1"])
        XCTAssertEqual(out.map(\.fallback), [false, true, false])
    }

    func testThePickerListsItsRoleFirstThenOtherRoles() {
        // One Bulky and six Heavy hitters.
        let names = ["umbreon", "weavile", "hydreigon", "garchomp", "chandelure", "mamoswine", "salamence"]
        let builds = names.enumerated().map { P23.build("c\($0.offset)", $0.element, areas: ["Raids"], built: false) }
        let tbl = P23.table([P23.tierEntry("raids", "Dark", "B", "umbreon")] + ["weavile", "hydreigon", "garchomp", "chandelure", "mamoswine", "salamence"].map { P23.tierEntry("raids", "Ghost", "A", $0) })
        let c = P23.ctx(builds: builds, entries: names.enumerated().map { P23.entry("c\($0.offset)", $0.element) }, table: tbl)
        let cands = HubSquads.raidCandidates(row: giratina, mode: .available, ctx: c)
        XCTAssertEqual(cands.filter { $0.role == .bulky }.count, 1)
        let all = cands.map(\.entryId)
        let bulky = HubSquads.pickerGroups(own: HubSquads.raidPool(role: "Bulky hitter", in: cands), all: all, allowsOther: true)
        XCTAssertEqual(bulky.own, ["c0"])
        XCTAssertEqual(bulky.other.count, 6, "every other Pokémon, each with its role")
        XCTAssertEqual(bulky.other, all.filter { $0 != "c0" }, "in the order the fill uses")
        let mega = HubSquads.pickerGroups(own: HubSquads.raidPool(role: "Mega", in: cands), all: all, allowsOther: false)
        XCTAssertEqual(mega.other, [], "the Mega slot lists Mega candidates only")
    }

    func testARoleHasRunOutWhenNoListedCandidateOfItIsLeft() {
        // Manager call, 31 Oct 2026: a Bulky slot with only an unlisted Bulky left (Abomasnow: its Mega is listed, the plain form is not) takes a listed Heavy hitter first.
        let builds = [P23.build("sw", "mamoswine", areas: ["Raids"], built: false, powerUp: false), P23.build("gb", "garchomp", areas: ["Raids"], built: false, powerUp: false),
                      P23.build("ab", "abomasnow", areas: ["Raids"], built: false, powerUp: false, viaMega: true, steps: steps("megaEvolve"))]
        let entries = [P23.entry("sw", "swinub"), P23.entry("gb", "gabite"), P23.entry("ab", "abomasnow")]
        let c = P23.ctx(builds: builds, entries: entries, table: table())
        let cands = HubSquads.raidCandidates(row: giratina, mode: .available, ctx: c)
        let ab = try! XCTUnwrap(cands.first { $0.entryId == "ab" })
        XCTAssertEqual(ab.role, .bulky); XCTAssertEqual(ab.tier, "", "plain Abomasnow is unlisted")
        XCTAssertEqual(squad(c, slots: [SquadSlot(role: "Heavy hitter"), SquadSlot(role: "Bulky hitter")]).map(\.entryId), ["sw", "gb"], "the listed Heavy hitter beats the unlisted Bulky")
        let three = squad(c, slots: [SquadSlot(role: "Heavy hitter"), SquadSlot(role: "Bulky hitter"), SquadSlot(role: "Bulky hitter")])
        XCTAssertEqual(three.map(\.entryId), ["sw", "gb", "ab"], "only then the unlisted one, in its own role")
        XCTAssertEqual(three.map(\.fallback), [false, true, false])
        // Phase three before four: an unlisted candidate of the slot's own role comes before an unlisted one of another role.
        let gaps = squad(c, slots: [SquadSlot(role: "Bulky hitter"), SquadSlot(role: "Bulky hitter"), SquadSlot(role: "Bulky hitter"), SquadSlot(role: "Bulky hitter")])
        XCTAssertEqual(gaps.compactMap(\.entryId), ["sw", "gb", "ab"], "listed Heavy hitters of another role first, then the unlisted Bulky; the fourth slot has nothing left")
    }

    func testMaxFillsASlotWithAnyRoleToo() {
        let boss = P23.row("2026-10-30", "2026-11-05", .maxMonday, bosses: [P23.boss("charizard", types: ["fire"])])
        let tbl = P23.table([P23.tierEntry("max", "Attackers", "S", "swampert"), P23.tierEntry("max", "Attackers", "A", "kingler")])
        let builds = [P23.build("s", "swampert", areas: ["Max"], built: false), P23.build("k", "kingler", areas: ["Max"], built: false, powerUp: false)]
        let c = P23.ctx(builds: builds, entries: [P23.entry("s", "swampert"), P23.entry("k", "krabby")], table: tbl)
        let cands = HubSquads.maxCandidates(row: boss, mode: .available, ctx: c)
        XCTAssertEqual(cands.map(\.entryId), ["s", "k"], "an evolution still to do is a candidate")
        let place = HubSquads.placeable(screen: .max, mode: .available, ctx: c)
        let slots = HubSquads.maxSquad(candidates: cands, fillAnyRole: true, placeable: place)
        XCTAssertEqual(slots.map(\.role), ["Tank", "Healer", "Attacker"])
        XCTAssertEqual(slots.map(\.entryId), ["k", nil, "s"], "the Attacker slot takes the strongest Attacker; the Tank slot then takes the one left; the Healer has nothing")
        XCTAssertEqual(slots.map(\.fallback), [true, false, false])
        XCTAssertEqual(HubSquads.maxSquad(candidates: cands, placeable: place).map(\.entryId), [nil, nil, "s"], "without the rule the Tank slot is empty")
    }

    func testGymRocketAndPvpAvailableAlsoTakeUpgrades() {
        let gymTable = P23.table([P23.tierEntry("gym", "Tiers", "S", "snorlax")])
        let gym = P23.ctx(builds: [P23.build("g", "snorlax", areas: ["Gym"], built: false, powerUp: false)], entries: [P23.entry("g", "munchlax")], table: gymTable)
        XCTAssertEqual(HubSquads.gymRows(mode: .available, ctx: gym).map { $0.build.entryId }, ["g"], "an evolution to do is a defender")
        XCTAssertTrue(HubSquads.placeable(screen: .gym, mode: .available, ctx: gym)("g", "Defender"))

        let mewtwo = HubData.Boss(name: "Mewtwo", speciesId: "mewtwo", types: ["psychic"], shadow: nil)
        let rocket = P23.ctx(builds: [P23.build("r", "gengar", areas: ["Rocket"], built: false, formChange: true)], entries: [P23.entry("r", "gastly")])
        XCTAssertEqual(HubSquads.rocketPicker(options: [mewtwo], mode: .available, ctx: rocket).map(\.entryId), ["r"])

        let leagues = ["c0": ["gl": P23.rating([P23.option("medicham", isSelf: false, score: 95)])]]
        let pvp = P23.ctx(entries: [P23.entry("c0", "meditite")], leagues: leagues)
        XCTAssertEqual(HubSquads.pvpCandidates(league: "gl", mode: .available, ctx: pvp).map(\.entryId), ["c0"], "an evolution is a candidate")
        XCTAssertTrue(HubSquads.placeable(screen: .pvp, mode: .available, league: "gl", ctx: pvp)("c0", "Lead"))
        XCTAssertFalse(HubSquads.placeable(screen: .pvp, mode: .available, league: "gl", ctx: pvp)("zz", "Lead"))
    }

    func testPvpStillNeverPutsTwoOfOneSpeciesInASquad() {
        let leagues = ["a": ["gl": P23.rating([P23.option("medicham", isSelf: false, score: 95)])], "b": ["gl": P23.rating([P23.option("medicham", isSelf: true, score: 93)])],
                       "c": ["gl": P23.rating([P23.option("azumarill", isSelf: true, score: 92)])]]
        let c = P23.ctx(entries: [P23.entry("a", "meditite"), P23.entry("b", "medicham"), P23.entry("c", "azumarill")], leagues: leagues)
        XCTAssertEqual(HubSquads.pvpCandidates(league: "gl", mode: .available, ctx: c).map(\.entryId), ["a", "c"], "the best copy of each species")
    }

    // MARK: one definition of Mega-capable

    func testMegaCapableUsesTheCollectionsRule() throws {
        let gm = P23.gm
        let membership = HubCollection.Membership(entries: [], gm: gm)
        for id in gm.byId.keys where !id.contains("_mega") && !id.contains("_primal") {
            XCTAssertEqual(HubSquads.hasMegaForm(id, gm: gm), membership.megaIds.contains(id), id)
        }
        XCTAssertTrue(HubSquads.hasMegaForm("charizard", gm: gm))
        XCTAssertFalse(HubSquads.hasMegaForm("pikachu", gm: gm))
        // Camerupt: whatever the Collection says of it, Raids says the same.
        XCTAssertEqual(HubSquads.hasMegaForm("camerupt", gm: gm), membership.megaIds.contains("camerupt"))
        print("CAMERUPT hasMegaForm", HubSquads.hasMegaForm("camerupt", gm: gm), gm.byId["camerupt_mega"].map { "released=\($0.released) tags=\($0.tags)" } ?? "no camerupt_mega")
    }

    // MARK: Best: one status per row (S1)

    func testEveryBestRowHasExactlyOneOfThreeStatusesWithItsReason() {
        let fire = P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("charizard", types: ["fire"])])
        let tbl = P23.table([P23.tierEntry("raids", "Water", "S", "vaporeon"),                                   // owned, built
                             P23.tierEntry("raids", "Water", "S", "kingler"),                                   // owned, needs work
                             P23.tierEntry("raids", "Water", "S", "palkia", obtain: "Hard"),                     // a raid boss now
                             P23.tierEntry("raids", "Water", "A", "excadrill", obtain: "Medium. T5 raids"),      // the research says it can be got
                             P23.tierEntry("raids", "Water", "A", "darkrai", obtain: "Hard. Past raid"),         // boss later, not now
                             P23.tierEntry("raids", "Water", "A", "mewtwo", obtain: "Hard. Raids"),              // Hard, no schedule
                             P23.tierEntry("raids", "Water", "B", "heatran", obtain: "Locked. GO Fest only"),
                             P23.tierEntry("raids", "Water", "B", "machop"),                                    // no obtain line at all
                             P23.tierEntry("raids", "Water", "B", "slaking", obtain: "Easy–Hard. Wild"),         // a range to Hard
                             P23.tierEntry("raids", "Water", "B", "slowbro", obtain: "Medium / Easy"),           // a slash
                             P23.tierEntry("raids", "Water", "B", "lapras", obtain: "Easy. Wild until Sep 2026"),  // names a month
                             P23.tierEntry("raids", "Water", "B", "swampert_mega", mega: true, obtain: "Easy")])  // a Mega: the schedule decides
        let rotation = [fire, P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("palkia", types: ["water", "dragon"])]),
                        P23.row("2026-11-09", "2026-11-15", bosses: [P23.boss("darkrai", types: ["dark"])])]
        let builds = [P23.build("a", "vaporeon", areas: ["Raids"]), P23.build("b", "kingler", areas: ["Raids"], built: false)]
        let rows = HubSquads.bestRaidRows(row: fire, ctx: P23.ctx(builds: builds, entries: [P23.entry("a", "vaporeon"), P23.entry("b", "kingler")], table: tbl, today: "2026-10-25", rotation: rotation))
        XCTAssertEqual(rows.map(\.key), ["vaporeon", "kingler", "palkia", "excadrill", "darkrai", "mewtwo", "heatran", "machop", "slaking", "slowbro", "lapras", "swampert_mega"])
        let none = "Not available now · not on the schedule"
        XCTAssertEqual(rows.map(\.status.text), ["In your box", "In your box · needs upgrade", "Can get now · Raid boss now", "Can get now · Medium. T5 raids",
                                                 "Not available now · Raids from 9 Nov", none, none, none, none, none, none, none])
        XCTAssertEqual(rows.map(\.status.kind), [.inBox, .inBox, .canGetNow, .canGetNow] + Array(repeating: .notAvailableNow, count: 8))
    }

    func testABestCopyWithNoBuildIsInYourBoxNeedingAnUpgradeWithItsReason() {
        let tbl = P23.table([P23.tierEntry("gym", "Tiers", "S", "snorlax")])
        let rows = HubSquads.bestGymRows(ctx: P23.ctx(entries: [P23.entry("s", "snorlax")], table: tbl))
        XCTAssertEqual(rows.map(\.status.text), ["In your box · needs upgrade · no build for this"])
        XCTAssertEqual(HubSquads.BestRow(key: "x", name: "X", speciesId: "x", tier: "S", roles: [], types: [], availability: "").status.text, "Not available now · not on the schedule", "no default status without a reason")
    }

    func testOnlyTheCatchableRocketSlotIsABossNow() {
        let giovanni = HubData.Leader(name: "Giovanni", since: "2026-10", slots: [[P23.boss("persian_shadow", types: ["normal"])], [P23.boss("kangaskhan", types: ["normal"])], [P23.boss("zekrom", types: ["dragon"])]], source: "")
        let cliff = HubData.Leader(name: "Cliff", since: "2026-10", slots: [[P23.boss("machop", types: ["fighting"])], [P23.boss("snorlax", types: ["normal"])], [P23.boss("onix", types: ["rock"])]], source: "")
        let tbl = P23.table([P23.tierEntry("rocket", "T", "S", "zekrom", obtain: "Hard"), P23.tierEntry("rocket", "T", "S", "persian_shadow", shadow: true, obtain: "Hard"),
                             P23.tierEntry("rocket", "T", "A", "machop", obtain: "Hard"), P23.tierEntry("rocket", "T", "A", "onix", obtain: "Hard")])
        let c = P23.ctx(table: tbl, edit: { $0.leaders = [giovanni, cliff] })
        func now(_ i: Int) -> Bool { HubSquads.availabilityParts(of: tbl.entries[i], ctx: c).canGetNow }
        XCTAssertEqual([now(0), now(1), now(2), now(3)], [true, false, true, false], "Giovanni's third slot and Cliff's first; the others are not catchable")
        XCTAssertEqual(HubSquads.availabilityParts(of: tbl.entries[0], ctx: c).rotation, "Rocket boss now")
    }

    // MARK: real data

    func testTheResearchLinesOfMegasAndLegendsAreNeverCanGetNow() throws {
        let real = try TierTable.bundled()
        let ctx = P23.ctx(table: real, rotation: [])
        for name in ["Xerneas", "Mega Starmie", "Mega Delphox", "Mega Gengar"] {
            let e = try XCTUnwrap(real.entries.first { $0.area == "raids" && $0.name == name }, name)
            let p = HubSquads.availabilityParts(of: e, ctx: ctx)
            XCTAssertFalse(p.canGetNow, "\(name): \(e.obtain ?? "-")")
        }
        // Every row of the real Raids table against an empty schedule: a Mega, Primal, Legend, Mythical or Ultra Beast is never got now, and nothing reads Can get now
        // whose line names a month or year or ranges to Hard.
        for e in real.entries where e.area == "raids" {
            guard HubSquads.availabilityParts(of: e, ctx: ctx).canGetNow else { continue }
            let tags = (P23.gm.byId[e.speciesId] ?? P23.gm.byId[e.speciesId.replacingOccurrences(of: "_shadow", with: "")])?.tags ?? []
            XCTAssertFalse(e.flags.mega || tags.contains("legendary") || tags.contains("mythical") || tags.contains("ultrabeast"), "\(e.name): \(e.obtain ?? "")")
            XCTAssertNil((e.obtain ?? "").range(of: #"\b20[0-9]{2}\b"#, options: .regularExpression), "\(e.name): \(e.obtain ?? "")")
            let head = (e.obtain ?? "").split(separator: ".").first.map(String.init) ?? ""
            XCTAssertFalse(head.contains("Hard") || head.contains("/"), "\(e.name): \(e.obtain ?? "")")
        }
    }

    // MARK: Greg's real box

    private static var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    /// Raids against Giratina (Origin) on Greg's own box of 22 Oct 2026, through the real engine: every slot is filled.
    func testGiratinaOriginOnGregsRealBoxFillsEverySlot() throws {
        let gm = P23.gm
        let text = try String(contentsOf: Self.root.appendingPathComponent("fixtures/greg-2026-10-22.box.csv"), encoding: .utf8)
        let box = BoxCSVReader.entries(csv: text, gm: gm)
        let rows = box.enumerated().map { i, e in var r = e.row; r.index = i + 1; return r }
        let advice = BoxAdvice.make(from: try sharedEngine.advise(rows: rows, scanDate: Date(timeIntervalSince1970: 1_790_000_000)), entries: box)
        let hub = P23.hub
        let row = try XCTUnwrap(hub.rotation.first { $0.kind == .fiveStar && $0.bosses.contains { $0.speciesId == "giratina_origin" } })
        let ctx = HubContext(advice: advice, entries: box, gm: gm, hub: hub, table: try TierTable.bundled(), today: row.from)
        let cands = HubSquads.raidCandidates(row: row, mode: .available, ctx: ctx)
        let slots = HubSquads.raidSquad(candidates: cands, fillAnyRole: true, placeable: HubSquads.placeable(screen: .raids, mode: .available, ctx: ctx))
        let byId = Dictionary(cands.map { ($0.entryId, $0) }, uniquingKeysWith: { a, _ in a })
        var lines = [String]()
        for (i, s) in slots.enumerated() {
            guard let id = s.entryId, let c = byId[id] else { lines.append("slot \(i + 1) \(s.role): EMPTY"); continue }
            let isMega = s.role == "Mega"
            let b = isMega ? (c.mega?.build ?? c.build) : c.build
            let tier = isMega ? (c.mega?.tier ?? "") : c.tier
            let full = HubSquads.isFullStrength(b, screen: .raids, ctx: ctx)
            let cost = HubSquads.cost(of: b)
            let copy = ctx.entry(id)?.row.title ?? id
            lines.append("slot \(i + 1) \(s.role): \(copy) as \(b.targetName)\(isMega ? " (Mega build)" : "")  role \(isMega ? "Mega" : c.role.rawValue)  tier \(tier.isEmpty ? "unlisted" : tier)  \(full ? "Full strength" : "Upgrade: " + b.action + " " + (cost.value.map { "\($0) \(cost.currency.rawValue)" } ?? "free"))\(s.fallback ? "  (another role)" : "")")
        }
        print("GIRATINA-REAL-BOX\n" + lines.joined(separator: "\n"))
        print("GIRATINA-REAL-BOX candidates \(cands.count), mega candidates \(cands.filter { $0.mega != nil }.count), builds \(advice.builds.count)")
        XCTAssertTrue(slots.allSatisfy { $0.entryId != nil }, lines.joined(separator: "\n"))
        XCTAssertEqual(Set(slots.compactMap(\.entryId)).count, 6)
        let mega = try XCTUnwrap(byId[try XCTUnwrap(slots[0].entryId)])
        XCTAssertNotNil(mega.mega, "the Mega slot holds a Mega candidate")
    }
}
