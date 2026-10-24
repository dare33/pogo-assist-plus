import XCTest

/// The Gym battles, Team Rocket and PvP leagues screens, driven with the sample scan. Screenshots go to the folder in POGO_SCREENS.
/// Not part of `swift test`.
final class HubTeamsTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// A fresh account with the sample scan reviewed and saved (as HubScreensTests does); leaves the app on the Box.
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

    private func openHub(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Pogo Hub"].waitForExistence(timeout: 15))
        app.buttons["Pogo Hub"].tap()
        XCTAssertTrue(app.buttons["hub-tile-everything"].waitForExistence(timeout: 10), "the Hub shows its tiles")
    }

    /// Anything on screen whose accessibility label contains `text`, scrolling the page up to `swipes` times to bring it into the lazy grid.
    private func find(_ app: XCUIApplication, label text: String, swipes: Int = 8) -> XCUIElement {
        let match = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        var n = 0
        while !match.exists && n < swipes { app.swipeUp(); n += 1 }
        return match
    }

    func testGymRocketPvPScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openHub(app)
        // The tiles carry the counts once the advice is ready; the screens read the same advice.
        let counted = NSPredicate(format: "label CONTAINS 'build'")
        expectation(for: counted, evaluatedWith: app.buttons["hub-tile-everything"])
        waitForExpectations(timeout: 60)

        // Gym: the slots panel, then TOP AVAILABLE.
        app.buttons["hub-tile-gym"].tap()
        XCTAssertTrue(app.staticTexts["Top defenders"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["TOP AVAILABLE"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["hub-gym-slot-1"].exists, "the first slot")
        sleep(1)
        shot("gym-01-light")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["hub-tile-rocket"].waitForExistence(timeout: 5))

        // Rocket: leader cards, Change leader, then the grunts.
        app.buttons["hub-tile-rocket"].tap()
        XCTAssertTrue(app.buttons["hub-leader-Giovanni"].waitForExistence(timeout: 10), "a leader card")
        XCTAssertTrue(app.staticTexts["YOUR TEAM FOR GIOVANNI"].exists)
        sleep(1)
        shot("rocket-01-light")
        app.buttons["hub-change-leader"].tap()
        let sierra = app.buttons["Sierra"]
        XCTAssertTrue(sierra.waitForExistence(timeout: 5), "the menu lists Sierra")
        for name in ["Giovanni", "Cliff", "Arlo"] { XCTAssertTrue(app.buttons[name].exists, "the menu lists \(name)") }
        sierra.tap()
        XCTAssertTrue(app.staticTexts["YOUR TEAM FOR SIERRA"].waitForExistence(timeout: 5))
        let normal = find(app, label: "Normal does not mean weak")
        XCTAssertTrue(normal.exists, "the Normal grunt's tile")
        sleep(1)
        shot("rocket-02-light-grunts")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["hub-tile-pvp"].waitForExistence(timeout: 5))

        // PvP: Ultra, the team and its coverage, then a candidate opens the Pokémon page.
        app.buttons["hub-tile-pvp"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["hub-pvp-league"].waitForExistence(timeout: 10))
        let ultra = app.buttons["hub-pvp-league-ul"]
        XCTAssertTrue(ultra.waitForExistence(timeout: 5))
        ultra.tap()
        XCTAssertTrue(app.staticTexts["Suggested team"].waitForExistence(timeout: 10), "the Suggested team panel")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Coverage'")).firstMatch.exists, "the coverage line")
        sleep(1)
        shot("pvp-01-light-ultra")
        // The sample scan has at most three candidates in a league and all of them sit on the team, so OTHER CANDIDATES is not on screen here
        // (the candidate list is pinned by HubTeamsModelTests, not driven). When a league does list one, its row opens the Pokémon page.
        for key in ["gl", "ml"] {
            app.buttons["hub-pvp-league-\(key)"].tap()
            XCTAssertTrue(app.staticTexts["Suggested team"].waitForExistence(timeout: 3) || app.staticTexts["hub-pvp-none"].exists
                          || app.descendants(matching: .any)["hub-pvp-none"].waitForExistence(timeout: 3), "league \(key) answers")
            if key == "ml" { shot("pvp-02-light-master") }
        }
        let row = app.buttons.matching(identifier: "hub-pvp-candidate").firstMatch
        if row.exists {
            row.tap()
            XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Suggested team"].exists, "a Pokémon page replaced the screen")
            shot("pvp-03-light-pokemon")
        }
        app.terminate()

        // Dark: the box is kept; the Rocket screen.
        let dark = XCUIApplication()
        dark.launchArguments = ["-appearance", "dark"]
        dark.launch()
        openHub(dark)
        dark.buttons["hub-tile-rocket"].tap()
        XCTAssertTrue(dark.buttons["hub-leader-Giovanni"].waitForExistence(timeout: 10))
        sleep(2)
        shot("rocket-03-dark")
        dark.terminate()
    }
}
