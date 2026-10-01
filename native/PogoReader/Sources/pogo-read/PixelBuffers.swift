import Foundation
import Accelerate
import CoreGraphics
import CoreText
import CoreVideo
import ImageIO
import PogoReader

// Mac-tool helpers: PNG decoding, RGBA -> 420 bi-planar CVPixelBuffer (the format ReplayKit
// delivers), and the synthetic frame drawn with CoreGraphics.

enum ToolError: Error, CustomStringConvertible {
    case message(String)
    var description: String { if case .message(let m) = self { return m }; return "" }
}

/// PNG files of a directory in natural filename order (f2.png before f10.png), or one PNG file.
func pngPaths(_ input: String) throws -> [URL] {
    let url = URL(fileURLWithPath: input)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: input, isDirectory: &isDir) else { throw ToolError.message("no such file or directory: \(input)") }
    if !isDir.boolValue { return [url] }
    let names = try FileManager.default.contentsOfDirectory(atPath: input).filter { $0.lowercased().hasSuffix(".png") }
    return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { url.appendingPathComponent($0) }
}

func decodePNG(_ url: URL) throws -> RGBAImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw ToolError.message("cannot decode \(url.path)")
    }
    var img = RGBAImage(width: cg.width, height: cg.height)
    let ok = img.bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        return true
    }
    if !ok { throw ToolError.message("cannot create a bitmap for \(url.path)") }
    return img
}

/// Converts RGBA frames into one reused full-size 420 bi-planar pixel buffer, as the extension
/// would receive it. The buffer is allocated once; every frame is written into it.
final class Pixel420Maker {
    let fullRange: Bool
    private var buffer: CVPixelBuffer?
    private var info = vImage_ARGBToYpCbCr()
    private var ready = false

    init(fullRange: Bool) { self.fullRange = fullRange }

    func make(from img: RGBAImage) throws -> CVPixelBuffer {
        let w = img.width & ~1, h = img.height & ~1
        if buffer == nil || CVPixelBufferGetWidth(buffer!) != w || CVPixelBufferGetHeight(buffer!) != h {
            var pb: CVPixelBuffer?
            let format = fullRange ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
            guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, format, attrs as CFDictionary, &pb) == kCVReturnSuccess, let made = pb else {
                throw ToolError.message("cannot create a \(w)x\(h) pixel buffer")
            }
            CVBufferSetAttachment(made, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
            buffer = made
        }
        if !ready {
            var range = fullRange
                ? vImage_YpCbCrPixelRange(Yp_bias: 0, CbCr_bias: 128, YpRangeMax: 255, CbCrRangeMax: 255, YpMax: 255, YpMin: 1, CbCrMax: 255, CbCrMin: 0)
                : vImage_YpCbCrPixelRange(Yp_bias: 16, CbCr_bias: 128, YpRangeMax: 235, CbCrRangeMax: 240, YpMax: 255, YpMin: 0, CbCrMax: 255, CbCrMin: 1)
            vImageConvert_ARGBToYpCbCr_GenerateConversion(kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2!, &range, &info, kvImageARGB8888, kvImage420Yp8_CbCr8, vImage_Flags(kvImageNoFlags))
            ready = true
        }
        let pb = buffer!
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let err: vImage_Error = img.bytes.withUnsafeBytes { raw in
            var src = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: raw.baseAddress), height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: img.width * 4)
            var yDst = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(pb, 0), height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pb, 0))
            var cDst = vImage_Buffer(data: CVPixelBufferGetBaseAddressOfPlane(pb, 1), height: vImagePixelCount(h / 2), width: vImagePixelCount(w / 2), rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pb, 1))
            let map: [UInt8] = [3, 0, 1, 2]   // RGBA source -> ARGB order
            return vImageConvert_ARGB8888To420Yp8_CbCr8(&src, &yDst, &cDst, &info, map, vImage_Flags(kvImageNoFlags))
        }
        if err != kvImageNoError { throw ToolError.message("420 conversion failed (\(err))") }
        return pb
    }
}

/// Write an RGBA image as a PNG (used to save synthetic frames, so they can be read back as PNG input).
func writePNG(_ img: RGBAImage, to url: URL) throws {
    var copy = img
    let cg: CGImage? = copy.bytes.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
    }
    guard let image = cg, let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw ToolError.message("cannot write \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { throw ToolError.message("cannot write \(url.path)") }
}
