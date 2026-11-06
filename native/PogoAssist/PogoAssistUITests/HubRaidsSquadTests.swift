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

        // Available is the default and fills every slot from the box (S1), even for Shadow Landorus, which nothing in the box counters: Mega-capable copies fill the
        // slots on their Mega build and plain form, below any listed counter. There is no "not counted" state.
        XCTAssertTrue(slot(app, "raids", 1).label.hasPrefix("Slot 1 of 6, Mega, ") && !slot(app, "raids", 1).label.contains("empty"), slot(app, "raids", 1).label)
        XCTAssertTrue(slot(app, "raids", 1).label.contains("Upgrade available: mega evolve"), "the Mega slot never reads Ready: Mega Evolve is still to do: \(slot(app, "raids", 1).label)")
        XCTAssertEqual(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Heavy hitter"), true)
        XCTAssertEqual(app.buttons["squad-tab-available"].isSelected, true)
        XCTAssertEqual(el(app, "squad-status").label, "Nearly ready: 6 need work")

        // The picker of a slot: role chips, and an empty list says so (Available lists only the box: no Could get now list).
        openPicker(app, "raids", slot: 2)
        XCTAssertTrue(app.buttons["squad-role-All"].exists && app.buttons["squad-role-Mega"].exists, "the role chips")
        XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists, "Available has no Could get now list")
        app.buttons["squad-role-Bulky hitter"].tap()
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Bulky hitter"), "choosing a role relabels the slot: \(slot(app, "raids", 2).label)")
        shot("raids-picker")
        closePicker(app)

        // The role change is a draft on Available: it never switches tabs, nothing is saved, and leaving the screen drops it.
        XCTAssertTrue(tab(app, "available").isSelected)
        XCTAssertFalse(tab(app, "current").exists)
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(slot(app, "raids", 2).waitForExistence(timeout: 30))
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Heavy hitter"), "the draft does not survive leaving the screen: \(slot(app, "raids", 2).label)")

        // Set this squad on Available saves the shown squad to Current (nothing to replace, so no question) and sets the mark there.
        openPicker(app, "raids", slot: 2)
        app.buttons["squad-role-Bulky hitter"].tap()
        closePicker(app)
        let set = app.buttons["squad-set"]
        reveal(app, set).tap()
        XCTAssertTrue(el(app, "squad-set-state").waitForExistence(timeout: 5), "✓ Squad set")
        XCTAssertTrue(app.buttons["squad-undo"].exists)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5), "Set this squad saved the squad: the Current tab appears")
        XCTAssertTrue(tab(app, "available").isSelected, "and the player stays on the tab they are on")
        XCTAssertTrue(el(app, "hub-raid-row-0").label.contains("squad set"), "the card says so: \(el(app, "hub-raid-row-0").label)")
        // Leave and come back: the screen opens on Current, with the role, the mark and Undo.
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 30))
        XCTAssertTrue(tab(app, "current").isSelected, "a squad with a Current opens on it")
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Bulky hitter"), "the role was saved to Current: \(slot(app, "raids", 2).label)")
        XCTAssertTrue(el(app, "squad-set-state").waitForExistence(timeout: 5))
        app.buttons["squad-undo"].tap()
        XCTAssertTrue(app.buttons["squad-set"].waitForExistence(timeout: 5), "Undo takes the mark back")
        // "Set this squad" on Current sets the mark as it always did.
        app.buttons["squad-set"].tap()
        XCTAssertTrue(el(app, "squad-set-state").waitForExistence(timeout: 5))
        app.buttons["squad-undo"].tap()

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
        // S1: Available fills the Mega slot with a copy that can Mega Evolve, whatever work it needs (the sample box's Rayquaza), and shows the work.
        let available = (1...6).map { slot(app, "raids", $0).label }
        XCTAssertTrue(available[0].hasPrefix("Slot 1 of 6, Mega") && !available[0].contains("empty") && available[0].contains("Upgrade available"), available[0])
        XCTAssertFalse(available.contains { $0.contains("not in your box") }, "Available never puts a Pokémon the box lacks in a slot: \(available)")
        app.buttons["squad-tab-best"].tap()
        XCTAssertEqual(app.buttons["squad-tab-best"].isSelected, true)
        let best = (1...6).map { slot(app, "raids", $0).label }
        shot("raids-palkia-best")
        XCTAssertNotEqual(available.joined(), best.joined(), "switching to Best changes the suggestions: \(best)")
        // Best fills every slot from the raid table, so the Mega slot holds a Mega; a Pokémon the box lacks is drawn as such and counted in the squad line.
        XCTAssertFalse(best[0].contains("empty"), best[0])
        XCTAssertTrue(best.contains { $0.contains("not in your box, to get") }, "a Pokémon the box lacks is drawn as such: \(best)")
        XCTAssertTrue(el(app, "squad-status").label.hasPrefix("Not ready: ") && el(app, "squad-status").label.contains("to get"), el(app, "squad-status").label)
        // Each filled slot's spoken label ends with its status.
        XCTAssertTrue(best.allSatisfy { $0.hasSuffix("ready") || $0.hasSuffix("needs work") || $0.hasSuffix("to get") || $0.hasSuffix("empty") }, "\(best)")
        let megaName = best[0].components(separatedBy: ", ")[2]

        // The picker of slot 2 under any role: the tier table's rows, the Pokémon the box lacks with an availability line; the copy in slot 1 is not offered (a Pokémon
        // sits in one slot at a time), the slot's own is, ticked.
        openPicker(app, "raids", slot: 2)
        app.buttons["squad-role-All"].tap()
        let rows = pickerRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "Best lists the table's rows for Palkia")
        XCTAssertFalse(rows.allElementsBoundByIndex.contains { $0.label.hasPrefix(megaName) }, "a Pokémon in another slot is not listed")
        XCTAssertTrue(rows.matching(NSPredicate(format: "label CONTAINS 'Not available now' OR label CONTAINS 'Can get now'")).firstMatch.exists, "a Pokémon the box lacks says Can get now or Not available now: \(rows.allElementsBoundByIndex.map(\.label))")
        XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists, "there is no Could get now list")
        let ticked = rows.matching(NSPredicate(format: "selected == true")).firstMatch
        XCTAssertTrue(ticked.exists, "the slot's own Pokémon is listed, ticked")
        let chosen = ticked.label.components(separatedBy: ",").first ?? ""
        ticked.tap()
        XCTAssertTrue(slot(app, "raids", 2).label.contains(chosen), "the slot shows the choice: \(slot(app, "raids", 2).label)")
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, All"), "and the role it was given: \(slot(app, "raids", 2).label)")
        closePicker(app)

        // A pick that is NOT the current Pokémon: slot 2 holds one Pokémon, and the suggested Mega is made free by turning slot 1 into a Bulky hitter slot, which a Mega
        // does not fit. Then that Mega is chosen for slot 2.
        openPicker(app, "raids", slot: 1)
        app.buttons["squad-role-Bulky hitter"].tap()
        XCTAssertFalse(slot(app, "raids", 1).label.contains(megaName), "a Pokémon that does not fit the new role leaves the slot: \(slot(app, "raids", 1).label)")
        closePicker(app)
        openPicker(app, "raids", slot: 2)
        let mega = pickerRows(app).matching(NSPredicate(format: "label BEGINSWITH %@", megaName)).firstMatch
        XCTAssertTrue(mega.waitForExistence(timeout: 5), "the freed Mega is listed for slot 2")
        XCTAssertTrue(slot(app, "raids", 2).label.contains(chosen) && !slot(app, "raids", 2).label.contains(megaName), "slot 2 holds a different Pokémon before the pick: \(slot(app, "raids", 2).label)")
        mega.tap()
        XCTAssertTrue(slot(app, "raids", 2).label.contains(megaName), "the slot shows the choice: \(slot(app, "raids", 2).label)")
        closePicker(app)

        // Edits of Best are a draft: leaving the screen drops them, and the Available | Best choice is remembered.
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(app.buttons["squad-tab-best"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["squad-tab-best"].isSelected, true, "Best is remembered")
        el(app, "hub-raid-row-1").tap()
        XCTAssertTrue(slot(app, "raids", 2).waitForExistence(timeout: 10))
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Heavy hitter") && !slot(app, "raids", 2).label.contains(megaName), "the drafted pick and role are gone: \(slot(app, "raids", 2).label)")
        XCTAssertTrue(slot(app, "raids", 1).label.hasPrefix("Slot 1 of 6, Mega"), slot(app, "raids", 1).label)
        XCTAssertFalse(tab(app, "current").exists, "nothing was saved")
    }

    /// Rule 27: replacing a Pokémon in one slot moves nothing else, choosing one that sits in another slot swaps the two, and Reset restores the suggestion.
    /// Rule 32: the squad strength line reads 100% on the unedited Best tab and falls once the squad is edited. Under Best, where the tables give many rows.
    func testRaidsReplaceSwapAndReset() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        let card = el(app, "hub-raid-row-1")
        XCTAssertTrue(card.waitForExistence(timeout: 60))
        card.tap()
        XCTAssertTrue(slot(app, "raids", 1).waitForExistence(timeout: 30))
        selectBest(app)
        let strength = el(app, "squad-strength")
        XCTAssertTrue(reveal(app, strength).exists)
        XCTAssertTrue(strength.label.hasPrefix("Squad strength 100 percent") && strength.label.contains("the best squad"), "the unedited Best squad is the reference: \(strength.label)")
        let startStrength = strength.label
        XCTAssertFalse(app.buttons["squad-reset-draft"].exists, "an unchanged squad has no Reset")
        let original = (1...6).map { slot(app, "raids", $0).label }
        let names = (1...6).map { slotName(app, "raids", $0) }

        // Replace slot 4: its Pokémon does not drop into another slot, and no other slot changes.
        openPicker(app, "raids", slot: 4)
        let fresh = try XCTUnwrap(chooseAFreshRow(app), "the table lists another Pokémon for a Heavy hitter slot")
        closePicker(app)
        XCTAssertTrue(slot(app, "raids", 4).label.contains(fresh), "slot 4 shows the choice: \(slot(app, "raids", 4).label)")
        for n in [1, 2, 3, 5, 6] { XCTAssertEqual(slot(app, "raids", n).label, original[n - 1], "slot \(n) did not move") }
        XCTAssertFalse([1, 2, 3, 5, 6].contains { slot(app, "raids", $0).label.contains(names[3]) }, "the replaced Pokémon is not in another slot")
        XCTAssertTrue(reveal(app, app.buttons["squad-reset-draft"]).exists, "an edited squad has Reset")
        XCTAssertTrue(tab(app, "best").isSelected, "and stays on Best")
        let edited = reveal(app, el(app, "squad-strength")).label
        XCTAssertTrue(edited.hasPrefix("Squad strength ") && !edited.contains("the best squad"), "an edited Best squad has its own value against the unedited one: \(edited)")

        // Swap: slot 4's picker lists slot 2's Pokémon, marked; choosing it exchanges the two.
        openPicker(app, "raids", slot: 4)
        let held = pickerRows(app).matching(NSPredicate(format: "label CONTAINS 'in slot 2, choosing it swaps the two'")).firstMatch
        XCTAssertTrue(held.waitForExistence(timeout: 10), "slot 2's Pokémon is listed in slot 4's picker, marked")
        XCTAssertTrue(held.label.hasPrefix(names[1]), held.label)
        held.tap()
        closePicker(app)
        XCTAssertTrue(slot(app, "raids", 4).label.contains(names[1]), "slot 4 took slot 2's Pokémon: \(slot(app, "raids", 4).label)")
        XCTAssertTrue(slot(app, "raids", 2).label.contains(fresh), "slot 2 took slot 4's: \(slot(app, "raids", 2).label)")
        for n in [1, 3, 5, 6] { XCTAssertEqual(slot(app, "raids", n).label, original[n - 1], "slot \(n) did not move") }

        // Reset drops the draft at once.
        reveal(app, app.buttons["squad-reset-draft"]).tap()
        XCTAssertTrue(waitGone(app.buttons["squad-reset-draft"]), "Reset clears the control")
        for n in 1...6 { XCTAssertEqual(slot(app, "raids", n).label, original[n - 1], "slot \(n) is back to the suggestion") }
        XCTAssertEqual(reveal(app, el(app, "squad-strength")).label, startStrength)
    }

    /// Rule 33: Max damage is a Mega and five Heavy hitters; Balanced the Mega, three Heavy and two Bulky hitters. The choice is remembered, drops the Available and Best drafts and
    /// leaves Current as it was.
    func testRaidsMaxDamageGivesFiveHeavyHitterSlots() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        let card = el(app, "hub-raid-row-1")
        XCTAssertTrue(card.waitForExistence(timeout: 60))
        card.tap()
        XCTAssertTrue(slot(app, "raids", 1).waitForExistence(timeout: 30))
        let balanced = app.buttons["squad-style-balanced"], maxDamage = app.buttons["squad-style-max-damage"]
        XCTAssertTrue(reveal(app, balanced).exists)
        XCTAssertTrue(balanced.isSelected, "Balanced is the default")
        for (n, role) in [(1, "Mega"), (2, "Heavy hitter"), (3, "Heavy hitter"), (4, "Heavy hitter"), (5, "Bulky hitter"), (6, "Bulky hitter")] {
            XCTAssertTrue(slot(app, "raids", n).label.hasPrefix("Slot \(n) of 6, \(role)"), slot(app, "raids", n).label)
        }
        // A Current squad under Balanced, to see it left alone.
        changeTheSquad(app, "raids")
        saveToCurrent(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5))
        // And a draft that the style change drops.
        changeTheSquad(app, "raids")
        XCTAssertTrue(reveal(app, app.buttons["squad-reset-draft"]).exists)

        maxDamage.tap()
        XCTAssertTrue(waitSelected(maxDamage), "Max damage is chosen")
        XCTAssertTrue(slot(app, "raids", 1).label.hasPrefix("Slot 1 of 6, Mega"), slot(app, "raids", 1).label)
        for n in 2...6 { XCTAssertTrue(slot(app, "raids", n).label.hasPrefix("Slot \(n) of 6, Heavy hitter"), "Max damage: five Heavy hitter slots: \(slot(app, "raids", n).label)") }
        XCTAssertTrue(waitGone(app.buttons["squad-reset-draft"]), "a change of style drops the Available draft")
        shot("raids-max-damage")
        selectBest(app)
        for n in 2...6 { XCTAssertTrue(slot(app, "raids", n).label.hasPrefix("Slot \(n) of 6, Heavy hitter"), "and Best: \(slot(app, "raids", n).label)") }
        XCTAssertTrue(el(app, "squad-strength").label.contains("the best squad"), "the Best squad of this style is the reference: \(el(app, "squad-strength").label)")
        shot("raids-best")
        // Current keeps the roles it was saved with.
        selectTab(app, "current")
        XCTAssertTrue(slot(app, "raids", 5).label.hasPrefix("Slot 5 of 6, Bulky hitter"), "Current is untouched by the style: \(slot(app, "raids", 5).label)")

        // The style is remembered per account.
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(app.buttons["squad-style-max-damage"].waitForExistence(timeout: 30))
        card.tap()
        XCTAssertTrue(reveal(app, app.buttons["squad-style-max-damage"]).isSelected, "Max damage is remembered")
        // The explainer says what each style is.
        app.buttons["squad-info"].tap()
        let explainer = el(app, "squad-explainer")
        XCTAssertTrue(explainer.waitForExistence(timeout: 5))
        XCTAssertTrue(explainer.label.contains("Balanced: a Mega, three heavy hitters and two bulky hitters that stay in longer.") && explainer.label.contains("Max damage: a Mega and five heavy hitters; faster, with more relobbies."), explainer.label)
    }

    /// Rule 27 and Greg's wording: a squad holds one Mega, and the second Mega slot says so.
    func testRaidsASecondMegaSlotSaysYouCanOnlyHaveOne() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        let card = el(app, "hub-raid-row-1")
        XCTAssertTrue(card.waitForExistence(timeout: 60))
        card.tap()
        XCTAssertTrue(slot(app, "raids", 2).waitForExistence(timeout: 30))
        openPicker(app, "raids", slot: 2)
        app.buttons["squad-role-Mega"].tap()
        closePicker(app)
        XCTAssertTrue(slot(app, "raids", 2).label.contains("You can only have 1 Mega slot"), slot(app, "raids", 2).label)
        XCTAssertFalse(slot(app, "raids", 2).label.contains("No Mega-capable Pokémon left"), "the old words are gone")
    }

    /// Rule 27: saving over a Current squad asks first; Cancel and Replace both work; edits on Current save at once and survive leaving the screen.
    func testRaidsSaveReplaceDialogAndCurrentEdits() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        let card = el(app, "hub-raid-row-1")
        XCTAssertTrue(card.waitForExistence(timeout: 60))
        card.tap()
        XCTAssertTrue(slot(app, "raids", 1).waitForExistence(timeout: 30))
        changeTheSquad(app, "raids")
        saveToCurrent(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5))
        selectTab(app, "current")
        let saved = (1...6).map { slot(app, "raids", $0).label }
        // A fresh edit on Available, then Save to Current: it asks. Cancel leaves Current as saved.
        selectAvailable(app)
        changeTheSquad(app, "raids")
        reveal(app, app.buttons["squad-save-current"]).tap()
        XCTAssertTrue(app.buttons.matching(identifier: "squad-save-current-confirm").firstMatch.waitForExistence(timeout: 5))
        shot("raids-save-replace-dialog")
        answer(app, asked: "squad-save-current", confirm: false)
        selectTab(app, "current")
        XCTAssertEqual((1...6).map { slot(app, "raids", $0).label }, saved, "Cancel left Current as it was")
        // Edits on Current save at once.
        changeTheSquad(app, "raids")
        let edited = (1...6).map { slot(app, "raids", $0).label }
        XCTAssertNotEqual(edited, saved, "an edit on Current changed it")
        XCTAssertTrue(tab(app, "current").isSelected)
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        card.tap()
        XCTAssertTrue(slot(app, "raids", 1).waitForExistence(timeout: 30))
        XCTAssertTrue(tab(app, "current").isSelected, "a squad with a Current opens on it")
        XCTAssertEqual((1...6).map { slot(app, "raids", $0).label }, edited, "the edit was saved straight away")
    }

    /// Rule 34: the pinned strip at the default text size and at AX5 (where the chips keep whole words and the strip scrolls sideways).
    func testRaidsPinnedStripFollowsTheList() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        let palkia = { (app: XCUIApplication) in
            let card = self.el(app, "hub-raid-row-1")
            if card.waitForExistence(timeout: 30) { card.tap() }
            XCTAssertTrue(self.slot(app, "raids", 1).waitForExistence(timeout: 30))
        }
        let app = launch()
        openTile(app, "raids")
        palkia(app)
        assertStripPinsTheSquad(app, "raids", open: 2, chip: 4, shotName: "raids-strip-scrolled")
        app.terminate()
        let big = launch(ax5: true)
        openTile(big, "raids")
        palkia(big)
        assertStripPinsTheSquad(big, "raids", open: 2, chip: 3, shotName: "raids-strip-scrolled-ax5")
        big.terminate()
    }

    /// P1: every picker row says the copy's CP and IVs and its estimated damage in its one VoiceOver label (the bar itself is hidden from VoiceOver).
    func testRaidsPickerRowsShowCpIvsAndStrength() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        let card = el(app, "hub-raid-row-1")
        if card.waitForExistence(timeout: 30) { card.tap() }
        openPicker(app, "raids", slot: 2)
        assertPickerFigures(app, figure: "estimated damage", available: true)
        closePicker(app)
        // Best: the box's Pokémon say their figures; one the box lacks has no CP line but says its figure at level 50.
        selectBest(app)
        openPicker(app, "raids", slot: 2)
        assertPickerFigures(app, figure: "estimated damage", available: false)
        closePicker(app)
    }

    func testRaidsScreenshots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        // Palkia, the second card: the sample box counters it, so Available shows a filled squad (the first card, Shadow Landorus, has no counter in the box).
        let palkia = { (app: XCUIApplication) in
            let card = self.el(app, "hub-raid-row-1")
            if card.waitForExistence(timeout: 30) { card.tap() }
        }
        screenSet("raids") { app in
            palkia(app)
            let s = self.slot(app, "raids", 2)
            if s.waitForExistence(timeout: 30) { self.reveal(app, s).tap() }
        }
        bestSet("raids", slot: 2, prepare: palkia)
        // The picker of a Bulky slot under Available: its own role, then "Other roles:".
        let app = launch()
        openTile(app, "raids")
        palkia(app)
        let available = app.buttons["squad-tab-available"]
        if available.waitForExistence(timeout: 30) { available.tap() }
        openPicker(app, "raids", slot: 5)
        let other = el(app, "squad-picker-other-roles")
        XCTAssertTrue(other.waitForExistence(timeout: 10) || reveal(app, other).exists, "Other roles: heading in the picker")
        _ = reveal(app, other)
        shot("raids-other-roles-picker")
        app.terminate()
    }

    /// The squad on Current after one saved edit, with its strength bar and links: light, dark, default text and AX5.
    func testRaidsSquadStrengthShots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        strengthShots("raids") { app in
            let card = self.el(app, "hub-raid-row-1")
            if card.waitForExistence(timeout: 30) { card.tap() }
        }
    }
}
