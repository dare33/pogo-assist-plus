import XCTest

/// The Raids and Max battles screens, driven with the sample scan: the timeline in both segments with its readiness bars and BRING chips,
/// the builds that close the gaps, and the Max roster following the Dynamax switch on a Pokémon's page. Screenshots go to the folder in
/// POGO_SCREENS. Not part of `swift test`. Every launch passes `-uitest-today 2026-10-25` (honoured by debug builds), so the rows shown and their
/// "in N d" figures do not depend on the day the test runs.
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
        app.launchArguments = ["-uitest-reset", "-appearance", "light", "-uitest-today", "2026-10-25"]
        app.launch()
        populate(app)
        openTile(app, "raids")
        let segment = app.descendants(matching: .any).matching(identifier: "hub-raids-segment").firstMatch
        XCTAssertTrue(segment.waitForExistence(timeout: 10), "the Now | Coming up switch")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'hub-raid-row-'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "the timeline has at least one row")
        XCTAssertTrue(rows.firstMatch.label.contains("Shadow Landorus"), "Now lists what is under way on 25 Oct: \(rows.firstMatch.label)")
        sleep(1)
        shot("raids-01-light-now")

        app.buttons["Coming up"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "Coming up has rows")
        // The row is one accessibility element; its label names the types to bring and the dates (2026-10-25: Giratina starts in 3 days).
        let first = rows.firstMatch
        XCTAssertTrue(first.label.contains("28 October to 3 November, in 3 days"), first.label)
        XCTAssertTrue(first.label.contains("bring Ice, Ghost, Dragon and Dark"), first.label)
        XCTAssertTrue(first.label.contains("Giratina (Origin)"), first.label)
        XCTAssertTrue(app.staticTexts["BUILDS THAT CLOSE THE GAPS"].exists, "the gap-closer header")
        XCTAssertTrue(app.buttons["hub-schedule-link"].exists || app.links["Full schedule on pokemongo.com ›"].exists || app.descendants(matching: .any)["hub-schedule-link"].exists)
        sleep(1)
        shot("raids-02-light-coming-up")
        app.swipeUp()
        shot("raids-03-light-builds")
        app.terminate()

        // Dark; the box is kept.
        let dark = XCUIApplication()
        dark.launchArguments = ["-appearance", "dark", "-uitest-today", "2026-11-05"]   // a different day, which also proves the launch argument is read
        dark.launch()
        openTile(dark, "raids")
        XCTAssertTrue(dark.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'hub-raid-row-'")).firstMatch.waitForExistence(timeout: 30))
        let darkFirst = dark.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'hub-raid-row-'")).firstMatch
        XCTAssertTrue(darkFirst.label.contains("Mega Sableye") && darkFirst.label.contains("now"), "on 5 Nov the first row under way (by first day) is the Mega Sableye raid: \(darkFirst.label)")
        sleep(1)
        shot("raids-04-dark-now")
        dark.buttons["Coming up"].tap()
        sleep(1)
        shot("raids-05-dark-coming-up")
        dark.terminate()

        // The third accessibility text size (AX3): the date goes above the name and the chips and counters wrap.
        let large = XCUIApplication()
        large.launchArguments = ["-appearance", "light", "-uitest-today", "2026-10-25", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        large.launch()
        openTile(large, "raids")
        XCTAssertTrue(large.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'hub-raid-row-'")).firstMatch.waitForExistence(timeout: 30))
        sleep(1)
        shot("raids-06-ax3-now")
        large.terminate()
    }

    /// The Dynamax switch on a Pokémon's page still decides the Max readiness: with Blissey marked, its Max pick reads Full strength in the squad (the roster of
    /// Dynamax copies the screen once showed is gone, design pass 2).
    func testMaxPickFollowsTheDynamaxSwitch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light", "-uitest-today", "2026-10-25"]
        app.launch()
        populate(app)

        // Mark the first Pokémon Dynamax on its page.
        let species = app.buttons.matching(identifier: "species-row").firstMatch
        XCTAssertTrue(species.waitForExistence(timeout: 10)); app.openSpeciesList(species)
        let members = app.buttons.matching(identifier: "pokemon-row")
        XCTAssertTrue(members.firstMatch.waitForExistence(timeout: 5))
        let memberLabel = members.firstMatch.label
        members.firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
        let control = app.buttons["mark-dynamax"]
        XCTAssertTrue(control.waitForExistence(timeout: 10), "the Dynamax mark is on the details card")
        control.tap()
        expectation(for: NSPredicate(format: "value == 'On'"), evaluatedWith: control)
        waitForExpectations(timeout: 10)
        app.buttons["Back"].tap()
        XCTAssertTrue(members.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Pogo Hub"].waitForExistence(timeout: 10))

        openTile(app, "max")
        let row = app.descendants(matching: .any)["hub-max-row-0"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "a Max timeline row")
        row.tap()
        // The sample box's first Pokémon is a Blissey, the Tank of the squad: marked Dynamax and with nothing left to do, it is at full strength.
        let tank = app.descendants(matching: .any)["hub-max-slot-1"]
        XCTAssertTrue(tank.waitForExistence(timeout: 10))
        let name = memberLabel.components(separatedBy: CharacterSet(charactersIn: ",\n")).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        XCTAssertFalse(name.isEmpty, memberLabel)
        XCTAssertTrue(tank.label.contains(name) && tank.label.hasSuffix("Full strength"), "the marked copy reads Full strength: \(tank.label) (row '\(memberLabel)')")
        shot("max-01-light-squad")
    }
}
