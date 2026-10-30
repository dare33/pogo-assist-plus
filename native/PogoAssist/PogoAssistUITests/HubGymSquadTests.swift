import XCTest

/// Gym battles with its Top defenders (design pass 2), driven with the sample scan: the six slot cards, the picker with DEF / HP and BULK, GYM BUILDS, and what the screen
/// keeps across a relaunch.
final class HubGymSquadTests: SquadUITestCase {
    func testGymPickerAndWhatItKeeps() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "gym")
        XCTAssertTrue(app.staticTexts["Top defenders"].waitForExistence(timeout: 60))
        XCTAssertTrue(slot(app, "gym", 1).label.contains("Blissey"), slot(app, "gym", 1).label)
        XCTAssertTrue(slot(app, "gym", 1).label.contains("Full strength"), "a built defender carries the Full strength mark: \(slot(app, "gym", 1).label)")
        XCTAssertTrue(slot(app, "gym", 2).label.contains("empty"), slot(app, "gym", 2).label)
        // Slot status (CONCEPTS rules 29 and 30): Blissey is at Full strength and tier S, so its slot is ready; the other five are empty.
        XCTAssertTrue(slot(app, "gym", 1).label.hasSuffix("ready"), "a ready slot says so: \(slot(app, "gym", 1).label)")
        XCTAssertEqual(el(app, "squad-status").label, "Not ready: 5 empty")

        // Slot 1's picker: its own Pokémon, ticked, with Defence, HP and bulk.
        openPicker(app, "gym", slot: 1)
        XCTAssertTrue(app.staticTexts["Slot 1 · Defender"].exists)
        let rows = pickerRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(rows.firstMatch.label.hasPrefix("Blissey"), rows.firstMatch.label)
        XCTAssertTrue(rows.firstMatch.isSelected, "the slot's own Pokémon is ticked")
        XCTAssertTrue(rows.firstMatch.label.contains("Defence") && rows.firstMatch.label.contains("HP") && rows.firstMatch.label.contains("bulk"), rows.firstMatch.label)
        rows.firstMatch.tap()
        XCTAssertTrue(slot(app, "gym", 1).label.contains("Blissey"))
        // The order is explained behind the "i", not shown.
        XCTAssertFalse(el(app, "squad-picker-explainer").exists)
        app.buttons["squad-picker-info"].tap()
        XCTAssertTrue(el(app, "squad-picker-explainer").waitForExistence(timeout: 5), "the order of the list is behind an i")
        closePicker(app)

        // Slot 2: the one build is in slot 1, so nothing is listed. Available lists only the box: the empty text stands alone, with no "could get" list.
        openPicker(app, "gym", slot: 2)
        XCTAssertEqual(rows.count, 0, "a Pokémon in another slot is not listed")
        XCTAssertEqual(el(app, "squad-picker-empty").label, "Everything in your box for this slot is already in your squad.", "the box has a Gym build, in slot 1: the text says so")
        XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists, "Available has no Could get now list")
        shot("gym-picker-empty")
        closePicker(app)

        // GYM BUILDS replaces TOP AVAILABLE, and the Available | Best switch is the screen's own.
        XCTAssertTrue(reveal(app, app.staticTexts["GYM BUILDS"]).exists)
        XCTAssertFalse(app.staticTexts["TOP AVAILABLE"].exists)
        app.swipeDown(); app.swipeDown()
        app.buttons["squad-mode-best"].tap()
        XCTAssertEqual(app.buttons["squad-mode-best"].isSelected, true)
        // Best fills the six slots from the Gym table whether or not the box has them: the ones it lacks are red, in the squad line and on their cards.
        XCTAssertTrue(el(app, "squad-status").label.hasPrefix("Not ready: ") && el(app, "squad-status").label.contains("to get"), el(app, "squad-status").label)
        XCTAssertTrue((2...6).contains { slot(app, "gym", $0).label.contains("not in your box, to get") }, "a not-owned Pokémon is drawn as such: \(slot(app, "gym", 2).label)")
        openPicker(app, "gym", slot: 2)
        let notOwned = rows.matching(NSPredicate(format: "label CONTAINS 'Not in your box'")).firstMatch
        XCTAssertTrue(notOwned.waitForExistence(timeout: 5), "Best lists a Pokémon the box lacks, with its availability line: \(rows.allElementsBoundByIndex.map(\.label))")
        XCTAssertTrue(rows.firstMatch.label.contains("tier"), rows.firstMatch.label)
        XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists)
        shot("gym-picker-best")
        closePicker(app)
        app.terminate()

        // Relaunched: the box, the picks and the setting are where they were left.
        let again = launch()
        openTile(again, "gym")
        XCTAssertTrue(slot(again, "gym", 1).waitForExistence(timeout: 60))
        XCTAssertTrue(slot(again, "gym", 1).label.contains("Blissey"), slot(again, "gym", 1).label)
        XCTAssertEqual(again.buttons["squad-mode-best"].isSelected, true, "Best is remembered across a relaunch")
    }

    func testGymScreenshots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        screenSet("gym") { app in
            let s = self.slot(app, "gym", 2)
            if s.waitForExistence(timeout: 30) { self.reveal(app, s).tap() }
        }
        bestSet("gym", slot: 2)
    }
}
