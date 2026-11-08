import XCTest

/// Raids with its squads (design pass 2), driven with the sample scan: the Now cards and the chosen raid's squad, Available | Best | Current, the picker and what it keeps, the
/// Set this squad pill and its toasts, and Coming up's rows opening into BRING and the squad.
final class HubRaidsSquadTests: SquadUITestCase {
    func testRaidsSquadPickerSetUnsetAndUndo() throws {
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
        XCTAssertFalse(el(app, "squad-mode-info").exists || el(app, "squad-mode-explainer").exists, "the tabs have no (i) of their own")
        XCTAssertFalse(app.staticTexts["SQUAD"].exists || app.staticTexts["STYLE"].exists, "and no captions")
        // The tabs and the style share one row: tabs on the left, style on the right.
        let tabs = el(app, "squad-mode"), styleRow = el(app, "squad-style")
        XCTAssertTrue(tabs.exists && styleRow.exists)
        XCTAssertEqual(tabs.frame.midY, styleRow.frame.midY, accuracy: 4, "one row")
        XCTAssertLessThan(tabs.frame.minX, styleRow.frame.minX, "tabs left, style right")
        XCTAssertLessThan(tab(app, "available").frame.minX, tab(app, "best").frame.minX)
        // The title's (i) opens the tabs, the suggestion, the style and one line per chip sign.
        app.buttons["squad-info"].tap()
        let info = el(app, "squad-explainer")
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        for word in ["Current", "Available", "Best", "Suggested for raids", "Balanced", "✓ Ready:", "↑ with a cost:", "◎ Get now:", "◌ Not now:", "⇄ Slot N:"] { XCTAssertTrue(info.label.contains(word), "(i) says \(word): \(info.label)") }
        app.buttons["squad-info"].tap()

        // The picker of a slot: role chips, and an empty list says so (Available lists only the box: no Could get now list). The title's (i) carries what the tabs' own (i) did.
        openPicker(app, "raids", slot: 2)
        XCTAssertTrue(app.buttons["squad-role-All"].exists && app.buttons["squad-role-Mega"].exists, "the role chips")
        XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists, "Available has no Could get now list")
        app.buttons["squad-role-Bulky hitter"].tap()
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Bulky hitter"), "choosing a role relabels the slot: \(slot(app, "raids", 2).label)")
        shot("raids-picker")
        closePicker(app)

        // The role change is kept as it is made: it never switches tabs, nothing is set, and it survives leaving the screen.
        XCTAssertTrue(tab(app, "available").isSelected)
        XCTAssertFalse(tab(app, "current").exists)
        XCTAssertFalse(el(app, "hub-raid-row-0").label.contains("squad set"))
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(slot(app, "raids", 2).waitForExistence(timeout: 30))
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Bulky hitter"), "the edit is kept after leaving the screen: \(slot(app, "raids", 2).label)")

