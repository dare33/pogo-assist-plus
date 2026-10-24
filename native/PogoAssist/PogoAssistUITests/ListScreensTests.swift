import XCTest

/// The Pokémon list's activity chips, to-check badge and league tiles, the species list's tags and the detail page's Activities row, driven with the sample scan.
final class ListScreensTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery { app.buttons.matching(identifier: "species-row") }
    private func row(_ app: XCUIApplication, _ species: String) -> XCUIElement {
        rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", "\(species),")).firstMatch
    }
    private func launchPopulated(_ extra: [String] = ["-appearance", "light"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"] + extra
        app.launch()
        populate(app)
        // The tiles and the chips read the advice; wait for it (a tile that has it never says "…").
        XCTAssertTrue(row(app, "Blissey").waitForExistence(timeout: 10))
        let ready = NSPredicate(format: "label CONTAINS 'Great League: Over cap'")
        expectation(for: ready, evaluatedWith: row(app, "Blissey"))
        waitForExpectations(timeout: 60)
        return app
    }
    private func resetRanking(_ app: XCUIApplication) {
        let control = app.descendants(matching: .any)["list-scoring"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        if control.value as? String != "Classic" { control.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap() }
    }

    /// Activity chips filter the species and change the count capsules to the matching copies; the chosen species carries its best copy's tag.
    func testActivityChipsFilterTheListAndChangeTheCounts() throws {
        let app = launchPopulated()
        let all = row(app, "Moltres").label
        XCTAssertTrue(all.hasPrefix("Moltres, 6 Pokémon"), all)
        XCTAssertTrue(row(app, "Blissey").exists)
        app.buttons["chip-raids"].tap()
        XCTAssertTrue(app.buttons["chip-raids"].isSelected)
        let moltres = row(app, "Moltres")
        XCTAssertTrue(moltres.waitForExistence(timeout: 5))
        XCTAssertTrue(moltres.label.hasPrefix("Moltres, 3 Pokémon, OK for Raids"), "the capsule counts the matching copies: " + moltres.label)
        XCTAssertFalse(row(app, "Blissey").exists, "a species with no Strong or OK copy for Raids is gone")
        XCTAssertTrue(row(app, "Lucario").label.contains("Strong for Raids"), row(app, "Lucario").label)
        sleep(1); shot("list-raids-chip")
        app.buttons["chip-all"].tap()
        XCTAssertTrue(row(app, "Blissey").waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, "Moltres").label.hasPrefix("Moltres, 6 Pokémon"))
    }

    /// A league chip keeps the species with a Strong or OK copy for that league under the shown pick; Great League is over the cap for this whole box.
    func testALeagueChipFilters() throws {
        let app = launchPopulated()
        resetRanking(app)
        app.buttons["chip-ml"].tap()
        let xerneas = row(app, "Xerneas")
        XCTAssertTrue(xerneas.waitForExistence(timeout: 5))
        XCTAssertTrue(xerneas.label.hasPrefix("Xerneas, 2 Pokémon, Strong for Master"), xerneas.label)
        XCTAssertFalse(row(app, "Blissey").exists, "a species with no Strong or OK copy for Master League is gone")
        for r in rows(app).allElementsBoundByIndex { XCTAssertTrue(r.label.contains("for Master"), r.label) }
        app.buttons["chip-gl"].tap()
        XCTAssertTrue(app.staticTexts["No Pokémon match."].waitForExistence(timeout: 5), "nothing in this box fits Great League")
    }

    func testTheToCheckBadgeFiltersAndClears() throws {
        let app = launchPopulated()
        let badge = app.buttons["to-check-badge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertEqual(badge.label, "To check 2")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == 'Last scan'")).firstMatch.exists)
        XCTAssertTrue(row(app, "Blissey").exists)
        badge.tap()
        XCTAssertTrue(badge.isSelected)
        XCTAssertTrue(row(app, "Staraptor").waitForExistence(timeout: 5))
        XCTAssertFalse(row(app, "Blissey").exists, "only species with a Pokémon to check")
        for r in rows(app).allElementsBoundByIndex { XCTAssertTrue(r.label.contains("to check"), r.label) }
        badge.tap()
        XCTAssertFalse(badge.isSelected)
        XCTAssertTrue(row(app, "Blissey").waitForExistence(timeout: 5), "tapping again clears it")
    }

    func testLeagueTilesShowValuesAndOverCap() throws {
        let app = launchPopulated()
        resetRanking(app)
        let blissey = row(app, "Blissey").label
        XCTAssertTrue(blissey.contains("Great League: Over cap. Ultra League: Blissey, 94.9 percent. Master League: Blissey, 89.3 percent"), blissey)
        // The tiles follow the ranking switch, which is the same app-wide preference the species list shows.
        let control = app.descendants(matching: .any)["list-scoring"]
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "Pogo Assist")
        XCTAssertTrue(row(app, "Blissey").label.contains("Master League: Blissey"), row(app, "Blissey").label)
        row(app, "Moltres").tap()
        let species = app.descendants(matching: .any)["species-scoring"]
        XCTAssertTrue(species.waitForExistence(timeout: 5))
        XCTAssertEqual(species.value as? String, "Pogo Assist", "one app-wide setting")
        species.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertEqual(species.value as? String, "Classic")
    }

    /// The species list: league and activity tags on the best copy; opened from a chip, every copy has its tag (tap for the line) and Weak ones are last.
    func testSpeciesListTagsAndTheChipTag() throws {
        let app = launchPopulated()
        resetRanking(app)
        row(app, "Charizard").tap()
        let copy = app.buttons.matching(identifier: "pokemon-row").firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertTrue(copy.label.contains("Best for Master League: Charizard 97.1 percent"), copy.label)
        XCTAssertTrue(copy.label.contains("Best for Raids as Mega Charizard Y"), copy.label)
        XCTAssertTrue(app.staticTexts["tags-note"].exists)
        XCTAssertFalse(app.buttons["pokemon-tag"].exists, "no per-copy tag without a chip")
        XCTAssertEqual(app.staticTexts["species-order"].label, "Best IVs first")
        app.buttons["Back"].tap()

        app.buttons["chip-raids"].tap()
        row(app, "Moltres").tap()
        XCTAssertTrue(app.buttons["pokemon-tag"].firstMatch.waitForExistence(timeout: 5))
        let tags = app.buttons.matching(identifier: "pokemon-tag").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(tags.count, 6, "every copy has its tag: " + tags.joined(separator: " | "))
        let rank = { (t: String) in t.hasPrefix("Strong") ? 0 : t.hasPrefix("OK") ? 1 : 2 }
        XCTAssertEqual(tags.map(rank), tags.map(rank).sorted(), "Weak last: " + tags.joined(separator: " | "))
        XCTAssertTrue(tags.contains { $0.hasPrefix("Weak") })
        let weak = app.buttons.matching(NSPredicate(format: "identifier == 'pokemon-tag' AND label BEGINSWITH 'Weak'")).firstMatch
        weak.tap()
        let line = app.staticTexts["pokemon-tag-line"]
        XCTAssertTrue(line.waitForExistence(timeout: 3))
        XCTAssertFalse(line.label.isEmpty)
        sleep(1); shot("species-raids-chip")
        weak.tap()
        XCTAssertFalse(app.staticTexts["pokemon-tag-line"].exists, "tapping again closes it")
    }

    func testDetailActivitiesRow() throws {
        let app = launchPopulated()
        row(app, "Charizard").tap()
        app.buttons.matching(identifier: "pokemon-row").firstMatch.tap()
        let raids = app.buttons["activity-raids"]
        var n = 0
        while !raids.isHittable && n < 8 { app.swipeUp(); n += 1 }
        XCTAssertTrue(raids.waitForExistence(timeout: 20))
        XCTAssertEqual(raids.label, "Raids: OK")
        for area in ["gym", "rocket", "max"] { XCTAssertTrue(app.buttons["activity-\(area)"].exists, area) }
        XCTAssertTrue(app.staticTexts["activities-panel"].exists)
        raids.tap()
        let line = app.staticTexts["activity-raids-line"]
        XCTAssertTrue(line.waitForExistence(timeout: 3))
        XCTAssertTrue(line.label.hasPrefix("Raids"), line.label)
        sleep(1); shot("detail-activities")
    }

    /// Screenshots and the large-text pass: the list with a chip, the species list and the Pokémon page, light, dark and at the first accessibility size.
    func testListScreensLightDarkAndLargeText() throws {
        func session(_ app: XCUIApplication, _ tag: String) {
            sleep(1)
            app.swipeUp(velocity: .slow); sleep(1)
            shot("\(tag)-list")
            app.buttons["chip-raids"].tap(); sleep(1); shot("\(tag)-list-raids")
            XCTAssertTrue(rows(app).firstMatch.exists)
            rows(app).firstMatch.tap()
            XCTAssertTrue(app.buttons["pokemon-row"].firstMatch.waitForExistence(timeout: 5))
            sleep(1); shot("\(tag)-species")
            app.buttons.matching(identifier: "pokemon-row").firstMatch.tap()
            XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
            let raids = app.buttons["activity-raids"]
            var n = 0
            while !raids.isHittable && n < 10 { app.swipeUp(); n += 1 }
            XCTAssertTrue(raids.exists)
            sleep(1); shot("\(tag)-detail-activities")
            app.buttons["Back"].tap(); app.buttons["Back"].tap()
            app.buttons["chip-all"].tap()
        }
        let light = launchPopulated(["-appearance", "light"])
        session(light, "light")
        light.terminate()
        let dark = XCUIApplication()
        dark.launchArguments = ["-appearance", "dark"]
        dark.launch()
        XCTAssertTrue(dark.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 15))
        session(dark, "dark")
        dark.terminate()
        let large = XCUIApplication()
        large.launchArguments = ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        large.launch()
        XCTAssertTrue(large.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 15))
        session(large, "large")
    }

    /// A fresh account with the sample scan reviewed and saved; leaves the app on the list.
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
}
