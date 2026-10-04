import Foundation

// Port of src/extract/layout.js (plus one Swift-only addition, `findDamagedHpBar`, which the JavaScript
// does not have): find the UI anchors that place the text regions, so the same code
// reads iPhone and iPad frames and re-encoded copies: the white CP text at the top and the green
// HP bar under the name. Everything is in pixels of the frame; `rect` is the content rectangle.

public typealias ColourMask = (UInt8, UInt8, UInt8) -> Bool

/// Text colour masks for the CP. White for every ordinary Pokémon; a Mega-evolved Pokémon's CP is
/// drawn in the Mega's pink over its aura, so the pink mask is the fallback. (Tested on Mega
/// Mewtwo Y only; other Mega colours may need a third mask.)
public let cpMasks: [(name: String, mask: ColourMask)] = [
    ("white", { r, g, b in r > 225 && g > 225 && b > 225 }),
    ("pink", { r, g, b in Int(r) > 190 && Int(r) - Int(g) > 100 && Int(r) - Int(b) > 60 && b > 60 }),
]

/// The HP bar is bright green on the iPhone and a muted green on the iPad's red-tinted panel
/// (about 120/142/108 there, only 4 units over JS's old g > r + 18). A 4:2:0 frame (what the device
/// delivers) smears that chroma over 2x2 pixels, and scaling the planes separately smears it again, so
/// the margins are 10 and 16 (JS: 18 and 22): the bar was lost on iPad frames through the pixel-buffer
/// path at the old ones. Green type icons and green scenery are still told apart by the thin-band and
/// longest-run rules in `findHpBar`.
@inline(__always) private func isGreen(_ d: UnsafeBufferPointer<UInt8>, _ i: Int) -> Bool {
    let r = Int(d[i]), g = Int(d[i + 1]), b = Int(d[i + 2])
    return g > r + 10 && g > b + 16 && g > 100
}

public struct CpText: Equatable {
    public var x0: Int, x1: Int
    public var digitsX0: Int
    public var y0: Int, y1: Int
    public var centred: Bool
    public var mask: String
}

/// The CP text at the top of the screen. Rows in the top 14% of the rect whose centre band
/// (x 30-70%) holds enough mask pixels form runs; the first run of text height whose column
/// cluster nearest the centre is text-like wins. Tries each mask in turn. Returns nil when there
/// is none. The status bar is too sparse in the centre band, the white arc too thin and a white
/// sprite too tall, so they fail one of the tests.
public func findCpText(_ img: RGBAImage, _ rect: PixelRect, masks: [(name: String, mask: ColourMask)] = cpMasks) -> CpText? {
    var fallback: CpText? = nil
    for (name, mask) in masks {
        if var found = findTextByMask(img, rect, mask) {
            found.mask = name
            if found.centred { return found }
            if fallback == nil { fallback = found }
        }
    }
    return fallback
}

