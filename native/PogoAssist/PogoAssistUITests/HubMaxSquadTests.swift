import XCTest

/// Max battles with its squads (design pass 2), driven with the sample scan: the lists in both segments, a row opening into BRING and the squad of three, the role
/// chips, the picker and what it keeps, Set this squad, and the roster being gone.
final class HubMaxSquadTests: SquadUITestCase {
    func testMaxRowOpensIntoASquadOfThree() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "max")
        // Nothing is under way on 25 Oct, so the screen opens on Coming up: the first Max Monday is tomorrow.
        let row = el(app, "hub-max-row-0")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "a Max timeline row")
        XCTAssertTrue(row.label.contains("26 October, in 1 day") && row.label.contains("Sableye"), row.label)
        XCTAssertFalse(el(app, "hub-max-tile").exists, "the roster is gone")
        XCTAssertFalse(app.staticTexts["YOUR MAX ROSTER"].exists, "and its heading")
        app.buttons["Now"].tap()
        XCTAssertTrue(app.staticTexts["Nothing listed."].waitForExistence(timeout: 5), "Now is empty on 25 Oct")
        app.buttons["Coming up"].tap()

        row.tap()
        XCTAssertTrue(slot(app, "max", 1).waitForExistence(timeout: 10), "an opened row shows its squad")
        XCTAssertTrue(slot(app, "max", 1).label.hasPrefix("Slot 1 of 3, Tank"), slot(app, "max", 1).label)
        XCTAssertTrue(slot(app, "max", 2).label.hasPrefix("Slot 2 of 3, Healer"), slot(app, "max", 2).label)
        XCTAssertTrue(slot(app, "max", 3).label.hasPrefix("Slot 3 of 3, Attacker"), slot(app, "max", 3).label)
        // No Pokémon is marked Dynamax yet, so every Max pick reads Upgrade available (read-back Q7).
        XCTAssertTrue(slot(app, "max", 1).label.contains("Upgrade available"), slot(app, "max", 1).label)
        // An Upgrade available pick is amber: the slot says it needs work, and the squad line counts it (CONCEPTS rules 29 and 30).
        XCTAssertTrue(slot(app, "max", 1).label.hasSuffix("needs work"), slot(app, "max", 1).label)
        XCTAssertTrue(el(app, "squad-status").label.hasPrefix("Nearly ready: ") || el(app, "squad-status").label.hasPrefix("Not ready: "), el(app, "squad-status").label)
        shot("max-open-row")

        // Available lists the player's own Pokémon; those whose build still needs work come under "Available upgrades:" (every Max pick does until it is marked Dynamax).
        openPicker(app, "max", slot: 1)
        XCTAssertTrue(pickerRows(app).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(el(app, "squad-picker-upgrades").label, "Available upgrades:")
        XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists, "Available has no Could get now list")
        closePicker(app)

        // The role chips of a slot: Tank | Healer | Attacker | All. A role change relabels the slot and is kept.
        openPicker(app, "max", slot: 3)
        for r in ["Tank", "Healer", "Attacker", "All"] { XCTAssertTrue(app.buttons["squad-role-\(r)"].exists, "chip \(r)") }
        app.buttons["squad-role-Tank"].tap()
        XCTAssertTrue(slot(app, "max", 3).label.hasPrefix("Slot 3 of 3, Tank"), slot(app, "max", 3).label)
        closePicker(app)
        let set = app.buttons["squad-set"]
        reveal(app, set).tap()
        XCTAssertTrue(el(app, "squad-set-state").waitForExistence(timeout: 5), "✓ Squad set")
        XCTAssertTrue(el(app, "hub-max-row-0").label.contains("squad set"), el(app, "hub-max-row-0").label)

        back(app, toTile: "max")
        app.buttons["hub-tile-max"].tap()
        XCTAssertTrue(el(app, "hub-max-row-0").waitForExistence(timeout: 30))
        XCTAssertTrue(el(app, "hub-max-row-0").label.contains("squad set"), "the squad stays set: \(el(app, "hub-max-row-0").label)")
        el(app, "hub-max-row-0").tap()
        XCTAssertTrue(slot(app, "max", 3).waitForExistence(timeout: 10))
        XCTAssertTrue(slot(app, "max", 3).label.hasPrefix("Slot 3 of 3, Tank"), "the role survives leaving the screen: \(slot(app, "max", 3).label)")
        app.buttons["squad-undo"].tap()
        XCTAssertTrue(app.buttons["squad-set"].waitForExistence(timeout: 5))
    }

    func testMaxSuggestionsFollowAvailableAndBest() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "max")
        el(app, "hub-max-row-0").tap()
        XCTAssertTrue(slot(app, "max", 1).waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["squad-mode-available"].isSelected, true, "Available is the default")
        // The sample box's Max Pokémon are all usable as they are, so Best suggests the same three here; the switch is still the screen's own setting.
        app.buttons["squad-mode-best"].tap()
        XCTAssertEqual(app.buttons["squad-mode-best"].isSelected, true)
        XCTAssertTrue(slot(app, "max", 1).label.hasPrefix("Slot 1 of 3, Tank, Blissey"), slot(app, "max", 1).label)
        // A pick in the picker: the slot's own Pokémon is listed, ticked, and a click keeps it.
        openPicker(app, "max", slot: 1)
        let rows = pickerRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(rows.firstMatch.isSelected, "the slot's own Pokémon is ticked")
        XCTAssertTrue(rows.matching(NSPredicate(format: "label CONTAINS 'Not in your box ·'")).firstMatch.exists, "Best lists a Pokémon the box lacks with its availability line: \(rows.allElementsBoundByIndex.map(\.label))")
        XCTAssertFalse(el(app, "squad-picker-upgrades").exists, "the Available upgrades heading belongs to Available")
        let name = rows.firstMatch.label.components(separatedBy: ",").first ?? ""
        rows.firstMatch.tap()
        XCTAssertTrue(slot(app, "max", 1).label.contains(name), slot(app, "max", 1).label)
        closePicker(app)
        // A pick that is NOT the current Pokémon: slot 1 holds Blissey, and Lapras (slot 2's Healer) is made free by turning slot 2 into an Attacker slot, which Lapras does
        // not fit. Then, with slot 1 open to any role, Lapras is chosen for it.
        openPicker(app, "max", slot: 2)
        app.buttons["squad-role-Attacker"].tap()
        XCTAssertFalse(slot(app, "max", 2).label.contains("Lapras"), slot(app, "max", 2).label)
        closePicker(app)
        openPicker(app, "max", slot: 1)
        app.buttons["squad-role-All"].tap()
        let lapras = pickerRows(app).matching(NSPredicate(format: "label BEGINSWITH 'Lapras'")).firstMatch
        XCTAssertTrue(lapras.waitForExistence(timeout: 5), "the freed copy is listed for slot 1")
        XCTAssertTrue(slot(app, "max", 1).label.contains("Blissey") && !slot(app, "max", 1).label.contains("Lapras"), "slot 1 holds a different Pokémon before the pick: \(slot(app, "max", 1).label)")
        lapras.tap()
        XCTAssertTrue(slot(app, "max", 1).label.contains("Lapras"), slot(app, "max", 1).label)
        closePicker(app)
        back(app, toTile: "max")
        app.buttons["hub-tile-max"].tap()
        el(app, "hub-max-row-0").tap()
        XCTAssertTrue(slot(app, "max", 1).waitForExistence(timeout: 30))
        XCTAssertTrue(slot(app, "max", 1).label.contains("Lapras") && slot(app, "max", 1).label.hasPrefix("Slot 1 of 3, All"), "the exact copy chosen survives leaving the screen: \(slot(app, "max", 1).label)")
        XCTAssertTrue(slot(app, "max", 2).label.hasPrefix("Slot 2 of 3, Attacker"), slot(app, "max", 2).label)
        back(app, toTile: "max")
        app.buttons["hub-tile-max"].tap()
        XCTAssertTrue(app.buttons["squad-mode-best"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons["squad-mode-best"].isSelected, true, "Best is remembered for the Max screen")
    }

    func testMaxScreenshots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        screenSet("max") { app in
            let r = self.el(app, "hub-max-row-0")
            if r.waitForExistence(timeout: 30) { r.tap() }
            let s = self.slot(app, "max", 2)
            if s.waitForExistence(timeout: 10) { self.reveal(app, s).tap() }
        }
    }
}
