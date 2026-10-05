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

    func testAppearanceSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
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
        app.buttons["mode-dark"].tap()
        XCTAssertTrue(app.buttons["mode-dark"].isSelected)
        sleep(1)
        shot("a-04-dark")
        app.buttons["help-guide"].tap()
        XCTAssertTrue(app.buttons["help-guide"].isSelected && !app.buttons["help-standard"].isSelected)
        shot("a-05-guide-me")
        app.buttons["help-essentials"].tap()
        XCTAssertTrue(app.buttons["help-essentials"].isSelected)
        shot("a-06-essentials")
        app.buttons["mode-light"].tap()
        app.buttons["accent-forest"].tap()
        sleep(1)
        shot("a-07-light-forest")
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
