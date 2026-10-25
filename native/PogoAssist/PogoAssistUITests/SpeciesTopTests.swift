import XCTest

/// The species page's "YOUR BEST" section and the numbered place markers on its rows, driven with the sample scan. Expectations are read off the screen (the card's
/// figures against the row that is first for the use), so they do not depend on which sample Pokémon happen to be strongest.
final class SpeciesTopTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func rows(_ app: XCUIApplication) -> XCUIElementQuery { app.buttons.matching(identifier: "species-row") }
    private func copies(_ app: XCUIApplication) -> XCUIElementQuery { app.buttons.matching(identifier: "pokemon-row") }
    private func cards(_ app: XCUIApplication) -> [XCUIElement] {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'species-best-'")).allElementsBoundByIndex
    }
    private func card(_ app: XCUIApplication, _ activity: String) -> XCUIElement { app.descendants(matching: .any)["species-best-\(activity)"] }

    private func openSpecies(_ app: XCUIApplication, _ name: String) {
        let search = app.textFields["box-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.clearText(); search.typeText(name)
        let r = rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(r.waitForExistence(timeout: 5), "\(name) is in the sample box")
        r.tap()
    }

    private func launchPopulated(_ extra: [String] = ["-appearance", "light"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"] + extra
        app.launch()
        populate(app)
        XCTAssertTrue(rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", "Blissey,")).firstMatch.waitForExistence(timeout: 10))
        let ready = NSPredicate(format: "label CONTAINS 'Great League: Over cap'")
        expectation(for: ready, evaluatedWith: rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", "Blissey,")).firstMatch)
        waitForExpectations(timeout: 60)
        // Classic scoring, the order the sample expectations were written under.
        let control = app.descendants(matching: .any)["list-scoring"]
        if control.waitForExistence(timeout: 5), control.value as? String != "Classic" { control.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap() }
        return app
    }

    /// The "CP 1480" in a spoken label.
    private func cp(_ label: String) -> String? {
        label.range(of: "CP [0-9]+", options: .regularExpression).map { String(label[$0]) }
    }

    /// The section shows above the list, a card opens the copy that is first for its use, and that copy's row says so.
    func testTheSectionShowsAndACardOpensTheFirstCopy() throws {
        let app = launchPopulated()
        openSpecies(app, "Moltres")
        XCTAssertTrue(copies(app).firstMatch.waitForExistence(timeout: 5))
        let section = app.descendants(matching: .any)["species-best"]
        XCTAssertTrue(section.waitForExistence(timeout: 5), "Moltres has Top or Good copies")
        XCTAssertTrue(app.staticTexts["YOUR BEST"].exists)
        let raids = card(app, "raids")
        XCTAssertTrue(raids.exists)
        XCTAssertTrue(raids.label.hasPrefix("Raids, best: CP "), raids.label)
        XCTAssertTrue(raids.label.contains("Top") || raids.label.contains("Good"), raids.label)
        XCTAssertFalse(raids.label.contains("Weak"))
        // The cards run in chip order.
        let order = ["gl", "ul", "ml", "raids", "gym", "rocket", "max"]
        let shown = cards(app).map(\.identifier).map { String($0.dropFirst("species-best-".count)) }
        XCTAssertEqual(shown, order.filter(shown.contains), "chip order: \(shown)")
        // The row that is first for Raids has the card's CP.
        let first = copies(app).matching(NSPredicate(format: "label CONTAINS[c] %@", "number 1 for Raids")).firstMatch
        XCTAssertTrue(first.exists)
        XCTAssertEqual(cp(first.label), cp(raids.label), "card \(raids.label) vs row \(first.label)")
        sleep(1); shot("lane-b-section")
        // The copy the card opens is the one the row says is first: its CP and its IVs are on the page.
        let rowLabel = first.label, rowIVs = rowLabel.range(of: "[0-9]+/[0-9]+/[0-9]+", options: .regularExpression).map { String(rowLabel[$0]) }
        raids.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5), "the card opens the copy")
        let rowCP = try XCTUnwrap(cp(rowLabel)), page = app.staticTexts.matching(NSPredicate(format: "label == %@", rowCP)).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5), "the opened page shows \(rowCP), the place-1 row's CP (\(rowLabel))")
        if let rowIVs {
            let parts = rowIVs.split(separator: "/").map(String.init)
            for (bar, value) in zip(["Attack", "Defence", "HP"], parts) {
                let hit = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", "^\(bar)\\D+\(value)$")).firstMatch
                XCTAssertTrue(hit.exists, "and its IVs \(rowIVs): \(bar) \(value)")
            }
        } else {
            XCTAssertTrue(app.staticTexts["IVs not read"].exists, "a copy whose IVs the row does not show reads the same on its page")
        }
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(copies(app).firstMatch.waitForExistence(timeout: 5))
    }

    /// Markers sit on the rows, one per use, at most three places each, and a copy can wear several.
    func testRowsCarryTheirPlaces() throws {
        let app = launchPopulated()
        openSpecies(app, "Moltres")
        XCTAssertTrue(copies(app).firstMatch.waitForExistence(timeout: 5))
        let labels = copies(app).allElementsBoundByIndex.map(\.label)
        let placed = labels.filter { $0.localizedCaseInsensitiveContains("number ") }
        XCTAssertFalse(placed.isEmpty, "some copy is placed: " + labels.joined(separator: " | "))
        for l in placed { XCTAssertFalse(l.contains("number 4") || l.contains("Number 4"), l) }
        for use in ["Raids", "Gym", "Rocket", "Max"] {
            let count = labels.filter { $0.localizedCaseInsensitiveContains("number 1 for \(use)") }.count
            XCTAssertLessThanOrEqual(count, 1, "one first place for \(use)")
        }
        XCTAssertFalse(labels.contains { $0.contains("Best for") }, "the old best-for words are gone")
        XCTAssertFalse(app.buttons["pokemon-tag"].exists, "no per-copy rating tag without a chip")
    }

    /// The section does not move when a chip filters and orders the list below it: the same cards for the same copies, and each copy keeps its places, under the Raids chip
    /// for two species. (No sample species changes its row order under a chip, checked on 26 Oct 2026 for every one with two or more copies, under all seven chips: Lapras,
    /// Meowscarada, Moltres, Staraptor, Xerneas and Zamazenta (Hero) rate in the same order as their IVs. So "cards and places unchanged while the rows re-sort" rests on the
    /// unit tests: BoxTopTests, where `top` has no chip argument at all, and BoxInsightStoreTests for the order itself.)
    func testTheSectionIsTheSameUnderAChip() throws {
        let app = launchPopulated()
        // A chip keeps only the species that have a copy for it, so each chip is paired with a species that has one.
        for (name, chip) in [("Moltres", "chip-raids"), ("Charizard", "chip-raids")] {
            do {
                app.buttons["All"].tap()
                openSpecies(app, name)
                XCTAssertTrue(app.descendants(matching: .any)["species-best"].waitForExistence(timeout: 5), name)
                let before = cards(app).map { "\($0.identifier)=\($0.label)" }
                let rowsBefore = copies(app).allElementsBoundByIndex.map(\.label)
                app.buttons["Back"].tap()
                app.buttons[chip].tap()
                let row = rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 5), "\(name) is listed under \(chip)")
                row.tap()
                XCTAssertTrue(app.buttons["pokemon-tag"].firstMatch.waitForExistence(timeout: 10), "under the chip every copy has its tag")
                XCTAssertEqual(cards(app).map { "\($0.identifier)=\($0.label)" }, before, "\(name) under \(chip): the same cards with the same copies")
                XCTAssertEqual(Set(copies(app).allElementsBoundByIndex.map(\.label)), Set(rowsBefore), "\(name) under \(chip): each copy keeps its places")
                if name == "Moltres", chip == "chip-raids" { shot("lane-b-under-chip") }
                app.buttons["Back"].tap()
            }
        }
    }

    /// A species with no Top or Good copy has no section at all (not an empty one).
    func testNoSectionWhenNothingQualifies() throws {
        let app = launchPopulated()
        // Find a species in the sample box whose page has no card: try each in turn, as which species qualify is the sample's.
        let names = ["Blissey", "Pidgey", "Rattata", "Zubat", "Eevee", "Magikarp", "Weedle", "Caterpie", "Charizard", "Staraptor"]
        var found = false
        for name in names {
            let search = app.textFields["box-search"]
            guard search.waitForExistence(timeout: 5) else { break }
            search.tap(); search.clearText(); search.typeText(name)
            let r = rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            guard r.waitForExistence(timeout: 3) else { continue }
            r.tap()
            XCTAssertTrue(copies(app).firstMatch.waitForExistence(timeout: 5))
            sleep(1)
            let none = !app.descendants(matching: .any)["species-best"].exists
            if none {
                found = true
                XCTAssertFalse(app.staticTexts["YOUR BEST"].exists, "no caption either")
                XCTAssertTrue(app.staticTexts["species-order"].exists, "the page itself is intact")
                XCTAssertFalse(copies(app).allElementsBoundByIndex.contains { $0.label.localizedCaseInsensitiveContains("number ") }, "and no row carries a place")
                break
            }
            app.buttons["Back"].tap()
        }
        XCTAssertTrue(found, "some sample species has no Top or Good copy")
    }

    /// Select mode leaves the cards on show but inert: a tap on one opens nothing.
    func testSelectModeLeavesTheCardsInert() throws {
        let app = launchPopulated()
        openSpecies(app, "Moltres")
        let raids = card(app, "raids")
        XCTAssertTrue(raids.waitForExistence(timeout: 5))
        app.buttons["Select"].tap()
        XCTAssertTrue(raids.exists, "still on show")
        XCTAssertFalse(app.buttons["species-best-raids"].exists, "no longer a button")
        raids.tap()
        XCTAssertFalse(app.buttons["Fix a value"].exists, "a tap on a card opens nothing in Select mode")
        XCTAssertTrue(raids.label.hasSuffix("not available while selecting"), "VoiceOver is told the card is inert: \(raids.label)")
        XCTAssertTrue(app.buttons["Cancel"].exists, "still selecting")
        XCTAssertTrue(copies(app).firstMatch.exists)
        sleep(1); shot("lane-b-select")
    }

    /// At the default size two cards sit side by side, and a third goes under them (Zamazenta has three).
    func testAtTheDefaultSizeTheCardsAreTwoAcross() throws {
        let app = launchPopulated()
        openSpecies(app, "Zamazenta")
        XCTAssertTrue(app.descendants(matching: .any)["species-best"].waitForExistence(timeout: 10))
        let all = cards(app)
        XCTAssertGreaterThanOrEqual(all.count, 2, "Zamazenta has two or more cards in the sample")
        XCTAssertEqual(all[0].frame.minY, all[1].frame.minY, accuracy: 1, "the first two share a row")
        XCTAssertGreaterThanOrEqual(all[1].frame.minX, all[0].frame.maxX - 0.5, "side by side")
        XCTAssertLessThan(all[0].frame.width, app.frame.width * 0.7, "half a row each, not full width")
        if all.count > 2 { XCTAssertGreaterThanOrEqual(all[2].frame.minY, all[0].frame.maxY - 0.5, "the third is on the next row") }
    }

    /// At the largest accessibility size the cards are one column and nothing runs off the screen.
    func testAtAX5TheCardsAreOneColumnAndFit() throws {
        launchPopulated().terminate()
        let app = XCUIApplication()
        app.launchArguments = ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 20))
        openSpecies(app, "Zamazenta")
        XCTAssertTrue(app.descendants(matching: .any)["species-best"].waitForExistence(timeout: 10))
        let all = cards(app)
        XCTAssertGreaterThanOrEqual(all.count, 2, "Zamazenta has two or more cards in the sample, so the stacking is real")
        for c in all {
            XCTAssertGreaterThanOrEqual(c.frame.minX, -0.5, c.identifier)
            XCTAssertLessThanOrEqual(c.frame.maxX, app.frame.width + 0.5, "\(c.identifier) is not clipped on the right")
            XCTAssertGreaterThan(c.frame.width, app.frame.width * 0.7, "\(c.identifier) is a full-width card: one column")
        }
        for (a, b) in zip(all, all.dropFirst()) { XCTAssertLessThanOrEqual(a.frame.maxY, b.frame.minY + 0.5, "stacked, not side by side") }
        sleep(1); shot("lane-b-ax5")
    }

    /// Light and dark at the default size, for the screenshots.
    func testLightAndDarkScreens() throws {
        for mode in ["light", "dark"] {
            let app = launchPopulated(["-appearance", mode])
            openSpecies(app, "Zamazenta")
            XCTAssertTrue(app.descendants(matching: .any)["species-best"].waitForExistence(timeout: 10))
            sleep(1); shot("lane-b-\(mode)")
            app.terminate()
        }
    }

    // MARK: set-up

    private func populate(_ app: XCUIApplication) {
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        app.buttons["More"].tap()
        let diagnostics = app.buttons["Diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        let load = app.buttons["Load sample scan"]
        if !load.waitForExistence(timeout: 8), diagnostics.exists { diagnostics.tap() }
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        load.tap()
        app.openReviewFromDone()
        let save = app.buttons["Save to box"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "review did not appear")
        save.tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 15))
        XCTAssertTrue(rows(app).firstMatch.waitForExistence(timeout: 10), "the box shows no species")
    }
}

private extension XCUIElement {
    /// Empties a text field by deleting what it holds.
    func clearText() {
        guard let text = value as? String, !text.isEmpty else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }
}
