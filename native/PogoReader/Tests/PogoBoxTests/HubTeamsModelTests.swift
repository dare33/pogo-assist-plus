import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The Gym, Team Rocket and PvP suggestions, pinned on the report the advisor gives for the fixture box. The fixture's builds are mostly
/// not built yet and none has the Gym area, so the cases it does not reach use fixture builds with their figures changed.
final class HubTeamsModelTests: XCTestCase {
    private func advice() throws -> BoxAdvice {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!
        let es = try Fixture.expected().rows.enumerated().map { i, r in BoxEntry(id: "e\(i)", row: r, firstSeen: date, lastSeen: date) }
        return BoxAdvice.make(from: try sharedEngine.advise(rows: es.map(\.row)), entries: es)
    }
    private let gm = try! GameMaster.bundled(), hub = try! HubData.bundled()

    private func variant(_ b: BoxAdvice.Build, id: String? = nil, name: String? = nil, areas: [String]? = nil, tier: String? = nil, score: Double? = nil,
                         steps: [BoxAdvice.Build.Step]? = nil, built: Bool = false) -> BoxAdvice.Build {
        var v = b
        if let id { v.targetId = id; v.entryId = "v-" + id }
        if let name { v.targetName = name; v.title = name }
        if let areas { v.areas = areas }
        if let tier { v.tier = tier }
        if let score { v.score = score }
        if let steps { v.steps = steps } else if built { v.steps = [] }
        return v
    }

    // MARK: built

    func testBuiltMeansNoStepsOrOnlyTheDynamaxRequirement() throws {
        let b = try advice().builds
        XCTAssertEqual(b.map(HubTeams.isBuilt), [false, false, false, true, false], "Lucario, Zamazenta, Xerneas, Staraptor (Mega, no steps), Moltres")
        var v = b[0]
        v.steps = [.init(kind: "needsDynamaxCopy")]; XCTAssertTrue(HubTeams.isBuilt(v))
        v.steps = [.init(kind: "needsDynamaxCopy"), .init(kind: "secondMove")]; XCTAssertFalse(HubTeams.isBuilt(v))
        v.steps = nil; XCTAssertTrue(HubTeams.isBuilt(v))
        XCTAssertEqual(b.map(HubTeams.todo), ["mega evolve Lucario", "form change Zamazenta (Hero)", "power up Xerneas", "staraptor (Mega)", "power up Moltres"])
    }

    // MARK: Gym

    func testTopDefendersAreBuiltGymBuildsByTierThenScoreOnePerSpecies() throws {
        let b = try advice().builds
        let base = b[3]   // built
        XCTAssertTrue(HubTeams.topDefenders(builds: b).isEmpty, "the fixture has no Gym build")
        let list = [variant(base, id: "snorlax", name: "Snorlax", areas: ["Gym"], tier: "A", score: 5),
                    variant(base, id: "blissey", name: "Blissey", areas: ["Gym"], tier: "S", score: 3),
                    variant(base, id: "snorlax", name: "Snorlax", areas: ["Gym", "Raids"], tier: "A", score: 4),      // the same species again
                    variant(base, id: "lapras", name: "Lapras", areas: ["Gym"], tier: "S", score: 7, steps: [.init(kind: "powerUp")]),   // not built
                    variant(base, id: "metagross", name: "Metagross", areas: ["Gym"], tier: "S", score: 6),
                    variant(base, id: "togekiss", name: "Togekiss", areas: ["Raids"], tier: "S", score: 9)]           // no Gym area
        XCTAssertEqual(HubTeams.topDefenders(builds: list).map(\.targetName), ["Metagross", "Blissey", "Snorlax"])
        let many = (1...8).map { variant(base, id: "s\($0)", name: "S\($0)", areas: ["Gym"], tier: "B", score: Double($0)) }
        XCTAssertEqual(HubTeams.topDefenders(builds: many).map(\.targetName), ["S8", "S7", "S6", "S5", "S4", "S3"], "up to six")
        XCTAssertEqual(HubTeams.gymAvailable(builds: list).map(\.targetName), ["Snorlax", "Blissey", "Snorlax", "Lapras", "Metagross"], "advisor order, built or not")
        XCTAssertEqual(HubTeams.gymEmptyHints(builds: list, slots: 3), ["Power up Lapras", nil, nil])
    }

