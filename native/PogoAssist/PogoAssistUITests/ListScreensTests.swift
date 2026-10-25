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
        XCTAssertEqual(app.staticTexts["species-order"].label, "Raids first")
        let tags = app.buttons.matching(identifier: "pokemon-tag").allElementsBoundByIndex.map(\.label)
        // The tag's tap target is the chip (about 20 pt) plus 6 pt above and below, about 32 pt: no more, so that two rows' targets and the IVs line are never overlapped.
        for t in app.buttons.matching(identifier: "pokemon-tag").allElementsBoundByIndex { XCTAssertGreaterThanOrEqual(t.frame.height, 30, "tap target of \(t.label)"); XCTAssertLessThan(t.frame.height, 40, "and not 44: \(t.label)") }
        XCTAssertEqual(tags.count, 6, "every copy has its tag: " + tags.joined(separator: " | "))
        let rank = { (t: String) in t.hasPrefix("Strong") ? 0 : t.hasPrefix("OK") ? 1 : 2 }
        XCTAssertEqual(tags.map(rank), tags.map(rank).sorted(), "Weak last: " + tags.joined(separator: " | "))
        XCTAssertTrue(tags.contains { $0.hasPrefix("Weak") })
        XCTAssertTrue(tags.contains { $0.contains(", best as ") }, "the best-of tag for the area is merged into the status tag: " + tags.joined(separator: " | "))
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
        // The rows' tap targets are 6 pt taller than the chip each way and do not overlap: a tap on the bottom edge of Raids' target opens Raids, not Gym's line.
        raids.tap()
        XCTAssertTrue(line.waitForNonExistence(timeout: 3))
        raids.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).tap()
        XCTAssertTrue(line.waitForExistence(timeout: 3), "the bottom of the Raids target opens Raids")
        XCTAssertFalse(app.staticTexts["activity-gym-line"].exists, "and not the Gym line under it")
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
                let ready = NSPredicate(format: "label CONTAINS 'Great League'")
                expectation(for: ready, evaluatedWith: rows(app).firstMatch)
                waitForExpectations(timeout: 60)
            } else {
                app = launchPopulated(["-appearance", "light", "-UIPreferredContentSizeCategoryName", category])
            }
            sleep(1); app.swipeUp(velocity: .slow); sleep(1)   // the saved panel pushes the chips and the sort line down at the large sizes
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

    /// The Pokémon list's header (count line, search, chips, sort line with the ranking switch) is fixed: after the list is scrolled well down it is where it was,
    /// still hittable, and the species rows have moved under it. At the default size, AX3 and AX5 (light), and default and AX5 in dark; the ranking explainer is
    /// opened inside the fixed block too. Screenshots go to POGO_SCREENS.
    func testHeaderStaysFixedAtTheDefaultSize() throws { try headerFixed("hdr-default-light", "UICTContentSizeCategoryL", "light") }
    func testHeaderStaysFixedInDark() throws { try headerFixed("hdr-default-dark", "UICTContentSizeCategoryL", "dark") }
    func testHeaderStaysFixedAtAX3() throws { try headerFixed("hdr-ax3-light", "UICTContentSizeCategoryAccessibilityXL", "light") }
    func testHeaderStaysFixedAtAX5() throws { try headerFixed("hdr-ax5-light", "UICTContentSizeCategoryAccessibilityXXXL", "light") }
    func testHeaderStaysFixedAtAX5InDark() throws { try headerFixed("hdr-ax5-dark", "UICTContentSizeCategoryAccessibilityXXXL", "dark") }

    private func headerFixed(_ name: String, _ category: String, _ appearance: String) throws {
        launchPopulated().terminate()
        let app = XCUIApplication()
        app.launchArguments = ["-appearance", appearance, "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        let search = app.textFields["box-search"], sort = app.descendants(matching: .any)["sort-menu"], chipAll = app.buttons["chip-all"]
        XCTAssertTrue(search.waitForExistence(timeout: 10) && sort.exists && chipAll.exists, name)
        let before = (search.frame, sort.frame, chipAll.frame)
        shot("\(name)-top")
        let firstRow = rows(app).firstMatch.label
        for _ in 0..<4 { app.swipeUp(); }
        sleep(1)
        XCTAssertEqual(search.frame, before.0, "\(name): the search field did not move")
        XCTAssertEqual(sort.frame, before.1, "\(name): the sort line did not move")
        XCTAssertEqual(chipAll.frame, before.2, "\(name): the chips did not move")
        XCTAssertTrue(search.isHittable && sort.isHittable, name)
        XCTAssertNotEqual(rows(app).firstMatch.label, firstRow, "\(name): the list did scroll")
        shot("\(name)-scrolled")
        // The explainer opens inside the fixed block.
        let info = app.buttons["list-scoring-info"]
        XCTAssertTrue(info.exists, name)
        info.tap()
        XCTAssertTrue(app.descendants(matching: .any)["list-scoring-explainer"].waitForExistence(timeout: 5), "\(name): the explainer opens in the header")
        XCTAssertTrue(search.isHittable || search.exists, "\(name): the header is still there with the explainer open")
        XCTAssertTrue(rows(app).firstMatch.exists, "\(name): some of the list is left under an open explainer")
        sleep(1); shot("\(name)-explainer")
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
