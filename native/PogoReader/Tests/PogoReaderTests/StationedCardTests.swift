import XCTest
import CoreGraphics
import ImageIO
@testable import PogoReader

/// Round 31: a Pokémon stationed away (a Power Spot; a gym defender is believed to look the same) has a card with no "CP n" at the
/// top and no HP bar or HP text. The reader used to find nothing at all on it (empty name, CP and HP, flag `no-cp-text`). It now
/// reads the name and the appraisal bars and flags the reading `stationed`, and nothing downstream treats it as a card yet.
final class StationedCardTests: XCTestCase {
    // MARK: - stand-ins

    /// Answers the name crop first and the "At" line second, the order `completeStationed` reads them in.
    final class StationText: TextReader {
        var name: String, line: String
        var reads = [TextKind]()
        init(name: String = "Zapdos", line: String = "At N&R Superette") { self.name = name; self.line = line }
        func read(_ image: RGBAImage, kind: TextKind) -> TextRead {
            reads.append(kind)
            return line(reads.count == 1 ? name : self.line, 92)
        }
        private func line(_ t: String, _ c: Double) -> TextRead { PogoReaderTests.line(t, c) }
    }

    /// A drawn stationed card: dark header, white card, a teal RECALL pill (with its white text) 34% wide and 4.9% tall, centred,
    /// at 50.5% of the height, and nothing else in the middle of the card. No CP text, no HP bar.
    private func stationedScreen(w: Int = 750, h: Int = 1630, button: Bool = true, buttonX: Double = 0.329, buttonW: Double = 0.342, buttonH: Double = 0.049,
                                 buttonY: Double = 0.505, hpBar: Bool = false, text: Bool = true) -> RGBAImage {
        var img = RGBAImage(width: w, height: h)
        let W = Double(w), H = Double(h)
        img.fill(Rect(x: 0, y: 0, w: W, h: H), (60, 80, 100))
        img.fill(Rect(x: 0, y: 0.35 * H, w: W, h: 0.65 * H), (215, 228, 238))
        if button {
            img.fill(Rect(x: buttonX * W, y: buttonY * H, w: buttonW * W, h: buttonH * H), (105, 175, 150))
            if text { img.fill(Rect(x: (buttonX + buttonW / 2 - 0.08) * W, y: (buttonY + 0.28 * buttonH) * H, w: 0.16 * W, h: 0.4 * buttonH * H), (230, 240, 240)) }   // "RECALL", mid-button
        }
        if hpBar { img.fill(Rect(x: 0.26 * W, y: 0.45 * H, w: 0.48 * W, h: 0.006 * H), (102, 231, 170)) }
        return img
    }

    private func read(_ img: RGBAImage, _ text: TextReader) -> FrameReading {
        FrameReader(text: text, names: names).read(img, frame: "f", time: 0)
    }

    // MARK: - the three-part rule (synthetic card, stand-in text)

    func testAStationedCardNeedsTheButtonTheNameAndTheAtLine() {
        let r = read(stationedScreen(), StationText())
        XCTAssertEqual(r.name, "Zapdos")
        XCTAssertEqual(r.speciesIds, ["zapdos"])
        XCTAssertTrue(r.isStationed)
        XCTAssertNil(r.cp); XCTAssertNil(r.hp)
        XCTAssertEqual(r.cpText, ""); XCTAssertEqual(r.hpText, "")
        XCTAssertEqual(r.flags, ["stationed", "no-bars"], "no bars were drawn")
    }

    func testWithoutTheButtonTheCardIsTheOldBlankFrame() {
        let text = StationText()
        let r = read(stationedScreen(button: false), text)
        XCTAssertEqual(r.flags, ["no-cp-text"]); XCTAssertNil(r.name); XCTAssertEqual(r.nameText, "")
        XCTAssertEqual(text.reads, [], "no text is read when the pixel test fails: the extra cost is only paid on a candidate")
    }

    func testAButtonShapedBandThatIsTooTallTooNarrowOrOffCentreIsNotTheButton() {
        for (label, img) in [("too tall", stationedScreen(buttonH: 0.09)), ("too narrow", stationedScreen(buttonX: 0.40, buttonW: 0.20)),
                             ("too wide", stationedScreen(buttonX: 0.2, buttonW: 0.6)), ("off centre", stationedScreen(buttonX: 0.50, buttonW: 0.342, text: false)),
                             ("a thin bar", stationedScreen(buttonH: 0.01)), ("too high", stationedScreen(buttonY: 0.30)),
                             ("too low", stationedScreen(buttonY: 0.70))] {
            XCTAssertNil(findRecallButton(img, contentRect(img)), label)
            XCTAssertFalse(read(img, StationText()).isStationed, label)   // a thin or narrow band is read as the HP bar it may be, as before
        }
        XCTAssertNotNil(findRecallButton(stationedScreen(), contentRect(stationedScreen())))
    }