    func testEmptyGymSlotsNameUnbuiltBuildsThenGymGaps() throws {
        let a = try advice()
        let unbuilt = variant(a.builds[3], id: "lapras", name: "Lapras", areas: ["Gym"], steps: [.init(kind: "powerUp")])
        let gaps = [BoxAdvice.Gap(area: "Gym", section: nil, tier: "S", name: "Snorlax", obtain: nil, haveBase: false),
                    BoxAdvice.Gap(area: "Max", section: nil, tier: "S", name: "Lapras", obtain: nil, haveBase: false),     // not a Gym gap
                    BoxAdvice.Gap(area: "Gym", section: nil, tier: "B", name: "Slowbro", obtain: nil, haveBase: false),    // not S or A
                    BoxAdvice.Gap(area: "Gym", section: nil, tier: "A", name: "Togekiss", obtain: nil, haveBase: false)]
        XCTAssertEqual(HubTeams.gymEmptyHints(builds: [unbuilt], gaps: gaps, slots: 4), ["Power up Lapras", "Catch Snorlax", "Catch Togekiss", nil])
        XCTAssertEqual(HubTeams.gymEmptyHints(builds: a.builds, gaps: a.gaps, slots: 2), ["Catch Blissey", "Catch Chansey"], "the fixture has no Gym build; its S gaps follow the report's order")
    }

    // MARK: Rocket

    func testGiovanniOnTheFixture() throws {
        let a = try advice(), b = a.builds
        let giovanni = hub.leaders.first { $0.name == "Giovanni" }!
        // Slot 2 (Kangaskhan, Rhyperior, Machamp): Lucario (S, not built) beats Kangaskhan and Rhyperior; Staraptor (B, built) beats Machamp only. Hits come first.
        let slot2 = HubTeams.counter(for: giovanni.slots[1], builds: b, gm: gm, hub: hub)
        XCTAssertEqual(slot2, .toBuild(b[0]))
        XCTAssertEqual(HubTeams.beatsText(by: b[0], options: giovanni.slots[1], gm: gm, hub: hub), "beats Kangaskhan and Rhyperior")
        XCTAssertEqual(HubTeams.beatsText(by: b[3], options: giovanni.slots[1], gm: gm, hub: hub), "beats Machamp only")
        XCTAssertEqual(HubTeams.beatsText(by: b[0], options: giovanni.slots[0], gm: gm, hub: hub), "beats Persian")
        // The team gives Lucario to slot 1 (the only Fighting counter), so slot 2 takes the next copy that hits most.
        let team = HubTeams.leaderTeam(leader: giovanni, builds: b, gaps: a.gaps, gm: gm, hub: hub)
        XCTAssertEqual(team.map(\.name), ["Lucario", "Zamazenta (Crowned Shield)", "Xerneas"])
        XCTAssertEqual(team.map(\.gapText), ["gap: mega evolve Lucario", "gap: form change Zamazenta (Hero)", "gap: power up Xerneas"])
        XCTAssertEqual(team.compactMap(\.build).map(\.entryId).count, Set(team.compactMap(\.build).map(\.entryId)).count, "a copy serves one slot")
        // Once Lucario is built, slot 1 takes it as a built counter.
        var built = b; built[0].steps = []
        XCTAssertEqual(HubTeams.leaderTeam(leader: giovanni, builds: built, gm: gm, hub: hub).first, .built(built[0]))
    }

    func testACopyServesOneSlotButTwoCopiesOfASpeciesMayServeTwo() throws {
        let b = try advice().builds
        let giovanni = hub.leaders.first { $0.name == "Giovanni" }!
        let lucario = variant(b[3], id: "lucario", name: "Lucario", areas: ["Rocket"], tier: "S", score: 9, built: true)
        var twin = lucario; twin.entryId = "second-lucario"; twin.score = 8
        let one = HubTeams.leaderTeam(leader: giovanni, builds: [lucario], gm: gm, hub: hub)
        XCTAssertEqual(one.map(\.name), ["Lucario", "—", "—"], "one copy is not reused when nothing else will do")
        let two = HubTeams.leaderTeam(leader: giovanni, builds: [lucario, twin], gm: gm, hub: hub)
        XCTAssertEqual(two.compactMap(\.build).map(\.entryId), ["v-lucario", "second-lucario"])
    }

