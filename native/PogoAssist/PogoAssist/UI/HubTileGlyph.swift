import SwiftUI

/// The six Hub tile glyphs (pass 2 `Main.dc.html`), drawn after the game's own icons but as our own paths, not its artwork: a Pokédex, a raid egg with a star, a gym tower,
/// a bold R, a shield with crossed blades and a Dynamax cloud with a rising arrow. Each is a few SVG path strings in the boards' 24 x 24 box, stroked (or filled) in the
/// tile's ink. The glyph grows with the text size, but not past 1.6 times, so the chip beside it keeps its place.
struct HubTileGlyph: View {
    let type: ContentType
    @Environment(\.accent) private var accent
    @ScaledMetric(relativeTo: .title2) private var scale: CGFloat = 1

    private struct Part { let path: String; var width: CGFloat = 2; var filled = false }

    private static func parts(_ type: ContentType) -> [Part] {
        switch type {
        case .everything:
            return [Part(path: "M7 2.5h10a3 3 0 0 1 3 3v13a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3v-13a3 3 0 0 1 3-3z"),
                    Part(path: "M6.5 8a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0z"),
                    Part(path: "M14 6.8h3M14 9.3h3M7.5 14h9M7.5 17.5h6")]
        case .raids:
            return [Part(path: "M12 2.5C8 2.5 5 8.5 5 13.5a7 7 0 0 0 14 0c0-5-3-11-7-11z", width: 2.2),
                    Part(path: "M12 9.5l1.3 2.6 2.8.4-2 2 .5 2.8-2.6-1.4-2.6 1.4.5-2.8-2-2 2.8-.4z", filled: true)]
        case .gym:
            return [Part(path: "M8 6.5a4 4 0 1 0 8 0a4 4 0 1 0-8 0z"),
                    Part(path: "M8 6.5h8M10 11l-1.5 9.5h7L14 11M5.5 20.5h13")]
        case .rocket:
            return [Part(path: "M8.5 20V4h5a4 4 0 0 1 0 8h-5M13 12l4.5 8", width: 2.6)]
        case .pvp:
            return [Part(path: "M12 2.5l7.5 3v5.5c0 5-3.2 8.7-7.5 10.5-4.3-1.8-7.5-5.5-7.5-10.5V5.5z"),
                    Part(path: "M9 8.5l6 6M15 8.5l-6 6")]
        case .max:
            return [Part(path: "M7 15a4 4 0 0 1-.6-7.95A5.5 5.5 0 0 1 17 6.5a4.25 4.25 0 0 1 .5 8.5z"),
                    Part(path: "M12 22v-8M8.5 17.5L12 14l3.5 3.5")]
        }
    }

    var body: some View {
        let side = 22 * min(scale, 1.6), k = side / 24, ink = type.ink(accent)
        ZStack {
            ForEach(Array(Self.parts(type).enumerated()), id: \.offset) { _, p in
                if p.filled {
                    SVGGlyph(data: p.path).fill(ink)
                } else {
                    SVGGlyph(data: p.path).stroke(ink, style: StrokeStyle(lineWidth: p.width * k, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
