import XCTest
import CoreVideo
@testable import PogoReader

/// The device path (a 4:2:0 or BGRA pixel buffer, scaled by vImage) must read what the RGBA path reads, at the
/// sizes real frames come in, including an odd-ish one. The muted style is the iPad's red card and dull green HP
/// bar, which a chroma round trip nearly loses: it is what failed (HP bar not found) when the pixel-buffer path
/// first met raw iPad frames.
final class FormatParityTests: XCTestCase {
    private let spec = SyntheticScreen.Spec(name: "Staraptor", cp: 1984, hp: 140, ivs: IVs(atk: 15, def: 12, hp: 12))
    private let sizes = [(1320, 2868), (1488, 2266), (1301, 2147)]

    private func meanAbsDiff(_ a: RGBAImage, _ b: RGBAImage) -> Double {
        XCTAssertEqual(a.width, b.width); XCTAssertEqual(a.height, b.height)
        var sum = 0.0, n = 0.0
        for y in stride(from: 0, to: min(a.height, b.height), by: 7) {
            for x in stride(from: 0, to: min(a.width, b.width), by: 7) {
                let p = a.pixel(x, y), q = b.pixel(x, y)
                sum += abs(Double(p.r) - Double(q.r)) + abs(Double(p.g) - Double(q.g)) + abs(Double(p.b) - Double(q.b)); n += 3
            }
        }
        return sum / n
    }

    /// The conversion itself is right: black comes back as black and white as white (and a dark purple as itself), for
    /// video and full range and for BT.601 and BT.709, at full size and scaled.
    func testYCbCrConversionIsExactAtTheEnds() throws {
        let colours: [(UInt8, UInt8, UInt8)] = [(0, 0, 0), (255, 255, 255), (8, 7, 52), (40, 20, 80), (20, 15, 40), (102, 231, 170)]
        for full in [false, true] {
            for bt601 in [false, true] {
                for c in colours {
                    var img = RGBAImage(width: 400, height: 800)
                    img.fill(Rect(x: 0, y: 0, w: 400, h: 800), c)
                    let pb = try Pixel420Maker(fullRange: full, bt601: bt601).make(from: img)
                    for width in [Int?.none, 200] {
                        let p = FrameProcessor(textReader: NullTextReader(), names: [], targetWidth: width)
                        _ = p.analyse(pb, time: 0)
                        let px = p.scaledFrame.pixel(p.scaledFrame.width / 2, p.scaledFrame.height / 2)
                        for (got, want, ch) in [(Int(px.r), Int(c.0), "r"), (Int(px.g), Int(c.1), "g"), (Int(px.b), Int(c.2), "b")] {
                            XCTAssertEqual(got, want, accuracy: 2, "\(ch) of \(c) full \(full) bt601 \(bt601) width \(String(describing: width))")
                        }
                    }
                }
            }
        }
    }

    func testEveryFormatAndSizeReadsTheSameAsRgba() throws {
        for style in [SyntheticScreen.Style.phone, .padMuted, .darkSky] {
            for (w, h) in sizes {
                var img = RGBAImage(width: w, height: h)
                SyntheticScreen.draw(into: &img, spec, style: style)
                for width in [Int?.some(750), nil] {
                    let label = "\(w)x\(h) \(style.hpBar) width \(String(describing: width))"
                    let rgba = FrameProcessor(textReader: VisionTextReader(), names: names, targetWidth: width)
                    let reference = rgba.process(img, time: 0, frame: "rgba")
                    XCTAssertEqual(reference.cp, 1984, "RGBA \(label)")
                    XCTAssertEqual(reference.name, "Staraptor", "RGBA \(label)")
                    XCTAssertEqual(reference.hp, HP(current: 140, max: 140), "RGBA \(label)")
                    XCTAssertEqual(reference.ivs, spec.ivs, "RGBA \(label)")
                    XCTAssertEqual(reference.flags, [], "RGBA \(label)")
                    let refFrame = rgba.scaledFrame.width > 0 ? rgba.scaledFrame : img
                    var buffers: [(String, CVPixelBuffer)] = [("BGRA", try PixelBuffers.bgra(from: img))]
                    buffers.append(("420v", try Pixel420Maker(fullRange: false).make(from: img)))
                    buffers.append(("420f", try Pixel420Maker(fullRange: true).make(from: img)))
                    for (format, pb) in buffers {
                        let p = FrameProcessor(textReader: VisionTextReader(), names: names, targetWidth: width)
                        let r = p.process(pb, time: 0, frame: format)
                        XCTAssertEqual(r.cp, 1984, "\(format) \(label): \(r.cpText)")
                        XCTAssertEqual(r.name, "Staraptor", "\(format) \(label): \(r.nameText) \(r.flags)")
                        XCTAssertEqual(r.hp, HP(current: 140, max: 140), "\(format) \(label): \(r.hpText)")
                        XCTAssertEqual(r.ivs, spec.ivs, "\(format) \(label)")
                        XCTAssertEqual(r.flags, [], "\(format) \(label)")
                        // Near-identical pixels (the frame is the same up to the 4:2:0 chroma loss).
                        let got = p.scaledFrame
                        if got.width == refFrame.width && got.height == refFrame.height {
                            XCTAssertLessThan(meanAbsDiff(got, refFrame), format == "BGRA" ? 0.5 : 6, "pixels \(format) \(label)")
                        }
                    }
                }
            }
        }
    }
}
