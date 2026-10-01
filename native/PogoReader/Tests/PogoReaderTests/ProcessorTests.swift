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
