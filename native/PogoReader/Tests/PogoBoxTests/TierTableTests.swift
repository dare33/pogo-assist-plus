import XCTest
@testable import PogoBox

/// The bundled tier tables as the Hub reads them.
final class TierTableTests: XCTestCase {
    func testCountsPerAreaAndKind() throws {
        let t = try TierTable.bundled()
        XCTAssertEqual(t.entries.count, 319)
        let counts = Dictionary(grouping: t.entries, by: { "\($0.area)/\($0.kind)" }).mapValues(\.count)
        XCTAssertEqual(counts, ["raids/pve-by-type": 169, "gym/defence": 14, "rocket/attacker": 22, "gl/pvp": 25, "ul/pvp": 25, "ml/pvp": 25, "max/max": 39])
        XCTAssertEqual(Set(t.entries.map(\.tier)), ["S", "A", "B"])
    }

    func testRaidsEntriesAreSectionedByAttackingType() throws {
        let t = try TierTable.bundled()
        // Kartana is Grass/Steel but the table lists it for Grass and for Fighting.
        XCTAssertEqual(t.entries(for: "kartana", area: "raids").map { "\($0.section) \($0.tier)" }, ["Grass A", "Fighting B"])
        // Lucario is Fighting/Steel; the Mega is the S entry under Fighting.
        XCTAssertEqual(t.entries(for: "lucario_mega", area: "raids").map { "\($0.section) \($0.tier)" }, ["Fighting S"])
        XCTAssertTrue(try XCTUnwrap(t.entries(for: "lucario_mega", area: "raids").first).flags.mega)
        XCTAssertEqual(t.entries(for: "moltres", area: "raids").map(\.section), ["Fire", "Flying"])
        XCTAssertTrue(t.entries(for: "kartana", area: "max").isEmpty)
    }

    func testMaxEntriesCarryTheirRole() throws {
        let t = try TierTable.bundled()
        let blissey = try XCTUnwrap(t.entries(for: "blissey", area: "max").first)
        XCTAssertEqual(blissey.role, "Tank and healer"); XCTAssertEqual(blissey.section, "Tanks and healers"); XCTAssertEqual(blissey.tier, "S")
        XCTAssertEqual(t.entries(for: "zamazenta_crowned_shield", area: "max").first?.role, "Tank")
        XCTAssertEqual(t.entries(for: "snorlax", area: "max").map(\.role), [nil, "Per-boss tank", "Healer"])
        XCTAssertNil(t.entries(for: "gengar", area: "max").first?.role, "an attacker has no role")
        XCTAssertEqual(t.entries(for: "gengar", area: "max").first?.section, "Attackers")
    }

    func testAPvpEntry() throws {
        let t = try TierTable.bundled()
        let x = try XCTUnwrap(t.entries(for: "xerneas", area: "ml").first)
        XCTAssertEqual(x.kind, "pvp"); XCTAssertEqual(x.tier, "S"); XCTAssertEqual(x.section, "Tiers")
        XCTAssertEqual(t.entries(for: "xerneas", area: "raids").map(\.section), ["Fairy"])
    }
}
