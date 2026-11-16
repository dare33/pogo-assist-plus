import XCTest
@testable import PogoBox

/// Pass 2-6, H3: one helper gives the display name from a game-master name.
final class SquadNamesTests: XCTestCase {
    func testSquadNamesWriteAMegaOrPrimalInFrontAndLeaveAShadowABracket() {
        XCTAssertEqual(SquadNames.display("Rayquaza (Mega)"), "Mega Rayquaza")
        XCTAssertEqual(SquadNames.display("Charizard (Mega X)"), "Mega Charizard X")
        XCTAssertEqual(SquadNames.display("Charizard (Mega Y)"), "Mega Charizard Y")
        XCTAssertEqual(SquadNames.display("Groudon (Primal)"), "Primal Groudon")
        XCTAssertEqual(SquadNames.display("Palkia (Shadow)"), "Palkia (Shadow)")
        XCTAssertEqual(SquadNames.display("Zamazenta (Crowned Shield)"), "Zamazenta (Crowned Shield)")
        XCTAssertEqual(SquadNames.display("Mega Gardevoir"), "Mega Gardevoir", "already in front")
        XCTAssertEqual(SquadNames.display("Gardevoir"), "Gardevoir")
    }
}
