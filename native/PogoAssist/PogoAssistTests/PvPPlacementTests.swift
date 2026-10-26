import XCTest
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// A PvP pick under Available is placed by the option the screen shows for the ranking in use (Classic pick, or the experimental member under Pogo Assist).
final class PvPPlacementTests: XCTestCase {
    typealias R = BoxAdvice.LeagueRating
    private func ctx() throws -> HubContext {
        let me = R.Option(speciesId: "eevee", name: "Eevee", isSelf: true, strength: .init(score: 85, rank: 50, of: 1152), overCap: false)
        let evo = R.Option(speciesId: "flareon", name: "Flareon", isSelf: false, strength: .init(score: 91, rank: 5, of: 1152), overCap: false)
        var advice = BoxAdvice(builds: [], gaps: [], duplicates: [], unresolved: [])
        // Classic shows the copy itself; the Pogo Assist ranking moves to the evolution.
        advice.leagues = ["a": ["ul": R(options: [me, evo], pick: 0, experimental: 1)], "b": ["ul": R(options: [me], pick: 0)]]
        return HubContext(advice: advice, entries: [], gm: try GameMaster.bundled(), hub: try HubData.bundled(), table: try TierTable.bundled(), today: "2026-10-26")
    }

    func testAvailablePlacesTheOptionTheRankingShows() throws {
        let c = try ctx()
        let classic = PvPPlacement.placeable(league: "ul", mode: .available, pogoAssist: false, ctx: c)
        let assist = PvPPlacement.placeable(league: "ul", mode: .available, pogoAssist: true, ctx: c)
        XCTAssertTrue(classic("a", "Lead"), "Classic shows the copy itself")
        XCTAssertFalse(assist("a", "Lead"), "the Pogo Assist ranking shows an evolution, which is work")
        XCTAssertTrue(assist("b", "Lead"), "a copy with no other option is itself under both")
        XCTAssertFalse(classic("missing", "Lead"), "a copy with no rating is not placed")
    }

    func testBestPlacesAnything() throws {
        let c = try ctx()
        XCTAssertTrue(PvPPlacement.placeable(league: "ul", mode: .best, pogoAssist: true, ctx: c)("a", "Lead"))
    }

    private func candidate(_ id: String, _ species: String, score: Double, roles: [HubSquads.PvpRole]) -> HubSquads.PvpCandidate {
        let o = R.Option(speciesId: species, name: species.capitalized, isSelf: true, strength: .init(score: score, rank: 1, of: 1152), overCap: false)
        return HubSquads.PvpCandidate(candidate: HubTeams.Candidate(entryId: id, option: o, copyTitle: species, score: score, ivRank: 10, ivPct: 95, built: true), roles: roles)
    }

    /// GO Battle League allows one copy of a species in a squad.
    func testASquadNeverHoldsTwoCopiesOfOneSpecies() {
        let a = candidate("a", "azumarill", score: 95, roles: [.lead]), b = candidate("b", "azumarill", score: 94, roles: [.safeSwap, .closer])
        let c = candidate("c", "umbreon", score: 90, roles: [.safeSwap])
        let species = ["a": "azumarill", "b": "azumarill", "c": "umbreon"]
        let filled = PvPPlacement.squad(slots: HubSquads.defaultPvpSlots(), candidates: [a, b, c], placeable: { _, _ in true }, species: { species[$0] })
        XCTAssertEqual(filled.map(\.entryId), ["a", "c", nil], "the second Azumarill is neither a Closer nor a fallback")
        // A kept pick wins over a new suggestion of its species.
        var slots = HubSquads.defaultPvpSlots(); slots[2].pick = "b"
        let kept = PvPPlacement.squad(slots: slots, candidates: [a, b, c], placeable: { _, _ in true }, species: { species[$0] })
        XCTAssertEqual(kept.map(\.entryId), ["c", nil, "b"], "the kept Closer stays; the Lead falls back to another species and no second Azumarill is suggested")
        // The picker of another slot does not offer a species the squad holds.
        let ex = PvPPlacement.excluded(by: filled, editing: 2, candidates: [a, b, c], species: { species[$0] })
        XCTAssertTrue(ex.contains("b") && ex.contains("a") && ex.contains("c"))
        let ex1 = PvPPlacement.excluded(by: filled, editing: 0, candidates: [a, b, c], species: { species[$0] })
        XCTAssertFalse(ex1.contains("a"), "the slot's own Pokémon stays listed")
        XCTAssertTrue(ex1.contains("c"))
    }

    func testTheWeaknessLineReadsTheMembersShown() throws {
        let hub = try HubData.bundled()
        // Two members hit by Rock (Fire and Flying), one that is not: a kept pick outside the candidates counts like the others.
        XCTAssertEqual(PvPPlacement.sharedWeakness(memberTypes: [["fire"], ["flying"], ["water"]], hub: hub).hasPrefix("Weak to"), true)
        XCTAssertEqual(PvPPlacement.sharedWeakness(memberTypes: [["fire"]], hub: hub), "No shared weakness.")
    }
}
