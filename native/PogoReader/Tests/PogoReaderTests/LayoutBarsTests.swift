import XCTest
@testable import PogoReader

final class LayoutBarsTests: XCTestCase {
    func testClassifyPixel() {
        XCTAssertEqual(classifyPixel(PINK.0, PINK.1, PINK.2), .fill)
        XCTAssertEqual(classifyPixel(ORANGE.0, ORANGE.1, ORANGE.2), .fill)
        XCTAssertEqual(classifyPixel(GREY.0, GREY.1, GREY.2), .grey)
        XCTAssertEqual(classifyPixel(255, 255, 255), .white)
        XCTAssertEqual(classifyPixel(30, 30, 30), .other)
        XCTAssertEqual(classifyPixel(120, 200, 150), .other)
    }

    private func segs(_ spec: String) -> [Seg] {
        spec.split(separator: " ").map { t in
            let c: PixelClass = ["f": .fill, "g": .grey, "w": .white, "o": .other][t.first!]!
            return Seg(c: c, n: Int(t.dropFirst())!)
        }
    }

    func testFillOfTrackIgnoresBlockGapsAndCountsABlendAsHalf() {
        XCTAssertEqual(fillOfTrack(segs("f40 w4 f40 w4 f40")), 1)
        XCTAssertEqual(fillOfTrack(segs("g40 w4 g40 w4 g40")), 0)
        XCTAssertEqual(fillOfTrack(segs("f40 w4 f40 w4 g40")), 80.0 / 120)
        XCTAssertEqual(fillOfTrack(segs("f40 o4 f40 w4 f20 o4 g16")), (100.0 + 2) / 120, accuracy: 1e-12)
    }

    func testReadBarsMeasuresEveryIvIncluding0And15() {
        let rect = PixelRect(x: 0, y: 0, w: 600, h: 400)
        for ivs in [IVs(atk: 15, def: 14, hp: 15), IVs(atk: 0, def: 7, hp: 3), IVs(atk: 12, def: 10, hp: 11), IVs(atk: 15, def: 15, hp: 15), IVs(atk: 1, def: 0, hp: 6)] {
            let r = readBars(appraisalPanel(ivs), rect, Rect(x: 0, y: 50, w: 400, h: 350))
            XCTAssertEqual(r.bars.count, 3, "\(ivs)")
            XCTAssertEqual(r.result?.ivs, ivs)
            XCTAssertGreaterThan(r.result?.confidence ?? 0, 0.9)
        }
    }

    func testReadIvsRejectsUnevenSpacingOrDifferentWidths() {
        func bar(_ y0: Int, _ x0: Int, _ x1: Int, _ fill: Double) -> Bar { Bar(y0: y0, y1: y0 + 10, x0: x0, x1: x1, fill: fill) }
        XCTAssertNil(readIvs([bar(100, 60, 200, 1), bar(160, 60, 200, 1), bar(300, 60, 200, 1)]))
        XCTAssertNil(readIvs([bar(100, 60, 200, 1), bar(160, 60, 300, 1), bar(220, 60, 200, 1)]))
        XCTAssertEqual(readIvs([bar(100, 60, 200, 1), bar(160, 60, 200, 0.5), bar(220, 60, 200, 0)])?.ivs, IVs(atk: 15, def: 8, hp: 0))
        // A mid-animation fill gets a low confidence.
        XCTAssertLessThan(readIvs([bar(100, 60, 200, 0.5), bar(160, 60, 200, 0.5), bar(220, 60, 200, 7.5 / 15)])!.confidence, 0.2)
    }

    func testFindBarsIgnoresColouredRunsThatAreNotOnPanelWhite() {
        var img = RGBAImage(width: 300, height: 100)
        img.fill(Rect(x: 0, y: 0, w: 300, h: 100), (240, 200, 60))  // a jacket, not a panel
        img.fill(Rect(x: 50, y: 40, w: 150, h: 10), ORANGE)
        XCTAssertEqual(findBars(img, PixelRect(x: 0, y: 0, w: 300, h: 100), Rect(x: 0, y: 0, w: 300, h: 100)).count, 0)
    }