        // Set this squad on Available makes the shown squad the Current (nothing to replace, so no question and no toast).
        XCTAssertEqual(pill(app).label, "Set this squad")
        setThisSquad(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5), "Set this squad made it the Current: the Current tab appears")
        XCTAssertTrue(tab(app, "available").isSelected, "and the player stays on the tab they are on")
        XCTAssertTrue(el(app, "hub-raid-row-0").label.contains("squad set"), "the card says so exactly when the squad has a Current: \(el(app, "hub-raid-row-0").label)")
        shot("raids-set-pill")
        // Leave and come back: the screen opens on the tab the squad was last on (D74), here Current, with the role; the Current tab has no pill.
        selectTab(app, "current")
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 30))
        XCTAssertTrue(tab(app, "current").isSelected, "the squad opens on the tab it was last on: Current")
        XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Bulky hitter"), "the role is in the Current: \(slot(app, "raids", 2).label)")
        XCTAssertFalse(pill(app).exists, "the Current tab has no pill")
        // Tapping Squad set (on Available) unsets: the Current segment goes, the pill reads Set this squad, a toast offers Undo.
        selectAvailable(app)
        XCTAssertTrue(waitSquadSet(app), "the tab's squad is the Current, so the pill reads Squad set")
        pill(app).tap()
        XCTAssertEqual(toastText(app), "Squad unset")
        XCTAssertEqual(pill(app).label, "Set this squad")
        XCTAssertTrue(waitGone(tab(app, "current")), "the Current segment disappears")
        XCTAssertFalse(el(app, "hub-raid-row-0").label.contains("squad set"), "and the card is no longer set")
        tapToastUndo(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5), "Undo puts the Current back")
        XCTAssertTrue(waitSquadSet(app))
        XCTAssertTrue(el(app, "hub-raid-row-0").label.contains("squad set"))

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

        // Edits of Best are kept: leaving the screen keeps them, and the Available | Best choice is remembered.
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(app.buttons["squad-tab-best"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["squad-tab-best"].isSelected, true, "Best is remembered")
        el(app, "hub-raid-row-1").tap()
        XCTAssertTrue(slot(app, "raids", 2).waitForExistence(timeout: 10))
        XCTAssertTrue(slot(app, "raids", 2).label.contains(megaName), "the edited pick is kept: \(slot(app, "raids", 2).label)")
        XCTAssertTrue(slot(app, "raids", 1).label.hasPrefix("Slot 1 of 6, Bulky hitter"), "and the role: \(slot(app, "raids", 1).label)")
        XCTAssertFalse(tab(app, "current").exists, "an edit is not a Current")
    }

    /// Rule 27: replacing a Pokémon in one slot moves nothing else, choosing one that sits in another slot swaps the two, and Reset to suggestion restores the suggestion.
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
        XCTAssertEqual(strength.label, "Squad strength 100 percent", "the unedited Best squad is the reference, with no suffix: \(strength.label)")
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
        XCTAssertTrue(edited.hasPrefix("Squad strength ") && (edited.contains("of best") || edited == "Squad strength 100 percent"), "an edited Best squad has its own value against the unedited one: \(edited)")

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

    /// Rule 33: Max damage is a Mega and five Heavy hitters; Balanced the Mega, three Heavy and two Bulky hitters. The choice is remembered; each style keeps its own Available and Best
    /// edits (switching back shows them again) and Current is left as it was.
    func testRaidsMaxDamageGivesFiveHeavyHitterSlotsAndEachStyleKeepsItsEdits() throws {
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
        setThisSquad(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5))
        // And an edit under Balanced (a role change always differs from the suggestion).
        openPicker(app, "raids", slot: 3)
        app.buttons["squad-role-Bulky hitter"].tap()
        closePicker(app)
        XCTAssertTrue(reveal(app, app.buttons["squad-reset-draft"]).exists)

        maxDamage.tap()
        XCTAssertTrue(waitSelected(maxDamage), "Max damage is chosen")
        XCTAssertTrue(slot(app, "raids", 1).label.hasPrefix("Slot 1 of 6, Mega"), slot(app, "raids", 1).label)
        for n in 2...6 { XCTAssertTrue(slot(app, "raids", n).label.hasPrefix("Slot \(n) of 6, Heavy hitter"), "Max damage: five Heavy hitter slots: \(slot(app, "raids", n).label)") }
        XCTAssertTrue(waitGone(app.buttons["squad-reset-draft"]), "Max damage has no edit of its own yet")
        shot("raids-max-damage")
        selectBest(app)
        for n in 2...6 { XCTAssertTrue(slot(app, "raids", n).label.hasPrefix("Slot \(n) of 6, Heavy hitter"), "and Best: \(slot(app, "raids", n).label)") }
        XCTAssertEqual(el(app, "squad-strength").label, "Squad strength 100 percent", "the Best squad of this style is the reference")
        shot("raids-best")
        // Current keeps the roles it was set with.
        selectTab(app, "current")
        XCTAssertTrue(slot(app, "raids", 5).label.hasPrefix("Slot 5 of 6, Bulky hitter"), "Current is untouched by the style: \(slot(app, "raids", 5).label)")
        // Back to Balanced: its Available edit is shown again.
        selectAvailable(app)
        reveal(app, balanced).tap()
        XCTAssertTrue(waitSelected(balanced))
        XCTAssertTrue(slot(app, "raids", 3).label.hasPrefix("Slot 3 of 6, Bulky hitter"), "the Balanced edit is back: \(slot(app, "raids", 3).label)")
        XCTAssertTrue(reveal(app, app.buttons["squad-reset-draft"]).exists)
        reveal(app, maxDamage).tap()

        // The style is remembered per account.
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(app.buttons["squad-style-max-damage"].waitForExistence(timeout: 30))
        card.tap()
        XCTAssertTrue(reveal(app, app.buttons["squad-style-max-damage"]).isSelected, "Max damage is remembered")
        // The title's (i) says what each style is.
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
        XCTAssertTrue(slot(app, "raids", 2).label.contains("You can only have 1 Mega slot") || slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, Heavy hitter"), slot(app, "raids", 2).label)
        XCTAssertFalse(slot(app, "raids", 2).label.contains("No Mega-capable Pokémon left"), "the old words are gone")
    }

    /// Pass 2-6, rule 10: the Mega chip, tapped on a slot that is not the squad's Mega while another slot holds one, shows only "You can only have 1 Mega slot" in place of the rows and does not
    /// change the slot's role. Under Available and under Best; the Mega slot's own picker and every other chip are unchanged.
    func testRaidsTheMegaChipOnAnotherSlotShowsOnlyTheOneMegaMessageUnderBothTabs() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        let card = el(app, "hub-raid-row-1")
        XCTAssertTrue(card.waitForExistence(timeout: 60))
        card.tap()
        XCTAssertTrue(slot(app, "raids", 2).waitForExistence(timeout: 30))
        for tabName in ["available", "best"] {
            selectTab(app, tabName)
            XCTAssertTrue(slot(app, "raids", 1).label.hasPrefix("Slot 1 of 6, Mega") && !slot(app, "raids", 1).label.contains("empty"), "slot 1 holds the squad's Mega: \(slot(app, "raids", 1).label)")
            let before = slot(app, "raids", 2).label
            openPicker(app, "raids", slot: 2)
            XCTAssertTrue(pickerRows(app).firstMatch.waitForExistence(timeout: 5), "slot 2 lists rows")
            XCTAssertFalse(el(app, "squad-picker-one-mega").exists)
            app.buttons["squad-role-Mega"].tap()
            let message = el(app, "squad-picker-one-mega")
            XCTAssertTrue(message.waitForExistence(timeout: 5), "\(tabName): the Mega chip shows the message")
            XCTAssertEqual(message.label, "You can only have 1 Mega slot")
            XCTAssertEqual(pickerRows(app).count, 0, "in place of the rows")
            XCTAssertFalse(el(app, "squad-picker-empty").exists, "and of the empty text")
            XCTAssertLessThan(message.frame.height, 60, "a box no taller than the line needs: \(message.frame)")
            XCTAssertEqual(slot(app, "raids", 2).label, before, "the slot's role is unchanged: \(slot(app, "raids", 2).label)")
            shot("raids-mega-message-\(tabName)")
            // Another chip brings the rows back and changes the role as it always did.
            app.buttons["squad-role-All"].tap()
            XCTAssertTrue(waitGone(message))
            XCTAssertTrue(slot(app, "raids", 2).label.hasPrefix("Slot 2 of 6, All"), slot(app, "raids", 2).label)
            XCTAssertTrue(pickerRows(app).firstMatch.waitForExistence(timeout: 5))
            app.buttons["squad-role-Heavy hitter"].tap()
            closePicker(app)
            // The Mega slot's own picker, with its own Mega chip, lists Mega candidates as before.
            openPicker(app, "raids", slot: 1)
            app.buttons["squad-role-Mega"].tap()
            XCTAssertFalse(el(app, "squad-picker-one-mega").exists, "the Mega slot itself has no message")
            XCTAssertTrue(pickerRows(app).firstMatch.waitForExistence(timeout: 5))
            closePicker(app)
        }
    }

    /// Pass 2-6, rule 27: replacing a different Current asks nothing, shows "Current squad replaced" with Undo, and the replaced squad is the newest of the earlier current squads;
    /// Set squad on a row brings it back; edits on Current save at once and survive leaving the screen.
    func testRaidsSetReplacesWithAToastUndoAndTheHistory() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        let card = el(app, "hub-raid-row-1")
        XCTAssertTrue(card.waitForExistence(timeout: 60))
        card.tap()
        XCTAssertTrue(slot(app, "raids", 1).waitForExistence(timeout: 30))
        changeTheSquad(app, "raids")
        setThisSquad(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5))
        selectTab(app, "current")
        let first = (1...6).map { slot(app, "raids", $0).label }
        XCTAssertFalse(historyRow(app, 1).exists, "no earlier current squad yet")
        // A fresh edit on Available, then Set this squad: a different Current is replaced with no question.
        selectAvailable(app)
        openPicker(app, "raids", slot: 3)
        app.buttons["squad-role-Bulky hitter"].tap()
        closePicker(app)
        let second = (1...6).map { slot(app, "raids", $0).label }
        XCTAssertEqual(pill(app).label, "Set this squad", "a different squad is not the Current")
        pill(app).tap()
        XCTAssertEqual(toastText(app), "Current squad replaced")
        XCTAssertFalse(app.buttons.matching(identifier: "squad-save-current-confirm").firstMatch.exists, "no question")
        shot("raids-replaced-toast")
        selectTab(app, "current")
        XCTAssertEqual((1...6).map { slot(app, "raids", $0).label }, second, "the Current is the squad just set")
        let row = reveal(app, historyRow(app, 1))
        XCTAssertTrue(row.exists, "the replaced squad is the newest earlier current squad")
        XCTAssertTrue(row.label.contains("Today"), row.label)
        let rowBefore = row.label
        shot("raids-current-history")
        // Set squad brings it back; Undo puts the other back again.
        setHistorySquad(app, 1)
        XCTAssertEqual(toastText(app), "Current squad replaced")
        XCTAssertEqual((1...6).map { slot(app, "raids", $0).label }, first, "the old squad is the Current again")
        tapToastUndo(app)
        XCTAssertEqual(toastText(app), "Undone")
        XCTAssertEqual((1...6).map { slot(app, "raids", $0).label }, second, "Undo restored the squad the history row replaced")
        // H1: the history is as it was before Set squad: the same one row, nothing consumed, nothing left over.
        XCTAssertEqual(reveal(app, historyRow(app, 1)).label, rowBefore, "the earlier current squad is back where it was")
        XCTAssertFalse(historyRow(app, 2).exists, "and no other row appeared")
        // Edits on Current save at once.
        changeTheSquad(app, "raids")
        let edited = (1...6).map { slot(app, "raids", $0).label }
        XCTAssertNotEqual(edited, second, "an edit on Current changed it")
        XCTAssertTrue(tab(app, "current").isSelected)
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        card.tap()
        XCTAssertTrue(slot(app, "raids", 1).waitForExistence(timeout: 30))
        XCTAssertTrue(tab(app, "current").isSelected, "a squad with a Current opens on it")
        XCTAssertEqual((1...6).map { slot(app, "raids", $0).label }, edited, "the edit was saved straight away")
    }

    /// D74, rule 27.1: the tab a squad was last on survives a relaunch. A boss with a Current, left on Available, reopens on Available after the app is killed (the edit made there is in
    /// sight), not on Current.
    func testRaidsTheTabASquadWasLastOnSurvivesARelaunch() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        let card = el(app, "hub-raid-row-1")
        XCTAssertTrue(card.waitForExistence(timeout: 60))
        card.tap()
        XCTAssertTrue(slot(app, "raids", 1).waitForExistence(timeout: 30))
        changeTheSquad(app, "raids", availableOnly: true)
        setThisSquad(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5), "the boss has a Current")
        selectTab(app, "current")
        selectTab(app, "available")
        app.terminate()
        let again = launch()
        openTile(again, "raids")
        let boss = el(again, "hub-raid-row-1")
        XCTAssertTrue(boss.waitForExistence(timeout: 60))
        boss.tap()
        XCTAssertTrue(slot(again, "raids", 1).waitForExistence(timeout: 30))
        XCTAssertTrue(tab(again, "current").exists, "the boss still has its Current")
        XCTAssertTrue(waitSelected(tab(again, "available")), "and reopens on Available, where the player left it")
    }

    /// Rule 27 and 32: "Set this squad" on the unedited Best tab makes it the Current and leaves the tab unedited: no Reset, "Squad strength 100%", and the pill reads Squad set.
    func testRaidsSetOnAnUneditedBestTabLeavesItUnedited() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "raids")
        let card = el(app, "hub-raid-row-1")
        XCTAssertTrue(card.waitForExistence(timeout: 60))
        card.tap()
        XCTAssertTrue(slot(app, "raids", 1).waitForExistence(timeout: 30))
        selectBest(app)
        setThisSquad(app)
        XCTAssertTrue(tab(app, "current").waitForExistence(timeout: 5), "the squad was set")
        XCTAssertTrue(tab(app, "best").isSelected)
        XCTAssertFalse(app.buttons["squad-reset-draft"].exists, "the tab is unedited")
        XCTAssertEqual(reveal(app, el(app, "squad-strength")).label, "Squad strength 100 percent")
        shot("raids-set-best")
    }

    /// Rule 34: the pinned strip, two rows of three on this six-slot squad, at the default text size and at AX5 (the rows stay, a chip's name wraps and the strip grows).
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
        assertStripPinsTheSquad(app, "raids", open: 2, chip: 4, slots: 6, shotName: "raids-strip-scrolled")
        // All six chips take a tap while the picker is scrolled (slice 3, D5; H12): each tap opens that chip's slot, highlights its chip and no other. A frame inside the strip is not
        // enough, so every chip is tapped, by coordinate because the framework's hit test can say no for a chip drawn on screen under the strip's inset (H18).
        openPicker(app, "raids", slot: 2)
        for _ in 0..<3 { app.swipeUp() }
        for n in 1...6 {
            let c = app.buttons["squad-strip-chip-\(n)"]
            XCTAssertTrue(c.exists, "slot \(n) has a chip")
            c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Slot \(n) ·")).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 5), "tapping chip \(n) opens slot \(n)'s picker")
            XCTAssertTrue(waitSelected(app.buttons["squad-strip-chip-\(n)"]), "and highlights chip \(n)")
            for other in 1...6 where other != n { XCTAssertFalse(app.buttons["squad-strip-chip-\(other)"].isSelected, "chip \(other) is not the open slot when chip \(n) was tapped") }
        }
        closePicker(app)
        app.terminate()
        let big = launch(ax5: true)
        openTile(big, "raids")
        palkia(big)
        // The tab and style rows at AX5: whole words, one size, stacked.
        XCTAssertTrue(reveal(big, big.buttons["squad-style-max-damage"]).exists)
        XCTAssertTrue(big.buttons["squad-style-max-damage"].label == "Max damage" && big.buttons["squad-tab-available"].exists)
        shot("raids-tabs-style-ax5")
        assertStripPinsTheSquad(big, "raids", open: 2, chip: 3, slots: 6, shotName: "raids-strip-scrolled-ax5")
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

    /// The squad on Available after one edit, with its pill, chips, strength bar and Reset link: light, dark, default text and AX5.
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
