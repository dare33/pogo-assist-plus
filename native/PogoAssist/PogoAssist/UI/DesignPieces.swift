import SwiftUI
import PogoBox

// The pieces design passes 2 and 3 share (pass 2 README "Design tokens added" and "Shared components", pass 3 README): type icons, the upgrade mark with its cost,
// the Full strength badge, graded numbers and the tab header. Their glyphs are the boards' own SVG path strings (`SVGGlyph`). Every colour is a Theme token, so
// light and dark follow; sizes that carry a glyph grow a little with the text size (never past 1.5 times) so they stay in step with the words beside them.

// MARK: glyph paths

enum Glyph {
    /// The 18 type glyphs (pass 2 boards' `TYPE_PATHS`), our own drawings, not the game's artwork.
    static let types: [String: String] = [
        "normal": "M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18zm0 4.5a4.5 4.5 0 1 1 0 9a4.5 4.5 0 1 1 0-9z",
        "fire": "M12 2c1 4 6 6 6 12a6 6 0 0 1-12 0c0-3 2-5 3-6c0 2 1 3 2 3c0-4-1-6 1-9z",
        "water": "M12 2.5c3 4.5 6 8 6 11.5a6 6 0 0 1-12 0c0-3.5 3-7 6-11.5z",
        "electric": "M13.5 2L5 13.5h6L9.5 22L19 9.5h-6.5L13.5 2z",
        "grass": "M19 3C9 3 4.5 9 4.5 15.5c0 1.2.2 2.4.6 3.5L7 17.1C9.6 17.9 19 15 19 3z",
        "ice": "M11 2h2v7.3l6.3-3.6 1 1.7L14 11l6.3 3.6-1 1.7L13 12.7V22h-2v-9.3l-6.3 3.6-1-1.7L10 11 3.7 7.4l1-1.7L11 9.3z",
        "fighting": "M6 10a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v5a5 5 0 0 1-5 5h-2a5 5 0 0 1-5-5zM7.5 3.5h2.5v3.5H7.5zM11 2.5h2.5v4.5H11zM14.5 3.5H17v3.5h-2.5z",
        "poison": "M4 14a5 5 0 1 0 10 0a5 5 0 1 0-10 0zM14 7a3 3 0 1 0 6 0a3 3 0 1 0-6 0zM15 17a2 2 0 1 0 4 0a2 2 0 1 0-4 0z",
        "ground": "M2 19L9 7l4 6 2.5-3.5L22 19z",
        "flying": "M3 14c4-1 7-4 9-10c1 4 1 7-1 9c3 0 6-1 9-3c-2 5-6 8-11 8c-2 0-4-1-6-4z",
        "psychic": "M12 6C7 6 3.5 9.5 2 12c1.5 2.5 5 6 10 6s8.5-3.5 10-6c-1.5-2.5-5-6-10-6zm0 3a3 3 0 1 1 0 6a3 3 0 1 1 0-6z",
        "bug": "M8 4.5l2.2 2.2h3.6L16 4.5l1.2 1.2-2 2.2A5 5 0 0 1 17 11.5v3.5a5 5 0 0 1-10 0v-3.5a5 5 0 0 1 1.8-3.6l-2-2.2z",
        "rock": "M7 4h9l5 6-3 9H7l-4-8z",
        "ghost": "M12 3a7 7 0 0 0-7 7v11l2.5-2 2.3 2 2.2-2 2.2 2 2.3-2 2.5 2V10a7 7 0 0 0-7-7zM9.5 9a1.5 1.5 0 1 1 0 3a1.5 1.5 0 1 1 0-3zm5 0a1.5 1.5 0 1 1 0 3a1.5 1.5 0 1 1 0-3z",
        "dragon": "M4 20c0-8 4.5-14 15-16c-4 3-6 6-6 9c2-1 4.5-1 6.5 0c-4.5 1-7.5 3-8.5 7z",
        "dark": "M15 3a9 9 0 1 0 6 15.5A7 7 0 0 1 15 3z",
        "steel": "M12 2l8.7 5v10L12 22l-8.7-5V7zm0 6.5a3.5 3.5 0 1 0 0 7a3.5 3.5 0 1 0 0-7z",
        "fairy": "M11 2c.8 5 2 7.2 7 8-5 .8-6.2 3-7 8-.8-5-2-7.2-7-8 5-.8 6.2-3 7-8zM18.5 14c.3 2 1 2.7 3 3-2 .3-2.7 1-3 3-.3-2-1-2.7-3-3 2-.3 2.7-1 3-3z",
    ]
    static let upArrow = "M12 4l-7 7h4.5v9h5v-9H19z"
    static let tick = "M5 12.5l4.5 4.5L19 7.5"
    static let stardust = "M12 3c.6 4.6 2.4 6.4 7 7-4.6.6-6.4 2.4-7 7-.6-4.6-2.4-6.4-7-7 4.6-.6 6.4-2.4 7-7z"
    static let candy = "M8.5 8.5a5 5 0 1 1 7 7a5 5 0 1 1-7-7zM2.5 3l5 1.5.5 3.5zM21.5 21l-5-1.5-.5-3.5z"
}

