import Foundation
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PogoBox
import PogoReader
import PogoImport

/// Screenshot import end to end below the UI: real screenshots from the owner's phone (the fixtures of `PogoReaderTests`) staged into a real queue, read by the real reader (Vision),
/// merged and saved into a real box on disk. Where a case needs a picture the fixtures do not have, it is made from one (bars painted out, one pixel changed).
final class ScreenshotImporterTests: XCTestCase {
    var dir: URL!
    var queue: ImportQueue!
    var lib: BoxLibrary!
    var importer: ScreenshotImporter!
    /// Every read that reached the reader, by staged item id.
    var reads = [String]()
    var failing = Set<String>()

    // The real reader is shared: Vision is the slow part, and a picture reads the same every time.
    static let vision = try! StillReader()
    static var cache = [String: StillOutcome]()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-import-\(UUID().uuidString)")
        queue = ImportQueue(root: dir.appendingPathComponent("screenshot-imports"))
        lib = BoxLibrary(root: dir.appendingPathComponent("boxes"))
        try lib.createAccount("Main")
        importer = makeImporter()
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeImporter() -> ScreenshotImporter {
        ScreenshotImporter(queue: queue, library: lib) { [unowned self] url, label in
            reads.append(label)
            if failing.contains(label) { throw StillImageError.cannotDecode }
            let hash = try ImageNormalising.sha256(of: url)
            if let hit = Self.cache[hash] { return hit }
            let out = try Self.vision.read(contentsOf: url, label: "cached")
            Self.cache[hash] = out
            return out
        }
    }

    // MARK: pictures

    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PogoReaderTests/Fixtures")
    func file(_ name: String) throws -> Data { try Data(contentsOf: Self.fixtures.appendingPathComponent(name)) }
    var nickit: Data { get throws { try file("normal-nickit-212.png") } }
    var rayquaza: Data { get throws { try file("rayquaza-damaged-19of190.png") } }
    var rayquazaFainted: Data { get throws { try file("rayquaza-fainted-0of190.png") } }
    var stationed: Data { get throws { try file("stationed-zapdos.png") } }

    /// The picture with its appraisal bars painted out (name, CP and HP stay).
    func withoutBars(_ data: Data) throws -> Data {
        var img = try StillImage.decode(data: data)
        img.fill(Rect(x: 0, y: 0.58 * Double(img.height), w: Double(img.width), h: 0.42 * Double(img.height)), (240, 245, 247))
        return try png(img)
    }

    /// The same Pokémon screenshotted again: one pixel of the status bar differs, so the bytes (and hash) do.
    func retake(_ data: Data) throws -> Data {
        var img = try StillImage.decode(data: data)
        img.bytes[0] = img.bytes[0] &+ 7
        return try png(img)
    }

