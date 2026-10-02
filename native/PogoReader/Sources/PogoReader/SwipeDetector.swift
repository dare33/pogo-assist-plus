import Foundation
import CoreVideo

/// The cheap swipe signature of the JS reference (`src/extract/segment.js`), for the extension's callback: a
/// swipe between two Pokémon makes the CP band (top 12% of the frame) and the name band (36% to 58%) change
/// sharply for a few frames, while a Pokémon being looked at leaves them still even when its sprite animates.
/// The signature is 40 luma samples across x 10-90% on one row per 1% of the height in those two bands; a
/// frame whose mean absolute difference from the previous frame's signature exceeds `threshold` (12 on
/// 0-255 luma, the JS value) is a swipe frame.
///
/// It reads the Y plane of a 4:2:0 buffer (or luma from BGRA) straight from the buffer: no scaled copy, no
/// allocation after the first frame of a size beyond two small reused arrays. It is fed EVERY kept frame
/// (5 fps), including those the reader will drop because Vision is busy, which is the point: under load the
/// anchor-less frames of a swipe are dropped with everything else, but the signature still sees them.
public struct SwipeDetector {
    public static let threshold = 12.0
    static let cols = 40
    /// (first row fraction, number of 1% rows): the CP band and the name band.
    static let bands: [(fy: Double, rows: Int)] = [(0.0, 12), (0.36, 22)]
    static var sampleCount: Int { cols * bands.reduce(0) { $0 + $1.rows } }

    private var previous = [Float]()
    private var current = [Float]()
    private var havePrevious = false
    private var xs = [Int](), ys = [Int]()
    private var sizeKey = (0, 0)

    public init() {}

    public mutating func reset() { havePrevious = false }

    /// Mean absolute luma difference from the previous frame fed; nil for the first.
    public mutating func feed(_ pixelBuffer: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        switch format {
        case kCVPixelFormatType_32BGRA:
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let p = base.assumingMemoryBound(to: UInt8.self)
            return sample(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer)) { x, y in
                let i = y * stride + x * 4
                return 0.299 * Float(p[i + 2]) + 0.587 * Float(p[i + 1]) + 0.114 * Float(p[i])
            }
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let p = base.assumingMemoryBound(to: UInt8.self)
            let video = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            return sample(width: CVPixelBufferGetWidthOfPlane(pixelBuffer, 0), height: CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)) { x, y in
                let v = Float(p[y * stride + x])
                return video ? (v - 16) * (255.0 / 219.0) : v     // video range to the 0-255 scale the threshold is on
            }
        default:
            return nil
        }
    }

    /// The same on an RGBA image (the tool's PNG path).
    public mutating func feed(_ img: RGBAImage) -> Double? {
        sample(width: img.width, height: img.height) { x, y in Float(img.luma(x, y)) }
    }

    private mutating func sample(width: Int, height: Int, _ luma: (Int, Int) -> Float) -> Double? {
        guard width > 0, height > 0 else { return nil }
        if sizeKey != (width, height) || ys.isEmpty {
            sizeKey = (width, height)
            xs = (0..<Self.cols).map { c in min(width - 1, Int(((0.1 + 0.8 * (Double(c) + 0.5) / Double(Self.cols)) * Double(width)).rounded())) }
            ys = Self.bands.flatMap { band in (0..<band.rows).map { k in min(height - 1, Int(((band.fy + 0.01 * Double(k)) * Double(height)).rounded())) } }
            havePrevious = false
        }
        if current.count != Self.sampleCount { current = [Float](repeating: 0, count: Self.sampleCount); previous = current }
        var i = 0
        for y in ys { for x in xs { current[i] = luma(x, y); i += 1 } }
        defer { swap(&previous, &current) }
        guard havePrevious else { havePrevious = true; return nil }
        var d: Float = 0
        for k in 0..<current.count { d += abs(current[k] - previous[k]) }
        return Double(d) / Double(current.count)
    }
}
