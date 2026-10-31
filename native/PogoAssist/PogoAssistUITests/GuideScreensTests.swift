import XCTest

/// Settings > Appearance and the Guide me review flow (DEBUG builds only: the Guide tests use the `-uitest-seed-review` fixture).
/// Screenshots go to the folder in POGO_SCREENS (TEST_RUNNER_POGO_SCREENS for xcodebuild): light, dark and one large Dynamic Type size. Not part of `swift test`.
final class GuideScreensTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func launch(_ extra: [String], variant: String = "full") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-seed-review", variant] + extra
        app.launch()
        XCTAssertTrue(app.scrollViews["review-scroll"].waitForExistence(timeout: 90), "the seeded review did not appear")
        sleep(1)
        return app
    }

    /// "Question 3 of 13": the position and the count, read from the top bar.
    private func position(_ app: XCUIApplication) -> (n: Int, of: Int)? {
        let t = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Question '")).firstMatch
        guard t.waitForExistence(timeout: 5) else { return nil }
        let nums = t.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return nums.count == 2 ? (nums[0], nums[1]) : nil
    }

    /// "What saving does" is now the second segment, so the entry card is lower on the result: scroll to it, clear of the bottom bar, then tap it.
    private func openGuide(_ app: XCUIApplication) {
        let start = app.buttons["guide-start"]
        let h = app.windows.firstMatch.frame.height
        func clear() -> Bool { start.exists && start.isHittable && start.frame.maxY < h - 190 && start.frame.minY > 150 }
        // From wherever the result was left (the last answers leave it low down), go up first, then down to the card.
        for _ in 0..<12 where !clear() && !app.staticTexts["Scan finished at the end of your list"].exists { app.swipeDown() }
        for _ in 0..<4 where !clear() { app.swipeUp() }
        start.tap()
    }

    // MARK: Appearance

    /// Scrolls the Appearance page until the control is inside it. On the iPad the page is in Settings' form sheet, shorter than the screen, so the lower
    /// controls start below the sheet's edge: the sheet clips them, but they still report themselves hittable, and a tap there lands on the backdrop. The sheet's
    /// scroll view is the last one in the tree (the Box's list is behind it) and its frame is the visible area.
    private func reveal(_ app: XCUIApplication, _ e: XCUIElement) {
        let page = app.scrollViews.element(boundBy: app.scrollViews.count - 1)
        for _ in 0..<8 where e.exists {
            if e.frame.maxY >= page.frame.maxY - 8 { page.swipeUp() }
            else if e.frame.minY <= page.frame.minY + 8 { page.swipeDown() }
            else { break }
        }
    }

    /// Luminance (0 dark, 1 light) of the Settings sheet's own background, read from a screenshot: a point in the padding of the Mode panel, just
    /// right of the mode capsule, so it survives layout changes. The panel is white in light and #181C26 in dark. Whole-screen comparisons cannot do this
    /// job: the selected-mode capsule and the status-bar clock change the bytes whatever the colour scheme is.
    private func sheetLuminance(_ app: XCUIApplication) -> Double? {
        let auto = app.buttons["mode-auto"]
        guard auto.exists else { return nil }
        let image = XCUIScreen.main.screenshot().image
        guard let cg = image.cgImage else { return nil }
        let screenWidth = app.windows.firstMatch.frame.width
        let scale = CGFloat(cg.width) / screenWidth   // points to pixels, from the screenshot itself
        let x = Int((auto.frame.maxX + 12) * scale), y = Int(auto.frame.midY * scale)
        guard x >= 0, y >= 0, x < cg.width, y < cg.height, let px = cg.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let drew = rgba.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(px, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drew else { return nil }
        return (0.2126 * Double(rgba[0]) + 0.7152 * Double(rgba[1]) + 0.0722 * Double(rgba[2])) / 255
    }

    /// Polls until the sheet background is dark (or light), for up to `seconds`; returns the last reading.
    private func waitForSheet(_ app: XCUIApplication, dark: Bool, seconds: TimeInterval) -> Double? {
        let end = Date().addingTimeInterval(seconds)
        var last: Double?
        repeat {
            last = sheetLuminance(app)
            if let l = last, dark ? l < 0.5 : l > 0.5 { return l }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < end
        return last
    }

    func testAppearanceSettings() throws {
        // The system starts light whatever the simulator was in; set before launch so it is in place from the first frame.
        XCUIDevice.shared.appearance = .light
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]   // clears UserDefaults, so the stored mode starts at Auto
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))

        app.buttons["More"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        if !app.navigationBars["Settings"].waitForExistence(timeout: 6), settings.exists { settings.tap() }   // the menu can swallow the first tap
        let row = app.buttons["settings-appearance"]
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Settings has an Appearance row")
        shot("a-01-settings")
        row.tap()
        XCTAssertTrue(app.buttons["accent-berry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accent-blue"].isSelected, "Blue is the default accent")
        XCTAssertTrue(app.buttons["mode-auto"].isSelected, "Auto is the default mode")
        XCTAssertTrue(app.buttons["help-standard"].isSelected, "Standard is the default help level")
        shot("a-02-appearance-default")

        app.buttons["accent-berry"].tap()
        XCTAssertTrue(app.buttons["accent-berry"].isSelected && !app.buttons["accent-blue"].isSelected, "the accent changes at once")
        shot("a-03-berry")
        reveal(app, app.buttons["mode-auto"])
        let start = waitForSheet(app, dark: false, seconds: 5)
        XCTAssertNotNil(start, "the sheet background could not be sampled")
        XCTAssertGreaterThan(start ?? 0, 0.5, "Auto on a light system starts light (luminance \(start ?? -1))")

        app.buttons["mode-dark"].tap()
        XCTAssertTrue(app.buttons["mode-dark"].isSelected)
        let dark = waitForSheet(app, dark: true, seconds: 5)
        shot("a-04-dark")
        XCTAssertLessThan(dark ?? 1, 0.5, "Dark makes the open sheet dark (luminance \(dark ?? -1))")

        // Dark, then Auto with the Settings sheet still open, on a LIGHT system: the sheet must go light again.
        reveal(app, app.buttons["mode-auto"])
        app.buttons["mode-auto"].tap()
        XCTAssertTrue(app.buttons["mode-auto"].isSelected)
        let autoLight = waitForSheet(app, dark: false, seconds: 5)
        shot("a-04b-auto-system-light")
        XCTAssertGreaterThan(autoLight ?? 0, 0.5, "Dark then Auto on a light system leaves the sheet light (luminance \(autoLight ?? -1))")

        // A LIVE system change with Auto selected and the sheet open is not asserted: `XCUIDevice.shared.appearance = .dark` reached the app
        // within 10 s in every run of this test alone (24 Oct, 5 of 5, both starting appearances) and not in the full-suite run of the same day (the sample stayed light for the 10 s),
        // so the harness, not the app, is what varies. With the override back at .unspecified, following the system is the OS's job;
        // check it by hand with `xcrun simctl ui <id> appearance dark` while this screen is open.
        reveal(app, app.buttons["help-guide"])
        app.buttons["help-guide"].tap()
        XCTAssertTrue(app.buttons["help-guide"].isSelected && !app.buttons["help-standard"].isSelected)
        shot("a-05-guide-me")
        reveal(app, app.buttons["help-essentials"])
        app.buttons["help-essentials"].tap()
        XCTAssertTrue(app.buttons["help-essentials"].isSelected)
        shot("a-06-essentials")
        reveal(app, app.buttons["mode-light"])
        app.buttons["mode-light"].tap()
        reveal(app, app.buttons["accent-forest"])
        app.buttons["accent-forest"].tap()
        sleep(1)
        shot("a-07-light-forest")
    }

    /// The Mega and Restore rows' "i" buttons open their explanation inline; the Mega row itself still opens its menu.
    func testSettingsInfoRows() throws {
        for mode in ["light", "dark"] { try settingsInfoTour(["-appearance", mode], tag: mode) }
    }

    /// The same at AX3 (UICTContentSizeCategoryAccessibilityXL; M is AX1, L AX2): no word breaks mid-word, the Mega "i" stays beside its title (read from the screenshots).
    func testSettingsInfoRowsLargeText() throws {
        try settingsInfoTour(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"], tag: "ax3")
    }

    /// The same at AX5 (UICTContentSizeCategoryAccessibilityXXXL), where the Mega title is most likely to wrap.
    func testSettingsInfoRowsLargestText() throws {
        try settingsInfoTour(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], tag: "ax5", createFirst: true)
    }

    /// `createFirst`: the account is made at the normal text size and the app relaunched at the large one with the account kept (the first screen does not fit at AX5).
    private func settingsInfoTour(_ extra: [String], tag: String, createFirst: Bool = false) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"] + (createFirst ? [] : extra)
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        if createFirst {
            app.terminate()
            app.launchArguments = extra
            app.launch()
            XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 10))
        }
        app.buttons["More"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        if !app.navigationBars["Settings"].waitForExistence(timeout: 6), settings.exists { settings.tap() }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8), "Settings did not open")

        let megaInfo = app.buttons["settings-mega-info"], megaCard = app.descendants(matching: .any)["settings-mega-explainer"]
        let restoreInfo = app.buttons["settings-restore-info"], restoreCard = app.descendants(matching: .any)["settings-restore-explainer"]
        XCTAssertTrue(megaInfo.waitForExistence(timeout: 5))
        XCTAssertFalse(megaCard.exists, "the Mega explanation starts closed")
        XCTAssertEqual(megaInfo.value as? String, "Collapsed")
        shot("si-\(tag)-closed")
        megaInfo.tap()
        XCTAssertTrue(megaCard.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Normal"].exists, "a tap on the \"i\" does not open the menu")
        XCTAssertTrue(megaCard.label.contains("Which form a Pokémon's page shows first"), "card text: \(megaCard.label)")
        XCTAssertEqual(megaInfo.value as? String, "Expanded")
        shot("si-\(tag)-mega-open")
        megaInfo.tap()
        XCTAssertTrue(megaCard.waitForNonExistence(timeout: 3), "a second tap closes it")

        reveal(app, restoreInfo)
        XCTAssertTrue(restoreInfo.waitForExistence(timeout: 5))
        XCTAssertFalse(restoreCard.exists, "the restore explanation starts closed")
        XCTAssertTrue(restoreInfo.isEnabled, "the \"i\" works on the disabled row")
        XCTAssertFalse(app.buttons["Restore previous box"].isEnabled, "a fresh account has nothing to restore")
        restoreInfo.tap()
        XCTAssertTrue(restoreCard.waitForExistence(timeout: 3))
        XCTAssertTrue(restoreCard.label.contains("no earlier box"), "card text: \(restoreCard.label)")
        reveal(app, restoreCard)
        shot("si-\(tag)-restore-open")
        restoreInfo.tap()
        XCTAssertTrue(restoreCard.waitForNonExistence(timeout: 3))

        // The row itself, not the "i", opens the menu.
        let mega = app.buttons["settings-mega"]
        for _ in 0..<6 where !mega.isHittable { app.swipeDown() }
        mega.tap()
        XCTAssertTrue(app.buttons["Normal"].waitForExistence(timeout: 3) && app.buttons["Mega"].exists, "the menu's options appear")
        shot("si-\(tag)-mega-menu")
        app.buttons["Normal"].tap()   // re-selecting the current value dismisses the menu
        XCTAssertTrue(app.buttons["Normal"].waitForNonExistence(timeout: 3), "the menu closes")
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        app.terminate()
    }

    /// The choices are read by the root: launched with them, the Guide me level shows its way in to the guided questions.
    func testChoicesAreRead() throws {
        let app = launch(["-appearance", "dark", "-accent", "berry", "-helpLevel", "guide"])
        XCTAssertTrue(app.buttons["guide-start"].exists, "the Guide me level shows the way in to the guided questions")
        shot("a-08-guide-result-dark-berry")
    }

    // MARK: Guide me

    /// Answers every question one screen at a time: the first answer on even positions, the second on odd ones (the first where there is no second).
    func testGuideWalkThrough() throws {
        let app = launch(["-appearance", "light", "-helpLevel", "guide"])
        XCTAssertFalse(app.buttons["review-save"].exists, "Save is locked while questions are open")
        shot("g-00-result")
        let start = app.buttons["guide-start"]
        XCTAssertTrue(start.exists)
        XCTAssertTrue(start.label.hasPrefix("Start the "), "no answer given yet: \(start.label)")
        openGuide(app)

        guard let first = position(app) else { return XCTFail("the guided screen did not open") }
        XCTAssertEqual(first.n, 1)
        let total = first.of
        XCTAssertGreaterThan(total, 6)
        var tapped = [String]()
        func choose(_ i: Int) -> XCUIElement {
            let second = app.buttons["guide-answer-1"]
            return (i % 2 == 1 && second.exists) ? second : app.buttons["guide-answer-0"]
        }
        for i in 0..<total {
            let p = position(app)
            XCTAssertEqual(p?.n, i + 1, "the position follows the questions")
            XCTAssertEqual(p?.of, total)
            shot(String(format: "g-%02d-question", i + 1))
            if i == 0 {
                XCTAssertFalse(app.buttons["guide-back"].exists, "no Back on the first question")
                let info = app.buttons["guide-info"]
                XCTAssertTrue(info.exists)
                info.tap()
                XCTAssertTrue(app.staticTexts["Paste it into the game's storage search, look at the Pokémon, then come back."].waitForExistence(timeout: 3))
                shot("g-00b-info-open")
                info.tap()
            }
            let a = choose(i)
            XCTAssertTrue(a.waitForExistence(timeout: 5), "question \(i + 1) has answers")
            tapped.append(a.label)
            a.tap()
            if i == 2 {
                // Back goes to the question before, with the answer given marked; the same answer again moves on.
                let back = app.buttons["guide-back"]
                XCTAssertTrue(back.waitForExistence(timeout: 5))
                back.tap()
                XCTAssertEqual(position(app)?.n, 3, "Back from question 4 is question 3")
                XCTAssertEqual(app.buttons.matching(NSPredicate(format: "value == 'Your answer'")).count, 1)
                shot("g-back-answered")
                let mine = app.buttons.matching(NSPredicate(format: "label == %@", tapped[2])).firstMatch
                XCTAssertEqual(mine.value as? String, "Your answer", "question 3 shows the answer tapped")
                mine.tap()
                XCTAssertEqual(position(app)?.n, 4, "the same answer again moves on")
                sleep(1)
                continue
            }
            sleep(1)
        }
        XCTAssertTrue(app.buttons["review-save"].waitForExistence(timeout: 10), "after the last answer the result shows and Save to box is unlocked")
        XCTAssertTrue(app.buttons["review-save"].isEnabled)
        XCTAssertEqual(app.buttons["guide-start"].label.hasPrefix("Review your answers"), true)
        shot("g-99-result-answered")

        // The answers are what was tapped: reopen the questions and each one shows its answer.
        openGuide(app)
        for i in 0..<total {
            XCTAssertEqual(position(app)?.n, i + 1)
            let mine = app.buttons.matching(NSPredicate(format: "label == %@", tapped[i])).firstMatch
            XCTAssertTrue(mine.waitForExistence(timeout: 5))
            XCTAssertEqual(mine.value as? String, "Your answer", "question \(i + 1) shows the answer tapped: \(tapped[i])")
            if i == 0 { shot("g-review-first") }
            mine.tap()
            sleep(1)
        }
        XCTAssertTrue(app.buttons["review-save"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["review-save"].isEnabled, "the same answers again leave Save unlocked")
    }

    func testGuideDark() throws {
        let app = launch(["-appearance", "dark", "-accent", "berry", "-helpLevel", "guide"])
        openGuide(app)
        guard let p = position(app) else { return XCTFail("the guided screen did not open") }
        for i in 0..<min(5, p.of) {
            shot(String(format: "gd-%02d-question", i + 1))
            app.buttons["guide-answer-0"].tap()
            sleep(1)
        }
    }

    func testGuideLargeText() throws {
        let app = launch(["-appearance", "light", "-helpLevel", "guide", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        openGuide(app)
        XCTAssertNotNil(position(app))
        shot("gl-01-question")
        app.swipeUp(); shot("gl-02-question-lower")
        app.swipeUp(); shot("gl-03-question-lowest")
        app.swipeDown(); app.swipeDown()
        app.buttons["guide-answer-0"].tap()
        sleep(1)
        shot("gl-04-second")
        XCTAssertTrue(app.buttons["guide-back"].exists)
    }

    // MARK: other levels

    func testStandardKeepsTheCards() throws {
        let app = launch(["-appearance", "light", "-helpLevel", "standard"])
        XCTAssertFalse(app.buttons["guide-start"].exists, "Standard has no guided entry")
        XCTAssertTrue(app.buttons["Don't include"].firstMatch.waitForExistence(timeout: 10), "the question cards are on the result screen")
        shot("s-01-standard")
    }

    func testEssentialsKeepsTheCards() throws {
        let app = launch(["-appearance", "light", "-helpLevel", "essentials"])
        XCTAssertFalse(app.buttons["guide-start"].exists)
        XCTAssertTrue(app.buttons["Don't include"].firstMatch.waitForExistence(timeout: 10))
    }
}
