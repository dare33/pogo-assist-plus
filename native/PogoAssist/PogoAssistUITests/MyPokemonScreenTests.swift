import XCTest

extension XCUIApplication {
    /// A short upward drag (a quarter of the screen), so a row is brought up without being thrown past the top as a full swipe does.
    func nudgeUp() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
    }
    /// A species row opens in place on My Pokémon (design pass 3); "See all N copies" under it opens the species list.
    func openSpeciesList(_ row: XCUIElement) {
        // The floating tab bar covers the bottom of the screen: a row there is scrolled up first, or the tap lands on the bar.
        var n = 0
        while row.exists, (!row.isHittable || row.frame.midY > frame.height * 0.72), n < 8 { nudgeUp(); n += 1 }
        row.tap()
        let all = buttons["see-all"]
        // A tap during a screen transition can reach nothing: if it did not open and the row is still closed, tap it once more.
        if !all.waitForExistence(timeout: 3), row.exists, !row.label.hasSuffix("Open") { row.tap() }
        // The list is lazy: the button under a species opened near the bottom is not built until it is scrolled towards.
        n = 0
        while !all.waitForExistence(timeout: 3), n < 4 { nudgeUp(); n += 1 }
        if !all.exists { XCTContext.runActivity(named: "species did not open") { $0.add(XCTAttachment(screenshot: screenshot())) } }
        XCTAssertTrue(all.exists, "the species did not open in place")
        n = 0
        while !all.isHittable, n < 4 { nudgeUp(); n += 1 }   // under the tab bar's Scan button a tap would start a scan
        all.tap()
    }
}

/// The My Pokémon tab (design pass 3, Option A): species open in place with TOP PVP and TOP IVS, "See all", the A-Z index for VoiceOver, and the screenshots.
///
/// Accessibility identifiers of the new elements (stable): `tab-title` (the header's title), `species-row` (a species row: a button that opens or closes the species in
/// place; its label ends "Opens in place" or "Open"), `top-pvp-caption`, `top-ivs-caption`, `top-pvp-row`, `top-ivs-row` (copy rows, buttons), `top-pvp-waiting`
/// (the note while the advice is worked out), `see-all` ("See all N copies"), `az-jump` (the always-present "Jump to letter" element for VoiceOver).
/// The sample box's Moltres (6 copies) has two Ultra League cards under the cap and four other copies.
final class MyPokemonScreenTests: XCTestCase {
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

    private func row(_ app: XCUIApplication, _ species: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH %@", "\(species),")).firstMatch
    }

