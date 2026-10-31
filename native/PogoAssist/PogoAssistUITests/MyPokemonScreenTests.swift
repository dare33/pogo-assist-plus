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
        // The letters are kept drawn by the launch argument (they fade a second after the list stops, which a UI test cannot beat). A is first, over the index element's frame.
        for letter in ["M", "T", "C"] {
            XCTAssertGreaterThan(jump.frame.height, 300, "the index is the height of its letters")
            letterSpot(app, letter).tap()
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

    /// What the DEBUG index says of itself (see `AZIndex.debugElement`): the number of letters, and one character per jump, "1" if the list was coasting at the jump.
    private func debugState(_ app: XCUIApplication) -> (letters: Int, wide: Bool, jumps: String) {
        let value = app.descendants(matching: .any)["az-debug"].value as? String ?? ""
        let parts = value.split(separator: " ").map { $0.split(separator: "=", omittingEmptySubsequences: false) }
        let letters = parts.first { $0.first == "letters" }.flatMap { $0.last }.flatMap { Int($0) } ?? 0
        let jumps = parts.first { $0.first == "jumps" }.flatMap { $0.count > 1 ? String($0[1]) : "" } ?? ""
        let wide = parts.first { $0.first == "wide" }.flatMap { $0.last } == "1"
        return (letters, wide, jumps)
    }

    /// The screen point over the letter `letter` of the index (A is first; the index has the letters of the big box, no "#"): `inset` points in from the strip's trailing
    /// edge, and `along` of the way down the letter's own row (0.5 is the middle).
    private func letterPoint(_ app: XCUIApplication, _ letter: String, inset: CGFloat = 11, along: CGFloat = 0.5) -> CGPoint {
        let frame = app.descendants(matching: .any)["az-jump"].frame
        let letters = debugState(app).letters
        XCTAssertGreaterThan(letters, 0, "the index says how many letters it has")
        let at = CGFloat(Int(letter.unicodeScalars.first!.value) - 65)
        return CGPoint(x: frame.maxX - inset, y: frame.minY + (at + along) * frame.height / CGFloat(max(letters, 1)))
    }

    private func letterSpot(_ app: XCUIApplication, _ letter: String, inset: CGFloat = 11, along: CGFloat = 0.5) -> XCUICoordinate {
        let p = letterPoint(app, letter, inset: inset, along: along), size = app.frame.size
        return app.coordinate(withNormalizedOffset: CGVector(dx: p.x / size.width, dy: p.y / size.height))
    }

    /// One touch record with two fingers: the first flings the list from `from` to `to` in `flingTime` seconds and lifts, the second presses `press` `pressAt` seconds
    /// after the record starts and lifts. XCTest's own swipe and tap each wait for the list to stop moving before they return, so a press cannot follow a fling
    /// while it is still coasting through them; this sends both in one record (XCTest's synthesized-event classes, reached by name; test-only). If this Xcode no longer
    /// has them the test fails with that said, instead of crashing.
    private func flingThenPress(from: CGPoint, to: CGPoint, flingTime: TimeInterval = 0.08, press: CGPoint, pressAt: TimeInterval) {
        guard let pathType = NSClassFromString("XCPointerEventPath") as? NSObject.Type, let recordType = NSClassFromString("XCSynthesizedEventRecord") as? NSObject.Type else {
            XCTFail("this Xcode's XCTest has no XCPointerEventPath or XCSynthesizedEventRecord: the fling-and-press helper has to be redone"); return
        }
        let needed: [(NSObject.Type, String)] = [(pathType, "initForTouchAtPoint:offset:"), (pathType, "moveToPoint:atOffset:"), (pathType, "liftUpAtOffset:"),
                                                 (recordType, "initWithName:interfaceOrientation:"), (recordType, "addPointerEventPath:"), (recordType, "synthesizeWithError:")]
        for (type, name) in needed where !type.instancesRespond(to: NSSelectorFromString(name)) {
            XCTFail("this Xcode's XCTest no longer has -[\(type) \(name)]: the fling-and-press helper has to be redone"); return
        }
        typealias InitTouch = @convention(c) (AnyObject, Selector, CGPoint, TimeInterval) -> AnyObject
        typealias AtPoint = @convention(c) (AnyObject, Selector, CGPoint, TimeInterval) -> Void
        typealias AtOffset = @convention(c) (AnyObject, Selector, TimeInterval) -> Void
        typealias InitRecord = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
        typealias Add = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        typealias Synthesize = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool
        func imp<T>(_ o: AnyObject, _ sel: String, as: T.Type) -> T { unsafeBitCast(o.method(for: NSSelectorFromString(sel)), to: T.self) }
        func touch(at point: CGPoint, offset: TimeInterval) -> AnyObject {
            let o = pathType.perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
            return imp(o, "initForTouchAtPoint:offset:", as: InitTouch.self)(o, NSSelectorFromString("initForTouchAtPoint:offset:"), point, offset)
        }
        let fling = touch(at: from, offset: 0)
        imp(fling, "moveToPoint:atOffset:", as: AtPoint.self)(fling, NSSelectorFromString("moveToPoint:atOffset:"), to, flingTime)
        imp(fling, "liftUpAtOffset:", as: AtOffset.self)(fling, NSSelectorFromString("liftUpAtOffset:"), flingTime)
        let tap = touch(at: press, offset: pressAt)   // a touch path starts pressed
        imp(tap, "liftUpAtOffset:", as: AtOffset.self)(tap, NSSelectorFromString("liftUpAtOffset:"), pressAt + 0.06)
        let record = recordType.perform(NSSelectorFromString("alloc"))!.takeUnretainedValue()
        let r = imp(record, "initWithName:interfaceOrientation:", as: InitRecord.self)(record, NSSelectorFromString("initWithName:interfaceOrientation:"), "fling and press", 1)
        imp(r, "addPointerEventPath:", as: Add.self)(r, NSSelectorFromString("addPointerEventPath:"), fling)
        imp(r, "addPointerEventPath:", as: Add.self)(r, NSSelectorFromString("addPointerEventPath:"), tap)
        var error: NSError?
        let ok = imp(r, "synthesizeWithError:", as: Synthesize.self)(r, NSSelectorFromString("synthesizeWithError:"), &error)
        XCTAssertTrue(ok, "the touch record was sent: \(String(describing: error))")
    }

    /// The section headings on the screen, top to bottom: single-letter labels at the leading edge (the index draws the same letters at the trailing edge).
    private func headers(_ app: XCUIApplication) -> [(letter: String, y: CGFloat)] {
        // One snapshot of the whole screen, so a row built or dropped by the list while it is read cannot make an element vanish halfway.
        guard let root = try? app.snapshot() else { return [] }
        var found = [(letter: String, y: CGFloat)]()
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .staticText, node.label.count == 1, node.label.range(of: "^[A-Z#]$", options: .regularExpression) != nil, node.frame.minX < app.frame.width / 3 {
                found.append((node.label, node.frame.minY))
            }
            node.children.forEach(walk)
        }
        walk(root)
        return found.sorted { $0.y < $1.y }
    }

    /// True when `letter`'s heading is the first section heading on the list and sits directly under the pinned header (the search field's bottom edge): measured 20 pt
    /// below it, allowed 0 to 32. Returns where it is, for the failure message.
    private func isAtTop(_ app: XCUIApplication, _ letter: String, listTop: CGFloat) -> (ok: Bool, seen: String) {
        let visible = headers(app).filter { $0.y >= listTop - 4 }
        guard let first = visible.first else { return (false, "no heading") }
        return (first.letter == letter && first.y <= listTop + 32, "first heading \(first.letter) at \(first.y - listTop) under the pinned header")
    }

    private func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { if condition() { return true }; usleep(100_000) }
        return condition()
    }

    /// Phone feedback 31 Oct, 3b: a letter pressed while the list is still coasting from a fling stops it and takes the list to that letter, as it does when the list is
    /// still. Every press goes against the fling's direction (or far past where it would stop), so the list ends wrong if the jump is lost. The index says, for every
    /// jump, whether the list was coasting when it was made: a round where it was not fails the test instead of counting as a pass. The heading of the letter must be the
    /// first on the list, directly under its top, and still there once any momentum would have run out.
    func testALetterPressedWhileTheListIsStillScrollingJumpsThere() throws {
        let app = bigBoxApp()
        let height = app.frame.height, x = app.frame.midX, listTop = app.textFields["box-search"].frame.maxY
        // The list starts in the middle (M), so a fling either way has a long way to go. That jump is the setup, not a round: nothing is coasting.
        letterSpot(app, "M").tap()
        XCTAssertTrue(waitUntil(15) { isAtTop(app, "M", listTop: listTop).ok }, "the setup jump to M")
        sleep(3)
        let setup = debugState(app).jumps.count
        for (round, (letter, up)) in [("D", true), ("X", false), ("E", true), ("X", false), ("D", true)].enumerated() {
            let spot = letterPoint(app, letter)   // worked out before the fling: reading the big list's frames afterwards takes longer than the fling lasts
            // 0.5 s after the fling is lifted the list is still coasting (a fling this fast coasts for about two seconds).
            flingThenPress(from: CGPoint(x: x, y: height * (up ? 0.75 : 0.3)), to: CGPoint(x: x, y: height * (up ? 0.3 : 0.75)), press: spot, pressAt: 0.5)
            XCTAssertTrue(waitUntil(8) { debugState(app).jumps.count == setup + round + 1 }, "round \(round + 1) (\(letter)): the index made a jump (jumps: \(debugState(app).jumps))")
            XCTAssertEqual(debugState(app).jumps.last, "1", "round \(round + 1) (\(letter)): the list was still coasting when the jump was made (jumps: \(debugState(app).jumps))")
            _ = waitUntil(8) { isAtTop(app, letter, listTop: listTop).ok }
            let first = isAtTop(app, letter, listTop: listTop)
            XCTAssertTrue(first.ok, "round \(round + 1): after a press on \(letter) during a fling, the \(letter) heading is the first on the list, at its top (\(first.seen))")
            sleep(2)
            let later = isAtTop(app, letter, listTop: listTop)
            XCTAssertTrue(later.ok, "round \(round + 1): and it stays there (\(later.seen))")
        }
    }

    /// A species row (not open) whose middle is behind the strip's height, as a press point for its chevron: the row's trailing edge less the card's 16 pt padding and
    /// half the chevron's width.
    private func rowBehindTheStrip(_ app: XCUIApplication) -> XCUIElement? {
        let strip = app.descendants(matching: .any)["az-jump"].frame
        return app.buttons.matching(identifier: "species-row").allElementsBoundByIndex.first {
            $0.exists && $0.label.hasSuffix("Opens in place") && $0.frame.midY > strip.minY + 20 && $0.frame.midY < min(strip.maxY - 20, app.frame.height * 0.7)
        }
    }

    /// Phone feedback 31 Oct, 3a (review): the index's wider touch area never takes a press meant for a row's chevron: with the letters shown, a tap on the chevron of a
    /// row behind the strip opens the species. At rest (the list's top part behind the strip) and after a jump (the list's top part gone).
    func testTheIndexDoesNotTakeAPressOnARowsChevron() throws {
        let app = bigBoxApp()
        let strip = app.descendants(matching: .any)["az-jump"].frame
        for stage in ["at rest", "after a jump"] {
            if stage == "after a jump" { letterSpot(app, "M").tap(); XCTAssertTrue(waitUntil(15) { isAtTop(app, "M", listTop: app.textFields["box-search"].frame.maxY).ok }); sleep(1) }
            let row = try XCTUnwrap(rowBehindTheStrip(app), "a closed species row is behind the strip \(stage)")
            let chevron = CGPoint(x: row.frame.maxX - 16 - 4, y: row.frame.midY)
            print("PAGE-BAND \(stage) (wide \(debugState(app).wide)): the strip's trailing edge \(strip.maxX), the row's trailing edge \(row.frame.maxX), the chevron's layout edge \(row.frame.maxX - 16), the band's leading edge \(strip.maxX - 32), gap \(strip.maxX - 32 - (row.frame.maxX - 16))")
            XCTAssertGreaterThanOrEqual(strip.maxX - 32 - (row.frame.maxX - 16), 4, "the band stops at least 4 pt short of the chevron")
            let title = row.label.components(separatedBy: ",").first ?? ""
            let size = app.frame.size
            app.coordinate(withNormalizedOffset: CGVector(dx: chevron.x / size.width, dy: chevron.y / size.height)).tap()
            let opened = app.buttons.matching(NSPredicate(format: "identifier == 'species-row' AND label BEGINSWITH %@ AND label ENDSWITH 'Open'", title)).firstMatch
            XCTAssertTrue(opened.waitForExistence(timeout: 5), "\(stage): a tap on \(title)'s chevron opened it, with the letters shown")
            opened.tap()   // closes it again, on its left part
        }
    }

    /// The same for the "i" button at the first accessibility text size, where the rows of chips and the sort line are tall and reach the strip: a tap on the right edge
    /// of the "i" opens the explainer.
    func testTheIndexDoesNotTakeAPressOnTheInfoButtonAtAX5() throws {
        let app = bigBoxApp(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let info = app.buttons["list-scoring-info"]
        let strip = app.descendants(matching: .any)["az-jump"].frame
        // At this size the sort line starts below the fold: the list is brought up until the "i" is level with the strip, where the index could take a press for it.
        var moves = 0
        while moves < 8, !(info.exists && info.isHittable && info.frame.midY > strip.minY && info.frame.midY < strip.maxY) {
            if info.exists, info.frame.midY < strip.minY { app.smallDrag(up: false) } else { app.nudgeUp() }
            moves += 1
        }
        XCTAssertTrue(info.exists && info.frame.midY > strip.minY && info.frame.midY < strip.maxY, "the i button is level with the strip (\(info.frame), strip \(strip))")
        print("PAGE-BAND AX5: the i button \(info.frame), the strip \(strip), wide \(debugState(app).wide)")
        XCTAssertFalse(debugState(app).wide, "the touch area is the drawn column while the list's top part is behind the strip")
        let size = app.frame.size
        app.coordinate(withNormalizedOffset: CGVector(dx: (info.frame.maxX - 2) / size.width, dy: info.frame.midY / size.height)).tap()
        XCTAssertTrue(waitUntil(5) { info.value as? String == "Expanded" }, "a tap on the right edge of the i button opens the explainer")
    }

    /// Phone feedback 31 Oct, 3a: each letter's touch area is bigger (it was 22 wide by 14 tall): measured by pressing, not by the VoiceOver element's frame. Once the
    /// list's top part is gone a press 30 pt in from the trailing edge (beyond the drawn 22 pt column) still jumps; a press 1 pt inside the top and 1 pt inside the bottom
    /// of a letter's 16 pt row jumps to that letter. The VoiceOver element stays the drawn column.
    func testEachLetterHasALargerTouchArea() throws {
        let app = bigBoxApp()
        let jump = app.descendants(matching: .any)["az-jump"], listTop = app.textFields["box-search"].frame.maxY
        let letters = debugState(app).letters
        let row = jump.frame.height / CGFloat(letters)
        print("A-Z letter row \(row) pt, strip \(jump.frame), the Scan button \(app.buttons["Scan"].frame)")
        XCTAssertGreaterThanOrEqual(row, 16, "each letter's row is 16 pt tall")
        XCTAssertEqual(jump.frame.width, 22, "the VoiceOver element is the drawn column")
        letterSpot(app, "M").tap()   // takes the list past its top part, so the touch area is at its widest
        XCTAssertTrue(waitUntil(15) { isAtTop(app, "M", listTop: listTop).ok }, "the first jump")
        sleep(1)
        for (letter, inset, along, what) in [("D", 11, 0.94, "1 pt inside the bottom of its row"), ("W", 30, 0.5, "30 pt in from the trailing edge"), ("T", 11, 0.06, "1 pt inside the top of its row")] as [(String, CGFloat, CGFloat, String)] {
            letterSpot(app, letter, inset: inset, along: along).tap()
            XCTAssertTrue(waitUntil(15) { isAtTop(app, letter, listTop: listTop).ok }, "a press \(what) jumps to \(letter) (\(isAtTop(app, letter, listTop: listTop).seen); index \(debugState(app)))")
        }
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
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("my-pokemon-index-\(tag)-\(mode)-\(size).png"))
            app.terminate()
        }
    }
}
