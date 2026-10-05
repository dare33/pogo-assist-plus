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
        app.openReviewFromDone()
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
            // The species list is pushed with the To check filter on; its rows appear after the push, so wait for them rather than tapping at once.
            XCTAssertTrue(members.firstMatch.waitForExistence(timeout: 10), "the species list under the To check chip shows its Pokémon")
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

    // MARK: Re-scan N

    /// A box saved with checks and the command set made: the Saved panel offers "Re-scan N", the To check chip offers it too, and it lands on the Scan screen
    /// with Add and update and the smallest command covering N plus the margin. Editing the options, or leaving the screen, drops the suggestion.
    func testRescanButtonLandsOnScanWithTheCommand() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-seed-review", "full+commands+answered", "-appearance", "light"]
        app.launch()
        let save = app.buttons["review-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 90), "the seeded review did not appear")
        save.tap()
        let button = app.buttons["rescan-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "the Saved panel offers Re-scan when the box has checks")
        let n = Int(button.label.replacingOccurrences(of: "Re-scan ", with: "")) ?? 0
        XCTAssertGreaterThan(n, 0, button.label)
        shot("rescan-01-saved-panel")

        // With the chip on, the one button sits under the chips.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'To check'")).firstMatch.tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "rescan-button").count, 1)
        XCTAssertEqual(button.label, "Re-scan \(n)")
        sleep(1)
        shot("rescan-02-to-check-chip")

        let sizes = [25, 50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 4000, 5000]
        let command = "Pogo scan \(sizes.first { $0 >= n + max(2, n / 10) }!)"
        button.tap()
        XCTAssertTrue(app.navigationBars["Scan Pokémon"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add and update"].waitForExistence(timeout: 5), "the scan kind is Add and update")
        XCTAssertTrue(app.staticTexts["rescan-line"].exists)
        XCTAssertEqual(app.staticTexts["rescan-line"].label, "Re-scan of \(n) to check: in the game, show just those, open the first one's appraisal, then start.")
        XCTAssertTrue(app.staticTexts["\"\(command)\""].exists, "the steps name \(command)")
        sleep(1)
        shot("rescan-03-scan-screen")

        // Edit drops it: the steps go back to naming the size.
        app.buttons["Edit scan options"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Add and update"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["rescan-line"].exists)
        XCTAssertFalse(app.staticTexts["\"\(command)\""].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '\"Pogo scan\" and the size'")).firstMatch.exists)
    }

    /// Changing the scan kind, or closing the Scan screen, drops the suggestion; the screen opened later from the tab bar does not meet it.
    func testRescanSuggestionDoesNotSurviveALaterVisit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-seed-review", "full+commands+answered", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["review-save"].waitForExistence(timeout: 90))
        app.buttons["review-save"].tap()
        let button = app.buttons["rescan-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        XCTAssertTrue(app.staticTexts["rescan-line"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        app.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan Pokémon"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["rescan-line"].exists, "a later visit does not carry the suggestion")
    }

    // MARK: Mega form

    /// The seeded Mega pair answered "Same Pokémon" and saved: the box holds one Blaziken with a Mega form. Leaves the app on the Box.
    private func saveMegaPair(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-seed-review", "megapair+answered"] + extra
        app.launch()
        let save = app.buttons["review-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 90), "the seeded review did not appear")
        save.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20), "the box shows no species")
        return app
    }

    private func openBlaziken(_ app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Blaziken'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let one = app.buttons.matching(identifier: "pokemon-row").firstMatch
        XCTAssertTrue(one.waitForExistence(timeout: 5)); one.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
        sleep(1)
    }

    private func searchValue(_ app: XCUIApplication) -> String? {
        let b = app.buttons.matching(NSPredicate(format: "label == 'Copy search'")).firstMatch
        return b.exists ? b.value as? String : nil
    }

    /// The detail's Normal / Mega switch, the row marker, the one-entry count and the Settings choice that sets where the switch starts.
    func testMegaFormSwitchRowMarkerCountAndSettings() throws {
        let app = saveMegaPair(["-appearance", "light"])
        sleep(1)
        let count = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '9' AND label CONTAINS '9 species'")).firstMatch
        XCTAssertTrue(count.exists, "one entry with both forms counts once: 6 + Blaziken + 2 new = 9")
        shot("mega-light-01-box")

        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Blaziken'")).firstMatch
        XCTAssertTrue(row.exists); row.tap()
        let one = app.buttons.matching(identifier: "pokemon-row")
        XCTAssertTrue(one.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(one.count, 1, "the species list has one Blaziken")
        XCTAssertTrue(one.firstMatch.label.contains("CP 2819") && one.firstMatch.label.contains("has a Mega form"), one.firstMatch.label)
        XCTAssertTrue(app.staticTexts["Mega"].exists, "the row's Mega marker")
        shot("mega-light-02-species-row")
        one.firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
        sleep(1)

        // Normal first (the Settings choice is Normal): the entry's own values.
        XCTAssertTrue(app.staticTexts["CP 2819"].exists && app.staticTexts["Blaziken"].exists)
        XCTAssertTrue(app.buttons["form-normal"].isSelected && !app.buttons["form-mega"].isSelected)
        XCTAssertEqual(searchValue(app), "blaziken&cp2819")
        XCTAssertFalse(app.staticTexts["mega-search-note"].exists, "the caption is for the Mega side only")
        XCTAssertTrue(app.buttons["Fix a value"].isEnabled)
        shot("mega-light-03-detail-normal")

        app.buttons["form-mega"].tap()
        XCTAssertTrue(app.staticTexts["CP 3970"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Blaziken (Mega)"].exists && !app.staticTexts["CP 2819"].exists)
        XCTAssertEqual(searchValue(app), "blaziken&cp2819", "the game search stays the normal form's: the game shows the Mega CP only while it is Mega evolved")
        XCTAssertTrue(app.staticTexts["The game shows the Mega CP only while it is Mega evolved, so this search uses the normal CP."].exists)
        XCTAssertFalse(app.buttons["Fix a value"].isEnabled, "Fix a value changes the normal values only")
        shot("mega-light-04-detail-mega")
        app.swipeUp()
        shot("mega-light-05-detail-mega-lower")
        app.buttons["Back"].tap(); app.buttons["Back"].tap()

        // Settings > Mega Pokémon sets where the switch starts.
        app.buttons["More"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        if !app.navigationBars["Settings"].waitForExistence(timeout: 6), settings.exists { settings.tap() }
        let pick = app.buttons["settings-mega"]
        XCTAssertTrue(pick.waitForExistence(timeout: 8), "Settings has a Mega Pokémon row")
        XCTAssertTrue(pick.label.hasPrefix("Mega Pokémon"), pick.label)
        shot("mega-light-06-settings")
        pick.tap()
        let mega = app.buttons["Mega"].firstMatch
        XCTAssertTrue(mega.waitForExistence(timeout: 5)); mega.tap()
        sleep(1)
        shot("mega-light-07-settings-mega")
        app.buttons["Done"].tap()
        // The sheet must be gone before the next tap: a tap during its dismissal reached nothing on iOS 27.
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 5))
        openBlaziken(app)
        XCTAssertTrue(app.buttons["form-mega"].isSelected, "the page starts on Mega when Settings says so")
        XCTAssertTrue(app.staticTexts["CP 3970"].exists)
        app.buttons["form-normal"].tap()
        XCTAssertTrue(app.staticTexts["CP 2819"].waitForExistence(timeout: 3), "and the switch still moves to Normal")
    }

    func testMegaFormDark() throws {
        let app = saveMegaPair(["-appearance", "dark"])
        sleep(1)
        shot("mega-dark-01-box")
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Blaziken'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "pokemon-row").firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot("mega-dark-02-species-row")
        app.buttons.matching(identifier: "pokemon-row").firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5)); sleep(1)
        shot("mega-dark-03-detail-normal")
        app.buttons["form-mega"].tap(); sleep(1)
        shot("mega-dark-04-detail-mega")
    }

    func testMegaFormLargeText() throws {
        let app = saveMegaPair(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        sleep(1)
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Blaziken'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "pokemon-row").firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot("mega-large-01-species-row")
        app.buttons.matching(identifier: "pokemon-row").firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5)); sleep(1)
        shot("mega-large-02-detail-normal")
        app.buttons["form-mega"].tap(); sleep(1)
        shot("mega-large-03-detail-mega")
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
