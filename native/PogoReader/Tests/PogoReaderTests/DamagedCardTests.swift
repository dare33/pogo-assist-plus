import XCTest
import CoreGraphics
import ImageIO
@testable import PogoReader

/// A damaged or fainted Pokémon's HP bar has no green fill, which is the colour the reader anchors the
/// name and HP on: run17's first card (Rayquaza CP 4262, 19 / 190 HP) was read as a CP alone in every
/// frame. The identifying HP of a box row is the MAX (190); the current figure rides along.
final class DamagedCardTests: XCTestCase {
    private func read(_ img: RGBAImage, _ text: FakeText) -> FrameReading {
        FrameReader(text: text, names: names).read(img, frame: "f", time: 0, wantBars: false)
    }
    // The real card is 750 x 1630 at the width the broadcast reads (the gradient's slope depends on the height).
    private func card(_ bar: HpBarLook, gradient: Bool) -> RGBAImage { cardScreen(bar: bar, gradient: gradient, w: 750, h: 1630) }

    func testADamagedBarGivesNameCpAndHpOnASyntheticCardFlatOrShaded() {
        for gradient in [false, true] {
            let r = read(card(.damaged, gradient: gradient), FakeText(hp: "19 / 190 HP"))
            XCTAssertEqual(r.name, "Zapdos", "gradient \(gradient)")
            XCTAssertEqual(r.cp, 1234)
            XCTAssertEqual(r.hp, HP(current: 19, max: 190), "gradient \(gradient)")
            XCTAssertEqual(r.flags, [], "gradient \(gradient)")
        }
    }

    func testAFaintedBarGivesNameCpAndZeroCurrentHpOnASyntheticCardFlatOrShaded() {
        for gradient in [false, true] {
            let r = read(card(.fainted, gradient: gradient), FakeText(hp: "0 / 190 HP"))
            XCTAssertEqual(r.name, "Zapdos", "gradient \(gradient)")
            XCTAssertEqual(r.cp, 1234)
            XCTAssertEqual(r.hp, HP(current: 0, max: 190), "gradient \(gradient)")
            XCTAssertFalse(r.flags.contains("hp-unread"))
        }
    }

    /// The bar is found by its shape, so the gradient band under it is not taken for it, and where it is placed decides the crops.
    func testTheBarIsFoundAtTheRealBarNotTheCardsGradient() {
        let img = card(.damaged, gradient: true)
        let rect = contentRect(img)
        let bar = findDamagedHpBar(img, rect)
        XCTAssertNotNil(bar)
        let barY = Int(0.45 * 1630)
        XCTAssertTrue(bar.map { abs($0.y0 - barY) <= 2 && $0.y1 - $0.y0 >= 9 && $0.y1 - $0.y0 <= 13 } ?? false, "\(String(describing: bar))")
        XCTAssertTrue(bar.map { abs($0.x0 - 188) <= 2 && abs($0.x1 - 563) <= 2 } ?? false, "\(String(describing: bar))")
    }

    /// The text guard: a bar-shaped band whose text is not an HP is a frame with no HP bar, exactly as before the fallback.
    func testABarShapedBandWithoutAnHpTextIsTheOldNoHpBarFrame() {
        for gradient in [false, true] {
            for text in ["Level 12", "", "CP 1234 / 99", "dH 99 / 99"] {
                let r = read(card(.damaged, gradient: gradient), FakeText(hp: text))
                XCTAssertNil(r.name, text)
                XCTAssertNil(r.hp, text)
                XCTAssertEqual(r.cp, 1234, "\(text): the CP is still read")
                XCTAssertEqual(r.flags, ["no-hp-bar"], "\(text) gradient \(gradient)")
            }
        }
    }

    func testAScreenWithNoBarAtAllStillHasNoHpBar() {
        for gradient in [false, true] {
            var img = card(.full, gradient: gradient)
            img.fill(Rect(x: 0, y: 0.40 * 1630, w: 750, h: 0.1 * 1630), (250, 250, 245))   // wipe the bar
            XCTAssertTrue(read(img, FakeText()).flags.contains("no-hp-bar"), "gradient \(gradient)")
            XCTAssertNil(findDamagedHpBar(img, contentRect(img)))
        }
        // the card's gradient alone, with no bar
        var shaded = card(.fainted, gradient: true)
        shaded.fill(Rect(x: 0, y: 0.44 * 1630, w: 750, h: 0.03 * 1630), (222, 233, 240))
        XCTAssertNil(findDamagedHpBar(shaded, contentRect(shaded)))
    }

    func testARedPatchWithoutATrackIsNotAnHpBar() {
        var img = card(.full, gradient: true)
        img.fill(Rect(x: 0, y: 0.40 * 1630, w: 750, h: 0.1 * 1630), (250, 250, 245))
        img.fill(Rect(x: 0.26 * 750, y: 0.45 * 1630, w: 0.04 * 750, h: 0.0067 * 1630), (173, 87, 89))
        XCTAssertNil(findDamagedHpBar(img, contentRect(img)))
    }

    func testABandAcrossTheWholeCardIsNotAnHpBar() {
        var img = card(.full, gradient: true)
        img.fill(Rect(x: 0, y: 0.40 * 1630, w: 750, h: 0.1 * 1630), (250, 250, 245))
        img.fill(Rect(x: 0.04 * 750, y: 0.45 * 1630, w: 0.92 * 750, h: 0.0067 * 1630), (205, 216, 219))
        XCTAssertNil(findDamagedHpBar(img, contentRect(img)))
    }

    // MARK: - the owner's screenshots

    private func fixtureURL(_ name: String) -> URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)") }

    /// The screenshot as the owner's phone saved it (Display P3 values, read without conversion, as `decodeRGBA` does).
    private func p3(_ name: String) throws -> RGBAImage { try decodeRGBA(contentsOf: fixtureURL(name)) }

    /// The same screenshot in sRGB values, which is what the broadcast delivers (every recorded frame set is tagged sRGB / BT.709).
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

    private enum Path: String, CaseIterable { case rgba750, rgbaFull, video420 }

    private func process(_ img: RGBAImage, _ path: Path) throws -> FrameReading {
        switch path {
        case .rgba750: return FrameProcessor(names: names).process(img, time: 0, frame: "f")
        case .rgbaFull: return FrameProcessor(names: names, targetWidth: nil).process(img, time: 0, frame: "f")
        case .video420: return FrameProcessor(names: names).process(try Pixel420Maker(fullRange: false).make(from: img), time: 0, frame: "f")
        }
    }

    /// Both cards, in the phone's P3 values and in broadcast sRGB values, at the width the broadcast reads, at full width and
    /// through the 420 video-range path, with real Vision.
    func testTheRayquazaCardsReadNameCpHpAndBarsInEveryColourSpaceAndPath() throws {
        for (file, current) in [("rayquaza-damaged-19of190.png", 19), ("rayquaza-fainted-0of190.png", 0)] {
            for (space, img) in [("P3", try p3(file)), ("sRGB", try srgb(file))] {
                for path in Path.allCases {
                    let r = try process(img, path)
                    let label = "\(file) \(space) \(path)"
                    XCTAssertEqual(r.name, "Rayquaza", "\(label): nameText \(r.nameText)")
                    XCTAssertEqual(r.cp, 4262, "\(label): cpText \(r.cpText)")
                    XCTAssertEqual(r.hp, HP(current: current, max: 190), "\(label): hpText \(r.hpText)")
                    XCTAssertEqual(r.ivs, IVs(atk: 13, def: 12, hp: 14), label)
                    XCTAssertEqual(r.flags, [], label)
                }
            }
        }
    }
}
