import XCTest
@testable import PogoBox
import PogoReader

/// The confirmation round's six items (G1 to G6), one test each at least.
final class ConfirmationFoldTests: XCTestCase {
    private typealias A = PokemonActivities
    private let gm = P23.gm

    private func rocketCtx(builds: [BoxAdvice.Build], copy: BoxEntry) -> HubContext {
        P23.ctx(builds: builds, entries: [copy]) { h in
            h.grunts = [HubData.Grunt(type: "grass", quote: "", label: "")]
            h.leaders = [HubData.Leader(name: "Giovanni", since: "2026-01-01", slots: [[HubData.Boss(name: "Persian", speciesId: "persian", types: ["normal"], shadow: nil)],
                                                                                    [HubData.Boss(name: "Rhyperior", speciesId: "rhyperior", types: ["rock"], shadow: nil)]], source: "")]
        }
    }

    // MARK: G1

    func testARocketMemberWithABuildIsShownEvenWhenItBeatsNoGruntType() {
        let ev = P23.entry("ev", "eevee")
        let planned = rocketCtx(builds: [P23.build("ev", "vaporeon", areas: ["Rocket"], built: false)], copy: ev)
        let r = A.summary(copy: ev, ctx: planned).first { $0.activity == .rocket }!
        XCTAssertEqual(r.verdict, .planned)
        XCTAssertEqual(r.lines.map(\.plain), ["Beats Giovanni slot 2"], "Water hits the Rock option, not the Grass grunt")
        // Without the build: the member beating the most grunt types; Flareon and Glaceon tie on one, so the later evolution.
        let none = A.summary(copy: ev, ctx: rocketCtx(builds: [], copy: ev)).first { $0.activity == .rocket }!
        XCTAssertEqual(none.lines, [A.Line(lead: nil, text: "As Glaceon", score: nil, icons: ["grass"])])
        XCTAssertEqual(none.verdict, .beatsGrunts(1))
    }

    func testALeaderOnlyMemberIsShownOnlyWhenNoMemberBeatsAGruntType() {
        let cm = P23.entry("cm", "charmander")
        let ctx = P23.ctx(entries: [cm]) { h in
            h.grunts = [HubData.Grunt(type: "water", quote: "", label: "")]
            h.leaders = [HubData.Leader(name: "L", since: "2026-01-01", slots: [[HubData.Boss(name: "A", speciesId: "a", types: ["grass"], shadow: nil)],
                                                                              [HubData.Boss(name: "B", speciesId: "b", types: ["steel"], shadow: nil)]], source: "")]
        }
        let r = A.summary(copy: cm, ctx: ctx).first { $0.activity == .rocket }!
        XCTAssertEqual(r.lines.map(\.plain), ["Beats L slots 1, 2"]); XCTAssertEqual(r.verdict, .notUsed)
        let sn = P23.entry("sn", "snorlax")
        XCTAssertEqual(A.summary(copy: sn, ctx: P23.ctx(entries: [sn])).first { $0.activity == .rocket }?.lines.map(\.plain), ["No type advantage on any grunt"])
    }

    // MARK: G2