private func findTextByMask(_ img: RGBAImage, _ rect: PixelRect, _ mask: ColourMask) -> CpText? {
    let width = img.width
    let yEnd = min(img.height, jsRound(Double(rect.y) + 0.14 * Double(rect.h)))
    let xa = jsRound(Double(rect.x) + 0.3 * Double(rect.w)), xb = jsRound(Double(rect.x) + 0.7 * Double(rect.w))
    let minRow = max(3, jsRound(0.03 * Double(xb - xa)))
    var on = [Bool]()
    if yEnd > rect.y {
        img.bytes.withUnsafeBufferPointer { d in
            for y in rect.y..<yEnd {
                var n = 0
                for x in xa..<xb { let i = (y * width + x) * 4; if mask(d[i], d[i + 1], d[i + 2]) { n += 1 } }
                on.append(n >= minRow)
            }
        }
    }
    // Bridge small gaps between text rows (a blurred re-encode drops rows), then walk the runs.
    let bridgeRows = max(1, jsRound(0.004 * Double(rect.h)))
    var off = -1
    for i in 0...on.count {
        if i < on.count && !on[i] { if off < 0 { off = i }; continue }
        if off >= 0 && i - off <= bridgeRows && off > 0 && i < on.count { for k in off..<i { on[k] = true } }
        off = -1
    }
    // Text height limits, and the text starts in the top 10% (a white sprite starts lower).
    let minH = 0.016 * Double(rect.h), maxH = 0.042 * Double(rect.h), maxStart = 0.10 * Double(rect.h)
    var r0: Int? = nil
    var fallback: CpText? = nil
    for i in 0...on.count {
        if i < on.count && on[i] { if r0 == nil { r0 = i }; continue }
        guard let start = r0 else { continue }
        r0 = nil
        let h = Double(i - start)
        if h < minH || h > maxH || Double(start) > maxStart { continue }
        if let found = clusterOfText(img, rect, rect.y + start, rect.y + i, mask) {
            if found.centred { return found }
            if fallback == nil { fallback = found }
        }
    }
    return fallback
}

/// Column clusters of mask pixels within the text rows; the cluster nearest the centre that is
/// text-sized and text-like (not a solid pill or circle) wins.
private func clusterOfText(_ img: RGBAImage, _ rect: PixelRect, _ y0: Int, _ y1: Int, _ mask: ColourMask) -> CpText? {
    let width = img.width
    let th = y1 - y0
    var cols = [Int](repeating: 0, count: rect.w)
    img.bytes.withUnsafeBufferPointer { d in
        for y in y0..<y1 {
            for x in rect.x..<(rect.x + rect.w) {
                let i = (y * width + x) * 4
                if mask(d[i], d[i + 1], d[i + 2]) { cols[x - rect.x] += 1 }
            }
        }
    }
    let bridge = jsRound(Double(th) * 0.6)
    struct Cluster { var a: Int, b: Int, ink: Int }
    var clusters = [Cluster]()
    var c0: Int? = nil
    var gap = 0, ink = 0
    for x in 0...rect.w {
        let n = x < rect.w ? cols[x] : 0
        if n > 0 {
            if c0 == nil { c0 = x; ink = 0 }
            gap = 0; ink += n
        } else if let c = c0 {
            gap += 1
            if gap > bridge || x == rect.w { clusters.append(Cluster(a: c, b: x - gap, ink: ink)); c0 = nil; gap = 0 }
        }
    }
    struct Sized { var c: Cluster; var w: Int; var centre: Double; var solidity: Double }
    var sized = clusters.map { c -> Sized in
        let w = c.b - c.a
        return Sized(c: c, w: w, centre: Double(c.a + c.b) / 2 / Double(rect.w), solidity: Double(c.ink) / Double(w * th))
    }.filter { Double($0.w) >= 0.03 * Double(rect.w) && Double($0.w) <= 0.4 * Double(rect.w) && $0.solidity < 0.7 }
    if sized.isEmpty { return nil }
    sized.sort { abs($0.centre - 0.5) < abs($1.centre - 0.5) }
    let best = sized[0].c
    // The "CP" prefix is set smaller than the digits: skip leading columns whose ink starts well
    // below the cap height, so a digits-only crop holds digits only.
    var digitsFrom = best.a
    img.bytes.withUnsafeBufferPointer { d in
        for x in best.a..<best.b {
            var top = -1
            var y = y0
            while y < y1 && top < 0 {
                let i = (y * width + rect.x + x) * 4
                if mask(d[i], d[i + 1], d[i + 2]) { top = y }
                y += 1
            }
            if top >= 0 && Double(top - y0) <= 0.2 * Double(th) { digitsFrom = x; break }
        }
    }
    // Back up to the left edge of that glyph (a "9" reaches cap height only in its middle columns).
    while digitsFrom > best.a && cols[digitsFrom - 1] > 0 { digitsFrom -= 1 }
    return CpText(x0: rect.x + best.a, x1: rect.x + best.b, digitsX0: rect.x + digitsFrom, y0: y0, y1: y1,
                  centred: abs(sized[0].centre - 0.5) < 0.12, mask: "")
}

