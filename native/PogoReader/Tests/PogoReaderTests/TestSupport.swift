import XCTest
@testable import PogoReader

let table: SpeciesTable = { try! SpeciesTable.bundled() }()
let names: [NameCandidate] = displayNames(table)
func candidate(_ display: String) -> NameCandidate { names.first { $0.display == display }! }

func line(_ text: String, _ confidence: Double) -> TextRead {
    TextRead(text: text, confidence: confidence, words: text.isEmpty ? [] : [TextWord(text: text, confidence: confidence)])
}

let marker: (UInt8, UInt8, UInt8) = (255, 0, 255)  // painted one line above the usual name position

func hasMark(_ img: RGBAImage) -> Bool {
    var i = 0
    while i < img.bytes.count { if img.bytes[i] == 255 && img.bytes[i + 1] == 0 && img.bytes[i + 2] == 255 { return true }; i += 4 }
    return false
}

/// Text reader stand-in. `name` is (text, confidence); `above` is what the line above the name reads.
final class FakeText: TextReader {
    var cp = "CP1234", name: (String, Double) = ("Zapdos", 92), above: (String, Double)?, hp = "129 / 129 HP"
    var nameCalls = 0
    init(cp: String = "CP1234", name: (String, Double) = ("Zapdos", 92), above: (String, Double)? = nil, hp: String = "129 / 129 HP") {
        self.cp = cp; self.name = name; self.above = above; self.hp = hp
    }
    func read(_ image: RGBAImage, kind: TextKind) -> TextRead {
        switch kind {
        case .cp: return line(cp, 90)
        case .hp: return line(hp, 90)
        case .name:
            nameCalls += 1
            if let a = above, hasMark(image) { return line(a.0, a.1) }
            return line(name.0, name.1)
        }
    }
}

/// Dark header, white card, optional CP "text" blocks, a green HP bar starting at `barX` of the width
/// (the JS read-frame test's screen).
func cardScreen(cp: Bool = true, barX: Double = 0.26, lucky: Bool = false, w: Int = 400, h: Int = 800) -> RGBAImage {
    var img = RGBAImage(width: w, height: h)
    let W = Double(w), H = Double(h), barY = 0.45 * H
    img.fill(Rect(x: 0, y: 0, w: W, h: H), (60, 80, 100))
    img.fill(Rect(x: 0, y: 0.35 * H, w: W, h: 0.65 * H), (250, 250, 245))
    if cp { for i in 0..<4 { img.fill(Rect(x: 0.42 * W + Double(i) * 0.045 * W, y: 0.06 * H, w: 0.02 * W, h: Double(jsRound(0.025 * H))), (255, 255, 255)) } }
    img.fill(Rect(x: barX * W, y: barY, w: 0.48 * W, h: 0.006 * H), (102, 231, 170))
    if lucky { img.fill(Rect(x: 0.3 * W, y: barY - 0.08 * H, w: 6, h: 4), marker) }
    return img
}

let PINK: (UInt8, UInt8, UInt8) = (218, 113, 120), ORANGE: (UInt8, UInt8, UInt8) = (242, 155, 65)
let GREY: (UInt8, UInt8, UInt8) = (222, 221, 223), WHITE: (UInt8, UInt8, UInt8) = (255, 255, 255)

/// A synthetic appraisal panel: three tracks of 3 blocks x 5 units, filled to the given IVs.
func appraisalPanel(_ ivs: IVs, w: Int = 600, h: Int = 400, unit: Double = 8, gap: Double = 4, barH: Double = 10, top: Double = 100, left: Double = 60, rowGap: Double = 60) -> RGBAImage {
    var img = RGBAImage(width: w, height: h)
    img.fill(Rect(x: 0, y: 0, w: Double(w), h: Double(h)), WHITE)
    img.fill(Rect(x: 0, y: 0, w: Double(w), h: 40), (200, 180, 120))  // something else above the panel
    for (k, v) in [ivs.atk, ivs.def, ivs.hp].enumerated() {
        let y = top + Double(k) * rowGap
        for b in 0..<3 {
            let bx = left + Double(b) * (5 * unit + gap)
            img.fill(Rect(x: bx, y: y, w: 5 * unit, h: barH), GREY)
            let filled = max(0, min(5, v - 5 * b))
            if filled > 0 { img.fill(Rect(x: bx, y: y, w: Double(filled) * unit, h: barH), v == 15 ? PINK : ORANGE) }
        }
    }
    return img
}
