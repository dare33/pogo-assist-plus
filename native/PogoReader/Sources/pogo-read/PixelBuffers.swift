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
    do { return try decodeRGBA(contentsOf: url) } catch { throw ToolError.message("\(error)") }
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
