import XCTest

/// The Raids and Max battles screens, driven with the sample scan: the timeline in both segments with its readiness bars and BRING chips,
/// the builds that close the gaps, and the Max roster following the Dynamax switch on a Pokémon's page. Screenshots go to the folder in
/// POGO_SCREENS. Not part of `swift test`. The rows shown follow the device's date (the schedule ends on 1 Dec 2026).
final class HubRaidsMaxTests: XCTestCase {
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

    private func openHub(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Pogo Hub"].waitForExistence(timeout: 15))
        app.buttons["Pogo Hub"].tap()
        XCTAssertTrue(app.buttons["hub-tile-everything"].waitForExistence(timeout: 10), "the Hub shows its tiles")
    }

    private let typeNames = ["NORMAL", "FIRE", "WATER", "ELECTRIC", "GRASS", "ICE", "FIGHTING", "POISON", "GROUND", "FLYING", "PSYCHIC", "BUG", "ROCK", "GHOST", "DRAGON", "DARK", "STEEL", "FAIRY"]

    /// The Hub's tile for a screen, once the advice has arrived.
    private func openTile(_ app: XCUIApplication, _ id: String) {
        openHub(app)
        let tile = app.buttons["hub-tile-\(id)"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10), "the \(id) screen opens")
    }

    func testRaidsTimeline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openTile(app, "raids")
        let segment = app.descendants(matching: .any).matching(identifier: "hub-raids-segment").firstMatch
        XCTAssertTrue(segment.waitForExistence(timeout: 10), "the Now | Coming up switch")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'hub-raid-row-'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "the timeline has at least one row")
        sleep(1)
        shot("raids-01-light-now")

        app.buttons["Coming up"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "Coming up has rows")
        let bring = app.staticTexts.matching(NSPredicate(format: "label IN %@", typeNames))
        XCTAssertTrue(bring.firstMatch.waitForExistence(timeout: 5), "a BRING chip names a type")
        XCTAssertTrue(app.staticTexts["BRING"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["BUILDS THAT CLOSE THE GAPS"].exists, "the gap-closer header")
        XCTAssertTrue(app.buttons["hub-schedule-link"].exists || app.links["Full schedule on pokemongo.com ›"].exists || app.descendants(matching: .any)["hub-schedule-link"].exists)
        sleep(1)
        shot("raids-02-light-coming-up")
        app.swipeUp()
        shot("raids-03-light-builds")
        app.terminate()

        // Dark; the box is kept.
        let dark = XCUIApplication()
        dark.launchArguments = ["-appearance", "dark"]
        dark.launch()
        openTile(dark, "raids")
        XCTAssertTrue(dark.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'hub-raid-row-'")).firstMatch.waitForExistence(timeout: 30))
        sleep(1)
        shot("raids-04-dark-now")
        dark.buttons["Coming up"].tap()
        sleep(1)
        shot("raids-05-dark-coming-up")
        dark.terminate()
    }

    func testMaxRosterFollowsTheSwitch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)

        // Mark the first Pokémon Dynamax on its page.
        let species = app.buttons.matching(identifier: "species-row").firstMatch
        XCTAssertTrue(species.waitForExistence(timeout: 10)); species.tap()
        let members = app.buttons.matching(identifier: "pokemon-row")
        XCTAssertTrue(members.firstMatch.waitForExistence(timeout: 5))
        let memberLabel = members.firstMatch.label
        members.firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
        let control = app.descendants(matching: .any).matching(identifier: "dynamax-switch").firstMatch
        var swipes = 0
        while !(control.exists && control.isHittable) && swipes < 10 { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(control.isHittable, "the Dynamax switch is on the page")
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).tap()   // Not set | Yes | No
        expectation(for: NSPredicate(format: "value == 'Yes'"), evaluatedWith: control)
        waitForExpectations(timeout: 10)
        app.buttons["Back"].tap()
        XCTAssertTrue(members.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Pogo Hub"].waitForExistence(timeout: 10))

        openTile(app, "max")
        let tiles = app.descendants(matching: .any).matching(identifier: "hub-max-tile")
        var scrolls = 0
        while !tiles.firstMatch.exists && scrolls < 6 { app.swipeUp(); scrolls += 1 }
        _ = tiles.firstMatch.waitForExistence(timeout: 30)
        shot("max-01-light-roster")
        XCTAssertTrue(tiles.firstMatch.exists, "the roster holds the Pokémon marked Dynamax")
        XCTAssertEqual(tiles.count, 1)
        // The member row reads like "Name, CP ..." and the tile like "Name, line, CP n": the first words agree.
        let name = memberLabel.components(separatedBy: CharacterSet(charactersIn: ",\n")).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        XCTAssertFalse(name.isEmpty, memberLabel)
        XCTAssertTrue(tiles.firstMatch.label.hasPrefix(name), "roster tile '\(tiles.firstMatch.label)' names '\(name)' (row '\(memberLabel)')")
    }
}