    func testASlotWithNoCounterTakesTheGapFallbackElseReadsDash() throws {
        let a = try advice()
        let cliff = hub.leaders.first { $0.name == "Cliff" }!   // slot 1 Cubone (Ground): nothing in the fixture box is Water, Grass or Ice
        let bare = HubTeams.leaderTeam(leader: cliff, builds: a.builds, gm: gm, hub: hub)
        XCTAssertEqual(bare.first, HubTeams.Counter.none)
        XCTAssertEqual(bare.first?.name, "—")
        XCTAssertNil(bare.first?.gapText)
        // With the gaps: the first S gap of the Rocket area that a Water or Ground type fills (Swampert, Water/Ground).
        let withGaps = HubTeams.leaderTeam(leader: cliff, builds: a.builds, gaps: a.gaps, gm: gm, hub: hub)
        XCTAssertEqual(withGaps.first?.gapText, "gap: Swampert")
        XCTAssertEqual(withGaps.first?.name, "—")
    }

    func testSlotRankingHitsThenBuiltThenRocketThenTierThenScore() throws {
        let base = try advice().builds[3]
        let slot = hub.leaders.first { $0.name == "Giovanni" }!.slots[1]   // Kangaskhan (Normal), Rhyperior (Rock/Ground), Machamp (Fighting)
        func pick(_ list: [BoxAdvice.Build]) -> String { HubTeams.counter(for: slot, builds: list, gm: gm, hub: hub).name }
        let three = variant(base, id: "hawlucha", name: "Hawlucha", areas: ["Raids"], tier: "B", score: 1, steps: [.init(kind: "powerUp")])   // Fighting/Flying: all 3, not built
        let water = variant(base, id: "swampert", name: "Swampert", areas: ["Raids"], tier: "S", score: 9, built: true)                       // Rhyperior only, built
        XCTAssertEqual(HubTeams.beatsText(by: three, options: slot, gm: gm, hub: hub), "beats all 3")
        XCTAssertEqual(pick([water, three]), "Hawlucha", "the most options beaten comes before built, tier and score")
        let fighting = variant(base, id: "lucario", name: "Lucario", areas: ["Raids"], tier: "B", score: 1, steps: [.init(kind: "powerUp")])   // Kangaskhan and Rhyperior
        let fightingBuilt = variant(fighting, id: "hariyama", name: "Hariyama", steps: [])
        XCTAssertEqual(pick([fightingBuilt, three]), "Hawlucha")
        let sameHits = variant(fighting, id: "heracross", name: "Heracross", steps: [])        // 2 hits, built
        let sameHitsUnbuilt = variant(fighting, id: "hariyama", name: "Hariyama", steps: [.init(kind: "powerUp")])
        XCTAssertEqual(pick([sameHitsUnbuilt, sameHits]), "Heracross", "at equal hits a built copy wins")
        let rocket = variant(sameHits, id: "machamp", name: "Machamp", areas: ["Rocket"])
        XCTAssertEqual(pick([sameHits, rocket]), "Machamp", "then the Rocket area")
        let tierS = variant(sameHits, id: "conkeldurr", name: "Conkeldurr", tier: "S", score: 0.1)
        XCTAssertEqual(pick([sameHits, tierS]), "Conkeldurr", "then tier")
        let scored = variant(sameHits, id: "blaziken", name: "Blaziken", score: 9)
        XCTAssertEqual(pick([sameHits, scored]), "Blaziken", "then score")
        XCTAssertEqual(HubTeams.counter(for: slot, builds: [variant(base, areas: ["Max"], built: true)], gm: gm, hub: hub), HubTeams.Counter.none, "Max alone is not a Rocket area")
    }

