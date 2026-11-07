import XCTest

/// Team Rocket with its squads (design pass 2), driven with the sample scan: the leader cards, YOUR SQUAD FOR <LEADER>, the three slot cards and their picker, Next best
/// for a slot nothing beats, and the grunts' rows with their counters.
final class HubRocketSquadTests: SquadUITestCase {
    func testRocketSquadPickerAndGrunts() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "rocket")
        XCTAssertTrue(app.buttons["hub-leader-Giovanni"].waitForExistence(timeout: 30), "a leader card")
        XCTAssertTrue(app.staticTexts["YOUR SQUAD FOR GIOVANNI"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["YOUR TEAM FOR GIOVANNI"].exists)

        // Best: the Rocket table's rows fill the slots, whether or not the box has them (Available leaves a slot empty when nothing in the box beats it).
        app.buttons["squad-tab-best"].tap()
        let one = slot(app, "rocket", 1), two = slot(app, "rocket", 2), three = slot(app, "rocket", 3)
        XCTAssertTrue(one.label.contains("Lucario") && one.label.contains("against Persian"), one.label)
        // A slot of one option has no "beats" line; a slot of three says how many it beats.
        XCTAssertFalse(one.label.contains("beats"), one.label)
        XCTAssertTrue(one.label.contains("Fighting"), "a slot card names the Pokémon's types: \(one.label)")
        XCTAssertTrue(two.label.contains("beats") && two.label.contains("against Kangaskhan / Rhyperior / Machamp"), two.label)
        XCTAssertTrue([one, two, three].contains { $0.label.contains("not in your box, to get") }, "a Pokémon the box lacks is drawn as such")
        XCTAssertTrue(el(app, "squad-status").label.hasPrefix("Not ready: "), el(app, "squad-status").label)

        // Slot 3's picker: choose another row than the suggestion; the slot shows it and it is kept.
        openPicker(app, "rocket", slot: 3)
        XCTAssertTrue(app.staticTexts["Slot 3 · vs Zekrom"].exists)
        let rows = pickerRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let ticked = rows.matching(NSPredicate(format: "selected == true"))
        XCTAssertEqual(ticked.count, 1, "the slot's own Pokémon is ticked")
        XCTAssertGreaterThan(rows.count, 1, "the table lists more than one counter for Zekrom")
        XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists, "there is no Could get now list")
        let other = rows.matching(NSPredicate(format: "selected == false")).firstMatch
        let chosen = other.label.components(separatedBy: ",").first ?? ""
        other.tap()
        XCTAssertTrue(three.label.contains(chosen), "the slot shows the choice: \(three.label)")
        XCTAssertTrue(ticked.count == 1 && ticked.firstMatch.label.hasPrefix(chosen), "and the tick moves")
        shot("rocket-picker")
        closePicker(app)

        // A different leader has its own squad, and Giovanni's kept edit is still there on return.
        app.buttons["hub-change-leader"].tap()
        app.buttons["Sierra"].tap()
        XCTAssertTrue(app.staticTexts["YOUR SQUAD FOR SIERRA"].waitForExistence(timeout: 5))
        XCTAssertFalse(slot(app, "rocket", 3).label.contains("against Zekrom"), "another leader's squad is its own: \(slot(app, "rocket", 3).label)")
        app.buttons["hub-leader-Giovanni"].tap()
        XCTAssertTrue(slot(app, "rocket", 3).label.contains(chosen), "Giovanni's pick is kept: \(slot(app, "rocket", 3).label)")
        back(app, toTile: "rocket")
        app.buttons["hub-tile-rocket"].tap()
        XCTAssertTrue(slot(app, "rocket", 3).waitForExistence(timeout: 30))
        XCTAssertTrue(slot(app, "rocket", 3).label.contains(chosen), "and after leaving the screen too: an edit is kept as it is made: \(slot(app, "rocket", 3).label)")
        // The pill is on this screen too: it makes the squad the Current and nothing else.
        XCTAssertEqual(pill(app).label, "Set this squad")

        // Grunts: a row each; a typed grunt lists the box's counters and the types that beat it, a typeless one says any strong attacker.
        let normal = reveal(app, app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Normal does not mean weak'")).firstMatch, swipes: 12)
        XCTAssertTrue(normal.exists, "the Normal grunt's row")
        XCTAssertTrue(normal.label.contains("Counters:") && normal.label.contains("Beaten by Fighting"), normal.label)
        let mixed = reveal(app, app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Winning is for winners'")).firstMatch, swipes: 12)
        XCTAssertEqual(mixed.label, "Winning is for winners Mixed team. Any strong attacker")
        let decoy = reveal(app, app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Fooled ya, twerp'")).firstMatch, swipes: 12)
        XCTAssertEqual(decoy.label, "Fooled ya, twerp Decoy. Any strong attacker")
        shot("rocket-grunts")
    }

    /// Under Available a slot nothing in the box beats lists Next best (up to three closest options) or, with none, says so; there is no Could get now list.
    func testRocketNextBestUnderAvailable() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "rocket")
        XCTAssertTrue(app.staticTexts["YOUR SQUAD FOR GIOVANNI"].waitForExistence(timeout: 60))
        XCTAssertEqual(app.buttons["squad-tab-available"].isSelected, true, "Available is the default")
        var nextBestRows = [Int](), listed = [Int]()
        for n in 1...3 {
            openPicker(app, "rocket", slot: n)
            listed.append(pickerRows(app).count)
            if app.staticTexts["Next best"].exists {
                nextBestRows.append(pickerRows(app).count)
                XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists, "Available has no Could get now list")
                if nextBestRows.count == 1 { shot("rocket-next-best") }
            }
            closePicker(app)
        }
        // S1: Available takes any build, so the sample box may beat every slot and offer no Next best. Every slot lists something (counters, or Next best), and where
        // Next best is offered it has one to three rows.
        XCTAssertEqual(listed.count, 3)
        XCTAssertTrue(listed.allSatisfy { $0 > 0 }, "each slot's picker lists counters or Next best: \(listed)")
        XCTAssertTrue(nextBestRows.allSatisfy { (1...3).contains($0) }, "up to three rows: \(nextBestRows)")
    }

    /// P1: Rocket picker rows say CP, IVs and their damage figure, under Available and Best.
    func testRocketPickerRowsShowCpIvsAndStrength() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "rocket")
        openPicker(app, "rocket", slot: 2)
        assertPickerFigures(app, figure: "estimated damage", available: true)
        closePicker(app)
        selectBest(app)
        openPicker(app, "rocket", slot: 2)
        assertPickerFigures(app, figure: "estimated damage", available: false)
        closePicker(app)
    }

    func testRocketScreenshots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        screenSet("rocket") { app in
            let s = self.slot(app, "rocket", 2)
            if s.waitForExistence(timeout: 30) { self.reveal(app, s).tap() }
        }
        bestSet("rocket", slot: 2)
    }

    /// Rule 32 and rule 27: the squad strength line, a change, Reset and what it restores.
    func testRocketSquadStrengthChangeAndReset() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "rocket")

        XCTAssertTrue(slot(app, "rocket", 1).waitForExistence(timeout: 60))
        let strength = el(app, "squad-strength")
        XCTAssertTrue(reveal(app, strength).exists)
        XCTAssertTrue(strength.label.hasPrefix("Squad strength"), strength.label)
        let original = slot(app, "rocket", 1).label + "|" + slot(app, "rocket", 2).label + "|" + slot(app, "rocket", 3).label
        XCTAssertFalse(app.buttons["squad-reset-draft"].exists, "an unchanged squad has no Reset")
        changeTheSquad(app, "rocket")
        XCTAssertTrue(reveal(app, app.buttons["squad-reset-draft"]).waitForExistence(timeout: 5), "a changed squad has Reset")
        app.buttons["squad-reset-draft"].tap()
        XCTAssertTrue(waitGone(app.buttons["squad-reset-draft"]), "Reset clears the control")
        // Reset shows the suggestion again; the change may have been made under Best, so look at the squad under Available, where it was read.
        selectAvailable(app)
        XCTAssertEqual(slot(app, "rocket", 1).label + "|" + slot(app, "rocket", 2).label + "|" + slot(app, "rocket", 3).label, original, "the suggestion is back")
    }

    /// Rule 34: the pinned strip of the three slots while a picker is open and scrolled.
    func testRocketPinnedStripFollowsTheList() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "rocket")
        XCTAssertTrue(slot(app, "rocket", 1).waitForExistence(timeout: 60))
        assertStripPinsTheSquad(app, "rocket", open: 1, chip: 3, slots: 3, shotName: "rocket-strip-scrolled")
    }

    /// The squad on Available after one edit, with its pill, chips, strength bar and Reset link: light, dark, default text and AX5.
    func testRocketSquadStrengthShots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        strengthShots("rocket")
    }
}
