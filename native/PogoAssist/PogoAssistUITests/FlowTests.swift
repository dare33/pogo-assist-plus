import XCTest

/// Drives the app in the simulator through the flow that needs no broadcast: first launch, sample scan, review, save, box,
/// detail, Next. Screenshots go to the folder in POGO_SCREENS (default: the temporary directory). Not part of `swift test`.
final class FlowTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// Box rows are buttons now, not list cells: open a species (the third, or the last there is) and then its first Pokémon.
    private func openPokemon(_ app: XCUIApplication, species: Int = 2) {
        let rows = app.buttons.matching(identifier: "species-row")
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 10), "the box shows no species")
        rows.element(boundBy: min(species, rows.count - 1)).tap()
        let first = app.buttons.matching(identifier: "pokemon-row").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "the species list shows no Pokémon")
        first.tap()
    }

    /// The tab bar's scan button replaced the old "Scan Pokémon" button on the Box screen.
    func testWholeFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 15))
        sleep(1)
        shot("06-box")

        // Read the saved scan again from Settings > Scans: the review opens against the box before it; Discard changes nothing.
        app.buttons["More"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        if !app.navigationBars["Settings"].waitForExistence(timeout: 6), settings.exists { settings.tap() }   // the menu can swallow the first tap
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8), "Settings did not open")
        let actions = app.buttons["Scan actions"]
        for _ in 0..<6 where !(actions.exists && actions.isHittable) { app.swipeUp() }
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        shot("15-settings-scans")
        actions.tap()
        let again = app.buttons["Read again with the latest rules"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        let discard = app.buttons["Discard"]
        if !discard.waitForExistence(timeout: 20), again.exists { again.tap() }   // the menu can swallow a tap
        if !discard.waitForExistence(timeout: 60) { shot("15-debug-reread") }
        XCTAssertTrue(discard.exists, "the re-read review did not appear")
        sleep(1)
        shot("15b-reread-review")
        discard.tap()
        app.buttons["Discard scan"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 10))
        let toCheck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'To check'")).firstMatch
        if toCheck.exists { toCheck.tap(); shot("07-box-to-check"); app.buttons["All"].tap() }

        openPokemon(app)
        sleep(2)
        shot("08-detail")
        app.swipeUp()
        shot("09-detail-advice")
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()
        app.buttons["Next"].tap()
        sleep(3)
        shot("10-next")
        app.swipeUp(); app.swipeUp()
        shot("11-next-gaps")

        // Round 2: a part-read CP is asked about, and "Fix a value".
        app.buttons["Box"].tap()
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
        let screenHeight = app.windows.firstMatch.frame.height
        for _ in 0..<6 where !(leave.isHittable && leave.frame.maxY < screenHeight - 170) { app.swipeUp() }   // clear of the Save bar at the bottom
        leave.tap()
        sleep(1)
        XCTAssertTrue(app.buttons["Save to box"].isEnabled, "the answer was not taken")
        shot("12b-review-unsure-answered")
        app.buttons["Save to box"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 15))
        openPokemon(app)
        let fix = app.buttons["Fix a value"]
        for _ in 0..<5 where !(fix.exists && fix.isHittable) { app.swipeUp() }   // the detail is longer now: scroll to the button
        XCTAssertTrue(fix.waitForExistence(timeout: 5))
        fix.tap()
        sleep(1)
        shot("13-fix-a-value")
    }

    /// The Scan screen with a storage count typed: the command to say and the one-time set file.
    func testScanCommandScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        app.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan Pokémon"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next"].exists, "the scan screen hides the floating tab bar")
        // The first scan opens in Edit: type the count, then Done brings the steps back.
        let count = app.textFields["Count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        count.tap(); count.typeText("1400")
        app.buttons["Hide keyboard"].tap()   // dismiss the number pad
        app.buttons["Done"].tap()
        let name = ProcessInfo.processInfo.environment["POGO_SCAN_SHOT"] ?? "14-scan-command"
        XCTAssertTrue(app.staticTexts["Tap the button, then Start Broadcast"].waitForExistence(timeout: 5))
        shot(name + "-top")
        // The setup lists are on the Scan setup screen. The lists are lazy: scroll until the element is on screen.
        // Both directions: on a smaller screen the lazy list drops what is scrolled out of sight, and the elements sit in no fixed order.
        app.buttons["Scan setup"].tap()
        XCTAssertTrue(app.navigationBars["Scan setup"].waitForExistence(timeout: 5))
        func reveal(_ e: XCUIElement, up: Bool = true) {
            var n = 0
            while !e.waitForExistence(timeout: 1.5), n < 8 { if up { app.swipeUp() } else { app.swipeDown() }; n += 1 }
            n = 0
            while !e.exists, n < 16 { if up { app.swipeDown() } else { app.swipeUp() }; n += 1; _ = e.waitForExistence(timeout: 1.0) }
        }
        let attention = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Attention Aware'")).firstMatch
        reveal(attention, up: false)
        XCTAssertTrue(attention.exists, "the setup list names Attention Aware")
        let sharing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Screen Sharing'")).firstMatch
        reveal(sharing, up: false)
        XCTAssertTrue(sharing.exists, "the setup list names the Screen Sharing notification setting")
        app.swipeUp()
        shot(name)
        // the command to say, as it is spoken: digits without a thousands separator
        reveal(app.staticTexts["Say: Pogo scan 1500"])
        XCTAssertTrue(app.staticTexts["Say: Pogo scan 1500"].waitForExistence(timeout: 5), "1,400 Pokémon is covered by the 1,500 command")
        reveal(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Go to sleep'")).firstMatch)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Go to sleep'")).firstMatch.waitForExistence(timeout: 5), "the warning says how to stop a command")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'cannot be stopped'")).firstMatch.exists)
        let get = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Get the'")).firstMatch
        reveal(get)
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
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
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

    /// The UI v1 component gallery (DEBUG builds, `-ui-gallery`): light, dark, a non-default accent and a large
    /// text size, scrolled top to bottom, so the components can be looked at. Screenshots go to POGO_SCREENS.
    func testGalleryScreens() throws {
        let runs: [(String, [String])] = [
            ("light", ["-appearance", "light"]),
            ("dark", ["-appearance", "dark"]),
            ("berry", ["-appearance", "light", "-accent", "berry"]),
            ("large-text", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]),
        ]
        for (name, args) in runs {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-gallery"] + args
            app.launch()
            let scroll = app.scrollViews["gallery-scroll"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 10), "the gallery did not open")
            XCTAssertTrue(app.buttons["Scan"].exists && app.buttons["Box"].exists && app.buttons["Next"].exists, "the tab bar's buttons are labelled Box, Scan, Next")
            let pages = name == "light" || name == "large-text" ? 14 : 9
            for i in 0..<pages {
                shot("gallery-\(name)-\(String(format: "%02d", i))")
                scroll.swipeUp(velocity: .slow)
            }
            app.terminate()
        }
    }
}
