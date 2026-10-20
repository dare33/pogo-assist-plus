import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PogoImport

final class ImportQueueTests: XCTestCase {
    var dir: URL!
    var queue: ImportQueue!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("import-queue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        queue = ImportQueue(root: dir.appendingPathComponent("screenshot-imports"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    // MARK: helpers

    /// A distinct picture per seed, as encoded bytes of the given type, with GPS and EXIF text in it when asked.
    func picture(_ seed: Int, w: Int = 500, h: Int = 900, type: UTType = .png, metadata: Bool = false, orientation: Int? = nil) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.1 + Double(seed % 7) / 10, green: 0.5, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: seed * 3 % 200, y: 100 + seed * 7 % 300, width: 120, height: 60 + seed))   // makes each seed a different picture
        let cg = try XCTUnwrap(ctx.makeImage())
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil))
        var props = [CFString: Any]()
        if metadata {
            props[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W"]
            props[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: "secret place", kCGImagePropertyExifDateTimeOriginal: "2026:10:20 10:00:00"]
            props[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFModel: "iPhone Test", kCGImagePropertyTIFFSoftware: "Camera app"]
        }
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    func makeBatch(_ seeds: [Int], assets: [String?]? = nil, account: String? = "Main", origin: ImportManifest.Origin = .photoPicker, now: Date = Date()) throws -> ImportManifest {
        let b = try queue.beginBatch(origin: origin, account: account, now: now)
        for (i, s) in seeds.enumerated() { try b.add(data: try picture(s), assetId: assets?[i]) }
        return try b.commit(now: now)
    }

    // MARK: staging

    func testStagingKeepsThePixelsAndDropsEveryPieceOfMetadata() throws {
        let b = try queue.beginBatch(origin: .photoPicker, account: "Main")
        let item = try b.add(data: try picture(1, type: .jpeg, metadata: true), assetId: "ASSET-1/L0/001")
        let m = try b.commit()
        let url = queue.stagedURL(batch: m.batchId, item: item)
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(src) as String?, UTType.png.identifier)
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertNil(props[kCGImagePropertyGPSDictionary]); XCTAssertNil(props[kCGImagePropertyTIFFDictionary])
        // ImageIO writes the picture's own size into an EXIF block; nothing else of the original's is there
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        XCTAssertNil(exif[kCGImagePropertyExifUserComment]); XCTAssertNil(exif[kCGImagePropertyExifDateTimeOriginal])
        XCTAssertNil(props[kCGImagePropertyIPTCDictionary]); XCTAssertNil(props[kCGImagePropertyMakerAppleDictionary])
        // and the secret text is not anywhere in the bytes
        let bytes = try Data(contentsOf: url)
        XCTAssertNil(bytes.range(of: Data("secret place".utf8))); XCTAssertNil(bytes.range(of: Data("iPhone Test".utf8)))
        XCTAssertEqual(item.width, 500); XCTAssertEqual(item.height, 900)
        XCTAssertEqual(item.assetId, "ASSET-1/L0/001")
    }

    func testStagingAppliesTheOrientationTagToThePixels() throws {
        // An upright 500 x 900 picture with a red block at its top-left, stored sideways (900 x 500, turned a quarter counter-clockwise) and tagged "right" (6).
        func draw(_ w: Int, _ h: Int, _ body: (CGContext) -> Void) throws -> CGImage {
            let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            body(ctx); return try XCTUnwrap(ctx.makeImage())
        }
        let upright = try draw(500, 900) { c in
            c.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 500, height: 900))
            c.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 900 - 120, width: 120, height: 120))   // top-left in the picture
        }
        let sideways = try draw(900, 500) { c in c.translateBy(x: 900, y: 0); c.rotate(by: .pi / 2); c.draw(upright, in: CGRect(x: 0, y: 0, width: 500, height: 900)) }
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, sideways, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let b = try queue.beginBatch(origin: .photoPicker, account: nil)
        let item = try b.add(data: out as Data)
        XCTAssertEqual(item.width, 500); XCTAssertEqual(item.height, 900)
        let m = try b.commit()
        let staged = try XCTUnwrap(CGImageSourceCreateWithURL(queue.stagedURL(batch: m.batchId, item: item) as CFURL, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(staged, 0, nil))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        let px = try XCTUnwrap(ctx.data).assumingMemoryBound(to: UInt8.self)
        func at(_ x: Int, _ yFromTop: Int) -> (Int, Int, Int) { let i = (yFromTop * cg.width + x) * 4; return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2])) }
        XCTAssertGreaterThan(at(20, 20).0, 200, "the red block is at the top-left of the upright picture"); XCTAssertLessThan(at(20, 20).2, 60)
        XCTAssertLessThan(at(400, 800).0, 100, "and the rest is the blue background")
    }

    func testBytesAndStagedHashesAreRecordedAndAreTheSameForTheSameFile() throws {
        let data = try picture(3)
        let b = try queue.beginBatch(origin: .photoPicker, account: "Main")
        let a = try b.add(data: data), again = try b.add(data: data), other = try b.add(data: try picture(4))
        XCTAssertEqual(a.sourceHash, ImageNormalising.sha256(of: data))
        XCTAssertEqual(a.sourceHash, again.sourceHash); XCTAssertEqual(a.stagedHash, again.stagedHash)
        XCTAssertNotEqual(a.id, again.id)
        XCTAssertNotEqual(a.sourceHash, other.sourceHash)
        // a file on disk hashes to the same value as its bytes
        let f = dir.appendingPathComponent("p.png"); try data.write(to: f)
        XCTAssertEqual(try ImageNormalising.sha256(of: f), a.sourceHash)
        b.abort()
    }

    func testImagesThatAreNotUsableAreRefusedAndTheBatchCarriesOn() throws {
        let b = try queue.beginBatch(origin: .shareExtension, account: "Main")
        XCTAssertThrowsError(try b.add(data: Data("junk".utf8))) { XCTAssertEqual($0 as? ImageStagingError, .cannotDecode) }
        XCTAssertThrowsError(try b.add(data: try picture(5, w: 100, h: 150))) { XCTAssertEqual($0 as? ImageStagingError, .tooSmall(width: 100, height: 150)) }
        XCTAssertThrowsError(try b.add(contentsOf: dir.appendingPathComponent("nope.png")))
        try b.add(data: try picture(6))
        XCTAssertEqual(try b.commit().items.count, 1)
    }

    func testAnEmptyBatchIsNotMadeAndLeavesNothing() throws {
        let b = try queue.beginBatch(origin: .photoPicker, account: "Main")
        XCTAssertThrowsError(try b.commit()) { XCTAssertEqual($0 as? ImportQueueError, .emptyBatch) }
        XCTAssertEqual(try queue.list().manifests.count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: queue.root.path), [])
    }

    func testTheCapsOnABatchAndOnTheQueue() throws {
        let b = try queue.beginBatch(origin: .photoPicker, account: "Main")
        let data = try picture(7)
        for _ in 0..<ImportQueue.maxImagesPerBatch { try b.add(data: data) }
        XCTAssertThrowsError(try b.add(data: data)) { XCTAssertEqual($0 as? ImportQueueError, .tooManyInBatch(max: 50)) }
        b.abort()
        // the queue as a whole: six full batches fit (300), a seventh image does not
        for _ in 0..<6 { let x = try queue.beginBatch(origin: .photoPicker, account: "Main"); for _ in 0..<50 { try x.add(data: data) }; try x.commit() }
        let over = try queue.beginBatch(origin: .photoPicker, account: "Main"); try over.add(data: data)
        XCTAssertThrowsError(try over.commit()) { XCTAssertEqual($0 as? ImportQueueError, .queueFull(max: 300)) }
    }

    // MARK: the manifest

    func testABatchIsVisibleWholeOrNotAtAll() throws {
        let b = try queue.beginBatch(origin: .shareExtension, account: "Main")
        try b.add(data: try picture(8)); try b.add(data: try picture(9))
        XCTAssertEqual(try queue.list().manifests.count, 0, "staged files are not a batch until the manifest is in and the folder is renamed")
        let m = try b.commit()
        let listed = try queue.list().manifests
        XCTAssertEqual(listed.map(\.batchId), [m.batchId])
        XCTAssertEqual(listed[0].items.count, 2)
        for item in listed[0].items { XCTAssertTrue(FileManager.default.fileExists(atPath: queue.stagedURL(batch: m.batchId, item: item).path)) }
        XCTAssertEqual(listed[0].origin, .shareExtension); XCTAssertEqual(listed[0].account, "Main")
        XCTAssertEqual(listed[0].signature, "import:" + m.batchId)
    }

    func testAnUpdateIsAtomicAndAStrayTemporaryFileDoesNotMatter() throws {
        let m = try makeBatch([10, 11])
        // a writer that died after the temporary file and before the rename leaves it behind
        try Data("half".utf8).write(to: queue.batchDirectory(m.batchId).appendingPathComponent(".manifest.json.deadbeef.tmp"))
        let updated = try queue.update(m.batchId) { $0.items[0].state = .failed; $0.items[0].detail = "x" }
        XCTAssertEqual(updated.items[0].state, .failed)
        let again = try queue.load(m.batchId)
        XCTAssertEqual(again.items[0].state, .failed); XCTAssertEqual(again.items[1].state, .pending)
        XCTAssertEqual(again.items, updated.items)
    }

    func testAManifestThatIsDamagedOrFromANewerAppIsReportedNotDropped() throws {
        let good = try makeBatch([12]), damaged = try makeBatch([13]), newer = try makeBatch([14])
        try Data("{ not json".utf8).write(to: queue.batchDirectory(damaged.batchId).appendingPathComponent("manifest.json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: queue.batchDirectory(newer.batchId).appendingPathComponent("manifest.json"))) as? [String: Any])
        json["version"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: queue.batchDirectory(newer.batchId).appendingPathComponent("manifest.json"))
        let l = try queue.list()
        XCTAssertEqual(l.manifests.map(\.batchId), [good.batchId])
        XCTAssertEqual(Set(l.unreadable), [damaged.batchId, newer.batchId])
        XCTAssertThrowsError(try queue.load(newer.batchId)) { XCTAssertEqual($0 as? ImportQueueError, .newerVersion(newer.batchId)) }
    }

    func testTolerantDecodingKeepsWhatIsThereAndReadsUnknownStatesAsPending() throws {
        let m = try makeBatch([15])
        let url = queue.batchDirectory(m.batchId).appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["somethingNew"] = ["x": 1]
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        items[0]["state"] = "holographic"; items[0]["alsoNew"] = true; items[0].removeValue(forKey: "attempts")
        json["items"] = items
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let back = try queue.load(m.batchId)
        XCTAssertEqual(back.items[0].state, .pending); XCTAssertEqual(back.items[0].attempts, 0); XCTAssertEqual(back.items[0].sourceHash, m.items[0].sourceHash)
    }

    func testBatchNamesAreChecked() throws {
        XCTAssertThrowsError(try queue.load("../escape")) { XCTAssertEqual($0 as? ImportQueueError, .badName("../escape")) }
        XCTAssertThrowsError(try queue.remove("a/b"))
        XCTAssertThrowsError(try queue.markDuplicates(".staging-x"))
    }

    // MARK: duplicates

    func testTheSameAssetOrTheSameBytesIsTheSameScreenshotInOneBatch() throws {
        let same = try picture(20)
        let b = try queue.beginBatch(origin: .photoPicker, account: "Main")
        let first = try b.add(data: same, assetId: "A")
        let bytes = try b.add(data: same, assetId: "B")                       // same bytes, other asset id
        let asset = try b.add(data: try picture(21), assetId: "A")            // other bytes, same asset id
        let other = try b.add(data: try picture(22), assetId: "C")
        let m = try b.commit()
        let marked = try queue.markDuplicates(m.batchId)
        XCTAssertNil(marked.item(first.id)?.duplicateOf)
        XCTAssertEqual(marked.item(bytes.id)?.duplicateOf, first.id)
        XCTAssertEqual(marked.item(asset.id)?.duplicateOf, first.id)
        XCTAssertNil(marked.item(other.id)?.duplicateOf)
        XCTAssertEqual(marked.included.count, 0, "nothing is read yet")
        // marking again changes nothing
        XCTAssertEqual(try queue.markDuplicates(m.batchId).items, marked.items)
    }

    func testARetriedShareOfTheSameScreenshotsIsRecognisedAcrossBatches() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try makeBatch([30, 31, 32], origin: .shareExtension, now: t0)
        let retry = try makeBatch([30, 31, 99], origin: .shareExtension, now: t0.addingTimeInterval(60))
        let marked = try queue.markDuplicates(retry.batchId)
        XCTAssertEqual(marked.items[0].duplicateOf, "\(first.batchId)/\(first.items[0].id)")
        XCTAssertEqual(marked.items[1].duplicateOf, "\(first.batchId)/\(first.items[1].id)")
        XCTAssertNil(marked.items[2].duplicateOf)
        // the older batch is never marked against the newer one
        XCTAssertTrue(try queue.markDuplicates(first.batchId).items.allSatisfy { $0.duplicateOf == nil })
    }

    func testBatchesForDifferentAccountsAreNotDuplicatesOfEachOther() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try makeBatch([40], account: "Main", now: t0)
        let alt = try makeBatch([40], account: "Alt", now: t0.addingTimeInterval(5))
        XCTAssertNil(try queue.markDuplicates(alt.batchId).items[0].duplicateOf)
        let unassigned = try makeBatch([40], account: nil, now: t0.addingTimeInterval(10))
        XCTAssertNotNil(try queue.markDuplicates(unassigned.batchId).items[0].duplicateOf, "a share made before an account existed is compared with everything")
    }

    func testWhatAnEarlierImportSavedIsRecognisedAndHeldBackUntilThePersonSaysOtherwise() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try makeBatch([50, 51], now: t0)
        try queue.recordSaved(first.items, batchId: first.batchId, account: "Main", now: t0.addingTimeInterval(30))
        try queue.remove(first.batchId)
        var next = try makeBatch([50, 52], now: t0.addingTimeInterval(3600))
        next = try queue.markDuplicates(next.batchId)
        XCTAssertEqual(next.items[0].alreadyImported, t0.addingTimeInterval(30))
        XCTAssertNil(next.items[1].alreadyImported)
        // read in full, the old one is held back; the person's "import it again" lets it through
        next = try queue.update(next.batchId) { for i in $0.items.indices { $0.items[i].state = .read } }
        XCTAssertEqual(next.heldBack.map(\.id), [next.items[0].id])
        XCTAssertEqual(next.included.map(\.id), [next.items[1].id])
        next = try queue.update(next.batchId) { $0.items[0].includeAnyway = true }
        XCTAssertEqual(next.included.count, 2)
        // another account's box has never had it
        let other = try makeBatch([50], account: "Alt", now: t0.addingTimeInterval(7200))
        XCTAssertNil(try queue.markDuplicates(other.batchId).items[0].alreadyImported)
    }

    func testTwoDifferentScreenshotsAreNeverDuplicatesWhateverThePokemonIs() throws {
        // The queue knows nothing of species, CP or IVs: only bytes and asset ids make a duplicate.
        let m = try makeBatch([60, 61], assets: ["X", "Y"])
        XCTAssertTrue(try queue.markDuplicates(m.batchId).items.allSatisfy { $0.duplicateOf == nil })
    }

    func testTheLedgerIsBoundedInAge() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let m = try makeBatch([70], now: t0)
        try queue.recordSaved(m.items, batchId: m.batchId, account: "Main", now: t0)
        XCTAssertEqual(queue.ledger().entries.count, 2, "the two hash keys; this item has no asset id")
        let later = t0.addingTimeInterval(ImportLedger.keepFor + 10)
        let n = try makeBatch([71], now: later)
        try queue.recordSaved(n.items, batchId: n.batchId, account: "Main", now: later)
        XCTAssertTrue(queue.ledger().entries.allSatisfy { $0.batchId == n.batchId })
    }

    // MARK: clean-up

    func testCleanupRemovesWhatIsDeadAndKeepsWhatIsAlive() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let live = try makeBatch([80], now: now.addingTimeInterval(-3600))
        let old = try makeBatch([81], now: now.addingTimeInterval(-40 * 24 * 3600))
        let neverShown = try makeBatch([85], now: now.addingTimeInterval(-60 * 24 * 3600))
        let saved = try makeBatch([82], now: now.addingTimeInterval(-60))
        queue.markSeen([live.batchId], now: now.addingTimeInterval(-3600))
        queue.markSeen([old.batchId], now: now.addingTimeInterval(-15 * 24 * 3600))   // shown, then left alone for fifteen days
        _ = try queue.update(saved.batchId, now: now) { $0.savedAt = now }
        // a half-made batch from a process that died, an hour and a bit ago, and a fresh one that is still being made
        let stale = queue.root.appendingPathComponent(".staging-stale"), fresh = queue.root.appendingPathComponent(".staging-fresh")
        for d in [stale, fresh] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-7200)], ofItemAtPath: stale.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: fresh.path)
        // a damaged batch and a newer-version one, a month old: neither is removed
        let damaged = try makeBatch([83]), newer = try makeBatch([84])
        try Data("{".utf8).write(to: queue.batchDirectory(damaged.batchId).appendingPathComponent("manifest.json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: queue.batchDirectory(newer.batchId).appendingPathComponent("manifest.json"))) as? [String: Any])
        json["version"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: queue.batchDirectory(newer.batchId).appendingPathComponent("manifest.json"))
        for d in [damaged, newer] { try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-30 * 24 * 3600)], ofItemAtPath: queue.batchDirectory(d.batchId).path) }

        let report = queue.cleanup(now: now)
        XCTAssertEqual(report, ImportQueue.CleanupReport(removedStaging: 1, removedSaved: 1, removedAbandoned: 1, removedDamaged: 0))
        XCTAssertEqual(Set(try queue.list().manifests.map(\.batchId)), [live.batchId, neverShown.batchId], "a batch nobody was shown is never removed, however old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.batchDirectory(newer.batchId).path), "a newer app's batch is never deleted for the person")
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.batchDirectory(damaged.batchId).path), "nor is a damaged one: the person is told it is there")
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.batchDirectory(old.batchId).path))
    }

    func testTheFortnightIsCountedFromWhenTheBatchWasLastShown() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let m = try makeBatch([86], now: now.addingTimeInterval(-90 * 24 * 3600))
        queue.markSeen([m.batchId], now: now.addingTimeInterval(-2 * 24 * 3600))   // shown two days ago, though made three months ago
        XCTAssertEqual(queue.cleanup(now: now).removedAbandoned, 0)
        XCTAssertEqual(queue.cleanup(now: now.addingTimeInterval(13 * 24 * 3600)).removedAbandoned, 1)
    }

    // MARK: size, cameras, retiring

    func testAPictureLargerThanTheReaderNeedsIsScaledDownWhenStagedToAConcreteSize() throws {
        let b = try queue.beginBatch(origin: .photoPicker, account: "Main")
        let item = try b.add(data: try picture(40, w: 3200, h: 6400))
        XCTAssertEqual(item.width, 1500); XCTAssertEqual(item.height, 3000, "3000 px on the long side, aspect kept")
        let phone = try b.add(data: try picture(41, w: 1320, h: 2868))
        XCTAssertEqual(phone.width, 1320); XCTAssertEqual(phone.height, 2868, "a phone's own screenshot is not touched")
        let m = try b.commit()
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(queue.stagedURL(batch: m.batchId, item: m.items[0]) as CFURL, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 1500); XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 3000)
    }

    func testAPictureWithCameraMetadataIsStagedLikeAnyOtherAndLeftForTheReaderToJudge() throws {
        // A screenshot can inherit a make or lens from an edited copy, so metadata never refuses a picture: it is scaled and staged, and the reader says what it is.
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple"], kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "iPhone back camera"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let b = try queue.beginBatch(origin: .shareExtension, account: "Main")
        let item = try b.add(data: out as Data)
        XCTAssertEqual(item.width, 3000); XCTAssertEqual(item.height, 2250)
    }

    func testTheQueueHasAByteCapAsWellAsAnImageCap() throws {
        _ = try makeBatch([43, 44])
        let bytes = queue.stagedBytes()
        XCTAssertGreaterThan(bytes, 0)
        queue.maxQueuedBytes = bytes + 10
        let b = try queue.beginBatch(origin: .photoPicker, account: "Main"); try b.add(data: try picture(45))
        XCTAssertThrowsError(try b.commit()) { XCTAssertEqual($0 as? ImportQueueError, .queueTooLarge(maxMB: (bytes + 10) / 1_000_000)) }
        XCTAssertEqual(try queue.list().manifests.count, 1, "nothing was queued")
    }

    func testRetiringKeepsOnlyWhatStillNeedsThePersonAndGivesTheNextSaveItsOwnSignature() throws {
        var m = try makeBatch([46, 47, 48, 49])
        m = try queue.update(m.batchId) {
            $0.items[0].state = .read; $0.items[1].state = .read; $0.items[1].repeatOf = $0.items[0].id   // held back
            $0.items[2].state = .failed; $0.items[3].state = .unsupported
        }
        let first = m.signature
        let left = try XCTUnwrap(try queue.retire(m.batchId, saved: [m.items[0].id]))
        XCTAssertEqual(left.items.map(\.id), [m.items[1].id, m.items[2].id], "held back and failed stay; the saved and the not-actionable go")
        XCTAssertNotEqual(left.signature, first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.stagedURL(batch: m.batchId, item: m.items[0]).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: queue.stagedURL(batch: m.batchId, item: m.items[1]).path))
        XCTAssertNil(try queue.retire(m.batchId, saved: [m.items[1].id, m.items[2].id]), "nothing left: the batch goes")
        XCTAssertEqual(try queue.list().manifests.count, 0)
    }

    func testAnEarlierFailureDoesNotClaimItsScreenshotSoSharingItAgainIsTheRetry() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try makeBatch([50], now: t0)
        _ = try queue.update(first.batchId) { $0.items[0].state = .failed }
        let again = try makeBatch([50], now: t0.addingTimeInterval(30))
        XCTAssertNil(try queue.markDuplicates(again.batchId).items[0].duplicateOf)
        _ = try queue.update(first.batchId) { $0.items[0].state = .ivsMissing }   // a verdict, not a fault: now it claims it
        XCTAssertNotNil(try queue.markDuplicates(again.batchId).items[0].duplicateOf)
    }

    func testABatchsOwnLedgerEntriesNeverMakeItsScreenshotsLookAlreadyImported() throws {
        // a save cut off after the ledger was written and before the batch was removed
        let m = try makeBatch([51])
        try queue.recordSaved(m.items, batchId: m.batchId, account: "Main")
        XCTAssertNil(try queue.markDuplicates(m.batchId).items[0].alreadyImported)
        let other = try makeBatch([51], now: Date(timeIntervalSinceNow: 5))
        XCTAssertNotNil(try queue.markDuplicates(other.batchId).items[0].alreadyImported, "but another batch's is")
    }

    func testTheLedgerFollowsAnAccountThroughItsNameOrNotAtAll() throws {
        let m = try makeBatch([52])
        try queue.recordSaved(m.items, batchId: m.batchId, account: "Old", epoch: 3)
        let l = queue.ledger()
        XCTAssertNotNil(l.savedAt(account: "New", keys: m.items[0].keys, currentName: { _ in "New" }))
        XCTAssertNil(l.savedAt(account: "New", keys: m.items[0].keys, currentName: { _ in nil }), "an entry whose account can no longer be told is not counted")
        XCTAssertNil(l.savedAt(account: "Other", keys: m.items[0].keys, currentName: { _ in "New" }))
    }

    func testRemovingABatchRemovesItsImages() throws {
        let m = try makeBatch([90, 91])
        let files = m.items.map { queue.stagedURL(batch: m.batchId, item: $0) }
        try queue.remove(m.batchId)
        for f in files { XCTAssertFalse(FileManager.default.fileExists(atPath: f.path)) }
        XCTAssertEqual(try queue.list().manifests.count, 0)
        XCTAssertNoThrow(try queue.remove(m.batchId), "removing twice is fine")
    }

    func testAnUpdateThatChangesNothingWritesNothing() throws {
        let m = try makeBatch([60])
        let url = queue.manifestURL(m.batchId)
        let before = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: url.path)
        _ = try queue.update(m.batchId) { _ in }
        _ = try queue.markDuplicates(m.batchId)   // nothing to mark
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, Date(timeIntervalSince1970: 1_000_000), "the file was not rewritten")
    }

    func testOneScreenshotCanBeDiscardedAndTheBatchGoesWithTheLastOne() throws {
        let m = try makeBatch([61, 62])
        let left = try XCTUnwrap(try queue.removeItem(m.batchId, item: m.items[0].id))
        XCTAssertEqual(left.items.map(\.id), [m.items[1].id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: queue.stagedURL(batch: m.batchId, item: m.items[0]).path))
        XCTAssertNil(try queue.removeItem(m.batchId, item: m.items[1].id))
        XCTAssertEqual(try queue.list().manifests.count, 0)
    }

    func testASavedSourceLiftsTheHoldOnItsRepeat() throws {
        var m = try makeBatch([63, 64])
        m = try queue.update(m.batchId) { $0.items[0].state = .read; $0.items[1].state = .read; $0.items[1].repeatOf = $0.items[0].id }
        XCTAssertTrue(m.items[1].heldBack)
        let left = try XCTUnwrap(try queue.retire(m.batchId, saved: [m.items[0].id]))
        XCTAssertNil(left.items[0].repeatOf); XCTAssertFalse(left.items[0].heldBack); XCTAssertFalse(left.items[0].hasHold)
    }

    func testAHoldOnAScreenshotThatIsNotKeptIsLiftedWhetherItWasSavedOrLeftOut() throws {
        var m = try makeBatch([70, 71, 72])
        m = try queue.update(m.batchId) {
            for i in 0..<3 { $0.items[i].state = .read }
            $0.items[1].repeatOf = $0.items[0].id; $0.items[2].repeatOf = $0.items[0].id
        }
        // the first was read and then left out by the person
        let left = try XCTUnwrap(try queue.retire(m.batchId, saved: [], dropped: [m.items[0].id]))
        XCTAssertEqual(left.items.count, 2)
        XCTAssertTrue(left.items.allSatisfy { $0.repeatOf == nil && $0.holdLifted == true }, "no hold may point at a screenshot that is gone")
        let n = try makeBatch([73, 74])
        let kept = try queue.update(n.batchId) { $0.items[0].state = .failed; $0.items[1].state = .read; $0.items[1].repeatOf = $0.items[0].id }
        let after = try XCTUnwrap(try queue.retire(kept.batchId, saved: []))
        XCTAssertEqual(after.items.map(\.id), [kept.items[0].id, kept.items[1].id])
        XCTAssertEqual(after.items[1].repeatOf, kept.items[0].id, "a hold on a screenshot that stays is kept")
    }

    /// Without the lock around read-modify-write, concurrent updates lose each other's changes.
    func testConcurrentUpdatesAreNotLost() throws {
        let m = try makeBatch([75])
        let q = queue!
        let group = DispatchGroup()
        for t in 0..<8 {
            group.enter()
            DispatchQueue.global().async {
                for _ in 0..<25 { _ = try? q.update(m.batchId) { $0.items[0].attempts += 1 } }
                _ = t; group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(try queue.load(m.batchId).items[0].attempts, 200)
    }

    func testALedgerFailureIsReportedAndLeavesNothingHalfWritten() throws {
        let m = try makeBatch([76])
        struct Boom: Error {}
        var q = queue!; q.ledgerFailure = { throw Boom() }
        XCTAssertThrowsError(try q.recordSaved(m.items, batchId: m.batchId, account: "Main"))
        XCTAssertTrue(queue.ledger().entries.isEmpty)
    }

    func testTheLedgerKeepsTheFoldersBirthDateSoAFolderMadeAgainIsNotTheSameAccount() throws {
        let m = try makeBatch([77])
        try queue.recordSaved(m.items, batchId: m.batchId, account: "Main", epoch: 1, born: 1234.5)
        XCTAssertEqual(queue.ledger().entries.first?.born, 1234.5)
    }
}
