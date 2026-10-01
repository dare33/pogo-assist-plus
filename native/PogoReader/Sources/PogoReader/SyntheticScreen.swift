import Foundation
import CoreGraphics
import CoreText

/// Draws a Pokémon detail screen the reader's anchors can find: dark header with white "CP1234", the
/// name, a green HP bar with "145 / 145 HP" under it, and a white appraisal panel with three
/// bars. Everything is placed by fractions of the frame, like the real layout, so any size works.
public struct SyntheticScreen {
    public static let names = ["Pikachu", "Bulbasaur", "Charizard", "Mewtwo", "Zapdos", "Eevee", "Machamp", "Dragonite", "Snorlax", "Gengar"]
    /// How many consecutive frames show one Pokémon.
    public static let framesPerPokemon = 6

    public struct Spec {
        public var name: String
        public var cp: Int
        public var hp: Int
        public var ivs: IVs
        public init(name: String, cp: Int, hp: Int, ivs: IVs) { self.name = name; self.cp = cp; self.hp = hp; self.ivs = ivs }
    }

    public static func spec(frame i: Int) -> Spec {
        let k = i / framesPerPokemon
        return Spec(name: names[k % names.count], cp: 1000 + (k * 137) % 2900, hp: 100 + (k * 11) % 90,
                    ivs: IVs(atk: (k * 7) % 16, def: (k * 5 + 3) % 16, hp: (k * 3 + 9) % 16))
    }

    public static func draw(into img: inout RGBAImage, _ s: Spec) {
        let w = img.width, h = img.height
        let W = CGFloat(w), H = CGFloat(h)
        img.bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            // CoreGraphics' origin is bottom-left; flip so fractions read top-down like the frame.
            ctx.translateBy(x: 0, y: H)
            ctx.scaleBy(x: 1, y: -1)
            func rect(_ c: (Int, Int, Int), _ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) {
                ctx.setFillColor(CGColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1))
                ctx.fill(CGRect(x: x.rounded(), y: y.rounded(), width: rw.rounded(), height: rh.rounded()))
            }
            func text(_ str: String, size: CGFloat, centreX: CGFloat, baseline: CGFloat, colour: CGColor) {
                let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
                let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: colour]
                let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, str as CFString, attrs as CFDictionary)!)
                let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                ctx.saveGState()
                ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)     // text upright in the flipped space
                ctx.textPosition = CGPoint(x: centreX - CGFloat(width) / 2, y: baseline)
                CTLineDraw(line, ctx)
                ctx.restoreGState()
            }
            rect((60, 80, 100), 0, 0, W, H)                                   // dark header / scene
            rect((250, 250, 245), 0, 0.35 * H, W, 0.65 * H)                   // white card
            let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1), ink = CGColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1)
            text("CP\(s.cp)", size: 0.035 * H, centreX: 0.5 * W, baseline: 0.06 * H + 0.026 * H, colour: white)
            let barY = 0.45 * H
            rect((102, 231, 170), 0.26 * W, barY, 0.48 * W, 0.006 * H)        // HP bar
            text(s.name, size: 0.03 * H, centreX: 0.5 * W, baseline: barY - 0.022 * H, colour: ink)
            text("\(s.hp) / \(s.hp) HP", size: 0.018 * H, centreX: 0.5 * W, baseline: barY + 0.006 * H + 0.004 * H + 0.019 * H, colour: ink)
            // Appraisal panel: three tracks of 3 blocks x 5 units, orange fill (pink at 15).
            let left = 0.08 * W, gap = (0.008 * W).rounded(), total = 0.45 * W
            let block = ((total - 2 * gap) / 3).rounded(), unit = block / 5, barH = (0.012 * H).rounded()
            for (k, v) in [s.ivs.atk, s.ivs.def, s.ivs.hp].enumerated() {
                let y = 0.62 * H + CGFloat(k) * 0.075 * H
                let fillColour = v == 15 ? (218, 113, 120) : (242, 155, 65)
                for b in 0..<3 {
                    let bx = left + CGFloat(b) * (block + gap)
                    rect((222, 221, 223), bx, y, block, barH)
                    let filled = max(0, min(5, v - 5 * b))
                    if filled > 0 { rect(fillColour, bx, y, unit * CGFloat(filled), barH) }
                }
            }
        }
    }
}

