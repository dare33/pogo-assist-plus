import XCTest

extension XCUIApplication {
    /// A finished scan shows the Scan screen's Done state first: its one button opens the review.
    func openReviewFromDone() {
        let open = buttons["scan-done-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 60), "the Done screen did not appear")
        open.tap()
    }
}

/// The Scan screen's Done state (what the person sees after a scan has ended): the sample scans stand in for a finished broadcast, and the DEBUG launch arguments
/// `-fake-ending` and `-fake-storage-count` set only the ending markers and the typed count the extension would have written. Screenshots go to POGO_SCREENS.
final class ScanDoneTests: XCTestCase {
    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["POGO_SCREENS"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let screenshot = XCUIScreen.main.screenshot()
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        // Also kept in the result bundle: the runner cannot always write to POGO_SCREENS.
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func runs() -> [(String, [String])] {
        [("light", ["-appearance", "light"]),
         ("dark", ["-appearance", "dark"]),
         ("large", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])]
    }

    /// Fresh install with an account, then Diagnostics > Load sample scan (or the partial-read one). Leaves the app on the Done screen.
    private func finishedScan(_ extra: [String] = [], partial: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"] + extra
        app.launch()
        let field = app.textFields["Trainer name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("Greg main")
        app.buttons["Create account"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 5))
        if partial {
            // The part-read Pokémon is only a question against a saved box: save the full sample first.
            loadSample(app, partial: false)
            app.openReviewFromDone()
            app.buttons["Save to box"].tap()
            XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 20))
        }
        loadSample(app, partial: partial)
        XCTAssertTrue(app.buttons["scan-done-open"].waitForExistence(timeout: 60), "the Done screen did not appear")
        sleep(1)   // the ring finishes turning
        return app
    }

    private func loadSample(_ app: XCUIApplication, partial: Bool) {
        app.buttons["More"].tap()
        let diagnostics = app.buttons["Diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        let load = app.buttons[partial ? "Load partial-read sample" : "Load sample scan"]
        if !load.waitForExistence(timeout: 8), diagnostics.exists { diagnostics.tap() }   // the menu can swallow the first tap
        // At a large text size the button is below the fold, and the lazy list has not made it yet.
        for _ in 0..<8 where !(load.exists && load.isHittable) { app.swipeUp() }
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        load.tap()
    }

    private func headline(_ app: XCUIApplication, _ text: String) {
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5), "the headline is not \"\(text)\"")
    }

    /// The sample scan was not ended by the end of the list, a pause or the person (its markers say nothing), so the headline says only that it finished.
    func testDoneAfterSampleScanAndTheButtonOpensTheReview() throws {
        for (name, args) in runs() {
            let app = finishedScan(args)
            headline(app, "Scan finished.")
            XCTAssertFalse(app.staticTexts["That's your whole box."].exists)
            XCTAssertTrue(app.staticTexts["Finished scanning? Say \"Go to sleep\" to turn Voice Control off."].exists)
            let ring = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '.* read in .*'")).firstMatch
            XCTAssertTrue(ring.exists, "the ring says what was read")
            let open = app.buttons["scan-done-open"]
            XCTAssertTrue(open.label.contains("quick question") || open.label == "Review and save", "the button names what needs doing: \(open.label)")
            XCTAssertFalse(app.buttons["Start scan"].exists, "no start button on the Done screen")
            shot("done-sample-\(name)")
            if name == "light" {
                open.tap()
                XCTAssertTrue(app.buttons["Save to box"].waitForExistence(timeout: 20) || app.buttons["review-save-locked"].waitForExistence(timeout: 5), "the review did not open")
                // The sample has no questions, so step 1 says so; it has rows to check, so step 2 keeps "Check N in the game".
                XCTAssertTrue(app.staticTexts["Successful scan"].exists)
                shot("review-sample-successful-scan")
                XCTAssertFalse(app.staticTexts["Finished scanning? Say \"Go to sleep\" to turn Voice Control off."].exists)
            }
            app.terminate()
        }
    }

    /// The part-read sample has one question; the button names it, and Back leaves a pill that returns to the Done screen.
    func testDoneWithQuestionsAndLeavingItAndComingBack() throws {
        for (name, args) in runs() {
            let app = finishedScan(args, partial: true)
            let open = app.buttons["scan-done-open"]
            XCTAssertTrue(open.label.hasPrefix("1 quick question"), "the button names the question: \(open.label)")
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'then save'")).firstMatch.exists)
            shot("done-questions-\(name)")
            if name == "light" {
                // Back: the scan is not lost; a pill over the Box screen says so and returns to the Done screen.
                app.navigationBars.buttons.element(boundBy: 0).tap()
                let pill = app.buttons["scan-done-pill"]
                XCTAssertTrue(pill.waitForExistence(timeout: 5), "no way back to the finished scan")
                XCTAssertTrue(pill.label.hasPrefix("Scan finished"))
                shot("done-pill-\(name)")
                pill.tap()
                XCTAssertTrue(app.buttons["scan-done-open"].waitForExistence(timeout: 5))
                // The tab bar's Scan button reaches it too.
                app.navigationBars.buttons.element(boundBy: 0).tap()
                XCTAssertTrue(pill.waitForExistence(timeout: 5))
                app.buttons["Scan"].tap()
                XCTAssertTrue(app.buttons["scan-done-open"].waitForExistence(timeout: 5))
                open.tap()
                XCTAssertTrue(app.buttons["Don't include"].waitForExistence(timeout: 20), "the review did not open")
                // Discard from the review: the scan is gone and the Scan screen closes with it.
                app.buttons["Discard"].tap()
                app.buttons["Discard scan"].tap()
                XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["scan-done-pill"].exists)
            }
            app.terminate()
        }
    }

    /// The three headlines, and the end of the list that is not a sound Full scan, from the ending markers alone.
    func testTheHeadlinesFollowTheEnding() throws {
        // At the end of the list with a count the scan can be checked against (the sample reads this many): the whole box.
        let whole = finishedScan(["-appearance", "light", "-fake-ending", "list-end", "-fake-storage-count", "\(Self.sampleCount)"])
        headline(whole, "That's your whole box.")
        shot("done-headline-whole-box")
        whole.terminate()
        // At the end of the list, but no count was typed, so it is not judged a sound Full scan: no claim about the whole box.
        let noCount = finishedScan(["-appearance", "light", "-fake-ending", "list-end"])
        headline(noCount, "Scan finished at the end of your list.")
        noCount.terminate()
        let pause = finishedScan(["-appearance", "light", "-fake-ending", "pause"])
        headline(pause, "Stopped after a long pause.")
        shot("done-headline-pause")
        pause.terminate()
        let person = finishedScan(["-appearance", "dark", "-fake-ending", "person"])
        let said = person.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You stopped at '")).firstMatch
        XCTAssertTrue(said.waitForExistence(timeout: 5), "the headline names where the person stopped")
        XCTAssertEqual(said.label, "You stopped at \(Self.sampleCount).")
        shot("done-headline-stopped-dark")
        person.terminate()
    }

    /// A scan that finished and waits must keep its own log: a second scan finishing in the meantime rewrites the shared one. Scan A (the sample) waits behind the pill,
    /// scan B (the partial-read sample) is installed as a newly finished broadcast, A is saved: A's stored log is A's (read again gives A's 51), and B is then offered.
    func testASecondFinishedScanDoesNotChangeTheWaitingOnesLog() throws {
        let app = finishedScan(["-appearance", "light"])
        XCTAssertTrue(app.staticTexts["Scan finished."].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let pill = app.buttons["scan-done-pill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        loadSample(app, partial: true)            // B replaces the shared log while A waits
        sleep(3)                                   // the timer has looked at it more than once
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "A is still the scan waiting")
        pill.tap()
        let ring = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '51 read in .*'")).firstMatch
        XCTAssertTrue(ring.waitForExistence(timeout: 10), "the Done screen still describes scan A")
        app.openReviewFromDone()
        let save = app.buttons["Save to box"]
        XCTAssertTrue(save.waitForExistence(timeout: 30), "A's review did not open")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '51 Pokémon read in'")).firstMatch.exists, "A's review has A's 51 Pokémon")
        save.tap()
        // B was not lost: it is offered once A is saved.
        let second = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '1 read in .*'")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 30), "B's Done screen was not offered")
        app.openReviewFromDone()
        let discard = app.buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 30), "B's review did not open")
        discard.tap()
        app.buttons["Discard scan"].tap()
        XCTAssertTrue(app.buttons["Scan"].waitForExistence(timeout: 10))
        // Read A again from Settings > Scans: it reads A's own log (51), not B's.
        app.buttons["More"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        if !app.navigationBars["Settings"].waitForExistence(timeout: 6), settings.exists { settings.tap() }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8), "Settings did not open")
        let actions = app.buttons["Scan actions"]
        for _ in 0..<6 where !(actions.exists && actions.isHittable) { app.swipeUp() }
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        let again = app.buttons["Read again with the latest rules"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        again.tap()
        let reread = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '51 Pokémon read in'")).firstMatch
        if !reread.waitForExistence(timeout: 20), again.exists { again.tap() }
        XCTAssertTrue(reread.waitForExistence(timeout: 60), "the saved scan was not read again as A's 51 Pokémon")
        app.terminate()
    }

    /// The red cross on the Done screen asks first; Cancel keeps the scan, Discard scan clears it, closes the Scan screen and leaves no pill; Scan then opens at its start view.
    func testDiscardFromTheDoneScreen() throws {
        for (name, args) in runs() {
            let app = finishedScan(args)
            let discard = app.buttons["scan-done-discard"]
            XCTAssertTrue(discard.exists, "no discard button on the Done screen")
            XCTAssertEqual(discard.label, "Discard scan")
            shot("done-discard-button-\(name)")
            guard name == "light" else { app.terminate(); continue }
            discard.tap()
            // The dialog's own button has the cross's label but no identifier.
            let confirm = app.buttons.matching(NSPredicate(format: "label == 'Discard scan' AND identifier == ''")).firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no question asked")
            sleep(1)
            shot("done-discard-dialog-\(name)")
            // Here iOS shows the dialog as a popover, which has no Cancel button: tapping outside it is Cancel.
            let cancel = app.buttons["Cancel"]
            if cancel.exists { cancel.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap() }
            XCTAssertTrue(app.buttons["scan-done-discard"].waitForExistence(timeout: 5) && !confirm.exists, "the dialog did not close")
            XCTAssertTrue(app.buttons["scan-done-open"].exists, "Cancel kept the Done screen")
            discard.tap()
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            confirm.tap()
            // The flow is idle, so the Scan screen closes with the scan (as after a discard from the review) and the tabs are back with no pill over them.
            XCTAssertTrue(app.buttons["Box"].waitForExistence(timeout: 10), "the Scan screen did not close")
            XCTAssertFalse(app.buttons["scan-done-open"].exists)
            XCTAssertFalse(app.buttons["scan-done-pill"].waitForExistence(timeout: 2), "a discarded scan left a pill")
            // Scan opens at its start view, not at a Done screen.
            app.buttons["Scan"].tap()
            XCTAssertTrue(app.buttons["Start scan"].waitForExistence(timeout: 10), "the Scan screen did not open at its start view")
            XCTAssertFalse(app.buttons["scan-done-open"].exists)
            shot("done-discard-after-\(name)")
            app.terminate()
        }
    }

    /// How many Pokémon the bundled sample scan reads.
    static let sampleCount = 51
}
