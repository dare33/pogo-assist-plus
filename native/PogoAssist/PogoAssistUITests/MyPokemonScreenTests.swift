import XCTest

extension XCUIApplication {
    /// A short upward drag (a quarter of the screen), so a row is brought up without being thrown past the top as a full swipe does.
    func nudgeUp() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
    }
    /// A small drag (a tenth of the screen) up or down, to place a caption just under the search field.
    func smallDrag(up: Bool) {
        let (a, b): (CGFloat, CGFloat) = up ? (0.65, 0.55) : (0.55, 0.65)
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: a)).press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: b)))
    }
    /// Moves the list's content by `fraction` of the screen's height (positive: down, so what is above comes into view), slowly and holding at the end so the list
    /// stops where the finger stopped. A fast drag throws it on past the mark, and a fixed step wider than the target band then swings it from one side to the other.
    func dragContent(by fraction: CGFloat) {
        let f = max(-0.3, min(0.3, fraction))
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55 - f / 2)).press(forDuration: 0.05, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55 + f / 2)),
                                                                                  withVelocity: .slow, thenHoldForDuration: 0.4)
    }
    /// Waits until the insight is built, which only it can show: under the Raids chip a species row carries its best copy's tag ("Top for Raids"). Puts the chip back on All.
    func awaitInsight() {
        XCTAssertTrue(buttons["chip-raids"].waitForExistence(timeout: 20))
        buttons["chip-raids"].tap()
        let tagged = buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label CONTAINS ' for Raids'")).firstMatch
        XCTAssertTrue(tagged.waitForExistence(timeout: 90), "the insight was not built: no species row carries its Raids tag")
        buttons["chip-all"].tap()
    }
    /// A species row opens in place on My Pokémon (design pass 3); "See all N copies" under it opens the species list.
    func openSpeciesList(_ row: XCUIElement) {
        // The floating tab bar covers the bottom of the screen: a row there is scrolled up first, or the tap lands on the bar.
        var n = 0
        while row.exists, (!row.isHittable || row.frame.midY > frame.height * 0.72), n < 8 { nudgeUp(); n += 1 }
        row.tap()
        let all = buttons["see-all"]
        // A tap during a screen transition can reach nothing: if it did not open and the row is still closed, tap it once more.
        if !all.waitForExistence(timeout: 3), row.exists, !row.label.hasSuffix("Open") { row.tap() }
        // The list is lazy: the button under a species opened near the bottom is not built until it is scrolled towards.
        n = 0
        while !all.waitForExistence(timeout: 3), n < 4 { nudgeUp(); n += 1 }
        if !all.exists { XCTContext.runActivity(named: "species did not open") { $0.add(XCTAttachment(screenshot: screenshot())) } }
        XCTAssertTrue(all.exists, "the species did not open in place")
        n = 0
        while !all.isHittable, n < 4 { nudgeUp(); n += 1 }   // under the tab bar's Scan button a tap would start a scan
        all.tap()
    }
}

/// The My Pokémon tab (design pass 3, Option A): species open in place with TOP PVP and TOP IVS, "See all", the A-Z index for VoiceOver, and the screenshots.
///
/// Accessibility identifiers of the new elements (stable): `tab-title` (the header's title), `species-row` (a species row: a button that opens or closes the species in
/// place; its label ends "Opens in place" or "Open"), `top-pvp-caption`, `top-ivs-caption`, `top-pvp-row`, `top-ivs-row` (copy rows, buttons), `top-pvp-waiting`
/// (the note while the advice is worked out), `see-all` ("See all N copies"), `az-jump` (the always-present "Jump to letter" element for VoiceOver).
/// The sample box's Moltres (6 copies) has two Ultra League cards under the cap and four other copies.
final class MyPokemonScreenTests: XCTestCase {
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

    /// Empties the search field (its clear button, when there is text in it).
    private func clearSearch(_ app: XCUIApplication) {
        if app.buttons["Clear search"].exists { app.buttons["Clear search"].tap() }
        app.textFields["box-search"].tap()
    }

