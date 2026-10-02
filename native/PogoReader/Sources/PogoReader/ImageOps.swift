import Foundation

// Ports of src/extract/image.js: the pixel helpers the layout and bar code use.

/// [start, end) of the longest run of true values.
public func widestRun(_ flags: [Bool]) -> (Int, Int) {
    var best = (0, 0)
    var cur: Int? = nil
    for i in 0...flags.count {
        if i < flags.count && flags[i] {
            if cur == nil { cur = i }
        } else if let c = cur {
            if i - c > best.1 - best.0 { best = (c, i) }
            cur = nil
        }
    }
    return best
}

/// The rectangle of the frame that holds the phone screen: the widest run of columns whose mean
/// brightness clears `threshold`, then the widest run of rows within those columns. Handles the
/// black pillarboxing of a landscape re-encode and letterboxing of a portrait one. On a frame with
/// no dark border it returns the whole frame.
public func contentRect(_ img: RGBAImage, threshold: Double = 30, step: Int = 4) -> PixelRect {
    let width = img.width, height = img.height
    guard width > 0, height > 0 else { return PixelRect(x: 0, y: 0, w: 0, h: 0) }
    var colOn = [Bool](repeating: false, count: width)
    img.bytes.withUnsafeBufferPointer { d in
        // Column means in one pass over the sampled rows (JS walks column by column; same sums).
        var sums = [Int](repeating: 0, count: width)
        var n = 0
        var y = 0
        while y < height {
            let row = y * width * 4
            for x in 0..<width { let i = row + x * 4; sums[x] += Int(d[i]) + Int(d[i + 1]) + Int(d[i + 2]) }
            n += 1
            y += step
        }
        for x in 0..<width { colOn[x] = Double(sums[x]) / Double(3 * n) > threshold }
    }
    // A black border is many rows or columns wide; a line a few pixels thick between content is not one. (A dark
    // top and the thin dark stroke at a card's edge averaged just under the threshold on one row after the
    // 4:2:0 conversion and scaling, and cut a whole screen in two.)
    bridgeGaps(&colOn, maxGap: max(2, Int(0.005 * Double(width))))
    let (x0, x1) = widestRun(colOn)
    guard x1 > x0 else { return PixelRect(x: 0, y: 0, w: 0, h: 0) }
    var rowOn = [Bool](repeating: false, count: height)
    img.bytes.withUnsafeBufferPointer { d in
        for y in 0..<height {
            var s = 0, n = 0
            var x = x0
            while x < x1 { let i = (y * width + x) * 4; s += Int(d[i]) + Int(d[i + 1]) + Int(d[i + 2]); n += 1; x += step }
            rowOn[y] = Double(s) / Double(3 * n) > threshold
        }
    }
    bridgeGaps(&rowOn, maxGap: max(2, Int(0.005 * Double(height))))
    let (y0, y1) = widestRun(rowOn)
    return PixelRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
}

/// Turn short runs of false that sit between true values into true (a thin dark line inside the content, such as
/// the stroke along a card's top edge, is not a border). Runs at either end are left alone.
func bridgeGaps(_ flags: inout [Bool], maxGap: Int) {
    var i = 0
    while i < flags.count {
        if flags[i] { i += 1; continue }
        var j = i
        while j < flags.count, !flags[j] { j += 1 }
        if i > 0, j < flags.count, j - i <= maxGap { for k in i..<j { flags[k] = true } }
        i = j
    }
}

/// Copy a pixel rectangle, clamped to the image.
public func crop(_ img: RGBAImage, _ r: Rect) -> RGBAImage {
    let x0 = max(0, jsRound(r.x)), y0 = max(0, jsRound(r.y))
    let x1 = min(img.width, jsRound(r.x + r.w)), y1 = min(img.height, jsRound(r.y + r.h))
    let w = max(0, x1 - x0), h = max(0, y1 - y0)
    var out = RGBAImage(width: w, height: h)
    guard w > 0, h > 0 else { return out }
    img.bytes.withUnsafeBufferPointer { src in
        out.bytes.withUnsafeMutableBufferPointer { dst in
            for y in y0..<y1 {
                let s = (y * img.width + x0) * 4, d = (y - y0) * w * 4
                dst.baseAddress!.advanced(by: d).update(from: src.baseAddress!.advanced(by: s), count: w * 4)
            }
        }
    }
    return out
}

public func crop(_ img: RGBAImage, _ r: PixelRect) -> RGBAImage {
    crop(img, Rect(x: Double(r.x), y: Double(r.y), w: Double(r.w), h: Double(r.h)))
}

/// Variance of the 3x3 Laplacian of the luma: higher means sharper. Blurred swipe frames score low.
public func laplacianVariance(_ img: RGBAImage) -> Double {
    let width = img.width, height = img.height
    if width < 3 || height < 3 { return 0 }
    var g = [Float](repeating: 0, count: width * height)
    for y in 0..<height { for x in 0..<width { g[y * width + x] = Float(img.luma(x, y)) } }
    var sum = 0.0, sumSq = 0.0
    var n = 0.0
    for y in 1..<(height - 1) {
        for x in 1..<(width - 1) {
            let i = y * width + x
            let l = Double(4 * g[i] - g[i - 1] - g[i + 1] - g[i - width] - g[i + width])
            sum += l; sumSq += l * l; n += 1
        }
    }
    let mean = sum / n
    return sumSq / n - mean * mean
}
