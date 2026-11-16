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
        reveal(app, done)
        // The pinned strip is drawn over the top of the scroll area: a Done button scrolled under it is not tapped until it is dragged below it (the largest text sizes make the strip tall).
        let strip = el(app, "squad-strip")
        var n = 0
        while strip.exists && done.exists && done.frame.minY < strip.frame.maxY + 4 && n < 10 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)))
            n += 1
        }
        done.tap()
        XCTAssertTrue(waitGone(el(app, "squad-picker")), "Done closes the picker")
    }

    func waitGone(_ e: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let p = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: e)], timeout: timeout) == .completed
    }

    /// P1: every row of the open picker says its figure in its one VoiceOver label (`figure`: "estimated damage", "bulk" or "score"); under Available every row is a copy of the
    /// player's, so it also says its CP and IVs. (The bar itself is hidden from VoiceOver, so the label is what a UI test can read.) Spoken text uses commas, not " · ".
    func assertPickerFigures(_ app: XCUIApplication, figure: String, available: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let rows = pickerRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the picker lists rows", file: file, line: line)
        XCTAssertGreaterThan(rows.count, 0, file: file, line: line)
        for i in 0..<min(rows.count, 8) {
            let label = rows.element(boundBy: i).label
            XCTAssertTrue(label.contains(figure), "row \(i) says its \(figure): \(label)", file: file, line: line)
            if available { XCTAssertTrue(label.contains("CP "), "row \(i) says its CP: \(label)", file: file, line: line) }
            XCTAssertFalse(label.contains(" · "), "spoken text uses commas: \(label)", file: file, line: line)
        }
    }

    /// Scrolls back to the top and switches the suggestions to Available.
    func selectAvailable(_ app: XCUIApplication) { selectTab(app, "available") }

    /// Scrolls back to the top and switches the suggestions to Best.
    func selectBest(_ app: XCUIApplication) { selectTab(app, "best") }

    /// Scrolls until the open picker's title line (its Done button) is near the top of the screen, so its first rows show.
    func scrollPickerIntoView(_ app: XCUIApplication) {
        let done = app.buttons["squad-picker-done"]
        // Short drags (a fifth of the screen), not swipes: at the largest text size one swipe moves past the whole picker.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)), to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        var n = 0
        while n < 40 && !(done.exists && done.isHittable && done.frame.minY < 450) {
            if done.exists && done.frame.minY < 0 { to.press(forDuration: 0.05, thenDragTo: from) } else { from.press(forDuration: 0.05, thenDragTo: to) }
            n += 1
        }
    }

    /// The Best-mode set of a screen: Best on, a slot's picker open, so a Pokémon the box lacks shows on its card and in the list (the box is kept from the first launch).
    func bestSet(_ screen: String, slot n: Int, tile: String? = nil, prepare: @escaping (XCUIApplication) -> Void = { _ in }) {
        screenSet("\(screen)-best", tile: tile ?? screen) { app in
            prepare(app)
            let best = app.buttons["squad-tab-best"]
            if best.waitForExistence(timeout: 30) { best.tap() }
            let s = self.slot(app, screen, n)
            if s.waitForExistence(timeout: 30) { self.reveal(app, s).tap() }
        }
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
            // The open picker's rows, scrolled up under the status bar (at the largest text size the picker is far down the page).
            if app.buttons["squad-picker-done"].exists { scrollPickerIntoView(app) } else { app.swipeUp() }
            sleep(1)
            shot("\(screen)-\(scheme)-\(size)-2")
            app.terminate()
        }
    }

    // MARK: the fixed suggestion and the squad strength bar (CONCEPTS rules 27 and 32)

    /// A slot card's Pokémon: its label reads "Slot 2 of 6, Heavy hitter, Name, ..." on Raids, Max and PvP and "Slot 2 of 6, Name, ..." on Gym and Rocket.
    func slotName(_ app: XCUIApplication, _ screen: String, _ n: Int) -> String {
        let parts = slot(app, screen, n).label.components(separatedBy: ", ")
        return parts.count > (["raids", "max", "pvp"].contains(screen) ? 2 : 1) ? parts[["raids", "max", "pvp"].contains(screen) ? 2 : 1] : ""
    }

    /// Picks the first row of the open picker that is not the slot's own and not in another slot; returns its name, or nil when there is none.
    @discardableResult func chooseAFreshRow(_ app: XCUIApplication) -> String? {
        let rows = pickerRows(app)
        _ = rows.firstMatch.waitForExistence(timeout: 10)
        let fresh = rows.matching(NSPredicate(format: "selected == false AND NOT (label CONTAINS 'choosing it')")).firstMatch
        guard fresh.exists else { return nil }
        let name = fresh.label.components(separatedBy: ",").first ?? ""
        fresh.tap()
        return name
    }

    /// Changes the squad once: a fresh row in slot 2, else (nothing fresh in the box) a swap with another slot's Pokémon; under Best when Available has nothing to offer.
    func changeTheSquad(_ app: XCUIApplication, _ screen: String) {
        for best in [false, true] {
            if best { selectBest(app) }
            for n in [2, 1, 3] {
                guard slot(app, screen, n).exists else { continue }
                openPicker(app, screen, slot: n)
                if chooseAFreshRow(app) != nil { closePicker(app); return }
                let held = pickerRows(app).matching(NSPredicate(format: "label CONTAINS 'choosing it'")).firstMatch
                if held.exists { held.tap(); closePicker(app); return }
                closePicker(app)
            }
        }
        XCTFail("no slot offered a row to change the squad with")
    }

    /// A tab of the squad's Current | Available | Best switch.
    func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement { app.buttons["squad-tab-\(name)"] }

    /// Scrolls back to the top and chooses a tab (`current`, `available` or `best`).
    func selectTab(_ app: XCUIApplication, _ name: String) {
        let t = tab(app, name)
        var n = 0
        while !(t.exists && t.isHittable) && n < 8 { app.swipeDown(); n += 1 }
        XCTAssertTrue(t.exists, "the \(name) tab exists")
        if !t.isSelected { t.tap() }
        XCTAssertTrue(waitSelected(t), "the \(name) tab is selected")
    }

    func waitSelected(_ e: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: e)], timeout: timeout) == .completed
    }

    /// Taps Save to Current on Available or Best. `replacing` is nil when the squad has no Current (no question is asked); otherwise the question "Replace your current squad?"
    /// is answered with Replace (true) or Cancel (false).
    func saveToCurrent(_ app: XCUIApplication, replacing: Bool? = nil) {
        reveal(app, app.buttons["squad-save-current"]).tap()
        guard let replacing else { return }
        answer(app, asked: "squad-save-current", confirm: replacing)
    }

    /// Answers a confirmation dialog whose buttons are `<asked>-confirm` and `<asked>-cancel`.
    func answer(_ app: XCUIApplication, asked: String, confirm: Bool) {
        let ok = app.buttons.matching(identifier: "\(asked)-confirm").firstMatch
        XCTAssertTrue(ok.waitForExistence(timeout: 5), "\(asked) asks first")
        if confirm { ok.tap(); return }
        // On the simulator the question is a popover with no Cancel button of its own: tapping outside it (its dismiss region) is Cancel.
        let byId = app.buttons.matching(identifier: "\(asked)-cancel").firstMatch
        let outside = app.otherElements["PopoverDismissRegion"]
        if byId.exists { byId.tap() } else if outside.exists { outside.tap() } else { app.buttons["Cancel"].tap() }
        XCTAssertTrue(waitGone(ok), "Cancel closes the question")
    }

    func deleteCurrent(_ app: XCUIApplication, confirm: Bool) {
        reveal(app, app.buttons["squad-delete-current"]).tap()
        answer(app, asked: "squad-delete-current", confirm: confirm)
    }

    /// Scrolls until the squad strength line is near the top, so the bar, the slots and the button under them show.
    func scrollToStrength(_ app: XCUIApplication) {
        let line = el(app, "squad-strength")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)), to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        var n = 0
        while n < 40 && !(line.exists && line.isHittable && line.frame.minY < 380 && line.frame.minY > 60) {
            if line.exists && line.frame.minY < 60 { to.press(forDuration: 0.05, thenDragTo: from) } else { from.press(forDuration: 0.05, thenDragTo: to) }
            n += 1
        }
    }

    /// The screenshots of a squad on Current after one saved edit, so the tabs, the strength bar and the links show: light and dark at the default text size and at AX5
    /// (the box is kept from the first launch), named <screen>-<light|dark>-<default|ax5>.
    func strengthShots(_ screen: String, tile: String? = nil, prepare: (XCUIApplication) -> Void = { _ in }) {
        for (scheme, size) in [("light", "default"), ("dark", "default"), ("light", "ax5"), ("dark", "ax5")] {
            let app = launch(dark: scheme == "dark", ax5: size == "ax5")
            openTile(app, tile ?? screen)
            prepare(app)
            XCTAssertTrue(slot(app, screen, 1).waitForExistence(timeout: 60))
            if !tab(app, "current").exists {
                changeTheSquad(app, screen)
                saveToCurrent(app)
                XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 10), "saving adds the Current tab")
            }
            selectTab(app, "current")
            XCTAssertTrue(reveal(app, app.buttons["squad-delete-current"]).exists, "Current has its Delete current squad link")
            scrollToStrength(app)
            sleep(1)
            shot("\(screen)-\(scheme)-\(size)")
            app.terminate()
        }
    }

    // MARK: the pinned squad strip (rule 34)

    /// With a slot's picker open and the page scrolled well down the Pokémon list, the strip of the squad's slots stays at the top; tapping another slot's chip opens that slot's
    /// picker; Done hides the strip. `titlePrefix` is the start of the opened picker's title ("Slot 3 ·").
    func assertStripPinsTheSquad(_ app: XCUIApplication, _ screen: String, open: Int = 1, chip: Int = 3, shotName: String? = nil) {
        XCTAssertFalse(el(app, "squad-strip").exists, "no strip while no picker is open")
        openPicker(app, screen, slot: open)
        let strip = el(app, "squad-strip")
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "an open picker pins the squad strip")
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertTrue(strip.exists && strip.isHittable, "the strip is still on screen after scrolling down the list")
        let target = app.buttons["squad-strip-chip-\(chip)"], editing = app.buttons["squad-strip-chip-\(open)"]
        XCTAssertTrue(target.exists && editing.exists, "every slot has a chip")
        // At the accessibility sizes only a chip or two fits: the strip scrolls sideways to the one wanted.
        var n = 0
        while !(target.isHittable && editing.exists) && n < 10 { let drag = editing.isHittable ? editing : strip; if chip > open { drag.swipeLeft() } else { drag.swipeRight() }; n += 1 }
        // (H18: a chip can report itself not hittable although it is on screen and a tap on it works: the screen's own scroll view's frame starts at the strip's top, under the strip
        // that the safe-area inset draws over it, and the test framework's hit test sees that frame. The check is the chip's frame inside the strip, then a coordinate tap.)
        XCTAssertTrue(target.isHittable || (target.frame.midX > 0 && target.frame.midX < app.frame.width && target.frame.intersects(strip.frame)), "the chip for slot \(chip) can be reached: \(target.frame)")
        XCTAssertTrue(editing.isSelected, "the slot being edited is highlighted: \(editing.label)")
        XCTAssertTrue(editing.label.hasSuffix("editing"), editing.label)
        XCTAssertTrue(target.label.hasPrefix("Slot \(chip)"), target.label)
        if let shotName { shot(shotName) }
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Slot \(chip) ·")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "tapping a chip opens that slot's picker")
        XCTAssertTrue(waitSelected(app.buttons["squad-strip-chip-\(chip)"]), "and highlights it")
        XCTAssertTrue(app.buttons["squad-strip-chip-\(chip)"].label.hasSuffix("editing"))
        closePicker(app)
        XCTAssertTrue(waitGone(el(app, "squad-strip")), "Done hides the strip")
    }
}
