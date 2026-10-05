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
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
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
            XCTAssertTrue(app.staticTexts["Say \"Go to sleep\""].exists)
            let ring = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES '.* read in .*'")).firstMatch
            XCTAssertTrue(ring.exists, "the ring says what was read")
            let open = app.buttons["scan-done-open"]
            XCTAssertTrue(open.label.contains("quick question") || open.label == "Save", "the button names what needs doing: \(open.label)")
            XCTAssertFalse(app.buttons["Start scan"].exists, "no start button on the Done screen")
            shot("done-sample-\(name)")
            if name == "light" {
                open.tap()
                XCTAssertTrue(app.buttons["Save to box"].waitForExistence(timeout: 20) || app.buttons["review-save-locked"].waitForExistence(timeout: 5), "the review did not open")
                XCTAssertFalse(app.staticTexts["Say \"Go to sleep\""].exists)
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

    /// How many Pokémon the bundled sample scan reads.
    static let sampleCount = 51
}
