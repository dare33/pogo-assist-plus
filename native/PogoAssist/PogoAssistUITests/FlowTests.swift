import XCTest

/// Drives the app in the simulator through the flow that needs no broadcast: first launch, sample scan, review, save, box,
/// detail, Next. Screenshots go to the folder in POGO_SCREENS (default: the temporary directory). Not part of `swift test`.
final class FlowTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testWholeFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan Pokémon"].waitForExistence(timeout: 5))
        shot("02-box-empty")

        app.buttons["More"].tap()
        let diagnostics = app.buttons["Diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        let load = app.buttons["Load sample scan"]
        if !load.waitForExistence(timeout: 8), diagnostics.exists { diagnostics.tap() }   // the menu can swallow the first tap
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        shot("03-diagnostics")
        load.tap()
        let save = app.buttons["Save to box"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "review did not appear")
        sleep(1)
        shot("04-review-top")
        app.swipeUp(); app.swipeUp()
        shot("05-review-flags")
        save.tap()
        XCTAssertTrue(app.buttons["Scan Pokémon"].waitForExistence(timeout: 15))
        sleep(1)
        shot("06-box")

        // Read the saved scan again from Settings > Scans: the review opens against the box before it; Discard changes nothing.
        app.buttons["More"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let actions = app.buttons["Scan actions"]
        for _ in 0..<6 where !(actions.exists && actions.isHittable) { app.swipeUp() }
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        shot("15-settings-scans")
        actions.tap()
        let again = app.buttons["Read again with the latest rules"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        let discard = app.buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 60), "the re-read review did not appear")
        sleep(1)
        shot("15b-reread-review")
        discard.tap()
        app.buttons["Discard scan"].tap()
        XCTAssertTrue(app.buttons["Scan Pokémon"].waitForExistence(timeout: 10))
        let toCheck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'To check'")).firstMatch
        if toCheck.exists { toCheck.tap(); shot("07-box-to-check"); app.buttons.matching(identifier: "All").firstMatch.tap() }

        app.cells.element(boundBy: 2).tap()
        sleep(2)
        shot("08-detail")
        app.swipeUp()
        shot("09-detail-advice")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Next"].tap()
        sleep(3)
        shot("10-next")
        app.swipeUp(); app.swipeUp()
        shot("11-next-gaps")

        // Round 2: a part-read CP is asked about, and "Fix a value".
        app.tabBars.buttons["Box"].tap()
        app.buttons["More"].tap()
        let diagnostics2 = app.buttons["Diagnostics"]
        XCTAssertTrue(diagnostics2.waitForExistence(timeout: 5))
        diagnostics2.tap()
        let partial = app.buttons["Load partial-read sample"]
        if !partial.waitForExistence(timeout: 8), diagnostics2.exists { diagnostics2.tap() }
        XCTAssertTrue(partial.waitForExistence(timeout: 10))
        partial.tap()
        let leave = app.buttons["Leave it out of the box"]
        XCTAssertTrue(leave.waitForExistence(timeout: 60), "the unsure section did not appear")
        sleep(1)
        shot("12-review-unsure")
        leave.tap()
        sleep(1)
        shot("12b-review-unsure-answered")
        app.buttons["Save to box"].tap()
        XCTAssertTrue(app.buttons["Scan Pokémon"].waitForExistence(timeout: 15))
        app.cells.element(boundBy: 2).tap()
        let fix = app.buttons["Fix a value"]
        XCTAssertTrue(fix.waitForExistence(timeout: 5))
        fix.tap()
        sleep(1)
        shot("13-fix-a-value")
    }

    /// The Scan screen with a storage count typed: the command estimate and the pace choices.
    func testScanCommandScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan Pokémon"].waitForExistence(timeout: 5))
        app.buttons["Scan Pokémon"].tap()
        let count = app.textFields["Optional"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        count.tap(); count.typeText("1400")
        app.buttons["Done"].tap()   // dismiss the number pad
        sleep(1)
        let name = ProcessInfo.processInfo.environment["POGO_SCAN_SHOT"] ?? "14-scan-command"
        shot(name + "-top")
        app.swipeUp()
        shot(name)
        let get = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Get the'")).firstMatch
        XCTAssertTrue(get.waitForExistence(timeout: 5))
        get.tap()
        sleep(3)
        shot(name + "-share")
    }

    /// "Make scans better" opens from the scan result and cancels. The test build can never send: its transport refuses.
    func testMakeScansBetterSheetOpensAndCancels() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-reports-enabled"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan Pokémon"].waitForExistence(timeout: 5))
        app.buttons["More"].tap()
        let diagnostics = app.buttons["Diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        let load = app.buttons["Load sample scan"]
        if !load.waitForExistence(timeout: 8), diagnostics.exists { diagnostics.tap() }
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        load.tap()
        let better = app.buttons["Make scans better"]
        XCTAssertTrue(better.waitForExistence(timeout: 60), "the button did not appear on the scan result")
        shot("16a-review-with-button")
        better.tap()
        XCTAssertTrue(app.staticTexts["Nothing is sent unless you tap Send."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'no device identifier'")).firstMatch.exists)
        shot("16-make-scans-better")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Save to box"].waitForExistence(timeout: 5), "back on the scan result")
    }
}
