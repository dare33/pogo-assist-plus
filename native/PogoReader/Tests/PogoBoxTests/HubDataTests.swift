import XCTest
@testable import PogoBox

final class HubDataTests: XCTestCase {
    func testBundledFileDecodes() throws {
        let hub = try HubData.bundled()
        XCTAssertFalse(hub.rotation.isEmpty)
        XCTAssertEqual(hub.leaders.map(\.name), ["Giovanni", "Sierra", "Cliff", "Arlo"])
        XCTAssertEqual(hub.grunts.count, 19)
        XCTAssertEqual(hub.typeChart.count, 18)
        XCTAssertTrue(hub.typeChart.values.allSatisfy { $0.count == 18 })
        XCTAssertFalse(hub.events.isEmpty)
        XCTAssertTrue(hub.rotation.contains { $0.kind == .maxMonday && $0.bosses.isEmpty })
        XCTAssertTrue(hub.leaders.allSatisfy { $0.slots.count == 3 && $0.slots.allSatisfy { !$0.isEmpty } })
    }

    func testTyranitarIsWeakestToFighting() throws {
        let hub = try HubData.bundled()
        let w = hub.weaknesses(of: ["rock", "dark"])
        XCTAssertEqual(w.first?.type, "fighting")
        XCTAssertEqual(w.first?.multiplier ?? 0, 2.56, accuracy: 0.0001)
        // The single weaknesses all tie at 1.6 and keep the chart's type order.
        XCTAssertEqual(w.map(\.type), ["fighting", "water", "grass", "ground", "bug", "steel", "fairy"])
        XCTAssertTrue(w.dropFirst().allSatisfy { abs($0.multiplier - 1.6) < 0.0001 })
        XCTAssertFalse(w.contains { $0.type == "psychic" }, "Dark is immune-class to psychic")
    }

    func testEffectiveness() throws {
        let hub = try HubData.bundled()
        XCTAssertEqual(hub.effectiveness("ground", against: ["flying"]), 0.390625, accuracy: 1e-9)
        XCTAssertEqual(hub.effectiveness("fire", against: ["grass", "steel"]), 2.56, accuracy: 1e-9)
        XCTAssertEqual(hub.effectiveness("fire", against: []), 1)
    }
}
