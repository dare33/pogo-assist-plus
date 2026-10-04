import XCTest

/// The Box and Pokémon detail screens of UI v1, driven with the sample scan: Box (with the Saved panel), search, a chip,
/// a species list, select mode with the game search built, detail and a detail with a check, in light and dark.
/// Screenshots go to the folder in POGO_SCREENS. Not part of `swift test`.
final class BoxScreensTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// A fresh account with the sample scan reviewed and saved; leaves the app on the Box.
    private func populate(_ app: XCUIApplication) {
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
        if !load.waitForExistence(timeout: 8), diagnostics.exists { diagnostics.tap() }   // the menu can swallow the first tap
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        load.tap()
        let save = app.buttons["Save to box"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "review did not appear")
        save.tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 10), "the box shows no species")
    }

    /// The title a species row's label starts with ("Staraptor, 24 Pokémon, ...").
    private func speciesTitle(_ row: XCUIElement) -> String { row.label.components(separatedBy: ", ").first ?? row.label }

    private func screens(_ app: XCUIApplication, _ mode: String, saved: Bool) {
        let rows = app.buttons.matching(identifier: "species-row")
        sleep(1)
        shot("box-01-\(mode)-box")
        if saved { XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to'")).firstMatch.exists, "the Saved panel is at the top of Box") }

        // Search by a piece of a name.
        let title = speciesTitle(rows.element(boundBy: 0))
        let search = app.textFields["box-search"]
        XCTAssertTrue(search.exists)
        search.tap(); search.typeText(String(title.lowercased().prefix(3)))
        sleep(1)
        shot("box-02-\(mode)-search")
        XCTAssertTrue(rows.firstMatch.exists)
        app.buttons["Clear search"].tap()

        // Search by CP range: every species row that is left has a top CP inside it or a Pokémon in it.
        search.tap(); search.typeText("cp1-99999")
        sleep(1)
        XCTAssertTrue(rows.firstMatch.exists, "a wide CP range matches")
        app.buttons["Clear search"].tap()
        search.typeText("zzzzqq")
        XCTAssertTrue(app.staticTexts["No Pokémon match."].waitForExistence(timeout: 3))
        app.buttons["Clear search"].tap()
        app.swipeDown()

        // A chip: To check, when the box has checks.
        let toCheck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'To check'")).firstMatch
        if toCheck.exists { toCheck.tap(); sleep(1); shot("box-03-\(mode)-chip-to-check"); app.buttons["All"].tap() }

        // A species list, then select mode with the search built from the picked Pokémon.
        rows.element(boundBy: 0).tap()
        let members = app.buttons.matching(identifier: "pokemon-row")
        XCTAssertTrue(members.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot("box-04-\(mode)-species")
        app.buttons["Select"].tap()
        members.element(boundBy: 0).tap()
        if members.count > 1 { members.element(boundBy: 1).tap() }
        let built = app.staticTexts.matching(NSPredicate(format: "value CONTAINS '&cp'")).firstMatch
        let builtAny = app.otherElements.matching(NSPredicate(format: "label == 'Search to paste into the game'")).firstMatch
        XCTAssertTrue(built.waitForExistence(timeout: 5) || builtAny.waitForExistence(timeout: 5), "select mode builds the game search")
        sleep(1)
        shot("box-05-\(mode)-select")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Copy search'")).firstMatch.tap()
        sleep(1)
        shot("box-05b-\(mode)-copied")
        app.buttons["Cancel"].tap()
        members.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
        sleep(1)
        shot("box-06-\(mode)-detail")
        app.swipeUp()
        shot("box-06b-\(mode)-detail-lower")
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()

        // A detail with a check.
        if toCheck.exists {
            toCheck.tap()
            rows.element(boundBy: 0).tap()
            members.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["These values are right"].waitForExistence(timeout: 5), "a Pokémon with a check shows the button")
            sleep(1)
            shot("box-07-\(mode)-detail-check")
            app.buttons["Back"].tap()
            app.buttons["Back"].tap()
            app.buttons["All"].tap()
        }
    }

    func testBoxScreensLightThenDark() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        screens(app, "light", saved: true)
        app.terminate()

        // The box is kept: launch again without the reset, in dark.
        let dark = XCUIApplication()
        dark.launchArguments = ["-appearance", "dark"]
        dark.launch()
        XCTAssertTrue(dark.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 15))
        screens(dark, "dark", saved: false)
        dark.terminate()

        // Large text: rows grow and nothing is cut off.
        let large = XCUIApplication()
        large.launchArguments = ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        large.launch()
        XCTAssertTrue(large.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 15))
        sleep(1)
        shot("box-08-large-text-box")
        large.buttons.matching(identifier: "species-row").element(boundBy: 0).tap()
        large.buttons.matching(identifier: "pokemon-row").firstMatch.tap()
        XCTAssertTrue(large.buttons["Fix a value"].waitForExistence(timeout: 5))
        sleep(1)
        shot("box-09-large-text-detail")
    }

    /// The synthetic 15,000-entry box (DEBUG, `-box-synthetic`): the index timing is on screen and in the log, and the list scrolls and searches.
    func testBoxAt15000() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-box-synthetic", "-appearance", "light"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        let bench = app.otherElements["bench-result"].exists ? app.otherElements["bench-result"] : app.staticTexts["bench-result"]
        XCTAssertTrue(bench.waitForExistence(timeout: 30), "the index was not built")
        print("BENCH:", bench.label)
        XCTContext.runActivity(named: bench.label) { _ in }
        sleep(1)
        shot("box-10-15000")
        let start = Date()
        for _ in 0..<6 { app.swipeUp(velocity: .fast) }
        print("BENCH: six fast swipes took", Date().timeIntervalSince(start), "s")
        shot("box-10b-15000-scrolled")
        let search = app.textFields["box-search"]
        for _ in 0..<12 where !search.isHittable { app.swipeDown(velocity: .fast) }
        search.tap(); search.typeText("ra")
        let t = Date()
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 5))
        print("BENCH: typed search shown after", Date().timeIntervalSince(t), "s")
        shot("box-10c-15000-search")
    }
}
