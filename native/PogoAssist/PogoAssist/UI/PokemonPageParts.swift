import SwiftUI
import PogoBox

// The pieces the Pokémon page of design pass 3 draws with: the activity glyphs and colours, the tab row, the verdict words and the plan block. Their glyph
// paths are the board's own (`OptionA.dc.html`); every colour is a Theme token, so light and dark follow.

// MARK: activity colours and glyphs

extension PokemonActivities.Tab {
    /// The Hub tile this tab shares its glyph and colours with; Summary takes the accent.
    var content: ContentType {
        switch self {
        case .summary: return .everything
        case .pvp: return .pvp
        case .raids: return .raids
        case .gym: return .gym
        case .rocket: return .rocket
        case .max: return .max
        }
    }
}

extension PokemonActivities.Activity {
    var content: ContentType {
        switch self {
        case .pvp: return .pvp
        case .raids: return .raids
        case .gym: return .gym
        case .rocket: return .rocket
        case .max: return .max
        }
    }
}

/// An activity's glyph (the Summary tab's list lines for Summary): strokes in the colour given, the Raids star filled.
struct ActivityGlyph: View {
    let tab: PokemonActivities.Tab
    var size: CGFloat = 15
    let ink: Color
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private struct Layer { let path: String; var fill = false; var width: CGFloat = 2.2 }

    private var layers: [Layer] {
        switch tab {
        case .summary: return [Layer(path: "M5 6h14M5 12h14M5 18h9", width: 2.6)]
        case .raids: return [Layer(path: "M12 2.5C8 2.5 5 8.5 5 13.5a7 7 0 0 0 14 0c0-5-3-11-7-11z"),
                             Layer(path: "M12 9.5l1.3 2.6 2.8.4-2 2 .5 2.8-2.6-1.4-2.6 1.4.5-2.8-2-2 2.8-.4z", fill: true)]
        case .gym: return [Layer(path: "M8 6.5a4 4 0 1 0 8 0a4 4 0 1 0-8 0M8 6.5h8M10 11l-1.5 9.5h7L14 11M5.5 20.5h13")]
        case .rocket: return [Layer(path: "M8.5 20V4h5a4 4 0 0 1 0 8h-5M13 12l4.5 8", width: 2.8)]
        case .pvp: return [Layer(path: "M12 2.5l7.5 3v5.5c0 5-3.2 8.7-7.5 10.5-4.3-1.8-7.5-5.5-7.5-10.5V5.5zM9 8.5l6 6M15 8.5l-6 6")]
        case .max: return [Layer(path: "M7 15a4 4 0 0 1-.6-7.95A5.5 5.5 0 0 1 17 6.5a4.25 4.25 0 0 1 .5 8.5zM12 22v-8M8.5 17.5L12 14l3.5 3.5")]
        }
    }

    var body: some View {
        let side = size * min(scale, 1.5)
        ZStack {
            ForEach(Array(layers.enumerated()), id: \.offset) { _, l in
                if l.fill { SVGGlyph(data: l.path).fill(ink) }
                else { SVGGlyph(data: l.path).stroke(ink, style: StrokeStyle(lineWidth: l.width * side / 24, lineCap: .round, lineJoin: .round)) }
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

// MARK: the tab row

/// Summary, PvP, Raids, Gym, Rocket, Max (rule 19): 38 pt pills with the glyph and label in the activity's colour, `surface` when off, the activity's tint
/// with a 2 pt ring when on. The row scrolls sideways and brings the chosen tab into view.
struct ActivityTabBar: View {
    @Binding var selection: PokemonActivities.Tab
    @Environment(\.accent) private var accent

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PokemonActivities.Tab.allCases, id: \.self) { pill($0).id($0) }
                }
                .padding(.horizontal, Theme.Space.screen).padding(.vertical, 3)
            }
            // The row is as wide as the screen: the page's own margin is taken back so the pills slide to the edge.
            .padding(.horizontal, -Theme.Space.screen)
            .onChange(of: selection) { _, new in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) } }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activities")
        .accessibilityIdentifier("page-tabs")
    }

    private func pill(_ tab: PokemonActivities.Tab) -> some View {
        let on = tab == selection
        let ink = tab.content.ink(accent), tint = tab.content.tint(accent)
        let shape = Capsule()
        return Button { selection = tab } label: {
            HStack(spacing: 6) {
                ActivityGlyph(tab: tab, size: 15, ink: ink)
                Text(tab.title).font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(ink).lineLimit(1).fixedSize()
            }
            .padding(.leading, 10).padding(.trailing, 13)
            .frame(minHeight: 38)
            .background(on ? tint : Theme.surface, in: shape)
            .overlay { if on { shape.strokeBorder(ink, lineWidth: 2) } }
            .modifier(OffShadow(on: !on))
            .padding(.vertical, 3).contentShape(Rectangle()).padding(.vertical, -3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("page-tab-\(tab.rawValue)")
    }
}

private struct OffShadow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { if on { content.panelShadow() } else { content } }
}

// MARK: verdict

/// A Summary row's verdict (D14, D18, D20): 10/800 capitals, letter-spacing .5; green for full strength, top and beats, orange for planned and needs Dynamax,
/// muted for the rest.
struct VerdictText: View {
    let verdict: PokemonActivities.Verdict
    var body: some View {
        Text(verdict.text).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.5).foregroundStyle(ink).lineLimit(1).fixedSize()
    }
    private var ink: Color {
        switch verdict.tone {
        case .positive: return Theme.greenInk
        case .action: return Theme.orangeInk
        case .neutral: return Theme.muted
        }
    }
}

// MARK: cost slot

/// A plan's or a row's mark with its cost, or the Full strength tick.
struct PlanMark: View {
    let mark: MyPokemon.BuildMark
    var label: String?
    var body: some View { BuildMarkView(mark: mark, upgradeLabel: label ?? "Upgrade available") }
}

// MARK: small shared bits

/// A small caption in the board's style: 10/800, letter-spacing .6, `faint`.
struct CapsCaption: View {
    let text: String
    var ink: Color = Theme.faint
    init(_ text: String, ink: Color = Theme.faint) { self.text = text; self.ink = ink }
    var body: some View { Text(text).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.6).foregroundStyle(ink) }
}
