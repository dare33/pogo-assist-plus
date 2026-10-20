import XCTest
import CoreGraphics
import ImageIO
@testable import PogoReader

/// The still-image adapter: a screenshot decoded to the reader's sRGB RGBA values and read once. The cards are the owner's real screenshots (Display P3, read with real Vision);
/// the other cases are made from them or drawn.
final class StillReaderTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    private func fixture(_ name: String) -> URL { Self.fixtures.appendingPathComponent(name) }

    private func reader() throws -> StillReader { try StillReader() }

    /// Encode a CGImage with the given type and (optionally) an EXIF orientation.
    private func encode(_ cg: CGImage, type: String, quality: Double? = nil, orientation: Int? = nil) throws -> Data {
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, type as CFString, 1, nil))
        var props = [CFString: Any]()
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func cgImage(_ name: String) throws -> CGImage {
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(fixture(name) as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    // MARK: decoding

    func testAScreenshotIsDecodedToItsOwnSizeInSRGBValues() throws {
        let img = try StillImage.decode(contentsOf: fixture("normal-nickit-212.png"))
        XCTAssertEqual(img.width, 1320); XCTAssertEqual(img.height, 2868)
        // The P3 file's values are converted, not copied: the same file read without conversion (the recorded-frame path) differs.
        let raw = try decodeRGBA(contentsOf: fixture("normal-nickit-212.png"))
        XCTAssertNotEqual(img.bytes, raw.bytes)
    }

    func testAnOrientationTagIsAppliedAndNothingIsEnlarged() throws {
        // Stored sideways (the pixels turned a quarter) with orientation 6 ("right"): the upright image is the original's shape again.
        let cg = try cgImage("rayquaza-damaged-19of190.png")   // 750 x 1629
        let sideways = try XCTUnwrap(rotated(cg))              // 1629 x 750 pixels
        let data = try encode(sideways, type: "public.png", orientation: 6)
        let img = try StillImage.decode(data: data)
        XCTAssertEqual(img.width, 750); XCTAssertEqual(img.height, 1629)
    }

    func testAHugeImageIsScaledDownWhileDecodedAndASmallOneIsNotScaledUp() throws {
        var big = RGBAImage(width: 5000, height: 2500)
        big.fill(Rect(x: 0, y: 0, w: 5000, h: 2500), (200, 210, 220))
        let data = try encode(try cgOf(big), type: "public.png")
        let img = try StillImage.decode(data: data)
        XCTAssertEqual(max(img.width, img.height), StillImage.maxLongSide)
        let small = try StillImage.decode(contentsOf: fixture("rayquaza-damaged-19of190.png"))
        XCTAssertEqual(small.width, 750)
    }

    func testJunkAndTinyImagesAreRefused() throws {
        XCTAssertThrowsError(try StillImage.decode(data: Data("not an image".utf8))) { XCTAssertEqual($0 as? StillImageError, .cannotDecode) }
        XCTAssertThrowsError(try StillImage.decode(data: Data())) { XCTAssertEqual($0 as? StillImageError, .cannotDecode) }
        var tiny = RGBAImage(width: 120, height: 200)
        tiny.fill(Rect(x: 0, y: 0, w: 120, h: 200), (255, 255, 255))
        XCTAssertThrowsError(try StillImage.decode(data: try encode(try cgOf(tiny), type: "public.png"))) {
            XCTAssertEqual($0 as? StillImageError, .tooSmall(width: 120, height: 200))
        }
        XCTAssertThrowsError(try StillImage.decode(contentsOf: fixture("missing.png")))
    }

    // MARK: reading real screenshots

    func testANormalCardIsReadInFull() throws {
        let r = try reader()
        guard case .read(let reading) = try r.read(contentsOf: fixture("normal-nickit-212.png"), label: "a") else { return XCTFail("not read") }
        XCTAssertEqual(reading.name, "Nickit"); XCTAssertEqual(reading.cp, 212)
        XCTAssertEqual(reading.hp, HP(current: 61, max: 61)); XCTAssertEqual(reading.ivs, IVs(atk: 9, def: 2, hp: 13))
        XCTAssertEqual(reading.frame, "a")
    }

    func testADamagedCardIsReadAndTheSameReaderTakesTheNextImage() throws {
        let r = try reader()
        for (file, current) in [("rayquaza-damaged-19of190.png", 19), ("rayquaza-fainted-0of190.png", 0), ("normal-nickit-212.png", 61)] {
            guard case .read(let reading) = try r.read(contentsOf: fixture(file)) else { return XCTFail("\(file) not read") }
            XCTAssertEqual(reading.hp?.current, current, file)
        }
    }

    func testTheEncodingDoesNotMatter() throws {
        let r = try reader()
        let cg = try cgImage("normal-nickit-212.png")
        for (type, quality) in [("public.jpeg", 0.9), ("public.heic", 0.9), ("public.png", nil)] as [(String, Double?)] {
            let img = try StillImage.decode(data: try encode(cg, type: type, quality: quality))
            guard case .read(let reading) = r.read(img) else { return XCTFail("\(type) not read: \(r.read(img))") }
            XCTAssertEqual(reading.name, "Nickit", type); XCTAssertEqual(reading.cp, 212, type); XCTAssertEqual(reading.ivs, IVs(atk: 9, def: 2, hp: 13), type)
        }
    }

    func testAStationedCardIsUnsupportedAndNeverNamed() throws {
        let r = try reader()
        for file in ["stationed-zapdos.png", "stationed-moltres.png"] {
            guard case .unsupported(let why) = try r.read(contentsOf: fixture(file)) else { return XCTFail("\(file) was not refused") }
            XCTAssertTrue(why.contains("stationed"), why)
        }
    }

    func testAnotherScreenIsUnsupported() throws {
        let r = try reader()
        var img = RGBAImage(width: 750, height: 1630)
        img.fill(Rect(x: 0, y: 0, w: 750, h: 1630), (30, 90, 160))
        img.fill(Rect(x: 0, y: 800, w: 750, h: 400), (245, 245, 245))
        guard case .unsupported = r.read(img) else { return XCTFail("\(r.read(img))") }
        guard case .unsupported = r.read(RGBAImage(width: 750, height: 1630)) else { return XCTFail("a black screen") }
    }

    func testACardWithoutItsAppraisalBarsIsReadButHasNoIVs() throws {
        let r = try reader()
        var img = try StillImage.decode(contentsOf: fixture("normal-nickit-212.png"))
        // Paint the lower part of the card over: the name, CP and HP stay, the appraisal panel goes.
        let w = Double(img.width), h = Double(img.height)
        img.fill(Rect(x: 0, y: 0.58 * h, w: w, h: 0.42 * h), (240, 245, 247))
        let outcome = r.read(img)
        guard case .ivsMissing(let reading, let why) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(reading.name, "Nickit"); XCTAssertEqual(reading.cp, 212)
        XCTAssertEqual(why, .barsNotVisible)
        XCTAssertNil(reading.ivs)
    }

    // MARK: the rules

    private func reading(_ edit: (inout FrameReading) -> Void = { _ in }) -> FrameReading {
        var r = FrameReading(frame: "f", time: 0)
        r.name = "Nickit"; r.cp = 212; r.hp = HP(current: 61, max: 61); r.ivs = IVs(atk: 9, def: 2, hp: 13); r.ivConfidence = 0.95
        edit(&r)
        return r
    }

    func testTheRulesTakeOnlyAWholeReading() {
        XCTAssertEqual(StillReader.judge(reading()), .read(reading()))
        // bars: absent, or below the settled confidence
        if case .ivsMissing(_, let why) = StillReader.judge(reading { $0.ivs = nil }) { XCTAssertEqual(why, .barsNotVisible) } else { XCTFail() }
        if case .ivsMissing(_, let why) = StillReader.judge(reading { $0.ivConfidence = 0.69 }) { XCTAssertEqual(why, .barsNotSettled) } else { XCTFail() }
        XCTAssertEqual(StillReader.judge(reading { $0.ivConfidence = SETTLED }), .read(reading { $0.ivConfidence = SETTLED }))
        // identity: each of name, CP, HP is needed, and a faint name is not taken
        for edit in [{ (r: inout FrameReading) in r.cp = nil }, { $0.hp = nil }, { $0.nameWeak = true }, { $0.name = nil; $0.cpText = "CP212" }] as [(inout FrameReading) -> Void] {
            guard case .unreadable = StillReader.judge(reading(edit)) else { return XCTFail("\(reading(edit))") }
        }
        // screens the reader does not support
        guard case .unsupported = StillReader.judge(reading { $0.flags = ["stationed"] }) else { return XCTFail() }
        guard case .unsupported = StillReader.judge(reading { $0.name = nil; $0.flags = ["mid-swipe"] }) else { return XCTFail() }
        guard case .unsupported = StillReader.judge(reading { $0.name = nil; $0.cp = nil; $0.flags = ["no-cp-text"] }) else { return XCTFail() }
        // a stationed reading that carries bars is still not a Pokémon to add
        guard case .unsupported = StillReader.judge(reading { $0.flags = ["stationed"]; $0.cp = nil; $0.hp = nil }) else { return XCTFail() }
    }

    // MARK: helpers

    private func cgOf(_ img: RGBAImage) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(img.bytes) as CFData))
        return try XCTUnwrap(CGImage(width: img.width, height: img.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    /// The image turned a quarter clockwise-to-sideways: width and height swapped.
    private func rotated(_ cg: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: cg.height, height: cg.width, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.translateBy(x: CGFloat(cg.height), y: 0)
        ctx.rotate(by: .pi / 2)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return ctx.makeImage()
    }
}