    func testGruntCounters() throws {
        let a = try advice()
        func c(_ t: String, _ builds: [BoxAdvice.Build]? = nil, gaps: [BoxAdvice.Gap]? = nil) -> HubTeams.Counter {
            HubTeams.gruntCounter(type: t, builds: builds ?? a.builds, gaps: gaps ?? a.gaps, gm: gm, hub: hub)
        }
        // Fire grunt (Water, Rock, Ground answer it): nothing in the fixture box is one, so the first S gap that is (Swampert, a Rocket attacker).
        guard case .gap(let g) = c("fire") else { return XCTFail("\(c("fire"))") }
        XCTAssertEqual(g.name, "Swampert")
        XCTAssertEqual(c("fire").gapText, "gap: Swampert")
        XCTAssertEqual(c("fire").name, "—")
        XCTAssertEqual(c("grass"), .built(a.builds[3]), "Staraptor (Flying) is built")
        XCTAssertEqual(c("normal"), .toBuild(a.builds[0]))
        XCTAssertEqual(c("normal").gapText, "gap: mega evolve Lucario")
        XCTAssertEqual(c("bug"), .built(a.builds[3]), "built beats unbuilt")
        XCTAssertEqual(c("fire", gaps: []), HubTeams.Counter.none)
        let pupitar = variant(a.builds[3], id: "tyranitar", name: "Tyranitar", areas: ["Rocket"], tier: "S", steps: [.init(kind: "evolve", to: "Tyranitar")])
        var named = pupitar; named.title = "Pupitar"
        XCTAssertEqual(c("psychic", [named]).gapText, "gap: evolve Pupitar")   // Dark answers Psychic
        let raid = variant(a.builds[3], id: "tyranitar", name: "Tyranitar", areas: ["Raids"], tier: "S", score: 99, built: true)
        let rocket = variant(a.builds[3], id: "honchkrow", name: "Honchkrow", areas: ["Rocket"], tier: "B", score: 1, built: true)
        XCTAssertEqual(c("psychic", [raid, rocket]).name, "Honchkrow", "Rocket area beats Raids at the same standing")
    }

    func testGapFallbackFiltersByTierAreaAndTakesTypesFromTheSpeciesId() throws {
        func gap(_ name: String, _ id: String?, tier: String = "S", area: String = "Rocket") -> BoxAdvice.Gap {
            BoxAdvice.Gap(area: area, section: nil, tier: tier, name: name, obtain: nil, haveBase: false, speciesId: id)
        }
        func fire(_ gaps: [BoxAdvice.Gap]) -> HubTeams.Counter { HubTeams.gruntCounter(type: "fire", builds: [], gaps: gaps, gm: gm, hub: hub) }
        XCTAssertEqual(fire([gap("Swampert", "swampert", tier: "B")]), HubTeams.Counter.none, "a B gap is not offered")
        XCTAssertEqual(fire([gap("Swampert", "swampert", area: "Gym")]), HubTeams.Counter.none, "only the Rocket and Raids areas")
        XCTAssertEqual(fire([gap("Machamp", "machamp")]), HubTeams.Counter.none, "a Fighting type does not beat Fire")
        XCTAssertEqual(fire([gap("Swampert", "swampert", tier: "A")]).gapText, "gap: Swampert", "an A gap is")
        XCTAssertEqual(fire([gap("Swampert", "swampert", tier: "A"), gap("Rhyperior", "rhyperior", tier: "S")]).gapText, "gap: Rhyperior", "S before A")
        XCTAssertEqual(fire([gap("Rhyperior", "rhyperior", area: "Raids"), gap("Swampert", "swampert")]).gapText, "gap: Swampert", "Rocket area before Raids")
        // The id decides, not the words in the name: a Mega's own types, and a name that is no species at all.
        XCTAssertEqual(fire([gap("Mega Garchomp", "garchomp_mega", area: "Raids")]).gapText, "gap: Mega Garchomp", "Ground/Dragon Mega beats Fire")
        XCTAssertEqual(fire([gap("Shadow Swampert", "swampert_shadow")]).gapText, "gap: Shadow Swampert")
        XCTAssertEqual(fire([gap("Not A Species", "swampert")]).gapText, "gap: Not A Species")
        XCTAssertEqual(fire([gap("Swampert", nil)]).gapText, "gap: Swampert", "no id: the name")
        XCTAssertEqual(fire([gap("Shadow Swampert", nil)]), HubTeams.Counter.none, "no id and no such name: skipped")
        // A report cached before the engine sent ids decodes with none.
        let old = #"{"area":"Rocket","tier":"S","name":"Swampert","haveBase":false}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(BoxAdvice.Gap.self, from: old).speciesId)
    }

