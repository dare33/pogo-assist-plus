import SwiftUI

/// The scan mark, direction G1 (design handoff, Scan §3o): a ring, two parallel diagonal lines clipped inside it
/// and three equal four-point sparks rising along the band. Drawn from the 48 x 48 artboard in the current
/// foreground colour, at any size.
struct ScanMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 48
            ZStack {
                MarkCircle(radius: 22.2).stroke(style: StrokeStyle(lineWidth: 3 * s))
                MarkLines().stroke(style: StrokeStyle(lineWidth: 2.4 * s))
                    .clipShape(MarkCircle(radius: 20.6))
                MarkSparks().fill()
            }
            .frame(width: 48 * s, height: 48 * s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct MarkCircle: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 48
        return Path(ellipseIn: CGRect(x: rect.minX + (24 - radius) * s, y: rect.minY + (24 - radius) * s, width: 2 * radius * s, height: 2 * radius * s))
    }
}

private struct MarkLines: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 48
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(3.02, 47.31)); path.addLine(to: p(54.44, 16.47))
        path.move(to: p(-6.44, 31.53)); path.addLine(to: p(44.98, 0.69))
        return path
    }
}

private struct MarkSparks: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 48
        var path = Path()
        // Each spark: centre (cx, cy), long arm 5.6, short waist 1.57, as in the artboard.
        for (cx, cy) in [(14.0, 30.0), (24.0, 24.0), (34.0, 18.0)] as [(CGFloat, CGFloat)] {
            let pts: [(CGFloat, CGFloat)] = [(0, -5.6), (1.57, -1.57), (5.6, 0), (1.57, 1.57), (0, 5.6), (-1.57, 1.57), (-5.6, 0), (-1.57, -1.57)]
            for (i, d) in pts.enumerated() {
                let pt = CGPoint(x: rect.minX + (cx + d.0) * s, y: rect.minY + (cy + d.1) * s)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
        }
        return path
    }
}
