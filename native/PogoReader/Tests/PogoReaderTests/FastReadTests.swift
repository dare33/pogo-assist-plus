import XCTest
@testable import PogoReader

/// The two ways a frame is read with fewer Vision passes: name and HP in one pass (`singlePass`), and no pass at all for a name or
/// HP crop that has not changed since the last frame read it (`reuseStaticText`). Both must give the reading the plain reader gives.
final class FastReadTests: XCTestCase {
    /// Counts passes: `reads` are single-crop passes, `stacks` are passes that read several crops at once.
    final class CountingText: TextReader {
        var cp = "CP1234", name = "Zapdos", hp = "129 / 129 HP"
        var reads = [TextKind](), stacks = 0
        func answer(_ kind: TextKind) -> TextRead {
            switch kind {
            case .cp: return line(cp, 90)
            case .name: return line(name, 92)
            case .hp: return line(hp, 90)
            }
        }
        func read(_ image: RGBAImage, kind: TextKind) -> TextRead { reads.append(kind); return answer(kind) }
        func readStack(_ parts: [(image: RGBAImage, kind: TextKind)]) -> [TextRead] { stacks += 1; return parts.map { answer($0.kind) } }
        var passes: Int { reads.count + stacks }
    }

    private func reader(_ text: CountingText, stack: Bool = false, reuse: Bool = false) -> FrameReader {
        let r = FrameReader(text: text, names: names)
        r.singlePass = stack; r.reuseStaticText = reuse
        return r
    }

    func testTheDefaultReaderMakesOnePassPerCrop() {
        let text = CountingText()
        let r = reader(text).read(cardScreen(), frame: "f", time: 0, wantBars: false)
        XCTAssertEqual(r.name, "Zapdos")
        XCTAssertEqual(text.reads, [.cp, .name, .hp])
        XCTAssertEqual(text.stacks, 0)
    }

    func testSinglePassReadsNameAndHpTogetherAndGivesTheSameReading() {
        let plain = CountingText(), fast = CountingText()
        let a = reader(plain).read(cardScreen(), frame: "f", time: 0, wantBars: false)
        let b = reader(fast, stack: true).read(cardScreen(), frame: "f", time: 0, wantBars: false)
        XCTAssertEqual(a, b)
        XCTAssertEqual(fast.reads, [.cp], "the CP crop keeps a pass of its own")
        XCTAssertEqual(fast.stacks, 1)
    }

    func testSinglePassStillGivesAnUnnamedFrameItsCpAndNoHp() {
        let text = CountingText(); text.name = "xyzzy"
        let r = reader(text, stack: true).read(cardScreen(), frame: "f", time: 0, wantBars: false)
        XCTAssertNil(r.name)
        XCTAssertEqual(r.cp, 1234)
        XCTAssertNil(r.hp, "an unnamed frame has no HP, as with one pass per crop")
    }

    func testTheLuckySecondLookIsStillItsOwnPass() {
        let text = FakeText(name: ("nothing", 90), above: ("Zapdos", 95))
        let r = FrameReader(text: text, names: names)
        r.singlePass = true
        let reading = r.read(cardScreen(lucky: true), frame: "f", time: 0, wantBars: false)
        XCTAssertEqual(reading.name, "Zapdos")
        XCTAssertEqual(text.nameCalls, 2, "FakeText has no stacked pass (the protocol default reads each crop): the usual name line, then the second look")
    }

    func testAnUnchangedFrameNeedsNoNameOrHpPass() {
        let text = CountingText()
        let r = reader(text, reuse: true)
        let first = r.read(cardScreen(), frame: "1", time: 0, wantBars: false)
        XCTAssertEqual(text.reads, [.cp, .name, .hp])
        let second = r.read(cardScreen(), frame: "2", time: 0.2, wantBars: false)
        XCTAssertEqual(text.reads, [.cp, .name, .hp, .cp], "only the CP is read again")
        XCTAssertEqual(first.name, second.name)
        XCTAssertEqual(first.hp, second.hp)
        XCTAssertEqual(first.nameConfidence, second.nameConfidence)
        XCTAssertEqual(first.cp, second.cp)
    }

    func testAChangedCropIsReadAgain() {
        let text = CountingText()
        let r = reader(text, reuse: true)
        _ = r.read(cardScreen(), frame: "1", time: 0, wantBars: false)
        text.name = "Moltres"; text.hp = "131 / 131 HP"
        var changed = cardScreen()
        // A block the size of a digit inside the HP crop and of a letter inside the name crop, dark on the light card.
        changed.fill(Rect(x: 160, y: 372, w: 12, h: 8), (30, 30, 30))
        changed.fill(Rect(x: 160, y: 320, w: 20, h: 14), (30, 30, 30))
        let second = r.read(changed, frame: "2", time: 0.2, wantBars: false)
        XCTAssertEqual(second.name, "Moltres")
        XCTAssertEqual(second.hp, HP(current: 131, max: 131))
    }

    func testAFailedNameReadIsNotKeptForTheNextFrame() {
        let text = CountingText(); text.name = "xyzzy"
        let r = reader(text, reuse: true)
        XCTAssertNil(r.read(cardScreen(), frame: "1", time: 0, wantBars: false).name)
        text.name = "Zapdos"
        XCTAssertEqual(r.read(cardScreen(), frame: "2", time: 0.2, wantBars: false).name, "Zapdos", "an unchanged crop that failed is read again")
    }

    func testReuseAndSinglePassTogether() {
        let text = CountingText()
        let r = reader(text, stack: true, reuse: true)
        _ = r.read(cardScreen(), frame: "1", time: 0, wantBars: false)
        XCTAssertEqual(text.passes, 2)
        _ = r.read(cardScreen(), frame: "2", time: 0.2, wantBars: false)
        XCTAssertEqual(text.passes, 3, "the second frame reads the CP and nothing else")
    }

    // MARK: - CropSignature

    func testSignatureToleratesNoiseAndSeesAChangedGlyph() {
        var a = RGBAImage(width: 64, height: 32)
        a.fill(Rect(x: 0, y: 0, w: 64, h: 32), (200, 200, 200))
        var noisy = a
        for i in stride(from: 0, to: noisy.bytes.count, by: 4) { noisy.bytes[i] = UInt8(clamping: Int(noisy.bytes[i]) + (i % 8 == 0 ? 3 : -3)) }
        XCTAssertTrue(CropSignature(a).matches(CropSignature(noisy)))
        var glyph = a
        glyph.fill(Rect(x: 20, y: 8, w: 8, h: 12), (40, 40, 40))
        XCTAssertFalse(CropSignature(a).matches(CropSignature(glyph)))
    }

    func testSignaturesOfDifferentSizesNeverMatch() {
        XCTAssertFalse(CropSignature(RGBAImage(width: 64, height: 32)).matches(CropSignature(RGBAImage(width: 68, height: 32))))
        XCTAssertFalse(CropSignature(RGBAImage(width: 0, height: 0)).matches(CropSignature(RGBAImage(width: 0, height: 0))))
    }
}