    func testTypelessGruntsGetNoCounter() throws {
        let a = try advice()
        let typeless = hub.grunts.filter { $0.type.isEmpty }
        XCTAssertEqual(typeless.map(\.label), ["Mixed team", "Decoy"])
        XCTAssertEqual(typeless.map(\.quote), ["Winning is for winners", "Fooled ya, twerp"])
        for g in typeless { XCTAssertEqual(HubTeams.gruntCounter(type: g.type, builds: a.builds, gaps: a.gaps, gm: gm, hub: hub), .anyAttacker) }
        XCTAssertEqual(HubTeams.Counter.anyAttacker.name, "Any attacker")
        XCTAssertNil(HubTeams.Counter.anyAttacker.gapText)
    }

    // MARK: PvP

    private func rating(_ id: String, _ name: String, score: Double, ivRank: Int, over: Bool = false, selfName: String? = nil, gender: String? = nil) -> BoxAdvice.LeagueRating {
        let option = BoxAdvice.LeagueRating.Option(speciesId: id, name: name, isSelf: selfName == nil, genderLocked: gender, strength: .init(score: score, rank: 5, of: 200), moves: nil,
                                                    iv: .init(rank: ivRank, pct: 97.5, rankPct: 99, level: 25, cp: 1490), overCap: over)
        guard let selfName else { return .init(options: [option]) }
        return .init(options: [.init(speciesId: "x", name: selfName, isSelf: true), option], pick: 1)
    }

    func testTheFixtureCandidates() throws {
        let a = try advice()
        let gl = HubTeams.candidates(league: "gl", advice: a), ul = HubTeams.candidates(league: "ul", advice: a)
        let ml = HubTeams.candidates(league: "ml", advice: a)
        XCTAssertEqual(ml.map(\.name), ["Xerneas", "Zamazenta (Crowned Shield)"])
        XCTAssertEqual(ml.map(\.score), [94.0, 92.2])
        XCTAssertEqual(ml.map(\.ivRank), [249, 339])
        XCTAssertEqual(ml.map(\.tier), ["S", "S"])
        XCTAssertEqual(ml.map(\.fromText), [nil, "From Zamazenta (Hero)"])
        XCTAssertEqual(ml.map(\.stateText), ["To build", "To build"], "Xerneas still has steps to do; Zamazenta is a form change")
        XCTAssertEqual(ml[0].subText, "#249 · 95.8%")
        XCTAssertTrue(gl.allSatisfy { $0.score >= 80 } && ul.allSatisfy { $0.score >= 80 })
        let team = HubTeams.suggestedTeam(candidates: ml, gm: gm, hub: hub)
        XCTAssertEqual(team.map(\.name), ["Xerneas", "Zamazenta (Crowned Shield)"], "only two candidates, so a team of two")
        // Fairy: Fighting, Dragon, Dark. Fighting: Normal, Ice, Rock, Dark, Steel. Steel: Ice, Rock, Fairy. Eight different types.
        XCTAssertEqual(HubTeams.coverage(team: team, gm: gm, hub: hub), 8)
        XCTAssertEqual(HubTeams.weaknessNote(team: team, candidates: ml, gm: gm, hub: hub), "No shared weakness.")
        XCTAssertTrue(HubTeams.others(candidates: ml, team: team).isEmpty)
        XCTAssertEqual(HubTeams.weaknessNote(team: [team[0]], gm: gm, hub: hub), "", "a team of one has no shared weakness to name")
        XCTAssertEqual(HubTeams.weaknessNote(team: [], gm: gm, hub: hub), "")
    }

