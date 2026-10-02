import Foundation
import Accelerate
import CoreVideo

/// Wraps a text reader to sample memory after every recognition (the peak is during Vision).
private final class ProbedTextReader: TextReader {
    let inner: TextReader
    let probe: MemoryProbe
    init(_ inner: TextReader, _ probe: MemoryProbe) { self.inner = inner; self.probe = probe }
    func read(_ image: RGBAImage, kind: TextKind) -> TextRead {
        let r = inner.read(image, kind: kind)
        probe.sample()
        return r
    }
}

/// The one entry point used by both the broadcast extension and the Mac tool: a screen frame in,
/// a `FrameReading` out. The frame is scaled into ONE reused RGBA buffer (vImage; width
/// `targetWidth`, height by aspect) and read there; no full-size copy of the frame is ever made, so
/// per-frame memory is the scaled buffer plus Vision's working set for the small crops.
public final class FrameProcessor {
    /// Width the frame is scaled to before reading; nil reads the frame at its own size.
    public let targetWidth: Int?
    public let reader: FrameReader
    public let memory: MemoryProbe?

    // One RGBA buffer, allocated at first use and reused for every frame of the same size.
    private var scaled = RGBAImage(width: 0, height: 0)
    // Scaled 420 planes (only when the source is YCbCr and is being scaled) and vImage's scratch.
    private var yPlane = [UInt8]()
    private var cbcrPlane = [UInt8]()
    private var temp: UnsafeMutableRawPointer?
    private var tempSize = 0
    private var conversions = [String: vImage_YpCbCrToARGB]()

    public init(textReader: TextReader? = nil, names: [NameCandidate], targetWidth: Int? = 750, memory: MemoryProbe? = nil) {
        self.targetWidth = targetWidth
        self.memory = memory
        let base: TextReader = textReader ?? VisionTextReader()
        self.reader = FrameReader(text: memory.map { ProbedTextReader(base, $0) } ?? base, names: names)
    }

    deinit { temp?.deallocate() }

    /// The reused scaled buffer as last filled (for tests).
    var scaledFrame: RGBAImage { scaled }

    /// A processor that only does the pixel work (`analyse`): no Vision request is ever created. The
    /// broadcast extension uses it in "save crops" mode.
    public static func cropsOnly(names: [NameCandidate], targetWidth: Int? = 750, memory: MemoryProbe? = nil) -> FrameProcessor {
        FrameProcessor(textReader: NullTextReader(), names: names, targetWidth: targetWidth, memory: memory)
    }

    // MARK: - RGBA input (PNG frames)

    /// Read an RGBA frame (a decoded PNG). Scaled into the reused buffer when wider than the target;
    /// read in place otherwise.
    public func process(_ image: RGBAImage, time: Double, frame: String? = nil) -> FrameReading {
        autoreleasepool {
            guard let working = prepared(image) else { var r = FrameReading(frame: frame, time: time); r.flags.append("scale-failed"); return r }
            return reader.read(working, frame: frame, time: time)
        }
    }

    /// The pixel half only: anchors, bars and the small text crops of an RGBA frame.
    public func analyse(_ image: RGBAImage, time: Double, frame: String? = nil) -> (FrameAnalysis, FrameCrops?) {
        autoreleasepool {
            guard let working = prepared(image) else { var a = FrameAnalysis(frame: frame, time: time); a.flags.append("scale-failed"); return (a, nil) }
            let r = reader.analyse(working, frame: frame, time: time)
            memory?.sample()
            return r
        }
    }

    /// The frame to read: the input itself when no wider than the target, else scaled into the reused buffer.
    private func prepared(_ image: RGBAImage) -> RGBAImage? {
        guard let tw = targetWidth, image.width > tw else { memory?.sample(); return image }
        let (dw, dh) = scaledSize(srcWidth: image.width, srcHeight: image.height)
        prepare(width: dw, height: dh, scratchFor: (image.width, image.height))
        let ok = image.bytes.withUnsafeBytes { s in
            scaled.bytes.withUnsafeMutableBytes { d in
                Scale.argb8888(src: s.baseAddress!, srcWidth: image.width, srcHeight: image.height, srcRowBytes: image.width * 4,
                               dst: d.baseAddress!, dstWidth: dw, dstHeight: dh, temp: temp)
            }
        }
        memory?.sample()
        return ok ? scaled : nil
    }

    // MARK: - CVPixelBuffer input (ReplayKit)

    /// Read a ReplayKit frame: 420 bi-planar YCbCr (video or full range) or BGRA.
    public func process(_ pixelBuffer: CVPixelBuffer, time: Double, frame: String? = nil) -> FrameReading {
        autoreleasepool {
            guard fill(from: pixelBuffer) else {
                var r = FrameReading(frame: frame, time: time); r.flags.append("unsupported-pixel-format"); return r
            }
            memory?.sample()
            return reader.read(scaled, frame: frame, time: time)
        }
    }

