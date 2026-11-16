import XCTest

/// The Box and Pokémon detail screens of UI v1, driven with the sample scan: Box (with the Saved panel), search, a chip,
/// a species list, select mode with the game search built, detail and a detail with a check, in light and dark.
/// Screenshots go to the folder in POGO_SCREENS. Not part of `swift test`.
final class BoxScreensTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// A fresh account with the sample scan reviewed and saved; leaves the app on the Box.
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
        if !load.waitForExistence(timeout: 8), diagnostics.exists { diagnostics.tap() }   // the menu can swallow the first tap
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        load.tap()
        app.openReviewFromDone()
        let save = app.buttons["Save to box"]
        XCTAssertTrue(save.waitForExistence(timeout: 60), "review did not appear")
        save.tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 10), "the box shows no species")
    }

    /// The title a species row's label starts with ("Staraptor, 24 Pokémon, ...").
    private func speciesTitle(_ row: XCUIElement) -> String { row.label.components(separatedBy: ", ").first ?? row.label }

    private func screens(_ app: XCUIApplication, _ mode: String, saved: Bool) {
        let rows = app.buttons.matching(identifier: "species-row")
        sleep(1)
        shot("box-01-\(mode)-box")
        if saved { XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Saved to'")).firstMatch.exists, "the Saved panel is at the top of Box") }

        // Search by a piece of a name.
        let title = speciesTitle(rows.element(boundBy: 0))
        let search = app.textFields["box-search"]
        XCTAssertTrue(search.exists)
        search.tap(); search.typeText(String(title.lowercased().prefix(3)))
        sleep(1)
        shot("box-02-\(mode)-search")
        XCTAssertTrue(rows.firstMatch.exists)
        app.buttons["Clear search"].tap()

        // Search by CP range: every species row that is left has a top CP inside it or a Pokémon in it.
        search.tap(); search.typeText("cp1-99999")
        sleep(1)
        XCTAssertTrue(rows.firstMatch.exists, "a wide CP range matches")
        app.buttons["Clear search"].tap()
        search.typeText("zzzzqq")
        XCTAssertTrue(app.staticTexts["No Pokémon match."].waitForExistence(timeout: 3))
        app.buttons["Clear search"].tap()
        app.swipeDown()

        // A chip: To check, when the box has checks.
        let toCheck = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'To check'")).firstMatch
        if toCheck.exists { toCheck.tap(); sleep(1); shot("box-03-\(mode)-chip-to-check"); app.buttons["All"].tap() }

        // A species list, then select mode with the search built from the picked Pokémon.
        app.openSpeciesList(rows.element(boundBy: 0))
        let members = app.buttons.matching(identifier: "pokemon-row")
        XCTAssertTrue(members.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot("box-04-\(mode)-species")
        app.buttons["Select"].tap()
        members.element(boundBy: 0).tap()
        if members.count > 1 { members.element(boundBy: 1).tap() }
        let built = app.staticTexts.matching(NSPredicate(format: "value CONTAINS '&cp'")).firstMatch
        let builtAny = app.otherElements.matching(NSPredicate(format: "label == 'Search to paste into the game'")).firstMatch
        XCTAssertTrue(built.waitForExistence(timeout: 5) || builtAny.waitForExistence(timeout: 5), "select mode builds the game search")
        sleep(1)
        shot("box-05-\(mode)-select")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Copy search'")).firstMatch.tap()
        sleep(1)
        shot("box-05b-\(mode)-copied")
        app.buttons["Cancel"].tap()
        members.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
        sleep(1)
        shot("box-06-\(mode)-detail")
        app.swipeUp()
        shot("box-06b-\(mode)-detail-lower")
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()

        // A detail with a check.
        if toCheck.exists {
            toCheck.tap()
            app.openSpeciesList(rows.element(boundBy: 0))
            // The species list is pushed with the To check filter on; its rows appear after the push, so wait for them rather than tapping at once.
            XCTAssertTrue(members.firstMatch.waitForExistence(timeout: 10), "the species list under the To check chip shows its Pokémon")
            members.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["These values are right"].waitForExistence(timeout: 5), "a Pokémon with a check shows the button")
            sleep(1)
            shot("box-07-\(mode)-detail-check")
            app.buttons["Back"].tap()
            app.buttons["Back"].tap()
            app.buttons["All"].tap()
        }
    }

    func testBoxScreensLightThenDark() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        screens(app, "light", saved: true)
        app.terminate()

        // The box is kept: launch again without the reset, in dark.
        let dark = XCUIApplication()
        dark.launchArguments = ["-appearance", "dark"]
        dark.launch()
        XCTAssertTrue(dark.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 15))
        screens(dark, "dark", saved: false)
        dark.terminate()

        // Large text: rows grow and nothing is cut off.
        let large = XCUIApplication()
        large.launchArguments = ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        large.launch()
        XCTAssertTrue(large.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 15))
        sleep(1)
        shot("box-08-large-text-box")
        large.openSpeciesList(large.buttons.matching(identifier: "species-row").element(boundBy: 0))
        large.buttons.matching(identifier: "pokemon-row").firstMatch.tap()
        XCTAssertTrue(large.buttons["Fix a value"].waitForExistence(timeout: 5))
        sleep(1)
        shot("box-09-large-text-detail")
    }

    // MARK: Export

    /// Export asks which file: a CSV, or the Markdown one for Claude or ChatGPT. Each lands on the share sheet with its own file name (a `.csv` or a `.md`).
    func testExportOffersTwoFilesAndSharesEach() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        // The share sheet shortens the file name in its preview, so the app also says it whole in an element of its own.
        let sheetFile = { (ext: String) in app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'export-file' AND label BEGINSWITH 'pogo-box-' AND label ENDSWITH '.\(ext)'")).firstMatch }

        app.buttons["Export"].tap()
        XCTAssertTrue(app.buttons["CSV"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["For Claude or ChatGPT"].exists)
        sleep(1)
        shot("export-01-choice")
        app.buttons["For Claude or ChatGPT"].tap()
        XCTAssertTrue(sheetFile("md").waitForExistence(timeout: 30), "the share sheet offers a .md file")
        sleep(1)
        shot("export-02-share-markdown")
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["Export"].waitForExistence(timeout: 10))

        // Just after a share sheet is swiped away its popover layer can still be up for a moment and swallow the first tap on the header's button (the hierarchy then shows
        // My Pokémon with no dialog): tap again, as `openSpeciesList` does for a tap lost in a screen transition. Two taps that open nothing still fail.
        app.buttons["Export"].tap()
        if !app.buttons["CSV"].waitForExistence(timeout: 3) { app.buttons["Export"].tap() }
        XCTAssertTrue(app.buttons["CSV"].waitForExistence(timeout: 5))
        app.buttons["CSV"].tap()
        XCTAssertTrue(sheetFile("csv").waitForExistence(timeout: 30), "the share sheet offers a .csv file")
        shot("export-03-share-csv")
        app.swipeDown(velocity: .fast)

        // Select mode's export asks too, and the picked Pokémon go in the file.
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 10))
        app.openSpeciesList(app.buttons.matching(identifier: "species-row").element(boundBy: 0))
        XCTAssertTrue(app.buttons.matching(identifier: "pokemon-row").firstMatch.waitForExistence(timeout: 5))
        app.buttons["Select"].tap()
        app.buttons.matching(identifier: "pokemon-row").element(boundBy: 0).tap()
        app.buttons["Export"].tap()
        XCTAssertTrue(app.buttons["For Claude or ChatGPT"].waitForExistence(timeout: 5))
        app.buttons["For Claude or ChatGPT"].tap()
        XCTAssertTrue(sheetFile("md").waitForExistence(timeout: 30), "select mode shares a .md file too")
        shot("export-04-select-share-markdown")
    }

    // MARK: Re-scan N

    /// The line under the buttons says what the copied search shows, and its numbers add up: the total is the to-check Pokémon it covers plus the others with the same name and CP
    /// (or just the to-check ones when there are no others), and the covered plus the left-out ones are all N.
    @discardableResult private func checkSearchLine(_ app: XCUIApplication, toCheck n: Int) -> String {
        let line = app.staticTexts["check-search-line"]
        XCTAssertTrue(line.waitForExistence(timeout: 5), "a line under the buttons says what the search shows")
        let text = line.label
        func numbers(_ s: String) -> [Int] { s.split(whereSeparator: { !$0.isNumber && $0 != "," }).compactMap { Int($0.replacingOccurrences(of: ",", with: "")) } }
        let sentences = text.components(separatedBy: ". ")
        let nums = numbers(sentences[0])
        var covered = 0
        if text.hasPrefix("The search shows at least ") {
            XCTAssertEqual(nums.count, 3, text)
            XCTAssertEqual(nums[0], nums[1] + nums[2], text)
            XCTAssertGreaterThan(nums[2], 0, text)
            covered = nums[1]
        } else {
            XCTAssertTrue(text.hasPrefix("The search finds the "), text)
            covered = nums[0]
        }
        let left = sentences.dropFirst().flatMap { numbers($0) }.first ?? 0
        XCTAssertEqual(covered + left, n, "every Pokémon to check is in the search or left out of it: \(text)")
        return text
    }

    /// A box saved with checks and the command set made: the Saved panel offers "Re-scan N", the To check chip offers it too, and it lands on the Scan screen
    /// with Add and update and the smallest command covering what the search shows plus the margin (not N alone). The options say that size while the re-scan lasts; opening the
    /// options for editing, or leaving the screen, drops the suggestion and the remembered Add and update number (untouched by the re-scan) names the command again.
    func testRescanButtonLandsOnScanWithTheCommand() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-seed-review", "full+commands+answered", "-appearance", "light"]
        app.launch()
        let save = app.buttons["review-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 90), "the seeded review did not appear")
        save.tap()
        let button = app.buttons["rescan-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "the Saved panel offers Re-scan when the box has checks")
        let n = Int(button.label.replacingOccurrences(of: "Re-scan ", with: "")) ?? 0
        XCTAssertGreaterThan(n, 0, button.label)
        shot("rescan-01-saved-panel")
        let savedLine = checkSearchLine(app, toCheck: n)

        // With the chip on, the one button sits under the chips.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'To check'")).firstMatch.tap()
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "rescan-button").count, 1)
        // Beside it, one search for all of them: names, then their CPs or HPs.
        let copy = app.buttons["copy-check-search"]
        XCTAssertTrue(copy.exists, "Copy search sits beside Re-scan")
        XCTAssertTrue(copy.value as? String ?? "" != "", "the search is not empty: \(String(describing: copy.value))")
        XCTAssertTrue((copy.value as? String ?? "").contains("&"), "the search has names and terms")
        XCTAssertEqual(button.label, "Re-scan \(n)")
        XCTAssertEqual(checkSearchLine(app, toCheck: n), savedLine, "the same line under the buttons on the chip")
        sleep(1)
        shot("rescan-02-to-check-chip")

        let sizes = [25, 50, 100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 4000, 5000]
        // The command is sized from what the search shows (the to-check ones it covers plus the others it also matches), not from N alone.
        let shownNumbers = savedLine.split(whereSeparator: { !$0.isNumber && $0 != "," }).compactMap { Int($0.replacingOccurrences(of: ",", with: "")) }
        let shown = shownNumbers[0]   // "shows at least <total> ..." or "finds the <covered> ..."
        let command = "Pogo scan \(sizes.first { $0 >= shown + max(2, shown / 10) }!)"
        button.tap()
        XCTAssertTrue(app.navigationBars["Scan Pokémon"].waitForExistence(timeout: 5))
        // The Scan screen opens on the options (Add and update chosen, the number set); the re-scan line sits above them, not behind them.
        XCTAssertTrue(app.staticTexts["How many Pokémon to scan?"].waitForExistence(timeout: 5), "the options are the first view")
        XCTAssertTrue(app.buttons["Add and update"].isSelected, "the scan kind is Add and update")
        XCTAssertTrue(app.staticTexts["rescan-size"].exists, "the options say the re-scan's size, not a field holding another number")
        XCTAssertTrue(app.staticTexts["rescan-size"].label.hasPrefix("\(sizes.first { $0 >= shown + max(2, shown / 10) }!) for this re-scan"), app.staticTexts["rescan-size"].label)
        XCTAssertEqual(app.staticTexts["rescan-line-editing"].label, "Re-scan of \(n) to check: paste the search into the game's storage, open the first one's appraisal, then start.")
        sleep(1)
        shot("rescan-03-scan-screen-options")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Add and update"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["rescan-line"].exists)
        XCTAssertEqual(app.staticTexts["rescan-line"].label, "Re-scan of \(n) to check: paste the search into the game's storage, open the first one's appraisal, then start.")
        XCTAssertTrue(app.staticTexts["Back in the game, say \"\(command)\"."].exists, "the steps name \(command)")
        sleep(1)
        shot("rescan-03-scan-screen")

        // Scan Options drops the re-scan line and its command size: the remembered number (none here, so 200) names the command again, and the re-scan never wrote into it.
        app.buttons["Scan Options"].tap()
        XCTAssertTrue(app.staticTexts["How many Pokémon to scan?"].waitForExistence(timeout: 3) || app.textFields.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["rescan-line-editing"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Add and update"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["rescan-line"].exists)
        XCTAssertTrue(app.staticTexts["Back in the game, say \"Pogo scan 200\"."].exists)
    }

    /// Changing the scan kind, or closing the Scan screen, drops the suggestion; the screen opened later from the tab bar does not meet it.
    func testRescanSuggestionDoesNotSurviveALaterVisit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-seed-review", "full+commands+answered", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["review-save"].waitForExistence(timeout: 90))
        app.buttons["review-save"].tap()
        let button = app.buttons["rescan-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        XCTAssertTrue(app.staticTexts["rescan-line-editing"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        app.buttons["Scan"].tap()
        XCTAssertTrue(app.navigationBars["Scan Pokémon"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["rescan-line"].exists || app.staticTexts["rescan-line-editing"].exists, "a later visit does not carry the suggestion")
    }

    // MARK: Mega form

    /// The seeded Mega pair answered "Same Pokémon" and saved: the box holds one Blaziken with a Mega form. Leaves the app on the Box.
    private func saveMegaPair(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-seed-review", "megapair+answered"] + extra
        app.launch()
        let save = app.buttons["review-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 90), "the seeded review did not appear")
        save.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20), "the box shows no species")
        return app
    }

    /// True once the element can be tapped (it exists and is not covered or mid-transition).
    private func waitHittable(_ el: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: el)], timeout: timeout) == .completed
    }

    private func openBlaziken(_ app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Blaziken'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(waitHittable(row), "the Blaziken row is tappable"); app.openSpeciesList(row)
        let one = app.buttons.matching(identifier: "pokemon-row").firstMatch
        // A tap during a screen transition can reach nothing: if the list has not appeared and the species row is still there, tap it once more.
        if !one.waitForExistence(timeout: 3), row.exists { row.tap() }
        XCTAssertTrue(one.waitForExistence(timeout: 5)); one.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
        sleep(1)
    }

    private func searchValue(_ app: XCUIApplication) -> String? {
        let b = app.buttons.matching(NSPredicate(format: "label == 'Copy search'")).firstMatch
        return b.exists ? b.value as? String : nil
    }

    /// The sample scan's Moltres: the copy that carries the build shows the build and NO keep/transfer verdict (hygiene ignores builds); a spare says
    /// once that there is no build for it and gives one verdict that agrees; "How it was read" is one line that opens its read notes.
    func testSpareAndBuiltCopyAdvice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "dark"]
        app.launch()
        populate(app)
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Moltres'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); app.openSpeciesList(row)
        let copies = app.buttons.matching(identifier: "pokemon-row")
        XCTAssertTrue(copies.firstMatch.waitForExistence(timeout: 5))
        let n = copies.count
        XCTAssertGreaterThan(n, 1, "the sample has several Moltres")
        func scrollToVerdictArea() {
            var swipes = 0
            while !app.staticTexts["ADVICE"].isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
        }
        var sawSpare = false, sawBuilt = false
        for i in 0..<n where !(sawSpare && sawBuilt) {
            let c = app.buttons.matching(identifier: "pokemon-row").element(boundBy: i)
            guard c.waitForExistence(timeout: 3) else { break }
            c.tap()
            _ = app.staticTexts["ADVICE"].waitForExistence(timeout: 20)
            if app.buttons["advice-info"].exists, app.buttons["advice-info"].value as? String == "Collapsed" { app.buttons["advice-info"].tap() }
            if app.otherElements["advice-build-0"].exists || app.staticTexts["advice-build-0"].exists || app.descendants(matching: .any)["advice-build-0"].exists {
                sawBuilt = true
                XCTAssertFalse(app.staticTexts["advice-verdict"].exists, "a copy with its own build shows the build and no keep or transfer verdict")
                scrollToVerdictArea(); shot("with-builds")
                // The chip beside a league tag is the build's marker: "Advice builds it", or "... as <target>" in the card's spoken label when the target is another species.
                app.buttons["page-tab-pvp"].tap()
                for key in ["gl", "ul", "ml"] {
                    let label = app.buttons["league-\(key)-pick"].label
                    if label.contains("Advice builds") { XCTAssertTrue(label.contains("Advice builds it"), label) }
                }
            } else if app.staticTexts["advice-spare"].exists {
                sawSpare = true
                XCTAssertEqual(app.staticTexts["advice-spare"].label, "No build for this copy: you already have another Moltres planned.")
                let verdict = app.staticTexts["advice-verdict"].label
                XCTAssertTrue([
                    "One of 6 Moltres in your box. Keep it: it has one of your two best IV sets of the 6.",
                    "One of 6 Moltres in your box. Keep it: it is one of your two strongest of the 6.",
                    "One of 6 Moltres in your box. The advisor would transfer this one.",
                ].contains(verdict), verdict)
                scrollToVerdictArea(); shot("spare-advice")
                let notes = app.buttons["how-it-was-read"]
                if notes.exists {
                    XCTAssertEqual(notes.value as? String, "Collapsed")
                    notes.tap()
                    XCTAssertEqual(notes.value as? String, "Expanded")
                    shot("how-it-was-read-open")
                }
            }
            app.buttons["Back"].tap()
            _ = app.buttons.matching(identifier: "pokemon-row").firstMatch.waitForExistence(timeout: 5)
        }
        XCTAssertTrue(sawSpare, "one of the Moltres is a spare for a better copy")
        XCTAssertTrue(sawBuilt, "one of the Moltres carries the build")

        // The chip must appear somewhere, or the wording check above could never fail: in the 51-Pokémon sample the Zamazenta (Hero) with CP 2661 and
        // IVs 13/10/11 has an Advice build that covers Master League, so its Master League card carries "Advice builds it".
        app.buttons["Back"].tap()
        let search = app.textFields["box-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Zamazenta")
        let zam = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Zamazenta'")).firstMatch
        XCTAssertTrue(zam.waitForExistence(timeout: 5), "Zamazenta is in the sample box"); app.openSpeciesList(zam)
        let built = app.buttons.matching(NSPredicate(format: "identifier == 'pokemon-row' AND label CONTAINS '2661'")).firstMatch
        XCTAssertTrue(built.waitForExistence(timeout: 5), "the Zamazenta with CP 2661"); built.tap()
        _ = app.staticTexts["ADVICE"].waitForExistence(timeout: 20)
        app.buttons["page-tab-pvp"].tap()
        let ml = app.buttons["league-ml-pick"]
        XCTAssertTrue(ml.waitForExistence(timeout: 10), "the Master League card")
        XCTAssertTrue(ml.label.contains("Advice builds it"), ml.label)
    }

    /// A copy with a Mega form that is opened with a league's tile (a TOP PVP copy) opens its normal form on that tile, not the Mega form's "no leagues" note.
    func testAnInitialLeagueOnAMegaCopyOpensTheNormalFormOnThePvPTab() throws {
        // The Settings choice starts the page on Mega, so the test fails without the fix that opens the normal form for a league.
        let app = saveMegaPair(["-appearance", "light", "-uitest-initial-league", "ul", "-megaDefault", "mega"])
        openBlaziken(app)
        XCTAssertTrue(app.buttons["form-normal"].isSelected, "the normal form")
        XCTAssertTrue(app.buttons["page-tab-pvp"].isSelected)
        XCTAssertTrue(app.buttons["league-ul-pick"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["league-ul-pick"].isSelected)
        XCTAssertFalse(app.staticTexts["Mega Pokémon cannot battle in GO Battle League. Switch to Normal to see the leagues."].exists)
    }

    /// The PvP tab on the Normal form closes with its tiles when the page goes to the Mega form (no Leagues there), the Summary keeps its Advice on the Mega
    /// page, and Normal comes back to the tiles.
    func testMegaFormWithThePvPTabOpen() throws {
        let app = saveMegaPair(["-appearance", "light"])
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Blaziken'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); app.openSpeciesList(row)
        let one = app.buttons.matching(identifier: "pokemon-row")
        XCTAssertTrue(one.firstMatch.waitForExistence(timeout: 5)); one.firstMatch.tap()
        XCTAssertTrue(app.buttons["form-mega"].waitForExistence(timeout: 5))
        let advice = app.staticTexts["ADVICE"]
        XCTAssertTrue(advice.waitForExistence(timeout: 20), "the Summary has its Advice panel once the advice is ready")
        app.buttons["page-tab-pvp"].tap()
        XCTAssertTrue(app.buttons["league-ul-pick"].waitForExistence(timeout: 20), "Blaziken has league ratings once the advice is ready")
        XCTAssertFalse(advice.exists, "no Advice panel on the PvP tab")
        app.buttons["form-mega"].tap()
        XCTAssertTrue(app.staticTexts["CP 3970"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["league-ul-pick"].exists, "no Leagues on the Mega form")
        app.buttons["page-tab-summary"].tap()
        XCTAssertTrue(advice.waitForExistence(timeout: 3), "the Mega page keeps its Advice panel")
        app.buttons["form-normal"].tap()
        app.buttons["page-tab-pvp"].tap()
        XCTAssertTrue(app.buttons["league-ul-pick"].waitForExistence(timeout: 3), "Normal comes back to the tiles")
    }

    /// The detail's Normal / Mega switch, the row marker, the one-entry count and the Settings choice that sets where the switch starts.
    func testMegaFormSwitchRowMarkerCountAndSettings() throws {
        let app = saveMegaPair(["-appearance", "light"])
        sleep(1)
        let count = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '9' AND label CONTAINS '9 species'")).firstMatch
        XCTAssertTrue(count.exists, "one entry with both forms counts once: 6 + Blaziken + 2 new = 9")
        shot("mega-light-01-box")

        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Blaziken'")).firstMatch
        XCTAssertTrue(row.exists); app.openSpeciesList(row)
        let one = app.buttons.matching(identifier: "pokemon-row")
        XCTAssertTrue(one.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(one.count, 1, "the species list has one Blaziken")
        XCTAssertTrue(one.firstMatch.label.contains("CP 2819") && one.firstMatch.label.contains("has a Mega form"), one.firstMatch.label)
        XCTAssertTrue(app.staticTexts["Mega"].exists, "the row's Mega marker")
        shot("mega-light-02-species-row")
        one.firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
        sleep(1)

        // Normal first (the Settings choice is Normal): the entry's own values.
        XCTAssertTrue(app.staticTexts["CP 2819"].exists && app.staticTexts["Blaziken"].exists)
        XCTAssertTrue(app.buttons["form-normal"].isSelected && !app.buttons["form-mega"].isSelected)
        XCTAssertEqual(searchValue(app), "blaziken&cp2819")
        XCTAssertFalse(app.staticTexts["mega-search-note"].exists, "the caption is for the Mega side only")
        XCTAssertTrue(app.buttons["Fix a value"].isEnabled)
        shot("mega-light-03-detail-normal")

        app.buttons["form-mega"].tap()
        XCTAssertTrue(app.staticTexts["CP 3970"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Blaziken (Mega)"].exists && !app.staticTexts["CP 2819"].exists)
        XCTAssertEqual(searchValue(app), "blaziken&cp2819", "the game search stays the normal form's: the game shows the Mega CP only while it is Mega evolved")
        XCTAssertTrue(app.staticTexts["The game shows the Mega CP only while it is Mega evolved, so this search uses the normal CP."].exists)
        XCTAssertFalse(app.buttons["Fix a value"].isEnabled, "Fix a value changes the normal values only")
        shot("mega-light-04-detail-mega")
        app.swipeUp()
        shot("mega-light-05-detail-mega-lower")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "pokemon-row").firstMatch.waitForExistence(timeout: 5), "back to the species list before the second Back")
        app.buttons["Back"].tap()

        // Settings > Mega Pokémon sets where the switch starts.
        let more = app.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        XCTAssertTrue(waitHittable(more), "More is tappable")
        more.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        if !app.navigationBars["Settings"].waitForExistence(timeout: 6), settings.exists { settings.tap() }
        let pick = app.buttons["settings-mega"]
        XCTAssertTrue(pick.waitForExistence(timeout: 8), "Settings has a Mega Pokémon row")
        XCTAssertTrue(pick.label.hasPrefix("Mega Pokémon"), pick.label)
        shot("mega-light-06-settings")
        pick.tap()
        let mega = app.buttons["Mega"].firstMatch
        XCTAssertTrue(mega.waitForExistence(timeout: 5)); mega.tap()
        sleep(1)
        shot("mega-light-07-settings-mega")
        app.buttons["Done"].tap()
        // The sheet must be gone before the next tap: a tap during its dismissal reached nothing on iOS 27.
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 10))
        sleep(1)
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 5))
        openBlaziken(app)
        XCTAssertTrue(app.buttons["form-mega"].isSelected, "the page starts on Mega when Settings says so")
        XCTAssertTrue(app.staticTexts["CP 3970"].exists)
        app.buttons["form-normal"].tap()
        XCTAssertTrue(app.staticTexts["CP 2819"].waitForExistence(timeout: 3), "and the switch still moves to Normal")
    }

    func testMegaFormDark() throws {
        let app = saveMegaPair(["-appearance", "dark"])
        sleep(1)
        shot("mega-dark-01-box")
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Blaziken'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); app.openSpeciesList(row)
        XCTAssertTrue(app.buttons.matching(identifier: "pokemon-row").firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot("mega-dark-02-species-row")
        app.buttons.matching(identifier: "pokemon-row").firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5)); sleep(1)
        shot("mega-dark-03-detail-normal")
        app.buttons["form-mega"].tap(); sleep(1)
        shot("mega-dark-04-detail-mega")
    }

    func testMegaFormLargeText() throws {
        let app = saveMegaPair(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        sleep(1)
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH 'Blaziken'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); app.openSpeciesList(row)
        XCTAssertTrue(app.buttons.matching(identifier: "pokemon-row").firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot("mega-large-01-species-row")
        app.buttons.matching(identifier: "pokemon-row").firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5)); sleep(1)
        shot("mega-large-02-detail-normal")
        app.buttons["form-mega"].tap(); sleep(1)
        shot("mega-large-03-detail-mega")
    }

    /// The synthetic 15,000-entry box (DEBUG, `-box-synthetic`): the index timing is on screen and in the log, and the list scrolls and searches.
    func testBoxAt15000() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-box-synthetic", "-appearance", "light"]
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        let bench = app.otherElements["bench-result"].exists ? app.otherElements["bench-result"] : app.staticTexts["bench-result"]
        XCTAssertTrue(bench.waitForExistence(timeout: 30), "the index was not built")
        print("BENCH:", bench.label)
        XCTContext.runActivity(named: bench.label) { _ in }
        sleep(1)
        shot("box-10-15000")
        let start = Date()
        for _ in 0..<6 { app.swipeUp(velocity: .fast) }
        print("BENCH: six fast swipes took", Date().timeIntervalSince(start), "s")
        shot("box-10b-15000-scrolled")
        let search = app.textFields["box-search"]
        for _ in 0..<12 where !search.isHittable { app.swipeDown(velocity: .fast) }
        search.tap(); search.typeText("ra")
        let t = Date()
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 5))
        print("BENCH: typed search shown after", Date().timeIntervalSince(t), "s")
        shot("box-10c-15000-search")
    }

    // MARK: Leagues

    /// Opens the first Pokémon of the species whose row starts with `name` from the Box; leaves the app on its detail page.
    private func openLeagueDetail(_ app: XCUIApplication, species name: String) {
        let search = app.textFields["box-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText(name)
        let row = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH %@", "\(name),")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(name) is in the sample box")
        app.openSpeciesList(row)
        let member = app.buttons.matching(identifier: "pokemon-row").firstMatch
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        member.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
    }

    private func closeLeagueDetail(_ app: XCUIApplication) {
        app.buttons["Back"].tap()
        app.buttons["Back"].tap()
        let clear = app.buttons["Clear search"]
        if clear.waitForExistence(timeout: 3) { clear.tap() }
    }

    private func scrollToLeagues(_ app: XCUIApplication, _ element: XCUIElement) {
        var n = 0
        while !element.isHittable && n < 8 { app.swipeUp(); n += 1 }
    }

    /// The tiles the PvP tab must have for the sample scan's Scyther (CP 2071, 7/13/1, level 29): every family member is over the Great League cap (no viable
    /// option there), and Ultra League shows Scyther itself with a cost.
    private func assertScyther(_ app: XCUIApplication) {
        let pvp = app.buttons["page-tab-pvp"]
        XCTAssertTrue(pvp.waitForExistence(timeout: 20), "the page has its tabs")
        pvp.tap()
        let header = app.staticTexts["leagues-panel"]
        XCTAssertTrue(header.waitForExistence(timeout: 20), "the PvP tab shows once the advice is ready")
        XCTAssertEqual(header.label, "PVP LEAGUES")
        let gl = app.buttons["league-gl-pick"], ul = app.buttons["league-ul-pick"], ml = app.buttons["league-ml-pick"]
        for tile in [gl, ul, ml] { XCTAssertTrue(tile.exists, tile.identifier) }
        XCTAssertTrue(gl.label.hasPrefix("Great League, under 1,500 CP. Pick: "), gl.label)
        XCTAssertTrue(gl.label.contains("over cap. No viable option. This copy is already above 1,500 CP as every member of the family."), gl.label)
        XCTAssertTrue(ul.label.hasPrefix("Ultra League, under 2,500 CP. Pick: Scyther."), ul.label)
        XCTAssertTrue(ul.label.contains("This copy 96.2 percent, IV rank 1,766"), ul.label)
        XCTAssertTrue(ul.label.contains("Target level 40, target CP 2,500, 160,000 dust, 190 candy"), ul.label)
        XCTAssertTrue(ml.label.hasPrefix("Master League, no CP cap. Pick: "), ml.label)
        // The tag: Scyther's Ultra pick (71.8, below the B-tier line) is Weak, and the spoken tile says so; a No viable option tile has none.
        XCTAssertTrue(ul.label.contains("Pick: Scyther. Weak for Ultra League. Species 71.8"), ul.label)
        XCTAssertFalse(gl.label.contains("for Great League. Species"), "no tag on a No viable option tile")
        XCTAssertTrue(gl.isSelected, "the page opens on Great League's tile")
        XCTAssertEqual(app.descendants(matching: .any)["league-worth-line"].label, "This copy is already above 1,500 CP as every member of the family.")
        ul.tap()
        XCTAssertEqual(app.descendants(matching: .any)["league-worth-line"].label, "Species below the B-tier line for Ultra League")
        // The "i" holds the ranking switch and the Shadow note (a scan does not know the Shadow status).
        app.buttons["leagues-scoring-info"].tap()
        XCTAssertTrue(app.staticTexts["Pogo Assist is currently unable to detect Shadow Pokémon."].waitForExistence(timeout: 3))
        app.buttons["leagues-scoring-info"].tap()
        for _ in 0..<6 where !app.staticTexts["Removes this copy from the app's box only, not from the game."].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Removes this copy from the app's box only, not from the game."].exists)
    }

    /// Makes sure the ranking switch (a persisted preference, inside the PvP tab's "i") starts on Classic.
    private func resetRanking(_ app: XCUIApplication) {
        let control = app.descendants(matching: .any)["leagues-scoring"]
        if !control.exists { app.buttons["leagues-scoring-info"].tap() }
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        if control.value as? String != "Classic" { control.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap() }
        XCTAssertEqual(control.value as? String, "Classic")
    }

    /// The tiles, the worth line, then the family and details fold opens with its option table, and a row opens.
    func testTilesWorthLineAndTheFamilyFold() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openLeagueDetail(app, species: "Scyther")
        assertScyther(app)
        resetRanking(app)
        XCTAssertTrue(app.buttons["league-ul-pick"].label.contains("Pick: Scyther"))
        for key in ["gl", "ul", "ml"] { XCTAssertTrue(app.descendants(matching: .any)["league-\(key)-pick"].exists, key) }
        // The family is folded at first, and its row says how many more there are.
        let toggle = app.buttons["league-family-toggle"]
        XCTAssertTrue(toggle.exists)
        XCTAssertTrue(toggle.label.hasPrefix("Ultra League family and details ("), toggle.label)
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'league-ul-option-'")).firstMatch.exists)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Expanded")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'league-ul-option-' AND NOT identifier ENDSWITH '-detail'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "the other family members are listed")
        XCTAssertEqual(row.value as? String, "Collapsed")
        row.tap()
        XCTAssertEqual(row.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Best level' OR label BEGINSWITH 'IVs not read' OR label BEGINSWITH 'Already above'")).firstMatch.exists, "the expanded row says its best level")
        sleep(1)
        shot("league-family-row-open")
        toggle.tap()
        XCTAssertFalse(row.waitForExistence(timeout: 2), "the fold closes")
    }

    /// The ranking switch changes the pick, not only the chip: the sample Scyther's Ultra League pick is Scyther itself under Classic and
    /// Scizor under Pogo Assist (the engine's `pick` and `experimental` differ).
    func testRankingSwitchChangesThePick() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openLeagueDetail(app, species: "Scyther")
        XCTAssertTrue(app.buttons["page-tab-pvp"].waitForExistence(timeout: 20))
        app.buttons["page-tab-pvp"].tap()
        XCTAssertTrue(app.staticTexts["leagues-panel"].waitForExistence(timeout: 20))
        resetRanking(app)
        let ul = app.buttons["league-ul-pick"]
        XCTAssertTrue(ul.label.contains("Pick: Scyther."), ul.label)
        XCTAssertFalse(ul.label.contains("Pogo Assist pick"))
        let control = app.descendants(matching: .any)["leagues-scoring"]
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "Pogo Assist")
        XCTAssertTrue(ul.label.contains("Pogo Assist pick: Scizor."), ul.label)
        XCTAssertTrue(ul.label.contains("This copy 95.3 percent, IV rank 2,379"), ul.label)
        let explainer = app.descendants(matching: .any)["leagues-scoring-explainer"]
        XCTAssertTrue(explainer.exists, "the explainer is open under the header")
        XCTAssertTrue(explainer.label.contains("starts from the strongest species"), explainer.label)
        resetRanking(app)
        XCTAssertTrue(ul.label.contains("Pick: Scyther."))
        // The option rows carry the species id: under Classic the other Ultra League members are Scizor and Kleavor.
        ul.tap()
        app.buttons["league-family-toggle"].tap()
        let row = app.buttons["league-ul-option-scizor"]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "league-ul-option-<speciesId>")
        XCTAssertTrue(app.buttons["league-ul-option-kleavor"].exists)
        row.tap()
        XCTAssertEqual(row.value as? String, "Expanded")
    }

    /// The orange search circle in the header copies the game search and toasts.
    func testSearchCircleCopiesTheGameSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openLeagueDetail(app, species: "Scyther")
        let chip = app.buttons["search-chip"]
        XCTAssertTrue(chip.exists)
        XCTAssertEqual(chip.label, "Copy search")
        XCTAssertTrue((chip.value as? String ?? "").hasPrefix("scyther&cp2071"))
        chip.tap()
        XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 3))
    }

    /// The Leagues section, light and dark, then large text: the sample scan's Scyther with the exact sentences, and a screenshot of each with the section in view.
    func testLeaguesSectionLightDarkAndLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        openLeagueDetail(app, species: "Scyther")
        XCTAssertTrue(app.staticTexts["CP 2071"].exists)
        assertScyther(app)
        sleep(1)
        shot("league-detail-light")
        app.terminate()

        let dark = XCUIApplication()
        dark.launchArguments = ["-appearance", "dark"]
        dark.launch()
        XCTAssertTrue(dark.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 15))
        openLeagueDetail(dark, species: "Scyther")
        assertScyther(dark)
        sleep(1)
        shot("league-detail-dark")
        dark.terminate()

        let large = XCUIApplication()
        large.launchArguments = ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        large.launch()
        XCTAssertTrue(large.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 15))
        openLeagueDetail(large, species: "Scyther")
        assertScyther(large)
        sleep(1)
        shot("league-detail-large-text")
    }

    /// The tiles wait while the page shows the Mega form (no Mega in GO Battle League) and come back on Normal.
    func testLeaguesSectionIsHiddenOnTheMegaForm() throws {
        let app = saveMegaPair(["-appearance", "light"])
        openBlaziken(app)
        XCTAssertTrue(app.buttons["page-tab-pvp"].waitForExistence(timeout: 20))
        app.buttons["page-tab-pvp"].tap()
        XCTAssertTrue(app.buttons["league-ul-pick"].waitForExistence(timeout: 20), "the tiles show on the Normal form")
        app.buttons["form-mega"].tap()
        XCTAssertTrue(app.staticTexts["CP 3970"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["league-ul-pick"].exists, "no league tiles on the Mega form")
        XCTAssertFalse(app.staticTexts["leagues-panel"].exists)
        XCTAssertTrue(app.staticTexts["Mega Pokémon cannot battle in GO Battle League. Switch to Normal to see the leagues."].exists)
        app.buttons["form-normal"].tap()
        XCTAssertTrue(app.buttons["league-ul-pick"].waitForExistence(timeout: 3))
    }

    /// Settings > About says where the league data comes from.
    func testAboutCreditsPvPoke() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        app.buttons["More"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        if !app.navigationBars["Settings"].waitForExistence(timeout: 6), settings.exists { settings.tap() }
        let credit = app.staticTexts["League ratings and recommended moves come from PvPoke (pvpoke.com), used under its MIT licence."]
        var n = 0
        while !credit.exists && n < 10 { app.swipeUp(); n += 1 }
        XCTAssertTrue(credit.exists)
        shot("league-about")
    }

    /// The Dynamax mark on the details card: it starts Off, On sticks after leaving the page and coming back.
    func testDynamaxMarkOnThePokemonPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        let members = app.buttons.matching(identifier: "pokemon-row")
        func openFirstPokemon() {
            let species = app.buttons.matching(identifier: "species-row").firstMatch
            XCTAssertTrue(species.waitForExistence(timeout: 10)); app.openSpeciesList(species)
            XCTAssertTrue(members.firstMatch.waitForExistence(timeout: 5)); members.firstMatch.tap()
            XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
        }
        openFirstPokemon()
        var mark = app.buttons["mark-dynamax"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertEqual(mark.value as? String, "Off")
        mark.tap()
        expectation(for: NSPredicate(format: "value == 'On'"), evaluatedWith: mark)
        waitForExpectations(timeout: 10)
        shot("dynamax-mark-light")

        // Back to the list and reopen the same Pokémon (the first row again): the flag was saved with the box.
        app.buttons["Back"].tap()
        XCTAssertTrue(members.firstMatch.waitForExistence(timeout: 5))
        members.firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 5))
        mark = app.buttons["mark-dynamax"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertEqual(mark.value as? String, "On")
    }
}
