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
    /// Opens the first copy in a species list. Taps near the row's title: under a chip the row's own tag button (44 pt tall) sits across its middle.
    private func openFirstCopy(_ app: XCUIApplication) {
        let copy = app.buttons.matching(identifier: "pokemon-row").firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.12)).tap()
    }
    /// Types a species into the search so its row is built (the list is lazy), then opens the species.
    private func openSpecies(_ app: XCUIApplication, _ name: String) {
        let search = app.textFields["box-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(name)
        // A species with a form reads "Zamazenta (Hero), 3 Pokémon", so match the name's start, not "name,".
        let r = rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(r.waitForExistence(timeout: 5), "\(name) is in the sample box")
        r.tap()
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
        // The count line used to carry "Last scan <date>" as static text; the badge took its place.
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Last scan'")).firstMatch.exists)
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
        // A species whose tile differs between the rankings (the sample's Scyther: Classic takes the IV fit, Pogo Assist the stronger Scizor). The search builds its row.
        let search = app.textFields["box-search"]
        search.tap(); search.typeText("Scyther\n")   // Return closes the keyboard, so the switch can be tapped
        XCTAssertTrue(row(app, "Scyther").waitForExistence(timeout: 5))
        XCTAssertTrue(row(app, "Scyther").label.contains("Ultra League: Scizor, 95.3 percent"), row(app, "Scyther").label)
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "Classic")
        XCTAssertTrue(row(app, "Scyther").label.contains("Ultra League: Scyther, 96.2 percent"), row(app, "Scyther").label)
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        app.buttons["Clear search"].tap()
        XCTAssertTrue(row(app, "Moltres").waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["Charizard · \(app.buttons.matching(identifier: "pokemon-row").count)"].exists, "plain header without a chip")
        // The order label and the ranking switch share one line at the default size.
        let order = app.staticTexts["species-order"].frame, switchFrame = app.descendants(matching: .any)["species-scoring"].frame
        XCTAssertLessThan(abs(order.midY - switchFrame.midY), 20, "order \(order) and switch \(switchFrame) on one line")
        app.buttons["Back"].tap()

        app.buttons["chip-raids"].tap()
        row(app, "Moltres").tap()
        XCTAssertTrue(app.buttons["pokemon-tag"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Moltres · 3 of 6 for Raids"].exists, "the header counts the Strong and OK copies under the chip")
        XCTAssertEqual(app.staticTexts["species-order"].label, "Best for Raids first")
        let tags = app.buttons.matching(identifier: "pokemon-tag").allElementsBoundByIndex.map(\.label)
        for t in app.buttons.matching(identifier: "pokemon-tag").allElementsBoundByIndex { XCTAssertGreaterThanOrEqual(t.frame.height, 44, "tap target of \(t.label)") }
        XCTAssertEqual(tags.count, 6, "every copy has its tag: " + tags.joined(separator: " | "))
        let rank = { (t: String) in t.hasPrefix("Strong") ? 0 : t.hasPrefix("OK") ? 1 : 2 }
        XCTAssertEqual(tags.map(rank), tags.map(rank).sorted(), "Weak last: " + tags.joined(separator: " | "))
        XCTAssertTrue(tags.contains { $0.hasPrefix("Weak") })
        XCTAssertTrue(tags.contains { $0.contains(", best of 6") }, "the best-of tag for the area is merged into the status tag: " + tags.joined(separator: " | "))
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

    /// The Zamazenta (Hero) with CP 2661 carries the advisor's build for an area: its Activities row shows the "ADVICE BUILDS" chip, with the cost spoken in grouped figures.
    func testDetailActivitiesRowShowsTheBuildChip() throws {
        let app = launchPopulated()
        openSpecies(app, "Zamazenta")
        let copy = app.buttons.matching(NSPredicate(format: "identifier == 'pokemon-row' AND label CONTAINS '2661'")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
        let chip = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'activity-' AND identifier ENDSWITH '-builds'")).firstMatch
        var n = 0
        while !chip.exists && n < 10 { app.swipeUp(); n += 1 }
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "the build chip on the Activities row")
        XCTAssertTrue(chip.label.lowercased().hasPrefix("advice builds"), chip.label)
        XCTAssertTrue(chip.label.contains("dust"), chip.label)
        sleep(1); shot("detail-activities-builds")
    }

    /// A hand fix made on the Pokémon page, then back to the list under a chip: the Box screen's tasks fire while the child screens are pushed, so the list is
    /// rebuilt (Fixed by hand appears), the advice is worked out again and the chip's rows come back without the list blanking to "Working out advice…" for good.
    func testAHandFixFromTheDetailPageReachesTheListUnderAChip() throws {
        let app = launchPopulated()
        app.buttons["chip-raids"].tap()
        XCTAssertFalse(app.buttons["chip-fixed"].exists)
        row(app, "Moltres").tap()
        openFirstCopy(app)
        let fix = app.buttons["Fix a value"]
        XCTAssertTrue(fix.waitForExistence(timeout: 5)); fix.tap()
        let attack = app.textFields.element(boundBy: 3)
        XCTAssertTrue(attack.waitForExistence(timeout: 5))
        let was = Int(attack.value as? String ?? "") ?? 0
        attack.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()   // the caret at the end of the number, so the deletes remove it
        attack.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + String((was + 1) % 16))
        shot("fix-1-sheet")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Fix a value"].waitForNonExistence(timeout: 15), "the fix saved and the sheet closed")
        shot("fix-2-after-save")
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()
        shot("fix-3-back")
        XCTAssertTrue(app.buttons["chip-fixed"].waitForExistence(timeout: 15), "the index task fired while the screens were pushed")
        XCTAssertTrue(app.buttons["chip-raids"].isSelected, "still under the chip")
        XCTAssertTrue(row(app, "Moltres").waitForExistence(timeout: 20), "the rows come back once the advice is worked out again")
        XCTAssertTrue(row(app, "Moltres").label.contains("for Raids"), row(app, "Moltres").label)
        XCTAssertFalse(app.staticTexts["Working out advice…"].exists)
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
            openFirstCopy(app)
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
