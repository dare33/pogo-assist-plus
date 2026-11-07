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

    /// Pass 2-6, rule 27: the tabs read Available | Best, then Current once there is one; an edit is kept as it is made and never switches tabs; "Reset to suggestion" drops it; "Set this
    /// squad" makes the squad as drawn the Current with no question and the pill turns to "Squad set"; a different squad set later replaces it, with a toast and Undo, and the old one is in
    /// the history; tapping "Squad set" unsets (toast, Undo); "Set squad" on a history row brings an old one back; Delete current squad asks without a message line.
    func testGymEditsAutoSaveResetSetReplaceUndoUnsetHistoryAndDelete() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "gym")
        XCTAssertTrue(slot(app, "gym", 1).waitForExistence(timeout: 60))
        XCTAssertTrue(slot(app, "gym", 1).label.contains("Blissey"))
        let strength = el(app, "squad-strength")
        XCTAssertTrue(strength.waitForExistence(timeout: 10))
        XCTAssertTrue(strength.label.hasPrefix("Squad strength ") && strength.label.contains("percent") && strength.label.contains("of best"), "one scored defender in six, against the best squad: \(strength.label)")
        let before = strength.label
        XCTAssertFalse(tab(app, "current").exists, "a squad with nothing set has no Current tab")
        XCTAssertFalse(app.buttons["squad-save-current"].exists || app.buttons["squad-reset-draft"].exists, "no Save to Current anywhere, and an unedited suggestion has no Reset")
        XCTAssertEqual(pill(app).label, "Set this squad", "the pill is on the tab")
        XCTAssertFalse(el(app, "squad-mode-info").exists, "the tabs have no (i) of their own")
        XCTAssertFalse(app.staticTexts["SQUAD"].exists, "and no caption")
        XCTAssertLessThan(tab(app, "available").frame.minX, tab(app, "best").frame.minX, "Available | Best")
        let slot1 = slot(app, "gym", 1).label

        // An edit is kept as it is made: Blissey moves to slot 2. No tab switch, no Save to Current; Reset to suggestion appears.
        openPicker(app, "gym", slot: 2)
        pickerRows(app).firstMatch.tap()
        closePicker(app)
        XCTAssertTrue(slot(app, "gym", 2).label.contains("Blissey"), "slot 2 took it: \(slot(app, "gym", 2).label)")
        XCTAssertTrue(slot(app, "gym", 1).label.contains("empty"), "slot 1 held it, so it is now empty: \(slot(app, "gym", 1).label)")
        XCTAssertTrue(tab(app, "available").isSelected, "editing never switches tabs")
        XCTAssertFalse(tab(app, "current").exists)
        let reset = reveal(app, app.buttons["squad-reset-draft"])
        XCTAssertTrue(reset.waitForExistence(timeout: 5), "an edited tab offers Reset to suggestion")
        XCTAssertEqual(reset.label, "Reset to suggestion")
        XCTAssertFalse(app.buttons["squad-save-current"].exists)
        XCTAssertTrue(el(app, "squad-strength").label.contains("of best"), el(app, "squad-strength").label)

        // Reset drops it at once, with no question.
        reset.tap()
        XCTAssertTrue(waitGone(app.buttons["squad-reset-draft"]), "Reset clears the link")
        XCTAssertEqual(slot(app, "gym", 1).label, slot1, "the suggestion is back")
        XCTAssertTrue(slot(app, "gym", 2).label.contains("empty"))
        XCTAssertEqual(reveal(app, el(app, "squad-strength")).label, before)

        // Edit again and set: no question; the player stays on Available; the Current segment appears on the right; the pill reads Squad set.
        openPicker(app, "gym", slot: 2)
        pickerRows(app).firstMatch.tap()
        closePicker(app)
        setThisSquad(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5), "the Current tab appears")
        XCTAssertGreaterThan(tab(app, "current").frame.minX, tab(app, "best").frame.minX, "on the right of Best")
        XCTAssertTrue(tab(app, "available").isSelected, "and the player stays where they were")
        XCTAssertFalse(toast(app).exists, "nothing was replaced, so no toast")

        // A further edit (Blissey on to slot 3) is a different squad: the pill reads Set this squad again; setting replaces Current with no question, a toast and Undo.
        openPicker(app, "gym", slot: 3)
        pickerRows(app).firstMatch.tap()
        closePicker(app)
        XCTAssertTrue(slot(app, "gym", 3).label.contains("Blissey"))
        var n = 0
        while !(pill(app).exists && pill(app).isHittable) && n < 8 { app.swipeDown(); n += 1 }
        XCTAssertEqual(pill(app).label, "Set this squad", "a changed squad is not the Current")
        pill(app).tap()
        XCTAssertTrue(waitSquadSet(app))
        XCTAssertEqual(toastText(app), "Current squad replaced", "no question, a toast")
        shot("gym-replaced-toast")
        tapToastUndo(app)
        XCTAssertEqual(toastText(app), "Undone")
        selectTab(app, "current")
        XCTAssertTrue(slot(app, "gym", 2).label.contains("Blissey") && slot(app, "gym", 3).label.contains("empty"), "Undo put the replaced squad back: \(slot(app, "gym", 3).label)")
        XCTAssertFalse(historyRow(app, 1).exists, "and the squad that was just set is dropped, not pushed")

        // Replace again, then the old one is in the history under Current; Set squad on its row brings it back with the toast.
        selectAvailable(app)
        setThisSquad(app)
        XCTAssertEqual(toastText(app), "Current squad replaced")
        selectTab(app, "current")
        XCTAssertTrue(app.staticTexts["EARLIER CURRENT SQUADS"].waitForExistence(timeout: 5) || reveal(app, app.staticTexts["EARLIER CURRENT SQUADS"]).exists, "the history caption")
        let row = reveal(app, historyRow(app, 1))
        XCTAssertTrue(row.exists)
        XCTAssertTrue(row.label.contains("Blissey") && row.label.contains("Today"), "date and Pokémon: \(row.label)")
        shot("gym-current-history")
        setHistorySquad(app, 1)
        XCTAssertEqual(toastText(app), "Current squad replaced", "Set squad asks nothing")
        XCTAssertTrue(slot(app, "gym", 3).label.contains("empty") && slot(app, "gym", 2).label.contains("Blissey"), "the old squad is the Current again")
        XCTAssertTrue(reveal(app, historyRow(app, 1)).exists, "and the one it replaced is at the top of the list")

        // Delete current squad asks first, with no message line; Cancel keeps it, the confirmation moves it to the history and shows Available (the remembered tab).
        reveal(app, app.buttons["squad-delete-current"]).tap()
        XCTAssertTrue(app.buttons.matching(identifier: "squad-delete-current-confirm").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Available and Best are not changed."].exists, "the dialog is the bold question and its buttons only")
        shot("gym-delete-dialog")
        answer(app, asked: "squad-delete-current", confirm: false)
        XCTAssertTrue(tab(app, "current").exists, "Cancel keeps the Current squad")
        deleteCurrent(app, confirm: true)
        XCTAssertEqual(toastText(app), "Current squad deleted", "Delete's toast offers Undo (H11)")
        XCTAssertTrue(waitGone(tab(app, "current")), "the Current tab goes")
        XCTAssertTrue(tab(app, "available").isSelected, "and Available shows")
        tapToastUndo(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5), "Undo of a Delete brings the Current back")
        deleteCurrent(app, confirm: true)
        XCTAssertTrue(waitGone(tab(app, "current")), "deleted again")

        // Squad set unsets: set it again, then tap the set pill.
        setThisSquad(app)
        pill(app).tap()
        XCTAssertEqual(toastText(app), "Squad unset")
        XCTAssertEqual(pill(app).label, "Set this squad", "the pill reads Set this squad")
        XCTAssertTrue(waitGone(tab(app, "current")), "the Current segment disappears")
        tapToastUndo(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5), "Undo of an unset puts the Current back")
        XCTAssertTrue(waitSquadSet(app))
    }

    /// Rule 27.3: an edit drawn as the suggestion is not an edit. Re-choosing the ticked Pokémon leaves the squad with no Reset.
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
        XCTAssertFalse(app.buttons["squad-reset-draft"].exists, "nothing differs from the suggestion")
        XCTAssertFalse(tab(app, "current").exists)
    }

    /// Pass 2-6, rule 27.2: an edit of Available is kept and survives leaving the screen and the app; Set this squad survives too, and the screen opens on Current.
    func testGymAnEditSurvivesLeavingTheScreenAndTheAppAndSetOpensOnCurrent() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "gym")
        XCTAssertTrue(slot(app, "gym", 1).waitForExistence(timeout: 60))
        let slot1 = slot(app, "gym", 1).label
        openPicker(app, "gym", slot: 2)
        pickerRows(app).firstMatch.tap()
        closePicker(app)
        XCTAssertTrue(slot(app, "gym", 2).label.contains("Blissey"))
        // Another tab and back keeps the edit; so does leaving the screen.
        selectBest(app)
        selectAvailable(app)
        XCTAssertTrue(slot(app, "gym", 2).label.contains("Blissey"), "switching tabs keeps the edit")
        back(app, toTile: "gym")
        app.buttons["hub-tile-gym"].tap()
        XCTAssertTrue(slot(app, "gym", 1).waitForExistence(timeout: 30))
        XCTAssertTrue(slot(app, "gym", 2).label.contains("Blissey"), "leaving the screen kept the edit: \(slot(app, "gym", 2).label)")
        XCTAssertTrue(reveal(app, app.buttons["squad-reset-draft"]).exists)
        app.terminate()
        // And the app.
        let again = launch()
        openTile(again, "gym")
        XCTAssertTrue(slot(again, "gym", 2).waitForExistence(timeout: 60))
        XCTAssertTrue(slot(again, "gym", 2).label.contains("Blissey"), "leaving the app kept the edit: \(slot(again, "gym", 2).label)")
        // Set: the squad survives, and the screen opens on Current.
        setThisSquad(again)
        back(again, toTile: "gym")
        again.buttons["hub-tile-gym"].tap()
        XCTAssertTrue(tab(again, "current").waitForExistence(timeout: 30))
        XCTAssertTrue(tab(again, "current").isSelected, "a squad with a Current opens on it")
        XCTAssertTrue(slot(again, "gym", 2).label.contains("Blissey"), slot(again, "gym", 2).label)
        XCTAssertFalse(pill(again).exists, "the Current tab has no pill")
        selectAvailable(again)
        XCTAssertTrue(waitSquadSet(again), "the pill on Available reads Squad set: the tab's squad is the Current")
        XCTAssertNotEqual(slot(again, "gym", 1).label, slot1, "Available still holds the kept edit")
    }

    /// The status words are chips: not elements of their own, and the card and row labels keep the full words.
    func testGymChipsKeepTheFullWordsInTheLabels() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "gym")
        XCTAssertTrue(slot(app, "gym", 1).waitForExistence(timeout: 60))
        XCTAssertTrue(slot(app, "gym", 1).label.hasSuffix("ready") && slot(app, "gym", 1).label.contains("Full strength"), slot(app, "gym", 1).label)
        // (The test framework still lists the chip's text as a static text under the card; the card is one element whose label is read, and the chip is marked hidden from VoiceOver.)
        XCTAssertFalse(slot(app, "gym", 1).label.contains("✓"), "the card's label has the words, not the signs")
        selectBest(app)
        XCTAssertTrue((2...6).contains { slot(app, "gym", $0).label.contains("Not available now") || slot(app, "gym", $0).label.contains("Can get now") }, "a card keeps its status words")
        openPicker(app, "gym", slot: 2)
        let notOwned = pickerRows(app).matching(NSPredicate(format: "label CONTAINS 'Not available now' OR label CONTAINS 'Can get now'")).firstMatch
        XCTAssertTrue(notOwned.waitForExistence(timeout: 5), "a row keeps its status words")
        // The strip says which slots the box lacks.
        let strip = el(app, "squad-strip")
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue((1...6).contains { app.buttons["squad-strip-chip-\($0)"].label.contains("not in your box") }, "a Pokémon the box lacks reads not in your box on its strip chip")
        shot("gym-best-strip-not-owned")
        closePicker(app)
    }

    /// Rule 34: with a picker open and the page scrolled down the list, the strip of the six slots stays at the top; a chip opens that slot's picker.
    func testGymPinnedStripFollowsTheList() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "gym")
        XCTAssertTrue(slot(app, "gym", 1).waitForExistence(timeout: 60))
        assertStripPinsTheSquad(app, "gym", open: 1, chip: 4, slots: 6, shotName: "gym-strip-scrolled")
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

    /// The squad on Available after one edit, with its pill, chips, strength bar and Reset link: light, dark, default text and AX5.
    func testGymSquadStrengthShots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        strengthShots("gym")
    }
}
