import XCTest
import CoreVideo
@testable import PogoReader

final class ProcessorTests: XCTestCase {
    private func makeBuffer(_ w: Int, _ h: Int, _ format: OSType) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, w, h, format, [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &pb), kCVReturnSuccess)
        return pb!
    }

    private func fill420(_ pb: CVPixelBuffer, y: UInt8, cb: UInt8, cr: UInt8) {
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        for plane in 0..<2 {
            let base = CVPixelBufferGetBaseAddressOfPlane(pb, plane)!.assumingMemoryBound(to: UInt8.self)
            let rows = CVPixelBufferGetHeightOfPlane(pb, plane), cols = CVPixelBufferGetWidthOfPlane(pb, plane), stride = CVPixelBufferGetBytesPerRowOfPlane(pb, plane)
            for r in 0..<rows { for c in 0..<cols {
                if plane == 0 { base[r * stride + c] = y } else { base[r * stride + c * 2] = cb; base[r * stride + c * 2 + 1] = cr }
            } }
        }
    }

    private func processor(width: Int?) -> FrameProcessor { FrameProcessor(textReader: FakeText(), names: names, targetWidth: width) }

    func testBgraFramesAreScaledIntoOneBufferAndComeOutAsRgba() {
        let pb = makeBuffer(400, 800, kCVPixelFormatType_32BGRA)
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(pb)
        for y in 0..<800 { for x in 0..<400 { let i = y * stride + x * 4; base[i] = 10; base[i + 1] = 20; base[i + 2] = 30; base[i + 3] = 255 } }  // B, G, R, A
        CVPixelBufferUnlockBaseAddress(pb, [])
        let p = processor(width: 200)
        _ = p.process(pb, time: 0)
        XCTAssertEqual(p.scaledFrame.width, 200)
        XCTAssertEqual(p.scaledFrame.height, 400)
        let px = p.scaledFrame.pixel(100, 200)
        XCTAssertEqual([px.r, px.g, px.b], [30, 20, 10])
        // Same buffer reused for the next frame: no reallocation of the reused image's size.
        _ = p.process(pb, time: 0.2)
        XCTAssertEqual(p.scaledFrame.width, 200)
    }

    func test420VideoAndFullRangeAreConvertedAtFullSizeAndScaled() {
        for (format, y, expect) in [(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, UInt8(235), 255), (kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, UInt8(16), 0), (kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, UInt8(255), 255), (kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, UInt8(0), 0)] {
            let pb = makeBuffer(400, 800, format)
            fill420(pb, y: y, cb: 128, cr: 128)
            for width in [Int?.none, 200] {
                let p = processor(width: width)
                _ = p.process(pb, time: 0)
                XCTAssertEqual(p.scaledFrame.width, width ?? 400)
                let px = p.scaledFrame.pixel(p.scaledFrame.width / 2, p.scaledFrame.height / 2)
                for c in [px.r, px.g, px.b] { XCTAssertEqual(Int(c), expect, accuracy: 3, "format \(format) y \(y) width \(String(describing: width))") }
            }
        }
    }

    func test420ColourIsPreserved() {
        // Video-range BT.709 red: Y 63, Cb 102, Cr 240 -> about (255, 0, 0).
        let pb = makeBuffer(200, 400, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        fill420(pb, y: 63, cb: 102, cr: 240)
        CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        let p = processor(width: nil)
        _ = p.process(pb, time: 0)
        let px = p.scaledFrame.pixel(100, 200)
        XCTAssertGreaterThan(Int(px.r), 240); XCTAssertLessThan(Int(px.g), 20); XCTAssertLessThan(Int(px.b), 20)
    }

    private func paddedBuffer(_ w: Int, _ h: Int, _ format: OSType) -> CVPixelBuffer {
        // Row alignment 64 makes the stride differ from the width, so a stride error shows.
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any], kCVPixelBufferBytesPerRowAlignmentKey: 64]
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, w, h, format, attrs as CFDictionary, &pb), kCVReturnSuccess)
        return pb!
    }

    /// Non-uniform BGRA content: every pixel differs, so a wrong stride, a swapped channel or a shifted row would show.
    func testBgraContentKeepsItsPositionsAndChannelsAtFullSizeAndScaled() {
        let w = 402, h = 800
        let pb = paddedBuffer(w, h, kCVPixelFormatType_32BGRA)
        XCTAssertNotEqual(CVPixelBufferGetBytesPerRow(pb), w * 4, "the test needs a padded stride")
        // Smooth ramps (so scaling stays predictable): B grows with x, G with y, R falls with x.
        func expected(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) { (255 - x * 255 / (w - 1), y * 255 / (h - 1), x * 255 / (w - 1)) }
        CVPixelBufferLockBaseAddress(pb, [])
        let base = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(pb)
        for y in 0..<h { for x in 0..<w { let e = expected(x, y), i = y * stride + x * 4; base[i] = UInt8(e.b); base[i + 1] = UInt8(e.g); base[i + 2] = UInt8(e.r); base[i + 3] = 255 } }
        CVPixelBufferUnlockBaseAddress(pb, [])
        let full = processor(width: nil)
        _ = full.process(pb, time: 0)
        XCTAssertEqual(full.scaledFrame.width, w)
        for (x, y) in [(0, 0), (1, 799), (200, 400), (401, 0), (123, 777), (300, 5)] {
            let p = full.scaledFrame.pixel(x, y), e = expected(x, y)
            XCTAssertEqual([Int(p.r), Int(p.g), Int(p.b)], [e.r, e.g, e.b], "full size at \(x),\(y)")
        }
        let half = processor(width: 201)
        _ = half.process(pb, time: 0)
        XCTAssertEqual(half.scaledFrame.width, 200)
        for (x, y) in [(10, 20), (100, 200), (190, 380), (50, 390)] {
            let p = half.scaledFrame.pixel(x, y), e = expected(2 * x, 2 * y)
            for (got, want, c) in [(Int(p.r), e.r, "r"), (Int(p.g), e.g, "g"), (Int(p.b), e.b, "b")] { XCTAssertEqual(got, want, accuracy: 5, "scaled \(c) at \(x),\(y)") }
        }
    }

    /// Non-uniform 420 content with a padded stride: luma and chroma ramps, checked against the BT.709 video-range conversion.
    func test420ContentKeepsItsPositionsAtFullSizeAndScaled() {
        let w = 402, h = 800
        let pb = paddedBuffer(w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        XCTAssertNotEqual(CVPixelBufferGetBytesPerRowOfPlane(pb, 0), w, "the test needs a padded stride")
        CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        func yAt(_ x: Int, _ y: Int) -> Double { 40 + Double(x) * 100 / Double(w) + Double(y) * 60 / Double(h) }
        func cbAt(_ cx: Int) -> Double { 90 + Double(cx) * 60 / Double(w / 2) }
        func crAt(_ cy: Int) -> Double { 170 - Double(cy) * 60 / Double(h / 2) }
        CVPixelBufferLockBaseAddress(pb, [])
        let yb = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self), ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let cb = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!.assumingMemoryBound(to: UInt8.self), cs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        for y in 0..<h { for x in 0..<w { yb[y * ys + x] = UInt8(yAt(x, y).rounded()) } }
        for cy in 0..<(h / 2) { for cx in 0..<(w / 2) { cb[cy * cs + cx * 2] = UInt8(cbAt(cx).rounded()); cb[cy * cs + cx * 2 + 1] = UInt8(crAt(cy).rounded()) } }
        CVPixelBufferUnlockBaseAddress(pb, [])
        func rgb(_ x: Int, _ y: Int) -> [Int] {
            let Y = 1.164 * (yAt(x, y) - 16), Cb = cbAt(x / 2) - 128, Cr = crAt(y / 2) - 128
            return [Y + 1.793 * Cr, Y - 0.213 * Cb - 0.533 * Cr, Y + 2.112 * Cb].map { Int(max(0, min(255, $0)).rounded()) }
        }
        let full = processor(width: nil)
        _ = full.process(pb, time: 0)
        XCTAssertEqual(full.scaledFrame.width, w)
        for (x, y) in [(40, 40), (200, 400), (361, 100), (123, 777), (300, 305), (20, 650)] {
            let p = full.scaledFrame.pixel(x, y), e = rgb(x, y)
            for (got, want, c) in [(Int(p.r), e[0], "r"), (Int(p.g), e[1], "g"), (Int(p.b), e[2], "b")] { XCTAssertEqual(got, want, accuracy: 6, "full size \(c) at \(x),\(y)") }
        }
        let half = processor(width: 201)
        _ = half.process(pb, time: 0)
        XCTAssertEqual(half.scaledFrame.width, 200)
        for (x, y) in [(40, 40), (100, 200), (180, 350), (60, 300)] {
            let p = half.scaledFrame.pixel(x, y), e = rgb(2 * x, 2 * y)
            for (got, want, c) in [(Int(p.r), e[0], "r"), (Int(p.g), e[1], "g"), (Int(p.b), e[2], "b")] { XCTAssertEqual(got, want, accuracy: 9, "scaled \(c) at \(x),\(y)") }
        }
    }

    func testAnUnsupportedFormatIsFlaggedNotCrashed() {
        let pb = makeBuffer(64, 64, kCVPixelFormatType_32ARGB)
        XCTAssertEqual(processor(width: nil).process(pb, time: 0).flags, ["unsupported-pixel-format"])
    }

    func testRgbaFramesNarrowerThanTheTargetAreReadInPlaceAndWiderOnesAreScaled() {
        let p = processor(width: 300)
        XCTAssertEqual(p.process(cardScreen(), time: 0, frame: "a").name, "Zapdos")     // 400 wide: scaled to 300
        XCTAssertEqual(p.scaledFrame.width, 300)
        let small = FrameProcessor(textReader: FakeText(), names: names, targetWidth: 750)
        XCTAssertEqual(small.process(cardScreen(), time: 0).name, "Zapdos")             // not scaled up
        XCTAssertEqual(small.scaledFrame.width, 0)
    }

    func testMemoryProbeReportsAFootprintAndAPeak() {
        let probe = MemoryProbe()
        XCTAssertGreaterThan(probe.sample(), 0)
        XCTAssertGreaterThanOrEqual(probe.peakBytes, MemoryProbe.footprintBytes() / 2)
    }
}