    func testFindCpTextAndHpBarLocateTheAnchorsAndDeriveRegions() {
        let img = cardScreen()
        let rect = PixelRect(x: 0, y: 0, w: 400, h: 800)
        let cp = findCpText(img, rect)
        XCTAssertNotNil(cp)
        XCTAssertEqual(cp?.centred, true)
        XCTAssertLessThanOrEqual(abs((cp?.y0 ?? 0) - 48), 2)
        let bar = findHpBar(img, rect)
        XCTAssertNotNil(bar)
        XCTAssertLessThanOrEqual(abs((bar?.y0 ?? 0) - 360), 1)
        let regions = regionsFrom(rect, cp, bar)
        XCTAssertLessThan(regions.name!.y, Double(bar!.y0))
        XCTAssertLessThanOrEqual(regions.name!.y + regions.name!.h, Double(bar!.y0))
        XCTAssertGreaterThanOrEqual(regions.hp!.y, Double(bar!.y1))
        XCTAssertGreaterThan(regions.panelSearch!.y, Double(bar!.y1))
        // The CP crop includes the "CP" prefix and the named padding.
        XCTAssertLessThan(regions.cp.x, Double(cp!.x0))
        let digits = regionsFrom(rect, cp, bar, cpPadding: 0.1, cpIncludesPrefix: false).cp
        XCTAssertEqual(digits.x, Double(cp!.digitsX0) - 0.1 * Double(cp!.y1 - cp!.y0), accuracy: 1e-9)
    }

    func testFindCpTextRejectsASolidOffCentreShapeAndAThinLine() {
        let rect = PixelRect(x: 0, y: 0, w: 400, h: 800)
        var solid = RGBAImage(width: 400, height: 800)
        solid.fill(Rect(x: 0, y: 0, w: 400, h: 800), (60, 80, 100))
        solid.fill(Rect(x: 130, y: 20, w: 140, h: 24), WHITE)   // a solid pill
        XCTAssertNil(findCpText(solid, rect))
        var thin = RGBAImage(width: 400, height: 800)
        thin.fill(Rect(x: 0, y: 0, w: 400, h: 800), (60, 80, 100))
        thin.fill(Rect(x: 100, y: 80, w: 200, h: 3), WHITE)     // the arc apex
        XCTAssertNil(findCpText(thin, rect))
    }

    func testFindCpTextFallsBackToThePinkMask() {
        var img = cardScreen(cp: false)
        for i in 0..<4 { img.fill(Rect(x: 168 + Double(i) * 18, y: 48, w: 8, h: 20), (230, 100, 140)) }
        XCTAssertEqual(findCpText(img, PixelRect(x: 0, y: 0, w: 400, h: 800))?.mask, "pink")
    }

    /// Fault 4: green type icons are a taller band of two short runs; the HP bar is the long run.
    func testFindHpBarTakesTheLongBarNotARowOfGreenTypeIcons() {
        let W = 660, H = 1434
        var img = RGBAImage(width: W, height: H)
        let green: (UInt8, UInt8, UInt8) = (80, 220, 150)
        img.fill(Rect(x: 0, y: 0, w: Double(W), h: Double(H)), WHITE)
        img.fill(Rect(x: 0, y: 0, w: 14, h: Double(H)), (60, 160, 40))   // grass background beside the card
        img.fill(Rect(x: 165, y: 645, w: 330, h: 9), green)               // the HP bar
        img.fill(Rect(x: 180, y: 759, w: 60, h: 13), green)               // Bug and Grass type icons: a taller band,
        img.fill(Rect(x: 260, y: 759, w: 60, h: 13), green)               // two runs, each long enough to count
        XCTAssertEqual(findHpBar(img, PixelRect(x: 0, y: 0, w: W, h: H)), HpBar(y0: 645, y1: 654, x0: 165, x1: 495))
    }

