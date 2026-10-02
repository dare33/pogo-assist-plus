import XCTest
import CoreVideo
@testable import PogoReader

final class SwipeDetectorTests: XCTestCase {
    private func drawn(_ style: SyntheticScreen.Style, cp: Int = 1984) -> RGBAImage {
        var img = RGBAImage(width: 1320, height: 2868)
        SyntheticScreen.draw(into: &img, SyntheticScreen.Spec(name: "Staraptor", cp: cp, hp: 140, ivs: IVs(atk: 15, def: 12, hp: 12)), style: style)
        return img
    }

    func testAStillFrameScoresZeroAndAMovedCardScoresAboveTheThreshold() {
        var d = SwipeDetector()
        let a = drawn(.phone)
        XCTAssertNil(d.feed(a))                                   // the first frame has nothing to compare with
        XCTAssertEqual(d.feed(a) ?? -1, 0, accuracy: 1e-6)
        // Another Pokémon's text in the same places is a small change; the card sliding (everything moves) is a big one.
        XCTAssertLessThan(d.feed(drawn(.phone, cp: 2017)) ?? 99, SwipeDetector.threshold)
        XCTAssertGreaterThan(d.feed(drawn(.padMuted)) ?? 0, SwipeDetector.threshold)
        d.reset()
        XCTAssertNil(d.feed(a))
    }

    /// Pixel buffers give the same signature as the RGBA frame they came from (video range scaled to 0-255).
    func testPixelBuffersGiveTheSameSignatureAsRgba() throws {
        let a = drawn(.phone), b = drawn(.padMuted)
        var rgba = SwipeDetector()
        _ = rgba.feed(a)
        let expected = try XCTUnwrap(rgba.feed(b))
        for (name, make) in [("BGRA", { (i: RGBAImage) in try PixelBuffers.bgra(from: i) }),
                             ("420v", { (i: RGBAImage) in try Pixel420Maker(fullRange: false).make(from: i) }),
                             ("420f", { (i: RGBAImage) in try Pixel420Maker(fullRange: true).make(from: i) })] {
            var d = SwipeDetector()
            _ = d.feed(try make(a))
            let got = try XCTUnwrap(d.feed(try make(b)))
            XCTAssertEqual(got, expected, accuracy: name == "BGRA" ? 0.5 : 6, name)   // 4:2:0 luma is BT.709-weighted, the JS signature Rec.601
        }
    }

    func testASizeChangeRestartsTheComparison() {
        var d = SwipeDetector()
        _ = d.feed(drawn(.phone))
        var small = RGBAImage(width: 600, height: 1300)
        SyntheticScreen.draw(into: &small, SyntheticScreen.Spec(name: "Zubat", cp: 203, hp: 62, ivs: IVs(atk: 1, def: 2, hp: 3)))
        XCTAssertNil(d.feed(small))
    }
}
