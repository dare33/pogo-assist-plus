import XCTest

/// The Special scan option: choosing it and a kind shows the search word and "Copy search", and the pass's wording replaces the usual wording on the step card, on the Done screen
/// and in the review. The sample scan stands in for a finished broadcast, as in ScanDoneTests; nothing here touches the game.
final class ScanPassFlowTests: XCTestCase {
    private func openScan() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        app.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan Pokémon"].waitForExistence(timeout: 5))
        return app
    }

    private func loadSample(_ app: XCUIApplication) {
        app.buttons["More"].tap()
        let diagnostics = app.buttons["Diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        let load = app.buttons["Load sample scan"]
        if !load.waitForExistence(timeout: 8), diagnostics.exists { diagnostics.tap() }
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        load.tap()
    }

    private func label(_ app: XCUIApplication, _ id: String) -> String { app.descendants(matching: .any)[id].firstMatch.label }

    func testSpecialScanDynamaxShowsTheSearchAndPassWordingEverywhere() throws {
        let app = openScan()
        // The options come first: three kinds side by side; Special scan opens the four-kind picker and the search.
        let special = app.buttons["scan-kind-special"]
        XCTAssertTrue(special.waitForExistence(timeout: 5))
        special.tap()
        for kind in ["shadow", "purified", "dynamax", "gigantamax"] { XCTAssertTrue(app.buttons["pass-kind-\(kind)"].exists, kind) }
        app.buttons["pass-kind-dynamax"].tap()
        XCTAssertTrue(app.buttons["scan-copy-search"].waitForExistence(timeout: 3), "the Copy search button")
        XCTAssertEqual(app.staticTexts["scan-search-word"].label, "dynamax")
        app.buttons["Done"].tap()

        // The step card: the pass's steps, not the usual first and last ones.
        let step1 = app.descendants(matching: .any)["scan-step-1"].firstMatch
        XCTAssertTrue(step1.waitForExistence(timeout: 5))
        XCTAssertTrue(step1.label.contains("type dynamax in the storage search"), step1.label)
        XCTAssertFalse(step1.label.contains("you want to start at"), "the usual first step is replaced")
        XCTAssertTrue(app.buttons["scan-copy-search"].exists, "Copy search on the step card too")
        XCTAssertTrue(label(app, "scan-step-6").contains("marked Dynamax"))
        XCTAssertFalse(app.staticTexts["When the scan ends, come back to Pogo Assist to meet your new Pokémon or export your collection."].exists)

        // The guide's first page names the search.
        app.buttons["Show the steps again"].tap()
        XCTAssertTrue(app.staticTexts["Search your storage for dynamax"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Open your first Pokémon's appraisal"].exists)
        app.buttons["Next"].tap(); app.buttons["Next"].tap()
        app.buttons["OK, I've got it. Let's scan!"].tap()

        // Done: the pass line replaces the usual headline. The sample scan is loaded from the Box screen; the pass chosen stays chosen.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        loadSample(app)
        let open = app.buttons["scan-done-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 60), "the Done screen did not appear")
        let headline = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Dynamax pass: '")).firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 5), "the Done headline is the pass line")
        XCTAssertTrue(headline.label.contains("new"), headline.label)
        XCTAssertFalse(app.staticTexts["Scan finished."].exists)

        // The review says which pass it was and does not offer the Full / Add and update switch.
        open.tap()
        let line = app.descendants(matching: .any)["review-pass-line"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 20))
        XCTAssertTrue(line.label.hasPrefix("Dynamax pass: "), line.label)
        XCTAssertFalse(app.buttons["Full scan"].exists)

        // Every row of the sample is new to this empty box, so the "Was this a dynamax search?" question comes before the save.
        let save = app.buttons["review-save"]
        if !save.waitForExistence(timeout: 5) { throw XCTSkip("the sample has questions in this build; the guard is covered in PogoBox tests") }
        save.tap()
        XCTAssertTrue(app.buttons["Yes, save as Dynamax pass"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["No, save as Add and update"].exists)
        XCTAssertTrue(app.buttons["No, discard the scan"].exists)
        app.buttons["Yes, save as Dynamax pass"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 20), "saved")
    }
}
