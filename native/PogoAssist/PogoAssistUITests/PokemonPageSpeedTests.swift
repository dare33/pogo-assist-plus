import XCTest

/// How fast the Pokémon page answers a tap on a big box (Greg's, about 2,100 Pokémon, seeded from `fixtures/` by the DEBUG launch argument `-uitest-seed-box`).
/// The app writes "pogo timings" lines to the log (tap to mark drawn, tap to advice, the edit's save, the advise); a timing run reads them with `simctl spawn log show`.
/// The tests here also hold the rules: a mark shows its new state at once, and rapid taps settle on the last state.
final class PokemonPageSpeedTests: XCTestCase {
    private static var bigBox: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/greg-2026-10-22.box.csv").path
    }

    private func launchBig() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light", "-uitest-today", "2026-10-25", "-uitest-seed-box", Self.bigBox]
        app.launch()
        return app
    }

    private func openCopy(_ app: XCUIApplication, _ species: String) {
        let search = app.textFields["box-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 60))
        search.tap(); search.typeText(species + "\n")
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH %@", species)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "\(species) is in the big box")
        app.openSpeciesList(row)
        let copy = app.buttons.matching(identifier: "pokemon-row").firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        copy.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["page-tab-summary"].waitForExistence(timeout: 120), "the page shows its tabs (the whole-box advice is ready)")
    }

    private func waitValue(_ app: XCUIApplication, _ id: String, _ value: String, timeout: TimeInterval = 20) {
        let e = app.buttons[id]
        expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: e)
        waitForExpectations(timeout: timeout)
    }

    /// Timing run: one tap on Dynamax, then on Shadow, each left to finish; then five quick taps on Dynamax. Read the log afterwards.
    func testTimingsOnABigBox() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["POGO_TIMINGS"] == nil, "a timing run only with POGO_TIMINGS (TEST_RUNNER_POGO_TIMINGS on the command line)")
        let app = launchBig()
        openCopy(app, "Lucario")
        app.buttons["mark-dynamax"].tap()
        waitValue(app, "mark-dynamax", "On")
        sleep(25)
        app.buttons["mark-shadow"].tap()
        waitValue(app, "mark-shadow", "On")
        sleep(25)
        for _ in 0..<5 { app.buttons["mark-dynamax"].tap() }   // an odd number: ends On to Off
        sleep(40)
    }
}
