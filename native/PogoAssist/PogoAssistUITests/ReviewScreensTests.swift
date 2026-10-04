import XCTest

/// The UI v1 Review screens (DEBUG builds only: they use the `-uitest-seed-review` fixture, a small box and scanned rows run through the real merge).
/// Screenshots go to the folder in POGO_SCREENS: light, dark (`-appearance dark`) and one large Dynamic Type size. Not part of `swift test`.
final class ReviewScreensTests: XCTestCase {
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

    private func scrollTop(_ app: XCUIApplication) { for _ in 0..<14 { app.swipeDown(velocity: .fast) } }

    /// Brings `e` on screen and clear of the bottom bar.
    @discardableResult
    private func reveal(_ app: XCUIApplication, _ e: XCUIElement, down: Bool = false) -> Bool {
        let h = app.windows.firstMatch.frame.height
        func clear() -> Bool { e.exists && e.isHittable && e.frame.maxY < h - 190 && e.frame.minY > 120 }
        for _ in 0..<14 { if clear() { return true }; if down { app.swipeDown() } else { app.swipeUp() } }
        for _ in 0..<14 { if clear() { return true }; if down { app.swipeUp() } else { app.swipeDown() } }
        return clear()
    }

    private func button(_ app: XCUIApplication, beginsWith s: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", s)).firstMatch
    }

    /// The open questions: the top of the result, every question kind, a part-read group answered one row, then in bulk, then folded, and one card answered.
    private func tourOpen(_ app: XCUIApplication, _ p: String, pages: Int, interactive: Bool = true) {
        shot("\(p)-01-result-top")
        XCTAssertTrue(app.buttons["review-save-locked"].exists, "Save is locked while questions are open")
        XCTAssertTrue(app.staticTexts["Scan finished at the end of your list"].exists)
        for i in 0..<pages { app.swipeUp(); shot("\(p)-02-questions-\(i)") }
        if pages < 7 || !interactive { return }

        // Few queries on purpose: each one walks the whole long page's accessibility tree, which is slow in a Debug build.
        scrollTop(app)
        let saved = app.buttons["It's the saved one"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        sleep(1)
        shot("\(p)-03-part-mid-answer")
        app.swipeUp()
        let bulk = button(app, beginsWith: "Yes, all")
        XCTAssertTrue(bulk.waitForExistence(timeout: 10), "the bulk button is on screen")
        bulk.tap()
        sleep(1)
        shot("\(p)-04-part-bulk-ticking")
        sleep(2)
        shot("\(p)-05-part-folded")
        let evolved = app.buttons["Yes, it evolved"].firstMatch
        XCTAssertTrue(evolved.waitForExistence(timeout: 10))
        evolved.tap(); sleep(1); shot("\(p)-06-card-answered")
        XCTAssertTrue(app.buttons["review-save-locked"].exists, "still locked with questions open")
    }

    /// Every question answered (the fixture's `+answered` variant): Save unlocked, the lower sections, To check, the Find sheet and Not seen.
    private func tourAnswered(_ app: XCUIApplication, _ p: String) {
        XCTAssertTrue(app.buttons["review-save"].exists && app.buttons["review-save"].isEnabled, "every question answered unlocks Save to box")
        shot("\(p)-07-answered-top")
        for i in 0..<9 { app.swipeUp(); shot("\(p)-08-answered-\(i)") }
        let notes = button(app, beginsWith: "Notes, nothing to do")
        if reveal(app, notes) { notes.tap(); sleep(1); shot("\(p)-09-notes-open") }
        let details = button(app, beginsWith: "Scan details")
        if reveal(app, details) { details.tap(); sleep(1); app.swipeUp(); shot("\(p)-10-scan-details") }

        // To check, and the Find sheet.
        scrollTop(app)
        let step = app.buttons["review-step-check"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        step.tap()
        XCTAssertTrue(app.staticTexts["to look at in the game"].waitForExistence(timeout: 5))
        sleep(1)
        shot("\(p)-11-to-check")
        app.swipeUp(); shot("\(p)-11b-to-check-more")
        let row = button(app, beginsWith: "Zapdos")
        XCTAssertTrue(reveal(app, row))
        row.tap(); sleep(1)
        shot("\(p)-12-find-sheet")
        app.buttons["Close"].firstMatch.tap(); sleep(1)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.scrollViews["review-scroll"].waitForExistence(timeout: 5))

        // Not seen.
        let notSeen = button(app, beginsWith: "Not seen in this scan")
        XCTAssertTrue(reveal(app, notSeen))
        notSeen.tap()
        XCTAssertTrue(app.staticTexts["Tap the ones you no longer have"].waitForExistence(timeout: 5))
        shot("\(p)-13-not-seen-list")
        let first = button(app, beginsWith: "Bulbasaur")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        sleep(1)
        XCTAssertTrue(button(app, beginsWith: "Done · 1 marked").exists, "tapping one marks it for removal")
        shot("\(p)-14-not-seen-list-marked")
        app.buttons["Grid"].tap(); sleep(1)
        shot("\(p)-15-not-seen-grid-marked")
        app.buttons["CP"].firstMatch.tap(); sleep(1)
        shot("\(p)-16-not-seen-grid-by-cp")
        button(app, beginsWith: "Done").tap()
        XCTAssertTrue(app.scrollViews["review-scroll"].waitForExistence(timeout: 5))
    }

    func testOpenLight() throws { tourOpen(launch(["-appearance", "light"]), "light", pages: 7) }
    func testOpenDark() throws { tourOpen(launch(["-appearance", "dark"]), "dark", pages: 7, interactive: false) }
    func testAnsweredLight() throws { tourAnswered(launch(["-appearance", "light"], variant: "full+answered"), "light") }
    func testAnsweredDark() throws { tourAnswered(launch(["-appearance", "dark"], variant: "full+answered"), "dark") }
    func testLargeText() throws {
        let app = launch(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        tourOpen(app, "large", pages: 4)
    }
    func testLargeTextAnswered() throws {
        let app = launch(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"], variant: "full+answered")
        shot("large-answered-top")
        for i in 0..<3 { app.swipeUp(); shot("large-answered-\(i)") }
    }

    /// A scan with nothing to ask: Save to box is available at once.
    func testCleanScanIsUnlocked() throws {
        let app = launch(["-appearance", "light"], variant: "clean")
        XCTAssertTrue(app.buttons["review-save"].exists)
        shot("clean-01-top")
    }

    /// Add and update: no Not seen row, and no Mark all.
    func testAddAndUpdateScan() throws {
        let app = launch(["-appearance", "light"], variant: "partial+answered")
        XCTAssertTrue(app.staticTexts["Scan finished"].exists, "an Add and update scan the person has no end marker for says Scan finished")
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertFalse(button(app, beginsWith: "Not seen in this scan").exists)
        shot("partial-lower")
    }
}
