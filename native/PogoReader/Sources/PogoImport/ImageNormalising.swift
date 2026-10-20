import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

public enum ImageStagingError: Error, Equatable, CustomStringConvertible {
    case cannotDecode
    case tooSmall(width: Int, height: Int)
    case cannotEncode
    public var description: String {
        switch self {
        case .cannotDecode: return "The image could not be opened."
        case .tooSmall(let w, let h): return "The image is only \(w) x \(h) pixels, too small to read."
        case .cannotEncode: return "The image could not be prepared."
        }
    }
}

/// The image handling the share extension and the app both need, and nothing else: no Vision, no species table, no reader. Small on purpose, since the share extension links it.
public enum ImageNormalising {
    /// Longest side kept. An image larger than this is scaled down while it is decoded, never enlarged.
    public static let maxLongSide = 4096
    public static let minShortSide = 300

    /// The upright, size-limited first frame of an image source (orientation applied, so nothing downstream needs the tag).
    public static func uprightImage(from src: CGImageSource) -> CGImage? {
        guard CGImageSourceGetCount(src) > 0 else { return nil }
        // The thumbnail size is a ceiling, but ask for no more than the stored longest side so a small image is certainly not enlarged.
        var limit = maxLongSide
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int { limit = min(maxLongSide, max(w, h)) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    /// SHA-256 of a file's bytes, read in chunks (a share extension has little memory), as lowercase hex.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hex(hasher.finalize())
    }

    public static func sha256(of data: Data) -> String { hex(SHA256.hash(data: data)) }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 { digest.map { String(format: "%02x", $0) }.joined() }

    /// An image to the bytes that are kept while it waits: PNG (lossless, so the reader sees what it would have seen), upright, size-limited, and carrying NO metadata:
    /// the pixels and their colour profile only. A screenshot's EXIF, GPS, TIFF, IPTC and maker data, creation dates and thumbnails are not copied. Nothing else about the file survives.
    public static func stagedPNG(from src: CGImageSource) throws -> (data: Data, width: Int, height: Int) {
        guard let cg = uprightImage(from: src), cg.width > 0, cg.height > 0 else { throw ImageStagingError.cannotDecode }
        guard min(cg.width, cg.height) >= minShortSide else { throw ImageStagingError.tooSmall(width: cg.width, height: cg.height) }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { throw ImageStagingError.cannotEncode }
        CGImageDestinationAddImage(dest, cg, nil)   // no properties dictionary: no orientation, no metadata
        guard CGImageDestinationFinalize(dest) else { throw ImageStagingError.cannotEncode }
        return (out as Data, cg.width, cg.height)
    }
}
