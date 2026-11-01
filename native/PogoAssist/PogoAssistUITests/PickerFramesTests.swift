import XCTest

/// P1: every row of an open picker at the largest text size, frame by frame to the end of the picker, so nothing that truncates can hide below the fold. Saves
/// `<screen>-<mode>-ax5-frame-NN.png` to POGO_SCREENS. Not part of `swift test`.
final class PickerFramesTests: SquadUITestCase {
    private func frames(_ name: String, screen: String, best: Bool = false, prepare: (XCUIApplication) -> Void, slot n: Int) {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        let app = launch(dark: false, ax5: true)
        openTile(app, screen)
        sleep(2)
        prepare(app)
        if best { selectBest(app) }
        let s = slot(app, screen, n)
        if s.waitForExistence(timeout: 30) { reveal(app, s).tap() }
        XCTAssertTrue(el(app, "squad-picker").waitForExistence(timeout: 10))
        scrollPickerIntoView(app)
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)), to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        var last = ""
        for k in 1...30 {
            sleep(1)
            shot("\(name)-frame-\(String(format: "%02d", k))")
            // The end of the picker: its last row is wholly on screen, or the page no longer moves.
            let rows = pickerRows(app), lastRow = rows.element(boundBy: max(0, rows.count - 1))
            let marker = "\(lastRow.frame.minY)/\(el(app, "squad-picker").frame.maxY)"
            if marker == last || (el(app, "squad-picker").frame.maxY < app.frame.height - 40) { break }
            last = marker
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        app.terminate()
    }

    func testRaidsAvailableFrames() { frames("raids-available-ax5", screen: "raids", prepare: { app in let c = self.el(app, "hub-raid-row-1"); if c.waitForExistence(timeout: 30) { c.tap() } }, slot: 2) }
    func testRaidsBestFrames() { frames("raids-best-ax5", screen: "raids", best: true, prepare: { app in let c = self.el(app, "hub-raid-row-1"); if c.waitForExistence(timeout: 30) { c.tap() } }, slot: 2) }
    func testMaxFrames() { frames("max-available-ax5", screen: "max", prepare: { app in let r = self.el(app, "hub-max-row-0"); if r.waitForExistence(timeout: 30) { r.tap() } }, slot: 1) }
    func testGymFrames() { frames("gym-available-ax5", screen: "gym", prepare: { _ in }, slot: 1) }
    func testRocketFrames() { frames("rocket-available-ax5", screen: "rocket", prepare: { _ in }, slot: 2) }
    func testPvPFrames() { frames("pvp-available-ax5", screen: "pvp", prepare: { app in if app.buttons["hub-pvp-league-ul"].waitForExistence(timeout: 30) { app.buttons["hub-pvp-league-ul"].tap() } }, slot: 2) }
}
