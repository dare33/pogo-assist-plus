import Foundation

/// A tiny fingerprint of a text crop: the mean brightness of each 4 x 4 block. Two frames of a card that has settled give
/// crops whose blocks differ by the compression noise, a few levels; a changed digit or letter moves the blocks it touches by tens.
/// `FrameReader.reuseStaticText` uses it to skip a recognition whose input has not changed. It is about a thousand bytes for a
/// name crop, so keeping the last one is not a retained buffer in any sense that grows.
struct CropSignature {
    static let cell = 4
    /// The biggest change of any block's mean brightness (0...255) still counted as the same crop.
    static let tolerance = 12

    let width: Int, height: Int
    var cells: [UInt8]

    init(_ image: RGBAImage) {
        let c = CropSignature.cell
        let w = image.width / c, h = image.height / c
        var cells = [UInt8](repeating: 0, count: max(0, w * h))
        image.bytes.withUnsafeBufferPointer { d in
            for by in 0..<h {
                for bx in 0..<w {
                    var sum = 0
                    for y in (by * c)..<(by * c + c) {
                        var i = (y * image.width + bx * c) * 4
                        for _ in 0..<c { sum += Int(d[i]) + Int(d[i + 1]) * 2 + Int(d[i + 2]); i += 4 }
                    }
                    cells[by * w + bx] = UInt8(sum / (c * c * 4))
                }
            }
        }
        width = w; height = h
        self.cells = cells
    }

    func matches(_ other: CropSignature, tolerance: Int = CropSignature.tolerance) -> Bool {
        guard width == other.width, height == other.height, !cells.isEmpty else { return false }
        for i in cells.indices where abs(Int(cells[i]) - Int(other.cells[i])) > tolerance { return false }
        return true
    }
}
