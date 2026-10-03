import XCTest
@testable import PogoReader

final class ScanEndNotificationTests: XCTestCase {
    func testBodyNamesTheLastPokemonAndDoesNotClaimToKnowWhereToContinue() {
        XCTAssertEqual(ScanEndNotification.title, "Scan stopped")
        let tail = "If the command is still tapping, say \"Go to sleep\". Open Pogo Assist for what to do next."
        XCTAssertEqual(ScanEndNotification.body(read: 1552, lastName: "Psyduck", lastCP: 68), "1552 read, last Psyduck CP 68. \(tail)")
        XCTAssertEqual(ScanEndNotification.body(read: 11, lastName: nil, lastCP: 4262), "11 read, last CP 4262. \(tail)")
        XCTAssertEqual(ScanEndNotification.body(read: 3, lastName: "", lastCP: nil), "3 read. \(tail)")
        XCTAssertEqual(ScanEndNotification.body(read: 5, lastName: "Abra", lastCP: nil), "5 read, last Abra. \(tail)")
        XCTAssertFalse(ScanEndNotification.body(read: 5, lastName: "Abra", lastCP: nil).contains("continue from"))
    }
}
