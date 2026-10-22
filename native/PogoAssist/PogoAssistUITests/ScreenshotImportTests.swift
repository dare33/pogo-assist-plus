import XCTest

/// Quick screenshot import through the system picker, in the simulator. The pictures must be in the simulator's Photos first:
///   xcrun simctl addmedia booted native/PogoReader/Tests/PogoReaderTests/Fixtures/{normal-nickit-212,rayquaza-damaged-19of190,stationed-zapdos}.png
/// (run in that order, so the stationed card is the newest). Not part of `swift test`; it needs the booted simulator and those three pictures as the newest in Photos.
final class ScreenshotImportTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testPickThreeScreenshotsReadThemAndReviewTheTwoThatCanBeAdded() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))

        app.buttons["More"].tap()
        let entry = app.buttons["Import screenshots"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let choose = app.buttons["import-choose"]
        if !choose.waitForExistence(timeout: 8), entry.exists { entry.tap() }   // the menu can swallow the first tap
        XCTAssertTrue(choose.waitForExistence(timeout: 8), "the import sheet did not open")
        shot("30-import-sheet")
        choose.tap()

        // The system picker: select the three newest pictures, then Add.
        // The picker is another process, and its elements carry no identifiers a test can rely on: tap the three newest pictures by position (the top row of the grid) and the
        // check mark. `31-picker` shows the layout this was written against (iPhone 17, iOS 27).
        // The picker is another process whose controls the test cannot query (its selection count is not in the accessibility tree), so it is given time to settle (a tap before the
        // grid is up is lost: that happened once) and the pictures are tapped slowly. The count is checked end to end below: the summary must offer "Review 2 screenshots".
        sleep(8)
        shot("31-picker")
        for x in [0.17, 0.5, 0.83] { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.46)).tap(); sleep(1) }
        shot("32-picker-selected")
        let add = app.buttons["Add"]
        if add.waitForExistence(timeout: 3) { add.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.165)).tap() }

        // Reading starts by itself; the summary appears with a way into the review.
        let review = app.buttons["import-review"]
        // The sheet is a lazy list: the button is below the three screenshots' rows, so scroll until it exists and is enabled.
        for _ in 0..<40 where !(review.exists && review.isEnabled) { app.swipeUp(); sleep(2) }
        XCTAssertTrue(review.exists && review.isEnabled, "no summary appeared")
        sleep(1)
        shot("33-import-summary")
        XCTAssertTrue(review.label.contains("Review 2 screenshots"), review.label)
        review.tap()

        let save = app.buttons["Save to box"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "the review did not open")
        sleep(1)
        shot("34-import-review")
        XCTAssertTrue(app.staticTexts["Screenshots read"].exists)
        XCTAssertFalse(app.buttons["Full scan"].exists, "an import is only ever Add and update")
        save.tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 20))
        sleep(1)
        shot("35-box-after-import")
    }
}