    /// The pixel half only, for a ReplayKit frame.
    public func analyse(_ pixelBuffer: CVPixelBuffer, time: Double, frame: String? = nil) -> (FrameAnalysis, FrameCrops?) {
        autoreleasepool {
            guard fill(from: pixelBuffer) else {
                var a = FrameAnalysis(frame: frame, time: time); a.flags.append("unsupported-pixel-format"); return (a, nil)
            }
            memory?.sample()
            let r = reader.analyse(scaled, frame: frame, time: time)
            memory?.sample()
            return r
        }
    }

    /// Size the frame is read at: `targetWidth` wide (even), height by aspect (even); or the frame's
    /// own size, rounded down to even, when no target is set or the frame is not wider than it.
    private func scaledSize(srcWidth: Int, srcHeight: Int) -> (Int, Int) {
        guard let tw = targetWidth, srcWidth > tw else { return (srcWidth & ~1, srcHeight & ~1) }
        let dw = tw & ~1
        let dh = max(2, Int((Double(srcHeight) * Double(dw) / Double(srcWidth)).rounded()) & ~1)
        return (dw, dh)
    }

    /// Make `scaled` the right size (allocated once, reused) and the scratch buffer big enough.
    private func prepare(width: Int, height: Int, scratchFor src: (Int, Int)) {
        if scaled.width != width || scaled.height != height { scaled = RGBAImage(width: width, height: height) }
        let need = Scale.tempSizeARGB(srcWidth: src.0, srcHeight: src.1, dstWidth: width, dstHeight: height)
        if need > tempSize { temp?.deallocate(); temp = UnsafeMutableRawPointer.allocate(byteCount: need, alignment: 64); tempSize = need }
    }

    private func ensureTemp(_ need: Int) {
        if need > tempSize { temp?.deallocate(); temp = UnsafeMutableRawPointer.allocate(byteCount: need, alignment: 64); tempSize = need }
    }

    private func fill(from pb: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let format = CVPixelBufferGetPixelFormatType(pb)
        switch format {
        case kCVPixelFormatType_32BGRA:
            return fillFromBGRA(pb)
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            return fillFrom420(pb, fullRange: format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        default:
            return false
        }
    }

    private func fillFromBGRA(_ pb: CVPixelBuffer) -> Bool {
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return false }
        let sw = CVPixelBufferGetWidth(pb), sh = CVPixelBufferGetHeight(pb), rowBytes = CVPixelBufferGetBytesPerRow(pb)
        let (dw, dh) = scaledSize(srcWidth: sw, srcHeight: sh)
        prepare(width: dw, height: dh, scratchFor: (sw, sh))
        let map: [UInt8] = [2, 1, 0, 3]     // BGRA -> RGBA
        if dw == sw & ~1 && dh == sh & ~1 && (targetWidth == nil || sw <= targetWidth!) {
            // Full size: swap channels straight from the source into the one buffer.
            var s = vImage_Buffer(data: base, height: vImagePixelCount(dh), width: vImagePixelCount(dw), rowBytes: rowBytes)
            return scaled.bytes.withUnsafeMutableBytes { d in
                var dst = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(dh), width: vImagePixelCount(dw), rowBytes: dw * 4)
                return vImagePermuteChannels_ARGB8888(&s, &dst, map, vImage_Flags(kvImageNoFlags)) == kvImageNoError
            }
        }
        let ok = scaled.bytes.withUnsafeMutableBytes { d in
            Scale.argb8888(src: base, srcWidth: sw, srcHeight: sh, srcRowBytes: rowBytes, dst: d.baseAddress!, dstWidth: dw, dstHeight: dh, temp: temp)
        }
        guard ok else { return false }
        return scaled.bytes.withUnsafeMutableBytes { d in
            var buf = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(dh), width: vImagePixelCount(dw), rowBytes: dw * 4)
            return vImagePermuteChannels_ARGB8888(&buf, &buf, map, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
    }

