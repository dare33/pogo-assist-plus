import Foundation

// Port of src/extract/bars.js: read the three appraisal bars (Attack, Defence, HP). Each bar is a
// track of 15 units drawn as three rounded blocks on the white appraisal panel: filled units are
// orange, all 15 filled is pink, unfilled units are light grey. The panel moves vertically between
// frames, so the bars are found by scanning rows for a long run of track-coloured pixels bounded by
// panel white.

public enum PixelClass { case white, grey, fill, other }

/// Measured on the recordings: pink 218/113/120, orange 242/155/65, track 222/221/223.
@inline(__always) public func classifyPixel(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> PixelClass {
    let ri = Int(r), gi = Int(g), bi = Int(b)
    let mx = max(ri, gi, bi), mn = min(ri, gi, bi)
    if mn > 240 { return .white }
    if mx - mn < 14 && mn > 190 && mx < 240 { return .grey }
    if ri > 180 && ri - bi > 70 && gi < 200 { return .fill }   // orange or pink (re-encodes mute both)
    return .other
}

/// A run of equal-class pixels along one row.
public struct Seg {
    public var c: PixelClass
    public var x: Int
    public var n: Int
    public init(c: PixelClass, x: Int = 0, n: Int) { self.c = c; self.x = x; self.n = n }
}

/// Fill fraction of one track row from its class runs. Runs between the blocks (white, or a blend
/// bounded by the same class on both sides) are gaps and count for nothing; a blend between fill
/// and grey is the fill boundary and counts half, which keeps the estimate unbiased on re-encoded
/// frames where that blend is several pixels wide.
public func fillOfTrack(_ segs: [Seg]) -> Double {
    // Tiny grey runs beside a white gap are the gap's shaded edge, not track.
    var cls = [PixelClass]()
    for (k, s) in segs.enumerated() {
        let before = k > 0 ? segs[k - 1].c : nil, after = k + 1 < segs.count ? segs[k + 1].c : nil
        cls.append(s.c == .grey && s.n <= 2 && (before == .white || after == .white) ? .white : s.c)
    }
    var fill = 0.0, total = 0.0
    for k in 0..<segs.count {
        let c = cls[k], n = Double(segs[k].n)
        if c == .fill { fill += n; total += n; continue }
        if c == .grey { total += n; continue }
        if c == .white { continue }
        // 'other': boundary if the nearest track classes on each side differ, else a gap.
        var l = k - 1
        while l >= 0 && cls[l] != .fill && cls[l] != .grey { l -= 1 }
        var r = k + 1
        while r < segs.count && cls[r] != .fill && cls[r] != .grey { r += 1 }
        if l >= 0 && r < segs.count && cls[l] != cls[r] { fill += n / 2; total += n }
    }
    return total > 0 ? fill / total : 0
}

public struct Bar: Equatable {
    public var y0: Int, y1: Int, x0: Int, x1: Int
    public var fill: Double
    public init(y0: Int, y1: Int, x0: Int, x1: Int, fill: Double) { self.y0 = y0; self.y1 = y1; self.x0 = x0; self.x1 = x1; self.fill = fill }
}

private struct BarRow { var y: Int; var x0: Int; var x1: Int; var fill: Double }
private struct BarGroup { var y0: Int; var y1: Int; var x0: Int; var x1: Int; var rows: [BarRow] }

/// Mean extent of a group's middle rows.
private func mid(_ b: BarGroup) -> (x0: Double, x1: Double) {
    let n = b.rows.count
    let lo = min(n / 4, n), hi = min(max(1, Int((Double(n) * 3 / 4).rounded(.up))), n)
    let u = lo < hi ? Array(b.rows[lo..<hi]) : b.rows
    return (u.reduce(0.0) { $0 + Double($1.x0) } / Double(u.count), u.reduce(0.0) { $0 + Double($1.x1) } / Double(u.count))
}

/// Scan the search rectangle for bar rows. A bar row has a span of fill/grey pixels at least
/// `minSpan` of the rect width, at least 85% of the pixels inside the span are fill or grey, and
/// the pixels just outside the span are white. Consecutive bar rows with matching spans form a bar.
/// Returns bars top to bottom, fill in 0..1.
public func findBars(_ img: RGBAImage, _ rect: PixelRect, _ search: Rect) -> [Bar] {
    let width = img.width
    let x0s = max(0, jsRound(search.x)), x1s = min(img.width, jsRound(search.x + search.w))
    let y0s = max(0, jsRound(search.y)), y1s = min(img.height, jsRound(search.y + search.h))
    guard x0s < x1s, y0s < y1s else { return [] }
    let rw = Double(rect.w)
    let minSpan = 0.15 * rw, margin = max(2, jsRound(0.004 * rw))
    let gapMax = max(3, jsRound(0.015 * rw))     // white gap between the three blocks
    let aliasMax = max(3, jsRound(0.02 * rw))    // anti-aliased or blended edge pixels (wider after re-encoding)
    var rows = [BarRow]()
    var segs = [Seg]()
    img.bytes.withUnsafeBufferPointer { d in
        for y in y0s..<y1s {
            // Run-length classes along the row.
            segs.removeAll(keepingCapacity: true)
            for x in x0s..<x1s {
                let i = (y * width + x) * 4
                let c = classifyPixel(d[i], d[i + 1], d[i + 2])
                if let last = segs.last, last.c == c { segs[segs.count - 1].n += 1 } else { segs.append(Seg(c: c, x: x, n: 1)) }
            }
            // A track: a maximal sequence of segments that starts and ends with fill/grey, bridging
            // white gaps up to gapMax and stray other-coloured pixels up to aliasMax. Keep the
            // longest per row.
            var best: (s: Int, e: Int, first: Int, last: Int, span: Int, nFill: Int, nGrey: Int)? = nil
            var s = 0
            while s < segs.count {
                if segs[s].c != .fill && segs[s].c != .grey { s += 1; continue }
                var e = s, nFill = 0, nGrey = 0
                var k = s
                while k < segs.count {
                    let seg = segs[k]
                    if seg.c == .fill { nFill += seg.n; e = k }
                    else if seg.c == .grey { nGrey += seg.n; e = k }
                    else if seg.c == .white && seg.n <= gapMax { k += 1; continue }
                    else if seg.c == .other && seg.n <= aliasMax { k += 1; continue }
                    else { break }
                    k += 1
                }
                let first = segs[s].x, last = segs[e].x + segs[e].n - 1
                let span = last - first + 1
                if Double(span) >= minSpan && (best == nil || span > best!.span) { best = (s, e, first, last, span, nFill, nGrey) }
                s = e + 1
            }
            guard let b = best, Double(b.nFill + b.nGrey) / Double(b.span) >= 0.85 else { continue }
            // Panel white on both sides of the track (after any anti-aliased edge).
            func outside(_ k: Int, _ dir: Int) -> Bool {
                var need = margin
                var j = k + dir
                while j >= 0 && j < segs.count && need > 0 {
                    if segs[j].c == .other && segs[j].n <= aliasMax { j += dir; continue }
                    if segs[j].c != .white { return false }
                    need -= segs[j].n
                    j += dir
                }
                return need <= 0 || k + dir < 0 || k + dir >= segs.count
            }
            if !outside(b.s, -1) || !outside(b.e, 1) { continue }
            rows.append(BarRow(y: y, x0: b.first, x1: b.last + 1, fill: fillOfTrack(Array(segs[b.s...b.e]))))
        }
    }
    // Group consecutive rows into bars. A row that fails the checks (a glow or a stray pixel) must
    // not split a bar: allow a gap of two rows.
    var bars = [BarGroup]()
    for r in rows {
        if var cur = bars.last, r.y - cur.y1 <= 2, abs(r.x0 - cur.x0) < margin * 2, abs(r.x1 - cur.x1) < margin * 2 {
            cur.y1 = r.y + 1; cur.rows.append(r)
            bars[bars.count - 1] = cur
        } else { bars.append(BarGroup(y0: r.y, y1: r.y + 1, x0: r.x0, x1: r.x1, rows: [r])) }
    }
    // A single row widened by a glow splits a bar in two; rejoin vertically adjacent groups whose
    // middle rows agree.
    var joined = [BarGroup]()
    for b in bars {
        if var prev = joined.last, b.y0 - prev.y1 <= 2,
           abs(mid(b).x0 - mid(prev).x0) < 0.03 * rw, abs(mid(b).x1 - mid(prev).x1) < 0.03 * rw {
            prev.y1 = b.y1; prev.rows.append(contentsOf: b.rows)
            joined[joined.count - 1] = prev
        } else { joined.append(b) }
    }
    let minH = max(2, jsRound(0.003 * Double(rect.h)))
    return joined.filter { $0.y1 - $0.y0 >= minH }.map { b in
        // Fill from the middle rows, where the rounded ends do not shorten the span.
        let lo = b.rows.count / 4, hi = Int((Double(b.rows.count) * 3 / 4).rounded(.up))
        let midRows = lo < hi ? Array(b.rows[lo..<min(hi, b.rows.count)]) : []
        let use = midRows.isEmpty ? b.rows : midRows
        let fill = use.reduce(0.0) { $0 + $1.fill } / Double(use.count)
        let x0 = jsRound(use.reduce(0.0) { $0 + Double($1.x0) } / Double(use.count))
        let x1 = jsRound(use.reduce(0.0) { $0 + Double($1.x1) } / Double(use.count))
        return Bar(y0: b.y0, y1: b.y1, x0: x0, x1: x1, fill: fill)
    }
}

public struct IVs: Codable, Equatable, Hashable {
    public var atk: Int, def: Int, hp: Int
    public init(atk: Int, def: Int, hp: Int) { self.atk = atk; self.def = def; self.hp = hp }
}

public struct IvRead {
    public var ivs: IVs
    public var fills: [Double]
    public var bars: [Bar]
    public var confidence: Double
}

/// Pick the Attack/Defence/HP trio out of the found bars: three bars with the same horizontal
/// extent and near-equal vertical spacing. Confidence is how close each fill is to a multiple of
/// 1/15 (1 at whole units, falling to 0 half a unit away).
public func readIvs(_ bars: [Bar]) -> IvRead? {
    var best: (read: IvRead, score: Double)? = nil
    var i = 0
    while i + 2 < bars.count {
        defer { i += 1 }
        let trio = Array(bars[i..<(i + 3)])
        let w = trio.map { Double($0.x1 - $0.x0) }
        let wMax = w.max()!, wMin = w.min()!
        let sameWidth = wMax - wMin < 0.08 * w[0]
        let sameLeft = abs(Double(trio[0].x0 - trio[1].x0)) < 0.05 * w[0] && abs(Double(trio[1].x0 - trio[2].x0)) < 0.05 * w[0]
        let gap1 = Double(trio[1].y0 - trio[0].y0), gap2 = Double(trio[2].y0 - trio[1].y0)
        let evenGaps = abs(gap1 - gap2) < 0.25 * max(gap1, gap2) && gap1 > Double(trio[0].y1 - trio[0].y0) * 1.5
        if !(sameWidth && sameLeft && evenGaps) { continue }
        let fills = trio.map { $0.fill }
        let units = fills.map { $0 * 15 }
        let ivs = units.map { max(0, min(15, jsRound($0))) }
        let err = zip(units, ivs).map { abs($0 - Double($1)) }.max()!
        let score = abs(gap1 - gap2) / max(gap1, gap2) + (wMax - wMin) / w[0]
        if best == nil || score < best!.score {
            best = (IvRead(ivs: IVs(atk: ivs[0], def: ivs[1], hp: ivs[2]), fills: fills, bars: trio, confidence: max(0, 1 - err * 2)), score)
        }
    }
    return best?.read
}

/// Find bars in the search rect and read the IVs.
public func readBars(_ img: RGBAImage, _ rect: PixelRect, _ search: Rect) -> (bars: [Bar], result: IvRead?) {
    let bars = findBars(img, rect, search)
    return (bars, readIvs(bars))
}
