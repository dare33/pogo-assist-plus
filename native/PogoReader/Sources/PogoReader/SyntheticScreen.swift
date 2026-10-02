import Foundation
import CoreGraphics
import CoreText

/// Draws a Pokémon detail screen the reader's anchors can find: dark header with white "CP1234", the
/// name, a green HP bar with "145 / 145 HP" under it, and a white appraisal panel with three
/// bars. Everything is placed by fractions of the frame, like the real layout, so any size works.
public struct SyntheticScreen {
    /// Colours of the drawn screen. `.phone` is the iPhone's bright layout; `.padMuted` the iPad's red-tinted
    /// card with its muted green HP bar (about 120/142/108), which only just passes the green test and is the
    /// first thing a 4:2:0 round trip loses.
    public struct Style {
        public var header: (Int, Int, Int), card: (Int, Int, Int), hpBar: (Int, Int, Int)
        /// A thin stroke along the card's top edge (nil: none).
        public var edgeStroke: (Int, Int, Int)?
        /// A dark band along the very top (1.35% of the height), as the darkest real skies have (darentas-02 f3049: 22 rows
        /// at 750 px wide averaging under 30); `contentRect` cuts it as a border, which must not matter.
        public var topBand: (Int, Int, Int)?
        public init(header: (Int, Int, Int), card: (Int, Int, Int), hpBar: (Int, Int, Int), edgeStroke: (Int, Int, Int)? = nil, topBand: (Int, Int, Int)? = nil) { self.header = header; self.card = card; self.hpBar = hpBar; self.edgeStroke = edgeStroke; self.topBand = topBand }
        public static let phone = Style(header: (60, 80, 100), card: (250, 250, 245), hpBar: (102, 231, 170))
        public static let padMuted = Style(header: (110, 115, 125), card: (218, 149, 149), hpBar: (120, 142, 108))
        /// A Poison- or Ghost-type background: a dark purple sky (about 8,7,52 to 40,20,80) over a white card whose top edge has a
        /// thin dark stroke, as the real screens have. Dark enough that one row (the stroke) averages near the black-border test.
        public static let darkTopBand = Style(header: (24, 14, 66), card: (252, 252, 250), hpBar: (102, 231, 170), edgeStroke: (33, 31, 36), topBand: (6, 6, 40))
        public static let darkSky = Style(header: (24, 14, 66), card: (252, 252, 250), hpBar: (102, 231, 170), edgeStroke: (33, 31, 36))
    }

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

    public static func draw(into img: inout RGBAImage, _ s: Spec, style: Style = .phone) {
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
            rect(style.header, 0, 0, W, H)                                    // header / scene
            if let band = style.topBand { rect(band, 0, 0, W, 0.0135 * H) }
            rect(style.card, 0, 0.35 * H, W, 0.65 * H)                        // card
            if let stroke = style.edgeStroke { rect(stroke, 0, 0.35 * H - 0.0012 * H, W, 0.0022 * H) }   // the card's dark top edge
            let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1), ink = CGColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1)
            text("CP\(s.cp)", size: 0.035 * H, centreX: 0.5 * W, baseline: 0.06 * H + 0.026 * H, colour: white)
            let barY = 0.45 * H
            rect(style.hpBar, 0.26 * W, barY, 0.48 * W, 0.006 * H)           // HP bar
            text(s.name, size: 0.03 * H, centreX: 0.5 * W, baseline: barY - 0.022 * H, colour: ink)
            text("\(s.hp) / \(s.hp) HP", size: 0.018 * H, centreX: 0.5 * W, baseline: barY + 0.006 * H + 0.004 * H + 0.019 * H, colour: ink)
            rect((255, 255, 255), 0.04 * W, 0.58 * H, 0.58 * W, 0.34 * H)    // the appraisal panel's white box
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

