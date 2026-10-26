import XCTest

/// What the squad screens' UI tests share: a fresh account with the sample scan, the Hub's tile for a screen, and the screenshot set (light and dark, default text and
/// the largest accessibility size) exported to the folder in POGO_SCREENS (the runs use `out/screens/<screen>/`). Every launch passes `-uitest-today 2026-10-25`
/// (honoured by debug builds), so the rows shown do not depend on the day the test runs. Not part of `swift test`.
class SquadUITestCase: XCTestCase {
    func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func launch(reset: Bool = false, dark: Bool = false, ax5: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["-uitest-reset"] : []) + ["-appearance", dark ? "dark" : "light", "-uitest-today", "2026-10-25"]
            + (ax5 ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launch()
        return app
    }

    /// A fresh account with the sample scan reviewed and saved; leaves the app on the Box.
    func populate(_ app: XCUIApplication) {
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

    /// The Hub's tile for a screen; the screen's Back button shows once it is open.
    func openTile(_ app: XCUIApplication, _ id: String) {
        let hubTab = app.buttons["Pogo Hub"]
        XCTAssertTrue(hubTab.waitForExistence(timeout: 15))
        // A tab tap made while the app is still settling after launch can be lost. Both tabs stay in the tree, so the tile "exists" either way and a tap
        // on it would land on My Pokémon underneath: tap until the Hub tab is the selected one.
        var tries = 0
        repeat {
            hubTab.tap(); tries += 1
        } while XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: hubTab)], timeout: 3) != .completed && tries < 4
        XCTAssertTrue(hubTab.isSelected, "the Hub tab is selected")
        let tile = app.buttons["hub-tile-\(id)"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "the Hub shows its tiles")
        // Then wait for the tile counts, as the Hub's own tests do: the tab lays out again when the advice arrives.
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'build'"), object: app.buttons["hub-tile-max"])], timeout: 60)
        tile.tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10), "the \(id) screen opens")
    }

    func back(_ app: XCUIApplication, toTile id: String) {
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["hub-tile-\(id)"].waitForExistence(timeout: 10))
    }

    func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func slot(_ app: XCUIApplication, _ screen: String, _ n: Int) -> XCUIElement { el(app, "hub-\(screen)-slot-\(n)") }

    /// Scrolls up to `swipes` times until the element is on screen.
    @discardableResult func reveal(_ app: XCUIApplication, _ e: XCUIElement, swipes: Int = 8) -> XCUIElement {
        var n = 0
        while !(e.exists && e.isHittable) && n < swipes { app.swipeUp(); n += 1 }
        return e
    }

    var pickerRows: (XCUIApplication) -> XCUIElementQuery = { $0.buttons.matching(identifier: "squad-picker-row") }

    /// Taps a slot and waits for its picker.
    func openPicker(_ app: XCUIApplication, _ screen: String, slot n: Int) {
        let s = slot(app, screen, n)
        XCTAssertTrue(s.waitForExistence(timeout: 30), "slot \(n) exists")
        reveal(app, s).tap()
        XCTAssertTrue(el(app, "squad-picker").waitForExistence(timeout: 10), "the picker opens under the squad")
    }

    func closePicker(_ app: XCUIApplication) {
        let done = app.buttons["squad-picker-done"]
        reveal(app, done).tap()
        XCTAssertTrue(waitGone(el(app, "squad-picker")), "Done closes the picker")
    }

    func waitGone(_ e: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let p = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }

    /// The screenshots of one screen: light and dark at the default text size and at AX5 (the box is kept from the first launch), each with `prepare` done (a
    /// picker open, say), the top of the page and then the page scrolled once.
    func screenSet(_ screen: String, tile: String? = nil, prepare: (XCUIApplication) -> Void = { _ in }) {
        for (scheme, size) in [("light", "default"), ("dark", "default"), ("light", "ax5"), ("dark", "ax5")] {
            let app = launch(dark: scheme == "dark", ax5: size == "ax5")
            openTile(app, tile ?? screen)
            sleep(2)
            prepare(app)
            sleep(1)
            shot("\(screen)-\(scheme)-\(size)")
            app.swipeUp(); sleep(1)
            shot("\(screen)-\(scheme)-\(size)-2")
            app.terminate()
        }
    }
}