public struct HpBar: Equatable {
    public var y0: Int, y1: Int, x0: Int, x1: Int
    public init(y0: Int, y1: Int, x0: Int, x1: Int) { self.y0 = y0; self.y1 = y1; self.x0 = x0; self.x1 = x1 }
}

/// The green HP bar under the name: a thin band of rows between 34% and 66% of the rect whose
/// centre half holds a long run of green. The bar is the band whose middle row holds the longest
/// unbroken run of green (fault 4): a row of green type icons (Bug / Grass) is also a thin green
/// band, and taller than the bar, but it is two short runs; a green background beside the card is
/// not part of the bar either.
public func findHpBar(_ img: RGBAImage, _ rect: PixelRect) -> HpBar? {
    let width = img.width
    let ya = jsRound(Double(rect.y) + 0.34 * Double(rect.h)), yb = min(img.height, jsRound(Double(rect.y) + 0.66 * Double(rect.h)))
    let xa = jsRound(Double(rect.x) + 0.2 * Double(rect.w)), xb = jsRound(Double(rect.x) + 0.8 * Double(rect.w))
    // A damaged Pokémon's bar is short (its right part is grey), so a short run of green counts;
    // the thin-band test below is what keeps a green sprite from matching.
    let need = 0.08 * Double(rect.w)
    var rows = [Bool]()
    img.bytes.withUnsafeBufferPointer { d in
        if yb > ya {
            for y in ya..<yb {
                var n = 0
                for x in xa..<xb where isGreen(d, (y * width + x) * 4) { n += 1 }
                rows.append(Double(n) >= need)
            }
        }
    }
    // Candidate bands: runs of green rows that are thin (the bar is under 1.5% of the height).
    let maxH = 0.015 * Double(rect.h), minH = max(2.0, 0.002 * Double(rect.h))
    var best: (bar: HpBar, run: Int)? = nil
    var start: Int? = nil
    img.bytes.withUnsafeBufferPointer { d in
        for i in 0...rows.count {
            if i < rows.count && rows[i] { if start == nil { start = i }; continue }
            if let s = start {
                let h = Double(i - s)
                if h >= minH && h <= maxH {
                    let ym = jsRound(Double(ya + s) + h / 2)
                    var flags = [Bool]()
                    flags.reserveCapacity(rect.w)
                    for x in rect.x..<(rect.x + rect.w) { flags.append(isGreen(d, (ym * width + x) * 4)) }
                    let (a, b) = widestRun(flags)
                    if Double(b - a) >= need && (best == nil || b - a > best!.run) {
                        best = (HpBar(y0: ya + s, y1: ya + i, x0: rect.x + a, x1: rect.x + b), b - a)
                    }
                }
                start = nil
            }
        }
    }
    return best?.bar
}

