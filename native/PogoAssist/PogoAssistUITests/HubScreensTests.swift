import XCTest

/// The Pogo Hub tab and its Everything screen, driven with the sample scan: the six tiles, the stardust card and the lists under it,
/// then the Hub in dark and at the first accessibility text size. Screenshots go to the folder in POGO_SCREENS. Not part of `swift test`.
final class HubScreensTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
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

        // The tiles; the counts arrive with the advice, so the Everything tile's label gains "N builds".
        for t in tiles { XCTAssertTrue(app.buttons["hub-tile-\(t)"].exists, "tile \(t)") }
        let everything = app.buttons["hub-tile-everything"]
        let counted = NSPredicate(format: "label CONTAINS 'builds' OR label CONTAINS '1 build'")
        expectation(for: counted, evaluatedWith: everything)
        waitForExpectations(timeout: 60)
        XCTAssertTrue(everything.label.contains("build"), everything.label)
        // Every tile carries its count once the advice is in.
        for t in tiles {
            let label = app.buttons["hub-tile-\(t)"].label
            XCTAssertNotNil(label.rangeOfCharacter(from: .decimalDigits), "tile \(t) has no count: \(label)")
        }
        let total = everything.label.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "?"
        XCTAssertTrue(app.staticTexts["HAPPENING IN POKÉMON GO"].exists)
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
}