    /// The name alone is what any card in mid-transition shows, so a stationed card without its "At" line is not one: it is a
    /// frame with no CP text, as before.
    func testAnyOtherSecondLineIsNotAStationedCard() {
        for lineText in ["", "Attack", "Atlas Park", "Level 12", "CALL", "Stats"] {
            let r = read(stationedScreen(), StationText(line: lineText))
            XCTAssertEqual(r.flags, ["no-cp-text"], "line '\(lineText)'")
            XCTAssertNil(r.name, "line '\(lineText)'")
            XCTAssertEqual(r.nameText, "", "an unconfirmed candidate keeps nothing it read")
        }
    }

    func testAnUnmatchedNameIsNotAStationedCard() {
        for nameText in ["", "Zxqwv", "Settings", "SHOP"] {
            let r = read(stationedScreen(), StationText(name: nameText))
            XCTAssertEqual(r.flags, ["no-cp-text"], "name '\(nameText)'")
            XCTAssertNil(r.name); XCTAssertEqual(r.nameText, "")
        }
    }

    func testTheWordAtIsRecognisedWithOrWithoutAPlace() {
        for t in ["At N&R Superette", "At Vival", "At", "at the park", " At  X ", "AT Market"] { XCTAssertTrue(stationLineBegins(t), t) }
        for t in ["", "A", "Attack", "Atlas", "Athens Park", "Bat", "Level 12", "x At y"] { XCTAssertFalse(stationLineBegins(t), t) }
    }

    /// A card with a CP or an HP bar is a normal card: the stationed look is never tried.
    func testANormalCardNeverTriesTheStationedLook() {
        let text = StationText()
        var img = cardScreen(w: 750, h: 1630)
        let rect = contentRect(img)
        // a teal pill at the button's place does not turn a card with an HP bar into a stationed one
        img.fill(Rect(x: 0.329 * 750, y: 0.505 * 1630, w: 0.342 * 750, h: 0.049 * 1630), (105, 175, 150))
        let r = FrameReader(text: FakeText(), names: names).read(img, frame: "f", time: 0)
        XCTAssertFalse(r.isStationed)
        XCTAssertEqual(r.cp, 1234); XCTAssertEqual(r.hp, HP(current: 129, max: 129))
        XCTAssertEqual(text.reads, [])
        _ = rect
        // CP text present, HP bar absent (the CP-only path): not a stationed candidate either
        var cpOnly = stationedScreen()
        for i in 0..<4 { cpOnly.fill(Rect(x: 0.42 * 750 + Double(i) * 0.045 * 750, y: 0.06 * 1630, w: 0.02 * 750, h: Double(jsRound(0.025 * 1630))), (255, 255, 255)) }
        let (a, _) = FrameReader(text: StationText(), names: names).analyse(cpOnly)
        XCTAssertNil(a.stationed); XCTAssertTrue(a.cpOnly)
        // CP text present but off centre (a card sliding): neither
        var sliding = stationedScreen()
        for i in 0..<4 { sliding.fill(Rect(x: 0.62 * 750 + Double(i) * 0.045 * 750 * 0.5, y: 0.06 * 1630, w: 0.01 * 750, h: Double(jsRound(0.025 * 1630))), (255, 255, 255)) }
        let (m, _) = FrameReader(text: StationText(), names: names).analyse(sliding)
        XCTAssertNil(m.stationed); XCTAssertNotNil(findCpText(sliding, contentRect(sliding)))
    }

    // MARK: - the encoding

