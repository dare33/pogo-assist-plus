import XCTest

/// The Pokémon page of design pass 3, driven with the sample scan: it opens on Summary, each tab switches, a Summary row opens its tab, the marks toggle and
/// persist (Shadow and Purified clear each other), the advanced details follow their rules, an initial league opens PvP with its tile chosen, and Fix a value
/// still opens. Screenshots are `PokemonPageScreenshotTests`.
final class PokemonPageTests: XCTestCase {
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

    private func launchPopulated(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light", "-uitest-today", "2026-10-25"] + extra
        app.launch()
        populate(app)
        return app
    }

    /// Opens a copy of a species from the box list (the list's route changes with the My Pokémon screen: only this helper knows it).
    private func openCopy(_ app: XCUIApplication, _ species: String) {
        let search = app.textFields["box-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText(species)
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH %@", species)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(species) is in the sample box")
        row.tap()
        let copy = app.buttons.matching(identifier: "pokemon-row").firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        copy.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["page-tab-summary"].waitForExistence(timeout: 30), "the page shows its tabs")
    }

    private func closeCopy(_ app: XCUIApplication) {
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()
        if app.buttons["Clear search"].waitForExistence(timeout: 2) { app.buttons["Clear search"].tap() }
    }

    /// Taps a tab; the row scrolls sideways, so the last tabs may start off the screen.
    private func selectTab(_ app: XCUIApplication, _ name: String) {
        let t = app.buttons["page-tab-\(name)"]
        XCTAssertTrue(t.waitForExistence(timeout: 20), "the \(name) tab")
        // Drag along the row's own height: the row's element is as wide as its content, so a swipe on it can start off the screen.
        func drag(_ from: CGFloat, _ to: CGFloat) {
            let y = (app.buttons["page-tab-summary"].exists ? app.buttons["page-tab-summary"].frame.midY : t.frame.midY) / app.frame.height
            app.coordinate(withNormalizedOffset: CGVector(dx: from, dy: y)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: to, dy: y)))
        }
        var n = 0
        while t.frame.maxX > app.frame.maxX - 6 && n < 4 { drag(0.9, 0.2); n += 1 }
        while t.frame.minX < 6 && n < 8 { drag(0.2, 0.9); n += 1 }
        t.tap()
    }

    private func top(_ app: XCUIApplication) { for _ in 0..<4 { app.swipeDown(velocity: .fast) } }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func waitValue(_ e: XCUIElement, _ value: String, _ message: String) {
        let p = NSPredicate(format: "value == %@", value)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: 15), .completed, message)
    }

    /// Summary first (rule 19); each tab switches; a Summary row opens its tab; Fix a value still opens.
    func testOpensOnSummaryTabsSwitchSummaryRowsOpenTabsAndFixStillOpens() throws {
        let app = launchPopulated()
        openCopy(app, "Scyther")
        XCTAssertTrue(app.buttons["page-tab-summary"].isSelected, "the page opens on Summary")
        XCTAssertTrue(el(app, "summary-rows").waitForExistence(timeout: 30))
        let content = ["pvp": "pvp-tab", "raids": "raids-tab", "gym": "gym-tab", "rocket": "rocket-tab", "max": "max-tab", "summary": "summary-rows"]
        for name in ["pvp", "raids", "gym", "rocket", "max", "summary"] {
            selectTab(app, name)
            XCTAssertTrue(el(app, content[name]!).waitForExistence(timeout: 10), "\(name) shows its content")
            XCTAssertTrue(app.buttons["page-tab-\(name)"].isSelected, "\(name) is the chosen tab")
            // Every tab keeps the facts and Delete under it, while that tab is shown.
            XCTAssertTrue(el(app, "page-facts").exists, "\(name): the facts row")
            XCTAssertTrue(app.buttons["Delete from box"].exists, "\(name): Delete from box")
        }
        // A Summary row opens its tab.
        app.buttons["summary-row-raids"].tap()
        XCTAssertTrue(el(app, "raids-tab").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["page-tab-raids"].isSelected)
        selectTab(app, "summary")
        app.buttons["summary-row-pvp"].tap()
        XCTAssertTrue(el(app, "pvp-tab").waitForExistence(timeout: 10))
        // The PvP tab: three tiles, the family folded at first and opened by its row.
        for key in ["gl", "ul", "ml"] { XCTAssertTrue(app.buttons["league-\(key)-pick"].exists, key) }
        XCTAssertFalse(el(app, "league-family").exists)
        el(app, "league-family-toggle").tap()
        XCTAssertTrue(el(app, "league-family").waitForExistence(timeout: 5))
        app.buttons["league-ul-pick"].tap()
        XCTAssertTrue(app.buttons["league-ul-pick"].isSelected)
        // Fix a value opens its sheet, unchanged.
        top(app)
        app.buttons["Fix a value"].tap()
        XCTAssertTrue(app.navigationBars["Fix a value"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Fix a value"].waitForNonExistence(timeout: 5))
    }

    /// The marks toggle and persist after leaving and reopening the page; Shadow on clears Purified and the reverse; Max moves show only while Dynamax is on; the
    /// second charged move cannot equal the first.
    func testMarksPersistAndAdvancedDetailsFollowTheirRules() throws {
        let app = launchPopulated()
        openCopy(app, "Scyther")
        let dynamax = app.buttons["mark-dynamax"], shadow = app.buttons["mark-shadow"], advanced = app.buttons["mark-advanced"]
        XCTAssertEqual(dynamax.value as? String, "Off"); XCTAssertEqual(shadow.value as? String, "Off")
        XCTAssertEqual(advanced.value as? String, "Collapsed")
        advanced.tap()
        XCTAssertEqual(advanced.value as? String, "Expanded")
        XCTAssertTrue(el(app, "advanced-details").waitForExistence(timeout: 5))
        XCTAssertFalse(el(app, "adv-max").exists, "Max moves wait for the Dynamax mark")
        XCTAssertFalse(el(app, "flag-gigantamax").exists, "and so does the Gigantamax chip")

        dynamax.tap(); waitValue(dynamax, "On", "the Dynamax mark turns on")
        XCTAssertTrue(el(app, "adv-max").waitForExistence(timeout: 10), "Max moves show once Dynamax is on")
        XCTAssertTrue(el(app, "flag-gigantamax").exists)
        XCTAssertTrue(app.buttons["max-attack-1"].isSelected, "Max Attack shows level 1 until a level is chosen")
        app.buttons["max-attack-3"].tap()
        XCTAssertTrue(app.buttons["max-attack-3"].waitForExistence(timeout: 5))
        let picked = NSPredicate(format: "isSelected == true")
        expectation(for: picked, evaluatedWith: app.buttons["max-attack-3"]); waitForExpectations(timeout: 10)

        // Shadow and Purified clear each other.
        shadow.tap(); waitValue(shadow, "On", "the Shadow mark turns on")
        el(app, "flag-purified").tap()
        waitValue(shadow, "Off", "Purified on clears Shadow")
        XCTAssertTrue(app.buttons["flag-purified"].isSelected)
        shadow.tap(); waitValue(shadow, "On", "Shadow on again")
        XCTAssertFalse(app.buttons["flag-purified"].isSelected, "Shadow on clears Purified")

        // The second charged move is never the first.
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'move-charged-' AND isSelected == true")).firstMatch
        XCTAssertTrue(first.exists, "a charged move is shown as chosen (the default)")
        let firstId = first.identifier.replacingOccurrences(of: "move-charged-", with: "")
        XCTAssertFalse(el(app, "move-charged2-\(firstId)").exists, "the first charged move is not offered as the second")
        XCTAssertTrue(app.buttons["move-charged2-none"].isSelected, "the second starts Not unlocked")
        let other = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'move-charged2-' AND NOT identifier ENDSWITH 'none'")).firstMatch
        XCTAssertTrue(other.exists)
        let otherId = other.identifier.replacingOccurrences(of: "move-charged2-", with: "")
        other.tap()
        XCTAssertTrue(app.buttons["move-charged2-\(otherId)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["move-charged2-\(otherId)"].isSelected)
        XCTAssertFalse(el(app, "move-charged-\(otherId)").exists, "the second charged move is not offered as the first")
        // An Elite move carries its tag.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Elite'")).firstMatch.exists)

        // Leave and come back: the marks and moves are kept.
        closeCopy(app)
        openCopy(app, "Scyther")
        XCTAssertEqual(app.buttons["mark-dynamax"].value as? String, "On")
        XCTAssertEqual(app.buttons["mark-shadow"].value as? String, "On")
        app.buttons["mark-advanced"].tap()
        XCTAssertTrue(app.buttons["max-attack-3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["max-attack-3"].isSelected, "the Max Attack level was kept")
        XCTAssertTrue(app.buttons["move-charged2-\(otherId)"].isSelected, "the second charged move was kept")
        app.buttons["mark-dynamax"].tap(); waitValue(app.buttons["mark-dynamax"], "Off", "the Dynamax mark turns off")
        XCTAssertTrue(el(app, "adv-max").waitForNonExistence(timeout: 10), "Max moves hide again")
    }

    /// The Max tab starts with the Dynamax state and reads NEEDS DYNAMAX until the mark is on.
    func testMaxTabNeedsDynamaxUntilMarked() throws {
        let app = launchPopulated()
        openCopy(app, "Blissey")
        selectTab(app, "max")
        XCTAssertTrue(el(app, "max-tab").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "max-dynamax-line").label.hasPrefix("Dynamax: not marked."), el(app, "max-dynamax-line").label)
        XCTAssertTrue(app.staticTexts["NEEDS DYNAMAX"].firstMatch.exists)
        selectTab(app, "summary")
        XCTAssertTrue(app.buttons["summary-row-max"].label.contains("needs dynamax"), app.buttons["summary-row-max"].label)
        top(app)
        app.buttons["mark-dynamax"].tap(); waitValue(app.buttons["mark-dynamax"], "On", "Dynamax on")
        selectTab(app, "max")
        XCTAssertTrue(el(app, "max-dynamax-line").label.hasPrefix("Marked as Dynamax."), el(app, "max-dynamax-line").label)
        XCTAssertFalse(app.staticTexts["NEEDS DYNAMAX"].firstMatch.exists)
    }

    /// An initial league opens the page on PvP with that tile chosen (a TOP PVP copy, rule 6). The launch argument stands in for the list's route.
    func testAnInitialLeagueOpensPvPWithItsTileChosen() throws {
        let first = launchPopulated()
        first.terminate()
        let app = XCUIApplication()
        app.launchArguments = ["-appearance", "light", "-uitest-initial-league", "ul"]
        app.launch()
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20))
        openCopy(app, "Scyther")
        XCTAssertTrue(app.buttons["page-tab-pvp"].isSelected, "opens on PvP")
        XCTAssertTrue(app.buttons["league-ul-pick"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["league-ul-pick"].isSelected, "with that league's tile chosen")
        XCTAssertFalse(app.buttons["league-gl-pick"].isSelected)
    }

    /// Two quick edits both persist: the second waits for the first and is made from the row as it is then (each details edit replaces them all).
    func testTwoQuickEditsBothPersist() throws {
        let app = launchPopulated()
        openCopy(app, "Scyther")
        app.buttons["mark-advanced"].tap()
        XCTAssertTrue(el(app, "flag-lucky").waitForExistence(timeout: 10))
        el(app, "flag-best-buddy").tap()
        el(app, "flag-weather-boosted").tap()   // at once: no wait for the first save
        el(app, "flag-lucky").tap()
        closeCopy(app)
        openCopy(app, "Scyther")
        app.buttons["mark-advanced"].tap()
        XCTAssertTrue(el(app, "flag-lucky").waitForExistence(timeout: 10))
        for id in ["flag-best-buddy", "flag-weather-boosted", "flag-lucky"] {
            let e = app.buttons[id]
            expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: e)
        }
        waitForExpectations(timeout: 15)
    }

    /// A default move that was only shown is not saved by leaving the page; tapping a move saves it. And a Lucky edit makes a new box version with new advice: the
    /// cost shown on a Summary row changes (Lucky halves the power-up dust).
    func testDefaultsStayUnsavedAndLuckyReRunsTheAdvice() throws {
        let app = launchPopulated()
        openCopy(app, "Scyther")
        let row = el(app, "summary-row-raids")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        let before = row.label
        XCTAssertTrue(before.contains("dust"), before)
        app.buttons["mark-advanced"].tap()
        let fast = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'move-fast-' AND isSelected == true")).firstMatch
        XCTAssertTrue(fast.waitForExistence(timeout: 10), "the default fast move is shown as chosen")
        let id = fast.identifier
        closeCopy(app)
        openCopy(app, "Scyther")
        app.buttons["mark-advanced"].tap()
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[id].isSelected, "still the default after leaving without a tap")
        XCTAssertEqual(el(app, "summary-row-raids").label, before, "leaving saved nothing that changed the advice")
        el(app, "flag-lucky").tap()
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: el(app, "summary-row-raids"))
        waitForExpectations(timeout: 30)
        XCTAssertTrue(app.buttons["flag-lucky"].isSelected)
    }
}
