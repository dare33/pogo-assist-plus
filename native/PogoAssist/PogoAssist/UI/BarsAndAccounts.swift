import SwiftUI

// BarsView and AccountMonogram (design handoff components 8 and 9), and the Box header pieces.

/// Three IV bars in game orange, each filled to iv / 15. The full variant has labels (Attack, Defence, HP) and the
/// value; `.mini` is the 4 pt triple used on grid tiles.
struct BarsView: View {
    var attack: Int
    var defence: Int
    var hp: Int
    var mini = false

    init(_ attack: Int, _ defence: Int, _ hp: Int, mini: Bool = false) {
        self.attack = attack; self.defence = defence; self.hp = hp; self.mini = mini
    }

    var body: some View {
        if mini {
            VStack(spacing: 2) { ForEach(Array(values.enumerated()), id: \.offset) { track($0.element, height: 4) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("IVs \(attack), \(defence), \(hp)")
        } else {
            VStack(spacing: 12) {
                ForEach(Array(zip(["Attack", "Defence", "HP"], values).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10) {
                        Text(item.0).font(.figtree(14, .semibold, relativeTo: .subheadline)).frame(width: 62 * scale, alignment: .leading)
                        track(item.1, height: 10)
                        Text("\(item.1)").font(.figtree(14, .semibold, relativeTo: .subheadline)).monospacedDigit().frame(width: 22 * scale, alignment: .trailing)
                    }
                    .foregroundStyle(Theme.ink)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
    @ScaledMetric private var scale: CGFloat = 1

    private var values: [Int] { [attack, defence, hp] }

    private func track(_ v: Int, height: CGFloat) -> some View {
        GeometryReader { g in
            Capsule().fill(Theme.off)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.orange).frame(width: g.size.width * CGFloat(min(max(v, 0), 15)) / 15)
                }
                .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

/// A circle in the account's colour with two initials. The app keeps no colour per account, so the colour comes
/// from the name (stable between launches) out of the design's account colours.
struct AccountMonogram: View {
    let name: String
    var size: CGFloat = 28

    static let palette: [UInt32] = [0x2F6BFF, 0x14A3B8, 0x22A55A, 0xFF8A1F, 0x9B51E0, 0xE8457A, 0xA2845E]

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard let first = words.first else { return "?" }
        if words.count >= 2, let a = first.first, let b = words[1].first { return String([a, b]).uppercased() }
        return String(first.prefix(2)).uppercased()
    }
    static func color(_ name: String) -> Color {
        // A plain sum of the scalars: Swift's own hashing is seeded per launch.
        let n = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 }
        return Color(uiColor: Theme.rgb(palette[n % palette.count]))
    }

    var body: some View {
        Text(Self.initials(name))
            .font(.figtree(size * 11 / 28, .heavy, relativeTo: .caption))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Self.color(name)))
            .accessibilityHidden(true)
    }
}
