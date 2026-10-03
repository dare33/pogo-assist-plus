import XCTest
@testable import PogoReader

final class ScanEndNotificationTests: XCTestCase {
    private let sizes = [25, 50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 4000, 5000]

    func testTheStoppedTextNamesTheCountAndTheLastPokemon() {
        let n = ScanNotification.stopped(event: 4, read: 1552, lastName: "Psyduck", lastCP: 68)
        XCTAssertEqual(n.title, "Scan stopped"); XCTAssertEqual(n.identifier, "pogo.scan.stopped.4"); XCTAssertFalse(n.offersFinish)
        XCTAssertEqual(n.body, "1552 read, last Psyduck CP 68. If the command is still tapping, say \"Go to sleep\". Open Pogo Assist for what to do next.")
        XCTAssertEqual(ScanNotification.stopped(event: 1, read: 11, lastName: nil, lastCP: 4262).body, "11 read, last CP 4262. If the command is still tapping, say \"Go to sleep\". Open Pogo Assist for what to do next.")
        XCTAssertEqual(ScanNotification.stopped(event: 1, read: 3, lastName: "", lastCP: nil).body, "3 read. If the command is still tapping, say \"Go to sleep\". Open Pogo Assist for what to do next.")
    }

    func testThePausedTextSaysWhereAndWhatToDoWithAndWithoutACount() {
        let n = ScanNotification.paused(event: 2, read: 170, storageCount: 1684, lastName: "Stunfisk", lastCP: 902, sizes: sizes)
        XCTAssertEqual(n.title, "Scan paused"); XCTAssertTrue(n.offersFinish); XCTAssertEqual(n.identifier, "pogo.scan.paused.2")
        XCTAssertEqual(n.body, "Paused at Stunfisk CP 902: 170 of about 1684 read. Reopen its appraisal to carry on, or say \"Pogo scan 2000\" if the taps have stopped.", "1,514 left: the smallest size covering it is 2000")
        XCTAssertTrue(ScanNotification.paused(event: 1, read: 1650, storageCount: 1684, lastName: "A", lastCP: 1, sizes: sizes).body.contains("\"Pogo scan 50\""))
        let none = ScanNotification.paused(event: 3, read: 51, storageCount: nil, lastName: "Abra", lastCP: 799, sizes: sizes)
        XCTAssertEqual(none.body, "Paused at Abra CP 799: 51 read. If that was not your last Pokémon, reopen its appraisal to carry on, or say the command again if the taps have stopped.")
        XCTAssertTrue(ScanNotification.paused(event: 1, read: 5, storageCount: 100, lastName: nil, lastCP: nil, sizes: []).body.contains("say the command again"))
    }

    func testTheCommandNameIsTheSmallestSizeThatCoversWhatIsLeft() {
        XCTAssertEqual(ScanNotification.commandName(covering: 26, sizes: sizes), "Pogo scan 50")
        XCTAssertEqual(ScanNotification.commandName(covering: 9000, sizes: sizes), "Pogo scan 5000")
        XCTAssertNil(ScanNotification.commandName(covering: 5, sizes: []))
    }
}
