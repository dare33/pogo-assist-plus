import XCTest
@testable import PogoBox

/// Review fold 2, finding 1: every tap command the app made is checked against the current screen, whatever pace is selected.
final class TapCommandCheckTests: XCTestCase {
    func testATapCommandMadeOnAnotherScreenIsFlagged() {
        let made: [(pace: VoiceCommandFile.Pace, screen: String?)] = [(.tapNormal, "440x956 iPhone"), (.tapFast, "440x956 iPhone")]
        XCTAssertEqual(TapCommandCheck.onOtherScreens(made: made, current: "402x874 iPhone"), [.tapNormal, .tapFast])
        XCTAssertEqual(TapCommandCheck.onOtherScreens(made: made, current: "440x956 iPhone"), [])
    }

    func testARecordWithNoScreenIsFlaggedAndSwipeCommandsAreNot() {
        let made: [(pace: VoiceCommandFile.Pace, screen: String?)] = [(.tapFast, nil), (.swipeFast, "320x568 iPhone"), (.swipeNormal, nil)]
        XCTAssertEqual(TapCommandCheck.onOtherScreens(made: made, current: "440x956 iPhone"), [.tapFast])
    }

    func testRecordsUnderAnotherAccountAreChecked() {
        let accounts: [String: [(pace: VoiceCommandFile.Pace, screen: String?)]] = [
            "Main": [(.tapNormal, "440x956 iPhone")],
            "Alt": [(.tapFast, "402x874 iPhone"), (.tapNormal, "440x956 iPhone")],
        ]
        XCTAssertEqual(TapCommandCheck.onOtherScreens(accounts: accounts, current: "440x956 iPhone"), [.tapFast], "the selected account is safe, the other account's fast scan is not")
        XCTAssertEqual(TapCommandCheck.onOtherScreens(accounts: accounts, current: "402x874 iPhone"), [.tapNormal], "the 440 command is unsafe here whichever account made it")
        XCTAssertEqual(TapCommandCheck.onOtherScreens(accounts: ["Main": [(.tapNormal, "440x956 iPhone")]], current: "440x956 iPhone"), [])
    }

    func testTheWarningNamesEveryCommandAndSaysWhatToDo() throws {
        let both = try XCTUnwrap(TapCommandCheck.warning(for: [.tapNormal, .tapFast]))
        XCTAssertTrue(both.contains("\"Pogo scan\"") && both.contains("\"Pogo fast scan\""))
        XCTAssertTrue(both.contains("Do not say them on this screen"))
        XCTAssertTrue(both.contains("Settings > Accessibility > Voice Control > Commands"))
        let one = try XCTUnwrap(TapCommandCheck.warning(for: [.tapFast]))
        XCTAssertTrue(one.contains("\"Pogo fast scan\"") && !one.contains("\"Pogo scan\"") && one.contains("Do not say it"))
        XCTAssertNil(TapCommandCheck.warning(for: []))
    }
}
