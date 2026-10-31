import XCTest
@testable import PogoBox

/// The species types the Pogo Hub reads from the bundled game master (slices 3 and 4 derive raid counters and grunt counters from them).
final class GameMasterTypesTests: XCTestCase {
    func testSpeciesCarryTheirTypes() throws {
        let gm = try GameMaster.bundled()
        XCTAssertEqual(gm.byId["tyranitar"]?.types, ["rock", "dark"])
        XCTAssertEqual(gm.byId["pikachu"]?.types, ["electric"], "a single-typed species lists one type, never PvPoke's \"none\" filler")
        XCTAssertEqual(gm.byId["tyranitar_shadow"]?.types, ["rock", "dark"])
        XCTAssertTrue(gm.byId.values.allSatisfy { (1...2).contains($0.types.count) }, "every entry has one or two types")
    }
}
