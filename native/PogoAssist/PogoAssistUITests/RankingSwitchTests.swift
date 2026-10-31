import XCTest

/// The ranking switch, its "i" and explainer, in the DEBUG design gallery (`-design-gallery`). Not part of `swift test`.
/// Screenshots go to the folder in POGO_SCREENS when it is set.
final class RankingSwitchTests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-design-gallery"] + extra
        app.launch()
        return app
    }

    /// Leaves the ranking preference at its default for whatever runs next.
    override func tearDown() {
        let app = launch(["-reset-ranking"])
        _ = app.descendants(matching: .any).matching(identifier: "ranking").firstMatch.waitForExistence(timeout: 10)
        app.terminate()
        super.tearDown()
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] else { return }
        let file = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: file)
        } catch {
            XCTFail("screenshot not written to \(file.path): \(error)")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "screenshot not written to \(file.path)")
    }

    func testRankingSwitchPersistsAndExplains() {
        var app = launch(["-reset-ranking"])
        var control = app.descendants(matching: .any).matching(identifier: "ranking").firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertEqual(control.value as? String, "Classic", "the preference starts at Classic")

        // A real tap on the right-hand segment.
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "Pogo Assist")

        // A tap on the left-hand segment goes back. (XCUITest cannot drive the adjustable increment and decrement actions: a
        // swipe on the element is a plain swipe, not a VoiceOver adjustment.)
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "Classic")
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "Pogo Assist")

        // The "i" opens and closes the explainer.
        let info = app.buttons["ranking-info"]
        XCTAssertTrue(info.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'starts from the strongest species'")).firstMatch.exists)
        info.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'starts from the strongest species'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(info.value as? String, "Expanded")
        shot("gallery-explainer-open")
        info.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'starts from the strongest species'")).firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 3), .completed, "the explainer closes")

        // It persisted: a relaunch without the reset still says Pogo Assist.
        app.terminate()
        app = launch()
        control = app.descendants(matching: .any).matching(identifier: "ranking").firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertEqual(control.value as? String, "Pogo Assist")
    }

    func testLeagueSwitchSelects() {
        let app = launch(["-reset-ranking"])
        let ul = app.buttons["gallery-league-ul"]
        XCTAssertTrue(ul.waitForExistence(timeout: 10))
        XCTAssertFalse(ul.isSelected)
        ul.tap()
        XCTAssertTrue(ul.isSelected)
    }

    /// The gallery with the explainer open, saved to POGO_SCREENS when set (the theme variants are shot from the shell with launch arguments).
    func testGalleryScreenshot() {
        let app = launch(["-reset-ranking"])
        XCTAssertTrue(app.buttons["ranking-info"].waitForExistence(timeout: 10))
        app.buttons["ranking-info"].tap()
        shot("gallery")
    }
}