    private func fillFrom420(_ pb: CVPixelBuffer, fullRange: Bool) -> Bool {
        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0), let cBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else { return false }
        let sw = CVPixelBufferGetWidthOfPlane(pb, 0), sh = CVPixelBufferGetHeightOfPlane(pb, 0)
        let yRow = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), cRow = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        let (dw, dh) = scaledSize(srcWidth: sw, srcHeight: sh)
        prepare(width: dw, height: dh, scratchFor: (sw, sh))
        let info = conversion(fullRange: fullRange, matrix601: Self.isBT601(pb))
        let flags = vImage_Flags(kvImageNoFlags)
        var infoVar = info
        // ARGB out -> RGBA: destination channel i takes source channel map[i].
        let map: [UInt8] = [1, 2, 3, 0]
        let scaling = !(dw == sw & ~1 && dh == sh & ~1)
        var srcY = vImage_Buffer(data: yBase, height: vImagePixelCount(dh), width: vImagePixelCount(dw), rowBytes: yRow)
        var srcC = vImage_Buffer(data: cBase, height: vImagePixelCount(dh / 2), width: vImagePixelCount(dw / 2), rowBytes: cRow)
        if !scaling {
            // Full size: convert straight from the source planes into the one RGBA buffer.
            return scaled.bytes.withUnsafeMutableBytes { d in
                var dst = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(dh), width: vImagePixelCount(dw), rowBytes: dw * 4)
                return vImageConvert_420Yp8_CbCr8ToARGB8888(&srcY, &srcC, &dst, &infoVar, map, 255, flags) == kvImageNoError
            }
        }
        // Scale the planes (Y at target size, CbCr at half) and convert the small result. The source is
        // never copied at full size.
        if yPlane.count != dw * dh { yPlane = [UInt8](repeating: 0, count: dw * dh) }
        if cbcrPlane.count != (dw / 2) * (dh / 2) * 2 { cbcrPlane = [UInt8](repeating: 0, count: (dw / 2) * (dh / 2) * 2) }
        var fullY = vImage_Buffer(data: yBase, height: vImagePixelCount(sh), width: vImagePixelCount(sw), rowBytes: yRow)
        var fullC = vImage_Buffer(data: cBase, height: vImagePixelCount(sh / 2), width: vImagePixelCount(sw / 2), rowBytes: cRow)
        let scaleFlags = vImage_Flags(kvImageHighQualityResampling)
        var dummy = vImage_Buffer(data: nil, height: vImagePixelCount(dh), width: vImagePixelCount(dw), rowBytes: dw)
        let needY = vImageScale_Planar8(&fullY, &dummy, nil, vImage_Flags(kvImageGetTempBufferSize | kvImageHighQualityResampling))
        var dummyC = vImage_Buffer(data: nil, height: vImagePixelCount(dh / 2), width: vImagePixelCount(dw / 2), rowBytes: dw)
        let needC = vImageScale_CbCr8(&fullC, &dummyC, nil, vImage_Flags(kvImageGetTempBufferSize | kvImageHighQualityResampling))
        ensureTemp(max(0, needY, needC))
        let ok: Bool = yPlane.withUnsafeMutableBytes { yp in
            cbcrPlane.withUnsafeMutableBytes { cp in
                scaled.bytes.withUnsafeMutableBytes { d in
                    var dstY = vImage_Buffer(data: yp.baseAddress, height: vImagePixelCount(dh), width: vImagePixelCount(dw), rowBytes: dw)
                    var dstC = vImage_Buffer(data: cp.baseAddress, height: vImagePixelCount(dh / 2), width: vImagePixelCount(dw / 2), rowBytes: dw)
                    guard vImageScale_Planar8(&fullY, &dstY, temp, scaleFlags) == kvImageNoError,
                          vImageScale_CbCr8(&fullC, &dstC, temp, scaleFlags) == kvImageNoError else { return false }
                    var dst = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(dh), width: vImagePixelCount(dw), rowBytes: dw * 4)
                    return vImageConvert_420Yp8_CbCr8ToARGB8888(&dstY, &dstC, &dst, &infoVar, map, 255, flags) == kvImageNoError
                }
            }
        }
        return ok
    }

    private static func isBT601(_ pb: CVPixelBuffer) -> Bool {
        guard let v = CVBufferCopyAttachment(pb, kCVImageBufferYCbCrMatrixKey, nil) else { return false }
        return (v as? String) == (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String)
    }

    private func conversion(fullRange: Bool, matrix601: Bool) -> vImage_YpCbCrToARGB {
        let key = "\(fullRange)-\(matrix601)"
        if let c = conversions[key] { return c }
        var range = fullRange
            ? vImage_YpCbCrPixelRange(Yp_bias: 0, CbCr_bias: 128, YpRangeMax: 255, CbCrRangeMax: 255, YpMax: 255, YpMin: 1, CbCrMax: 255, CbCrMin: 0)
            : vImage_YpCbCrPixelRange(Yp_bias: 16, CbCr_bias: 128, YpRangeMax: 235, CbCrRangeMax: 240, YpMax: 255, YpMin: 0, CbCrMax: 255, CbCrMin: 1)
        var info = vImage_YpCbCrToARGB()
        let matrix = matrix601 ? kvImage_YpCbCrToARGBMatrix_ITU_R_601_4! : kvImage_YpCbCrToARGBMatrix_ITU_R_709_2!
        vImageConvert_YpCbCrToARGB_GenerateConversion(matrix, &range, &info, kvImage420Yp8_CbCr8, kvImageARGB8888, vImage_Flags(kvImageNoFlags))
        conversions[key] = info
        return info
    }
}
