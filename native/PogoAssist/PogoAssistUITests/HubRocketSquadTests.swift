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

        // Best: the Rocket table's rows fill the slots, whether or not the box has them (Available leaves a slot empty when nothing is usable as it is).
        app.buttons["squad-mode-best"].tap()
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

        // A different leader has its own squad, and Giovanni's pick is still there on return.
        app.buttons["hub-change-leader"].tap()
        app.buttons["Sierra"].tap()
        XCTAssertTrue(app.staticTexts["YOUR SQUAD FOR SIERRA"].waitForExistence(timeout: 5))
        XCTAssertFalse(slot(app, "rocket", 3).label.contains("against Zekrom"), "another leader's squad is its own: \(slot(app, "rocket", 3).label)")
        app.buttons["hub-leader-Giovanni"].tap()
        XCTAssertTrue(slot(app, "rocket", 3).label.contains(chosen), "Giovanni's pick is kept: \(slot(app, "rocket", 3).label)")
        back(app, toTile: "rocket")
        app.buttons["hub-tile-rocket"].tap()
        XCTAssertTrue(slot(app, "rocket", 3).waitForExistence(timeout: 30))
        XCTAssertTrue(slot(app, "rocket", 3).label.contains(chosen), "and after leaving the screen: \(slot(app, "rocket", 3).label)")

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

    /// Under Available a slot with nothing usable as it is lists Next best (up to three closest options) or, with none, says so; there is no Could get now list.
    func testRocketNextBestUnderAvailable() throws {
        let app = launch(reset: true)
        populate(app)
        openTile(app, "rocket")
        XCTAssertTrue(app.staticTexts["YOUR SQUAD FOR GIOVANNI"].waitForExistence(timeout: 60))
        XCTAssertEqual(app.buttons["squad-mode-available"].isSelected, true, "Available is the default")
        var nextBestRows = [Int]()
        for n in 1...3 {
            openPicker(app, "rocket", slot: n)
            if app.staticTexts["Next best"].exists {
                nextBestRows.append(pickerRows(app).count)
                XCTAssertFalse(el(app, "squad-couldget").exists || el(app, "squad-couldget-toggle").exists, "Available has no Could get now list")
                if nextBestRows.count == 1 { shot("rocket-next-best") }
            }
            closePicker(app)
        }
        // The sample box has no usable counter for at least one of Giovanni's slots, so Next best must be offered, with one to three rows.
        XCTAssertFalse(nextBestRows.isEmpty, "a slot nothing usable beats lists Next best under Available")
        XCTAssertTrue(nextBestRows.allSatisfy { (1...3).contains($0) }, "up to three rows: \(nextBestRows)")
    }

    func testRocketScreenshots() throws {
        let setup = launch(reset: true)
        populate(setup)
        setup.terminate()
        screenSet("rocket") { app in
            let s = self.slot(app, "rocket", 2)
            if s.waitForExistence(timeout: 30) { self.reveal(app, s).tap() }
        }
    }
}
