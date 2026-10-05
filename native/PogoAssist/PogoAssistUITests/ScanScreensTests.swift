import XCTest

/// The UI v1 Scan screen in the simulator: ready with remembered options, Edit, the first scan (opens in Edit), the walkthrough steps, Scan setup,
/// and the scanning / paused states (DEBUG launch arguments `-fake-scan` and `-fake-scan-paused` write the shared broadcast state, as the sample scan does).
/// The system broadcast picker cannot start a broadcast in the simulator, so starting is not driven here. Screenshots go to POGO_SCREENS.
final class ScanScreensTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func openScan(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"] + extra
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        app.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan Pokémon"].waitForExistence(timeout: 5))
        return app
    }

    /// The first time the Scan screen is opened the steps come by themselves, with "Don't show this step again"; the next time they do not.
    func testTheStepsOpenByThemselvesTheFirstTime() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-first-walk", "-appearance", "light"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        app.buttons["Scan"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 5), "the steps open by themselves on the first visit")
        XCTAssertTrue(app.descendants(matching: .any)["Don't show this step again"].firstMatch.exists)
        shot("scan-first-walk")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Scan options"].waitForExistence(timeout: 5), "behind them, the first scan's options")
        XCTAssertTrue(app.staticTexts["Put in the number of Pokémon in your storage and scan them all."].exists)
        shot("scan-first-options")
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments = ["-first-walk", "-appearance", "light"]
        again.launch()
        XCTAssertTrue(again.buttons["Scan"].waitForExistence(timeout: 10))
        again.buttons["Scan"].tap()
        XCTAssertTrue(again.staticTexts["Scan options"].waitForExistence(timeout: 5))
        XCTAssertFalse(again.staticTexts["Step 1 of 3"].waitForExistence(timeout: 3), "only the first visit")
    }

    /// The first scan for the account opens in Edit; type the options and press Done.
    private func rememberOptions(_ app: XCUIApplication) {
        let count = app.textFields["Count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5), "the first scan opens in Edit")
        type(count, "1698")
        app.buttons["Hide keyboard"].tap()
        type(app.textFields["Eggs"], "12")
        app.buttons["Hide keyboard"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Full scan · 1,698 in storage"].waitForExistence(timeout: 5))
    }

    /// Taps a field until it has the keyboard (the panel can move while the keyboard rises), then types.
    private func type(_ field: XCUIElement, _ text: String) {
        for _ in 0..<3 {
            field.tap()
            if XCUIApplication().keyboards.firstMatch.waitForExistence(timeout: 2) { break }
        }
        usleep(400_000)
        field.typeText(text)
    }

    private func runs() -> [(String, [String])] {
        [("light", ["-appearance", "light"]),
         ("dark", ["-appearance", "dark"]),
         ("large", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])]
    }

    func testReadyEditFirstScanAndWalkthrough() throws {
        for (name, args) in runs() {
            let app = openScan(args)
            // First scan: nothing remembered, so the panel is in Edit and the button is dimmed.
            XCTAssertTrue(app.staticTexts["Scan options"].exists)
            XCTAssertFalse(app.buttons["Start scan"].isEnabled, "Start is dimmed while a Full scan has no count")
            shot("scan-first-scan-\(name)")
            rememberOptions(app)
            XCTAssertTrue(app.buttons["Start scan"].isEnabled)
            XCTAssertTrue(app.staticTexts["Tap the button, then Start Broadcast"].exists)
            XCTAssertTrue(app.staticTexts["We'll take you back to the game."].exists)
            shot("scan-ready-\(name)")
            // Edit swaps the steps for the options and dims Start.
            app.buttons["Edit scan options"].tap()
            XCTAssertTrue(app.staticTexts["Scan options"].waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["Start scan"].isEnabled)
            shot("scan-edit-\(name)")
            type(app.textFields["Eggs"], "99")
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Type a whole number of eggs'")).firstMatch.waitForExistence(timeout: 3))
            app.buttons["Hide keyboard"].tap()
            shot("scan-edit-problem-\(name)")
            type(app.textFields["Eggs"], String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "12")
            app.buttons["Hide keyboard"].tap()
            app.buttons["Done"].tap()
            // The walkthrough: three steps.
            app.buttons["Start scan"].tap()
            XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Open your first Pokémon's appraisal"].exists)
            shot("scan-walk-1-\(name)")
            app.buttons["Next"].tap()
            XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: 3))
            shot("scan-walk-2-\(name)")
            app.buttons["Next"].tap()
            XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["Start scanning"].exists)
            shot("scan-walk-3-\(name)")
            if name == "light" {
                // Hide step 1; the next time the walk starts at step 2 of 2. The ? brings it back.
                app.buttons["Close"].tap()
                app.buttons["Start scan"].tap()
                app.descendants(matching: .any)["Don't show this step again"].firstMatch.tap()
                app.buttons["Close"].tap()
                app.buttons["Start scan"].tap()
                XCTAssertTrue(app.staticTexts["Step 1 of 2"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Tap the button, then Start Broadcast"].exists)
                app.buttons["Close"].tap()
                app.buttons["Show the steps again"].tap()
                XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 5))
                app.buttons["Close"].tap()
            }
            app.terminate()
        }
    }

    /// The old "Scan setup" page is now "Get ready to scan" (SetupTests) and "More about scanning": the paging choice moved there, and the Scan screen names the command.
    func testMoreAboutScanningAndPaging() throws {
        let app = openScan(["-appearance", "light"])
        rememberOptions(app)
        app.buttons["setup-banner"].tap()
        XCTAssertTrue(app.staticTexts["Get ready to scan"].waitForExistence(timeout: 5))
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More about scanning'")).firstMatch
        app.swipeUp(); app.swipeUp()   // the last row sits under the Continue button until the page is scrolled
        more.tap()
        XCTAssertTrue(app.staticTexts["More about scanning"].waitForExistence(timeout: 5))
        shot("scan-more-top")
        // Paging by voice (the command set is not made in a test): the Scan screen then names the command, and says the set is missing.
        let voice = app.buttons["Page with the voice command"]
        for _ in 0..<10 where !voice.exists { app.swipeUp() }
        voice.tap()
        shot("scan-more-voice")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["In the game, say"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["\"Pogo scan 2000\""].exists)
        shot("scan-ready-command")
    }

    /// The extension published that the CP is covered (`-fake-cp covered`), or that it was and has cleared (`-fake-cp cleared`, `-fake-cp-stretches N`).
    func testCoveredCpPanel() throws {
        func panel(_ app: XCUIApplication) -> String {
            let p = app.descendants(matching: .any)["cp-covered-panel"].firstMatch
            XCTAssertTrue(p.waitForExistence(timeout: 10))
            return p.label
        }
        let covered = openScan(["-appearance", "light", "-fake-scan", "-fake-cp", "covered"])
        XCTAssertEqual(panel(covered), "Something may be covering the CP, From Pidgey on, several Pokémon in a row showed no CP. A banner or an alarm is probably over the top of the screen: clear it in the game. The scan keeps going.")
        shot("scan-cp-covered-light")
        covered.terminate()
        let dark = openScan(["-appearance", "dark", "-fake-scan", "-fake-cp", "covered"])
        _ = panel(dark)
        shot("scan-cp-covered-dark")
        dark.terminate()
        let cleared = openScan(["-appearance", "light", "-fake-scan", "-fake-cp", "cleared"])
        XCTAssertEqual(panel(cleared), "The CP was covered for a while, It started at Pidgey, right after Rattata CP 412. When the scan ends, the result shows which ones to check or read again.")
        shot("scan-cp-cleared-light")
        cleared.terminate()
        let twice = openScan(["-appearance", "light", "-fake-scan", "-fake-cp", "cleared", "-fake-cp-stretches", "2"])
        XCTAssertTrue(panel(twice).hasPrefix("The CP was covered 2 times, The latest time started at Pidgey"))
        shot("scan-cp-cleared-twice-light")
        twice.terminate()
        let large = openScan(["-appearance", "light", "-fake-scan", "-fake-cp", "covered", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        _ = panel(large)
        shot("scan-cp-covered-large")
        large.terminate()
        // No fields, no panel.
        let none = openScan(["-fake-scan"])
        XCTAssertTrue(none.staticTexts["Scan in progress"].waitForExistence(timeout: 10))
        XCTAssertFalse(none.descendants(matching: .any)["cp-covered-panel"].exists)
    }

    func testScanningStates() throws {
        for (name, args) in runs() {
            let app = openScan(args + ["-fake-scan"])
            XCTAssertTrue(app.staticTexts["Scan in progress"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '742'")).firstMatch.exists)
            shot("scan-scanning-\(name)")
            app.terminate()
        }
        let paused = openScan(["-appearance", "light", "-fake-scan-paused"])
        XCTAssertTrue(paused.buttons["Finish now"].firstMatch.waitForExistence(timeout: 10))
        shot("scan-paused-light")
    }
}
