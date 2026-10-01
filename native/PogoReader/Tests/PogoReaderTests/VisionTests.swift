import XCTest
@testable import PogoReader

/// Real Vision on a drawn frame, end to end: CP, name, HP and bars all read, at full size and at the
/// extension's scaled width, through the same FrameProcessor.
final class VisionTests: XCTestCase {
    func testDrawnFrameIsReadEndToEnd() {
        let spec = SyntheticScreen.Spec(name: "Charizard", cp: 2017, hp: 132, ivs: IVs(atk: 12, def: 13, hp: 13))
        var img = RGBAImage(width: 1320, height: 2868)
        SyntheticScreen.draw(into: &img, spec)
        for width in [Int?.none, 750] {
            let r = FrameProcessor(names: names, targetWidth: width).process(img, time: 0, frame: "drawn")
            XCTAssertEqual(r.cp, 2017, "width \(String(describing: width)) cpText \(r.cpText)")
            XCTAssertEqual(r.name, "Charizard", "nameText \(r.nameText)")
            XCTAssertEqual(r.hp, HP(current: 132, max: 132), "hpText \(r.hpText)")
            XCTAssertEqual(r.ivs, spec.ivs)
            XCTAssertEqual(r.flags, [])
        }
    }
}