    func testThePlaceableTestsOfMaxAndRocketUnderAvailable() {
        let ctx = P23.ctx(builds: [P23.build("a", "blissey", areas: ["Max"], powerUp: false), P23.build("b", "blissey", areas: ["Max"]),
                                   P23.build("c", "togekiss", areas: ["Rocket"], powerUp: false), P23.build("d", "togekiss", areas: ["Raids"]), P23.build("g", "snorlax", areas: ["Gym"])])
        let max = HubSquads.placeable(screen: .max, mode: .available, ctx: ctx)
        XCTAssertEqual([max("a", "Tank"), max("b", "Tank"), max("g", "Tank")], [true, true, false], "S1: an evolution-only Max build and a plain one are placed; a copy with no Max build is not")
        let rocket = HubSquads.placeable(screen: .rocket, mode: .available, ctx: ctx)
        XCTAssertEqual([rocket("c", "Counter"), rocket("d", "Counter"), rocket("g", "Counter")], [true, true, false], "Rocket counts the Raids area too")
        let best = HubSquads.placeable(screen: .max, mode: .best, ctx: ctx)
        XCTAssertTrue(best("a", "Tank")); XCTAssertTrue(HubSquads.placeable(screen: .rocket, mode: .best, ctx: ctx)("c", "Counter"))
        // The Max squad uses it: the evolution-only pick is placed under Available too (S1).
        let candidates = HubSquads.maxCandidates(row: P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("charizard", types: ["fire"])]), mode: .best,
                                                 ctx: P23.ctx(builds: [P23.build("b", "blissey", areas: ["Max"])], table: P23.table([P23.tierEntry("max", "Tanks and healers", "S", "blissey", role: "Tank")])))
        var slots = HubSquads.defaultMaxSlots(); slots[0].pick = "a"
        XCTAssertEqual(HubSquads.maxSquad(slots: slots, candidates: candidates, placeable: max).map(\.entryId), ["a", nil, nil])
        XCTAssertEqual(HubSquads.maxSquad(slots: slots, candidates: candidates, placeable: best).map(\.entryId), ["a", nil, nil])
    }

    // MARK: G3 and G4

    func testAMegaRouteBuildIsTheBestOfItsTypeWhenTheMegaEntryOutranksTheRest() {
        let table = P23.table([P23.tierEntry("raids", "Water", "A", "swampert"), P23.tierEntry("raids", "Water", "S", "swampert_mega", mega: true)])
        let builds = [P23.build("plain", "swampert", areas: ["Raids"]), P23.build("m", "swampert", areas: ["Raids"], powerUp: false, viaMega: true)]
        let best = A.bestRaidBuilds(ctx: P23.ctx(builds: builds, table: table))["water"]
        XCTAssertEqual(best?.build.entryId, "m"); XCTAssertEqual(best?.tier, "S")
    }

    func testNonTypeRaidSectionsAreReadOneWayEverywhere() {
        let typed = P23.tierEntry("raids", "Water", "B", "swampert"), untyped = P23.tierEntry("raids", "Tiers", "S", "swampert")
        let own = ["water", "ground"]
        XCTAssertEqual(HubRaidsModel.raidTypes([typed, untyped], speciesTypes: own), ["water"])
        XCTAssertEqual(HubRaidsModel.entryTypes(untyped, in: [typed, untyped], speciesTypes: own), [], "typed entries exist: the untyped one stands for nothing")
        XCTAssertEqual(HubRaidsModel.entryTypes(typed, in: [typed, untyped], speciesTypes: own), ["water"])
        XCTAssertEqual(HubRaidsModel.raidTypes([untyped], speciesTypes: own), ["water", "ground"])
        XCTAssertEqual(HubRaidsModel.entryTypes(untyped, in: [untyped], speciesTypes: own), own, "only untyped entries: the species' types")
        let row = P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("charizard", types: ["fire"])])
        let c = HubSquads.raidCandidates(row: row, mode: .best, ctx: P23.ctx(builds: [P23.build("s", "swampert", areas: ["Raids"])], table: P23.table([typed, untyped])))
        XCTAssertEqual(c.map(\.tier), ["B"], "the untyped S entry does not lift the tier")
        let s = P23.entry("s", "swampert")
        XCTAssertEqual(A.raidCards(copy: s, ctx: P23.ctx(entries: [s], table: P23.table([typed, untyped]), rotation: [row])).map { "\($0.type) \($0.tier)" }, ["water B"])
    }

    // MARK: G5

    func testAMaxBuildThatOnlyWaitsOnTheDynamaxMarkHasNoUpgradeMark() {
        let copy = P23.entry("b", "blissey", dynamax: nil)
        var waiting = P23.build("b", "blissey", areas: ["Max"]); waiting.steps = [.init(kind: "needsDynamaxCopy")]
        let table = P23.table([P23.tierEntry("max", "Tanks and healers", "S", "blissey", role: "Tank and healer")])
        let row = A.summary(copy: copy, ctx: P23.ctx(builds: [waiting], entries: [copy], table: table)).first { $0.activity == .max }!
        XCTAssertEqual(row.verdict, .needsDynamax)
        XCTAssertEqual(row.mark, A.Mark.none)
        // Work left on another build still shows as an upgrade, with its label.
        let work = P23.build("b", "blissey", areas: ["Max"], built: false, targetLevel: 40)
        guard case .upgrade(_, _, let label) = A.summary(copy: copy, ctx: P23.ctx(builds: [waiting, work], entries: [copy], table: table)).first(where: { $0.activity == .max })!.mark else { return XCTFail() }
        XCTAssertEqual(label, "Upgrade available: power up to level 40")
    }

    // MARK: G6

    func testTheMidSentenceStepsOfTheUpgradeLabelStartInLowerCase() {
        var b = P23.build("a", "vaporeon", areas: ["Raids"], built: false)
        b.steps = [.init(kind: "evolve", to: "Vaporeon"), .init(kind: "powerUp", toLevel: 30, areas: ["raids"]), .init(kind: "megaEvolve"), .init(kind: "cdMove")]
        XCTAssertEqual(HubSquads.upgradeLabel(b), "Upgrade available: evolve to Vaporeon + power up to level 30 + mega evolve + Community Day move")
    }
}