    func testAStationedReadingIsOneFlagOnTheSameFieldsAndAnOldLogStillDecodes() throws {
        var r = FrameReading(frame: "f", time: 3)
        r.name = "Zapdos"; r.speciesIds = ["zapdos"]; r.ivs = IVs(atk: 13, def: 14, hp: 14); r.ivConfidence = 0.94; r.flags = ["stationed"]
        let json = ReplayLog.encode(.reading(ReplayReading(r, time: 3, ms: 9)))
        guard case .reading(let back)? = ReplayLog.decode(json) else { return XCTFail("did not decode") }
        XCTAssertEqual(back.flags, ["stationed"]); XCTAssertEqual(back.name, "Zapdos"); XCTAssertNil(back.cp); XCTAssertNil(back.hp)
        XCTAssertTrue(back.frameReading.isStationed)
        // the line carries no field the old format lacked
        let keys = Set(((try JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]).keys)
        XCTAssertTrue(keys.isSubset(of: ["k", "t", "cp", "cpText", "name", "nameText", "nameWeak", "nameAttached", "speciesIds", "hp", "hpText", "ivs", "ivConfidence", "flags", "ms"]), "\(keys)")
        // a line from before round 31 (run23's blank frames) still decodes, and so does an analysis saved before it
        let old = #"{"k":"r","t":119485.8,"cpText":"","nameText":"","hpText":"","ivConfidence":0,"flags":["no-cp-text"],"ms":12.5}"#
        guard case .reading(let o)? = ReplayLog.decode(Data(old.utf8)) else { return XCTFail("old line did not decode") }
        XCTAssertEqual(o.flags, ["no-cp-text"]); XCTAssertFalse(o.frameReading.isStationed)
        let oldAnalysis = #"{"flags":["no-cp-text"],"needsText":false,"hasCpText":false,"cpOnly":false,"sharpness":0,"sharpnessUp":0,"ivConfidence":0}"#
        let a = try JSONDecoder().decode(FrameAnalysis.self, from: Data(oldAnalysis.utf8))
        XCTAssertNil(a.stationed)
        // and a normal card's analysis does not grow a key
        let normal = try JSONEncoder().encode(FrameAnalysis(frame: "f", time: 0))
        XCTAssertFalse(String(decoding: normal, as: UTF8.self).contains("stationed"))
    }

    // MARK: - what the place is not

    func testThePlaceTextIsNotKeptAnywhereInTheReadingOrItsLogLine() {
        let r = read(stationedScreen(), StationText(line: "At N&R Superette"))
        XCTAssertTrue(r.isStationed)
        let all = String(decoding: ReplayLog.encode(.reading(ReplayReading(r, time: 0, ms: 1))), as: UTF8.self)
            + String(decoding: (try? JSONEncoder().encode(r)) ?? Data(), as: UTF8.self)
        for word in ["Superette", "N&R", "At N"] { XCTAssertFalse(all.contains(word), word) }
        XCTAssertEqual(r.nameText, "Zapdos")
    }

