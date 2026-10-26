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
}
