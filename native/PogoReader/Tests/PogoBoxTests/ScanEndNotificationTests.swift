import XCTest
@testable import PogoReader

final class ScanEndNotificationTests: XCTestCase {
    private let sizes = [25, 50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 4000, 5000]

    func testTheStoppedTextNamesTheCountAndTheLastPokemon() {
        let n = ScanNotification.stopped(scan: 77, event: 4, read: 1552, lastName: "Psyduck", lastCP: 68)
        XCTAssertEqual(n.title, "Scan stopped"); XCTAssertEqual(n.identifier, "pogo.scan.stopped.77.4"); XCTAssertFalse(n.offersFinish)
        XCTAssertEqual(n.body, "1552 read, last Psyduck CP 68. If the command is still tapping, say \"Go to sleep\". Open Pogo Assist for what to do next.")
        XCTAssertEqual(ScanNotification.stopped(scan: 77, event: 1, read: 11, lastName: nil, lastCP: 4262).body, "11 read, last CP 4262. If the command is still tapping, say \"Go to sleep\". Open Pogo Assist for what to do next.")
        XCTAssertEqual(ScanNotification.stopped(scan: 77, event: 1, read: 3, lastName: "", lastCP: nil).body, "3 read. If the command is still tapping, say \"Go to sleep\". Open Pogo Assist for what to do next.")
    }

    func testThePausedTextSaysWhereAndWhatToDoWithAndWithoutACount() {
        let n = ScanNotification.paused(scan: 77, event: 2, read: 170, storageCount: 1684, lastName: "Stunfisk", lastCP: 902, sizes: sizes)
        XCTAssertEqual(n.title, "Scan paused"); XCTAssertTrue(n.offersFinish); XCTAssertEqual(n.identifier, "pogo.scan.paused.77.2")
        XCTAssertEqual(n.body, "Paused at Stunfisk CP 902: 170 of about 1684 read. Reopen its appraisal to carry on, or say \"Pogo scan 2000\" if the taps have stopped. It finishes by itself in 3 minutes if no new Pokémon is read.", "1,514 left: the smallest size covering it is 2000")
        XCTAssertTrue(ScanNotification.paused(scan: 77, event: 1, read: 1650, storageCount: 1684, lastName: "A", lastCP: 1, sizes: sizes).body.contains("\"Pogo scan 50\""))
        let none = ScanNotification.paused(scan: 77, event: 3, read: 51, storageCount: nil, lastName: "Abra", lastCP: 799, sizes: sizes)
        XCTAssertEqual(none.body, "Paused at Abra CP 799: 51 read. If that was not your last Pokémon, reopen its appraisal to carry on, or say the command again if the taps have stopped. It finishes by itself in 3 minutes if no new Pokémon is read.")
        XCTAssertTrue(ScanNotification.paused(scan: 77, event: 1, read: 5, storageCount: 100, lastName: nil, lastCP: nil, sizes: []).body.contains("say the command again"))
    }

    func testTheCommandNameIsTheSmallestSizeThatCoversWhatIsLeft() {
        XCTAssertEqual(ScanNotification.commandName(covering: 26, sizes: sizes), "Pogo scan 50")
        XCTAssertEqual(ScanNotification.commandName(covering: 9000, sizes: sizes), "Pogo scan 5000")
        XCTAssertNil(ScanNotification.commandName(covering: 5, sizes: []))
    }
}

extension ScanEndNotificationTests {
    func testTheIdentifierCarriesTheScanSoOneScansEventNeverReplacesAnothers() {
        let a = ScanNotification.paused(scan: 100, event: 1, read: 5, storageCount: nil, lastName: nil, lastCP: nil, sizes: [])
        let b = ScanNotification.paused(scan: 200, event: 1, read: 5, storageCount: nil, lastName: nil, lastCP: nil, sizes: [])
        XCTAssertNotEqual(a.identifier, b.identifier); XCTAssertEqual(a.scanId, 100)
        XCTAssertNotEqual(ScanNotification.stopped(scan: 100, event: 1, read: 1, lastName: nil, lastCP: nil).identifier, ScanNotification.stopped(scan: 200, event: 1, read: 1, lastName: nil, lastCP: nil).identifier)
    }

    /// M1: pause notifications are found by identifier (of one scan, or of every scan); a request to finish is honoured only for the running scan while it is paused.
    func testPauseNotificationsAreRecognisedAndAFinishRequestIsScopedToThePausedScan() {
        let a = ScanNotification.paused(scan: 77, event: 1, read: 1, storageCount: nil, lastName: nil, lastCP: nil, sizes: []).identifier
        let stopped = ScanNotification.stopped(scan: 77, event: 2, read: 1, lastName: nil, lastCP: nil).identifier
        XCTAssertTrue(ScanNotification.isPause(a)); XCTAssertTrue(ScanNotification.isPause(a, scan: 77))
        XCTAssertFalse(ScanNotification.isPause(a, scan: 7), "scan 7 is not scan 77")
        XCTAssertFalse(ScanNotification.isPause(a, scan: 78)); XCTAssertFalse(ScanNotification.isPause(stopped)); XCTAssertFalse(ScanNotification.isPause("pogo.scan.paused.770.1", scan: 77))
        XCTAssertTrue(ScanNotification.finishRequestHonoured(asked: 77, runningScan: 77, paused: true))
        XCTAssertFalse(ScanNotification.finishRequestHonoured(asked: 76, runningScan: 77, paused: true), "an old scan's notification")
        XCTAssertFalse(ScanNotification.finishRequestHonoured(asked: 77, runningScan: 77, paused: false), "not paused: a scan that carried on is not ended")
    }

    /// N1c: a finish request is kept for a short grace while the scan is momentarily not paused (a false resume and a second pause on the same stall), and still scoped to the scan.
    func testAFinishRequestWaitsBrieflyForTheNextPauseOfTheSameScan() {
        typealias V = ScanNotification.FinishRequestVerdict
        XCTAssertEqual(ScanNotification.finishRequestVerdict(asked: 77, runningScan: 77, paused: true, ageSeconds: 500), V.honour, "paused: honoured however old (it is the same scan)")
        XCTAssertEqual(ScanNotification.finishRequestVerdict(asked: 77, runningScan: 77, paused: false, ageSeconds: 3), V.keep)
        XCTAssertEqual(ScanNotification.finishRequestVerdict(asked: 77, runningScan: 77, paused: false, ageSeconds: ScanNotification.finishRequestGraceSeconds + 1), V.drop, "old and not paused: an old tap never ends a later pause")
        XCTAssertEqual(ScanNotification.finishRequestVerdict(asked: 76, runningScan: 77, paused: false, ageSeconds: 1), V.drop, "another scan's")
        XCTAssertEqual(ScanNotification.finishRequestVerdict(asked: 76, runningScan: 77, paused: true, ageSeconds: 1), V.drop)
        XCTAssertGreaterThan(ScanNotification.finishRequestGraceSeconds, 6 * 1.2 * 2, "longer than the end wait")
    }
}
