import XCTest

/// Drives the app in the simulator through the flow that needs no broadcast: first launch, sample scan, review, save, box,
/// detail, Next. Screenshots go to the folder in POGO_SCREENS (default: the temporary directory). Not part of `swift test`.
final class FlowTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testWholeFlow() throws {
        let app = XCUIApplication()
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan Pokémon"].waitForExistence(timeout: 5))
        shot("02-box-empty")

        app.buttons["More"].tap()
        app.buttons["Diagnostics"].tap()
        let load = app.buttons["Load sample scan"]
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        shot("03-diagnostics")
        load.tap()
        let save = app.buttons["Save to box"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "review did not appear")
        sleep(1)
        shot("04-review-top")
        app.swipeUp(); app.swipeUp()
        shot("05-review-flags")
        save.tap()
        XCTAssertTrue(app.buttons["Scan Pokémon"].waitForExistence(timeout: 15))
        sleep(1)
        shot("06-box")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'To check'")).firstMatch.tap()
        shot("07-box-to-check")
        app.buttons.matching(identifier: "All").firstMatch.tap()

        app.cells.element(boundBy: 2).tap()
        sleep(2)
        shot("08-detail")
        app.swipeUp()
        shot("09-detail-advice")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Next"].tap()
        sleep(3)
        shot("10-next")
        app.swipeUp(); app.swipeUp()
        shot("11-next-gaps")
    }
}