    func testContentRectFindsTheScreenInsideBlackBorders() {
        var img = RGBAImage(width: 300, height: 200)
        img.fill(Rect(x: 50, y: 0, w: 200, h: 200), (200, 200, 200))
        XCTAssertEqual(contentRect(img), PixelRect(x: 50, y: 0, w: 200, h: 200))
    }

    /// A thin dark line between content is not a border: the whole screen stays (a real border is still cut).
    func testContentRectIgnoresAThinDarkLineInsideTheContent() {
        var img = RGBAImage(width: 300, height: 600)
        img.fill(Rect(x: 0, y: 0, w: 300, h: 600), (200, 200, 200))
        img.fill(Rect(x: 0, y: 250, w: 300, h: 2), (10, 10, 10))      // the card's dark top edge
        XCTAssertEqual(contentRect(img), PixelRect(x: 0, y: 0, w: 300, h: 600))
        img.fill(Rect(x: 0, y: 0, w: 300, h: 60), (0, 0, 0))          // a real letterbox border is still removed
        XCTAssertEqual(contentRect(img).y, 60)
    }

    /// The bridging limit is 0.5% of the height for rows and of the width for columns (at least 2): exactly at the limit a
    /// gap is bridged, one more is not. The image is not square, so a width/height mix-up cannot pass.
    func testContentRectBridgesUpToTheLimitAndNoFurtherInRowsAndColumns() {
        func screen(darkRows: Range<Int>? = nil, darkCols: Range<Int>? = nil) -> RGBAImage {
            var img = RGBAImage(width: 400, height: 1000)
            img.fill(Rect(x: 0, y: 0, w: 400, h: 1000), (200, 200, 200))
            if let r = darkRows { img.fill(Rect(x: 0, y: Double(r.lowerBound), w: 400, h: Double(r.count)), (10, 10, 10)) }
            if let c = darkCols { img.fill(Rect(x: Double(c.lowerBound), y: 0, w: Double(c.count), h: 1000), (10, 10, 10)) }
            return img
        }
        let whole = PixelRect(x: 0, y: 0, w: 400, h: 1000)
        // Rows: the limit is Int(0.005 * 1000) = 5.
        XCTAssertEqual(contentRect(screen(darkRows: 300..<305)), whole)                           // 5 rows: bridged
        XCTAssertEqual(contentRect(screen(darkRows: 300..<306)), PixelRect(x: 0, y: 306, w: 400, h: 694))   // 6 rows: a border, the wider side wins
        // Columns: the limit is max(2, Int(0.005 * 400)) = 2.
        XCTAssertEqual(contentRect(screen(darkCols: 100..<102)), whole)                          // 2 columns: bridged
        XCTAssertEqual(contentRect(screen(darkCols: 100..<103)), PixelRect(x: 103, y: 0, w: 297, h: 1000))  // 3 columns: not
        // An internal band wider than the limit stays unbridged even when it is dark purple rather than black.
        var band = screen()
        band.fill(Rect(x: 0, y: 400, w: 400, h: 30), (8, 7, 52))
        XCTAssertNotEqual(contentRect(band), whole)
        // Dark gaps at the ends are never bridged (a letterbox).
        XCTAssertEqual(contentRect(screen(darkRows: 0..<3)).y, 3)
    }

    func testLaplacianVarianceIsLowerForABlurredEdge() {
        var sharp = RGBAImage(width: 40, height: 40), soft = RGBAImage(width: 40, height: 40)
        sharp.fill(Rect(x: 0, y: 0, w: 40, h: 40), (0, 0, 0)); sharp.fill(Rect(x: 20, y: 0, w: 20, h: 40), WHITE)
        for x in 0..<40 { let v = UInt8(max(0, min(255, (x - 10) * 12))); soft.fill(Rect(x: Double(x), y: 0, w: 1, h: 40), (v, v, v)) }
        XCTAssertGreaterThan(laplacianVariance(sharp), laplacianVariance(soft))
    }
}