/// The point size of a glyph beside text: it grows with Dynamic Type, but not past 1.5 times, so a row of icons does not outgrow its row.
private struct GrowsWithText: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    let size: CGFloat
    func body(content: Content) -> some View { content.frame(width: size * min(scale, 1.5), height: size * min(scale, 1.5)) }
}
private extension View {
    func glyphFrame(_ size: CGFloat) -> some View { modifier(GrowsWithText(size: size)) }
}

// MARK: type icons

/// A Pokémon type as a circle in the game's type colour with its glyph in white or ink (`Theme.pokemonTypeText`). Sizes 22, 18 (rows and cards), 16 (pills) and 13
/// (beaten-by lists); `grey` is the muted version for a type that is not in play (`off` circle, `faint` glyph). The type's name is the accessibility label.
struct TypeIcon: View {
    let type: String
    var size: CGFloat = 22
    var grey = false

    private var key: String { type.lowercased() }
    private var name: String { type.prefix(1).uppercased() + type.dropFirst().lowercased() }

    var body: some View {
        SVGGlyph(data: Glyph.types[key] ?? Glyph.types["normal"] ?? "")
            .fill(grey ? Theme.faint : Theme.pokemonTypeText(key), style: FillStyle(eoFill: true))
            .padding(size * 0.2)
            .glyphFrame(size)
            .background(Circle().fill(grey ? Theme.off : (Theme.pokemonType(key) ?? Theme.off)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isImage)
    }
}

/// A Pokémon's types, side by side with a 3 pt gap.
struct TypeIcons: View {
    let types: [String]
    var size: CGFloat = 22
    var grey = false
    var body: some View {
        HStack(spacing: 3) { ForEach(Array(types.enumerated()), id: \.offset) { TypeIcon(type: $0.element, size: size, grey: grey) } }
    }
}

// MARK: build marks

/// The currency icon after a cost: the stardust sparkle (violet) or the candy (muted), 12 pt.
struct CurrencyIcon: View {
    let currency: MyPokemon.Currency
    var body: some View {
        SVGGlyph(data: currency == .dust ? Glyph.stardust : Glyph.candy)
            .fill(currency == .dust ? Theme.changeInk : Theme.muted, style: FillStyle(eoFill: true))
            .glyphFrame(12)
            .accessibilityHidden(true)
    }
}

/// Upgrade available: an 18 pt circle on `orangeTint` with an up arrow in `orangeInk`; with a cost, the value (12/800 `orangeInk`) and its currency icon follow.
/// `label` is what VoiceOver reads for the whole mark ("Upgrade available: power up Umbreon").
struct UpgradeMark: View {
    var cost: MyPokemon.Cost? = nil
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            SVGGlyph(data: Glyph.upArrow).fill(Theme.orangeInk).padding(3.5).glyphFrame(18).background(Circle().fill(Theme.orangeTint))
            if let cost {
                Text(cost.value).font(.figtree(12, .heavy, relativeTo: .caption)).monospacedDigit().foregroundStyle(Theme.orangeInk).fixedSize()
                CurrencyIcon(currency: cost.currency)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
    }
}

/// Full strength: a solid green circle with a tick (white in light mode, the background's ink in dark). 18 pt, or 26 pt on build lists.
struct FullStrengthBadge: View {
    var size: CGFloat = 18
    var body: some View {
        SVGGlyph(data: Glyph.tick).stroke(Theme.pair(0xFFFFFF, 0x0E1118), style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
            .padding(size * 0.2)
            .glyphFrame(size)
            .background(Circle().fill(Theme.green))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Full strength")
            .accessibilityAddTraits(.isImage)
    }
}

/// A build mark from `MyPokemon`: the upgrade arrow with its cost, the Full strength tick, or nothing. `label` is the spoken form of an upgrade
/// ("Upgrade available: 2 builds to do, 12k dust").
struct BuildMarkView: View {
    let mark: MyPokemon.BuildMark
    var upgradeLabel = "Upgrade available"
    var body: some View {
        switch mark {
        case .upgrade(let cost, _): UpgradeMark(cost: cost, label: upgradeLabel)
        case .fullStrength: FullStrengthBadge()
        case .none: EmptyView()
        }
    }
}

// MARK: number grades

/// A number graded as `MyPokemon.Grade` says: top = `greenInk` 800 on `greenTint` (radius 6, 0 x 4 padding), good = `greenInk` 700, plain = the caller's weight and
/// colour. `size` and `plain` are the weight the surrounding text has, so the number sits in its line.
struct GradedNumber: View {
    let text: String
    let grade: MyPokemon.Grade
    var size: CGFloat = 13
    var plain: Font.Weight = .regular
    var style: Font.TextStyle = .footnote