/// A damaged or fainted Pokémon's HP bar has little or no green (a short red fill in front of a grey
/// track, or the empty track alone; run17's first card, Rayquaza 19 / 190 HP, was read without name or
/// HP), so `findHpBar`'s colour test never sees it. This fallback is tried only when the green search
/// found nothing and the CP text is centred, and it finds a BAR by its shape and its contrast with the
/// card on either side of it in the same row, never by an absolute colour (the owner's screenshots carry
/// a Display P3 profile and the broadcast delivers sRGB, a unit or two apart on every channel):
///  - a pixel is bar-like when, in its own row, it differs by at least `barContrast` on some channel
///    from the card on BOTH sides of the bar (the mean colour of the row at 6 to 18% and at 82 to 94% of
///    the content width, which must lie within 2 x `barContrast` - 1 of each other, else the row is
///    skipped: then a pixel between them cannot differ from both by `barContrast`). The card is a vertical
///    gradient, so its bands are about uniform along a row and never differ from their own sides: an
///    absolute "track grey" test also matched them, and a band of them out-ran the real bar;
///  - the bar is the widest such run in a row, 28 to 56% of the content width, starting 16 to 36% in
///    from its left edge (25% when settled; a card sliding in or out is a little to either side), in a band of rows 0.4 to 1.1% of the content height tall, nothing like it in the
///    rows around it (green bars in the 14,918 recorded frames: 50.0% of the width and 25.1% in on a
///    phone, 31.7% and 28.7% on the iPad, 0.61 to 0.79% tall; a covered bar is shorter, never wider);
///  - it sits 40 to 58% of the way down (recorded green bars: 42 to 47% on a phone, 55% on the iPad), the
///    band nearest the middle of that range winning.
/// The caller still requires the HP text under it to parse (`FrameReader.complete`); this only places it.
let barContrast = 12
let barWidthRange = 0.28...0.56, barLeftRange = 0.16...0.36, barHeightRange = 0.004...0.011, barExpectedY = 0.40...0.58

func findDamagedHpBar(_ img: RGBAImage, _ rect: PixelRect) -> HpBar? {
    let width = img.width, rh = Double(rect.h), rw = Double(rect.w)
    let ya = jsRound(Double(rect.y) + 0.34 * rh), yb = min(img.height, jsRound(Double(rect.y) + 0.66 * rh))
    let lx0 = rect.x + jsRound(0.06 * rw), lx1 = rect.x + jsRound(0.18 * rw)
    let rx0 = rect.x + jsRound(0.82 * rw), rx1 = rect.x + jsRound(0.94 * rw)
    guard yb > ya, lx1 > lx0, rx1 > rx0 else { return nil }
    // For each row, the widest run of bar-like pixels (start, end) or nil.
    var runs = [(a: Int, b: Int)?]()
    img.bytes.withUnsafeBufferPointer { d in
        func mean(_ y: Int, _ x0: Int, _ x1: Int) -> [Int] {
            var s = [0, 0, 0]
            for x in x0..<x1 { let i = (y * width + x) * 4; s[0] += Int(d[i]); s[1] += Int(d[i + 1]); s[2] += Int(d[i + 2]) }
            let n = x1 - x0
            return s.map { $0 / n }
        }
        for y in ya..<yb {
            let l = mean(y, lx0, lx1), r = mean(y, rx0, rx1)
            guard zip(l, r).allSatisfy({ abs($0 - $1) < 2 * barContrast - 1 }) else { runs.append(nil); continue }
            var best: (a: Int, b: Int)? = nil
            var start = -1
            let xa = lx1, xb = rx0
            for x in xa...xb {
                var on = false
                if x < xb {
                    let i = (y * width + x) * 4
                    let dl = max(abs(Int(d[i]) - l[0]), abs(Int(d[i + 1]) - l[1]), abs(Int(d[i + 2]) - l[2]))
                    let dr = max(abs(Int(d[i]) - r[0]), abs(Int(d[i + 1]) - r[1]), abs(Int(d[i + 2]) - r[2]))
                    on = min(dl, dr) >= barContrast
                }
                if on { if start < 0 { start = x } } else if start >= 0 {
                    if best == nil || x - start > best!.b - best!.a { best = (start, x) }
                    start = -1
                }
            }
            runs.append(best.flatMap { Double($0.b - $0.a) >= barWidthRange.lowerBound * rw ? $0 : nil })
        }
    }
    var found: (bar: HpBar, score: Double)? = nil
    var i = 0
    while i < runs.count {
        guard runs[i] != nil else { i += 1; continue }
        var j = i
        while j < runs.count, runs[j] != nil { j += 1 }
        defer { i = j }
        let h = Double(j - i) / rh
        guard barHeightRange.contains(h), let mid = runs[(i + j) / 2] else { continue }
        let w = Double(mid.b - mid.a) / rw, left = Double(mid.a - rect.x) / rw
        guard barWidthRange.contains(w), barLeftRange.contains(left) else { continue }
        let yFrac = (Double(ya + i) - Double(rect.y)) / rh
        guard barExpectedY.contains(yFrac) else { continue }
        let score = abs(yFrac - 0.5 * (barExpectedY.lowerBound + barExpectedY.upperBound))
        if found == nil || score < found!.score { found = (HpBar(y0: ya + i, y1: ya + j, x0: mid.a, x1: mid.b), score) }
    }
    return found?.bar
}