    func testTheAtLineCropIsNeverSavedByTheCropArchive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stationed-archive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (a, crops) = FrameReader(text: NullTextReader(), names: names).analyse(stationedScreen())
        let c = try XCTUnwrap(crops)
        XCTAssertEqual(a.stationed, true); XCTAssertNotNil(c.line)
        let archive = CropArchive(directory: dir)
        XCTAssertTrue(archive.save(a, c))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(files.contains { $0.contains("line") }, "\(files)")
        XCTAssertEqual(Set(files.map { $0.split(separator: "-").last.map(String.init) ?? $0 }).subtracting(["name.png", "nameup.png", "hp.png", "000001.json", "cp.png"]), [])
    }

    /// In "save crops" mode (a deferred read) a stationed candidate is a separator frame, as it was: it cannot be confirmed
    /// without its "At" line, which is not saved.
    func testTheCropSaverCountsAStationedCandidateAsNoCard() {
        var saver = CropSaver()
        var a = FrameAnalysis(frame: "f", time: 1); a.needsText = true; a.stationed = true; a.ivs = IVs(atk: 1, def: 2, hp: 3); a.ivConfidence = 0.9
        for i in 0..<10 { a.time = 1 + Double(i) * 0.2; XCTAssertFalse(saver.shouldSave(&a)) }
        XCTAssertNil(a.segment)
        var card = FrameAnalysis(frame: "g", time: 5); card.needsText = true; card.ivs = IVs(atk: 1, def: 2, hp: 3); card.ivConfidence = 0.9
        var saved = 0
        for i in 0..<10 { card.time = 5 + Double(i) * 0.2; if saver.shouldSave(&card) { saved += 1 } }
        XCTAssertGreaterThan(saved, 0, "a real card is still saved")
    }

    // MARK: - the live consumers keep today's behaviour

    private func card(_ name: String, cp: Int, hp: Int, ivs: IVs, t: Double) -> FrameReading {
        var r = FrameReading(frame: "c\(t)", time: t)
        r.name = name; r.speciesIds = [name.lowercased()]; r.cp = cp; r.cpReads = [cp]; r.cpText = "CP\(cp)"; r.hp = HP(current: hp, max: hp); r.hpText = "\(hp) / \(hp) HP"
        r.ivs = ivs; r.ivConfidence = 0.95; r.nameWeak = false; r.nameText = name
        return r
    }
    private func stationed(_ name: String, t: Double) -> FrameReading {
        var r = FrameReading(frame: "s\(t)", time: t)
        r.name = name; r.speciesIds = [name.lowercased()]; r.nameText = name; r.nameWeak = false
        r.ivs = IVs(atk: 13, def: 14, hp: 14); r.ivConfidence = 0.95; r.flags = ["stationed"]
        return r
    }
    private func blank(t: Double) -> FrameReading { var r = FrameReading(frame: "s\(t)", time: t); r.flags = ["no-cp-text"]; return r }

    /// A scan that passes a stationed Pokémon: a card, 3 s of stationed card (the same species as the card before, and then another
    /// species), a card. The rows are what they are when those frames are the blank frames they were before round 31.
    func testTheLiveGrouperStaysWhereItWasOnAStationedCard() {
        for stationedName in ["Zapdos", "Moltres"] {
            var withStation = LiveGrouper(species: table), withBlank = LiveGrouper(species: table)
            var t = 0.0
            func both(_ station: FrameReading, _ plain: FrameReading) { withStation.add(station); withBlank.add(plain) }
            for _ in 0..<5 { let c = card("Zapdos", cp: 1990, hp: 132, ivs: IVs(atk: 13, def: 14, hp: 14), t: t); both(c, c); t += 0.2 }
            for _ in 0..<15 { both(stationed(stationedName, t: t), blank(t: t)); t += 0.2 }
            for _ in 0..<5 { let c = card("Moltres", cp: 1966, hp: 131, ivs: IVs(atk: 15, def: 14, hp: 13), t: t); both(c, c); t += 0.2 }
            withStation.finish(); withBlank.finish()
            XCTAssertEqual(withStation.rows, withBlank.rows, stationedName)
            XCTAssertEqual(withStation.rows.map(\.name), ["Zapdos", "Moltres"], "no row for the stationed card, \(stationedName)")
        }
    }

    func testTheLiveGrouperStartsNoRowFromStationedFramesAlone() {
        var g = LiveGrouper(species: table)
        for i in 0..<25 { XCTAssertFalse(g.add(stationed("Zapdos", t: Double(i) * 0.2))) }
        g.finish()
        XCTAssertEqual(g.rows, [])
    }

    func testTheEndOfListDetectorAndTheScanEndControllerStayWhereTheyWereOnAStationedCard() {
        var a = EndOfListDetector(period: 1.2), b = EndOfListDetector(period: 1.2)
        var ca = ScanEndController(period: 1.2, storageCount: 50)!, cb = ScanEndController(period: 1.2, storageCount: 50)!
        var eventsA = [ScanEndController.Event](), eventsB = [ScanEndController.Event]()
        var t = 0.0, read = 0
        func feed(_ s: FrameReading, _ plain: FrameReading) {
            _ = a.feed(s, time: t); _ = b.feed(plain, time: t)
            eventsA.append(ca.feed(s, time: t, read: read)); eventsB.append(cb.feed(plain, time: t, read: read))
            t += 0.2
        }
        for k in 0..<6 { for _ in 0..<6 { let c = card(["Zapdos", "Moltres", "Articuno"][k % 3], cp: 1900 + k, hp: 130 + k, ivs: IVs(atk: 10 + k, def: 12, hp: 11), t: t); feed(c, c) }; read += 1 }
        for _ in 0..<40 { feed(stationed("Zapdos", t: t), blank(t: t)) }
        XCTAssertEqual(a.resets, b.resets)
        XCTAssertEqual(a.lastNew, b.lastNew)
        XCTAssertEqual(a.ended?.at, b.ended?.at)
        XCTAssertEqual(eventsA, eventsB)
        XCTAssertEqual(ca.detector.resets, cb.detector.resets)
    }

    /// During a pause a named reading with no CP after a paging tick is "another card was shown" (it moves where a timeout dates the
    /// end). A stationed card after the tick must not count: it was a blank frame, which does not.
    func testAStationedCardDuringAPauseIsNotEvidenceOfAnotherCard() {
        var results = [ScanEndController.Event](), fed = [ScanEndController.Event]()
        for station in [true, false] {
            var c = ScanEndController(period: 1.2, storageCount: 100)!
            var t = 0.0, paused: ScanEndController.Pause?
            for k in 0..<6 { for _ in 0..<6 { _ = c.feed(card(["Zapdos", "Moltres", "Articuno"][k % 3], cp: 1900 + k, hp: 130 + k, ivs: IVs(atk: 10 + k, def: 12, hp: 11), t: t), time: t, read: k + 1); t += 0.2 } }
            while paused == nil && t < 200 {
                if case .pause(let p) = c.feed(card("Zapdos", cp: 1906, hp: 136, ivs: IVs(atk: 15, def: 12, hp: 11), t: t), time: t, read: 6) { paused = p }
                t += 0.2
            }
            XCTAssertNotNil(paused, "the stalled card pauses the scan")
            c.noteSwipe(at: t + 0.1)
            for _ in 0..<8 { fed.append(c.feed(station ? stationed("Moltres", t: t) : blank(t: t), time: t, read: 6)); t += 0.2 }
            results.append(c.finishNow(at: t))
        }
        XCTAssertEqual(fed.prefix(8), fed.suffix(8), "a stationed card is no resume (a different name) and no restart")
        XCTAssertTrue(fed.allSatisfy { $0 == .none }, "\(fed)")
        XCTAssertEqual(results[0], results[1], "the stationed frames change nothing in how the pause ends")
        if case .finish(_, let last) = results[0] { XCTAssertLessThan(last, 40, "the end is dated at the stall, the repeated card after it is trimmed") } else { XCTFail("\(results[0])") }
    }

    func testAsBlankFrameLeavesEveryOtherReadingAlone() {
        let c = card("Zapdos", cp: 1990, hp: 132, ivs: IVs(atk: 13, def: 14, hp: 14), t: 1)
        XCTAssertEqual(c.asBlankFrame, c)
        var odd = FrameReading(frame: "x", time: 2); odd.flags = ["no-cp-text"]
        XCTAssertEqual(odd.asBlankFrame, odd)
        let s = stationed("Zapdos", t: 3).asBlankFrame
        XCTAssertEqual(s.flags, ["no-cp-text"]); XCTAssertNil(s.name); XCTAssertNil(s.ivs); XCTAssertEqual(s.frame, "s3.0"); XCTAssertEqual(s.time, 3)
    }

    // MARK: - the owner's screenshots

    private func fixtureURL(_ name: String) -> URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)") }
    private func p3(_ name: String) throws -> RGBAImage { try decodeRGBA(contentsOf: fixtureURL(name)) }
    private func srgb(_ name: String) throws -> RGBAImage {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(fixtureURL(name) as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var img = RGBAImage(width: cg.width, height: cg.height)
        let ok = img.bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        XCTAssertTrue(ok)
        return img
    }
    private enum Width: CaseIterable { case w750, full }
    private func process(_ img: RGBAImage, _ w: Width) -> FrameReading {
        FrameProcessor(names: names, targetWidth: w == .w750 ? 750 : nil).process(img, time: 0, frame: "f")
    }

    /// Zapdos 13/14/14 is the owner's Zapdos 1990 / 132 (13/14/14); Moltres 15/14/13 is the owner's Moltres 1966 / 131 (15/14/13).
    /// The fixtures are the owner's screenshots as saved (unblanked, by the owner's decision): "At N&R Superette" / "At Vival" are on them,
    /// and the reader must not keep them.
    func testTheStationedScreenshotsReadNameBarsAndTheFlagAndNoCpOrHp() throws {
        for (file, name, ids, ivs) in [("stationed-zapdos.png", "Zapdos", ["zapdos"], IVs(atk: 13, def: 14, hp: 14)),
                                       ("stationed-moltres.png", "Moltres", ["moltres"], IVs(atk: 15, def: 14, hp: 13))] {
            for (space, img) in [("P3", try p3(file)), ("sRGB", try srgb(file))] {
                for w in Width.allCases {
                    let r = process(img, w)
                    let label = "\(file) \(space) \(w): nameText '\(r.nameText)'"
                    XCTAssertEqual(r.name, name, label)
                    XCTAssertEqual(r.speciesIds, ids, label)
                    XCTAssertEqual(r.flags, ["stationed"], label)
                    XCTAssertNil(r.cp, label); XCTAssertNil(r.hp, label)
                    XCTAssertEqual(r.cpText, "", label); XCTAssertEqual(r.hpText, "", label)
                    XCTAssertEqual(r.ivs, ivs, label)
                    XCTAssertGreaterThanOrEqual(r.ivConfidence, SETTLED, label)
                    XCTAssertEqual(r.nameText, name, "the name crop holds the name and not the line under it: \(label)")
                    XCTAssertEqual(r.nameWeak, false, label)
                    let kept = String(decoding: ReplayLog.encode(.reading(ReplayReading(r, time: 0, ms: 1))), as: UTF8.self) + String(decoding: (try JSONEncoder().encode(r)), as: UTF8.self)
                    for place in ["Superette", "N&R", "Vival"] { XCTAssertFalse(kept.contains(place), "the place is not kept: \(label)") }
                }
            }
        }
    }

    /// The RECALL button is found at its real place (0.329 to 0.671 of the width, 0.505 to 0.556 of the height).
    func testTheButtonIsFoundAtItsRealPlaceOnTheScreenshots() throws {
        for file in ["stationed-zapdos.png", "stationed-moltres.png"] {
            for img in [try p3(file), try srgb(file)] {
                let b = try XCTUnwrap(findRecallButton(img, contentRect(img)))
                let W = Double(img.width), H = Double(img.height)
                XCTAssertEqual(Double(b.y0) / H, 0.505, accuracy: 0.004, file)
                XCTAssertEqual(Double(b.y1) / H, 0.556, accuracy: 0.006, file)
                XCTAssertEqual(Double(b.x0) / W, 0.329, accuracy: 0.008, file)
                XCTAssertEqual(Double(b.x1) / W, 0.671, accuracy: 0.008, file)
            }
        }
    }

    /// The normal card, for comparison: Nickit CP 212, 61 / 61 HP. NOT read today: the screenshot's backdrop is near black in two bands
    /// (rows 500 to 681 and the shadow band 925 to 952 average under `contentRect`'s brightness 30, and it bridges only 0.5% of the
    /// height), so `contentRect` takes the card alone (from row 952) as the content and the CP, which is above it, is never found:
    /// flags `no-cp-text`, as for any frame with no anchors. Pinned as the behaviour of the reader before and after round 31 (this is
    /// NOT the desired behaviour; when `contentRect` is fixed, expect CP 212 / HP 61/61 / flags [] here). What this test guards is the
    /// thing round 31 could break: a normal card is never taken for a stationed one, and never gains the flag.
    func testTheNormalNickitCardIsNeverTakenForAStationedOne() throws {
        let file = "normal-nickit-212.png"
        for (space, img) in [("P3", try p3(file)), ("sRGB", try srgb(file))] {
            for w in Width.allCases {
                let r = process(img, w)
                XCTAssertFalse(r.isStationed, "\(space) \(w)")
                XCTAssertNil(r.name, "\(space) \(w)")
                XCTAssertEqual(r.flags, ["no-cp-text"], "\(space) \(w): known limit of contentRect on a near-black backdrop")
            }
        }
    }

    /// The same card read with its dark sky lifted out of the way of `contentRect` (rows 300 to 950, the near-black backdrop, brightened to at least 90 in the
    /// test's copy only): CP 212, 61 / 61 HP, no flags: the card reads as a normal card and carries no `stationed`.
    func testTheNickitCardWithItsSkyLiftedReadsAsANormalCard() throws {
        for (space, original) in [("P3", try p3("normal-nickit-212.png")), ("sRGB", try srgb("normal-nickit-212.png"))] {
            var img = original
            for y in 300..<950 { for x in 0..<img.width { let i = (y * img.width + x) * 4; for k in 0..<3 { img.bytes[i + k] = max(img.bytes[i + k], 90) } } }
            for w in Width.allCases {
                let r = process(img, w)
                let label = "\(space) \(w): cpText '\(r.cpText)' hpText '\(r.hpText)'"
                XCTAssertEqual(r.name, "Nickit", label)
                XCTAssertEqual(r.cp, 212, label)
                XCTAssertEqual(r.hp, HP(current: 61, max: 61), label)
                XCTAssertFalse(r.isStationed, label)
                XCTAssertFalse(r.flags.contains("stationed"), label)
            }
        }
    }
}
