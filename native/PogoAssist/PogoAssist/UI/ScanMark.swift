import SwiftUI

/// The scan mark, matching the app icon (icon direction 2a): an open ring with its gap at the upper right and
/// three rounded five-point stars of growing size climbing the diagonal towards that gap. Drawn from the 48 x 48
/// artboard (the icon's 1024 x 1024 space divided by 1024/48), at any size. The ring takes the current
/// foreground style so the call sites can tint it; the stars are the icon's gold gradient, which reads on both
/// the light and dark accent discs. `monochrome: true` draws the stars in the foreground style too, for small or
/// tinted uses where gold would fight the surface.
struct ScanMark: View {
    var monochrome = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 48
            ZStack {
                MarkRing().stroke(style: StrokeStyle(lineWidth: 3.094 * s, lineCap: .round))
                ForEach(MarkStar.all.indices, id: \.self) { i in
                    let star = MarkStar.all[i]
                    let line = StrokeStyle(lineWidth: star.stroke * s, lineJoin: .round)
                    if monochrome {
                        // Fill and stroke in one colour: the stroke is what rounds the points.
                        ZStack {
                            star.shape.fill()
                            star.shape.stroke(style: line)
                        }
                    } else {
                        ZStack {
                            star.shape.fill(star.gradient)
                            star.shape.stroke(star.gradient, style: line)
                        }
                    }
                }
            }
            .frame(width: 48 * s, height: 48 * s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Circle of radius 14.0625 about (24, 24), running clockwise on screen from -10 degrees the long way round to
/// -80 degrees, which leaves the 70 degree gap at the upper right. SwiftUI's `clockwise` flag is inverted on
/// screen (the y axis points down), hence `false` for a visually clockwise sweep.
private struct MarkRing: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 48
        var path = Path()
        path.addArc(center: CGPoint(x: rect.minX + 24 * s, y: rect.minY + 24 * s), radius: 14.0625 * s,
                    startAngle: .degrees(-10), endAngle: .degrees(-80), clockwise: false)
        return path
    }
}

/// One star: the icon's exact vertices on the artboard (outer, inner, outer ... starting at the top point), its
/// stroke width, and the gradient spanning its own top to bottom (the icon's gradient is per star).
private struct MarkStar {
    let points: [(CGFloat, CGFloat)]
    let stroke: CGFloat

    var shape: StarShape { StarShape(points: points) }

    var gradient: LinearGradient {
        let ys = points.map(\.1)
        return LinearGradient(colors: [Color(red: 1, green: 0.8902, blue: 0.5608), Color(red: 1, green: 0.6824, blue: 0.1020)],
                              startPoint: UnitPoint(x: 0.5, y: (ys.min() ?? 0) / 48),
                              endPoint: UnitPoint(x: 0.5, y: (ys.max() ?? 48) / 48))
    }

    static let all: [MarkStar] = [
        MarkStar(points: [(19.028, 25.972), (19.91, 27.758), (21.881, 28.045), (20.455, 29.435), (20.791, 31.399),
                          (19.028, 30.472), (17.265, 31.399), (17.602, 29.435), (16.175, 28.045), (18.146, 27.758)],
                 stroke: 1.02),
        MarkStar(points: [(24.994, 18.975), (26.179, 21.375), (28.828, 21.76), (26.911, 23.628), (27.364, 26.267),
                          (24.994, 25.021), (22.625, 26.267), (23.078, 23.628), (21.16, 21.76), (23.81, 21.375)],
                 stroke: 1.371),
        MarkStar(points: [(32.452, 10.298), (33.995, 13.424), (37.445, 13.926), (34.949, 16.359), (35.538, 19.795),
                          (32.452, 18.173), (29.366, 19.795), (29.955, 16.359), (27.459, 13.926), (30.909, 13.424)],
                 stroke: 1.785),
    ]
}

private struct StarShape: Shape {
    let points: [(CGFloat, CGFloat)]
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 48
        var path = Path()
        for (i, p) in points.enumerated() {
            let pt = CGPoint(x: rect.minX + p.0 * s, y: rect.minY + p.1 * s)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}