/// Text regions derived from the anchors, in frame pixels.
public struct Regions {
    public var cp: Rect
    public var name: Rect?
    public var hp: Rect?
    public var panelSearch: Rect?
}

/// `cpPadding` is in text heights on each side of the CP crop; `includePrefix` starts the crop at
/// the "CP" prefix (Vision reads "CP1234" better than a bare digit crop; parseCp strips the
/// prefix). With includePrefix false and cpPadding 0.1/0.2 this is the JS digits-only crop.
public func regionsFrom(_ rect: PixelRect, _ cpText: CpText?, _ hpBar: HpBar?,
                        cpPadding: Double = Tuning.cpCropPadding, cpIncludesPrefix: Bool = true) -> Regions {
    let h = Double(rect.h), rx = Double(rect.x), rw = Double(rect.w)
    let pad = Double(jsRound(0.006 * h))
    var cp: Rect
    if let c = cpText {
        let th = Double(c.y1 - c.y0)
        let x0 = Double(cpIncludesPrefix ? c.x0 : c.digitsX0)
        cp = Rect(x: x0 - cpPadding * th, y: Double(c.y0) - pad, w: Double(c.x1) - x0 + 2 * cpPadding * th, h: th + 2 * pad)
    } else {
        cp = Rect(x: rx + 0.25 * rw, y: Double(rect.y), w: 0.5 * rw, h: 0.14 * h)
    }
    var out = Regions(cp: cp, name: nil, hp: nil, panelSearch: nil)
    if let bar = hpBar {
        out.name = Rect(x: rx + 0.14 * rw, y: Double(bar.y0) - 0.062 * h, w: 0.72 * rw, h: 0.055 * h)
        out.hp = Rect(x: rx + 0.25 * rw, y: Double(bar.y1) + 0.004 * h, w: 0.5 * rw, h: 0.026 * h)
        let top = Double(bar.y1) + 0.05 * h
        out.panelSearch = Rect(x: rx, y: top, w: 0.55 * rw, h: Double(rect.y + rect.h) - top)
    }
    return out
}

// MARK: - the stationed card (Round 31)

/// A Pokémon stationed away (at a Power Spot; a gym defender is believed to look the same) has an appraisal card with no
/// "CP n" at the top and no HP bar or HP text: the name, a line "At <place>", a green RECALL button, the dimmed STATS area, and
/// the appraisal box in its usual place. The RECALL button is the anchor (a teal pill, about 34% of the width and 5% of the
/// height, centred, at 50 to 56% of the way down); the name and the "At" line are placed from it. Measured on the owner's two
/// screenshots (1320 x 2868, one phone): button 0.329 to 0.671 of the width, 0.505 to 0.556 of the height; name text centred
/// 0.089 of the height above the button's top, the "At" line 0.044 above it.
public struct RecallButton: Equatable {
    public var y0: Int, y1: Int, x0: Int, x1: Int
}

/// Teal of the button, in Display P3 and in sRGB (the fill runs from about 129/184/151 at the top left to 74/155/152 at the
/// bottom right in P3, 112/186/148 to 26/157/153 in sRGB): green clearly above red, blue never more than a few units above green.
@inline(__always) private func isTeal(_ d: UnsafeBufferPointer<UInt8>, _ i: Int) -> Bool {
    let r = Int(d[i]), g = Int(d[i + 1]), b = Int(d[i + 2])
    return g > r + 40 && g + 5 >= b && g > 120
}

