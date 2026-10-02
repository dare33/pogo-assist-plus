import Foundation
import CoreGraphics
import ImageIO

public enum PNGDecodeError: Error, CustomStringConvertible {
    case cannotDecode(String)
    public var description: String { if case .cannotDecode(let p) = self { return "cannot decode \(p)" }; return "" }
}

/// Decode a PNG file to RGBA bytes WITHOUT colour conversion: the file's own bytes, as pngjs gives the
/// JS reader. A PNG tagged with a colour space (the iPhone's screen recordings are ITU-R 709) would
/// otherwise be converted to device RGB when drawn, which darkens a dark sky from (8, 7, 52) to (1, 1, 41)
/// and moves the content rectangle and every anchor with it (it made whole Pokémon unreadable on the
/// darentas clips). The bitmap context is created in the image's own colour space, so drawing is a copy.
public func decodeRGBA(contentsOf url: URL) throws -> RGBAImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw PNGDecodeError.cannotDecode(url.path)
    }
    var img = RGBAImage(width: cg.width, height: cg.height)
    let ok = img.bytes.withUnsafeMutableBytes { raw -> Bool in
        // The image's own space when it is an RGB one a bitmap context accepts, else device RGB.
        for space in [cg.colorSpace, CGColorSpaceCreateDeviceRGB()].compactMap({ $0 }) {
            guard let ctx = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { continue }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        return false
    }
    if !ok { throw PNGDecodeError.cannotDecode(url.path) }
    return img
}