    func testCandidatesFilterSortAndKeepTheBestCopyPerSpecies() {
        var a = BoxAdvice()
        a.leagues = ["c1": ["gl": rating("azumarill", "Azumarill", score: 96, ivRank: 40)],
                     "c2": ["gl": rating("azumarill", "Azumarill", score: 96, ivRank: 10)],        // the better copy of the same species
                     "c3": ["gl": rating("medicham", "Medicham", score: 96, ivRank: 30)],           // ties on score; IV rank 30 is worse than Azumarill's 10
                     "c4": ["gl": rating("skarmory", "Skarmory", score: 79.9, ivRank: 1)],          // under the candidate floor
                     "c5": ["gl": rating("registeel", "Registeel", score: 99, ivRank: 1, over: true)],   // past the cap
                     "c6": ["gl": rating("swampert", "Swampert", score: 91, ivRank: 7, selfName: "Mudkip")],
                     "c7": ["gl": rating("lanturn", "Lanturn", score: 80, ivRank: 7)],              // the floor itself is in, with no tier chip
                     "c8": ["gl": rating("hypno", "Hypno", score: 89, ivRank: 7)]]
        let c = HubTeams.candidates(league: "gl", advice: a)
        XCTAssertEqual(c.map(\.name), ["Azumarill", "Medicham", "Swampert", "Hypno", "Lanturn"])
        XCTAssertEqual(c.map(\.entryId), ["c2", "c3", "c6", "c8", "c7"])
        XCTAssertEqual(c.map(\.tier), ["S", "S", "A", "B", ""])
        XCTAssertEqual(c[2].fromText, "From Mudkip")
        XCTAssertEqual(HubTeams.tier(score: 88), "B"); XCTAssertEqual(HubTeams.tier(score: 90), "A"); XCTAssertEqual(HubTeams.tier(score: 92), "S"); XCTAssertEqual(HubTeams.tier(score: 87.99), "")
    }

    func testTheRankingSwitchChoosesTheShownOption() {
        // Pick 0 is Azumarill (91); the experimental member is Medicham (95).
        let first = rating("azumarill", "Azumarill", score: 91, ivRank: 4)
        let second = rating("medicham", "Medicham", score: 95, ivRank: 9)
        var a = BoxAdvice()
        a.leagues = ["c": ["gl": .init(options: first.options + second.options, pick: 0, experimental: 1)]]
        XCTAssertEqual(HubTeams.candidates(league: "gl", advice: a, pogoAssist: false).map(\.name), ["Azumarill"])
        XCTAssertEqual(HubTeams.candidates(league: "gl", advice: a, pogoAssist: true).map(\.name), ["Medicham"])
        XCTAssertEqual(HubTeams.candidates(league: "gl", advice: a, pogoAssist: true).first?.score, 95)
    }

    func testToBuildAndBuiltStates() throws {
        var a = try advice()
        a.leagues = ["e0": ["gl": rating("staraptor", "Staraptor", score: 90, ivRank: 1)],                             // built copy, itself
                     "e1": ["gl": rating("lucario", "Lucario", score: 89, ivRank: 1)],                                 // itself, but its build still has steps
                     "free": ["gl": rating("azumarill", "Azumarill", score: 88, ivRank: 1)],                           // itself, no build at all
                     "evo": ["gl": rating("gallade", "Gallade", score: 87, ivRank: 1, selfName: "Kirlia", gender: "male")]]   // an evolution of the copy
        let c = HubTeams.candidates(league: "gl", advice: a)
        XCTAssertEqual(c.map(\.name), ["Staraptor", "Lucario", "Azumarill", "Gallade"])
        XCTAssertEqual(c.map(\.stateText), ["Built", "To build", "Built", "To build"])
        XCTAssertEqual(c.map(\.displayName), ["Staraptor", "Lucario", "Azumarill", "Gallade, if it is male"])
        XCTAssertEqual(c[3].fromText, "From Kirlia")
    }

    func testSuggestedTeamAddsTheMostNewTypesAndNotesSharedWeakness() {
        var a = BoxAdvice()
        a.leagues = ["x": ["gl": rating("xerneas", "Xerneas", score: 99, ivRank: 1)],
                     "z": ["gl": rating("zamazenta_crowned_shield", "Zamazenta (Crowned Shield)", score: 95, ivRank: 1)],
                     "s": ["gl": rating("swampert", "Swampert", score: 90, ivRank: 1)],
                     "m": ["gl": rating("metagross", "Metagross", score: 89, ivRank: 1)]]
        let c = HubTeams.candidates(league: "gl", advice: a)
        XCTAssertEqual(c.map(\.name), ["Xerneas", "Zamazenta (Crowned Shield)", "Swampert", "Metagross"])
        // After Xerneas (Fighting, Dragon, Dark) Swampert adds six (Fire, Ground, Rock, Electric, Poison, Steel), Zamazenta five, Metagross (Steel/Psychic): Ice, Rock, Fairy, Fighting, Poison.
        let team = HubTeams.suggestedTeam(candidates: c, gm: gm, hub: hub)
        XCTAssertEqual(team.map(\.name), ["Xerneas", "Swampert", "Zamazenta (Crowned Shield)"])
        XCTAssertEqual(HubTeams.coverage(team: team, gm: gm, hub: hub), 12)
        XCTAssertEqual(HubTeams.others(candidates: c, team: team).map(\.name), ["Metagross"])
        XCTAssertEqual(HubTeams.weaknessNote(team: team, gm: gm, hub: hub), "No shared weakness.")
        // Zamazenta (Fire, Ground, Fighting, Flying, Psychic, Fairy) and Metagross (Fire, Ground, Ghost, Dark) share Fire and Ground.
        XCTAssertEqual(HubTeams.weaknessNote(team: [c[1], c[3]], gm: gm, hub: hub), "Weak to Fire and Ground.")
    }

