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
    /// The row of a species further down the list than the first screen: the fixed header leaves the list less room and the list is lazy, so scroll until it is built.
    private func reveal(_ app: XCUIApplication, _ species: String) -> XCUIElement {
        var n = 0
        while !row(app, species).exists && n < 8 { app.swipeUp(); n += 1 }
        return row(app, species)
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
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(name + "\n")   // Return puts the keyboard away, so the opened species is not under it
        // A species with a form reads "Zamazenta (Hero), 3 Pokémon", so match the name's start, not "name,".
        let r = rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(r.waitForExistence(timeout: 5), "\(name) is in the sample box")
        app.openSpeciesList(r)
    }
    private func launchPopulated(_ extra: [String] = ["-appearance", "light"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"] + extra
        app.launch()
        populate(app)
        // The tiles and the chips read the advice; wait for it (a tile that has it never says "…").
        XCTAssertTrue(row(app, "Blissey").waitForExistence(timeout: 10))
        app.awaitInsight()
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
        let all = reveal(app, "Moltres").label
        XCTAssertTrue(all.hasPrefix("Moltres, 6 Pokémon"), all)
        XCTAssertTrue(row(app, "Blissey").exists)
        app.buttons["chip-raids"].tap()
        XCTAssertTrue(app.buttons["chip-raids"].isSelected)
        let moltres = reveal(app, "Moltres")
        XCTAssertTrue(moltres.waitForExistence(timeout: 5))
        XCTAssertTrue(moltres.label.hasPrefix("Moltres, 3 Pokémon, Good for Raids"), "the capsule counts the matching copies: " + moltres.label)
        XCTAssertFalse(row(app, "Blissey").exists, "a species with no Top or Good copy for Raids is gone")
        XCTAssertTrue(reveal(app, "Lucario").label.contains("Top for Raids"), reveal(app, "Lucario").label)
        sleep(1); shot("list-raids-chip")
        app.buttons["chip-all"].tap()
        XCTAssertTrue(row(app, "Blissey").waitForExistence(timeout: 5))
        XCTAssertTrue(reveal(app, "Moltres").label.hasPrefix("Moltres, 6 Pokémon"))
    }

    /// A league chip keeps the species with a Top or Good copy for that league under the shown pick; Great League is over the cap for this whole box.
    func testALeagueChipFilters() throws {
        let app = launchPopulated()
        resetRanking(app)
        app.buttons["chip-ml"].tap()
        let xerneas = reveal(app, "Xerneas")
        XCTAssertTrue(xerneas.waitForExistence(timeout: 5))
        XCTAssertTrue(xerneas.label.hasPrefix("Xerneas, 2 Pokémon, Top for Master"), xerneas.label)
        XCTAssertFalse(row(app, "Blissey").exists, "a species with no Top or Good copy for Master League is gone")
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

    /// The league tiles left the species row with design pass 3 (the open species' TOP PVP says it instead): Blissey is over the cap for Great League and fits Ultra
    /// League; the pick follows the ranking switch, which is the same app-wide preference the species list shows.
    func testTopPvPShowsTheLeagueAndFollowsTheRanking() throws {
        let app = launchPopulated()
        resetRanking(app)
        let search = app.textFields["box-search"]
        search.tap(); search.typeText("Blissey\n")
        let blissey = row(app, "Blissey")
        XCTAssertTrue(blissey.waitForExistence(timeout: 5))
        blissey.tap()
        let pvp = app.buttons["top-pvp-row"].firstMatch
        XCTAssertTrue(pvp.waitForExistence(timeout: 10))
        XCTAssertTrue(pvp.label.contains("Ultra League: Blissey"), pvp.label)
        XCTAssertFalse(pvp.label.contains("Great League"), "over the cap for Great League: " + pvp.label)
        app.buttons["Clear search"].tap()
        // A species whose pick differs between the rankings (the sample's Scyther: Classic takes the IV fit, Pogo Assist the stronger Scizor).
        let control = app.descendants(matching: .any)["list-scoring"]
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "Pogo Assist")
        search.tap(); search.typeText("Scyther\n")   // Return closes the keyboard, so the switch can be tapped
        XCTAssertTrue(row(app, "Scyther").waitForExistence(timeout: 5))
        row(app, "Scyther").tap()
        XCTAssertTrue(app.buttons["top-pvp-row"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["top-pvp-row"].firstMatch.label.contains("Ultra League: Scizor"), app.buttons["top-pvp-row"].firstMatch.label)
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "Classic")
        XCTAssertTrue(app.buttons["top-pvp-row"].firstMatch.label.contains("Ultra League: Scyther"), app.buttons["top-pvp-row"].firstMatch.label)
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        app.buttons["Clear search"].tap()
        XCTAssertTrue(reveal(app, "Moltres").waitForExistence(timeout: 5))
        app.openSpeciesList(row(app, "Moltres"))
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
        app.openSpeciesList(row(app, "Charizard"))
        let copy = app.buttons.matching(identifier: "pokemon-row").firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        // The numbered places replace the old "best for" tags: the copies that are first for a use say so in their label, and the card carries the member.
        func placed(_ words: String) -> Bool { app.buttons.matching(identifier: "pokemon-row").matching(NSPredicate(format: "label CONTAINS[c] %@", words)).count > 0 }
        XCTAssertFalse(placed("for Master League"), "Charizard's Master League copy is Weak, so it is never numbered")
        XCTAssertTrue(placed("number 1 for Raids"), "a copy is first for Raids")
        XCTAssertFalse(copy.label.contains("Best for"), copy.label)
        XCTAssertTrue(app.staticTexts["tags-note"].exists)
        XCTAssertFalse(app.buttons["pokemon-tag"].exists, "no per-copy tag without a chip")
        XCTAssertEqual(app.staticTexts["species-order"].label, "Best IVs first")
        XCTAssertTrue(app.staticTexts["Charizard · \(app.buttons.matching(identifier: "pokemon-row").count)"].exists, "plain header without a chip")
        // The order label and the ranking switch share one line at the default size.
        let order = app.staticTexts["species-order"].frame, switchFrame = app.descendants(matching: .any)["species-scoring"].frame
        XCTAssertLessThan(abs(order.midY - switchFrame.midY), 20, "order \(order) and switch \(switchFrame) on one line")
        app.buttons["Back"].tap()

        app.buttons["chip-raids"].tap()
        app.openSpeciesList(row(app, "Moltres"))
        XCTAssertTrue(app.buttons["pokemon-tag"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Moltres · 3 of 6 for Raids"].exists, "the header counts the Top and Good copies under the chip")
        XCTAssertEqual(app.staticTexts["species-order"].label, "Raids first")
        let tags = app.buttons.matching(identifier: "pokemon-tag").allElementsBoundByIndex.map(\.label)
        // The tag's tap target is the chip (about 20 pt) plus 6 pt above and below, about 32 pt: no more, so that two rows' targets and the IVs line are never overlapped.
        for t in app.buttons.matching(identifier: "pokemon-tag").allElementsBoundByIndex { XCTAssertGreaterThanOrEqual(t.frame.height, 30, "tap target of \(t.label)"); XCTAssertLessThan(t.frame.height, 40, "and not 44: \(t.label)") }
        XCTAssertEqual(tags.count, 6, "every copy has its tag: " + tags.joined(separator: " | "))
        let rank = { (t: String) in t.hasPrefix("Top") ? 0 : t.hasPrefix("Good") ? 1 : 2 }
        XCTAssertEqual(tags.map(rank), tags.map(rank).sorted(), "Weak last: " + tags.joined(separator: " | "))
        XCTAssertTrue(tags.contains { $0.hasPrefix("Weak") })
        XCTAssertFalse(tags.contains { $0.contains(", best") }, "the status tag no longer carries the merged best-of text: " + tags.joined(separator: " | "))
        XCTAssertTrue(app.buttons.matching(identifier: "pokemon-row").matching(NSPredicate(format: "label CONTAINS[c] %@", "number 1 for Raids")).count > 0, "the first copy for Raids is marked under the chip")
        let weak = app.buttons.matching(NSPredicate(format: "identifier == 'pokemon-tag' AND label BEGINSWITH 'Weak'")).firstMatch
        weak.tap()
        let line = app.staticTexts["pokemon-tag-line"]
        XCTAssertTrue(line.waitForExistence(timeout: 3))
        XCTAssertFalse(line.label.isEmpty)
        sleep(1); shot("species-raids-chip")
        weak.tap()
        XCTAssertFalse(app.staticTexts["pokemon-tag-line"].exists, "tapping again closes it")
        // A tap on the row away from the chips opens the copy, not the tag: left of centre near the top, and beside the chip at the chip's own height (right of it, on
        // the same line), where a tap that reached the chip's tap target would open its line instead.
        for (dx, centredOnChip) in [(0.15, false), (0.93, true)] {
            let copy = app.buttons.matching(identifier: "pokemon-row").firstMatch
            var dy = 0.25
            if centredOnChip {
                let tag = app.buttons.matching(identifier: "pokemon-tag").firstMatch
                XCTAssertTrue(tag.waitForExistence(timeout: 5))
                dy = Double((tag.frame.midY - copy.frame.minY) / copy.frame.height)
            }
            copy.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
            XCTAssertTrue(copy.waitForNonExistence(timeout: 5), "a tap at \(dx), \(dy) across the row opens the copy")
            XCTAssertFalse(app.staticTexts["pokemon-tag-line"].exists)
            app.buttons["Back"].firstMatch.tap()
            XCTAssertTrue(app.buttons["pokemon-row"].firstMatch.waitForExistence(timeout: 5))
        }
    }

    /// The page's Summary tab lists the five activities (PvP leagues first), each a button that opens its tab.
    func testDetailSummaryRows() throws {
        let app = launchPopulated()
        app.openSpeciesList(row(app, "Charizard"))
        app.buttons.matching(identifier: "pokemon-row").firstMatch.tap()
        let raids = app.buttons["summary-row-raids"]
        XCTAssertTrue(raids.waitForExistence(timeout: 20))
        XCTAssertTrue(raids.label.hasPrefix("Raids. "), raids.label)
        for area in ["pvp", "gym", "rocket", "max"] { XCTAssertTrue(app.buttons["summary-row-\(area)"].exists, area) }
        XCTAssertLessThan(app.buttons["summary-row-pvp"].frame.minY, raids.frame.minY, "PvP leagues come first")
        raids.tap()
        XCTAssertTrue(app.descendants(matching: .any)["raids-tab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["page-tab-raids"].isSelected)
        sleep(1); shot("detail-summary-raids-tab")
    }

    /// The Zamazenta (Hero) with CP 2661 carries the advisor's build for an area: a Summary row shows its upgrade mark with the cost spoken in grouped figures.
    func testDetailSummaryRowShowsTheBuildCost() throws {
        let app = launchPopulated()
        openSpecies(app, "Zamazenta")
        let copy = app.buttons.matching(NSPredicate(format: "identifier == 'pokemon-row' AND label CONTAINS '2661'")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
        let costly = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'summary-row-' AND label CONTAINS 'Upgrade available'")).firstMatch
        XCTAssertTrue(costly.waitForExistence(timeout: 20), "a Summary row with an upgrade mark")
        XCTAssertTrue(costly.label.contains("dust") || costly.label.contains("candy"), costly.label)
        sleep(1); shot("detail-summary-builds")
    }

    /// A hand fix made on the Pokémon page, then back to the list under a chip: the Box screen's tasks fire while the child screens are pushed, so the list is
    /// rebuilt (Fixed by hand appears), the advice is worked out again and the chip's rows come back without the list blanking to "Working out advice…" for good.
    func testAHandFixFromTheDetailPageReachesTheListUnderAChip() throws {
        let app = launchPopulated()
        app.buttons["chip-raids"].tap()
        XCTAssertFalse(app.buttons["chip-fixed"].exists)
        app.openSpeciesList(row(app, "Moltres"))
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
            app.openSpeciesList(rows(app).firstMatch)
            XCTAssertTrue(app.buttons["pokemon-row"].firstMatch.waitForExistence(timeout: 5))
            sleep(1); shot("\(tag)-species")
            openFirstCopy(app)
            XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["summary-row-raids"].waitForExistence(timeout: 30))
            sleep(1); shot("\(tag)-detail-summary")
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

    /// The species list under Raids at the default size, xxxLarge and the accessibility sizes 3 and 5: the merged chip wraps instead of running off the edge, the
    /// order label is whole ("Raids first") and the ranking switch is on the screen. The Pokémon list's sort line is shot at xxxLarge and AX1 too.
    func testSpeciesListUnderRaidsAtTheDefaultSize() throws { try speciesListUnderRaids("default", "UICTContentSizeCategoryL") }
    func testSpeciesListUnderRaidsAtXXXLarge() throws { try speciesListUnderRaids("xxxl", "UICTContentSizeCategoryXXXL") }
    func testSpeciesListUnderRaidsAtAX1() throws { try speciesListUnderRaids("ax1", "UICTContentSizeCategoryAccessibilityM") }
    func testSpeciesListUnderRaidsAtAX3() throws { try speciesListUnderRaids("ax3", "UICTContentSizeCategoryAccessibilityXL") }
    func testSpeciesListUnderRaidsAtAX5() throws { try speciesListUnderRaids("ax5", "UICTContentSizeCategoryAccessibilityXXXL") }

    private func speciesListUnderRaids(_ name: String, _ category: String) throws {
        do {
            let app: XCUIApplication
            if category.contains("Accessibility") && category != "UICTContentSizeCategoryAccessibilityM" {
                // The sample-scan set-up screens do not fit at the largest sizes: build the box at the default size, then relaunch at this one with the box kept.
                launchPopulated().terminate()
                app = XCUIApplication()
                app.launchArguments = ["-appearance", "light", "-UIPreferredContentSizeCategoryName", category]
                app.launch()
                XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20))
                app.awaitInsight()   // the advice is read from the box saved by the default-size launch above
            } else {
                app = launchPopulated(["-appearance", "light", "-UIPreferredContentSizeCategoryName", category])
            }
            sleep(2)
            shot("size-\(name)-list")
            let sort = app.descendants(matching: .any)["sort-menu"], list = app.descendants(matching: .any)["list-scoring"]
            XCTAssertTrue(sort.waitForExistence(timeout: 10) && list.exists, "\(name): the sort line")
            XCTAssertLessThanOrEqual(list.frame.maxX, app.frame.width + 0.5, "\(name): the ranking switch is on the screen")
            app.buttons["chip-raids"].tap()
            openSpecies(app, "Moltres")
            XCTAssertTrue(app.buttons["pokemon-tag"].firstMatch.waitForExistence(timeout: 10), name)
            sleep(1); shot("size-\(name)-species-raids")
            XCTAssertEqual(app.staticTexts["species-order"].label, "Raids first", name)
            let order = app.staticTexts["species-order"].frame, switchFrame = app.descendants(matching: .any)["species-scoring"].frame
            XCTAssertGreaterThanOrEqual(order.width, 60, "\(name): the label is not squeezed")
            XCTAssertLessThanOrEqual(switchFrame.maxX, app.frame.width + 0.5, "\(name): the switch is on the screen")
            for t in app.buttons.matching(identifier: "pokemon-tag").allElementsBoundByIndex where t.isHittable {
                XCTAssertLessThanOrEqual(t.frame.maxX, app.frame.width + 0.5, "\(name): the chip stays on the screen: \(t.label)")
            }
            app.terminate()
        }
    }

    /// My Pokémon's search field stays under the header while the list scrolls (design pass 3, D7); the count line, chips, sort line and the saved-scan panel scroll
    /// with the list (READBACK Q7). After the list is scrolled well down the search is where it was and hittable, the chips are gone from the screen, and the rows have
    /// moved. At the default size and AX5, in light and dark. Screenshots go to POGO_SCREENS.
    func testSearchStaysFixedAtTheDefaultSize() throws { try searchFixed("hdr-default-light", "UICTContentSizeCategoryL", "light") }
    func testSearchStaysFixedInDark() throws { try searchFixed("hdr-default-dark", "UICTContentSizeCategoryL", "dark") }
    func testSearchStaysFixedAtAX3() throws { try searchFixed("hdr-ax3-light", "UICTContentSizeCategoryAccessibilityXL", "light") }
    func testSearchStaysFixedAtAX3InDark() throws { try searchFixed("hdr-ax3-dark", "UICTContentSizeCategoryAccessibilityXL", "dark") }
    func testSearchStaysFixedAtAX5InDark() throws { try searchFixed("hdr-ax5-dark", "UICTContentSizeCategoryAccessibilityXXXL", "dark") }

    /// The saved-scan panel is the top of the scrolling list: right after the save it is there, under the fixed search field, and it scrolls away with the list while
    /// the search stays (no relaunch: the panel goes with one).
    func testTheSavedScanPanelScrollsAwayWhileTheSearchStays() throws {
        let app = launchPopulated()
        sleep(1)
        let panel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to'")).firstMatch
        let search = app.textFields["box-search"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10) && panel.isHittable, "the saved-scan panel is on the list right after the save")
        let frame = search.frame
        for _ in 0..<3 { app.swipeUp() }
        sleep(1)
        XCTAssertEqual(search.frame, frame, "the search field did not move")
        XCTAssertFalse(panel.isHittable, "the panel scrolled away with the list")
        shot("hdr-saved-panel")
    }

    /// The ranking explainer opens inside the scrolling list, under the sort line, and the list is still there under it.
    func testTheRankingExplainerOpensInTheList() throws {
        let app = launchPopulated()
        let info = app.buttons["list-scoring-info"]
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        info.tap()
        let explainer = app.descendants(matching: .any)["list-scoring-explainer"]
        XCTAssertTrue(explainer.waitForExistence(timeout: 5), "the explainer opens")
        sleep(1)
        XCTAssertTrue(explainer.isHittable, "the open explainer is on the screen")
        XCTAssertTrue(app.textFields["box-search"].isHittable, "the search is still there")
        XCTAssertGreaterThan(app.buttons.matching(identifier: "species-row").count, 0, "rows follow the explainer in the list")
        info.tap()
        XCTAssertTrue(explainer.waitForNonExistence(timeout: 5), "and it closes")
    }

    func testSearchStaysFixedAtAX5() throws { try searchFixed("hdr-ax5-light", "UICTContentSizeCategoryAccessibilityXXXL", "light") }

    private func searchFixed(_ name: String, _ category: String, _ appearance: String) throws {
        launchPopulated().terminate()
        let app = XCUIApplication()
        app.launchArguments = ["-appearance", appearance, "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        let search = app.textFields["box-search"], chipAll = app.buttons["chip-all"]
        XCTAssertTrue(search.waitForExistence(timeout: 10) && chipAll.exists, name)
        XCTAssertTrue(app.staticTexts["tab-title"].exists, "\(name): the header names the tab")
        let searchFrame = search.frame, firstRow = rows(app).firstMatch.label
        shot("\(name)-top")
        for _ in 0..<5 { app.swipeUp() }
        sleep(1)
        XCTAssertEqual(search.frame, searchFrame, "\(name): the search field did not move")
        XCTAssertTrue(search.isHittable, name)
        XCTAssertFalse(chipAll.isHittable, "\(name): the chips scrolled away with the list")
        XCTAssertNotEqual(rows(app).firstMatch.label, firstRow, "\(name): the list did scroll")
        shot("\(name)-scrolled")
        // The search focused with the keyboard up: still hittable, and the keyboard closes with Return.
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "\(name): the keyboard is up")
        XCTAssertTrue(search.isHittable, name)
        search.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), name)
        app.terminate()
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