    init(_ text: String, _ grade: MyPokemon.Grade, size: CGFloat = 13, plain: Font.Weight = .regular, relativeTo style: Font.TextStyle = .footnote) {
        self.text = text; self.grade = grade; self.size = size; self.plain = plain; self.style = style
    }

    var body: some View {
        switch grade {
        case .plain: Text(text).font(.figtree(size, plain, relativeTo: style)).monospacedDigit()
        case .good: Text(text).font(.figtree(size, .bold, relativeTo: style)).monospacedDigit().foregroundStyle(Theme.greenInk)
        case .top:
            Text(text).font(.figtree(size, .heavy, relativeTo: style)).monospacedDigit().foregroundStyle(Theme.greenInk)
                .padding(.horizontal, 4)
                .background(Theme.greenTint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

extension MyPokemon.Grade {
    /// The grade as a word for VoiceOver, empty for plain.
    var spoken: String { self == .top ? "top" : self == .good ? "good" : "" }
}

// MARK: tab header

/// The header both tabs use (Greg, 26 Oct 2026): the account name small on the left (15/700 in the accent's ink, with a chevron; it opens the account menu), the
/// tab's title centred (17/800 in ink) and the tab's circle buttons on the right. At the accessibility text sizes the three no longer fit on one line, so the title
/// moves under the account name and the buttons rather than being cut off.
struct TabHeader<Trailing: View>: View {
    let title: String
    /// False while the tab is hidden: a menu in a hidden stack stays reachable by accessibility, so the account menu waits until the tab is shown.
    var showsAccount = true
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The circle buttons keep their 40 pt circles: their glyphs stop growing at xxxLarge, or they spill out of them and over each other.
    private var buttons: some View { HStack(spacing: 4) { trailing }.dynamicTypeSize(...DynamicTypeSize.xxxLarge) }

    private var heading: some View {
        Text(title).font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink).lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("tab-title")
    }
    private var account: some View {
        Group { if showsAccount { AccountTabButton() } else { Color.clear.frame(width: 1, height: 44) } }
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    HStack(spacing: 4) { account; Spacer(minLength: 8); buttons }
                    heading.frame(maxWidth: .infinity).padding(.bottom, 6)
                }
            } else {
                TabHeaderLayout {
                    account
                    heading
                    buttons
                }
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .frame(minHeight: 52)
    }
}

/// Account at the leading edge, the buttons at the trailing edge, the title centred on the header between them: it gets the width left once both sides have taken
/// the wider one's share, and is cut (one line) before the account name is.
private struct TabHeaderLayout: Layout {
    private func sizes(_ width: CGFloat, _ s: Subviews) -> (CGSize, CGSize, CGSize) {
        let trailing = s[2].sizeThatFits(.unspecified)
        let leading = s[0].sizeThatFits(ProposedViewSize(width: max(0, min(width * 0.5, width - trailing.width - 8)), height: nil))
        let side = max(leading.width, trailing.width) + 8
        let title = s[1].sizeThatFits(ProposedViewSize(width: max(0, width - 2 * side), height: nil))
        return (leading, CGSize(width: min(title.width, max(0, width - 2 * side)), height: title.height), trailing)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 402
        let (l, t, r) = sizes(w, subviews)
        return CGSize(width: w, height: max(l.height, t.height, r.height))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (l, t, r) = sizes(bounds.width, subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(l))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(r))
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(t))
    }
}

/// The account name for a tab header: 15/700 in the accent's ink with a chevron, opening the account menu (switch account, New account).
struct AccountTabButton: View {
    var body: some View { AccountMenu(tab: true) }
}
