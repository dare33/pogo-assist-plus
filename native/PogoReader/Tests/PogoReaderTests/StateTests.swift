import XCTest
import CoreGraphics
import CoreVideo
import ImageIO
@testable import PogoReader

final class StateTests: XCTestCase {
    /// The iPhone's recordings are PNGs tagged ITU-R 709: decoding must give the file's bytes, not a colour-managed copy.
    func testPngDecodingKeepsTheFilesOwnBytesWhateverItsColourSpace() throws {
        let w = 64, h = 32
        let space = CGColorSpace(name: CGColorSpace.itur_709)!
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) { bytes[i * 4] = 8; bytes[i * 4 + 1] = 7; bytes[i * 4 + 2] = 52; bytes[i * 4 + 3] = 255 }       // a dark night sky
        bytes[(5 * w + 9) * 4] = 200; bytes[(5 * w + 9) * 4 + 1] = 100; bytes[(5 * w + 9) * 4 + 2] = 50
        let cg: CGImage = bytes.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-709-\(UUID().uuidString).png")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let img = try decodeRGBA(contentsOf: url)
        XCTAssertEqual(img.width, w)
        let sky = img.pixel(0, 0), mark = img.pixel(9, 5)
        XCTAssertEqual([Int(sky.r), Int(sky.g), Int(sky.b)], [8, 7, 52])
        XCTAssertEqual([Int(mark.r), Int(mark.g), Int(mark.b)], [200, 100, 50])
    }

    private func drawn(_ spec: SyntheticScreen.Spec) -> RGBAImage {
        var img = RGBAImage(width: 1320, height: 2868)
        SyntheticScreen.draw(into: &img, spec)
        return img
    }

    private func bgra(_ img: RGBAImage) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, img.width, img.height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &pb)
        CVPixelBufferLockBaseAddress(pb!, [])
        let base = CVPixelBufferGetBaseAddress(pb!)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(pb!)
        for y in 0..<img.height { for x in 0..<img.width {
            let s = img.index(x, y), d = y * stride + x * 4
            base[d] = img.bytes[s + 2]; base[d + 1] = img.bytes[s + 1]; base[d + 2] = img.bytes[s]; base[d + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(pb!, [])
        return pb!
    }

    /// A reader is a pure function of the frame: what was read before changes nothing (the reused scaled
    /// buffer, the scratch and the Vision request carry no state into the next frame).
    func testAFrameReadsTheSameAloneAndAfterOtherFrames() {
        let a = SyntheticScreen.Spec(name: "Charizard", cp: 2017, hp: 132, ivs: IVs(atk: 12, def: 13, hp: 13))
        let b = SyntheticScreen.Spec(name: "Zubat", cp: 203, hp: 62, ivs: IVs(atk: 9, def: 6, hp: 15))
        let imgA = drawn(a), imgB = drawn(b)
        var dark = RGBAImage(width: 1320, height: 2868)
        dark.fill(Rect(x: 0, y: 0, w: 1320, h: 2868), (8, 7, 52))          // nothing to find
        var small = RGBAImage(width: 600, height: 1300)
        small.fill(Rect(x: 0, y: 0, w: 600, h: 1300), (250, 250, 245))      // another size, so the buffer is reallocated
        func key(_ r: FrameReading) -> String { "\(r.cp as Any)|\(r.name as Any)|\(r.hp as Any)|\(r.ivs as Any)|\(r.fills as Any)|\(r.flags)|\(r.sharpness)|\(r.cpText)|\(r.hpText)|\(r.nameText)" }
        for width in [Int?.none, 750, 500] {
            let alone = key(FrameProcessor(textReader: VisionTextReader(), names: names, targetWidth: width).process(imgB, time: 0, frame: "b"))
            let reused = FrameProcessor(textReader: VisionTextReader(), names: names, targetWidth: width)
            for other in [imgA, dark, small, imgA, dark] { _ = reused.process(other, time: 0, frame: "x") }
            XCTAssertEqual(key(reused.process(imgB, time: 0, frame: "b")), alone, "RGBA, width \(String(describing: width))")
            // Through pixel buffers as the extension gets them.
            let aloneBuf = key(FrameProcessor(textReader: VisionTextReader(), names: names, targetWidth: width).process(bgra(imgB), time: 0, frame: "b"))
            let reusedBuf = FrameProcessor(textReader: VisionTextReader(), names: names, targetWidth: width)
            for other in [imgA, dark, imgA] { _ = reusedBuf.process(bgra(other), time: 0, frame: "x") }
            XCTAssertEqual(key(reusedBuf.process(bgra(imgB), time: 0, frame: "b")), aloneBuf, "BGRA, width \(String(describing: width))")
            XCTAssertEqual(aloneBuf.contains("Zubat"), true)
        }
    }

    /// The pixel half alone: layout and bars of a frame do not depend on the frame before it.
    func testAnalysisIsIndependentOfThePreviousFrame() {
        let b = SyntheticScreen.Spec(name: "Zubat", cp: 203, hp: 62, ivs: IVs(atk: 9, def: 6, hp: 15))
        let imgB = drawn(b), imgA = drawn(SyntheticScreen.Spec(name: "Charizard", cp: 2017, hp: 132, ivs: IVs(atk: 12, def: 13, hp: 13)))
        let alone = FrameProcessor.cropsOnly(names: names, targetWidth: 750).analyse(imgB, time: 0, frame: "b").0
        let p = FrameProcessor.cropsOnly(names: names, targetWidth: 750)
        _ = p.analyse(imgA, time: 0, frame: "a")
        XCTAssertEqual(p.analyse(imgB, time: 0, frame: "b").0, alone)
    }
}
