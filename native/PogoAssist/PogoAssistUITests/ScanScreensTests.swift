import XCTest

/// The UI v1 Scan screen in the simulator: ready with remembered options, Edit, the first scan (opens in Edit), the guide ("?"), Scan setup,
/// and the scanning / paused states (DEBUG launch arguments `-fake-scan` and `-fake-scan-paused` write the shared broadcast state, as the sample scan does).
/// The system broadcast picker cannot start a broadcast in the simulator, so starting is not driven here (starting never opens the guide). Screenshots go to POGO_SCREENS.
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

    /// The first time the Scan screen is opened the guide comes by itself, with "Don't show this step again" and no Close; the last page's button only closes it, and the
    /// card behind it is on the options. The next time neither comes. Hiding a page keeps it out of the "?".
    func testTheGuideOpensByItselfTheFirstTime() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-first-walk", "-appearance", "light"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        app.buttons["Scan"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 5), "the guide opens by itself on the first visit")
        XCTAssertTrue(app.descendants(matching: .any)["Don't show this step again"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Close"].exists, "no Close at the top")
        shot("scan-first-walk")
        app.descendants(matching: .any)["Don't show this step again"].firstMatch.tap()
        app.buttons["Next"].tap()
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForExistence(timeout: 3))
        app.buttons["OK, I've got it. Let's scan!"].tap()
        XCTAssertTrue(app.staticTexts["Scan options"].waitForExistence(timeout: 5), "behind it, the first visit's options")
        XCTAssertTrue(app.staticTexts["Put in the number of Pokémon in your storage and scan them all."].exists)
        shot("scan-first-options")
        // The "?" skips the page that was hidden.
        app.buttons["Show the steps again"].tap()
        XCTAssertTrue(app.staticTexts["Step 1 of 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tap the button, then Start Broadcast"].exists)
        app.buttons["Next"].tap()
        app.buttons["OK, I've got it. Let's scan!"].tap()
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments = ["-first-walk", "-appearance", "light"]
        again.launch()
        XCTAssertTrue(again.buttons["Scan"].waitForExistence(timeout: 10))
        again.buttons["Scan"].tap()
        XCTAssertTrue(again.staticTexts["Scan options"].waitForExistence(timeout: 5))
        XCTAssertFalse(again.staticTexts["Step 1 of 2"].waitForExistence(timeout: 3), "only the first visit")
        XCTAssertFalse(again.staticTexts["Step 1 of 3"].exists, "only the first visit")
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

    /// Replaces what a number field holds: the caret is put at the end of the text first, then it is deleted back.
    private func retype(_ field: XCUIElement, _ text: String) {
        for _ in 0..<3 {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
            if XCUIApplication().keyboards.firstMatch.waitForExistence(timeout: 2) { break }
        }
        usleep(400_000)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + text)
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
            // Paging by hand (the default until the commands exist): six steps, step 2 (Voice Control) left out, step 5 swipes by hand.
            XCTAssertTrue(app.staticTexts["In Pokémon Go, open the appraisal of the Pokémon you want to start at."].exists)
            XCTAssertFalse(app.staticTexts["Make sure Voice Control is on. Not sure? Say \"Wake up\"."].exists)
            XCTAssertTrue(app.staticTexts["Choose your scan options above."].exists)
            XCTAssertTrue(app.staticTexts["Tap the Pogo Assist button, then Start Broadcast, then close that sheet. We'll take you back to the game."].exists)
            XCTAssertTrue(app.staticTexts["Back in the game, swipe from one Pokémon to the next yourself."].exists)
            XCTAssertTrue(app.staticTexts["When the scan ends, come back to Pogo Assist to meet your new Pokémon or export your collection."].exists)
            shot("scan-ready-\(name)")
            // Edit swaps the steps for the options and dims Start.
            app.buttons["Scan Options"].tap()
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
            // The guide from the "?": three pages; the last button only closes it.
            app.buttons["Show the steps again"].tap()
            XCTAssertTrue(app.staticTexts["Step 1 of 3"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Open your first Pokémon's appraisal"].exists)
            XCTAssertFalse(app.buttons["Close"].exists)
            shot("scan-walk-1-\(name)")
            app.buttons["Next"].tap()
            XCTAssertTrue(app.staticTexts["Step 2 of 3"].waitForExistence(timeout: 3))
            shot("scan-walk-2-\(name)")
            app.buttons["Next"].tap()
            XCTAssertTrue(app.staticTexts["Step 3 of 3"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["Page through your Pokémon by hand"].exists, "by hand the page stays as it was")
            XCTAssertFalse(app.buttons["Start scanning"].exists)
            shot("scan-walk-3-\(name)")
            app.buttons["OK, I've got it. Let's scan!"].tap()
            XCTAssertTrue(app.buttons["Show the steps again"].waitForExistence(timeout: 3), "the button only closed the guide")
            app.terminate()
        }
    }

    /// The guide's third page by voice, as one text (over the 128 characters a string subscript allows, so by predicate).
    private func voiceLine(_ app: XCUIApplication, _ n: Int) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "Say \"Pogo scan \(n)\". Then leave the phone alone until the scan is done! Note- the number will change depending on your chosen scan!")).firstMatch
    }

    private let step1 = "In Pokémon Go, open the appraisal of the Pokémon you want to start at."

    /// The options card is the first view of every fresh open of the Scan screen, with or without a remembered count; Done then shows the steps.
    func testTheOptionsAreTheFirstViewAndDoneShowsTheSteps() throws {
        for (name, args) in [("light", ["-appearance", "light"]), ("dark", ["-appearance", "dark"])] {
            let app = openScan(args)
            XCTAssertTrue(app.staticTexts["Scan options"].exists, "the options are open before any tap")
            XCTAssertTrue(app.textFields["Count"].exists)
            XCTAssertFalse(app.staticTexts[step1].exists, "the steps wait behind the options")
            shot("scan-editor-first-\(name)")
            rememberOptions(app)
            XCTAssertTrue(app.staticTexts[step1].exists, "Done shows the steps")
            XCTAssertTrue(app.buttons["Scan Options"].exists)
            // Left and opened again with the count remembered: still the options first.
            app.terminate()
            let again = XCUIApplication()
            again.launchArguments = args
            again.launch()
            XCTAssertTrue(again.buttons["Scan"].waitForExistence(timeout: 10))
            again.buttons["Scan"].tap()
            XCTAssertTrue(again.staticTexts["Scan options"].waitForExistence(timeout: 5), "the options first even with a count remembered")
            XCTAssertFalse(again.staticTexts[step1].exists)
            again.terminate()
        }
    }

    /// "Show less" folds the six steps away and keeps the Scan Options row and the mark button (which moves down with the card); the choice survives a relaunch.
    func testTheStepsFoldAwayAndStayFolded() throws {
        for (name, args) in [("light", ["-appearance", "light"]), ("dark", ["-appearance", "dark"])] {
            let app = openScan(args)
            rememberOptions(app)
            let toggle = app.buttons["scan-steps-toggle"]
            XCTAssertEqual(toggle.label, "Show less")
            XCTAssertTrue(app.staticTexts[step1].exists)
            XCTAssertTrue(app.staticTexts["Tap the Pogo Assist button, then Start Broadcast, then close that sheet. We'll take you back to the game."].exists)
            let before = app.buttons["Start scan"].frame.minY
            shot("scan-steps-expanded-\(name)")
            toggle.tap()
            XCTAssertTrue(app.buttons["Show more"].waitForExistence(timeout: 3))
            XCTAssertFalse(app.staticTexts[step1].exists, "the steps are folded away")
            XCTAssertTrue(app.buttons["Scan Options"].exists, "the options row stays")
            sleep(1)
            XCTAssertGreaterThan(app.buttons["Start scan"].frame.minY, before + 40, "the mark button moves down as the card shrinks")
            shot("scan-steps-collapsed-\(name)")
            app.terminate()
            // A relaunch without -uitest-reset keeps it folded; the options open first, Done shows the card.
            let again = XCUIApplication()
            again.launchArguments = args
            again.launch()
            XCTAssertTrue(again.buttons["Scan"].waitForExistence(timeout: 10))
            again.buttons["Scan"].tap()
            XCTAssertTrue(again.buttons["Done"].waitForExistence(timeout: 5))
            again.buttons["Done"].tap()
            XCTAssertTrue(again.buttons["Show more"].waitForExistence(timeout: 5), "still folded after a relaunch")
            XCTAssertFalse(again.staticTexts[step1].exists)
            again.buttons["Show more"].tap()
            XCTAssertTrue(again.staticTexts[step1].waitForExistence(timeout: 3), "Show more brings the steps back")
            XCTAssertEqual(again.buttons["scan-steps-toggle"].label, "Show less")
            again.terminate()
        }
    }

    /// Pages by voice from "More about scanning" (six steps) and picks Add and update, as on the owner's phone (greg-r3-2.png).
    private func voiceAddAndUpdate(_ app: XCUIApplication) {
        rememberOptions(app)
        app.buttons["setup-banner"].tap()
        app.swipeUp(); app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More about scanning'")).firstMatch.tap()
        let voice = app.buttons["Page with the voice command"]
        for _ in 0..<10 where !voice.exists { app.swipeUp() }
        voice.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Scan Options"].waitForExistence(timeout: 5))
        app.buttons["Scan Options"].tap()
        app.buttons["Add and update"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["scan-steps-toggle"].waitForExistence(timeout: 5))
    }

    /// "Show less" is fully on screen without scrolling, with the setup banner showing, six steps and Add and update (Greg, 7 Oct 2026: "can we resize slightly so its fully visible?").
    func testShowLessIsFullyVisibleWithoutScrolling() throws {
        for (name, args) in [("light", ["-appearance", "light"]), ("dark", ["-appearance", "dark"])] {
            let app = openScan(args)
            voiceAddAndUpdate(app)
            XCTAssertTrue(app.staticTexts["Make sure Voice Control is on. Not sure? Say \"Wake up\"."].exists, "six steps")
            XCTAssertTrue(app.buttons["setup-banner"].exists, "setup is not done")
            sleep(1)
            let toggle = app.buttons["scan-steps-toggle"]
            let window = app.windows.firstMatch.frame
            // The test phone has no command set, so two warning paragraphs sit in the card that the owner's phone does not show,: take their height out.
            var warnings: CGFloat = 0
            for start in ["The command set has not been made", "The scan ends by itself only with the commands"] {
                let t = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", start)).firstMatch
                if t.exists { warnings += t.frame.height + 10 }
            }
            // Nor does it show "n setup steps left" once setup is done; the banner stays either way.
            let left = app.buttons["setup-left"]
            if left.exists { warnings += left.frame.height + 12 }
            print("TOGGLE-MEASURE \(name) toggle.maxY=\(toggle.frame.maxY) warnings=\(warnings) window=\(window.size) mark=\(app.buttons["Start scan"].frame)")
            // Only a tall phone (the Pro Max class, 956 pt) has room for all of it: a shorter one scrolls, and the toggle is still reachable.
            shot("scan-steps-expanded-voice-\(name)")
            if window.height >= 940 {
                // (isHittable cannot be asserted: this phone's two warning paragraphs, taken out of the sum above, can still push the row below the screen.)
                XCTAssertLessThanOrEqual(toggle.frame.maxY - warnings, window.maxY - 20, "Show less is cut off at the bottom")
            } else {
                for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
                XCTAssertTrue(toggle.isHittable, "a short phone scrolls to it")
            }
            app.terminate()
        }
    }

    /// Switching Full scan / Add and update moves nothing but the fields: the card's top edge and the mark button stay put.
    func testSwitchingTheKindMovesNothingButTheFields() throws {
        let app = openScan(["-appearance", "light"])
        rememberOptions(app)
        app.buttons["Scan Options"].tap()
        XCTAssertTrue(app.textFields["Count"].waitForExistence(timeout: 3))
        sleep(1)
        let mark = app.buttons["Start scan"], title = app.staticTexts["Scan options"], done = app.buttons["Done"]
        let (m, t, d) = (mark.frame.minY, title.frame.minY, done.frame.minY)
        shot("scan-editor-full-light")
        app.buttons["Add and update"].tap()
        // Paging by hand (the default here) has no number to ask for, so only the one-line text shows.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Scan part of your storage'")).firstMatch.waitForExistence(timeout: 3))
        sleep(1)
        XCTAssertEqual(mark.frame.minY, m, accuracy: 1)
        XCTAssertEqual(title.frame.minY, t, accuracy: 1)
        XCTAssertEqual(done.frame.minY, d, accuracy: 1)
        XCTAssertFalse(app.textFields["Count"].exists, "the hidden section is not offered")
        shot("scan-editor-add-light")
    }

    /// "appraisal" in step 1 opens the picture of the game's appraisal screen, inside the app.
    func testTheAppraisalWordOpensThePicture() throws {
        for (name, args) in [("light", ["-appearance", "light"]), ("dark", ["-appearance", "dark"])] {
            let app = openScan(args)
            rememberOptions(app)
            let word = app.links["appraisal"].firstMatch
            XCTAssertTrue(word.waitForExistence(timeout: 3), "the word is a link in step 1")
            word.tap()
            let sheet = app.descendants(matching: .any)["appraisal-sheet"].firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["The appraisal screen"].exists)
            XCTAssertTrue(app.images["The appraisal screen in Pokémon GO, shown for a Cinderace"].exists)
            XCTAssertEqual(app.state, .runningForeground, "nothing was opened outside the app")
            sleep(1)
            shot("scan-appraisal-sheet-\(name)")
            app.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts["Scan options"].exists == false)
            XCTAssertTrue(app.buttons["scan-steps-toggle"].waitForExistence(timeout: 3))
            app.terminate()
        }
    }

    /// The guide's third page by voice: the command and "Then leave the phone alone until the scan is done!" read as one line in one style.
    func testTheGuideThirdPageByVoiceIsOneStyle() throws {
        for (name, args) in [("light", ["-appearance", "light"]), ("dark", ["-appearance", "dark"])] {
            let app = openScan(args)
            rememberOptions(app)
            app.buttons["setup-banner"].tap()
            app.swipeUp(); app.swipeUp()
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More about scanning'")).firstMatch.tap()
            let voice = app.buttons["Page with the voice command"]
            for _ in 0..<10 where !voice.exists { app.swipeUp() }
            voice.tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["Show the steps again"].tap()
            app.buttons["Next"].tap(); app.buttons["Next"].tap()
            XCTAssertTrue(voiceLine(app, 2000).waitForExistence(timeout: 3))
            shot("scan-walk-3-voice-\(name)")
            app.buttons["OK, I've got it. Let's scan!"].tap()
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
        XCTAssertTrue(app.staticTexts["Make sure Voice Control is on. Not sure? Say \"Wake up\"."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Back in the game, say \"Pogo scan 2000\"."].exists)
        shot("scan-ready-command")
        // The guide's third page shows that size, with the note in the same text.
        app.buttons["Show the steps again"].tap()
        app.buttons["Next"].tap(); app.buttons["Next"].tap()
        XCTAssertTrue(voiceLine(app, 2000).waitForExistence(timeout: 3))
        shot("scan-walk-3-size")
        app.buttons["OK, I've got it. Let's scan!"].tap()
    }

    /// Add and update asks how many to scan (remembered; empty means 200) and the steps and the guide's third page name the smallest command that covers it.
    func testAddAndUpdateNumberNamesTheCommand() throws {
        let app = openScan(["-appearance", "light"])
        rememberOptions(app)
        app.buttons["setup-banner"].tap()
        app.swipeUp(); app.swipeUp()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More about scanning'")).firstMatch.tap()
        let voice = app.buttons["Page with the voice command"]
        for _ in 0..<10 where !voice.exists { app.swipeUp() }
        voice.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Scan Options"].waitForExistence(timeout: 5))
        app.buttons["Scan Options"].tap()
        XCTAssertFalse(app.textFields["200"].exists, "a Full scan has no such field")
        app.buttons["Add and update"].tap()
        let number = app.textFields["200"]
        XCTAssertTrue(number.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["How many Pokémon to scan?"].exists)
        shot("scan-options-add-and-update")
        app.buttons["Done"].tap()
        // Nothing typed: the default, 200.
        XCTAssertTrue(app.staticTexts["Back in the game, say \"Pogo scan 200\"."].waitForExistence(timeout: 3))
        app.buttons["Show the steps again"].tap()
        app.buttons["Next"].tap(); app.buttons["Next"].tap()
        XCTAssertTrue(voiceLine(app, 200).waitForExistence(timeout: 3))
        shot("scan-walk-3-placeholder")
        app.buttons["OK, I've got it. Let's scan!"].tap()
        // 260 is covered by the 300 command.
        app.buttons["Scan Options"].tap()
        retype(app.textFields["200"], "260")
        app.buttons["Hide keyboard"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Back in the game, say \"Pogo scan 300\"."].waitForExistence(timeout: 3))
        shot("scan-ready-add-and-update")
        app.buttons["Show the steps again"].tap()
        app.buttons["Next"].tap(); app.buttons["Next"].tap()
        XCTAssertTrue(voiceLine(app, 300).waitForExistence(timeout: 3))
        app.buttons["OK, I've got it. Let's scan!"].tap()
        // 200 is itself a size; the number is remembered.
        app.buttons["Scan Options"].tap()
        retype(app.textFields["200"], "200")
        app.buttons["Hide keyboard"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Back in the game, say \"Pogo scan 200\"."].waitForExistence(timeout: 3))
        // Above the largest command: say so.
        app.buttons["Scan Options"].tap()
        retype(app.textFields["200"], "6000")
        app.buttons["Hide keyboard"].tap()
        shot("scan-options-above-largest")
        XCTAssertTrue(app.staticTexts["The largest command covers 5,000 Pokémon."].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Back in the game, say \"Pogo scan 5000\"."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'The largest command covers 5,000 Pokémon. Scan the first'")).firstMatch.exists)
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
