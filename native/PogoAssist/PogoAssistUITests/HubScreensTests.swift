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

    func testHubTilesAndEverything() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)

        // The tiles; the build counts arrive with the advice, so the Raids tile's label gains "N builds".
        for t in tiles { XCTAssertTrue(app.buttons["hub-tile-\(t)"].exists, "tile \(t)") }
        let everything = app.buttons["hub-tile-everything"]
        let counted = NSPredicate(format: "label CONTAINS 'build'")
        expectation(for: counted, evaluatedWith: app.buttons["hub-tile-raids"])
        waitForExpectations(timeout: 60)
        // Every tile carries its count once the advice is in.
        for t in tiles {
            let label = app.buttons["hub-tile-\(t)"].label
            XCTAssertNotNil(label.rangeOfCharacter(from: .decimalDigits), "tile \(t) has no count: \(label)")
        }
        XCTAssertTrue(app.staticTexts["HAPPENING NOW IN POKÉMON GO"].exists)
        XCTAssertTrue(app.buttons["hub-ranking-info"].exists)
        sleep(1)
        shot("hub-01-light-hub")

        // Everything: the stardust card starts unset, Change takes a number.
        everything.tap()
        XCTAssertTrue(app.buttons["hub-stardust-change"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Not set"].exists)
        shot("hub-02-light-everything-unset")
        // A rejected entry says so and changes nothing.
        app.buttons["hub-stardust-change"].tap()
        XCTAssertTrue(app.alerts.textFields.firstMatch.waitForExistence(timeout: 5))
        app.alerts.textFields.firstMatch.typeText("1234567890")   // ten digits: too many
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["hub-stardust-problem"].waitForExistence(timeout: 5), "a bad entry is explained")
        XCTAssertTrue(app.staticTexts["Not set"].exists)
        app.buttons["hub-stardust-change"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("100000")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["100,000"].waitForExistence(timeout: 5), "the card shows the stardust")
        XCTAssertFalse(app.staticTexts["hub-stardust-problem"].exists, "a valid entry clears the line")
        XCTAssertTrue(app.staticTexts["THESE FIT"].exists)
        let rows = app.buttons.matching(identifier: "hub-build-row")
        XCTAssertGreaterThanOrEqual(rows.count, 1, "at least one build fits")
        let figures = (0..<rows.count).map { (rows.element(boundBy: $0).value as? String) ?? "" }
        XCTAssertTrue(figures.contains { $0.lowercased().contains("dust") }, "a fitting build costs dust, not only Free: \(figures)")
        let total = app.buttons["hub-show-all"].label.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "?"
        XCTAssertEqual(app.buttons["hub-show-all"].label, "SHOW ALL \(total) ›")
        sleep(1)
        shot("hub-03-light-everything-fit")

        // Show all: the full list, then the gaps.
        app.buttons["hub-show-all"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'GAPS'")).firstMatch.waitForExistence(timeout: 5), "the gaps follow the full list")
        app.swipeUp()
        shot("hub-04-light-everything-all")
        app.buttons["hub-back"].tap()
        XCTAssertTrue(app.buttons["hub-tile-everything"].waitForExistence(timeout: 5))
        app.terminate()

        // Dark; the box and the stardust are kept.
        let dark = XCUIApplication()
        dark.launchArguments = ["-appearance", "dark"]
        dark.launch()
        openHub(dark)
        sleep(2)
        shot("hub-05-dark-hub")
        dark.buttons["hub-tile-everything"].tap()
        XCTAssertTrue(dark.buttons["hub-stardust-change"].waitForExistence(timeout: 10))
        XCTAssertTrue(dark.staticTexts["100,000"].exists, "the stardust is kept")
        sleep(1)
        shot("hub-06-dark-everything")
        dark.terminate()

        // The first accessibility text size.
        let large = XCUIApplication()
        large.launchArguments = ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        large.launch()
        openHub(large)
        sleep(2)
        shot("hub-07-ax1-hub")
        large.buttons["hub-tile-everything"].tap()
        XCTAssertTrue(large.buttons["hub-stardust-change"].waitForExistence(timeout: 10))
        XCTAssertTrue(large.staticTexts["100,000"].exists, "the stardust is kept")
        sleep(1)
        shot("hub-08-ax1-everything")
        large.terminate()
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
