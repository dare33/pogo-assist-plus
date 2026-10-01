import Foundation
import CoreGraphics
import Vision

/// What a crop is meant to hold; the reader may treat each differently (size, expectations), and
/// a test fake uses it to know which read is being asked for.
public enum TextKind { case cp, name, hp }

public struct TextWord: Equatable {
    public var text: String
    /// 0..100 (Vision's 0..1 times 100, so the JS thresholds carry over).
    public var confidence: Double
    public init(text: String, confidence: Double) { self.text = text; self.confidence = confidence }
}

public struct TextRead: Equatable {
    public var text: String
    public var confidence: Double
    public var words: [TextWord]
    public init(text: String, confidence: Double, words: [TextWord]) { self.text = text; self.confidence = confidence; self.words = words }
    public static let empty = TextRead(text: "", confidence: 0, words: [])
}

/// The one thing the reader needs from a text recogniser. Vision in the app; a fake in tests.
public protocol TextReader: AnyObject {
    func read(_ image: RGBAImage, kind: TextKind) -> TextRead
}

/// Apple Vision text recognition: accurate level, language correction off (it would "fix" Pokémon
/// names and digits into words), en-US. The request object is created once and reused.
public final class VisionTextReader: TextReader {
    private let request: VNRecognizeTextRequest
    private let colourSpace = CGColorSpaceCreateDeviceRGB()

    public init(fast: Bool = false) {
        request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
    }

    public func read(_ image: RGBAImage, kind: TextKind) -> TextRead {
        guard image.width > 0, image.height > 0 else { return .empty }
        let target: Double
        switch kind {
        case .cp: target = Tuning.cpCropTargetHeight
        case .name: target = Tuning.nameCropTargetHeight
        case .hp: target = Tuning.hpCropTargetHeight
        }
        return autoreleasepool {
            var work = upscaled(image, toHeight: target)
            guard let cg = cgImage(&work) else { return .empty }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { return .empty }
            let observations = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            var words = [TextWord]()
            for o in observations {
                guard let cand = o.topCandidates(1).first else { continue }
                words.append(TextWord(text: cand.string, confidence: Double(cand.confidence) * 100))
            }
            let text = words.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let conf = words.isEmpty ? 0 : words.reduce(0) { $0 + $1.confidence } / Double(words.count)
            return TextRead(text: text, confidence: conf, words: words)
        }
    }

    /// Wrap the crop's bytes in a CGImage (alpha ignored: the frame is opaque).
    private func cgImage(_ img: inout RGBAImage) -> CGImage? {
        let w = img.width, h = img.height
        return img.bytes.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: colourSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }
}
