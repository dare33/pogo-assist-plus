import XCTest

/// The Pogo Hub tab and the Collection screens, driven with the sample scan: the header and six tiles, the Collection, and the Collection lists with the stardust
/// card, then each in dark and at the first accessibility text size. Screenshots go to the folder in POGO_SCREENS. Not part of `swift test`.
final class HubScreensTests: XCTestCase {
    /// `folder` is a sub-folder of POGO_SCREENS (the design passes export one folder per screen: out/screens/hub-tab/).
    private func shot(_ name: String, in folder: String? = nil) {
        var dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        if let folder { dir = (dir as NSString).appendingPathComponent(folder) }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// A fresh account with the sample scan reviewed and saved (as BoxScreensTests does); leaves the app on the Box.
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

    private let tiles = ["everything", "raids", "gym", "rocket", "pvp", "max"]

    private func openHub(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Pogo Hub"].waitForExistence(timeout: 15))
        app.buttons["Pogo Hub"].tap()
        XCTAssertTrue(app.buttons["hub-tile-everything"].waitForExistence(timeout: 10), "the Hub shows its tiles")
    }

    /// Opens the Collection from the Hub, scrolls to its summary cards and opens the lists screen from one of them.
    private func openLists(_ app: XCUIApplication, card: String = "builds") {
        let tile = app.buttons["hub-tile-everything"]
        if tile.waitForExistence(timeout: 5) { tile.tap() }
        let target = app.buttons["collection-card-\(card)"]
        var n = 0
        while !target.isHittable && n < 40 { app.swipeUp(velocity: .fast); n += 1 }
        XCTAssertTrue(target.waitForExistence(timeout: 30), "the summary cards arrive with the advice")
        target.tap()
        XCTAssertTrue(app.buttons["collection-tab-\(card)"].waitForExistence(timeout: 10), "the lists screen opens")
    }

    private func setStardust(_ app: XCUIApplication, _ digits: String) {
        app.buttons["hub-stardust-change"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(digits)
        app.alerts.buttons["Save"].tap()
    }

    /// The screen's title is a text of its own, above the switch: not the switch's segment label (a button).
    private func assertTitle(_ app: XCUIApplication, _ title: String, above segment: String, file: StaticString = #filePath, line: UInt = #line) {
        let text = app.staticTexts[title]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "title \(title)", file: file, line: line)
        XCTAssertLessThan(text.frame.maxY, app.buttons[segment].frame.minY, "the title \(title) sits above the switch", file: file, line: line)
    }

    // MARK: Collection lists (design pass 2)

    func testCollectionListsBuilds() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        openLists(app)

        // Builds is the tab the Builds card opened; the title follows the switch.
        XCTAssertTrue(app.buttons["collection-tab-builds"].isSelected)
        assertTitle(app, "Builds", above: "collection-tab-builds")
        XCTAssertTrue(app.buttons["hub-stardust-change"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Not set"].exists)
        // A rejected entry says so and changes nothing; a good one shows THESE FIT.
        setStardust(app, "1234567890")   // ten digits: too many
        XCTAssertTrue(app.staticTexts["hub-stardust-problem"].waitForExistence(timeout: 5), "a bad entry is explained")
        XCTAssertTrue(app.staticTexts["Not set"].exists)
        setStardust(app, "100000")
        XCTAssertTrue(app.staticTexts["100,000"].waitForExistence(timeout: 5), "the card shows the stardust")
        XCTAssertFalse(app.staticTexts["hub-stardust-problem"].exists, "a valid entry clears the line")
        XCTAssertTrue(app.staticTexts["THESE FIT"].exists)
        // The full list, with no SHOW ALL.
        XCTAssertFalse(app.buttons["hub-show-all"].exists, "there is no SHOW ALL")
        let header = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^ALL [0-9]+ BUILDS$")).firstMatch
        XCTAssertTrue(header.exists, "the whole list has its header")
        let total = Int(header.label.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "") ?? -1
        let rows = app.buttons.matching(identifier: "hub-build-row")
        XCTAssertGreaterThanOrEqual(rows.count, 1)
        let figures = (0..<rows.count).map { (rows.element(boundBy: $0).value as? String) ?? "" }
        XCTAssertTrue(figures.contains { $0.lowercased().contains("dust") }, "a fitting build costs dust: \(figures)")
        // Scroll through the list (rows are lazy). Rule 15: a built row has the Full strength badge (its value) and no " · Free" in its line.
        var seen = Set<String>(), built = 0, n = 0
        while n < 30 && seen.count < total {
            for i in 0..<rows.count where rows.element(boundBy: i).exists {
                let row = rows.element(boundBy: i)
                if seen.insert(row.label).inserted, (row.value as? String) == "Full strength" {
                    built += 1
                    XCTAssertFalse(row.label.contains("Free"), row.label)
                }
            }
            app.swipeUp(velocity: .fast); n += 1
        }
        XCTAssertGreaterThanOrEqual(seen.count, total, "every build is listed (the THESE FIT rows add a few labels of their own)")
        XCTAssertGreaterThanOrEqual(built, 1, "the sample box has a built row with the badge")
        shot("lists-builds-end")
    }

    func testCollectionListsTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        // The Gaps card opens the Gaps tab, titled Gaps; the switch changes the tab and the title follows.
        openLists(app, card: "gaps")
        XCTAssertTrue(app.buttons["collection-tab-gaps"].isSelected)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'GAPS'")).firstMatch.waitForExistence(timeout: 5))
        assertTitle(app, "Gaps", above: "collection-tab-gaps")
        app.buttons["collection-tab-duplicates"].tap()
        assertTitle(app, "Duplicates", above: "collection-tab-duplicates")
        XCTAssertFalse(app.staticTexts["Gaps"].exists, "the title no longer reads Gaps")
        app.buttons["collection-tab-builds"].tap()
        assertTitle(app, "Builds", above: "collection-tab-builds")
        XCTAssertFalse(app.staticTexts["Duplicates"].exists, "the title no longer reads Duplicates")
        XCTAssertTrue(app.buttons["hub-stardust-change"].exists)
        // Back is the Collection.
        app.buttons["hub-back"].tap()
        XCTAssertTrue(any(app, "collection-species").firstMatch.waitForExistence(timeout: 5), "back is the Collection")
        // The Duplicates card opens the Duplicates tab.
        let dup = app.buttons["collection-card-duplicates"]
        var n = 0
        while !dup.isHittable && n < 40 { app.swipeUp(velocity: .fast); n += 1 }
        dup.tap()
        XCTAssertTrue(app.buttons["collection-tab-duplicates"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["collection-tab-duplicates"].isSelected)
    }

    func testCollectionListsScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        openLists(app)
        XCTAssertTrue(app.buttons["hub-stardust-change"].waitForExistence(timeout: 10))
        setStardust(app, "100000")
        XCTAssertTrue(app.staticTexts["100,000"].waitForExistence(timeout: 5))
        app.terminate()
        for (name, args) in [("light-default", ["-appearance", "light"]), ("dark-default", ["-appearance", "dark"]),
                             ("light-ax5", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
                             ("dark-ax5", ["-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])] {
            let again = XCUIApplication()
            again.launchArguments = args
            again.launch()
            openHub(again)
            openLists(again)
            XCTAssertTrue(again.staticTexts["100,000"].waitForExistence(timeout: 10), "the stardust is kept")
            sleep(2)
            shot("\(name)-builds-1", in: "collection-lists")
            let row = again.buttons.matching(identifier: "hub-build-row").firstMatch
            var swipes = 0
            while !row.isHittable && swipes < 30 { again.swipeUp(); swipes += 1 }
            sleep(1)
            shot("\(name)-builds-2", in: "collection-lists")
            again.swipeUp(); again.swipeUp()
            shot("\(name)-builds-3", in: "collection-lists")
            again.buttons["collection-tab-gaps"].tap()
            sleep(1)
            shot("\(name)-gaps", in: "collection-lists")
            again.buttons["collection-tab-duplicates"].tap()
            sleep(1)
            shot("\(name)-duplicates", in: "collection-lists")
            again.terminate()
        }
    }

    // MARK: Hub tab (design pass 2)

    func testHubHeaderAndTiles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)

        // The shared tab header: the account name small on the left (it opens the account menu), "Pogo Hub" centred, the More circle.
        let title = app.staticTexts.matching(identifier: "tab-title").matching(NSPredicate(format: "label == 'Pogo Hub'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "the header's title")
        let account = app.buttons["Account, Greg main"]
        XCTAssertTrue(account.exists, "the account name opens the account menu")
        XCTAssertTrue(app.buttons["More"].exists)
        XCTAssertLessThan(account.frame.midX, title.frame.midX, "the account name is on the left of the title")
        XCTAssertEqual(title.frame.midX, app.frame.midX, accuracy: 4, "the title is centred")

        XCTAssertTrue(app.staticTexts["HAPPENING NOW IN POKÉMON GO"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["hub-all-news"].exists)
        XCTAssertTrue(app.staticTexts["SQUADS AND COLLECTION"].exists)
        XCTAssertFalse(app.staticTexts["WHAT NEXT"].exists)
        XCTAssertTrue(app.buttons["hub-ranking-info"].exists)

        // Six tiles with their titles; the Collection tile's chip reads owned of released species.
        let titles = ["everything": "Collection", "raids": "Raids", "gym": "Gym battles", "rocket": "Team Rocket", "pvp": "PvP leagues", "max": "Max battles"]
        for t in tiles {
            let tile = app.buttons["hub-tile-\(t)"]
            XCTAssertTrue(tile.exists, "tile \(t)")
            XCTAssertTrue(tile.label.hasPrefix(titles[t] ?? "?"), tile.label)
        }
        let collection = app.buttons["hub-tile-everything"]
        let species = NSPredicate(format: "label MATCHES %@", "^Collection, [0-9]+ of [0-9]+ species\\..*")
        expectation(for: species, evaluatedWith: collection)
        waitForExpectations(timeout: 30)
        XCTAssertFalse(app.buttons["hub-tile-everything"].label.contains("Everything"))
        // The others carry their build counts once the advice is in.
        expectation(for: NSPredicate(format: "label CONTAINS 'build'"), evaluatedWith: app.buttons["hub-tile-max"])
        waitForExpectations(timeout: 60)
    }

    func testHubTabScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        expectation(for: NSPredicate(format: "label CONTAINS 'build'"), evaluatedWith: app.buttons["hub-tile-max"])
        waitForExpectations(timeout: 60)
        sleep(1)
        shot("light-default", in: "hub-tab")
        app.terminate()
        for (name, args) in [("dark-default", ["-appearance", "dark"]),
                             ("light-ax5", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
                             ("dark-ax5", ["-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])] {
            let again = XCUIApplication()
            again.launchArguments = args
            again.launch()
            openHub(again)
            sleep(2)
            shot(name, in: "hub-tab")
            if name.hasSuffix("ax5") { var n = 0; while !again.buttons["hub-tile-max"].isHittable && n < 25 { again.swipeUp(velocity: .fast); n += 1 }; sleep(1); shot(name + "-tiles", in: "hub-tab") }
            again.terminate()
        }
    }

    // MARK: Collection (design pass 2)

    /// Scrolls the page up (at most `swipes` times) until `element` can be tapped.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 20) {
        var n = 0
        while !element.isHittable && n < swipes { app.swipeUp(velocity: .fast); n += 1 }
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElementQuery { app.descendants(matching: .any).matching(identifier: id) }

    func testCollectionSections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        // The tile's chip arrives after the box is read; wait for the number before comparing.
        expectation(for: NSPredicate(format: "label MATCHES %@", "^Collection, [0-9]+ of [0-9]+ species.*"), evaluatedWith: app.buttons["hub-tile-everything"])
        waitForExpectations(timeout: 30)
        let tileLabel = app.buttons["hub-tile-everything"].label
        let tileCount = tileLabel.components(separatedBy: ", ").dropFirst().first?.components(separatedBy: " species").first ?? "?"
        app.buttons["hub-tile-everything"].tap()

        // Header: the title, "N Pokémon in your box" and the chip "owned of released".
        XCTAssertTrue(app.staticTexts["Collection"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9,]+ Pokémon in your box$")).firstMatch.exists, "the sub line")
        let chip = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ of [0-9]+ species$")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertNotNil(chip.label.range(of: "^[0-9]+ of [0-9]+ species$", options: .regularExpression), chip.label)
        // The Hub tile's chip and the Collection's chip are the same count.
        XCTAssertEqual(tileCount, chip.label.replacingOccurrences(of: " species", with: ""), "the tile and the Collection agree on owned of released")
        // The species panel.
        let panel = any(app, "collection-species").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertTrue(panel.label.contains("of the species in Pokémon GO"), panel.label)
        XCTAssertTrue(panel.label.contains("you can evolve now"), panel.label)
        // The sections, in order.
        for header in ["DEX BY REGION", "SHOWCASE · YOUR HIGHEST IV COPIES", "SPECIAL SETS", "MISSING", "BUILDS AND CLEAN-UP"] {
            XCTAssertTrue(app.staticTexts[header].exists, header)
        }
        XCTAssertEqual(any(app, "collection-region-row").count, 9, "nine regions")
        XCTAssertTrue(any(app, "collection-region-row").firstMatch.label.hasSuffix("Kanto species"), any(app, "collection-region-row").firstMatch.label)
        XCTAssertGreaterThanOrEqual(any(app, "collection-showcase-card").count, 1, "a highest IV copy")
        for slug in ["hundo", "legendary", "mythical", "ultra-beasts", "mega-capable", "lucky", "shadow"] { XCTAssertTrue(any(app, "collection-set-\(slug)").firstMatch.exists, "the \(slug) set card") }
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Lucky. Not in your scans yet'")).firstMatch.exists, "Lucky reads Not in your scans yet")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Hundo'")).firstMatch.exists)
        let missingRows = any(app, "collection-missing-row").count
        XCTAssertTrue((1...6).contains(missingRows), "the first six missing (\(missingRows))")
        let cards = any(app, "collection-showcase-card").count
        XCTAssertTrue((1...12).contains(cards), "up to twelve highest IV copies (\(cards))")
        let missingLabels = (0..<missingRows).map { any(app, "collection-missing-row").element(boundBy: $0).label }
        XCTAssertFalse(missingLabels.contains { $0.contains("Not in your box") }, "a missing species with no how-to-get text shows nothing there: \(missingLabels)")
        XCTAssertTrue(any(app, "collection-missing-all").firstMatch.exists)
        sleep(1)
        shot("collection-01-top")

        // A summary card opens the lists screen, back returns to the Collection.
        let builds = app.buttons["collection-card-builds"]
        scrollTo(builds, in: app)
        XCTAssertTrue(builds.waitForExistence(timeout: 30), "the summary cards arrive with the advice")
        XCTAssertTrue(builds.label.hasPrefix("Builds, "), builds.label)
        XCTAssertTrue(app.buttons["collection-card-gaps"].exists && app.buttons["collection-card-duplicates"].exists)
        builds.tap()
        XCTAssertTrue(app.buttons["hub-stardust-change"].waitForExistence(timeout: 10), "the lists screen opens")
        app.buttons["hub-back"].tap()
        XCTAssertTrue(any(app, "collection-species").firstMatch.waitForExistence(timeout: 5), "back is the Collection")
    }

    /// A Special sets card is a button that opens a sheet listing the player's Pokémon in the set, in My Pokémon's rows (phone feedback item 11).
    func testASpecialSetCardOpensItsList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        app.buttons["hub-tile-everything"].tap()
        XCTAssertTrue(any(app, "collection-species").firstMatch.waitForExistence(timeout: 15))
        let legendary = app.buttons["collection-set-legendary"]
        scrollTo(legendary, in: app)
        XCTAssertTrue(legendary.isHittable, "the Legendary card is a button")
        let card = legendary.label   // "Legendary, 3 of 52 species"
        legendary.tap()
        let sheet = any(app, "collection-set-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the sheet opens")
        XCTAssertTrue(app.staticTexts["Legendary"].exists, "titled with the set's name")
        XCTAssertEqual(app.staticTexts["collection-set-sheet-count"].label, card.replacingOccurrences(of: "Legendary, ", with: ""), "and the card's count")
        // The sheet's own rows: My Pokémon's list stays in the tree behind it.
        func row(_ species: String) -> XCUIElement { sheet.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH %@", "\(species),")).firstMatch }
        let moltres = row("Moltres")
        XCTAssertTrue(moltres.waitForExistence(timeout: 15), "an owned legendary species is listed")
        XCTAssertFalse(row("Blissey").exists, "a species outside the set is not")
        XCTAssertTrue(moltres.label.hasSuffix("Opens in place"), moltres.label)
        moltres.tap()
        XCTAssertTrue(sheet.buttons["see-all"].waitForExistence(timeout: 10), "it opens in place, as on My Pokémon")
        XCTAssertTrue(sheet.buttons["top-ivs-row"].firstMatch.waitForExistence(timeout: 10))
        sheet.buttons["top-ivs-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 15), "a copy opens its Pokémon page from the sheet")
        sheet.buttons["Back"].firstMatch.tap()
        let done = app.buttons["collection-set-sheet-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "Done closes the sheet")
        XCTAssertTrue(legendary.waitForExistence(timeout: 5), "back on the Collection")
    }

    /// "See all" inside the sheet opens the species list, Back returns to the sheet, and Done closes it. A copy marked Lucky from the sheet then moves the Lucky card
    /// from "Not in your scans yet" to a count of one, and its sheet lists the species.
    func testSeeAllInTheSheetAndAnEditFromIt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        app.buttons["hub-tile-everything"].tap()
        XCTAssertTrue(any(app, "collection-species").firstMatch.waitForExistence(timeout: 15))
        let legendary = app.buttons["collection-set-legendary"]
        scrollTo(legendary, in: app)
        legendary.tap()
        let sheet = any(app, "collection-set-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let moltres = sheet.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Moltres,'")).firstMatch
        XCTAssertTrue(moltres.waitForExistence(timeout: 15))
        moltres.tap()
        XCTAssertTrue(sheet.buttons["see-all"].waitForExistence(timeout: 10))
        sheet.buttons["see-all"].tap()
        XCTAssertTrue(sheet.buttons.matching(identifier: "pokemon-row").firstMatch.waitForExistence(timeout: 15), "the species list opens inside the sheet")
        sheet.buttons.matching(identifier: "pokemon-row").firstMatch.tap()
        XCTAssertTrue(app.buttons["mark-advanced"].waitForExistence(timeout: 15), "a copy's page opens")
        app.buttons["mark-advanced"].tap()
        let luckyFlag = app.descendants(matching: .any).matching(identifier: "flag-lucky").firstMatch
        XCTAssertTrue(luckyFlag.waitForExistence(timeout: 10))
        luckyFlag.tap()
        sheet.buttons["Back"].firstMatch.tap()   // the page
        sheet.buttons["Back"].firstMatch.tap()   // the species list
        XCTAssertTrue(app.buttons["collection-set-sheet-done"].waitForExistence(timeout: 10), "back on the sheet")
        app.buttons["collection-set-sheet-done"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10), "Done closes the sheet")
        let lucky = app.buttons["collection-set-lucky"]
        scrollTo(lucky, in: app)
        expectation(for: NSPredicate(format: "label == 'Lucky, 1 copy'"), evaluatedWith: lucky)
        waitForExpectations(timeout: 30)
        lucky.tap()
        XCTAssertTrue(app.staticTexts["collection-set-sheet-count"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["collection-set-sheet-count"].label, "1 copy")
        XCTAssertTrue(any(app, "collection-set-sheet").firstMatch.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Moltres,'")).firstMatch.waitForExistence(timeout: 15))
    }

    func testLuckyWithNoMarkedCopyOpensASheetThatSaysSo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        app.buttons["hub-tile-everything"].tap()
        XCTAssertTrue(any(app, "collection-species").firstMatch.waitForExistence(timeout: 15))
        let lucky = app.buttons["collection-set-lucky"]
        scrollTo(lucky, in: app)
        XCTAssertEqual(lucky.label, "Lucky. Not in your scans yet")
        lucky.tap()
        XCTAssertTrue(app.staticTexts["collection-set-sheet-count"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["collection-set-sheet-count"].label, "Not in your scans yet")
        XCTAssertEqual(any(app, "collection-set-sheet").firstMatch.staticTexts.matching(NSPredicate(format: "label == 'Not in your scans yet'")).count, 1, "the note is there once")
        XCTAssertFalse(app.staticTexts["collection-set-sheet-empty"].exists)
        XCTAssertEqual(any(app, "collection-set-sheet").firstMatch.buttons.matching(identifier: "species-row").count, 0)
        app.buttons["collection-set-sheet-done"].tap()
        XCTAssertTrue(lucky.waitForExistence(timeout: 5))
    }

    /// A Zapdos copy renamed to its Galarian form is a second Zapdos row under Legendary: the sheet says "Forms are listed separately." while the card still counts one species.
    /// Also takes the screenshots of that sheet and of the empty Lucky sheet (out/screens/fb-collection-r3).
    func testTheFormsLineAndTheEmptyLuckySheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        app.buttons["hub-tile-everything"].tap()
        XCTAssertTrue(any(app, "collection-species").firstMatch.waitForExistence(timeout: 15))
        let legendary = app.buttons["collection-set-legendary"]
        scrollTo(legendary, in: app)
        legendary.tap()
        let sheet = any(app, "collection-set-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["collection-set-sheet-forms"].exists, "one row a species: no forms line")
        let zapdos = sheet.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Zapdos,'")).firstMatch
        XCTAssertTrue(zapdos.waitForExistence(timeout: 15))
        zapdos.tap()
        XCTAssertTrue(sheet.buttons["top-ivs-row"].firstMatch.waitForExistence(timeout: 10))
        sheet.buttons["top-ivs-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 15))
        app.buttons["Fix a value"].tap()
        let name = app.textFields["Species name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        name.typeText("Zapdos (Galarian")
        let suggestion = app.buttons["Zapdos (Galarian)"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        suggestion.tap()
        app.buttons["Save"].tap()
        // A species with other base stats than the copy's CP and IVs fit says so in an alert (the values are kept and the copy marked for a check). The alert shows over
        // the sheet and the player is still in the set when it is dismissed (eyeball check F1): it used to take the sheet down with it.
        let ok = app.alerts.buttons["OK"]
        if ok.waitForExistence(timeout: 15) {
            XCTAssertTrue(sheet.exists, "the sheet is still there under the alert")
            ok.tap()
        }
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "still in the set after the alert is dismissed")
        XCTAssertTrue(sheet.buttons["Back"].firstMatch.waitForExistence(timeout: 10), "and still on the copy's page, where the player was")
        XCTAssertTrue(app.alerts.count == 0)
        sheet.buttons["Back"].firstMatch.tap()   // the page, back to the set's list
        XCTAssertTrue(app.buttons["collection-set-sheet-done"].waitForExistence(timeout: 10), "the set's list")
        XCTAssertTrue(app.staticTexts["collection-set-sheet-forms"].waitForExistence(timeout: 30), "two Zapdos rows, one species")
        XCTAssertEqual(app.staticTexts["collection-set-sheet-count"].label, "5 of 52 species", "forms do not change the species count")
        app.terminate()
        for (name, args) in [("light-default", ["-appearance", "light"]), ("dark-default", ["-appearance", "dark"]),
                             ("light-ax5", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
                             ("dark-ax5", ["-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])] {
            let again = XCUIApplication()
            again.launchArguments = args
            again.launch()
            openHub(again)
            again.buttons["hub-tile-everything"].tap()
            XCTAssertTrue(any(again, "collection-species").firstMatch.waitForExistence(timeout: 15))
            let card = again.buttons["collection-set-legendary"]
            scrollTo(card, in: again)
            card.tap()
            XCTAssertTrue(again.staticTexts["collection-set-sheet-forms"].waitForExistence(timeout: 30))
            sleep(2)
            shot("collection-set-sheet-forms-\(name)", in: "fb-collection-r3")
            again.buttons["collection-set-sheet-done"].tap()
            let lucky = again.buttons["collection-set-lucky"]
            scrollTo(lucky, in: again)
            lucky.tap()
            XCTAssertTrue(again.staticTexts["collection-set-sheet-count"].waitForExistence(timeout: 10))
            sleep(2)
            shot("collection-set-sheet-lucky-empty-\(name)", in: "fb-collection-r3")
            again.terminate()
        }
    }

    /// The Collection's cards and an open set's sheet, for Greg's page: out/screens/fb-collection (phone feedback item 11).
    func testSpecialSetsScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        expectation(for: NSPredicate(format: "label CONTAINS 'build'"), evaluatedWith: app.buttons["hub-tile-max"])
        waitForExpectations(timeout: 60)
        app.terminate()
        for (name, args) in [("light-default", ["-appearance", "light"]), ("dark-default", ["-appearance", "dark"]),
                             ("light-ax5", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
                             ("dark-ax5", ["-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])] {
            let again = XCUIApplication()
            again.launchArguments = args
            again.launch()
            openHub(again)
            again.buttons["hub-tile-everything"].tap()
            XCTAssertTrue(any(again, "collection-species").firstMatch.waitForExistence(timeout: 15))
            let card = again.buttons["collection-set-legendary"]
            scrollTo(card, in: again)
            sleep(1)
            shot("collection-cards-\(name)", in: "fb-collection-r3")
            card.tap()
            XCTAssertTrue(any(again, "collection-set-sheet").firstMatch.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 15))
            sleep(2)
            shot("collection-set-sheet-\(name)", in: "fb-collection-r3")
            again.terminate()
        }
    }

    func testCollectionScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        expectation(for: NSPredicate(format: "label CONTAINS 'build'"), evaluatedWith: app.buttons["hub-tile-max"])
        waitForExpectations(timeout: 60)
        app.terminate()
        for (name, args) in [("light-default", ["-appearance", "light"]), ("dark-default", ["-appearance", "dark"]),
                             ("light-ax5", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]),
                             ("dark-ax5", ["-appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])] {
            let again = XCUIApplication()
            again.launchArguments = args
            again.launch()
            openHub(again)
            again.buttons["hub-tile-everything"].tap()
            XCTAssertTrue(any(again, "collection-species").firstMatch.waitForExistence(timeout: 15))
            sleep(2)
            shot("\(name)-1", in: "collection")
            let stops: [(String, String)] = [("collection-region-row", "2"), ("collection-showcase-card", "3"), ("collection-set-legendary", "4"), ("collection-missing-row", "5"), ("collection-card-duplicates", "6")]
            for (id, n) in stops {
                let target = any(again, id).firstMatch
                var swipes = 0
                while !target.isHittable && swipes < 60 { again.swipeUp(); swipes += 1 }
                sleep(1)
                shot("\(name)-\(n)", in: "collection")
            }
            again.terminate()
        }
    }

    // MARK: tiles and an empty box (review round 1)

    func testEveryHubTileOpensItsScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        for (tile, title) in [("everything", "Collection"), ("raids", "Raids"), ("max", "Max battles"), ("gym", "Gym battles"), ("rocket", "Team Rocket"), ("pvp", "PvP leagues")] {
            let button = app.buttons["hub-tile-\(tile)"]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "tile \(tile)")
            button.tap()
            // The back circle by its label: a screen's own container identifier can hide the circle's "hub-back".
            XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 15), "\(title) opens")
            XCTAssertTrue(app.staticTexts[title].exists, "the \(title) screen is titled \(title)")
            app.buttons["Back"].tap()
            XCTAssertTrue(app.buttons["hub-tile-\(tile)"].waitForExistence(timeout: 10), "back to the Hub from \(title)")
        }
    }

    func testAnEmptyBoxStillShowsTheCollectionAtZero() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        openHub(app)
        let tile = app.buttons["hub-tile-everything"]
        XCTAssertNotNil(tile.label.range(of: "^Collection, 0 of [0-9]+ species", options: .regularExpression), "the tile reads 0 of the released species: \(tile.label)")
        tile.tap()
        XCTAssertTrue(any(app, "collection-species").firstMatch.waitForExistence(timeout: 10), "the species panel is there")
        XCTAssertTrue(any(app, "collection-species").firstMatch.label.hasPrefix("0 of "), any(app, "collection-species").firstMatch.label)
        XCTAssertEqual(any(app, "collection-region-row").count, 9)
        XCTAssertTrue(app.staticTexts["MISSING"].exists)
        XCTAssertTrue(any(app, "collection-empty").firstMatch.exists, "the scan prompt is an extra line, not instead")
        let prompts = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'the Collection will fill in'"))
        XCTAssertEqual(prompts.count, 1, "one scan prompt, not two")
    }
}
