import XCTest
@testable import PogoBox

final class HubDataTests: XCTestCase {
    func testBundledFileDecodes() throws {
        let hub = try HubData.bundled()
        XCTAssertFalse(hub.rotation.isEmpty)
        XCTAssertEqual(hub.leaders.map(\.name), ["Giovanni", "Sierra", "Cliff", "Arlo"])
        XCTAssertEqual(hub.grunts.count, 20)
        XCTAssertEqual(hub.grunts.filter { $0.type.isEmpty }.map(\.label), ["Mixed team", "Decoy"])
        XCTAssertEqual(hub.typeChart.count, 18)
        XCTAssertTrue(hub.typeChart.values.allSatisfy { $0.count == 18 })
        XCTAssertFalse(hub.events.isEmpty)
        XCTAssertTrue(hub.rotation.contains { $0.kind == .maxMonday && $0.bosses.isEmpty && $0.tba == true })
        XCTAssertEqual(hub.rotation.first { $0.title == "Dynamax Trails" }?.kind, .maxEvent)
        XCTAssertFalse(hub.rotation.contains { $0.kind == .other })
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

    /// One kind this app does not know yet must not make the whole file unreadable.
    func testAnUnknownRotationKindDecodesAsOther() throws {
        let json = """
        {"generated": "x", "events": [], "leaders": [], "grunts": [], "typeChart": {},
         "rotation": [
           {"from": "2026-11-01", "to": "2026-11-02", "kind": "5star", "title": "A", "bosses": [{"name": "Palkia", "speciesId": "palkia", "types": ["water", "dragon"]}], "note": "", "source": ""},
           {"from": "2026-11-03", "to": "2026-11-04", "kind": "somethingnew", "title": "B", "bosses": [], "note": "", "source": "", "tba": true}]}
        """
        let hub = try JSONDecoder().decode(HubData.self, from: Data(json.utf8))
        XCTAssertEqual(hub.rotation.map(\.kind), [.fiveStar, .other])
        XCTAssertEqual(hub.rotation[1].tba, true); XCTAssertNil(hub.rotation[0].tba); XCTAssertNil(hub.rotation[0].bosses[0].shadow)
    }

    func testEffectiveness() throws {
        let hub = try HubData.bundled()
        XCTAssertEqual(hub.effectiveness("ground", against: ["flying"]), 0.390625, accuracy: 1e-9)
        XCTAssertEqual(hub.effectiveness("fire", against: ["grass", "steel"]), 2.56, accuracy: 1e-9)
        XCTAssertEqual(hub.effectiveness("fire", against: []), 1)
    }
}
