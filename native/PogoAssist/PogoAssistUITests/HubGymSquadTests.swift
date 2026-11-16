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

        // Slot 2: the one build is in slot 1, which is listed, marked with its slot (choosing it swaps the two); nothing else is in the box for the slot.
        // Available lists only the box: there is no "could get" list.
        openPicker(app, "gym", slot: 2)
        XCTAssertEqual(rows.count, 1, "a Pokémon in another slot is listed, marked")
        XCTAssertTrue(rows.firstMatch.label.hasSuffix("in slot 1, choosing it moves it here"), "slot 2 is empty, so choosing it moves it: " + rows.firstMatch.label)
        XCTAssertFalse(rows.firstMatch.isSelected)
        XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists, "Available has no Could get now list")
        shot("gym-picker-empty")
        closePicker(app)

        // GYM BUILDS replaces TOP AVAILABLE, and the Available | Best switch is the screen's own.
        XCTAssertTrue(reveal(app, app.staticTexts["GYM BUILDS"]).exists)
        XCTAssertFalse(app.staticTexts["TOP AVAILABLE"].exists)
        app.swipeDown(); app.swipeDown()
        app.buttons["squad-tab-best"].tap()
        XCTAssertEqual(app.buttons["squad-tab-best"].isSelected, true)
        // Best fills the six slots from the Gym table whether or not the box has them: the ones it lacks are red, in the squad line and on their cards.
        XCTAssertTrue(el(app, "squad-status").label.hasPrefix("Not ready: ") && el(app, "squad-status").label.contains("to get"), el(app, "squad-status").label)
        XCTAssertTrue((2...6).contains { slot(app, "gym", $0).label.contains("not in your box, to get") }, "a not-owned Pokémon is drawn as such: \(slot(app, "gym", 2).label)")
        openPicker(app, "gym", slot: 2)
        let notOwned = rows.matching(NSPredicate(format: "label CONTAINS 'Not available now' OR label CONTAINS 'Can get now'")).firstMatch
        XCTAssertTrue(notOwned.waitForExistence(timeout: 5), "Best lists a Pokémon the box lacks, with its status (Can get now or Not available now): \(rows.allElementsBoundByIndex.map(\.label))")
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
        XCTAssertEqual(again.buttons["squad-tab-best"].isSelected, true, "Best is remembered across a relaunch")
    }

    /// Rule 27 (pass 2-5): an edit of Available is a draft that never switches tabs; Reset drops it; Save to Current stores it (the first save asks nothing, a second asks
    /// "Replace your current squad?"); Current edits save at once; Delete current squad asks first and leaves Available and Best as they were. Rule 32: the strength line.
    func testGymDraftResetSaveReplaceAndDelete() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "gym")
        XCTAssertTrue(slot(app, "gym", 1).waitForExistence(timeout: 60))
        XCTAssertTrue(slot(app, "gym", 1).label.contains("Blissey"))
        let strength = el(app, "squad-strength")
        XCTAssertTrue(strength.waitForExistence(timeout: 10))
        XCTAssertTrue(strength.label.hasPrefix("Squad strength "), strength.label)
        XCTAssertTrue(strength.label.contains("percent") && strength.label.contains("of best"), "the squad is one scored defender in six, against the best squad: \(strength.label)")
        let before = strength.label
        XCTAssertFalse(tab(app, "current").exists, "a squad with nothing saved has no Current tab")
        XCTAssertFalse(app.buttons["squad-save-current"].exists || app.buttons["squad-reset-draft"].exists, "an unedited suggestion has no Save to Current and no Reset")
        let slot1 = slot(app, "gym", 1).label

        // An edit: Blissey moves to slot 2. It stays on Available (no tab switch), and Save to Current and Reset appear.
        openPicker(app, "gym", slot: 2)
        pickerRows(app).firstMatch.tap()
        closePicker(app)
        XCTAssertTrue(slot(app, "gym", 2).label.contains("Blissey"), "slot 2 took it: \(slot(app, "gym", 2).label)")
        XCTAssertTrue(slot(app, "gym", 1).label.contains("empty"), "slot 1 held it, so it is now empty: \(slot(app, "gym", 1).label)")
        XCTAssertTrue(tab(app, "available").isSelected, "editing never switches tabs")
        XCTAssertFalse(tab(app, "current").exists, "and nothing is saved")
        XCTAssertTrue(reveal(app, app.buttons["squad-save-current"]).waitForExistence(timeout: 5), "an edited suggestion offers Save to Current")
        XCTAssertTrue(app.buttons["squad-reset-draft"].exists)
        XCTAssertTrue(el(app, "squad-strength").label.contains("of best"), el(app, "squad-strength").label)

        // Reset drops the draft at once, with no question.
        app.buttons["squad-reset-draft"].tap()
        XCTAssertTrue(waitGone(app.buttons["squad-reset-draft"]), "Reset clears the controls")
        XCTAssertEqual(slot(app, "gym", 1).label, slot1, "the suggestion is back")
        XCTAssertTrue(slot(app, "gym", 2).label.contains("empty"))
        XCTAssertEqual(reveal(app, el(app, "squad-strength")).label, before)

        // Edit again and save: nothing to replace, so no question; the player stays on Available, which says so, and the Current tab appears.
        openPicker(app, "gym", slot: 2)
        pickerRows(app).firstMatch.tap()
        closePicker(app)
        saveToCurrent(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5), "the Current tab appears")
        XCTAssertTrue(tab(app, "available").isSelected, "and the player stays where they were")
        XCTAssertTrue(el(app, "squad-saved-note").waitForExistence(timeout: 5), "the squad says Saved to Current")
        XCTAssertEqual(el(app, "squad-saved-note").label, "Saved to Current")
        XCTAssertFalse(app.buttons["squad-save-current"].exists, "a saved draft has nothing left to save")

        // A further edit (Blissey on to slot 3) and Save to Current again: it would replace a different squad, so it asks. Cancel leaves Current as it was.
        openPicker(app, "gym", slot: 3)
        pickerRows(app).firstMatch.tap()
        closePicker(app)
        XCTAssertTrue(slot(app, "gym", 3).label.contains("Blissey"))
        XCTAssertFalse(el(app, "squad-saved-note").exists, "a changed draft is no longer the saved one")
        saveToCurrent(app, replacing: false)
        selectTab(app, "current")
        XCTAssertTrue(slot(app, "gym", 2).label.contains("Blissey") && slot(app, "gym", 3).label.contains("empty"), "Cancel left Current as it was: \(slot(app, "gym", 2).label)")
        selectTab(app, "available")
        saveToCurrent(app, replacing: true)
        selectTab(app, "current")
        XCTAssertTrue(slot(app, "gym", 3).label.contains("Blissey"), "Replace made the draft the Current squad: \(slot(app, "gym", 3).label)")

        // Delete current squad asks first; Cancel keeps it, the confirmation removes it and shows Available (the remembered tab), whose draft is as it was.
        deleteCurrent(app, confirm: false)
        XCTAssertTrue(tab(app, "current").exists, "Cancel keeps the Current squad")
        deleteCurrent(app, confirm: true)
        XCTAssertTrue(waitGone(tab(app, "current")), "the Current tab goes")
        XCTAssertTrue(tab(app, "available").isSelected, "and Available shows")
        XCTAssertTrue(slot(app, "gym", 3).label.contains("Blissey"), "Available and Best are not changed: \(slot(app, "gym", 3).label)")
        // The draft was saved and Current is gone: Save shows again, and the squad no longer says it is saved.
        XCTAssertTrue(reveal(app, app.buttons["squad-save-current"]).exists, "Save to Current shows again for that draft")
        XCTAssertFalse(el(app, "squad-saved-note").exists, "and it does not say Saved to Current")
    }

    /// Rule 27.3: a draft drawn as the suggestion is not an edit. Re-choosing the ticked Pokémon leaves the squad with no Save to Current and no Reset.
    func testGymRechoosingTheTickedPokemonIsNotAnEdit() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "gym")
        XCTAssertTrue(slot(app, "gym", 1).waitForExistence(timeout: 60))
        openPicker(app, "gym", slot: 1)
        XCTAssertTrue(pickerRows(app).firstMatch.isSelected)
        pickerRows(app).firstMatch.tap()
        closePicker(app)
        sleep(1)
        XCTAssertFalse(app.buttons["squad-save-current"].exists || app.buttons["squad-reset-draft"].exists, "nothing differs from the suggestion")
        XCTAssertFalse(tab(app, "current").exists)
    }

    /// Rule 27: Available and Best edits last until the player leaves the screen; Current is kept, and the screen opens on it.
    func testGymLeavingTheScreenDropsTheDraftButKeepsCurrent() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "gym")
        XCTAssertTrue(slot(app, "gym", 1).waitForExistence(timeout: 60))
        let slot1 = slot(app, "gym", 1).label
        openPicker(app, "gym", slot: 2)
        pickerRows(app).firstMatch.tap()
        closePicker(app)
        XCTAssertTrue(slot(app, "gym", 2).label.contains("Blissey"))
        // Another tab and back keeps the draft.
        selectBest(app)
        selectAvailable(app)
        XCTAssertTrue(slot(app, "gym", 2).label.contains("Blissey"), "switching tabs keeps the draft")
        back(app, toTile: "gym")
        app.buttons["hub-tile-gym"].tap()
        XCTAssertTrue(slot(app, "gym", 1).waitForExistence(timeout: 30))
        XCTAssertEqual(slot(app, "gym", 1).label, slot1, "leaving the screen dropped the draft")
        XCTAssertFalse(app.buttons["squad-reset-draft"].exists)
        // Saved, the squad survives, and the screen opens on Current.
        openPicker(app, "gym", slot: 2)
        pickerRows(app).firstMatch.tap()
        closePicker(app)
        saveToCurrent(app)
        back(app, toTile: "gym")
        app.buttons["hub-tile-gym"].tap()
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 30))
        XCTAssertTrue(tab(app, "current").isSelected, "a squad with a Current opens on it")
        XCTAssertTrue(slot(app, "gym", 2).label.contains("Blissey"), slot(app, "gym", 2).label)
        selectAvailable(app)
        XCTAssertEqual(slot(app, "gym", 1).label, slot1, "Available starts from the suggestion again")
    }

    /// Rule 34: with a picker open and the page scrolled down the list, the strip of the six slots stays at the top; a chip opens that slot's picker.
    func testGymPinnedStripFollowsTheList() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "gym")
        XCTAssertTrue(slot(app, "gym", 1).waitForExistence(timeout: 60))
        assertStripPinsTheSquad(app, "gym", open: 1, chip: 4, shotName: "gym-strip-scrolled")
    }

    /// P1: a Gym picker row says the copy's CP and IVs and its bulk against the best in the game in its one label.
    func testGymPickerRowsShowCpIvsAndBulkBar() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "gym")
        openPicker(app, "gym", slot: 1)
        assertPickerFigures(app, figure: "percent of the best", available: true)
        XCTAssertTrue(pickerRows(app).firstMatch.label.contains("Defence"), "the existing DEF and HP words stay: \(pickerRows(app).firstMatch.label)")
        closePicker(app)
        selectBest(app)
        openPicker(app, "gym", slot: 1)
        assertPickerFigures(app, figure: "percent of the best", available: false)
        closePicker(app)
    }

    func testGymScreenshots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        // Slot 1: the sample box's one Gym build is offered there, so the picker has an owned row.
        screenSet("gym") { app in
            let s = self.slot(app, "gym", 1)
            if s.waitForExistence(timeout: 30) { self.reveal(app, s).tap() }
        }
        bestSet("gym", slot: 1)
    }

    /// The squad on Current after one saved edit, with its strength bar and links: light, dark, default text and AX5.
    func testGymSquadStrengthShots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        strengthShots("gym")
    }
}
