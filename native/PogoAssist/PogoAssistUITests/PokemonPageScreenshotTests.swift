import XCTest

/// The Pokémon page of design pass 3 (design-process section 6): Summary, PvP, Raids and Max, and the advanced details open, in light and dark, at the default
/// text size and at AX5. PNGs go to the folder in POGO_SCREENS (`TEST_RUNNER_POGO_SCREENS` on the command line), kept under the git-ignored `out/screens/pokemon-page/`.
/// Not part of `swift test`.
final class PokemonPageScreenshotTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

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
        if !load.waitForExistence(timeout: 8), diagnostics.exists { diagnostics.tap() }
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        load.tap()
        app.openReviewFromDone()
        let save = app.buttons["Save to box"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "review did not appear")
        save.tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 10), "the box shows no species")
    }

    /// Opens a copy of a species from the box list (the list's route changes with the My Pokémon screen: only this helper knows it).
    private func openCopy(_ app: XCUIApplication, _ species: String) {
        let search = app.textFields["box-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText(species + "\n")   // Return puts the keyboard away, so the opened species is not under it
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH %@", species)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(species) is in the sample box")
        app.openSpeciesList(row)   // My Pokémon opens the species in place; "See all" opens its list (as PokemonPageTests, 2a3e868)
        let copy = app.buttons.matching(identifier: "pokemon-row").firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        copy.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 10))
    }

    private func back(_ app: XCUIApplication) {
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()
        if app.buttons["Clear search"].waitForExistence(timeout: 2) { app.buttons["Clear search"].tap() }
    }

    private func top(_ app: XCUIApplication) {
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let t = app.buttons["page-tab-\(name)"]
        XCTAssertTrue(t.waitForExistence(timeout: 20), "the \(name) tab")
        // The row scrolls sideways: a tab may start off either edge of the screen.
        // Drag along the row's own height: the row's element is as wide as its content, so a swipe on it can start off the screen.
        func drag(_ from: CGFloat, _ to: CGFloat) {
            let y = (app.buttons["page-tab-summary"].exists ? app.buttons["page-tab-summary"].frame.midY : t.frame.midY) / app.frame.height
            app.coordinate(withNormalizedOffset: CGVector(dx: from, dy: y)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: to, dy: y)))
        }
        var n = 0
        while t.frame.maxX > app.frame.maxX - 6 && n < 4 { drag(0.9, 0.2); n += 1 }
        while t.frame.minX < 6 && n < 8 { drag(0.2, 0.9); n += 1 }
        t.tap()
        sleep(1)
    }

    private func page(_ app: XCUIApplication, _ tag: String) {
        // Scyther: Scizor and Kleavor give the Raids and PvP tabs content; Blissey is in the Max table.
        openCopy(app, "Scyther")
        XCTAssertTrue(app.buttons["page-tab-summary"].waitForExistence(timeout: 30))
        sleep(2)
        shot("summary-\(tag)")
        app.swipeUp(velocity: .slow); sleep(1)
        shot("summary-\(tag)-lower")
        top(app)
        tab(app, "pvp"); shot("pvp-\(tag)")
        tab(app, "raids"); shot("raids-\(tag)")
        app.swipeUp(velocity: .slow); sleep(1); shot("raids-\(tag)-lower")
        top(app)
        tab(app, "gym"); shot("gym-\(tag)")
        tab(app, "rocket"); shot("rocket-\(tag)")
        top(app)
        app.buttons["mark-advanced"].tap(); sleep(1)
        shot("advanced-\(tag)")
        app.swipeUp(velocity: .slow); sleep(1)
        shot("advanced-\(tag)-lower")
        back(app)

        openCopy(app, "Blissey")
        XCTAssertTrue(app.buttons["page-tab-summary"].waitForExistence(timeout: 30))
        top(app)
        let dynamax = app.buttons["mark-dynamax"]
        if !dynamax.waitForExistence(timeout: 10) { shot("debug-blissey-no-mark"); print(app.debugDescription) }
        if dynamax.value as? String != "On" { dynamax.tap(); sleep(2) }
        tab(app, "max"); shot("max-\(tag)")
        app.swipeUp(velocity: .slow); sleep(1); shot("max-\(tag)-lower")
        top(app)
        app.buttons["mark-advanced"].tap(); sleep(1)
        shot("advanced-dynamax-\(tag)")
        back(app)
    }

    func testPageScreensLightAndDarkAtDefaultAndAX5() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["POGO_SCREENS"] == nil, "screenshots only with POGO_SCREENS")
        let ax5 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        let runs: [(String, [String])] = [
            ("light-default", ["-appearance", "light"]), ("dark-default", ["-appearance", "dark"]),
            ("light-ax5", ["-appearance", "light"] + ax5), ("dark-ax5", ["-appearance", "dark"] + ax5),
        ]
        for (n, run) in runs.enumerated() {
            let app = XCUIApplication()
            app.launchArguments = (n == 0 ? ["-uitest-reset"] : []) + ["-uitest-today", "2026-10-25"] + run.1
            app.launch()
            if n == 0 { populate(app) } else { XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20)) }
            page(app, run.0)
            app.terminate()
        }
    }

    /// The top of the page (name, CP, level and HP, the marks), with the marks off and then Dynamax and Shadow on, in light and dark at the default size and AX5.
    /// The phone-feedback item on the Dynamax and Shadow marks (`out/screens/fb-item2/before` and `after`).
    func testPageTopWithTheMarks() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["POGO_SCREENS"] == nil, "screenshots only with POGO_SCREENS")
        let ax5 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        let runs: [(String, [String])] = [
            ("light-default", ["-appearance", "light"]), ("dark-default", ["-appearance", "dark"]),
            ("light-ax5", ["-appearance", "light"] + ax5), ("dark-ax5", ["-appearance", "dark"] + ax5),
        ]
        for (n, run) in runs.enumerated() {
            let app = XCUIApplication()
            app.launchArguments = (n == 0 ? ["-uitest-reset"] : []) + ["-uitest-today", "2026-10-25"] + run.1
            app.launch()
            if n == 0 { populate(app) } else { XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20)) }
            openCopy(app, "Scyther")
            XCTAssertTrue(app.buttons["page-tab-summary"].waitForExistence(timeout: 30))
            top(app); sleep(1)
            // Off, whichever state an earlier run left: turn a mark that is on off first.
            for id in ["mark-dynamax", "mark-shadow"] where app.buttons[id].value as? String == "On" { app.buttons[id].tap() }
            sleep(1)
            shot("top-off-\(run.0)")
            app.buttons["mark-dynamax"].tap(); app.buttons["mark-shadow"].tap(); sleep(1)
            shot("top-on-\(run.0)")
            for id in ["mark-dynamax", "mark-shadow"] { app.buttons[id].tap() }   // leave them off for the next run
            sleep(2)
            back(app)
            app.terminate()
        }
    }
}