    /// A populated box with Moltres on screen: the search builds its row (the list is lazy).
    private func launchOnMoltres() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        let search = app.textFields["box-search"]
        search.tap(); search.typeText("Moltres\n")
        XCTAssertTrue(row(app, "Moltres").waitForExistence(timeout: 10))
        return app
    }

    /// Opens Moltres in place and waits for the PvP picks (they come from the advice, which is worked out after a save).
    private func openMoltres(_ app: XCUIApplication) {
        row(app, "Moltres").tap()
        XCTAssertTrue(app.buttons["see-all"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["top-pvp-row"].firstMatch.waitForExistence(timeout: 60), "the PvP picks did not arrive")
    }

    func testTheTabAndTheScreenAreCalledMyPokemon() throws {
        let app = launchOnMoltres()
        XCTAssertTrue(app.buttons["My Pokémon"].exists, "the tab bar's label")
        XCTAssertEqual(app.staticTexts["tab-title"].label, "My Pokémon")
        XCTAssertTrue(app.buttons["Account, Greg main"].exists, "the account name is in the header")
        XCTAssertTrue(app.buttons["Export"].exists && app.buttons["More"].exists)
        let title = app.staticTexts["tab-title"].frame, account = app.buttons["Account, Greg main"].frame
        XCTAssertLessThan(account.maxX, title.minX, "the account name is on the left of the title")
        XCTAssertEqual(title.midX, app.frame.midX, accuracy: 3, "the title is centred")
    }

    func testASpeciesOpensAndClosesInPlace() throws {
        let app = launchOnMoltres()
        let moltres = row(app, "Moltres")
        XCTAssertTrue(moltres.label.hasSuffix("Opens in place"), moltres.label)
        moltres.tap()
        XCTAssertTrue(app.buttons["see-all"].waitForExistence(timeout: 10), "it opens under its row")
        XCTAssertTrue(app.staticTexts["top-ivs-caption"].exists)
        XCTAssertTrue(row(app, "Moltres").label.hasSuffix("Open"), row(app, "Moltres").label)
        XCTAssertTrue(app.buttons["species-row"].exists || row(app, "Moltres").exists, "still on the list, not pushed")
        XCTAssertFalse(app.buttons["pokemon-row"].exists, "no species list was pushed")
        row(app, "Moltres").tap()
        XCTAssertTrue(app.buttons["see-all"].waitForNonExistence(timeout: 5), "another tap closes it")
        XCTAssertTrue(row(app, "Moltres").label.hasSuffix("Opens in place"))
    }

    func testTopPvPAndTopIVsRowsForASpecies() throws {
        let app = launchOnMoltres()
        openMoltres(app)
        XCTAssertTrue(app.staticTexts["top-pvp-caption"].exists)
        let pvp = app.buttons.matching(identifier: "top-pvp-row"), ivs = app.buttons.matching(identifier: "top-ivs-row")
        XCTAssertEqual(pvp.count, 2, "the two copies with the best Great or Ultra League card")
        XCTAssertEqual(ivs.count, 2, "the next two by IVs")
        for r in pvp.allElementsBoundByIndex {
            XCTAssertTrue(r.label.contains("Ultra League: Moltres"), r.label)
            XCTAssertTrue(r.label.contains("IV rank"), r.label)
        }
        for r in ivs.allElementsBoundByIndex { XCTAssertFalse(r.label.contains("League"), "no league pick on a TOP IVS row: " + r.label) }
        XCTAssertTrue(ivs.allElementsBoundByIndex.contains { $0.label.contains("Transfer · one of 6") || $0.label.contains("Keep") }, "a keep or transfer tag")
        // The copy rows are four different copies.
        XCTAssertEqual(Set((pvp.allElementsBoundByIndex + ivs.allElementsBoundByIndex).map(\.label)).count, 4)
    }

    func testATopPvPTapOpensThePageWithThatLeagueChosen() throws {
        let app = launchOnMoltres()
        openMoltres(app)
        app.buttons["top-pvp-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 10), "the Pokémon page opened")
        XCTAssertTrue(app.buttons["leagues-back"].waitForExistence(timeout: 10), "its Ultra League view is the one chosen")
    }

    func testATopIVsTapOpensThePageAsToday() throws {
        let app = launchOnMoltres()
        openMoltres(app)
        app.buttons["top-ivs-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 10), "the Pokémon page opened")
        XCTAssertTrue(app.buttons["league-ul-pick"].waitForExistence(timeout: 10) || app.buttons["league-gl-pick"].exists, "its leagues show their base cards")
        XCTAssertFalse(app.buttons["leagues-back"].exists, "no league was chosen")
    }

    func testSeeAllOpensTheSpeciesList() throws {
        let app = launchOnMoltres()
        openMoltres(app)
        let all = app.buttons["see-all"]
        XCTAssertEqual(all.label, "See all 6 Moltres")
        all.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "pokemon-row").firstMatch.waitForExistence(timeout: 10), "the species list shows its copies")
        XCTAssertEqual(app.buttons.matching(identifier: "pokemon-row").count, 6)
    }

    func testTheJumpToLetterElementIsThereForVoiceOverWithoutScrolling() throws {
        let app = launchOnMoltres()
        app.buttons["Clear search"].tap()
        XCTAssertTrue(row(app, "Blissey").waitForExistence(timeout: 10))
        let jump = app.descendants(matching: .any)["az-jump"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5), "the index is reachable while its letters are hidden")
        XCTAssertEqual(jump.label, "Jump to letter")
    }

    // MARK: screenshots (design process section 6)

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    /// My Pokémon closed and with Moltres open, light and dark, at the default text size and at AX5, saved as attachments named `my-pokemon-<state>-<mode>-<size>`.
    func testScreenshots() throws {
        launchOnMoltres().terminate()
        for (mode, size, category) in [("light", "default", "UICTContentSizeCategoryL"), ("dark", "default", "UICTContentSizeCategoryL"),
                                       ("light", "ax5", "UICTContentSizeCategoryAccessibilityXXXL"), ("dark", "ax5", "UICTContentSizeCategoryAccessibilityXXXL")] {
            let app = XCUIApplication()
            app.launchArguments = ["-appearance", mode, "-UIPreferredContentSizeCategoryName", category]
            app.launch()
            XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20))
            sleep(3)
            attach("my-pokemon-closed-\(mode)-\(size)")
            var n = 0
            while !(row(app, "Moltres").exists && row(app, "Moltres").isHittable) && n < 25 { app.swipeUp(); n += 1 }
            row(app, "Moltres").tap()
            XCTAssertTrue(app.buttons["top-pvp-row"].firstMatch.waitForExistence(timeout: 60))
            n = 0
            while !app.buttons["see-all"].isHittable && n < 4 { app.swipeUp(velocity: .slow); n += 1 }
            sleep(1)
            attach("my-pokemon-open-\(mode)-\(size)")
            app.terminate()
        }
    }
}
