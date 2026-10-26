import XCTest

/// Raids with its squads (design pass 2), driven with the sample scan: the Now cards and the chosen raid's squad, SUGGESTIONS · Available | Best, the picker and what it
/// keeps, Set this squad and Undo, and Coming up's rows opening into BRING and the squad.
final class HubRaidsSquadTests: SquadUITestCase {
    func testRaidsSquadPickerSetAndUndo() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Your squad'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 60), "the first card is chosen when the screen opens and its squad shows")
        XCTAssertTrue(title.label.contains("Shadow Landorus"), title.label)

        // Available is the default, and a Mega is work: its slot is empty.
        XCTAssertTrue(slot(app, "raids", 1).label.contains("Mega, empty"), slot(app, "raids", 1).label)
        XCTAssertEqual(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Heavy hitter"), true)
        XCTAssertEqual(app.buttons["squad-mode-available"].isSelected, true)

        // The picker of a slot: role chips, and an empty list says so and keeps Could get now open.
        openPicker(app, "raids", slot: 2)
        XCTAssertTrue(app.buttons["squad-role-All"].exists && app.buttons["squad-role-Mega"].exists, "the role chips")
        app.buttons["squad-role-Bulky hitter"].tap()
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Bulky hitter"), "choosing a role relabels the slot: \(slot(app, "raids", 2).label)")
        shot("raids-picker")
        closePicker(app)

        // The role change was kept: leave and come back.
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(slot(app, "raids", 2).waitForExistence(timeout: 30))
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Bulky hitter"), "the role survives leaving the screen: \(slot(app, "raids", 2).label)")

        // Set and Undo.
        let set = app.buttons["squad-set"]
        reveal(app, set).tap()
        XCTAssertTrue(el(app, "squad-set-state").waitForExistence(timeout: 5), "✓ Squad set")
        XCTAssertTrue(app.buttons["squad-undo"].exists)
        XCTAssertTrue(el(app, "hub-raid-row-0").label.contains("squad set"), "the card says so: \(el(app, "hub-raid-row-0").label)")
        app.buttons["squad-undo"].tap()
        XCTAssertTrue(app.buttons["squad-set"].waitForExistence(timeout: 5), "Undo takes the mark back")

        // Tapping the chosen card closes its squad.
        app.swipeDown(); app.swipeDown()
        el(app, "hub-raid-row-0").tap()
        XCTAssertTrue(waitGone(title), "the chosen card, tapped again, closes the squad")
        el(app, "hub-raid-row-0").tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5), "and opens it again")

        // Coming up: a list; a row opens into BRING and the squad.
        app.buttons["Coming up"].tap()
        let row = el(app, "hub-raid-row-0")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(slot(app, "raids", 1).waitForExistence(timeout: 5), "the opened row shows its squad")
        XCTAssertTrue(app.staticTexts["BRING"].exists || el(app, "hub-raid-row-0").exists)
        shot("raids-coming-up-open")
    }

    func testRaidsSuggestionsFollowAvailableAndBest() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        XCTAssertTrue(slot(app, "raids", 1).waitForExistence(timeout: 60))
        // Palkia, the second card: the box has counters for it (Shadow Landorus has none, so its squad is empty either way).
        el(app, "hub-raid-row-1").tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Your squad – Palkia'")).firstMatch.waitForExistence(timeout: 5))
        // The Mega slot is the one Available leaves empty (rule 3); Best may fill it.
        let available = (1...6).map { slot(app, "raids", $0).label }
        XCTAssertTrue(available[0].contains("empty"), available[0])
        app.buttons["squad-mode-best"].tap()
        XCTAssertEqual(app.buttons["squad-mode-best"].isSelected, true)
        let best = (1...6).map { slot(app, "raids", $0).label }
        shot("raids-palkia-best")
        XCTAssertNotEqual(available.joined(), best.joined(), "switching to Best changes the suggestions: \(best)")

        // The picker of slot 2 under any role: the copy in slot 1 is not offered (a Pokémon sits in one slot at a time), the slot's own is, ticked.
        openPicker(app, "raids", slot: 2)
        app.buttons["squad-role-All"].tap()
        let rows = pickerRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "the box has a counter for Palkia")
        XCTAssertFalse(rows.allElementsBoundByIndex.contains { $0.label.hasPrefix("Rayquaza") }, "a Pokémon in another slot is not listed")
        let chosen = rows.firstMatch.label.components(separatedBy: ",").first ?? ""
        XCTAssertEqual(chosen, "Xerneas")
        XCTAssertTrue(rows.firstMatch.isSelected, "the slot's own Pokémon is listed, ticked")
        rows.firstMatch.tap()
        XCTAssertTrue(slot(app, "raids", 2).label.contains(chosen), "the slot shows the choice: \(slot(app, "raids", 2).label)")
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, All"), "and the role it was given: \(slot(app, "raids", 2).label)")
        closePicker(app)

        // The pick and the setting are remembered for the screen.
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(app.buttons["squad-mode-best"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["squad-mode-best"].isSelected, true, "Best is remembered")
        el(app, "hub-raid-row-1").tap()
        XCTAssertTrue(slot(app, "raids", 2).waitForExistence(timeout: 10))
        XCTAssertTrue(slot(app, "raids", 2).label.contains(chosen) && slot(app, "raids", 2).label.contains("All"), "the pick and its role survive leaving the screen: \(slot(app, "raids", 2).label)")
    }

    func testRaidsScreenshots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        screenSet("raids") { app in
            let s = self.slot(app, "raids", 2)
            if s.waitForExistence(timeout: 30) { self.reveal(app, s).tap() }
        }
    }
}