    func png(_ img: RGBAImage) throws -> Data {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(img.bytes) as CFData))
        let cg = try XCTUnwrap(CGImage(width: img.width, height: img.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    var blank: Data { get throws { var img = RGBAImage(width: 600, height: 1200); img.fill(Rect(x: 0, y: 0, w: 600, h: 1200), (30, 90, 160)); return try png(img) } }

    @discardableResult
    func stage(_ pictures: [Data], assets: [String?]? = nil, account: String? = "Main", origin: ImportManifest.Origin = .photoPicker, now: Date = Date()) throws -> ImportManifest {
        let b = try queue.beginBatch(origin: origin, account: account, renameMark: lib.store.renameCount, accountBorn: account.flatMap { lib.store.accountCreated($0) }, now: now)
        for (i, p) in pictures.enumerated() { try b.add(data: p, assetId: assets?[i]) }
        return try b.commit(now: now)
    }

    func state(_ m: ImportManifest) -> [ImportItem.State] { m.items.map(\.state) }
    func rowNames(_ p: ScreenshotImporter.Prepared) -> [String] { p.outcome.scan.rows.map { "\($0.name) \($0.cp)" } }

    /// Read the batch in full and make the review.
    func review(_ m: ImportManifest) throws -> ScreenshotImporter.Prepared {
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        return try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
    }

    func existing(_ names: [(String, Int)]) throws -> [BoxEntry] {
        // five unrelated saved Pokémon, as an earlier scan might have left them
        try names.enumerated().map { i, n in
            BoxEntry(id: "old\(i)", row: ScanRow(index: i + 1, name: n.0, display: n.0, form: "", speciesId: n.0.lowercased(), dex: 10 + i, cp: n.1, hp: 40, ivs: IVs(atk: 1, def: 2, hp: 3), ivsRead: nil, ivsGuess: nil,
                                                 level: 5, levelMax: 5, dust: 200, solveStatus: "exact", flags: [], frames: []), firstSeen: Date(timeIntervalSince1970: 1_790_000_000), lastSeen: Date(timeIntervalSince1970: 1_790_000_000))
        }
    }

    // MARK: single and batch imports

    func testASingleScreenshotBecomesAPartialImportThatSavesOnceAndTidiesUp() throws {
        let m = try stage([try nickit])
        let p = try review(m)
        XCTAssertEqual(rowNames(p), ["Nickit 212"])
        XCTAssertEqual(p.plan.kind, .partial)
        XCTAssertEqual(p.plan.new, [0]); XCTAssertTrue(p.plan.gone.isEmpty)
        XCTAssertEqual(p.outcome.scan.rows[0].ivs, IVs(atk: 9, def: 2, hp: 13))
        XCTAssertEqual(p.account, "Main")
        guard case .saved(let snap) = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail("not saved") }
        XCTAssertEqual(snap.entries.map { $0.row.name }, ["Nickit"])
        // recorded as a screenshot import, add-and-update, with the batch as its source
        let scan = try XCTUnwrap(try lib.store.list(account: "Main").scans.first)
        XCTAssertEqual(scan.source, "screenshot import"); XCTAssertEqual(scan.kind, .partial); XCTAssertEqual(scan.sourceSignature, m.signature)
        // staged files are gone; the screenshot is remembered
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.batchDirectory(m.batchId).path))
        XCTAssertEqual(try queue.list().manifests.count, 0)
        XCTAssertNotNil(queue.ledger().savedAt(account: "Main", keys: m.items[0].keys))
    }

    func testABatchReportsEachScreenshotAndOneBadImageCostsTheOthersNothing() throws {
        let m = try stage([try nickit, try rayquaza, try stationed, try withoutBars(try nickit), try blank])
        let p = try review(m)
        let read = try queue.load(m.batchId)
        XCTAssertEqual(state(read), [.read, .read, .unsupported, .ivsMissing, .unsupported])
        XCTAssertEqual(rowNames(p), ["Nickit 212", "Rayquaza 4262"])
        XCTAssertTrue(read.items[3].detail?.contains("appraisal bars") == true, read.items[3].detail ?? "")
        XCTAssertEqual(StillImport.title(of: read.items[3]), "Nickit, CP 212", "the person is told which Pokémon it was")
        XCTAssertNil(read.items[2].reading, "a stationed card is never named")
        XCTAssertEqual(p.rowItems, [read.items[0].id, read.items[1].id])
        XCTAssertEqual(p.outcome.readings, 5)
    }

    func testScreenshotsWithoutIVsOrOfOtherScreensNeverAddAPokemon() throws {
        let m = try stage([try withoutBars(try nickit), try stationed, try blank])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(state(try queue.load(m.batchId)), [.ivsMissing, .unsupported, .unsupported])
        XCTAssertThrowsError(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .nothingToImport) }
        XCTAssertNil(try lib.current(account: "Main"))
    }

    func testAnUnreadableFileFailsAloneAndCanBeRetried() throws {
        let m = try stage([try nickit, try rayquaza])
        failing = [m.items[1].id]
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        var now = try queue.load(m.batchId)
        XCTAssertEqual(state(now), [.read, .failed]); XCTAssertTrue(now.items[1].canRetry); XCTAssertFalse(now.items[0].canRetry)
        XCTAssertEqual(rowNames(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)), ["Nickit 212"], "the good read is not lost")
        failing = []
        reads = []
        now = try importer.retryAll(batch: m.batchId)
        XCTAssertEqual(state(now), [.read, .pending])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(reads, [m.items[1].id], "only the failed one is read again")
        XCTAssertEqual(rowNames(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)), ["Nickit 212", "Rayquaza 4262"])
    }

    func testStagingRefusesAFileThatIsNotAnImageWithoutSpoilingTheBatch() throws {
        let b = try queue.beginBatch(origin: .photoPicker, account: "Main")
        XCTAssertThrowsError(try b.add(data: Data(try nickit.prefix(40))))   // a truncated PNG
        try b.add(data: try nickit)
        XCTAssertEqual(try b.commit().items.count, 1)
    }

    // MARK: duplicates and twins

    func testTheSameAssetOrBytesAreReadOnceAndAddedOnce() throws {
        let m = try stage([try nickit, try nickit, try retake(try nickit)], assets: ["A", "B", "A"])
        let p = try review(m)
        XCTAssertEqual(reads.count, 1, "the second is the same bytes and the third the same asset: neither is read")
        XCTAssertEqual(rowNames(p), ["Nickit 212"])
        let done = try queue.load(m.batchId)
        XCTAssertEqual(done.items.map { $0.duplicateOf != nil }, [false, true, true])
        XCTAssertEqual(done.duplicates.count, 2)
    }

    func testARetriedShareIsRecognisedWhileQueuedAndAfterItsBatchWasSaved() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try stage([try nickit, try rayquaza], origin: .shareExtension, now: t0)
        let again = try stage([try nickit, try rayquaza], origin: .shareExtension, now: t0.addingTimeInterval(30))
        // both queued: the later batch's screenshots are copies and are not read
        try importer.readAll(batch: again.batchId, engine: sharedEngine)
        XCTAssertEqual(reads, [], "nothing was read: every screenshot is a copy of one in the older batch")
        XCTAssertThrowsError(try importer.prepareReview(batch: again.batchId, engine: sharedEngine)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .nothingToImport) }
        // the older batch is imported and saved
        guard case .saved = try importer.save(try review(first), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        // the older batch is gone, so the later one is no longer a copy of anything queued, but IS of what was saved: held back, not added again
        let later = try importer.prepare(batch: again.batchId)
        XCTAssertTrue(later.items.allSatisfy { $0.alreadyImported != nil && $0.duplicateOf == nil })
        try importer.readAll(batch: again.batchId, engine: sharedEngine)
        let done = try queue.load(again.batchId)
        XCTAssertEqual(done.heldBack.count, 2); XCTAssertEqual(done.included.count, 0)
        // the person can say "import it again": the box then pairs it with the saved one as an unchanged Pokémon, not a new one
        try importer.setIncluded(batch: again.batchId, item: done.items[0].id, true)
        let p = try importer.prepareReview(batch: again.batchId, engine: sharedEngine)
        XCTAssertEqual(rowNames(p), ["Nickit 212"]); XCTAssertEqual(p.plan.same.count, 1); XCTAssertTrue(p.plan.new.isEmpty)
    }

    func testTwoScreenshotsOfTheSamePokemonAreHeldBackNotMergedAndNotAddedTwice() throws {
        // Rayquaza at 19/190 HP and at 0/190: different pictures, the same species, CP, max HP and IVs.
        let m = try stage([try rayquaza, try rayquazaFainted])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        let done = try queue.load(m.batchId)
        XCTAssertNil(done.items[0].repeatOf); XCTAssertEqual(done.items[1].repeatOf, done.items[0].id)
        XCTAssertEqual(done.heldBack.map(\.id), [done.items[1].id])
        XCTAssertEqual(rowNames(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)), ["Rayquaza 4262"])
        // the person says they are two Pokémon (genuine twins exist): both are rows, and nothing merged them
        try importer.setIncluded(batch: m.batchId, item: done.items[1].id, true)
        let twins = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(rowNames(twins), ["Rayquaza 4262", "Rayquaza 4262"]); XCTAssertEqual(twins.plan.new, [0, 1])
        // and the choice can be taken back
        try importer.setIncluded(batch: m.batchId, item: done.items[1].id, false)
        XCTAssertEqual(rowNames(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)).count, 1)
    }

    func testRepeatsAreFoundByLookAndByIVsAtAnotherCPButNeverForADifferentPokemon() {
        func item(_ id: String) -> ImportItem { ImportItem(id: id, file: id, sourceHash: id, stagedHash: id, width: 1, height: 1, state: .read) }
        func row(_ species: String, cp: Int, hp: Int = 100, ivs: IVs) -> ScanRow {
            ScanRow(index: 1, name: species, display: species, form: "", speciesId: species, dex: 1, cp: cp, hp: hp, ivs: ivs, ivsRead: nil, ivsGuess: nil, level: 1, levelMax: 1, dust: 1, solveStatus: "exact", flags: [], frames: [])
        }
        let a = IVs(atk: 1, def: 2, hp: 3), b = IVs(atk: 4, def: 5, hp: 6)
        let items = ["1", "2", "3", "4", "5", "6"].map(item)
        let rows: [String: ScanRow] = ["1": row("pidgey", cp: 500, ivs: a), "2": row("pidgey", cp: 500, ivs: a),      // a retake or a twin
                                       "3": row("pidgey", cp: 650, ivs: a),                                         // the same IVs after a power-up, or another
                                       "4": row("pidgey", cp: 500, ivs: b),                                         // other IVs: a different Pokémon
                                       "5": row("rattata", cp: 500, ivs: a),                                        // other species
                                       "6": row("pidgey", cp: 500, hp: 90, ivs: b)]                                // same IVs as 4, other HP/CP: caught by the IVs rule
        XCTAssertEqual(StillImport.repeats(items: items, rows: rows), ["2": "1", "3": "1", "6": "4"])
        var copies = items; copies[1].duplicateOf = "1"
        XCTAssertNil(StillImport.repeats(items: copies, rows: rows)["2"], "a copy of a screenshot is not a candidate")
    }

    // MARK: the box

    func testAScreenshotOfAPokemonAlreadyInTheBoxIsAnUnchangedMatchNotANewEntry() throws {
        let first = try stage([try nickit])
        guard case .saved(let v1) = try importer.save(try review(first), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        let second = try stage([try retake(try nickit)])
        let p = try review(second)
        XCTAssertEqual(p.plan.same.count, 1); XCTAssertTrue(p.plan.new.isEmpty); XCTAssertTrue(p.plan.unsure.isEmpty)
        // BoxMerge pairs it with the saved one as unchanged, exactly as for Auto Scan: no question, nothing added.
        guard case .saved(let v2) = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(v2.entries.count, 1); XCTAssertEqual(v2.entries[0].id, v1.entries[0].id)
    }

    func testAnUncertainMatchIsAQuestionAndSaveWaitsForTheAnswer() throws {
        // The box holds this Rayquaza at a lower CP, same IVs: powered up, or another Pokémon? Never decided silently.
        let saved = try stage([try rayquaza])
        guard case .saved(let v1) = try importer.save(try review(saved), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        _ = try lib.mutate(account: "Main", reason: .edit, note: "lower CP") { entries in
            var e = entries; e[0].row.cp = 3900; return e
        }
        let m = try stage([try rayquazaFainted])
        let p = try review(m)
        XCTAssertEqual(p.plan.unsure.map(\.kind), [.poweredUp])
        XCTAssertThrowsError(try importer.save(p, resolutions: [:], engine: sharedEngine)) { XCTAssertEqual($0 as? BoxMerge.Failure, .unresolved(1)) }
        XCTAssertEqual(try lib.current(account: "Main")?.entries.map(\.row.cp), [3900], "nothing was written")
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.batchDirectory(m.batchId).path), "and the batch is still queued")
        // "it is new" adds beside it
        let p2 = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        guard case .saved(let snap) = try importer.save(p2, resolutions: [0: .new], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(snap.entries.count, 2); XCTAssertEqual(snap.entries[0].id, v1.entries[0].id); XCTAssertEqual(snap.entries[0].row.cp, 3900)
    }

    func testAnExtraTwinOfASavedPokemonIsAQuestionNotASilentAdd() throws {
        let saved = try stage([try rayquaza])
        guard case .saved = try importer.save(try review(saved), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        // the same Rayquaza screenshotted twice (different bytes) with the person saying "include it anyway": one pairs with the saved one, the other must be asked about
        let m = try stage([try retake(try rayquaza), try rayquazaFainted])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try importer.setIncluded(batch: m.batchId, item: m.items[1].id, true)
        let p = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(p.plan.same.count, 1)
        XCTAssertEqual(p.plan.unsure.map(\.kind), [.extraTwin])
        XCTAssertThrowsError(try importer.save(p, resolutions: [:], engine: sharedEngine))
    }

    func testHandCorrectionsSurviveAnImportThatReadsTheOldValueAgain() throws {
        let saved = try stage([try nickit])
        guard case .saved = try importer.save(try review(saved), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        // the person corrected the HP by hand (the scan had read 61)
        _ = try lib.mutate(account: "Main", reason: .edit, note: "corrected") { entries in
            var e = entries; e[0].row.hp = 62; e[0].corrections.hp = Fix(was: 61); return e
        }
        let m = try stage([try retake(try nickit)])
        guard case .saved(let snap) = try importer.save(try review(m), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(snap.entries.count, 1)
        XCTAssertEqual(snap.entries[0].row.hp, 62); XCTAssertEqual(snap.entries[0].corrections.hp, Fix(was: 61))
    }

    func testAPartialImportLeavesEveryOtherSavedPokemonExactlyAsItWas() throws {
        let others = try existing([("Pidgey", 100), ("Rattata", 120), ("Zubat", 90), ("Weedle", 80), ("Caterpie", 70)])
        _ = try lib.commit(account: "Main", entries: others, reason: .scan, note: "earlier")
        let m = try stage([try nickit])
        let p = try review(m)
        XCTAssertTrue(p.plan.gone.isEmpty); XCTAssertEqual(p.plan.kind, .partial)
        guard case .saved(let snap) = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(Array(snap.entries.prefix(5)), others, "not seen is not gone: all five untouched, byte for byte")
        XCTAssertEqual(snap.entries.count, 6)
    }

    // MARK: cancelling, relaunching, retrying

    func testCancellingMidwayKeepsWhatWasReadAndARelaunchFinishesTheRest() throws {
        let m = try stage([try nickit, try rayquaza, try withoutBars(try nickit)])
        var asked = 0
        try importer.readAll(batch: m.batchId, engine: sharedEngine, shouldStop: { asked += 1; return asked > 1 })
        let midway = try queue.load(m.batchId)
        XCTAssertEqual(state(midway), [.read, .pending, .pending])
        XCTAssertNotNil(midway.items[0].reading, "the first read is on disk")
        // a new importer (a relaunch) carries on from the file: the first is not read again
        importer = makeImporter(); reads = []
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(reads, [m.items[1].id, m.items[2].id])
        XCTAssertEqual(state(try queue.load(m.batchId)), [.read, .read, .ivsMissing])
    }

    func testAReadThatKeepsEndingTheAppIsNotStartedAgainOnItsOwn() throws {
        let m = try stage([try nickit])
        try queue.update(m.batchId) { $0.items[0].attempts = ScreenshotImporter.maxAttempts }   // two reads started and never finished
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        let done = try queue.load(m.batchId)
        XCTAssertEqual(done.items[0].state, .failed); XCTAssertEqual(reads, [])
        XCTAssertTrue(done.items[0].canRetry)
        _ = try importer.retry(batch: m.batchId, item: m.items[0].id)
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(try queue.load(m.batchId).items[0].state, .read)
    }

    func testAStartedReadIsCountedOnDiskBeforeItBegins() throws {
        let m = try stage([try nickit])
        var seen = -1
        importer = ScreenshotImporter(queue: queue, library: lib) { [unowned self] url, _ in
            seen = try queue.load(m.batchId).items[0].attempts   // what a killed app would leave behind
            return try Self.vision.read(contentsOf: url)
        }
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(seen, 1)
    }

    // MARK: accounts

    func testABatchBelongsToItsAccountWhateverIsSelectedLater() throws {
        try lib.createAccount("Alt")
        let m = try stage([try nickit], account: "Main")
        let p = try review(m)
        XCTAssertEqual(p.account, "Main")
        guard case .saved = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(try lib.current(account: "Main")?.entries.count, 1); XCTAssertNil(try lib.current(account: "Alt"))
    }

    func testARenamedAccountIsFollowedAndARemovedOneIsRefusedUntilAnotherIsChosen() throws {
        let m = try stage([try nickit], account: "Main")
        try lib.renameAccount(from: "Main", to: "Renamed")
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .account("Renamed"))
        let p = try review(m)
        XCTAssertEqual(p.account, "Renamed"); XCTAssertEqual(try queue.load(m.batchId).account, "Renamed")

        try lib.createAccount("Gone"); let g = try stage([try rayquaza], account: "Gone")
        try lib.store.deleteAccount("Gone")
        XCTAssertEqual(importer.owner(of: try queue.load(g.batchId)), .gone("Gone"))
        try importer.readAll(batch: g.batchId, engine: sharedEngine)
        XCTAssertThrowsError(try importer.prepareReview(batch: g.batchId, engine: sharedEngine)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .accountGone("Gone")) }
        XCTAssertThrowsError(try importer.assign(batch: g.batchId, to: "Nowhere"))
        try importer.assign(batch: g.batchId, to: "Renamed")
        XCTAssertEqual(try importer.prepareReview(batch: g.batchId, engine: sharedEngine).account, "Renamed")
    }

    func testAShareMadeBeforeAnyAccountWaitsForOne() throws {
        let m = try stage([try nickit], account: nil, origin: .shareExtension)
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .unassigned)
        XCTAssertThrowsError(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .noAccount) }
        try importer.assign(batch: m.batchId, to: "Main")
        XCTAssertEqual(rowNames(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)), ["Nickit 212"])
    }

    // MARK: saving

    func testASaveThatFailsWritesNothingAndKeepsTheBatchForARetryThatSavesOnce() throws {
        let m = try stage([try nickit])
        let p = try review(m)
        struct Boom: Error {}
        XCTAssertThrowsError(try importer.save(p, resolutions: [:], engine: sharedEngine, commitFailure: { throw Boom() }))
        XCTAssertNil(try lib.current(account: "Main")); XCTAssertEqual(try lib.store.list(account: "Main").scans.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.batchDirectory(m.batchId).path))
        guard case .saved = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(try lib.history(account: "Main").count, 1)
    }

    func testSavingTheSameReviewTwiceAddsItOnce() throws {
        let m = try stage([try nickit])
        let p = try review(m)
        guard case .saved = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        guard case .alreadySaved = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail("a second save wrote again") }
        XCTAssertEqual(try lib.history(account: "Main").count, 1); XCTAssertEqual(try lib.store.list(account: "Main").scans.count, 1)
        XCTAssertEqual(try lib.current(account: "Main")?.entries.count, 1)
    }

    func testASaveCutOffAfterTheBoxWasWrittenIsRecognisedOnRelaunchAndNotRepeated() throws {
        let m = try stage([try nickit, try rayquaza])
        let p = try review(m)
        struct Cut: Error {}
        // the box is written, then the app is ended before the clean-up
        XCTAssertThrowsError(try importer.save(p, resolutions: [:], engine: sharedEngine, afterCommit: { throw Cut() }))
        XCTAssertEqual(try lib.current(account: "Main")?.entries.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.batchDirectory(m.batchId).path))
        // relaunch: the next look at the queue finishes it from the note the save wrote down, and the box is not written again
        importer = makeImporter()
        _ = try importer.prepareAll(engine: sharedEngine)
        XCTAssertEqual(try lib.history(account: "Main").count, 1); XCTAssertEqual(try lib.current(account: "Main")?.entries.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.batchDirectory(m.batchId).path), "the clean-up that was cut off is finished")
        XCTAssertNotNil(queue.ledger().savedAt(account: "Main", keys: m.items[0].keys), "what was saved is in the ledger")
        // and a second tap on the review that was open saves nothing more
        guard case .alreadySaved = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail("saved a second time") }
        XCTAssertEqual(try lib.history(account: "Main").count, 1)
    }

    /// (round 2) The recovery used to guess that every row was saved. A row the person left out must not be recorded as saved.
    func testCrashRecoveryDoesNotRecordALeftOutScreenshotAsSaved() throws {
        let saved = try stage([try rayquaza])
        guard case .saved = try importer.save(try review(saved), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        _ = try lib.mutate(account: "Main", reason: .edit, note: "lower CP") { e in var e = e; e[0].row.cp = 3900; return e }
        let m = try stage([try rayquazaFainted])
        let p = try review(m)
        XCTAssertEqual(p.plan.unsure.count, 1)
        struct Cut: Error {}
        XCTAssertThrowsError(try importer.save(p, resolutions: [0: .leaveOut], engine: sharedEngine, afterCommit: { throw Cut() }))
        let written = try XCTUnwrap(try queue.load(m.batchId).pendingSave, "what the save contained was written down before the box")
        XCTAssertEqual(written.items, []); XCTAssertEqual(written.leftOut, [m.items[0].id]); XCTAssertEqual(written.account, "Main")
        importer = makeImporter()
        _ = try importer.prepareAll(engine: sharedEngine)
        XCTAssertNil(queue.ledger().savedAt(account: "Main", keys: m.items[0].keys), "a left-out screenshot is not in the ledger as saved")
        XCTAssertThrowsError(try queue.load(m.batchId), "and it is not kept to be asked about again")
    }

    func testASaveCutOffAfterTheLedgerWasWrittenDoesNotHoldItsOwnScreenshotsBack() throws {
        // The crash the earlier test did not model: box written, ledger written, batch not yet retired. On relaunch the batch's own screenshots must not look "already imported".
        let m = try stage([try nickit, try rayquaza])
        let p = try review(m)
        let entries = try BoxMerge.apply(p.plan, to: p.base, engine: sharedEngine)
        _ = try lib.commitScan(p.outcome.scan, entries: entries, account: "Main", scanDate: p.plan.scanDate, source: "screenshot import", kind: .partial, note: "cut off",
                               expectedCurrentSeq: .some(nil), sourceSignature: m.signature)
        try queue.recordSaved(m.items, batchId: m.batchId, account: "Main", epoch: lib.store.renameCount)
        importer = makeImporter()
        let again = try review(m)   // would throw nothingToImport if both were held back as already imported
        XCTAssertEqual(again.outcome.scan.rows.count, 2)
        guard case .alreadySaved = try importer.save(again, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(try lib.history(account: "Main").count, 1)
        XCTAssertEqual(try queue.list().manifests.count, 0)
    }

    func testARemovalCutOffAfterSavingIsFinishedByCleanupNotRepeatedAsASave() throws {
        let m = try stage([try nickit])
        let p = try review(m)
        let entries = try BoxMerge.apply(p.plan, to: p.base, engine: sharedEngine)
        _ = try lib.commitScan(p.outcome.scan, entries: entries, account: "Main", scanDate: p.plan.scanDate, source: "screenshot import", kind: .partial, note: "x", expectedCurrentSeq: .some(nil), sourceSignature: m.signature)
        try queue.recordSaved(m.items, batchId: m.batchId, account: "Main")
        _ = try queue.update(m.batchId) { $0.savedAt = Date() }   // ...and the app ended before the folder was removed
        XCTAssertEqual(queue.cleanup().removedSaved, 1)
        XCTAssertEqual(try queue.list().manifests.count, 0)
        XCTAssertEqual(try lib.history(account: "Main").count, 1)
    }

    func testDiscardingAddsNothingAndRemembersNothing() throws {
        let m = try stage([try nickit])
        _ = try review(m)
        try importer.discard(batch: m.batchId)
        XCTAssertNil(try lib.current(account: "Main")); XCTAssertEqual(try queue.list().manifests.count, 0)
        XCTAssertTrue(queue.ledger().entries.isEmpty)
        // so the same screenshot can be imported afterwards
        XCTAssertEqual(rowNames(try review(try stage([try nickit]))), ["Nickit 212"])
    }

    func testTwoQueuedBatchesAreEachImportedInTurn() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try stage([try nickit], origin: .shareExtension, now: t0)
        let b = try stage([try rayquaza], origin: .shareExtension, now: t0.addingTimeInterval(60))
        XCTAssertEqual(try queue.list().manifests.map(\.batchId), [a.batchId, b.batchId])
        guard case .saved = try importer.save(try review(a), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(try queue.list().manifests.map(\.batchId), [b.batchId])
        guard case .saved(let snap) = try importer.save(try review(b), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(snap.entries.map { $0.row.name }.sorted(), ["Nickit", "Rayquaza"])
        XCTAssertEqual(try lib.history(account: "Main").count, 2)
    }

    // MARK: the fold of review round 1

    /// 1. A value the solver corrected or worked out is not a read.
    func testACorrectedOrRecoveredValueIsNeverAddedAsARead() throws {
        guard case .read(let nick) = try Self.vision.read(contentsOf: Self.fixtures.appendingPathComponent("normal-nickit-212.png")),
              case .read(let rayq) = try Self.vision.read(contentsOf: Self.fixtures.appendingPathComponent("rayquaza-damaged-19of190.png")) else { return XCTFail() }
        guard case .row = StillImport.solve(nick, engine: sharedEngine) else { return XCTFail("the clean read is a row") }
        // bars one step off what CP and HP allow: the solver would "correct" the IVs
        var off = nick, found = false
        search: for (da, dd, dh) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1), (1, 1, 0), (-1, -1, 0), (0, 1, 1), (0, -1, -1), (1, 0, 1), (-1, 0, -1)] {
            var t = nick; t.ivs = IVs(atk: 9 + da, def: 2 + dd, hp: 13 + dh)
            guard let raw = try? sharedEngine.finish(readings: [t]).rows.first else { continue }
            if raw.solveStatus == "corrected" || raw.flags.contains(where: { $0.hasPrefix("ivs-corrected") }) { off = t; found = true; break search }
        }
        XCTAssertTrue(found, "the setup must find bars the solver corrects")
        guard case .unreadable(let why) = StillImport.solve(off, engine: sharedEngine) else { return XCTFail("a corrected IV set was taken as read") }
        XCTAssertTrue(why.contains("changed the IVs") || why.contains("corrected"), why)
        // the leading digit of the CP lost: the JavaScript recovers 4262 from 262
        var tail = rayq; tail.cp = 262; tail.cpReads = [262]
        let rawTail = try sharedEngine.finish(readings: [tail]).rows[0]
        XCTAssertTrue(rawTail.flags.contains { $0.hasPrefix("cp-recovered") }, "setup: \(rawTail.flags)")
        guard case .unreadable = StillImport.solve(tail, engine: sharedEngine) else { return XCTFail("a recovered CP was taken as read") }
        // and through the importer: nothing is added, the screenshot says why
        let m = try stage([try nickit])
        importer = ScreenshotImporter(queue: queue, library: lib) { _, _ in .read(off) }
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(try queue.load(m.batchId).items[0].state, .unreadable)
        XCTAssertThrowsError(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .nothingToImport) }
    }

    /// 2. A name renamed away and then reused is ambiguous; the person chooses; the ledger does not follow the wrong account.
    func testARenamedAwayNameThatIsUsedAgainIsAskedAboutNotGuessed() throws {
        let m = try stage([try nickit, try rayquaza], account: "Main")
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try lib.renameAccount(from: "Main", to: "Renamed")
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .account("Renamed"), "followed first")
        try lib.createAccount("Main")   // a new account takes the old name
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .ambiguous(old: "Main", renamedTo: "Renamed"))
        XCTAssertThrowsError(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .accountAmbiguous(old: "Main", renamedTo: "Renamed")) }
        XCTAssertNil(try lib.current(account: "Main")); XCTAssertNil(try lib.current(account: "Renamed"))
        try importer.assign(batch: m.batchId, to: "Renamed")
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .account("Renamed"))
        guard case .saved = try importer.save(try importer.prepareReview(batch: m.batchId, engine: sharedEngine), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(try lib.current(account: "Renamed")?.entries.count, 2); XCTAssertNil(try lib.current(account: "Main"))
        // The ledger: what was saved into "Renamed" is not "already imported" for the new account called "Main"
        let again = try stage([try nickit], account: "Main")
        XCTAssertNil(try importer.prepare(batch: again.batchId).items[0].alreadyImported)
        let toRenamed = try stage([try nickit], account: "Renamed")
        XCTAssertNotNil(try importer.prepare(batch: toRenamed.batchId).items[0].alreadyImported)
    }

    func testASaveIntoAnAccountRenamedAfterwardsStillCountsInTheLedgerOfItsNewName() throws {
        let m = try stage([try nickit])
        guard case .saved = try importer.save(try review(m), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        try lib.renameAccount(from: "Main", to: "Renamed")
        let again = try stage([try nickit], account: "Renamed")
        XCTAssertNotNil(try importer.prepare(batch: again.batchId).items[0].alreadyImported)
    }

    /// 3. Saving keeps what still needs the person.
    func testSavingKeepsTheHeldBackAndFailedScreenshotsQueued() throws {
        let m = try stage([try nickit, try rayquaza, try rayquazaFainted, try stationed])
        failing = [m.items[3].id]
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        let p = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(rowNames(p), ["Nickit 212", "Rayquaza 4262"])   // the fainted one is held back as a possible repeat; the last failed
        guard case .saved = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        let left = try queue.load(m.batchId)
        XCTAssertEqual(left.items.map(\.id), [m.items[2].id, m.items[3].id])
        XCTAssertEqual(left.items.map(\.state), [.read, .failed])
        // its source was saved, so the hold is lifted: the box merge decides what it is (here an exact match to the saved one, which is that Pokémon)
        XCTAssertNil(left.items[0].repeatOf); XCTAssertFalse(left.items[0].heldBack)
        XCTAssertNotEqual(left.signature, m.signature)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.stagedURL(batch: m.batchId, item: m.items[0]).path))
        // the held-back one can still be included; saving it is a second scan record and the batch then goes
        failing = []
        try importer.setIncluded(batch: m.batchId, item: m.items[2].id, true)
        _ = try importer.retryAll(batch: m.batchId)
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        let second = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(rowNames(second), ["Rayquaza 4262"], "the retried stationed card adds nothing; the included twin is a row")
        guard case .saved(let snap) = try importer.save(second, resolutions: [:], engine: sharedEngine) else { return XCTFail("the second save was taken for the first") }
        XCTAssertEqual(snap.entries.count, 2, "the twin matched the saved Rayquaza as unchanged")
        XCTAssertEqual(try lib.store.list(account: "Main").scans.count, 2)
        XCTAssertEqual(try queue.list().manifests.count, 0, "the stationed card is not actionable, so nothing is left")
    }

    /// 4. (the reviewer's reproduction) a copy of a screenshot in a batch that was never saved is not "already imported".
    func testTheLedgerRecordsOnlyWhatWasSaved() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let older = try stage([try nickit], origin: .shareExtension, now: t0)
        let newer = try stage([try nickit, try rayquaza], origin: .shareExtension, now: t0.addingTimeInterval(60))
        guard case .saved = try importer.save(try review(newer), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertNil(try lib.current(account: "Main")?.entries.first { $0.row.name == "Nickit" }, "Nickit was not saved")
        try importer.readAll(batch: older.batchId, engine: sharedEngine)
        let m = try queue.load(older.batchId)
        XCTAssertNil(m.items[0].alreadyImported, "a never-saved screenshot was marked already imported")
        XCTAssertEqual(rowNames(try importer.prepareReview(batch: older.batchId, engine: sharedEngine)), ["Nickit 212"])
        // a copy IN the batch of one that was saved is recorded; a screenshot the person left out is not
        let both = try stage([try rayquaza, try retake(try nickit)])
        let p = try review(both)
        guard case .saved = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertNotNil(queue.ledger().savedAt(account: "Main", keys: both.items[1].keys))
    }

    /// 5. A reader fault is retryable and a re-share while it is failed is the retry.
    func testAReaderFaultIsRetryableAndAReshareWhileFailedIsReadNormally() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let m = try stage([try nickit], now: t0)
        importer = ScreenshotImporter(queue: queue, library: lib) { _, _ in .fault("recogniser failed") }
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        var item = try queue.load(m.batchId).items[0]
        XCTAssertEqual(item.state, .failed); XCTAssertTrue(item.canRetry)
        // shared again while the old one is failed: not a copy, it is read on its own
        importer = makeImporter()
        let again = try stage([try nickit], origin: .shareExtension, now: t0.addingTimeInterval(60))
        try importer.readAll(batch: again.batchId, engine: sharedEngine)
        item = try queue.load(again.batchId).items[0]
        XCTAssertNil(item.duplicateOf); XCTAssertEqual(item.state, .read)
        XCTAssertEqual(rowNames(try importer.prepareReview(batch: again.batchId, engine: sharedEngine)), ["Nickit 212"])
    }

    /// 6. Screenshots that were copies of a batch that went away are read without anyone asking.
    func testACopyOnlyBatchIsReadAgainWhenTheBatchItCopiedIsDiscarded() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try stage([try nickit], origin: .shareExtension, now: t0)
        let second = try stage([try nickit], origin: .shareExtension, now: t0.addingTimeInterval(60))
        try importer.readAll(batch: second.batchId, engine: sharedEngine)
        XCTAssertTrue(try queue.load(second.batchId).isRead, "all copies: nothing to read, so it looks finished")
        XCTAssertEqual(try importer.prepareAll().map(\.batchId), [first.batchId], "only the older batch has anything to read")
        try importer.discard(batch: first.batchId)
        let waiting = try importer.prepareAll()
        XCTAssertEqual(waiting.map(\.batchId), [second.batchId], "it has something to read now")
        XCTAssertEqual(waiting[0].items[0].state, .pending)
        try importer.readAll(batch: second.batchId, engine: sharedEngine)
        XCTAssertEqual(rowNames(try importer.prepareReview(batch: second.batchId, engine: sharedEngine)), ["Nickit 212"])
    }

    /// 12. One unreadable scan file does not make every later import refuse to save.
    func testAnUnreadableScanFileOnlyBlocksTheImportItCouldBe() throws {
        let first = try stage([try nickit])
        guard case .saved = try importer.save(try review(first), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        // damage that scan's file (text added to the end: it no longer decodes, but it still says which import it was)
        let account = dir.appendingPathComponent("boxes/Main")
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: account.path).first { name in
            name.hasSuffix(".json") && (try? Data(contentsOf: account.appendingPathComponent(name)))?.range(of: Data(first.signature.utf8)) != nil
        })
        let handle = try FileHandle(forWritingTo: account.appendingPathComponent(file)); try handle.seekToEnd(); try handle.write(contentsOf: Data("{{garbage".utf8)); try handle.close()
        XCTAssertEqual(try lib.store.list(account: "Main").unreadable, [file])
        // another import is not refused for it...
        XCTAssertEqual(lib.scanAlreadySaved(account: "Main", signature: "import:some-other-batch"), .notSaved)
        let second = try stage([try rayquaza])
        guard case .saved = try importer.save(try review(second), resolutions: [:], engine: sharedEngine) else { return XCTFail("a damaged earlier scan blocked a new save") }
        // ...but the batch that damaged file could be IS: nothing is saved over a possible earlier save
        XCTAssertEqual(lib.scanAlreadySaved(account: "Main", signature: first.signature), .unknown)
    }

    // MARK: review round 2

    func testRenameReuseAfterFiftyRenamesIsStillAmbiguous() throws {
        try lib.createAccount("O0")
        for i in 0..<50 { try lib.renameAccount(from: "O\(i)", to: "O\(i + 1)") }
        let m = try stage([try nickit])
        let at = lib.store.renameCount
        try lib.renameAccount(from: "Main", to: "Renamed")
        XCTAssertEqual(lib.store.renameCount, (at ?? 0) + 1, "the sequence keeps counting past the 50 the history holds")
        try lib.createAccount("Main")
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .ambiguous(old: "Main", renamedTo: "Renamed"), "the batch must not go into the NEW account")
    }

    func testABindingOlderThanTheOldestRenameOnRecordIsAskedAbout() throws {
        let m = try stage([try nickit])
        for i in 0..<55 { try lib.createAccount("T\(i)"); try lib.renameAccount(from: "T\(i)", to: "U\(i)") }   // 55 renames: the oldest five are gone from the history
        guard case .unconfirmed = importer.owner(of: try queue.load(m.batchId)) else { return XCTFail("\(importer.owner(of: try queue.load(m.batchId)))") }
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertThrowsError(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)) { guard case .accountUnconfirmed = $0 as? ScreenshotImporter.Failure else { return XCTFail("\($0)") } }
        try importer.assign(batch: m.batchId, to: "Main")   // the person says
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .account("Main"))
    }

    func testAnAccountDeletedAndMadeAgainUnderTheSameNameIsAskedAbout() throws {
        let m = try stage([try nickit])
        try lib.store.deleteAccount("Main")
        try lib.createAccount("Main")
        guard case .unconfirmed = importer.owner(of: try queue.load(m.batchId)) else { return XCTFail("\(importer.owner(of: try queue.load(m.batchId)))") }
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertThrowsError(try importer.prepareReview(batch: m.batchId, engine: sharedEngine))
        XCTAssertNil(try lib.current(account: "Main"))
        // a rename alone does not trigger it: the folder keeps its birth date
        let ok = try stage([try rayquaza], account: "Main")
        try lib.renameAccount(from: "Main", to: "Moved")
        XCTAssertEqual(importer.owner(of: try queue.load(ok.batchId)), .account("Moved"))
    }

    func testAlreadyImportedSurvivesARenameOfTheBatchAccount() throws {
        let first = try stage([try nickit])
        guard case .saved = try importer.save(try review(first), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        let again = try stage([try nickit])
        try importer.readAll(batch: again.batchId, engine: sharedEngine)
        XCTAssertNotNil(try queue.load(again.batchId).items[0].alreadyImported, "held back before the rename")
        try lib.renameAccount(from: "Main", to: "Renamed")
        try importer.readAll(batch: again.batchId, engine: sharedEngine)   // prepared again, as the app does
        XCTAssertNotNil(try queue.load(again.batchId).items[0].alreadyImported, "and after it")
        XCTAssertThrowsError(try importer.prepareReview(batch: again.batchId, engine: sharedEngine)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .nothingToImport) }
    }

    func testQueuedBatchesAreComparedByTheirOwnersNowNotByTheNamesTheyRecorded() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try stage([try nickit], origin: .shareExtension, now: t0)
        try lib.renameAccount(from: "Main", to: "Renamed")
        let second = try stage([try nickit], account: "Renamed", now: t0.addingTimeInterval(60))   // recorded under the new name
        XCTAssertNotNil(try importer.prepare(batch: second.batchId).items[0].duplicateOf, "the same account, though the two batches recorded different names")
        XCTAssertEqual(importer.owner(of: try queue.load(first.batchId)), .account("Renamed"))
    }

    func testAKeptRepeatAfterItsSourceWasSavedIsAnExactMatchNotAHold() throws {
        let m = try stage([try rayquaza, try rayquazaFainted])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        guard case .saved = try importer.save(try importer.prepareReview(batch: m.batchId, engine: sharedEngine), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        let it = try XCTUnwrap(try queue.load(m.batchId).items.first)
        XCTAssertNil(it.repeatOf); XCTAssertFalse(it.heldBack); XCTAssertFalse(it.hasHold)
        _ = try importer.prepareAll()   // what the app runs on coming to the front: the hold does not come back
        XCTAssertFalse(try queue.load(m.batchId).items[0].hasHold)
        let p = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(p.plan.same.count, 1, "it is the saved Pokémon, unchanged, as Auto Scan would take it"); XCTAssertTrue(p.plan.new.isEmpty)
    }

    func testRereadingAfterARetryNeverDropsAHoldTheUserHasNotAnswered() throws {
        let m = try stage([try rayquaza, try rayquazaFainted])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(try queue.load(m.batchId).items[1].repeatOf, m.items[0].id)
        // the first one is retried and fails this time: the second must stay held
        failing = [m.items[0].id]
        try queue.update(m.batchId) { $0.items[0].state = .failed }   // it had failed on the retry
        let again = try importer.retry(batch: m.batchId, item: m.items[0].id)
        XCTAssertEqual(again.items[1].repeatOf, m.items[0].id, "retrying the source leaves the hold")
        try importer.readAll(batch: m.batchId, engine: sharedEngine)   // the source fails again
        XCTAssertEqual(try queue.load(m.batchId).items[1].repeatOf, m.items[0].id, "still held: the person has not answered")
        XCTAssertTrue(try queue.load(m.batchId).items[1].heldBack)
    }

    func testAnInterruptedReadGivesItsAttemptBack() throws {
        let m = try stage([try nickit])
        var during: (batch: String, item: String)?
        importer = ScreenshotImporter(queue: queue, library: lib) { [unowned self] url, _ in
            during = importer.inFlight
            importer.refundInterruptedRead()   // the system took the time away mid-read
            return try Self.vision.read(contentsOf: url)
        }
        XCTAssertNil(importer.inFlight)
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(during?.item, m.items[0].id)
        XCTAssertNil(importer.inFlight, "nothing is in flight once the read is done")
        // a read cut off for good (never finished) is the one that counts: attempts stays at 1 while pending
        var cut = try stage([try rayquaza], now: Date(timeIntervalSinceNow: 5))
        let p0 = try queue.load(cut.batchId)
        importer = ScreenshotImporter(queue: queue, library: lib) { _, _ in throw StillImageError.cannotDecode }
        _ = try importer.readNext(batch: p0.batchId, engine: sharedEngine)
        cut = try queue.load(cut.batchId)
        XCTAssertEqual(cut.items[0].attempts, 1)
    }

    func testAPhotoWithCameraMetadataIsStagedAndTheReaderSaysItIsNotAScreen() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.4, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let m = try stage([out as Data])
        XCTAssertEqual(m.items[0].width, 3000)
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(try queue.load(m.batchId).items[0].state, .unsupported)
    }

    func testALoneHeldBackLeftoverCanBeDiscardedAndTheBatchGoesWithIt() throws {
        let first = try stage([try nickit])
        guard case .saved = try importer.save(try review(first), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        let again = try stage([try nickit])
        try importer.readAll(batch: again.batchId, engine: sharedEngine)
        XCTAssertTrue(try queue.load(again.batchId).items[0].heldBack)
        try importer.discardItem(batch: again.batchId, item: again.items[0].id)
        XCTAssertEqual(try queue.list().manifests.count, 0)
    }

    // MARK: review round 3

    /// 1. (the reviewer's reproduction) The source of a held-back repeat is an unsure row the person LEAVES OUT: the repeat must not stay held against a screenshot that is gone.
    func testALeftOutSourceDoesNotLeaveItsRepeatHeldAgainstAScreenshotThatIsGone() throws {
        let saved = try stage([try rayquaza])
        guard case .saved = try importer.save(try review(saved), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        _ = try lib.mutate(account: "Main", reason: .edit, note: "lower CP") { e in var e = e; e[0].row.cp = 3900; return e }
        try FileManager.default.removeItem(at: queue.root.appendingPathComponent("ledger.json"))   // the box was filled some other way
        let m = try stage([try rayquaza, try rayquazaFainted], now: Date().addingTimeInterval(5))
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(try queue.load(m.batchId).items[1].repeatOf, m.items[0].id, "held as a repeat of the first")
        let p = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        let u = try XCTUnwrap(p.plan.unsure.first)
        guard case .saved = try importer.save(p, resolutions: [u.scanned: .leaveOut], engine: sharedEngine) else { return XCTFail() }
        let left = try queue.load(m.batchId)
        let ids = Set(left.items.map(\.id))
        XCTAssertFalse(left.items.contains { $0.repeatOf.map { !ids.contains($0) } ?? false }, "held back as a repeat of a screenshot that is no longer in the batch")
        XCTAssertFalse(left.items.contains { $0.heldBack })
    }

    func testAStaleHoldIsLiftedWhenTheBatchIsLookedAt() throws {
        let m = try stage([try rayquaza, try rayquazaFainted])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try queue.update(m.batchId) { $0.items[1].repeatOf = "an-id-that-is-not-there" }
        XCTAssertTrue(try queue.load(m.batchId).items[1].heldBack)
        XCTAssertNil(try importer.prepare(batch: m.batchId).items[1].repeatOf)
        // and with the engine, the repeat check runs again for a batch read in full: a real repeat is held again, a false one is not
        try queue.update(m.batchId) { $0.items[1].repeatOf = nil }
        XCTAssertEqual(try importer.prepare(batch: m.batchId, engine: sharedEngine).items[1].repeatOf, m.items[0].id)
    }

    /// 2. The refund is real: while the read is in progress the attempt is back to what it was.
    func testRefundingAnInterruptedReadLowersTheAttemptCountOnDisk() throws {
        let m = try stage([try nickit])
        var before = -1, after = -1
        importer = ScreenshotImporter(queue: queue, library: lib) { [unowned self] url, _ in
            before = try queue.load(m.batchId).items[0].attempts
            importer.refundInterruptedRead()
            after = try queue.load(m.batchId).items[0].attempts
            return try Self.vision.read(contentsOf: url)
        }
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(before, 1); XCTAssertEqual(after, 0)
    }

    /// 3. A failed ledger write keeps the batch (with what the save wrote down) and the next look finishes it, without saving again.
    func testAFailedLedgerWriteKeepsTheBatchAndIsRetriedWithoutSavingAgain() throws {
        let m = try stage([try nickit, try rayquaza])
        let p = try review(m)
        struct DiskFull: Error {}
        queue.ledgerFailure = { throw DiskFull() }
        importer = makeImporter()
        guard case .saved = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertEqual(try lib.history(account: "Main").count, 1)
        let kept = try queue.load(m.batchId)
        XCTAssertNotNil(kept.pendingSave); XCTAssertEqual(kept.items.count, 2, "not retired")
        XCTAssertEqual(kept.pendingSave?.account, "Main")
        XCTAssertTrue(queue.ledger().entries.isEmpty)
        // the disk is fine again; the app looks at the queue
        queue.ledgerFailure = nil
        importer = makeImporter()
        _ = try importer.prepareAll()
        XCTAssertThrowsError(try queue.load(m.batchId), "retired now")
        XCTAssertNotNil(queue.ledger().savedAt(account: "Main", keys: m.items[0].keys))
        XCTAssertEqual(try lib.history(account: "Main").count, 1, "the box was not written again")
    }

    /// 4. Stamps: a batch the app has not stamped is never followed through renames to another account without asking.
    func testAnUnstampedBatchIsNotFollowedThroughARename() throws {
        let b = try queue.beginBatch(origin: .shareExtension, account: "Main")   // no rename mark, no birth date: a share the app has not seen
        try b.add(data: try nickit)
        let m = try b.commit()
        XCTAssertEqual(importer.owner(of: m), .account("Main"), "its own name, as it stands")
        try lib.renameAccount(from: "Main", to: "Renamed")
        guard case .unconfirmed = importer.owner(of: try queue.load(m.batchId)) else { return XCTFail("followed the rename: \(importer.owner(of: try queue.load(m.batchId)))") }
        // first sight stamps it while the name is still the account's own
        let fresh = try queue.beginBatch(origin: .shareExtension, account: "Renamed"); try fresh.add(data: try rayquaza)
        let n = try fresh.commit()
        let stamped = try importer.prepare(batch: n.batchId)
        XCTAssertNotNil(stamped.renameMark); XCTAssertNotNil(stamped.accountBorn)
        try lib.renameAccount(from: "Renamed", to: "Again")
        XCTAssertEqual(importer.owner(of: try queue.load(n.batchId)), .account("Again"), "stamped: followed")
    }

    func testSeveralRenamesAfterABatchWasBoundAreFollowedAndAReusedNameIsStillAsked() throws {
        let m = try stage([try nickit])
        try lib.renameAccount(from: "Main", to: "B")
        try lib.renameAccount(from: "B", to: "C")
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .account("C"))
        try lib.createAccount("B")
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .account("C"), "a middle name being reused does not matter: the chain ends at C")
        try lib.createAccount("Main")
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .ambiguous(old: "Main", renamedTo: "C"), "but the name it was made for being reused does")
    }

    func testAnUnreadableRenameCounterNeverSendsTheSequenceBackAndEarlierStampsAreAsked() throws {
        let m = try stage([try nickit])
        for i in 0..<5 { try lib.createAccount("T\(i)"); try lib.renameAccount(from: "T\(i)", to: "U\(i)") }
        let before = try XCTUnwrap(lib.store.renameCount)
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("boxes/.renames-recorded"))
        XCTAssertNil(lib.store.renameCount)
        // nothing can be followed while it is unreadable: asked, not "gone" or "unknown", and assigning says the record is the problem
        guard case .unconfirmed = importer.owner(of: try queue.load(m.batchId)) else { return XCTFail("\(importer.owner(of: try queue.load(m.batchId)))") }
        XCTAssertThrowsError(try importer.assign(batch: m.batchId, to: "Main")) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .accountUnknown) }
        // the next rename recovers it, above everything before
        try lib.createAccount("X"); try lib.renameAccount(from: "X", to: "Y")
        XCTAssertGreaterThan(try XCTUnwrap(lib.store.renameCount), before)
        guard case .unconfirmed = importer.owner(of: try queue.load(m.batchId)) else { return XCTFail("a stamp from before the recovery was trusted") }
        try importer.assign(batch: m.batchId, to: "Main")
        XCTAssertEqual(importer.owner(of: try queue.load(m.batchId)), .account("Main"))
    }

    /// 6 + 7. The message is neutral, and the ledger does not carry into a folder made again under the same name.
    func testAnAccountMadeAgainDoesNotInheritWhatWasSavedIntoTheOldOne() throws {
        let first = try stage([try nickit])
        guard case .saved = try importer.save(try review(first), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        try lib.store.deleteAccount("Main"); Thread.sleep(forTimeInterval: 0.01); try lib.createAccount("Main")
        let again = try stage([try nickit])
        try importer.readAll(batch: again.batchId, engine: sharedEngine)
        XCTAssertEqual(importer.owner(of: try queue.load(again.batchId)), .account("Main"))
        XCTAssertNil(try queue.load(again.batchId).items[0].alreadyImported, "a fresh box does not hold back a screenshot as imported into the deleted one")
        // and an old batch for the old folder is asked about, in words that do not claim what happened
        let old = try stage([try rayquaza], account: "Main")
        try lib.store.deleteAccount("Main"); Thread.sleep(forTimeInterval: 0.01); try lib.createAccount("Main")
        guard case .unconfirmed(_, let why) = importer.owner(of: try queue.load(old.batchId)) else { return XCTFail() }
        XCTAssertFalse(why.contains("deleted")); XCTAssertTrue(why.contains("looks different"), why)
    }

    /// 8. Choosing the account recomputes what is already imported for it.
    func testChoosingTheAccountWorksOutAlreadyImportedAgainstIt() throws {
        let first = try stage([try nickit])
        guard case .saved = try importer.save(try review(first), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        try lib.createAccount("Alt")
        let b = try queue.beginBatch(origin: .shareExtension, account: nil); try b.add(data: try nickit)
        let m = try b.commit()
        XCTAssertNil(try importer.assign(batch: m.batchId, to: "Alt").items[0].alreadyImported, "Alt never had it")
        let after = try importer.assign(batch: m.batchId, to: "Main")
        XCTAssertNotNil(after.items[0].alreadyImported, "Main did: worked out again on choosing it")
    }

    /// The crash path with no record of what the save held (a save made before that was written down): nothing is invented.
    func testRecoveryWithNoRecordOfTheSaveRecordsNothingAndKeepsNothingRead() throws {
        let m = try stage([try nickit, try rayquaza])
        let p = try review(m)
        let entries = try BoxMerge.apply(p.plan, resolutions: [:], keepGone: [], to: p.base, engine: sharedEngine)
        _ = try lib.commitScan(p.outcome.scan, entries: entries, account: "Main", scanDate: p.plan.scanDate, source: "screenshot import", kind: .partial, note: "old build", expectedCurrentSeq: .some(p.boxSeq), sourceSignature: m.signature)
        let again = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        guard case .alreadySaved = try importer.save(again, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertThrowsError(try queue.load(m.batchId))
        XCTAssertTrue(queue.ledger().entries.isEmpty)
        XCTAssertEqual(try lib.history(account: "Main").count, 1)
    }

    /// 10. A photo from a camera (a screenshot scaled into a noisy 4:3 frame) is never a guessed Pokémon.
    func testACameraStylePhotoOfAScreenshotGivesNoPokemon() throws {
        let src = try StillImage.decode(contentsOf: Self.fixtures.appendingPathComponent("normal-nickit-212.png"))
        var seed: UInt64 = 12345
        var canvas = RGBAImage(width: 2000, height: 1500)
        for i in stride(from: 0, to: canvas.bytes.count, by: 4) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = UInt8(truncatingIfNeeded: seed >> 56)
            canvas.bytes[i] = v / 2 + 40; canvas.bytes[i + 1] = v / 3 + 60; canvas.bytes[i + 2] = v / 2 + 30; canvas.bytes[i + 3] = 255
        }
        // the screenshot, shrunk to 40% and put in the middle of the frame
        let tw = src.width * 2 / 5, th = src.height * 2 / 5, ox = (2000 - tw) / 2, oy = (1500 - th) / 2
        for y in 0..<th { for x in 0..<tw {
            let s = ((y * 5 / 2) * src.width + (x * 5 / 2)) * 4, d = ((oy + y) * 2000 + ox + x) * 4
            canvas.bytes[d] = src.bytes[s]; canvas.bytes[d + 1] = src.bytes[s + 1]; canvas.bytes[d + 2] = src.bytes[s + 2]
        } }
        let m = try stage([try png(canvas)])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        let item = try queue.load(m.batchId).items[0]
        XCTAssertTrue(item.state == .unsupported || item.state == .unreadable, "\(item.state) \(item.detail ?? "")")
        XCTAssertNil(item.reading.flatMap { _ in StillImport.title(of: item) }, "no Pokémon was named")
        XCTAssertThrowsError(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .nothingToImport) }
    }

    // MARK: review round 4

    func retake(_ data: Data, _ k: UInt8) throws -> Data {
        var img = try StillImage.decode(data: data); img.bytes[0] = img.bytes[0] &+ k; return try png(img)
    }

    /// D1. The ledger write fails and the batch is kept. An answer given meanwhile is not lost, and nothing is done to the batch until the last save is finished.
    func testAnAnswerGivenWhileTheLastSaveIsUnfinishedIsRefusedThenKept() throws {
        let m = try stage([try nickit, try retake(try nickit, 7)])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertTrue(try queue.load(m.batchId).items[1].heldBack)
        struct DiskFull: Error {}
        queue.ledgerFailure = { throw DiskFull() }; importer = makeImporter()
        guard case .saved = try importer.save(try importer.prepareReview(batch: m.batchId, engine: sharedEngine), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertNotNil(try queue.load(m.batchId).pendingSave)
        // while the ledger still cannot be written, nothing may be done to the batch
        XCTAssertThrowsError(try importer.setIncluded(batch: m.batchId, item: m.items[1].id, true)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .finishingLastSave) }
        XCTAssertThrowsError(try importer.prepareReview(batch: m.batchId, engine: sharedEngine)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .finishingLastSave) }
        XCTAssertNotNil(try? queue.load(m.batchId))
        // the disk recovers: the answer finishes the last save first, and is kept
        queue.ledgerFailure = nil; importer = makeImporter()
        try importer.setIncluded(batch: m.batchId, item: m.items[1].id, true)
        let left = try queue.load(m.batchId)
        XCTAssertNil(left.pendingSave); XCTAssertEqual(left.items.map(\.id), [m.items[1].id], "the answered screenshot stays for a later save")
        XCTAssertEqual(left.items[0].includeAnyway, true)
        let p = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(p.rowItems, [m.items[1].id])
    }

    /// D1 (retire keeps what the save did not contain, and drops what the person left out).
    func testRetireKeepsAnAnsweredIncludeThatWasNotInTheSaveAndDropsALeftOutOne() throws {
        var m = try stage([try nickit, try rayquaza, try rayquazaFainted])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        m = try queue.update(m.batchId) { $0.items[2].includeAnyway = true }   // answered after the save was written down
        let left = try XCTUnwrap(try queue.retire(m.batchId, saved: [m.items[0].id], dropped: [m.items[1].id]))
        XCTAssertEqual(left.items.map(\.id), [m.items[2].id])
    }

    /// D2. A batch whose save is unfinished is not saved again into another account by choosing one, or after a rename and reuse of its name.
    func testAnUnfinishedSaveIsNeverSavedAgainIntoAnotherAccount() throws {
        try lib.createAccount("Alt")
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        struct DiskFull: Error {}
        queue.ledgerFailure = { throw DiskFull() }; importer = makeImporter()
        guard case .saved = try importer.save(try importer.prepareReview(batch: m.batchId, engine: sharedEngine), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertThrowsError(try importer.assign(batch: m.batchId, to: "Alt")) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .finishingLastSave) }
        queue.ledgerFailure = nil; importer = makeImporter()
        // the batch is finished against the account the save went into; there is nothing left to assign
        XCTAssertThrowsError(try importer.assign(batch: m.batchId, to: "Alt"))
        XCTAssertThrowsError(try queue.load(m.batchId))
        XCTAssertEqual(try lib.history(account: "Alt").count, 0, "the same Pokémon went into a second box")
        XCTAssertEqual(try lib.history(account: "Main").count, 1)
    }

    func testAnUnfinishedSaveIsFinishedAgainstItsOwnAccountAfterARenameAndReuseOfTheName() throws {
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        struct DiskFull: Error {}
        queue.ledgerFailure = { throw DiskFull() }; importer = makeImporter()
        guard case .saved = try importer.save(try importer.prepareReview(batch: m.batchId, engine: sharedEngine), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        queue.ledgerFailure = nil; importer = makeImporter()
        try lib.renameAccount(from: "Main", to: "Moved"); try lib.createAccount("Main")   // the owner is ambiguous now
        guard case .ambiguous = importer.owner(of: try queue.load(m.batchId)) else { return XCTFail() }
        _ = try importer.prepareAll(engine: sharedEngine)
        XCTAssertThrowsError(try queue.load(m.batchId), "finished")
        XCTAssertNotNil(queue.ledger().savedAt(account: "Moved", keys: m.items[0].keys), "recorded against the account the save went into")
        XCTAssertNil(queue.ledger().savedAt(account: "Main", keys: m.items[0].keys))
        XCTAssertEqual(try lib.history(account: "Moved").count, 1); XCTAssertEqual(try lib.history(account: "Main").count, 0)
    }

    func testANoteForASaveThatNeverReachedTheBoxIsClearedAndDoesNotBlockTheBatch() throws {
        let m = try stage([try nickit])
        let p = try review(m)
        struct Boom: Error {}
        XCTAssertThrowsError(try importer.save(p, resolutions: [:], engine: sharedEngine, commitFailure: { throw Boom() }))
        XCTAssertNotNil(try queue.load(m.batchId).pendingSave, "written before the attempt")
        let again = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)   // settles: the box has nothing of it, so the note goes
        XCTAssertNil(try queue.load(m.batchId).pendingSave)
        guard case .saved = try importer.save(again, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
    }

    /// L1. A lifted hold does not come back against the other repeats.
    func testALiftedHoldIsNotReplacedByAHoldAmongTheRemainingRepeats() throws {
        let m = try stage([try nickit, try retake(try nickit, 7), try retake(try nickit, 13)])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(try queue.load(m.batchId).items.map(\.heldBack), [false, true, true])
        guard case .saved = try importer.save(try importer.prepareReview(batch: m.batchId, engine: sharedEngine), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        _ = try importer.prepareAll(engine: sharedEngine)
        let left = try queue.load(m.batchId)
        XCTAssertEqual(left.items.count, 2)
        XCTAssertTrue(left.items.allSatisfy { !$0.heldBack && $0.repeatOf == nil && $0.holdLifted == true }, "held again against each other: \(left.items.map(\.repeatOf))")
        // a retried screenshot is new again
        try queue.update(m.batchId) { $0.items[0].state = .failed }
        XCTAssertNil(try importer.retry(batch: m.batchId, item: m.items[1].id).items[0].holdLifted)
    }

    // MARK: review round 5

    struct DiskFull: Error {}
    struct Cut: Error {}

    func saveWithLedgerFailing(_ m: ImportManifest) throws {
        queue.ledgerFailure = { throw DiskFull() }; importer = makeImporter()
        guard case .saved = try importer.save(try importer.prepareReview(batch: m.batchId, engine: sharedEngine), resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertNotNil(try queue.load(m.batchId).pendingSave)
    }

    /// 1. A batch whose last save can never be finished can always be discarded, and discarding never saves anything.
    func testDiscardWorksWhateverStateTheLastSaveIsIn() throws {
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try saveWithLedgerFailing(m)   // the ledger keeps failing
        try importer.discard(batch: m.batchId)
        XCTAssertThrowsError(try queue.load(m.batchId))
        XCTAssertEqual(try lib.history(account: "Main").count, 1, "a discard saves nothing")
        XCTAssertTrue(queue.ledger().entries.isEmpty, "at worst a ledger entry is missing")
    }

    func testDiscardTriesToFinishTheLastSaveOnceFirst() throws {
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try saveWithLedgerFailing(m)
        queue.ledgerFailure = nil; importer = makeImporter()
        try importer.discard(batch: m.batchId)
        XCTAssertNotNil(queue.ledger().savedAt(account: "Main", keys: m.items[0].keys), "the one attempt recorded what was saved")
    }

    /// N1. The box file of the save is unreadable: it can never be finished, and can still be discarded.
    func testAnUnreadableBoxFileDoesNotTrapTheBatch() throws {
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        let p = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        XCTAssertThrowsError(try importer.save(p, resolutions: [:], engine: sharedEngine, afterCommit: { throw Cut() }))
        let boxDir = try lib.store.accountDirectory("Main", create: false).appendingPathComponent("box")
        for f in try FileManager.default.contentsOfDirectory(atPath: boxDir.path) where f.hasSuffix(".json") && !f.contains("advice") { try Data("{not json".utf8).write(to: boxDir.appendingPathComponent(f)) }
        importer = makeImporter()
        for _ in 0..<3 { _ = try importer.prepareAll(engine: sharedEngine) }
        XCTAssertNotNil(try queue.load(m.batchId).pendingSave, "cannot be finished while the box cannot be read")
        XCTAssertThrowsError(try importer.setIncluded(batch: m.batchId, item: m.items[0].id, true)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .finishingLastSave) }
        XCTAssertNoThrow(try importer.discard(batch: m.batchId))
        XCTAssertThrowsError(try queue.load(m.batchId))
    }

    /// N2. The folder's birth date changed (restored, moved by hand): the save is still found, by its signature, in whichever account holds it.
    func testAFolderWhoseBirthDateChangedIsFoundBySignature() throws {
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try saveWithLedgerFailing(m)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: try lib.store.accountDirectory("Main", create: false).path)
        queue.ledgerFailure = nil; importer = makeImporter()
        _ = try importer.prepareAll(engine: sharedEngine)
        XCTAssertThrowsError(try queue.load(m.batchId), "finished")
        XCTAssertNotNil(queue.ledger().savedAt(account: "Main", keys: m.items[0].keys))
        XCTAssertEqual(try lib.history(account: "Main").count, 1)
    }

    /// N3. The account the save went into is gone: no way to finish, and the way out is discarding. Choosing another account is refused, so nothing goes into a second box.
    func testADeletedAccountLeavesDiscardAsTheWayOut() throws {
        try lib.createAccount("Alt")
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try saveWithLedgerFailing(m)
        try lib.store.deleteAccount("Main")
        queue.ledgerFailure = nil; importer = makeImporter()
        _ = try importer.prepareAll(engine: sharedEngine)
        XCTAssertThrowsError(try importer.assign(batch: m.batchId, to: "Alt")) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .finishingLastSave) }
        XCTAssertEqual(try lib.history(account: "Alt").count, 0)
        try importer.discard(batch: m.batchId)
        XCTAssertThrowsError(try queue.load(m.batchId))
    }

    /// N4. A share of the same screenshot is not a copy of a batch whose save is unfinished.
    func testAReshareIsNotBlockedBehindABatchWithAnUnfinishedSave() throws {
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try saveWithLedgerFailing(m)
        let n = try stage([try nickit], now: Date().addingTimeInterval(5))
        try importer.readAll(batch: n.batchId, engine: sharedEngine)
        XCTAssertNil(try queue.load(n.batchId).items[0].duplicateOf)
        XCTAssertEqual(try queue.load(n.batchId).items[0].state, .read)
    }

    /// N9. The save's note is there, the commit did not happen, and an unreadable scan file carries the signature: it cannot be told, and can be discarded.
    func testAnUnreadableScanFileCarryingTheSignatureDoesNotTrapTheBatch() throws {
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        let p = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        struct Boom: Error {}
        XCTAssertThrowsError(try importer.save(p, resolutions: [:], engine: sharedEngine, commitFailure: { throw Boom() }))
        try Data("{\"sourceSignature\":\"\(m.signature)\" torn".utf8).write(to: try lib.store.accountDirectory("Main", create: false).appendingPathComponent("zz-torn.json"))
        _ = try importer.prepareAll(engine: sharedEngine)
        XCTAssertNotNil(try queue.load(m.batchId).pendingSave)
        XCTAssertNoThrow(try importer.discard(batch: m.batchId))
    }

    /// 2. Clean-up finishes an unfinished save before it removes the batch.
    func testCleanupFinishesAnUnfinishedSaveBeforeRemovingTheBatch() throws {
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try saveWithLedgerFailing(m)
        queue.ledgerFailure = nil; importer = makeImporter()
        queue.markSeen([m.batchId], now: Date().addingTimeInterval(-15 * 24 * 3600))   // shown, then left for fifteen days
        let report = importer.cleanup()
        XCTAssertEqual(report.removedAbandoned + report.removedSaved, 0, "finished by the save recovery, not removed as abandoned")
        XCTAssertThrowsError(try queue.load(m.batchId))
        XCTAssertNotNil(queue.ledger().savedAt(account: "Main", keys: m.items[0].keys), "the ledger entry was written before the batch went")
    }

    /// 3. Discarding one screenshot lifts the hold on the ones that were held against it, and they are not held against each other again.
    func testDiscardingAScreenshotDoesNotLeaveItsRepeatsHeldAgainstEachOther() throws {
        let m = try stage([try nickit, try retake(try nickit, 7), try retake(try nickit, 13)])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        XCTAssertEqual(try queue.load(m.batchId).items.map(\.heldBack), [false, true, true])
        try importer.discardItem(batch: m.batchId, item: m.items[0].id)
        _ = try importer.prepareAll(engine: sharedEngine)
        let left = try queue.load(m.batchId)
        XCTAssertEqual(left.items.count, 2)
        XCTAssertTrue(left.items.allSatisfy { !$0.heldBack && $0.holdLifted == true }, "\(left.items.map(\.repeatOf))")
    }

    /// 4. discardItem and retry deal with an unfinished save as the others do (S5, S6).
    func testDiscardItemFinishesTheLastSaveFirst() throws {
        let m = try stage([try nickit, try retake(try nickit, 7)])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try saveWithLedgerFailing(m)
        queue.ledgerFailure = nil; importer = makeImporter()
        try importer.discardItem(batch: m.batchId, item: m.items[1].id)
        XCTAssertThrowsError(try queue.load(m.batchId), "the saved screenshot was retired with the last save, then the other went")
        XCTAssertNotNil(queue.ledger().savedAt(account: "Main", keys: m.items[0].keys), "and what was saved was recorded first")
    }

    func testRetryIsRefusedWhileTheLastSaveIsUnfinished() throws {
        let m = try stage([try nickit, try rayquaza])
        failing = [m.items[1].id]
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        try saveWithLedgerFailing(m)
        failing = []
        XCTAssertThrowsError(try importer.retry(batch: m.batchId, item: m.items[1].id)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .finishingLastSave) }
        XCTAssertEqual(try queue.load(m.batchId).items.first { $0.id == m.items[1].id }?.state, .failed, "untouched")
    }

    /// A3 + N8. A review that was open when the account name changed meaning is not saved into the new account of that name, and a second tap while the ledger fails is not
    /// reported as saved.
    func testASecondSaveWhileTheLastSaveIsUnfinishedIsRefusedAndNeverGoesToTheNewSamenameAccount() throws {
        let m = try stage([try nickit])
        try importer.readAll(batch: m.batchId, engine: sharedEngine)
        let p = try importer.prepareReview(batch: m.batchId, engine: sharedEngine)
        queue.ledgerFailure = { throw DiskFull() }; importer = makeImporter()
        guard case .saved = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail() }
        XCTAssertThrowsError(try importer.save(p, resolutions: [:], engine: sharedEngine)) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .finishingLastSave) }
        XCTAssertEqual(try lib.history(account: "Main").count, 1)
        // the ledger recovers while the account is renamed and its name used again: the old review finishes the save against the account it went into
        queue.ledgerFailure = nil; importer = makeImporter()
        try lib.renameAccount(from: "Main", to: "Moved"); try lib.createAccount("Main")
        guard case .alreadySaved = try importer.save(p, resolutions: [:], engine: sharedEngine) else { return XCTFail("saved again") }
        XCTAssertEqual(try lib.history(account: "Main").count, 0, "nothing went into the new account called Main")
        XCTAssertEqual(try lib.history(account: "Moved").count, 1)
        XCTAssertNotNil(queue.ledger().savedAt(account: "Moved", keys: m.items[0].keys)); XCTAssertNil(queue.ledger().savedAt(account: "Main", keys: m.items[0].keys))
    }

    func testChoosingAnAccountThatIsNotThereSaysSo() throws {
        let m = try stage([try nickit])
        XCTAssertThrowsError(try importer.assign(batch: m.batchId, to: "Nowhere")) { XCTAssertEqual($0 as? ScreenshotImporter.Failure, .noSuchAccount("Nowhere")) }
    }
}