    private func row(_ app: XCUIApplication, _ species: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH %@", "\(species),")).firstMatch
    }

    /// A populated box with Moltres on screen: the search builds its row (the list is lazy).
    private func launchOnMoltres() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light"]
        app.launch()
        populate(app)
        let search = app.textFields["box-search"]
        search.tap(); search.typeText("Moltres\n")
        XCTAssertTrue(row(app, "Moltres").waitForExistence(timeout: 10))
        return app
    }

    /// Opens Moltres in place and waits for the PvP picks (they come from the advice, which is worked out after a save).
    private func openMoltres(_ app: XCUIApplication) {
        row(app, "Moltres").tap()
        XCTAssertTrue(app.buttons["see-all"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["top-pvp-row"].firstMatch.waitForExistence(timeout: 60), "the PvP picks did not arrive")
    }

    func testTheTabAndTheScreenAreCalledMyPokemon() throws {
        let app = launchOnMoltres()
        XCTAssertTrue(app.buttons["My Pokémon"].exists, "the tab bar's label")
        // Both tabs keep their shared header in the tree (the Hub tab's says "Pogo Hub"): take this tab's, the one on screen.
        let titleEl = app.staticTexts.matching(identifier: "tab-title").matching(NSPredicate(format: "label == %@", "My Pokémon")).firstMatch
        XCTAssertTrue(titleEl.exists, "the screen's title is My Pokémon")
        let accountEl = app.buttons.matching(NSPredicate(format: "label == %@", "Account, Greg main")).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(accountEl, "the account name is in the header")
        XCTAssertTrue(app.buttons["Export"].exists && app.buttons["More"].firstMatch.exists)
        let title = titleEl.frame, account = accountEl?.frame ?? .zero
        XCTAssertLessThan(account.maxX, title.minX, "the account name is on the left of the title")
        XCTAssertEqual(title.midX, app.frame.midX, accuracy: 3, "the title is centred")
    }

    func testASpeciesOpensAndClosesInPlace() throws {
        let app = launchOnMoltres()
        let moltres = row(app, "Moltres")
        XCTAssertTrue(moltres.label.hasSuffix("Opens in place"), moltres.label)
        moltres.tap()
        XCTAssertTrue(app.buttons["see-all"].waitForExistence(timeout: 10), "it opens under its row")
        XCTAssertTrue(app.staticTexts["top-ivs-caption"].exists)
        XCTAssertTrue(row(app, "Moltres").label.hasSuffix("Open"), row(app, "Moltres").label)
        XCTAssertTrue(app.buttons["species-row"].exists || row(app, "Moltres").exists, "still on the list, not pushed")
        XCTAssertFalse(app.buttons["pokemon-row"].exists, "no species list was pushed")
        row(app, "Moltres").tap()
        XCTAssertTrue(app.buttons["see-all"].waitForNonExistence(timeout: 5), "another tap closes it")
        XCTAssertTrue(row(app, "Moltres").label.hasSuffix("Opens in place"))
    }

    func testTopPvPAndTopIVsRowsForASpecies() throws {
        let app = launchOnMoltres()
        openMoltres(app)
        XCTAssertTrue(app.staticTexts["top-pvp-caption"].exists)
        let pvp = app.buttons.matching(identifier: "top-pvp-row"), ivs = app.buttons.matching(identifier: "top-ivs-row")
        XCTAssertEqual(pvp.count, 2, "the two copies with the best Great or Ultra League card")
        XCTAssertEqual(ivs.count, 2, "the next two by IVs")
        for r in pvp.allElementsBoundByIndex {
            XCTAssertTrue(r.label.contains("Ultra League: Moltres"), r.label)
            XCTAssertTrue(r.label.contains("IV rank"), r.label)
        }
        for r in ivs.allElementsBoundByIndex { XCTAssertFalse(r.label.contains("League"), "no league pick on a TOP IVS row: " + r.label) }
        XCTAssertTrue(ivs.allElementsBoundByIndex.contains { $0.label.contains("Transfer · one of 6") || $0.label.contains("Keep") }, "a keep or transfer tag")
        // The copy rows are four different copies.
        XCTAssertEqual(Set((pvp.allElementsBoundByIndex + ivs.allElementsBoundByIndex).map(\.label)).count, 4)
    }

    func testATopPvPTapOpensThePageWithThatLeagueChosen() throws {
        let app = launchOnMoltres()
        openMoltres(app)
        app.buttons["top-pvp-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 10), "the Pokémon page opened")
        XCTAssertTrue(app.buttons["page-tab-pvp"].waitForExistence(timeout: 10) && app.buttons["page-tab-pvp"].isSelected, "the page opens on PvP")
        XCTAssertTrue(app.buttons["league-ul-pick"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["league-ul-pick"].isSelected, "with the row's league, Ultra League, chosen")
        XCTAssertFalse(app.buttons["league-gl-pick"].isSelected || app.buttons["league-ml-pick"].isSelected, "and no other league")
    }

    func testATopIVsTapOpensThePageOnSummary() throws {
        let app = launchOnMoltres()
        openMoltres(app)
        app.buttons["top-ivs-row"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Fix a value"].waitForExistence(timeout: 10), "the Pokémon page opened")
        XCTAssertTrue(app.buttons["page-tab-summary"].waitForExistence(timeout: 10) && app.buttons["page-tab-summary"].isSelected, "the page opens on Summary (rule 19)")
    }

    func testSeeAllOpensTheSpeciesList() throws {
        let app = launchOnMoltres()
        openMoltres(app)
        let all = app.buttons["see-all"]
        XCTAssertEqual(all.label, "See all 6 Moltres")
        all.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "pokemon-row").firstMatch.waitForExistence(timeout: 10), "the species list shows its copies")
        XCTAssertEqual(app.buttons.matching(identifier: "pokemon-row").count, 6)
        XCTAssertTrue(app.descendants(matching: .any)["species-best"].waitForExistence(timeout: 10), "lane B's YOUR BEST section is on the list")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'species-best-'")).allElementsBoundByIndex.isEmpty, "with at least one card")
    }

    /// A tap on a letter of the A-Z index takes the list to that letter, on Greg's big box (seeded from the fixture by the DEBUG launch argument).
    func testATapOnALetterTakesTheListThere() throws {
        let csv = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/greg-2026-10-22.box.csv").path
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", "light", "-uitest-today", "2026-10-25", "-uitest-seed-box", csv, "-uitest-az-always"]
        app.launch()
        let first = app.buttons.matching(identifier: "species-row").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 90), "the big box shows its species")
        XCTAssertTrue(first.label.hasPrefix("A") || first.label.hasPrefix("B"), "the list starts near the top")
        let jump = app.descendants(matching: .any)["az-jump"]
        XCTAssertTrue(jump.waitForExistence(timeout: 10))
        func visible(startingWith letter: String) -> Bool {
            app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH %@", letter)).allElementsBoundByIndex.contains { $0.exists && $0.isHittable }
        }
        // The letters are kept drawn by the launch argument (they fade a second after the list stops, which a UI test cannot beat). They are 16 pt each (the touch area's height), A first, over the index element's frame.
        for (letter, at) in [("M", 12), ("T", 19), ("C", 2)] {
            let frame = jump.frame, size = app.frame.size
            XCTAssertGreaterThan(frame.height, 300, "the index is the height of its letters")
            let letterSpot = app.coordinate(withNormalizedOffset: CGVector(dx: frame.midX / size.width, dy: (frame.minY + (CGFloat(at) + 0.5) * 16) / size.height))
            letterSpot.tap()
            expectation(for: NSPredicate(format: "count > 0"), evaluatedWith: app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH %@", letter)))
            waitForExpectations(timeout: 15)
            XCTAssertTrue(visible(startingWith: letter), "a row starting with \(letter) is on the screen after the tap on \(letter)")
            XCTAssertFalse(visible(startingWith: letter == "M" ? "A" : "Z"), "and the list is not where it was")
        }
    }

    private func bigBoxApp(mode: String = "light", extra: [String] = []) -> XCUIApplication {
        let csv = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/greg-2026-10-22.box.csv").path
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-appearance", mode, "-uitest-today", "2026-10-25", "-uitest-seed-box", csv, "-uitest-az-always"] + extra
        app.launch()
        XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 90), "the big box shows its species")
        XCTAssertTrue(app.descendants(matching: .any)["az-jump"].waitForExistence(timeout: 10))
        return app
    }

    /// The screen point of the letter at `at` (A is 0): the middle of its row, `inset` points in from the strip's trailing edge.
    private func letterPoint(_ app: XCUIApplication, at: Int, inset: CGFloat = 11) -> CGPoint {
        let frame = app.descendants(matching: .any)["az-jump"].frame
        return CGPoint(x: frame.maxX - inset, y: frame.minY + (CGFloat(at) + 0.5) * frame.height / CGFloat(26))   // 26 letters on the big box (no "#" section)
    }

    private func letterSpot(_ app: XCUIApplication, at: Int, inset: CGFloat = 11) -> XCUICoordinate {
        let p = letterPoint(app, at: at, inset: inset), size = app.frame.size
        return app.coordinate(withNormalizedOffset: CGVector(dx: p.x / size.width, dy: p.y / size.height))
    }

    /// One touch record with two fingers: the first flings the list from `from` to `to` in `flingTime` seconds and lifts, the second presses `press` `pressAt` seconds
    /// after the record starts and lifts. XCTest's own swipe and tap each wait for the list to stop moving before they return, so a press cannot follow a fling
    /// while it is still coasting through them; this sends both in one record (XCTest's synthesized-event classes, reached by name; test-only).
    private func flingThenPress(from: CGPoint, to: CGPoint, flingTime: TimeInterval = 0.08, press: CGPoint, pressAt: TimeInterval) throws {
        typealias InitTouch = @convention(c) (AnyObject, Selector, CGPoint, TimeInterval) -> AnyObject
        typealias AtPoint = @convention(c) (AnyObject, Selector, CGPoint, TimeInterval) -> Void
        typealias AtOffset = @convention(c) (AnyObject, Selector, TimeInterval) -> Void
        typealias InitRecord = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
        typealias Add = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        typealias Synthesize = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool
        func call<T>(_ o: AnyObject, _ sel: String, as: T.Type) -> T { unsafeBitCast(o.method(for: NSSelectorFromString(sel)), to: T.self) }
        let pathClass = try XCTUnwrap(NSClassFromString("XCPointerEventPath")), recordClass = try XCTUnwrap(NSClassFromString("XCSynthesizedEventRecord"))
        func touch(at point: CGPoint, offset: TimeInterval) -> AnyObject {
            let o = (pathClass as AnyObject).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
            let initSel = NSSelectorFromString("initForTouchAtPoint:offset:")
            return unsafeBitCast(o.method(for: initSel), to: InitTouch.self)(o, initSel, point, offset)
        }
        let fling = touch(at: from, offset: 0)
        call(fling, "moveToPoint:atOffset:", as: AtPoint.self)(fling, NSSelectorFromString("moveToPoint:atOffset:"), to, flingTime)
        call(fling, "liftUpAtOffset:", as: AtOffset.self)(fling, NSSelectorFromString("liftUpAtOffset:"), flingTime)
        let tap = touch(at: press, offset: pressAt)   // a touch path starts pressed
        call(tap, "liftUpAtOffset:", as: AtOffset.self)(tap, NSSelectorFromString("liftUpAtOffset:"), pressAt + 0.06)
        let record = (recordClass as AnyObject).perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
        let initRec = NSSelectorFromString("initWithName:interfaceOrientation:")
        let r = unsafeBitCast(record.method(for: initRec), to: InitRecord.self)(record, initRec, "fling and press", 1)
        let add = NSSelectorFromString("addPointerEventPath:")
        unsafeBitCast(r.method(for: add), to: Add.self)(r, add, fling)
        unsafeBitCast(r.method(for: add), to: Add.self)(r, add, tap)
        var error: NSError?
        let ok = unsafeBitCast(r.method(for: NSSelectorFromString("synthesizeWithError:")), to: Synthesize.self)(r, NSSelectorFromString("synthesizeWithError:"), &error)
        XCTAssertTrue(ok, "the touch record was sent: \(String(describing: error))")
    }

    /// The y of a section's heading ("T") if it is built and on the screen, else nil. Matched by label and by sitting at the leading edge, as the index draws the same
    /// letters at the trailing edge.
    private func headerY(_ app: XCUIApplication, _ letter: String) -> CGFloat? {
        app.staticTexts.matching(NSPredicate(format: "label == %@", letter)).allElementsBoundByIndex.first { $0.frame.minX < app.frame.width / 3 }?.frame.minY
    }

    /// Phone feedback 31 Oct, 3b: a letter pressed while the list is still coasting from a fling stops it and takes the list to that letter, as it does when the list is
    /// still. The section header of the letter must be at the top of the list, and still there once any momentum would have run out.
    func testALetterPressedWhileTheListIsStillScrollingJumpsThere() throws {
        let app = bigBoxApp()
        let height = app.frame.height, x = app.frame.midX
        for (letter, at, up) in [("T", 19, true), ("D", 3, false), ("W", 22, true), ("C", 2, false), ("S", 18, true)] {
            let spot = letterPoint(app, at: at)   // worked out before the fling: reading the big list's frames afterwards takes longer than the fling lasts
                        // 0.4 s after the fling is lifted the list is still coasting (a fling this fast coasts for about two seconds).
            try flingThenPress(from: CGPoint(x: x, y: height * (up ? 0.75 : 0.3)), to: CGPoint(x: x, y: height * (up ? 0.3 : 0.75)), press: spot, pressAt: 0.5)
            let top = height * 0.4
            func atTop() -> Bool { headerY(app, letter).map { $0 >= 0 && $0 < top } ?? false }
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline, !atTop() { usleep(100_000) }
            XCTAssertTrue(atTop(), "after a press on \(letter) during a fling, the \(letter) header is at the top of the list")
            sleep(2)
            XCTAssertTrue(atTop(), "and it stays there (header at \(headerY(app, letter) ?? -1) of \(height))")
        }
    }

    /// Phone feedback 31 Oct, 3a: each letter's touch area is at least 44 pt wide and 16 pt tall (it was 22 by 14), so the strip is easier to hit; the strip's look
    /// is the same. A press at the far leading edge of the touch area, outside the drawn letters, still selects the letter.
    func testEachLetterHasALargerTouchArea() throws {
        let app = bigBoxApp()
        let frame = app.descendants(matching: .any)["az-jump"].frame
        let perLetter = frame.height / 26
        print("A-Z hit area per letter: \(frame.width) x \(perLetter) pt")
        XCTAssertGreaterThanOrEqual(frame.width, 44, "the touch area is 44 pt wide")
        XCTAssertGreaterThanOrEqual(perLetter, 16, "and 16 pt tall per letter")
        letterSpot(app, at: 19, inset: frame.width - 3).tap()   // 3 pt in from the leading edge, well left of the drawn letter
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, headerY(app, "T") == nil { usleep(100_000) }
        sleep(1)
        XCTAssertLessThan(headerY(app, "T") ?? .infinity, app.frame.height * 0.4, "a press at the leading edge of the strip jumps to that letter")
    }

    func testTheJumpToLetterElementIsAlwaysThereForVoiceOver() throws {
        let app = launchOnMoltres()   // a search is active: one section (M)
        let jump = app.descendants(matching: .any)["az-jump"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5), "the element is there with a search on and one letter showing")
        XCTAssertEqual(jump.label, "Jump to letter")
        let search = app.textFields["box-search"]
        search.tap(); clearSearch(app); search.typeText("Zap\n")   // Zapdos: one letter
        XCTAssertTrue(row(app, "Zapdos").waitForExistence(timeout: 10))
        XCTAssertTrue(jump.exists, "and with another search")
        search.tap(); clearSearch(app); search.typeText("qqqq\n")   // nothing matches: no letters
        XCTAssertTrue(app.staticTexts["No Pokémon match."].waitForExistence(timeout: 10))
        XCTAssertTrue(jump.exists, "and with no Pokémon shown")
        XCTAssertEqual(jump.value as? String, "No letters")
        app.buttons["Clear search"].tap()
        XCTAssertTrue(row(app, "Blissey").waitForExistence(timeout: 10))
        XCTAssertTrue(jump.exists, "and with the whole box, while the letters are hidden")
        search.tap(); search.typeText("e\n")   // several letters
        XCTAssertTrue(jump.waitForExistence(timeout: 5))
    }

    /// The build mark on a species row and on a copy row, and what VoiceOver says for it: the same cost the mark shows. A TOP IVS copy with a build keeps its
    /// keep or transfer tag beside the mark (CONCEPTS rule 5).
    func testBuildMarksAndTheirSpokenCost() throws {
        let app = launchOnMoltres()
        XCTAssertTrue(row(app, "Moltres").label.contains("Upgrade available: 1 build to do, 137k dust"), row(app, "Moltres").label)
        openMoltres(app)
        let built = app.buttons.matching(NSPredicate(format: "identifier == 'top-ivs-row' AND label CONTAINS 'Upgrade available'")).firstMatch
        XCTAssertTrue(built.exists, "the copy with the build shows its mark")
        XCTAssertTrue(built.label.contains("Upgrade available: power up Moltres, 137k dust"), built.label)
        XCTAssertTrue(built.label.contains("Keep") || built.label.contains("Transfer"), "a TOP IVS copy with a build keeps its tag: " + built.label)
        let search = app.textFields["box-search"]
        search.tap(); clearSearch(app); search.typeText("Staraptor\n")
        XCTAssertTrue(row(app, "Staraptor").waitForExistence(timeout: 10))
        XCTAssertTrue(row(app, "Staraptor").label.contains("Full strength"), row(app, "Staraptor").label)
    }

    // MARK: the special-type words (phone feedback item 12)

    /// A keyword in the search lists only the species with a copy of that type: "legendary" keeps Moltres and leaves Blissey out; a name with a keyword narrows to both.
    func testTheSearchUnderstandsTheSpecialTypeWords() throws {
        let app = launchOnMoltres()
        let search = app.textFields["box-search"]
        search.tap(); clearSearch(app); search.typeText("legendary\n")
        XCTAssertTrue(row(app, "Moltres").waitForExistence(timeout: 10), "a legendary species is listed")
        XCTAssertFalse(row(app, "Blissey").exists, "a species that is not legendary is not")
        XCTAssertFalse(row(app, "Staraptor").exists)
        search.tap(); clearSearch(app); search.typeText("molt legendary\n")
        XCTAssertTrue(row(app, "Moltres").waitForExistence(timeout: 10), "a piece of a name and a word together")
        XCTAssertFalse(row(app, "Zapdos").exists, "the name part still narrows it")
        search.tap(); clearSearch(app); search.typeText("shadow & legendary\n")
        XCTAssertTrue(app.staticTexts["No Pokémon match."].waitForExistence(timeout: 10), "every word must match: the sample box has no Shadow legendary")
        search.tap(); clearSearch(app); search.typeText("Moltres\n")
        XCTAssertTrue(row(app, "Moltres").waitForExistence(timeout: 10), "a plain name still works")
    }

    private func shot(_ name: String) {
        var dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        dir = (dir as NSString).appendingPathComponent("fb-collection-r3")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    /// My Pokémon with a keyword in the search, for Greg's page: out/screens/fb-collection.
    func testKeywordSearchScreenshots() throws {
        launchOnMoltres().terminate()
        for (mode, size, category) in [("light", "default", "UICTContentSizeCategoryL"), ("dark", "default", "UICTContentSizeCategoryL"),
                                       ("light", "ax5", "UICTContentSizeCategoryAccessibilityXXXL"), ("dark", "ax5", "UICTContentSizeCategoryAccessibilityXXXL")] {
            let app = XCUIApplication()
            app.launchArguments = ["-appearance", mode, "-UIPreferredContentSizeCategoryName", category]
            app.launch()
            XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20))
            let search = app.textFields["box-search"]
            sleep(2)
            shot("my-pokemon-placeholder-\(mode)-\(size)")   // the empty search field with its hint
            search.tap(); search.typeText("legendary\n")
            XCTAssertTrue(row(app, "Moltres").waitForExistence(timeout: 10))
            sleep(2)
            shot("my-pokemon-keyword-legendary-\(mode)-\(size)")
            app.terminate()
        }
    }

    // MARK: screenshots (design process section 6)

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    /// My Pokémon closed and with Moltres open, light and dark, at the default text size and at AX5, saved as attachments named `my-pokemon-<state>-<mode>-<size>`.
    func testScreenshots() throws {
        launchOnMoltres().terminate()
        for (mode, size, category) in [("light", "default", "UICTContentSizeCategoryL"), ("dark", "default", "UICTContentSizeCategoryL"),
                                       ("light", "ax5", "UICTContentSizeCategoryAccessibilityXXXL"), ("dark", "ax5", "UICTContentSizeCategoryAccessibilityXXXL")] {
            let app = XCUIApplication()
            app.launchArguments = ["-appearance", mode, "-UIPreferredContentSizeCategoryName", category]
            app.launch()
            XCTAssertTrue(app.buttons.matching(identifier: "species-row").firstMatch.waitForExistence(timeout: 20))
            sleep(3)
            attach("my-pokemon-closed-\(mode)-\(size)")
            var n = 0
            while !(row(app, "Moltres").exists && row(app, "Moltres").isHittable) && n < 25 { app.swipeUp(); n += 1 }
            row(app, "Moltres").tap()
            XCTAssertTrue(app.buttons["top-pvp-row"].firstMatch.waitForExistence(timeout: 60))
            // Scrolled until the TOP PVP caption and its first row are on the screen, just under the search field (at AX5 the open species is taller than the screen).
            let caption = app.staticTexts["top-pvp-caption"], pvp = app.buttons["top-pvp-row"].firstMatch
            n = 0
            while !(caption.exists && caption.isHittable) && n < 10 { app.nudgeUp(); n += 1 }
            // Aimed at 0.32 of the screen's height, each drag as far as the caption still is from there; accepted anywhere in 0.28...0.36.
            var seen = [String]()
            n = 0
            while caption.exists && n < 8 {
                let y = caption.frame.minY / app.frame.height
                seen.append(String(format: "%.2f", y))
                if y >= 0.28 && y <= 0.36 { break }
                app.dragContent(by: 0.32 - y)
                n += 1
            }
            XCTAssertTrue(caption.isHittable && pvp.exists, "the TOP PVP caption and its first row are on the screen (\(mode) \(size); caption at \(seen.joined(separator: ", ")) of the screen's height, hittable \(caption.isHittable))")
            sleep(1)
            attach("my-pokemon-open-\(mode)-\(size)")
            app.terminate()
        }
    }

    /// My Pokémon with the A-Z index drawn (the launch argument keeps it up), light and dark, default text and AX5. Folder `page` under POGO_SCREENS; names carry
    /// POGO_SHOT_TAG (before or after).
    func testIndexScreenshots() throws {
        let tag = ProcessInfo.processInfo.environment["POGO_SHOT_TAG"] ?? "after"
        for (mode, size, category) in [("light", "default", "UICTContentSizeCategoryL"), ("dark", "default", "UICTContentSizeCategoryL"),
                                       ("light", "ax5", "UICTContentSizeCategoryAccessibilityXXXL"), ("dark", "ax5", "UICTContentSizeCategoryAccessibilityXXXL")] {
            let app = bigBoxApp(mode: mode, extra: ["-UIPreferredContentSizeCategoryName", category])
            sleep(3)
            var dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
            dir = (dir as NSString).appendingPathComponent("page")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("my-pokemon-index-\(tag)-\(mode)-\(size).png"))
            app.terminate()
        }
    }
}
