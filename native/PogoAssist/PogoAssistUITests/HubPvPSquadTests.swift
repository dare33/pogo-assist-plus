import XCTest

/// PvP leagues with their squads (design pass 2), driven with the sample scan: the league switch, the Suggested squad by role with its coverage, the picker with role chips and
/// graded numbers, OTHER CANDIDATES, and the season line.
final class HubPvPSquadTests: SquadUITestCase {
    func testPvPSquadByRoleAndPicker() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "pvp")
        XCTAssertTrue(el(app, "hub-pvp-league").waitForExistence(timeout: 30))
        // Great League has no candidate in this box.
        XCTAssertTrue(el(app, "hub-pvp-none").waitForExistence(timeout: 60), "Great League has no candidate")
        app.buttons["hub-pvp-league-ul"].tap()
        XCTAssertTrue(app.staticTexts["Suggested squad"].waitForExistence(timeout: 30), "Ultra League shows a squad")
        XCTAssertFalse(app.staticTexts["Suggested team"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Coverage'")).firstMatch.exists, "the coverage figure")
        for (n, role) in [(1, "Lead"), (2, "Safe swap"), (3, "Closer")] {
            XCTAssertTrue(slot(app, "pvp", n).label.hasPrefix("Slot \(n) of 3, \(role)"), slot(app, "pvp", n).label)
        }
        // Available suggests copies as they are; Best may suggest an evolution.
        XCTAssertEqual(app.buttons["squad-mode-available"].isSelected, true)
        shot("pvp-ultra-available")

        openPicker(app, "pvp", slot: 1)
        for r in ["Lead", "Safe swap", "Closer", "All"] { XCTAssertTrue(app.buttons["squad-role-\(r)"].exists, "chip \(r)") }
        app.buttons["squad-role-All"].tap()
        XCTAssertTrue(slot(app, "pvp", 1).label.hasPrefix("Slot 1 of 3, All"), "a role change relabels the slot: \(slot(app, "pvp", 1).label)")
        let rows = pickerRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(rows.firstMatch.label.contains("score"), rows.firstMatch.label)
        shot("pvp-picker")
        closePicker(app)
        back(app, toTile: "pvp")
        app.buttons["hub-tile-pvp"].tap()
        app.buttons["hub-pvp-league-ul"].tap()
        XCTAssertTrue(slot(app, "pvp", 1).waitForExistence(timeout: 30))
        XCTAssertTrue(slot(app, "pvp", 1).label.hasPrefix("Slot 1 of 3, All"), "the role is kept for the league: \(slot(app, "pvp", 1).label)")

        // OTHER CANDIDATES opens a Pokémon's page; the season line closes the screen.
        let others = app.buttons.matching(identifier: "hub-pvp-candidate").firstMatch
        if reveal(app, others).exists { others.tap(); XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10)); app.buttons["Back"].tap() }
        XCTAssertTrue(reveal(app, el(app, "hub-pvp-season")).exists, "the season line")
        XCTAssertEqual(el(app, "hub-pvp-season").label, "Current Season: GO Battle League: Twilight Trails. Ends 1 December, 2026.")
    }

    func testPvPScreenshots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        screenSet("pvp") { app in
            if app.buttons["hub-pvp-league-ul"].waitForExistence(timeout: 30) { app.buttons["hub-pvp-league-ul"].tap() }
            let s = self.slot(app, "pvp", 2)
            if s.waitForExistence(timeout: 30) { self.reveal(app, s).tap() }
        }
    }
}
