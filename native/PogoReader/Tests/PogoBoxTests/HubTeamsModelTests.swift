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

    // MARK: Rocket

    func testGiovanniOnTheFixture() throws {
        let b = try advice().builds
        let giovanni = hub.leaders.first { $0.name == "Giovanni" }!
        // Slot 1 is Persian (Normal): the only Fighting counter in the box is Lucario, which still has to Mega evolve.
        let team = HubTeams.leaderTeam(leader: giovanni, builds: b, gm: gm, hub: hub)
        XCTAssertEqual(team.map(\.name), ["Lucario", "Staraptor", "Xerneas"])
        XCTAssertEqual(team.map(\.gapText), ["gap: mega evolve Lucario", nil, "gap: power up Xerneas"])
        XCTAssertEqual(team.map(\.isBuilt), [false, true, false])
        // Lucario hits all three of slot 2 (Fighting beats Kangaskhan and Rhyperior, Steel beats Rhyperior) but is not built, so the built Staraptor
        // (Flying beats Machamp) wins; with Staraptor taken, Lucario is the answer to be built.
        XCTAssertEqual(HubTeams.counter(for: giovanni.slots[1], builds: b, gm: gm, hub: hub).name, "Staraptor")
        XCTAssertEqual(HubTeams.counter(for: giovanni.slots[1], builds: b, gm: gm, hub: hub, excluding: ["staraptor"]), .toBuild(b[0]))
        // Once it is built, slot 1 takes it as a built counter.
        var built = b; built[0].steps = []
        XCTAssertEqual(HubTeams.leaderTeam(leader: giovanni, builds: built, gm: gm, hub: hub).first, .built(built[0]))
    }

    func testASlotWithNoCounterReadsDash() throws {
        let cliff = hub.leaders.first { $0.name == "Cliff" }!   // slot 1 Cubone (Ground): nothing in the fixture box is Water, Grass or Ice
        let team = HubTeams.leaderTeam(leader: cliff, builds: try advice().builds, gm: gm, hub: hub)
        XCTAssertEqual(team.first, HubTeams.Counter.none)
        XCTAssertEqual(team.first?.name, "—")
        XCTAssertNil(team.first?.gapText)
    }

    func testTheCounterThatHitsMostOptionsWinsAndTiesPreferRocket() throws {
        let b = try advice().builds
        let base = b[3]
        let rhyperiorMachamp = hub.leaders.first { $0.name == "Giovanni" }!.slots[1]   // Kangaskhan, Rhyperior, Machamp
        let water = variant(base, id: "swampert", name: "Swampert", areas: ["Raids"], tier: "S", score: 1)     // Water hits Rhyperior (Ground/Rock)
        let fighting = variant(base, id: "lucario", name: "Lucario", areas: ["Raids"], tier: "B", score: 1, built: true)   // Fighting hits Kangaskhan, Rhyperior
        XCTAssertEqual(HubTeams.counter(for: rhyperiorMachamp, builds: [water, fighting], gm: gm, hub: hub).name, "Lucario", "hits two options to one")
        let rocketTwin = variant(fighting, id: "hariyama", name: "Hariyama", areas: ["Rocket"], tier: "B", score: 0.5)
        XCTAssertEqual(HubTeams.counter(for: rhyperiorMachamp, builds: [fighting, rocketTwin], gm: gm, hub: hub).name, "Hariyama", "a tie goes to the Rocket area first")
        XCTAssertEqual(HubTeams.counter(for: rhyperiorMachamp, builds: [variant(base, areas: ["Max"], built: true)], gm: gm, hub: hub), HubTeams.Counter.none, "Max alone is not a Rocket area")
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
        // Grass grunt: Staraptor (Flying) is built.
        XCTAssertEqual(c("grass"), .built(a.builds[3]))
        // Normal grunt: Lucario (Fighting) still has to Mega evolve.
        XCTAssertEqual(c("normal"), .toBuild(a.builds[0]))
        XCTAssertEqual(c("normal").gapText, "gap: mega evolve Lucario")
        // Built beats unbuilt even when the unbuilt one is better ranked: Staraptor (Flying) and Lucario (Fighting) both answer Bug.
        XCTAssertEqual(c("bug"), .built(a.builds[3]))
        // Nothing, with no gap either.
        XCTAssertEqual(c("fire", gaps: []), HubTeams.Counter.none)
        // The pupitar case from the design: a build still to evolve.
        let pupitar = variant(a.builds[3], id: "tyranitar", name: "Tyranitar", areas: ["Rocket"], tier: "S", steps: [.init(kind: "evolve", to: "Tyranitar")])
        var named = pupitar; named.title = "Pupitar"
        XCTAssertEqual(c("psychic", [named]).gapText, "gap: evolve Pupitar")   // Dark answers Psychic
        // Rocket area beats Raids at the same standing.
        let raid = variant(a.builds[3], id: "tyranitar", name: "Tyranitar", areas: ["Raids"], tier: "S", score: 99, built: true)
        let rocket = variant(a.builds[3], id: "honchkrow", name: "Honchkrow", areas: ["Rocket"], tier: "B", score: 1, built: true)
        XCTAssertEqual(c("psychic", [raid, rocket]).name, "Honchkrow")
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

    private func rating(_ id: String, _ name: String, score: Double, ivRank: Int, over: Bool = false, selfName: String? = nil) -> BoxAdvice.LeagueRating {
        let option = BoxAdvice.LeagueRating.Option(speciesId: id, name: name, isSelf: selfName == nil, strength: .init(score: score, rank: 5, of: 200), moves: nil,
                                                    iv: .init(rank: ivRank, pct: 97.5, rankPct: 99, level: 25, cp: 1490), overCap: over)
        guard let selfName else { return .init(options: [option]) }
        return .init(options: [.init(speciesId: "x", name: selfName, isSelf: true), option], pick: 1)
    }

    func testTheFixtureHasMasterLeagueCandidatesOnly() throws {
        let a = try advice()
        XCTAssertTrue(HubTeams.candidates(league: "gl", advice: a).isEmpty, "no fixture copy reaches the B floor (88) in Great League")
        XCTAssertTrue(HubTeams.candidates(league: "ul", advice: a).isEmpty)
        let ml = HubTeams.candidates(league: "ml", advice: a)
        XCTAssertEqual(ml.map(\.name), ["Xerneas", "Zamazenta (Crowned Shield)"])
        XCTAssertEqual(ml.map(\.score), [94.0, 92.2])
        XCTAssertEqual(ml.map(\.ivRank), [249, 339])
        XCTAssertEqual(ml.map(\.tier), ["S", "S"])
        XCTAssertEqual(ml.map(\.fromText), [nil, "From Zamazenta (Hero)"])
        XCTAssertEqual(ml[0].subText, "#249 · 95.8%")
        let team = HubTeams.suggestedTeam(candidates: ml, gm: gm, hub: hub)
        XCTAssertEqual(team.map(\.name), ["Xerneas", "Zamazenta (Crowned Shield)"], "only two candidates, so a team of two")
        // Fairy: Fighting, Dragon, Dark. Fighting: Normal, Ice, Rock, Dark, Steel. Steel: Ice, Rock, Fairy. Eight different types.
        XCTAssertEqual(HubTeams.coverage(team: team, gm: gm, hub: hub), 8)
        XCTAssertEqual(HubTeams.weaknessNote(team: team, candidates: ml, gm: gm, hub: hub), "No shared weakness.")
        XCTAssertTrue(HubTeams.others(candidates: ml, team: team).isEmpty)
    }

    func testCandidatesFilterSortAndKeepTheBestCopyPerSpecies() {
        var a = BoxAdvice()
        a.leagues = ["c1": ["gl": rating("azumarill", "Azumarill", score: 96, ivRank: 40)],
                     "c2": ["gl": rating("azumarill", "Azumarill", score: 96, ivRank: 10)],        // the better copy of the same species
                     "c3": ["gl": rating("medicham", "Medicham", score: 96, ivRank: 30)],           // ties on score; IV rank 30 is worse than Azumarill's 10
                     "c4": ["gl": rating("skarmory", "Skarmory", score: 87.9, ivRank: 1)],          // under the B floor
                     "c5": ["gl": rating("registeel", "Registeel", score: 99, ivRank: 1, over: true)],   // past the cap
                     "c6": ["gl": rating("swampert", "Swampert", score: 91, ivRank: 7, selfName: "Mudkip")]]
        let c = HubTeams.candidates(league: "gl", advice: a)
        XCTAssertEqual(c.map(\.name), ["Azumarill", "Medicham", "Swampert"])
        XCTAssertEqual(c.map(\.entryId), ["c2", "c3", "c6"])
        XCTAssertEqual(c.map(\.tier), ["S", "S", "A"])
        XCTAssertEqual(c[2].fromText, "From Mudkip")
        XCTAssertEqual(HubTeams.tier(score: 88), "B"); XCTAssertEqual(HubTeams.tier(score: 90), "A"); XCTAssertEqual(HubTeams.tier(score: 92), "S"); XCTAssertEqual(HubTeams.tier(score: 87.99), "")
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
        let pair = [c[1], c[3]]
        XCTAssertEqual(HubTeams.weaknessNote(team: pair, gm: gm, hub: hub), "Weak to Fire and Ground.")
    }

    func testTheSwapNote() {
        var a = BoxAdvice()
        a.leagues = ["x": ["gl": rating("xerneas", "Xerneas", score: 99, ivRank: 1)],
                     "z": ["gl": rating("zamazenta_crowned_shield", "Zamazenta (Crowned Shield)", score: 95, ivRank: 1)],
                     "m": ["gl": rating("metagross", "Metagross", score: 94, ivRank: 1)],
                     "s": ["gl": rating("swampert", "Swampert", score: 90, ivRank: 1)]]
        let c = HubTeams.candidates(league: "gl", advice: a)
        // A hand-picked team (not the greedy one) so a swap helps: Xerneas, Zamazenta, Metagross cover Fighting, Dragon, Dark, Normal, Ice, Rock, Steel, Fairy, Poison = 9.
        let team = [c[0], c[1], c[2]]
        XCTAssertEqual(HubTeams.coverage(team: team, gm: gm, hub: hub), 9)
        let note = HubTeams.weaknessNote(team: team, candidates: c, gm: gm, hub: hub)
        // Swampert covers Fire, Ground, Electric as well as Rock, Poison, Steel: swapping out the lower-ranked of the two non-lead members gains the most.
        XCTAssertTrue(note.hasSuffix("Swapping Metagross for Swampert covers Fire, Electric and Ground."), note)
    }
}
