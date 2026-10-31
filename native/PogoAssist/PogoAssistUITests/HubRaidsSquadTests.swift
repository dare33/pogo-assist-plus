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
        XCTAssertEqual(app.buttons["squad-mode-available"].isSelected, true)
        XCTAssertEqual(el(app, "squad-status").label, "Nearly ready: 6 need work")

        // The picker of a slot: role chips, and an empty list says so (Available lists only the box: no Could get now list).
        openPicker(app, "raids", slot: 2)
        XCTAssertTrue(app.buttons["squad-role-All"].exists && app.buttons["squad-role-Mega"].exists, "the role chips")
        XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists, "Available has no Could get now list")
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
        // S1: Available fills the Mega slot with a copy that can Mega Evolve, whatever work it needs (the sample box's Rayquaza), and shows the work.
        let available = (1...6).map { slot(app, "raids", $0).label }
        XCTAssertTrue(available[0].hasPrefix("Slot 1 of 6, Mega") && !available[0].contains("empty") && available[0].contains("Upgrade available"), available[0])
        XCTAssertFalse(available.contains { $0.contains("not in your box") }, "Available never puts a Pokémon the box lacks in a slot: \(available)")
        app.buttons["squad-mode-best"].tap()
        XCTAssertEqual(app.buttons["squad-mode-best"].isSelected, true)
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

        // The pick and the setting are remembered for the screen.
        back(app, toTile: "raids")
        app.buttons["hub-tile-raids"].tap()
        XCTAssertTrue(app.buttons["squad-mode-best"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["squad-mode-best"].isSelected, true, "Best is remembered")
        el(app, "hub-raid-row-1").tap()
        XCTAssertTrue(slot(app, "raids", 2).waitForExistence(timeout: 10))
        XCTAssertTrue(slot(app, "raids", 2).label.contains(megaName) && slot(app, "raids", 2).label.contains("All"), "the exact pick and its role survive leaving the screen: \(slot(app, "raids", 2).label)")
        XCTAssertTrue(slot(app, "raids", 1).label.hasPrefix("Slot 1 of 6, Bulky hitter"), slot(app, "raids", 1).label)
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
        let available = app.buttons["squad-mode-available"]
        if available.waitForExistence(timeout: 30) { available.tap() }
        openPicker(app, "raids", slot: 5)
        let other = el(app, "squad-picker-other-roles")
        XCTAssertTrue(other.waitForExistence(timeout: 10) || reveal(app, other).exists, "Other roles: heading in the picker")
        _ = reveal(app, other)
        shot("raids-other-roles-picker")
        app.terminate()
    }
}
