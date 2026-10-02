import XCTest
@testable import PogoReader

final class CropTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-crops-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: u) }
        return u
    }

    private func analysis(card: Bool, settled: Bool = true, n: Int = 0) -> FrameAnalysis {
        var a = FrameAnalysis(frame: "f\(n)", time: Double(n) / 5)
        a.needsText = card
        if card { a.hasCpText = true; a.ivs = IVs(atk: 1, def: 2, hp: 3); a.ivConfidence = settled ? 0.95 : 0.3 }
        return a
    }

    func testSaverKeepsAtMostThreeSettledFramesPerSegmentAndStartsANewSegmentAfterASwipe() {
        var saver = CropSaver()
        var saved = [(Int, Int)]()   // (frame number within the run, segment)
        var n = 0
        for _ in 0..<2 {
            for k in 1...7 { n += 1; var a = analysis(card: true, n: n); if saver.shouldSave(&a) { saved.append((k, a.segment!)) } }
            for _ in 0..<4 { n += 1; var a = analysis(card: false, n: n); XCTAssertFalse(saver.shouldSave(&a)) }
        }
        XCTAssertEqual(saved.map(\.0), [2, 4, 6, 2, 4, 6])
        XCTAssertEqual(saved.map(\.1), [1, 1, 1, 2, 2, 2])
        // A segment whose bars never settle keeps its fifth frame; a short gap does not start a new segment.
        var s2 = CropSaver()
        var kept = 0
        for k in 1...7 { var a = analysis(card: true, settled: false, n: k); if s2.shouldSave(&a) { kept += 1; XCTAssertEqual(k, 5) } }
        XCTAssertEqual(kept, 1)
    }

    /// A card with no HP bar never has its bars read, so they never settle: it is kept on timing alone (3 frames).
    func testACardWithNoHpBarKeepsThreeFrames() {
        var saver = CropSaver()
        var kept = [Int]()
        for k in 0..<10 {
            var a = FrameAnalysis(frame: "f\(k)", time: Double(k) / 5)
            a.needsText = true; a.hasCpText = true; a.cpOnly = true
            if saver.shouldSave(&a) { kept.append(k) }
        }
        XCTAssertEqual(kept, [1, 3, 5])
        // The saver judges by time: every other frame dropped keeps the same number of frames.
        var sparse = CropSaver(), n = 0
        for k in stride(from: 0, to: 20, by: 2) {
            var a = FrameAnalysis(frame: "f\(k)", time: Double(k) / 5)
            a.needsText = true; a.cpOnly = true
            if sparse.shouldSave(&a) { n += 1 }
        }
        XCTAssertEqual(n, 3)
    }

    func testArchiveRoundTripsGrayCropsAndHonoursItsCaps() throws {
        var img = RGBAImage(width: 40, height: 12)
        img.fill(Rect(x: 0, y: 0, w: 40, h: 12), (200, 100, 50))
        img.fill(Rect(x: 5, y: 3, w: 10, h: 4), (255, 255, 255))
        let crops = FrameCrops(cp: img, name: img, nameUp: img, hp: img)
        let archive = CropArchive(directory: tempDir())
        var a = analysis(card: true, n: 1); a.segment = 4
        XCTAssertTrue(archive.save(a, crops))
        XCTAssertEqual(archive.frameCount, 1)
        XCTAssertEqual(archive.fileCount, 5)
        XCTAssertGreaterThan(archive.byteCount, 0)
        let (back, c) = archive.load(archive.frameURLs()[0])!
        XCTAssertEqual(back, a)
        XCTAssertEqual(c.name.width, 40)
        let px = c.name.pixel(7, 4), bg = c.name.pixel(0, 0)
        XCTAssertEqual(px.r, 255)
        XCTAssertEqual(Int(bg.r), Int(img.luma(0, 0).rounded()))
        XCTAssertEqual(bg.r, bg.g)
        // Reopening the folder sees what is there; the next frame gets the next number.
        let again = CropArchive(directory: archive.directory)
        XCTAssertEqual(again.frameCount, 1)
        XCTAssertTrue(again.save(analysis(card: true, n: 2), crops))
        XCTAssertEqual(again.frameURLs().map { $0.lastPathComponent }, ["000001.json", "000002.json"])
        // Caps: nothing is written once a cap would be passed.
        let small = CropArchive(directory: tempDir(), maxFiles: 5, maxBytes: 10_000_000)
        XCTAssertTrue(small.save(analysis(card: true, n: 1), crops))
        XCTAssertFalse(small.save(analysis(card: true, n: 2), crops))
        XCTAssertEqual(small.frameCount, 1)
        let tiny = CropArchive(directory: tempDir(), maxFiles: 100, maxBytes: 50)
        XCTAssertFalse(tiny.save(analysis(card: true, n: 1), crops))
        XCTAssertEqual(tiny.fileCount, 0)
        again.removeAll()
        XCTAssertEqual(again.fileCount, 0)
        XCTAssertEqual(again.frameURLs().count, 0)
    }

    func testPixelHalfAloneNeverNeedsAVisionRequest() {
        let spec = SyntheticScreen.Spec(name: "Charizard", cp: 2017, hp: 132, ivs: IVs(atk: 12, def: 13, hp: 13))
        var img = RGBAImage(width: 1320, height: 2868)
        SyntheticScreen.draw(into: &img, spec)
        let p = FrameProcessor.cropsOnly(names: names, targetWidth: 750)
        let (a, crops) = p.analyse(img, time: 0, frame: "x")
        XCTAssertTrue(a.needsText)
        XCTAssertTrue(a.hasCpText)
        XCTAssertEqual(a.ivs, spec.ivs)
        XCTAssertNotNil(crops?.cp)
        XCTAssertTrue(p.reader.text is NullTextReader)
    }

    /// The deferred path (frame -> crops on disk -> read later) gives the live reading, on a drawn frame, real Vision.
    func testDeferredReadGivesTheSameReadingAsTheLivePath() {
        let spec = SyntheticScreen.Spec(name: "Charizard", cp: 2017, hp: 132, ivs: IVs(atk: 12, def: 13, hp: 13))
        var img = RGBAImage(width: 1320, height: 2868)
        SyntheticScreen.draw(into: &img, spec)
        let live = FrameProcessor(names: names, targetWidth: 750).process(img, time: 0.4, frame: "f")
        let archive = CropArchive(directory: tempDir())
        let (a, crops) = FrameProcessor.cropsOnly(names: names, targetWidth: 750).analyse(img, time: 0.4, frame: "f")
        XCTAssertTrue(archive.save(a, crops!))
        let reader = FrameReader(text: VisionTextReader(), names: names)
        let result = DeferredRun.readAndGroup(archive: archive, reader: reader, species: table)
        XCTAssertEqual(result.readings.count, 1)
        let d = result.readings[0]
        for (name, l, r) in [("cp", live.cp as Any, d.cp as Any), ("name", live.name as Any, d.name as Any), ("hp", live.hp as Any, d.hp as Any), ("ivs", live.ivs as Any, d.ivs as Any),
                             ("flags", live.flags as Any, d.flags as Any), ("time", live.time as Any, d.time as Any), ("sharpness", live.sharpness as Any, d.sharpness as Any)] {
            XCTAssertEqual("\(l)", "\(r)", name)
        }
        XCTAssertEqual(d.cp, 2017); XCTAssertEqual(d.name, "Charizard"); XCTAssertEqual(d.hp, HP(current: 132, max: 132)); XCTAssertEqual(d.ivs, spec.ivs)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].cp, 2017)
        XCTAssertEqual(archive.fileCount, 0, "the crops are deleted after the read")
    }

    func testDeferredRunKeepsTwoIdenticalNeighboursApartByTheirSegments() {
        let img = cardScreen()
        let reader = FrameReader(text: FakeText(), names: names)
        let archive = CropArchive(directory: tempDir())
        let p = FrameProcessor.cropsOnly(names: names, targetWidth: nil)
        for (n, seg) in [(1, 1), (2, 1), (3, 2), (4, 2)] {
            var (a, crops) = p.analyse(img, time: Double(n), frame: "f\(n)")
            a.segment = seg
            XCTAssertTrue(archive.save(a, crops!))
        }
        let r = DeferredRun.readAndGroup(archive: archive, reader: reader, species: table)
        XCTAssertEqual(r.rows.count, 2)
        XCTAssertEqual(r.rows.map(\.frames), [2, 2])
    }

    /// After a deferred read only the frames that were read are deleted: one saved meanwhile (or unreadable) stays.
    func testADeferredReadDeletesOnlyTheFramesItRead() {
        let img = cardScreen()
        let archive = CropArchive(directory: tempDir())
        let p = FrameProcessor.cropsOnly(names: names, targetWidth: nil)
        for n in 1...2 { let (a, c) = p.analyse(img, time: Double(n), frame: "f\(n)"); XCTAssertTrue(archive.save(a, c!)) }
        let reader = FrameReader(text: FakeText(), names: names)
        let result = DeferredRun.readAndGroup(archive: archive, reader: reader, species: table, removeWhenDone: false)
        XCTAssertEqual(result.consumed.count, 2)
        // A frame arrives while the app was reading.
        let (a3, c3) = p.analyse(img, time: 3, frame: "f3"); XCTAssertTrue(archive.save(a3, c3!))
        archive.remove(frames: result.consumed)
        XCTAssertEqual(archive.frameURLs().map { $0.lastPathComponent }, ["000003.json"])
        XCTAssertEqual(archive.frameCount, 1)
        XCTAssertEqual(archive.fileCount, 5)
        XCTAssertEqual(CropArchive(directory: archive.directory).fileCount, 5)
    }

    func testTheLowMemoryGuard() {
        XCTAssertTrue(ReadGuard.shouldSkipVision(availableBytes: 7 * 1_048_576))
        XCTAssertFalse(ReadGuard.shouldSkipVision(availableBytes: 9 * 1_048_576))
        XCTAssertFalse(ReadGuard.shouldSkipVision(availableBytes: nil))
        XCTAssertEqual(ReaderMode.allCases.map(\.rawValue), ["accurate", "fast", "saveCrops", "accurateFewerPasses"])
    }
}
