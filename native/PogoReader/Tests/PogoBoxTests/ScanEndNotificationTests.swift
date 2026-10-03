import XCTest
import PogoReader

final class ScanEndNotificationTests: XCTestCase {
    func testTheTextNamesTheCountAndTheLastPokemon() {
        XCTAssertEqual(ScanEndNotification.title, "Scan stopped")
        XCTAssertEqual(ScanEndNotification.body(read: 1552, lastName: "Psyduck", lastCP: 68), "1552 Pokémon read, last: Psyduck CP 68. Say \"Go to sleep\" to stop the command, then continue from that Pokémon.")
        XCTAssertEqual(ScanEndNotification.body(read: 11, lastName: nil, lastCP: 4262), "11 Pokémon read, last: CP 4262. Say \"Go to sleep\" to stop the command, then continue from that Pokémon.")
        XCTAssertEqual(ScanEndNotification.body(read: 3, lastName: "", lastCP: nil), "3 Pokémon read. Say \"Go to sleep\" to stop the command, then continue from that Pokémon.")
        XCTAssertEqual(ScanEndNotification.body(read: 5, lastName: "Abra", lastCP: nil), "5 Pokémon read, last: Abra. Say \"Go to sleep\" to stop the command, then continue from that Pokémon.")
    }
}