    func testTheTieBreakIsTheBetterScore() {
        // After Xerneas, Lucario and Zamazenta (Crowned Shield) are both Fighting/Steel and add the same five types: the better score is taken.
        var a = BoxAdvice()
        a.leagues = ["x": ["gl": rating("xerneas", "Xerneas", score: 99, ivRank: 1)],
                     "l": ["gl": rating("lucario", "Lucario", score: 95, ivRank: 1)],
                     "z": ["gl": rating("zamazenta_crowned_shield", "Zamazenta (Crowned Shield)", score: 94, ivRank: 1)]]
        let c = HubTeams.candidates(league: "gl", advice: a)
        XCTAssertEqual(HubTeams.suggestedTeam(candidates: c, gm: gm, hub: hub).map(\.name), ["Xerneas", "Lucario", "Zamazenta (Crowned Shield)"])
        // And a lower-scored candidate adding more beats a higher-scored one adding less.
        a.leagues["s"] = ["gl": rating("swampert", "Swampert", score: 80, ivRank: 1)]
        XCTAssertEqual(HubTeams.suggestedTeam(candidates: HubTeams.candidates(league: "gl", advice: a), gm: gm, hub: hub).map(\.name).prefix(2), ["Xerneas", "Swampert"])
    }

    func testTheSwapNote() {
        var a = BoxAdvice()
        a.leagues = ["x": ["gl": rating("xerneas", "Xerneas", score: 99, ivRank: 1)],
                     "m": ["gl": rating("metagross", "Metagross", score: 95, ivRank: 1)],
                     "z": ["gl": rating("zamazenta_crowned_shield", "Zamazenta (Crowned Shield)", score: 94, ivRank: 1)],
                     "c": ["gl": rating("charizard", "Charizard", score: 92, ivRank: 1)],      // covers Grass and Bug: 10 types
                     "s": ["gl": rating("swampert", "Swampert", score: 90, ivRank: 1)]]       // covers Fire, Electric, Ground, Poison: 12 types
        let c = HubTeams.candidates(league: "gl", advice: a)
        func at(_ names: [String]) -> [HubTeams.Candidate] { names.map { n in c.first { $0.name == n }! } }
        // The lead is never the one to go, and the lowest-scored of the others is: Zamazenta (94) rather than Metagross (95); the better of the
        // two improving candidates is named even though the other has the higher score.
        let team = at(["Xerneas", "Metagross", "Zamazenta (Crowned Shield)"])
        XCTAssertEqual(HubTeams.coverage(team: team, gm: gm, hub: hub), 9)
        XCTAssertTrue(HubTeams.weaknessNote(team: team, candidates: c, gm: gm, hub: hub).hasSuffix("Swapping Zamazenta (Crowned Shield) for Swampert covers Fire, Electric and Ground."),
                      HubTeams.weaknessNote(team: team, candidates: c, gm: gm, hub: hub))
        // A lead that scores lowest still stays: the lowest-scored of the rest (Metagross, 95) goes.
        let odd = at(["Zamazenta (Crowned Shield)", "Metagross", "Xerneas"])
        let note = HubTeams.weaknessNote(team: odd, candidates: c, gm: gm, hub: hub)
        XCTAssertTrue(note.contains("Swapping Metagross for "), note)
        XCTAssertFalse(note.contains("Swapping Zamazenta"), note)
        // No candidate outside the team: no swap sentence.
        XCTAssertFalse(HubTeams.weaknessNote(team: team, candidates: team, gm: gm, hub: hub).contains("Swapping"))
    }
}
