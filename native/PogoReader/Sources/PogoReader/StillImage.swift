import Foundation
import CoreGraphics
import ImageIO
import PogoImport

public enum StillImageError: Error, Equatable, CustomStringConvertible {
    /// ImageIO cannot decode it (not an image, truncated, or an encoding this system does not read).
    case cannotDecode
    /// The image is smaller than any Pokémon GO screen could be at a size the reader can use.
    case tooSmall(width: Int, height: Int)

    public var description: String {
        switch self {
        case .cannotDecode: return "The image could not be opened."
        case .tooSmall(let w, let h): return "The image is only \(w) x \(h) pixels, too small to read."
        }
    }
}

/// A still image (a screenshot from Photos) to the RGBA buffer `FrameReader` reads. Not a video frame: the reader is given the one image once.
///
/// The reader's thresholds were tuned on sRGB pixel values (the broadcast delivers them; every recorded frame set is tagged sRGB / BT.709), while an iPhone saves
/// its screenshots in Display P3. `decodeRGBA` keeps a file's own bytes, which is right for a PNG frame of a recording and reads P3 screenshots too (the Rayquaza and
/// Nickit fixtures read the same either way). A screenshot is converted to sRGB here instead, so a still reaches the reader with the values a broadcast frame would have.
/// Orientation is applied (a screenshot is upright already; a photo may carry an EXIF turn), and an image longer than `maxLongSide` is scaled down while it is
/// decoded, never up, so a 48 MP picture costs the same memory as a screenshot. Alpha is dropped (drawn over black; a screenshot has none).
public enum StillImage {
    public static let maxLongSide = ImageNormalising.maxLongSide
    /// A Pokémon GO detail screen is never read below this on its short side: the CP text would be a few pixels high.
    public static let minShortSide = ImageNormalising.minShortSide

    public static func decode(contentsOf url: URL) throws -> RGBAImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw StillImageError.cannotDecode }
        return try decode(source: src)
    }

    public static func decode(data: Data) throws -> RGBAImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { throw StillImageError.cannotDecode }
        return try decode(source: src)
    }

    private static func decode(source src: CGImageSource) throws -> RGBAImage {
        guard let cg = ImageNormalising.uprightImage(from: src), cg.width > 0, cg.height > 0 else { throw StillImageError.cannotDecode }
        guard min(cg.width, cg.height) >= minShortSide else { throw StillImageError.tooSmall(width: cg.width, height: cg.height) }
        return try rgba(from: cg)
    }

    /// Draw into an sRGB bitmap (the broadcast's values), packed RGBA, alpha skipped.
    public static func rgba(from cg: CGImage) throws -> RGBAImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw StillImageError.cannotDecode }
        var img = RGBAImage(width: cg.width, height: cg.height)
        let ok = img.bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return true
        }
        if !ok { throw StillImageError.cannotDecode }
        return img
    }
}
