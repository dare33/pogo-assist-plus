import Foundation
import Accelerate

// vImage scaling helpers. vImage works on the bytes in place of a CIContext or UIKit image, which
// keeps the extension's allocations small and predictable.

enum Scale {
    /// Resample a packed 4-channel 8-bit image (channel order does not matter, all four are scaled
    /// alike) from `src` into `dst`. Returns false if vImage reports an error.
    static func argb8888(src: UnsafeRawPointer, srcWidth: Int, srcHeight: Int, srcRowBytes: Int,
                         dst: UnsafeMutableRawPointer, dstWidth: Int, dstHeight: Int,
                         temp: UnsafeMutableRawPointer? = nil) -> Bool {
        var s = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: src), height: vImagePixelCount(srcHeight), width: vImagePixelCount(srcWidth), rowBytes: srcRowBytes)
        var d = vImage_Buffer(data: dst, height: vImagePixelCount(dstHeight), width: vImagePixelCount(dstWidth), rowBytes: dstWidth * 4)
        return vImageScale_ARGB8888(&s, &d, temp, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError
    }

    /// Temp-buffer size vImage needs for the scalings used with `flags`.
    static func tempSizeARGB(srcWidth: Int, srcHeight: Int, dstWidth: Int, dstHeight: Int) -> Int {
        var s = vImage_Buffer(data: nil, height: vImagePixelCount(srcHeight), width: vImagePixelCount(srcWidth), rowBytes: srcWidth * 4)
        var d = vImage_Buffer(data: nil, height: vImagePixelCount(dstHeight), width: vImagePixelCount(dstWidth), rowBytes: dstWidth * 4)
        let n = vImageScale_ARGB8888(&s, &d, nil, vImage_Flags(kvImageGetTempBufferSize | kvImageHighQualityResampling))
        return max(0, n)
    }
}

/// Scale a small crop up so Vision gets text of a reasonable size. Returns the input unchanged when
/// it is already tall enough (never scales down) or when scaling fails.
public func upscaled(_ img: RGBAImage, toHeight target: Double, maxFactor: Double = Tuning.maxUpscale) -> RGBAImage {
    guard img.width > 0, img.height > 0, Double(img.height) < target else { return img }
    let factor = min(maxFactor, target / Double(img.height))
    let w = max(1, Int((Double(img.width) * factor).rounded())), h = max(1, Int((Double(img.height) * factor).rounded()))
    var out = RGBAImage(width: w, height: h)
    let ok = img.bytes.withUnsafeBytes { s in
        out.bytes.withUnsafeMutableBytes { d in
            Scale.argb8888(src: s.baseAddress!, srcWidth: img.width, srcHeight: img.height, srcRowBytes: img.width * 4,
                           dst: d.baseAddress!, dstWidth: w, dstHeight: h)
        }
    }
    return ok ? out : img
}