/// The RECALL button: a band of rows, 3.5 to 6.5% of the content height, 40 to 65% of the way down, in which the centre 40% of the
/// width holds teal pixels over at least 15% of the width (the white "RECALL" text takes the rest of the middle rows), whose rows
/// at 20% and 80% of the band hold one unbroken run of teal 28 to 46% of the width wide and centred within 4% of the middle. A
/// green HP bar is far too thin, scenery is not a centred pill. Called only for a frame with neither CP text nor HP bar.
public func findRecallButton(_ img: RGBAImage, _ rect: PixelRect) -> RecallButton? {
    let width = img.width, rh = Double(rect.h), rw = Double(rect.w)
    let ya = jsRound(Double(rect.y) + 0.40 * rh), yb = min(img.height, jsRound(Double(rect.y) + 0.65 * rh))
    let xa = jsRound(Double(rect.x) + 0.30 * rw), xb = jsRound(Double(rect.x) + 0.70 * rw)
    guard yb > ya, xb > xa else { return nil }
    var on = [Bool]()
    on.reserveCapacity(yb - ya)
    img.bytes.withUnsafeBufferPointer { d in
        for y in ya..<yb {
            var n = 0
            for x in xa..<xb where isTeal(d, (y * width + x) * 4) { n += 1 }
            on.append(Double(n) >= 0.15 * rw)
        }
    }
    bridgeGaps(&on, maxGap: max(2, jsRound(0.004 * rh)))
    // The first band that is button-shaped; scenery or an icon row fails the height or the width.
    var found: RecallButton? = nil
    img.bytes.withUnsafeBufferPointer { d in
        func extent(row y: Int) -> (Int, Int)? {
            var flags = [Bool]()
            flags.reserveCapacity(rect.w)
            for x in rect.x..<(rect.x + rect.w) { flags.append(isTeal(d, (y * width + x) * 4)) }
            let (a, b) = widestRun(flags)
            let w = Double(b - a) / rw, centre = (Double(a + b) / 2) / rw
            return w >= 0.28 && w <= 0.46 && abs(centre - 0.5) <= 0.04 ? (rect.x + a, rect.x + b) : nil
        }
        var start: Int? = nil
        for i in 0...on.count {
            if i < on.count && on[i] { if start == nil { start = i }; continue }
            guard let s = start else { continue }
            start = nil
            let h = Double(i - s)
            guard found == nil, h >= 0.035 * rh, h <= 0.065 * rh,
                  let top = extent(row: ya + s + Int(h * 0.2)), let bottom = extent(row: ya + s + Int(h * 0.8)) else { continue }
            found = RecallButton(y0: ya + s, y1: ya + i, x0: min(top.0, bottom.0), x1: max(top.1, bottom.1))
        }
    }
    return found
}

/// The crops the stationed read needs, placed from the button: the name (one line, kept clear of the "At" line under it) and the
/// "At <place>" line (read only to see that it begins with "At"; never kept), and where the bars are searched.
func stationedRegions(_ rect: PixelRect, _ button: RecallButton) -> (name: Rect, line: Rect, panelSearch: Rect) {
    let h = Double(rect.h), rx = Double(rect.x), rw = Double(rect.w)
    let top = Double(button.y0)
    let name = Rect(x: rx + 0.14 * rw, y: top - 0.1135 * h, w: 0.72 * rw, h: 0.05 * h)
    let line = Rect(x: rx + 0.10 * rw, y: top - 0.0685 * h, w: 0.80 * rw, h: 0.05 * h)
    let panelTop = Double(button.y1) + 0.05 * h
    return (name, line, Rect(x: rx, y: panelTop, w: 0.55 * rw, h: Double(rect.y + rect.h) - panelTop))
}
