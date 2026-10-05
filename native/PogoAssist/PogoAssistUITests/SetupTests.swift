import XCTest

/// "Get ready to scan" and what points at it: the banner, the checklist, the one-screen steps, "My phone is set up", the gentle sheet before a scan, the
/// "N setup steps left · Finish" line, and taking the player back to the game (a recorded request in the simulator, which has neither the game nor a broadcast).
/// `-fake-notifications notAsked` makes the notification permission the same on every run. Screenshots go to POGO_SCREENS.
final class SetupTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private static let base = ["-fake-notifications", "notAsked"]

    /// A fresh install with an account, on the Scan screen with the options remembered (so the steps and the line above the button show).
    private func openScan(_ extra: [String] = [], reset: Bool = true, remember: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["-uitest-reset"] : []) + Self.base + extra
        app.launch()
        if reset {
            let field = app.textFields["Trainer name"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.tap(); field.typeText("Greg main")
            app.buttons["Create account"].tap()
        }
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 10))
        app.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan Pokémon"].waitForExistence(timeout: 5))
        if reset && remember {
            let count = app.textFields["Count"]
            XCTAssertTrue(count.waitForExistence(timeout: 5))
            for _ in 0..<3 {
                count.tap()
                if app.keyboards.firstMatch.waitForExistence(timeout: 2) { break }
            }
            usleep(400_000)
            count.typeText("1400")
            app.buttons["Hide keyboard"].tap()
            app.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts["Tap the button, then Start Broadcast"].waitForExistence(timeout: 5))
        }
        return app
    }

    /// The checklist's last row sits under the Continue button until the page is scrolled.
    private func openMore(_ app: XCUIApplication) {
        let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More about scanning'")).firstMatch
        app.swipeUp(); app.swipeUp()
        more.tap()
    }

    /// The ticks of step 4 are switches for VoiceOver.
    private func sw(_ app: XCUIApplication, _ i: Int) -> XCUIElement { app.descendants(matching: .any)["setup-switch-\(i)"].firstMatch }

    private func toggleSetUp(_ app: XCUIApplication) {
        let t = app.switches["My phone is set up"]
        reveal(app, t)
        t.tap()
    }

    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }

    private func openChecklist(_ app: XCUIApplication) {
        app.buttons["setup-banner"].tap()
        XCTAssertTrue(app.staticTexts["Get ready to scan"].waitForExistence(timeout: 5))
    }

    private func openStep(_ app: XCUIApplication, _ n: Int) {
        let row = app.buttons["setup-step-\(n)"]
        // At large text the list is longer than the screen: from the top, short slow swipes until the row can be touched.
        for _ in 0..<3 where !(row.exists && clear(app, row)) { app.swipeDown() }
        for _ in 0..<14 where !(row.exists && clear(app, row)) { app.swipeUp(velocity: .slow) }
        row.tap()
        XCTAssertTrue(app.navigationBars["Step \(n) of 6"].waitForExistence(timeout: 5))
    }

    private func confirm(_ app: XCUIApplication) { app.buttons["setup-confirm"].tap() }

    private func done(_ app: XCUIApplication, _ n: Int) -> Bool {
        let label = app.staticTexts["\(n) of 6 done"]
        for _ in 0..<4 where !label.waitForExistence(timeout: 2) { app.swipeDown() }
        return label.exists
    }

    /// The element is on screen and clear of the navigation bar and of the button pinned at the bottom (which isHittable does not account for).
    private func clear(_ app: XCUIApplication, _ e: XCUIElement) -> Bool {
        let h = app.windows.firstMatch.frame.height
        return e.frame.minY > 110 && e.frame.maxY < h - 110
    }

    /// A switch or row lower on a page: scrolls until it can be touched.
    private func reveal(_ app: XCUIApplication, _ e: XCUIElement) {
        for _ in 0..<14 where !(e.exists && clear(app, e)) { app.swipeUp(velocity: .slow) }
    }

    /// Selects paging by the voice command on "More about scanning" (the default is by hand until the commands exist), then returns to the Scan screen.
    private func chooseVoicePaging(_ app: XCUIApplication) {
        openChecklist(app)
        openMore(app)
        let voice = app.buttons["Page with the voice command"]
        XCTAssertTrue(voice.waitForExistence(timeout: 8))
        voice.tap()
        XCTAssertEqual(voice.isSelected, true)
        back(app); back(app)
        XCTAssertTrue(app.navigationBars["Scan Pokémon"].waitForExistence(timeout: 5))
    }

    // MARK: banner

    func testBannerOpensTheChecklist() throws {
        let app = openScan()
        let banner = app.buttons["setup-banner"]
        XCTAssertTrue(banner.exists)
        XCTAssertEqual(banner.label, "Important! Before you start your scan please ensure that you have opened your first Pokémon's appraisal in Pokémon GO. For first time users, set your device up to work with Pogo Assist by tapping this banner.")
        XCTAssertFalse(app.buttons["Scan setup"].exists, "the old Scan setup link is gone")
        XCTAssertTrue(app.buttons["Start scan"].isHittable, "the banner does not push the mark button off the screen")
        banner.tap()
        XCTAssertTrue(app.staticTexts["Get ready to scan"].waitForExistence(timeout: 5))
        XCTAssertTrue(done(app, 0))
        XCTAssertTrue(app.buttons["Continue with step 1"].exists)
        for n in 1...6 { XCTAssertTrue(app.buttons["setup-step-\(n)"].exists, "row \(n)") }
    }

    // MARK: the steps

    func testWalkTheSixStepsAndTheTicksPersist() throws {
        let app = openScan(["-appearance", "light"])
        openChecklist(app)
        // Step 1: notifications are not allowed yet, so the person says it is done (in the simulator the permission cannot be given).
        app.buttons["Continue with step 1"].tap()
        XCTAssertTrue(app.navigationBars["Step 1 of 6"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Allow notifications"].exists)
        XCTAssertTrue(app.images["setup-picture"].exists || app.otherElements["setup-picture"].exists)
        confirm(app)
        XCTAssertTrue(done(app, 1))
        // Step 2 cannot be confirmed before the commands are made; making them hands the file to the share sheet.
        app.buttons["Continue with step 2"].tap()
        XCTAssertTrue(app.navigationBars["Step 2 of 6"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["setup-confirm"].isEnabled)
        app.buttons["Get the commands"].tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15), "the share sheet did not appear")
        close.tap()
        XCTAssertTrue(app.buttons["setup-confirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["setup-confirm"].label, "Continue", "the app's own record says the commands were made")
        confirm(app)
        XCTAssertTrue(done(app, 2))
        for n in 3...6 {
            XCTAssertTrue(app.buttons["Continue with step \(n)"].waitForExistence(timeout: 5))
            app.buttons["Continue with step \(n)"].tap()
            XCTAssertTrue(app.navigationBars["Step \(n) of 6"].waitForExistence(timeout: 5))
            if n == 4 { for i in 0..<3 { sw(app, i).tap() } }
            confirm(app)
            XCTAssertTrue(done(app, n))
        }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continue with step'")).firstMatch.exists, "nothing is left to continue with")
        // The Scan screen no longer shows the line.
        back(app)
        XCTAssertTrue(app.buttons["Start scan"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["setup-left"].exists)
        app.terminate()
        // A relaunch keeps the ticks (no reset).
        let again = openScan(["-appearance", "light"], reset: false)
        again.buttons["setup-banner"].tap()
        XCTAssertTrue(done(again, 6), "the ticks survived the relaunch")
    }

    func testSettingsPictureAndStepWordsForEveryStep() throws {
        let app = openScan(["-appearance", "light"])
        openChecklist(app)
        for n in 1...6 {
            openStep(app, n)
            XCTAssertTrue(app.descendants(matching: .any)["setup-picture"].firstMatch.exists, "step \(n) has its picture")
            XCTAssertEqual(app.descendants(matching: .any)["setup-siri"].firstMatch.exists, n == 3 || n == 4, "the Siri line only on the Voice Control steps")
            XCTAssertTrue(app.buttons["setup-confirm"].exists)
            back(app)
        }
    }

    func testThreeSwitchStep() throws {
        let app = openScan()
        openChecklist(app)
        openStep(app, 4)
        let confirmButton = app.buttons["setup-confirm"]
        XCTAssertEqual(confirmButton.label, "Done · 0 of 3 ticked")
        XCTAssertFalse(confirmButton.isEnabled)
        sw(app, 0).tap()
        XCTAssertEqual(confirmButton.label, "Done · 1 of 3 ticked")
        sw(app, 1).tap(); sw(app, 2).tap()
        XCTAssertEqual(confirmButton.label, "Done · 3 of 3 ticked")
        XCTAssertTrue(confirmButton.isEnabled)
        // A tick can be taken back.
        sw(app, 1).tap()
        XCTAssertFalse(confirmButton.isEnabled)
        sw(app, 1).tap()
        confirm(app)
        XCTAssertTrue(done(app, 1))
    }

    func testMyPhoneIsSetUp() throws {
        let app = openScan()
        openChecklist(app)
        let toggle = app.switches["My phone is set up"]
        XCTAssertTrue(toggle.exists)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertTrue(done(app, 6))
        XCTAssertFalse(app.buttons["Continue with step 1"].exists)
        XCTAssertEqual(app.buttons["setup-step-3"].value as? String, "You said done")
        back(app)
        XCTAssertFalse(app.buttons["setup-left"].exists, "setup is done: no line above the button")
        app.buttons["setup-banner"].tap()
        toggleSetUp(app)
        XCTAssertTrue(done(app, 0), "turning it off again brings the steps back")
        XCTAssertTrue(app.buttons["Continue with step 1"].exists)
    }

    // MARK: the line and the sheet

    func testStepsLeftLineOpensTheChecklist() throws {
        let app = openScan()
        let line = app.buttons["setup-left"]
        XCTAssertTrue(line.exists)
        XCTAssertEqual(line.label, "6 setup steps left · Finish")
        line.tap()
        XCTAssertTrue(app.staticTexts["Get ready to scan"].waitForExistence(timeout: 5))
        openStep(app, 3); confirm(app)
        XCTAssertTrue(done(app, 1))
        back(app)
        XCTAssertEqual(app.buttons["setup-left"].label, "5 setup steps left · Finish")
    }

    func testGentleSheetOnlyWhenSetupIsNotDoneAndPagingIsByVoice() throws {
        let app = openScan(["-appearance", "light"])
        // Paging by hand (the default until the commands exist): no sheet, the walkthrough starts.
        app.buttons["Start scan"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Set your phone up first?"].exists)
        app.buttons["Close"].tap()
        // Paging by voice, setup not done: the sheet comes first.
        chooseVoicePaging(app)
        app.buttons["Start scan"].tap()
        XCTAssertTrue(app.staticTexts["Set your phone up first?"].waitForExistence(timeout: 5))
        shot("setup-sheet-light")
        app.buttons["setup-sheet-anyway"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 5), "Scan anyway goes on as before")
        app.buttons["Close"].tap()
        // Open Scan setup lands on the next unfinished step.
        app.buttons["Start scan"].tap()
        XCTAssertTrue(app.buttons["setup-sheet-open"].waitForExistence(timeout: 5))
        app.buttons["setup-sheet-open"].tap()
        XCTAssertTrue(app.navigationBars["Step 1 of 6"].waitForExistence(timeout: 8), "the checklist opens at the next unfinished step")
        confirm(app)
        XCTAssertTrue(done(app, 1))
        // When setup is done the sheet never appears.
        toggleSetUp(app)
        back(app)
        app.buttons["Start scan"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Set your phone up first?"].exists)
    }

    // MARK: the game

    private func logLabel(_ app: XCUIApplication) -> String { app.descendants(matching: .any)["game-open-log"].firstMatch.label }

    func testTheGameIsOpenedOnceWhenTheBroadcastGoesLive() throws {
        let app = openScan(["-appearance", "light", "-fake-scan", "-fake-scan-after", "15", "-fake-open-game", "ok"])
        XCTAssertTrue(app.staticTexts["We'll take you back to the game."].exists)
        XCTAssertEqual(logLabel(app), "0 ", "nothing is opened before a broadcast starts")
        XCTAssertTrue(app.staticTexts["Scan in progress"].waitForExistence(timeout: 40))
        sleep(4)   // the state is rewritten every second: it must not be asked again
        XCTAssertEqual(logLabel(app), "1 pokemongo://", "exactly one request, for exactly pokemongo://")
        XCTAssertFalse(app.staticTexts["game-fallback"].exists)
    }

    func testTheFallbackLineWhenTheGameCannotBeOpened() throws {
        let app = openScan(["-appearance", "light", "-fake-scan", "-fake-scan-after", "15", "-fake-open-game", "fail"])
        XCTAssertTrue(app.staticTexts["Scan in progress"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts["game-fallback"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["game-fallback"].label, "Now switch to Pokémon GO.")
        XCTAssertEqual(logLabel(app), "1 pokemongo://")
        shot("scan-scanning-fallback")
    }

    func testAScanAlreadyRunningWhenTheScreenOpensDoesNotOpenTheGame() throws {
        let app = openScan(["-fake-scan", "-fake-open-game", "ok"], remember: false)
        XCTAssertTrue(app.staticTexts["Scan in progress"].waitForExistence(timeout: 10))
        sleep(2)
        XCTAssertEqual(logLabel(app), "0 ")
    }

    // MARK: screenshots

    func testSetupScreenshots() throws {
        let runs: [(String, [String])] = [
            ("light", ["-appearance", "light"]),
            ("dark", ["-appearance", "dark"]),
            ("large", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]),
        ]
        for (name, args) in runs {
            let app = openScan(args)
            shot("setup-scan-banner-\(name)")
            openChecklist(app)
            shot("setup-checklist-0-\(name)")
            for n in 1...6 {
                openStep(app, n)
                shot("setup-step\(n)-\(name)")
                if n == 4 { for i in 0..<2 { sw(app, i).tap() }; shot("setup-step4-ticked-\(name)") }
                back(app)
            }
            // At large text the screens above are the point (each row is a screen high); the rest is looked at in light and dark.
            if name == "large" { app.terminate(); continue }
            // Two done: steps 1 and 3.
            openStep(app, 1); confirm(app)
            openStep(app, 3); confirm(app)
            XCTAssertTrue(done(app, 2))
            shot("setup-checklist-2-\(name)")
            toggleSetUp(app)
            XCTAssertTrue(done(app, 6))
            shot("setup-checklist-6-\(name)")
            toggleSetUp(app)
            openMore(app)
            XCTAssertTrue(app.staticTexts["More about scanning"].waitForExistence(timeout: 5))
            shot("setup-more-\(name)")
            back(app); back(app)
            XCTAssertTrue(app.buttons["setup-banner"].waitForExistence(timeout: 5))
            do {
                chooseVoicePaging(app)
                app.buttons["Start scan"].tap()
                XCTAssertTrue(app.staticTexts["Set your phone up first?"].waitForExistence(timeout: 5))
                shot("setup-sheet-\(name)")
            }
            app.terminate()
        }
    }
}
