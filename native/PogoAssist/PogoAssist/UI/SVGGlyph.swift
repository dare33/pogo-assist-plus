import SwiftUI

/// An SVG path string ("M12 3a9 9 0 1 0 0 18z") drawn as a SwiftUI `Path`, scaled from its 24 x 24 viewBox to the rect it is given. The design boards draw
/// the type glyphs, the upgrade arrow, the tick and the currency icons as such strings, so they are kept as the boards have them and read here rather than
/// redrawn by hand. Supports M, L, H, V, C, S, Q, A and Z in both cases, which covers every glyph in the design.
struct SVGGlyph: Shape {
    let data: String
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var p = SVGPathReader.path(data)
        let side = min(rect.width, rect.height)
        let k = side / viewBox
        p = p.applying(CGAffineTransform(scaleX: k, y: k))
        return p.offsetBy(dx: rect.minX + (rect.width - side) / 2, dy: rect.minY + (rect.height - side) / 2)
    }
}

enum SVGPathReader {
    static func path(_ d: String) -> Path {
        var tokens = Tokens(Array(d.unicodeScalars))
        var path = Path()
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCubic: CGPoint?
        var cmd: Character = "M"
        while let c = tokens.nextCommand(or: cmd) {
            cmd = c
            let rel = c.isLowercase
            func abs(_ x: Double, _ y: Double) -> CGPoint { rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y) }
            var cubic: CGPoint?
            switch Character(c.uppercased()) {
            case "M":
                guard let x = tokens.number(), let y = tokens.number() else { return path }
                cur = abs(x, y); start = cur; path.move(to: cur)
                cmd = rel ? "l" : "L"   // further pairs after a moveto are linetos
            case "L":
                guard let x = tokens.number(), let y = tokens.number() else { return path }
                cur = abs(x, y); path.addLine(to: cur)
            case "H":
                guard let x = tokens.number() else { return path }
                cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y); path.addLine(to: cur)
            case "V":
                guard let y = tokens.number() else { return path }
                cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y); path.addLine(to: cur)
            case "C":
                guard let a = tokens.number(), let b = tokens.number(), let c2 = tokens.number(), let d2 = tokens.number(), let x = tokens.number(), let y = tokens.number() else { return path }
                let p1 = abs(a, b), p2 = abs(c2, d2), end = abs(x, y)
                path.addCurve(to: end, control1: p1, control2: p2); cubic = p2; cur = end
            case "S":
                guard let c2 = tokens.number(), let d2 = tokens.number(), let x = tokens.number(), let y = tokens.number() else { return path }
                let p1 = lastCubic.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let p2 = abs(c2, d2), end = abs(x, y)
                path.addCurve(to: end, control1: p1, control2: p2); cubic = p2; cur = end
            case "Q":
                guard let a = tokens.number(), let b = tokens.number(), let x = tokens.number(), let y = tokens.number() else { return path }
                let p1 = abs(a, b), end = abs(x, y)
                path.addQuadCurve(to: end, control: p1); cur = end
            case "A":
                guard let rx = tokens.number(), let ry = tokens.number(), let rot = tokens.number(), let large = tokens.flag(), let sweep = tokens.flag(), let x = tokens.number(), let y = tokens.number() else { return path }
                let end = abs(x, y)
                addArc(&path, from: cur, to: end, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep)
                cur = end
            case "Z":
                path.closeSubpath(); cur = start
            default:
                return path
            }
            lastCubic = cubic
        }
        return path
    }

    /// The SVG arc (endpoint form) as cubic curves: the endpoint-to-centre conversion of the SVG implementation notes, then up to a quarter turn per curve.
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: Double, ry ry0: Double, rotation: Double, large: Bool, sweep: Bool) {
        var rx = Swift.abs(rx0), ry = Swift.abs(ry0)
        if p0 == p1 { return }
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180, cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (Double(p0.x) - Double(p1.x)) / 2, dy = (Double(p0.y) - Double(p1.y)) / 2
        let x1 = cosPhi * dx + sinPhi * dy, y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : (max(0, num / den)).squareRoot()
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1 / ry, cyp = -coef * ry * x1 / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (Double(p0.x) + Double(p1.x)) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (Double(p0.y) + Double(p1.y)) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
        var delta = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi } else if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int((Swift.abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(segments)
        let t = 4.0 / 3.0 * tan(step / 4)
        var a = theta1
        for _ in 0..<segments {
            let b = a + step
            func point(_ ang: Double, _ dxs: Double = 0, _ dys: Double = 0) -> CGPoint {
                let ex = rx * (cos(ang) + dxs), ey = ry * (sin(ang) + dys)
                return CGPoint(x: cosPhi * ex - sinPhi * ey + cx, y: sinPhi * ex + cosPhi * ey + cy)
            }
            let c1 = point(a, -t * sin(a), t * cos(a)), c2 = point(b, t * sin(b), -t * cos(b))
            path.addCurve(to: point(b), control1: c1, control2: c2)
            a = b
        }
    }

    /// Reads numbers and commands out of a path string. A number may start with a sign or a point straight after the last one ("7 7-4.6.6"); an arc flag is a
    /// single 0 or 1 that may touch the next number.
    private struct Tokens {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        mutating func skipSeparators() { while i < s.count, s[i] == " " || s[i] == "," || s[i] == "\n" || s[i] == "\t" { i += 1 } }

        /// The next command letter, or `repeating` when numbers follow without one; nil at the end.
        mutating func nextCommand(or repeating: Character) -> Character? {
            skipSeparators()
            guard i < s.count else { return nil }
            let c = Character(s[i])
            if c.isLetter { i += 1; return c }
            return repeating
        }

        mutating func number() -> Double? {
            skipSeparators()
            let begin = i
            if i < s.count, s[i] == "-" || s[i] == "+" { i += 1 }
            var seenPoint = false
            while i < s.count {
                let c = s[i]
                if c.properties.numericType != nil, c.value < 128 { i += 1 }
                else if c == ".", !seenPoint { seenPoint = true; i += 1 }
                else { break }
            }
            return begin == i ? nil : Double(String(String.UnicodeScalarView(s[begin..<i])))
        }

        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < s.count, s[i] == "0" || s[i] == "1" else { return nil }
            defer { i += 1 }
            return s[i] == "1"
        }
    }
}
