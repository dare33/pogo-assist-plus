import Foundation
import Accelerate
import CoreVideo

public enum PixelBufferError: Error, CustomStringConvertible {
    case message(String)
    public var description: String { if case .message(let m) = self { return m }; return "" }
}

/// Test and tool helper: RGBA frames into the pixel-buffer formats ReplayKit delivers.
public enum PixelBuffers {
    /// A BGRA buffer with the image's pixels (rows padded to the system's alignment).
    public static func bgra(from img: RGBAImage) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, img.width, img.height, kCVPixelFormatType_32BGRA,
                                  [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]] as CFDictionary, &pb) == kCVReturnSuccess, let made = pb else {
            throw PixelBufferError.message("cannot create a \(img.width)x\(img.height) BGRA buffer")
        }
        CVPixelBufferLockBaseAddress(made, [])
        defer { CVPixelBufferUnlockBaseAddress(made, []) }
        let base = CVPixelBufferGetBaseAddress(made)!.assumingMemoryBound(to: UInt8.self), stride = CVPixelBufferGetBytesPerRow(made)
        for y in 0..<img.height {
            let row = base + y * stride
            for x in 0..<img.width {
                let s = img.index(x, y)
                row[x * 4] = img.bytes[s + 2]; row[x * 4 + 1] = img.bytes[s + 1]; row[x * 4 + 2] = img.bytes[s]; row[x * 4 + 3] = 255
            }
        }
        return made
    }
}

/// Converts RGBA frames into one reused full-size 420 bi-planar pixel buffer, as the extension
/// would receive it. The buffer is allocated once; every frame is written into it.
public final class Pixel420Maker {
    public let fullRange: Bool
    private var buffer: CVPixelBuffer?
    private var info = vImage_ARGBToYpCbCr()
    private var ready = false

    public init(fullRange: Bool) { self.fullRange = fullRange }

    public func make(from img: RGBAImage) throws -> CVPixelBuffer {
        let w = img.width & ~1, h = img.height & ~1
        if buffer == nil || CVPixelBufferGetWidth(buffer!) != w || CVPixelBufferGetHeight(buffer!) != h {
            var pb: CVPixelBuffer?
            let format = fullRange ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
            guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, format, attrs as CFDictionary, &pb) == kCVReturnSuccess, let made = pb else {
                throw PixelBufferError.message("cannot create a \(w)x\(h) pixel buffer")
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
        if err != kvImageNoError { throw PixelBufferError.message("420 conversion failed (\(err))") }
        return pb
    }
}
