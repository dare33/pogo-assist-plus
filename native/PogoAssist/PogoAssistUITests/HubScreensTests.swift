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
        XCTAssertTrue(app.staticTexts["Builds"].exists || app.buttons["collection-tab-builds"].exists)
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
        XCTAssertTrue(app.staticTexts["Gaps"].exists)
        app.buttons["collection-tab-duplicates"].tap()
        XCTAssertTrue(app.staticTexts["Duplicates"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'DUPLICATES'")).firstMatch.exists || app.staticTexts["Duplicates"].exists)
        app.buttons["collection-tab-builds"].tap()
        XCTAssertTrue(app.staticTexts["Builds"].waitForExistence(timeout: 5))
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
        app.buttons["hub-tile-everything"].tap()

        // Header: the title, "N Pokémon in your box" and the chip "owned of released".
        XCTAssertTrue(app.staticTexts["Collection"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9,]+ Pokémon in your box$")).firstMatch.exists, "the sub line")
        let chip = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+ of [0-9]+$")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertNotNil(chip.label.range(of: "^[0-9]+ of [0-9]+$", options: .regularExpression), chip.label)
        // The species panel.
        let panel = any(app, "collection-species").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertTrue(panel.label.contains("of the species in Pokémon GO"), panel.label)
        XCTAssertTrue(panel.label.contains("you can evolve now"), panel.label)
        // The sections, in order.
        for header in ["DEX BY REGION", "SHOWCASE · YOUR BEST COPIES", "SPECIAL SETS", "MISSING", "BUILDS AND CLEAN-UP"] {
            XCTAssertTrue(app.staticTexts[header].exists, header)
        }
        XCTAssertEqual(any(app, "collection-region-row").count, 9, "nine regions")
        XCTAssertTrue(any(app, "collection-region-row").firstMatch.label.hasSuffix("Kanto species"), any(app, "collection-region-row").firstMatch.label)
        XCTAssertGreaterThanOrEqual(any(app, "collection-showcase-card").count, 1, "a best copy")
        XCTAssertEqual(any(app, "collection-set").count, 7, "seven special sets")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Lucky. Not in your scans yet'")).firstMatch.exists, "Lucky reads Not in your scans yet")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '100% IVs'")).firstMatch.exists)
        XCTAssertLessThanOrEqual(any(app, "collection-missing-row").count, 6, "the first six missing")
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
            let stops: [(String, String)] = [("collection-region-row", "2"), ("collection-showcase-card", "3"), ("collection-set", "4"), ("collection-missing-row", "5"), ("collection-card-duplicates", "6")]
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
}
