import XCTest

/// The UI v1 Review screens (DEBUG builds only: they use the `-uitest-seed-review` fixture, a small box and scanned rows run through the real merge).
/// Screenshots go to the folder in POGO_SCREENS: light, dark (`-appearance dark`) and one large Dynamic Type size. Not part of `swift test`.
final class ReviewScreensTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func launch(_ extra: [String], variant: String = "full") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-seed-review", variant] + extra
        app.launch()
        XCTAssertTrue(app.scrollViews["review-scroll"].waitForExistence(timeout: 90), "the seeded review did not appear")
        sleep(1)
        return app
    }

    private func scrollTop(_ app: XCUIApplication) { for _ in 0..<14 { app.swipeDown(velocity: .fast) } }

    /// Brings `e` on screen and clear of the bottom bar.
    @discardableResult
    private func reveal(_ app: XCUIApplication, _ e: XCUIElement, down: Bool = false) -> Bool {
        let h = app.windows.firstMatch.frame.height
        func clear() -> Bool { e.exists && e.isHittable && e.frame.maxY < h - 190 && e.frame.minY > 120 }
        for _ in 0..<14 { if clear() { return true }; if down { app.swipeDown() } else { app.swipeUp() } }
        for _ in 0..<14 { if clear() { return true }; if down { app.swipeUp() } else { app.swipeDown() } }
        return clear()
    }

    /// Scrolls `e` clear of both bars in small steps, then touches its centre. A full swipe can leave a control under the pinned bar (iOS 27 scrolls further than 26.5), where a tap
    /// answers nothing, and `XCUIElement.tap()` on it did not reach the app on iOS 27.
    private func tapClear(_ app: XCUIApplication, _ e: XCUIElement) {
        for _ in 0..<12 {
            let y = e.frame.minY, h = app.windows.firstMatch.frame.height
            if y > 220 && y < h - 260 { break }
            let up = y >= 220
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.6 : 0.4)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.45 : 0.55)))
        }
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func button(_ app: XCUIApplication, beginsWith s: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", s)).firstMatch
    }

    /// The open questions: the top of the result, every question kind, a part-read group answered one row, then in bulk, then folded, and one card answered.
    private func tourOpen(_ app: XCUIApplication, _ p: String, pages: Int, interactive: Bool = true) {
        shot("\(p)-01-result-top")
        XCTAssertTrue(app.buttons["review-save-locked"].exists, "Save is locked while questions are open")
        XCTAssertTrue(app.staticTexts["Scan finished at the end of your list"].exists)
        for i in 0..<pages { app.swipeUp(); shot("\(p)-02-questions-\(i)") }
        if pages < 7 || !interactive { return }

        // Few queries on purpose: each one walks the whole long page's accessibility tree, which is slow in a Debug build.
        scrollTop(app)
        // One row is answered "Don't include" by hand first: the bulk button must neither count it nor overwrite it.
        // The part-read group's own "Don't include" (by identifier: the query order of identical labels is not the order on screen on every iOS version).
        let left = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'part-leave-'")).firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 10))
        // "What saving does" now sits above the questions, so the first card is lower: scroll it clear of the bars before tapping.
        tapClear(app, left)
        sleep(1)
        shot("\(p)-03-part-mid-answer")
        app.swipeUp()
        let bulk = button(app, beginsWith: "Yes, all")
        XCTAssertTrue(bulk.waitForExistence(timeout: 10), "the bulk button is on screen")
        XCTAssertEqual(bulk.label, "Yes, all 2 are the saved ones", "the label counts only the rows still open")
        bulk.tap()
        sleep(1)
        shot("\(p)-04-part-bulk-ticking")
        sleep(2)
        shot("\(p)-05-part-folded")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '1 not included'")).firstMatch.waitForExistence(timeout: 5), "the answer given by hand was kept, not overwritten by the bulk answer")
        let evolved = app.buttons["Yes, it evolved"].firstMatch
        XCTAssertTrue(evolved.waitForExistence(timeout: 10))
        evolved.tap(); sleep(1); shot("\(p)-06-card-answered")
        XCTAssertTrue(app.buttons["review-save-locked"].exists, "still locked with questions open")
    }

    /// Every question answered (the fixture's `+answered` variant): Save unlocked, the lower sections, To check, the Find sheet and Not seen.
    private func tourAnswered(_ app: XCUIApplication, _ p: String) {
        XCTAssertTrue(app.buttons["review-save"].exists && app.buttons["review-save"].isEnabled, "every question answered unlocks Save to box")
        shot("\(p)-07-answered-top")
        for i in 0..<9 { app.swipeUp(); shot("\(p)-08-answered-\(i)") }
        let notes = button(app, beginsWith: "Notes, nothing to do")
        if reveal(app, notes) { notes.tap(); sleep(1); shot("\(p)-09-notes-open") }
        let details = button(app, beginsWith: "Scan details")
        if reveal(app, details) { details.tap(); sleep(1); app.swipeUp(); shot("\(p)-10-scan-details") }

        // To check, and the Find sheet.
        scrollTop(app)
        let step = app.buttons["review-step-check"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        step.tap()
        XCTAssertTrue(app.staticTexts["to look at in the game"].waitForExistence(timeout: 5))
        sleep(1)
        shot("\(p)-11-to-check")
        app.swipeUp(); shot("\(p)-11b-to-check-more")
        let row = button(app, beginsWith: "Zapdos")
        XCTAssertTrue(reveal(app, row))
        row.tap(); sleep(1)
        shot("\(p)-12-find-sheet")
        app.buttons["Close"].firstMatch.tap(); sleep(1)
        app.buttons["Back"].tap()
        XCTAssertTrue(app.scrollViews["review-scroll"].waitForExistence(timeout: 5))

        // Not seen.
        let notSeen = button(app, beginsWith: "Not seen in this scan")
        XCTAssertTrue(reveal(app, notSeen))
        notSeen.tap()
        XCTAssertTrue(app.staticTexts["Tap the ones you no longer have"].waitForExistence(timeout: 5))
        shot("\(p)-13-not-seen-list")
        let first = button(app, beginsWith: "Bulbasaur")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].exists, "Done, in the normal style, while none is marked")
        XCTAssertFalse(button(app, beginsWith: "Remove ").exists, "nothing marked: no Remove button")
        first.tap()
        sleep(1)
        XCTAssertTrue(button(app, beginsWith: "Remove 1 when you save").exists, "tapping one marks it for removal, and the main button says what it will do")
        XCTAssertFalse(app.buttons["Done"].exists, "no plain Done while one is marked")
        shot("\(p)-14-not-seen-list-marked")
        app.buttons["Grid"].tap(); sleep(1)
        shot("\(p)-15-not-seen-grid-marked")
        app.buttons["CP"].firstMatch.tap(); sleep(1)
        shot("\(p)-16-not-seen-grid-by-cp")
        button(app, beginsWith: "Remove 1 when you save").tap()
        XCTAssertTrue(app.scrollViews["review-scroll"].waitForExistence(timeout: 5))
    }

    /// The last whole number in an InsetRow's label ("New, 8"), after scrolling down the answered page (the open page is too heavy to scroll to its end in a Debug build).
    private func rowNumber(_ app: XCUIApplication, _ title: String) -> Int? {
        let e = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        guard e.exists else { return nil }
        return e.label.split(whereSeparator: { !$0.isNumber }).last.flatMap { Int($0) }
    }

    /// "What saving does" is the second segment, so its rows are on screen at the top of the result.
    private func savingTotal(_ app: XCUIApplication) -> (new: Int, updated: Int, same: Int) {
        (rowNumber(app, "New") ?? 0, rowNumber(app, "Updated") ?? 0, rowNumber(app, "Same") ?? 0)
    }

    /// The numbers in the pinned bar's label ("What saving does: 15 new, 3 updated, 11 same, 1 removed. 2 questions not answered yet").
    private func barNumbers(_ bar: XCUIElement) -> [String: Int] {
        var out = [String: Int]()
        let main = bar.label.components(separatedBy: ". ").first ?? bar.label
        for part in main.replacingOccurrences(of: "What saving does: ", with: "").components(separatedBy: ", ") {
            let w = part.split(separator: " ")
            if w.count == 2, let n = Int(w[0].filter { $0.isNumber }) { out[String(w[1])] = n }
        }
        return out
    }

    /// The segment sits second, straight under the blue header; once it has scrolled away a slim bar carries the same numbers, follows the answers and goes back on a tap.
    func testSavingBarPinsAndFollowsAnswers() throws { try savingBarTour(launch(["-appearance", "light"]), "savebar") }
    func testSavingBarDark() throws { try savingBarTour(launch(["-appearance", "dark"]), "savebar-dark") }
    func testSavingBarLargeText() throws {
        try savingBarTour(launch(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]), "savebar-large")
    }

    /// The Not seen page at a large text size: Done with none marked, then the red button with one marked.
    func testNotSeenLargeText() throws {
        let app = launch(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"], variant: "full+answered")
        let notSeen = button(app, beginsWith: "Not seen in this scan")
        XCTAssertTrue(reveal(app, notSeen))
        notSeen.tap()
        XCTAssertTrue(app.staticTexts["Tap the ones you no longer have"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].exists)
        shot("notseen-large-none")
        let first = button(app, beginsWith: "Bulbasaur")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        // At this text size the first row starts under the bottom bar: bring it clear of the bar before touching it.
        XCTAssertTrue(reveal(app, first))
        first.tap(); sleep(1)
        XCTAssertTrue(button(app, beginsWith: "Remove 1 when you save").exists)
        shot("notseen-large-one")
    }

    private func savingBarTour(_ app: XCUIApplication, _ p: String) throws {
        let header = app.staticTexts["Scan finished at the end of your list"]
        let heading = app.staticTexts["What saving does"]
        XCTAssertTrue(heading.exists && header.exists)
        XCTAssertLessThan(header.frame.minY, heading.frame.minY, "the segment comes after the blue header")
        XCTAssertLessThan(heading.frame.minY, app.windows.firstMatch.frame.height * 0.8, "and is the next thing on the screen")
        let full = savingTotal(app)
        XCTAssertFalse(app.buttons["review-saving-bar"].exists, "no slim bar while the full segment is in view")
        shot("\(p)-01-result-top")

        let bar = app.buttons["review-saving-bar"]
        for _ in 0..<4 where !bar.exists { app.swipeUp() }
        shot("\(p)-02-pinned")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "the slim bar is pinned once the segment has scrolled past")
        XCTAssertTrue(bar.label.hasPrefix("What saving does: "))
        XCTAssertTrue(bar.label.contains("questions not answered yet"), "the bar says how many questions are open")
        let before = barNumbers(bar)
        XCTAssertEqual(before["new"], full.new); XCTAssertEqual(before["updated"], full.updated); XCTAssertEqual(before["same"], full.same)
        shot("\(p)-02-pinned")

        let evolved = app.buttons["Yes, it evolved"].firstMatch
        for _ in 0..<3 where !(evolved.exists && evolved.isHittable) { app.swipeUp() }
        XCTAssertTrue(evolved.waitForExistence(timeout: 10))
        // At a large text size the button can sit half under the bottom bar, where a tap at its centre lands on the bar.
        tapClear(app, evolved)
        sleep(1)
        let after = barNumbers(bar)
        XCTAssertNotEqual(after, before, "answering a question changes a number in the slim bar")
        XCTAssertEqual(after.values.reduce(0, +), before.values.reduce(0, +) + 1, "the answer adds one Pokémon to New, Updated or Same")
        shot("\(p)-03-after-answer")

        // By coordinate: on iOS 27 `XCUIElement.tap()` on this bar does not reach it (the app never receives the tap), while a touch at the same centre point does what a thumb does.
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        shot("\(p)-04-after-bar-tap")
        XCTAssertFalse(bar.exists, "the bar steps aside once the full segment is back")
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(heading.isHittable, "a tap on the bar scrolls back to the full segment")
        let back = savingTotal(app)
        XCTAssertEqual(back.new + back.updated + back.same, after.values.reduce(0, +) - (after["removed"] ?? 0), "the full segment shows the same numbers")
    }

    /// "What saving does" follows the answers: with one question still open the panel says so, and with every one answered New, Updated, Same and Removed are what Save will write.
    func testSavingNumbersFollowAnswers() throws {
        let one = launch(["-appearance", "light"], variant: "full+leaveone")
        let a = savingTotal(one)
        XCTAssertTrue(one.staticTexts["1 question not answered yet. It is not counted above."].exists, "the open question is named under the numbers")
        XCTAssertTrue(one.buttons["review-save-locked"].exists)
        shot("saving-one-open")
        one.terminate()

        let all = launch(["-appearance", "light"], variant: "full+answered")
        let b = savingTotal(all)
        XCTAssertFalse(all.staticTexts.matching(NSPredicate(format: "label CONTAINS 'not answered yet'")).firstMatch.exists)
        XCTAssertGreaterThan(b.new, 0, "New is counted")
        XCTAssertGreaterThan(b.updated, 0, "evolved and powered-up answers are counted as Updated")
        XCTAssertGreaterThan(b.same, 6, "the six rows already in the box and the rows answered as the saved one are counted as Same")
        XCTAssertEqual(b.new + b.updated + b.same, a.new + a.updated + a.same + 1, "answering the last question adds one row to New, Updated or Same")
        let removed = all.staticTexts["Removed"]
        XCTAssertTrue(removed.exists, "the Mega pair answered Same Pokémon removes the Mega entry")
        shot("saving-answered")
    }

    func testOpenLight() throws { tourOpen(launch(["-appearance", "light"]), "light", pages: 7) }
    func testOpenDark() throws { tourOpen(launch(["-appearance", "dark"]), "dark", pages: 7, interactive: false) }
    func testAnsweredLight() throws { tourAnswered(launch(["-appearance", "light"], variant: "full+answered"), "light") }
    func testAnsweredDark() throws { tourAnswered(launch(["-appearance", "dark"], variant: "full+answered"), "dark") }
    func testLargeText() throws {
        let app = launch(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        tourOpen(app, "large", pages: 4)
    }
    func testLargeTextAnswered() throws {
        let app = launch(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"], variant: "full+answered")
        shot("large-answered-top")
        for i in 0..<3 { app.swipeUp(); shot("large-answered-\(i)") }
    }

    // MARK: Mega pair

    /// The Mega pair card says what joining does now (one entry with both forms), the answered row shows the two forms, and "What saving does" counts the join as one removed entry.
    private func megaPairTour(_ app: XCUIApplication, _ p: String) {
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'the box keeps one entry with both forms'")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "the Mega pair card's note")
        XCTAssertTrue(note.label.contains("The normal entry keeps its values and hand corrections, the Mega entry's values become its Mega form, and the separate Mega entry is removed."), note.label)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'with whatever was saved for it'")).firstMatch.exists, "the old sentence is gone")
        XCTAssertTrue(app.buttons["Same Pokémon"].exists && app.buttons["Different ones"].exists)
        let same = app.buttons["Same Pokémon"]
        app.swipeUp(); sleep(1)
        shot("\(p)-01-card")
        tapClear(app, same)
        sleep(1)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Same Pokémon · Normal · CP 2819 · Mega · CP 3970'")).firstMatch.waitForExistence(timeout: 5), "the answered row shows both forms")
        shot("\(p)-02-answered")
        for _ in 0..<4 where !app.staticTexts["Removed"].exists { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Removed"].exists, "a join still removes one entry from the list")
        XCTAssertTrue(app.staticTexts["Mega entries joined into their normal entry"].exists)
    }
    func testMegaPairLight() throws { megaPairTour(launch(["-appearance", "light"], variant: "megapair"), "mega-light") }
    func testMegaPairDark() throws { megaPairTour(launch(["-appearance", "dark"], variant: "megapair"), "mega-dark") }
    func testMegaPairLargeText() throws {
        megaPairTour(launch(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"], variant: "megapair"), "mega-large")
    }

    // MARK: trouble stretch

    /// The seeded scan has 40 rows whose CP was worked out, 6 cards that could not be read between them, then 20 clean rows: one stretch of 46 cards, 66 cards from its first to the end of the scan.
    private func stretchText(_ app: XCUIApplication) -> String {
        let t = app.staticTexts["review-stretch-0"]
        XCTAssertTrue(t.waitForExistence(timeout: 10), "the stretch panel is on the result")
        return t.label
    }

    func testStretchPanelWithoutACommandSet() throws {
        let app = launch(["-appearance", "light"], variant: "stretch")
        let text = stretchText(app)
        XCTAssertTrue(text.contains("The CP was covered for 46 in a row"), text)
        XCTAssertTrue(text.contains("Something probably covered the top of the screen, such as a banner or an alarm, from Smoliv (CP 131, worked out) to Rattata. 6 of them are not in this scan's list: their CP could not be read or worked out."), text)
        XCTAssertTrue(text.contains("To read them again: in Pokémon GO open Smoliv (it comes right after Snorlax CP 133) with the appraisal showing, then scan again from there (Add and update)."), text)
        XCTAssertFalse(text.contains("Pogo scan"), "no command set was made: no command is named")
        XCTAssertFalse(text.contains("could not be read at all") || text.contains("in between"), "no clean row sits inside this stretch")
        XCTAssertTrue(text.contains("Keep your storage sorted the same way as for that scan."), text)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == 'Copy search' AND value == 'smoliv&hp60'")).firstMatch.exists, "a search would change the list's order: no search strip in the panel")
        XCTAssertFalse(app.staticTexts["To find the first one in the game:"].exists)
        XCTAssertFalse(app.staticTexts["review-stretch-1"].exists, "one stretch, one panel")
        let heading = app.staticTexts["What saving does"], panel = app.staticTexts["review-stretch-0"]
        XCTAssertLessThan(heading.frame.minY, panel.frame.minY, "the panel is under What saving does")
        shot("stretch-light-01-top")
        app.swipeUp(); sleep(1)
        shot("stretch-light-01b-panel")
    }

    func testStretchPanelNamesTheSmallestCommandThatCovers() throws {
        let app = launch(["-appearance", "light"], variant: "stretch+commands")
        let text = stretchText(app)
        XCTAssertTrue(text.contains("choose Add and update, then say \"Wake up\" and \"Pogo scan 100\"."), text + " (66 cards to the end: 100 is the smallest size that covers them)")
        app.swipeUp(); sleep(1)
        shot("stretch-light-02-command")
        app.terminate()
        let hand = launch(["-appearance", "light"], variant: "stretch+commands+hand")
        let t2 = stretchText(hand)
        XCTAssertTrue(t2.contains("then scan again from there (Add and update)."), t2)
        XCTAssertFalse(t2.contains("Pogo scan"), "paging by hand: no command is named")
    }

    /// Clean rows inside the stretch: the title no longer says "in a row" and the body says how many had their CP read.
    func testStretchPanelWithCleanRowsInside() throws {
        let app = launch(["-appearance", "light"], variant: "stretchmixed")
        let text = stretchText(app)
        XCTAssertTrue(text.contains("The CP was covered for 43 cards, on and off"), text)
        XCTAssertFalse(text.contains("in a row"), text)
        XCTAssertTrue(text.contains("6 of them are not in this scan's list: their CP could not be read or worked out. 3 Pokémon in between had their CP read."), text)
    }

    /// An unread card sits between the row before the stretch and its first row: that card is where to open, the command counts from it, and it follows how THIS scan was paged
    /// (the seeded review's paging), not today's setting.
    func testStretchResumesAtTheUnreadCardBeforeTheFirstRow() throws {
        let hand = launch(["-appearance", "light"], variant: "stretchlead")
        let t = stretchText(hand)
        XCTAssertTrue(t.contains("in Pokémon GO open the Pokémon that comes right after Snorlax CP 133 (the scan could not read it) with the appraisal showing, then scan again from there (Add and update)."), t)
        XCTAssertFalse(t.contains("open Smoliv"), t)
        XCTAssertFalse(hand.staticTexts["To find the first one in the game:"].exists, "no search strip in the stretch panel")
        hand.terminate()
        let app = launch(["-appearance", "light"], variant: "stretchlead+commands")
        XCTAssertTrue(stretchText(app).contains("then say \"Wake up\" and \"Pogo scan 100\"."), "67 cards from the unread one to the end")
        app.terminate()
        // Today's setting is by hand, but this scan was paged by the command: the command is still named.
        let was = launch(["-appearance", "light"], variant: "stretch+commands+hand+scancmd")
        XCTAssertTrue(stretchText(was).contains("Pogo scan 100"))
    }

    func testStretchPanelDarkAndLarge() throws {
        let dark = launch(["-appearance", "dark"], variant: "stretch+commands")
        _ = stretchText(dark)
        dark.swipeUp(); sleep(1)
        shot("stretch-dark-01-top")
        dark.terminate()
        let large = launch(["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"], variant: "stretch+commands")
        _ = stretchText(large)
        large.swipeUp(); sleep(1)
        shot("stretch-large-01-panel")
        large.swipeUp()
        shot("stretch-large-02-below")
    }

    /// Guide me shows the same panel on its result screen.
    func testStretchPanelOnTheGuideResult() throws {
        let app = launch(["-appearance", "light", "-helpLevel", "guide"], variant: "stretch+commands")
        XCTAssertTrue(stretchText(app).contains("The CP was covered for 46 in a row"))
        shot("stretch-guide-01-top")
    }

    /// A scan with nothing to ask: Save to box is available at once.
    func testCleanScanIsUnlocked() throws {
        let app = launch(["-appearance", "light"], variant: "clean")
        XCTAssertTrue(app.buttons["review-save"].exists)
        shot("clean-01-top")
    }

    /// Add and update: no Not seen row, and no Mark all.
    func testAddAndUpdateScan() throws {
        let app = launch(["-appearance", "light"], variant: "partial+answered")
        XCTAssertTrue(app.staticTexts["Scan finished"].exists, "an Add and update scan the person has no end marker for says Scan finished")
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertFalse(button(app, beginsWith: "Not seen in this scan").exists)
        shot("partial-lower")
    }
}
