import XCTest

/// The screenshots of design pass 2-6, slice 3, for the private page (docs/design-process.md): per squad screen the Available tab with one edit (light and dark, default text and AX5:
/// `strengthShots`), the Current tab with two earlier current squads, the strip while a picker is open and scrolled, and on Raids the Best tab, the set pill and the toast. Saved to
/// POGO_SCREENS. Not part of `swift test`.
final class Pass26ShotsTests: SquadUITestCase {
    private struct Spec {
        let id: String
        let slots: Int
        let prepare: (Pass26ShotsTests, XCUIApplication) -> Void
    }

    private let specs: [Spec] = [
        Spec(id: "raids", slots: 6) { t, app in let c = t.el(app, "hub-raid-row-1"); if c.waitForExistence(timeout: 30) { c.tap() } },
        Spec(id: "max", slots: 3) { t, app in let r = t.el(app, "hub-max-row-0"); if r.waitForExistence(timeout: 30) { r.tap() } },
        Spec(id: "gym", slots: 6) { _, _ in },
        Spec(id: "rocket", slots: 3) { _, _ in },
        Spec(id: "pvp", slots: 3) { _, app in if app.buttons["hub-pvp-league-ul"].waitForExistence(timeout: 30) { app.buttons["hub-pvp-league-ul"].tap() } },
    ]

    private func run(_ id: String) {
        let spec = specs.first { $0.id == id }!
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        // (Available with one edit, in four looks, is each screen's own testXSquadStrengthShots.)
        for scheme in ["light", "dark"] {
            // Current with two earlier current squads: set, change, set, change, set.
            let app = launch(dark: scheme == "dark")
            openTile(app, id)
            spec.prepare(self, app)
            XCTAssertTrue(slot(app, id, 1).waitForExistence(timeout: 60))
            selectAvailable(app)
            if app.buttons["squad-reset-draft"].exists { reveal(app, app.buttons["squad-reset-draft"]).tap() }
            for _ in 0..<3 {
                changeTheSquad(app, id)
                selectAvailable(app)
                // A change can land on the Current itself (a swap back), when the pill already reads Squad set.
                if reveal(app, pill(app)).label == "Set this squad" { setThisSquad(app) }
                if app.buttons["toast-action"].exists { sleep(1) }
            }
            selectTab(app, "current")
            _ = reveal(app, historyRow(app, 2))
            sleep(1)
            shot("\(id)-current-\(scheme)-default")
            if id == "raids" && scheme == "dark" {
                selectAvailable(app)
                scrollToTabs(app)
                sleep(1)
                shot("raids-set-dark-default")
                selectBest(app)
                scrollToTabs(app)
                sleep(1)
                shot("raids-best-dark-default")
                selectAvailable(app)
                changeTheSquad(app, id)
                setThisSquad(app)
                _ = toastText(app)
                shot("raids-replaced-toast")
            }
            app.terminate()
            // The strip while a picker is open and scrolled down the list.
            let strip = launch(dark: scheme == "dark")
            openTile(strip, id)
            spec.prepare(self, strip)
            XCTAssertTrue(slot(strip, id, 1).waitForExistence(timeout: 60))
            openPicker(strip, id, slot: 2)
            XCTAssertTrue(el(strip, "squad-strip").waitForExistence(timeout: 5))
            for _ in 0..<4 { strip.swipeUp() }
            sleep(1)
            shot("\(id)-strip-scrolled-\(scheme)")
            strip.terminate()
        }
    }

    func testRaidsShots() { run("raids") }
    func testMaxShots() { run("max") }
    func testGymShots() { run("gym") }
    func testRocketShots() { run("rocket") }
    func testPvPShots() { run("pvp") }
}
