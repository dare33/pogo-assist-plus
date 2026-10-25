#if DEBUG
import SwiftUI

/// The league and ranking pieces on their own, until screens use them. DEBUG only: PogoAssistApp shows it when
/// launched with `-design-gallery`; the file is compiled out of Release. `-reset-ranking` clears the ranking
/// preference before the first read (an `-ranking x` argument cannot do it: the argument domain would shadow every later write).
/// `-appearance` and `-accent` set those preferences as for ComponentGallery.
struct DesignGallery: View {
    @State private var infoOpen = false
    @State private var league = League.gl
    @State private var infoClosedDemo = false
    @Environment(\.accent) private var accent

    init() {
        if CommandLine.arguments.contains("-reset-ranking") { UserDefaults.standard.removeObject(forKey: PrefKey.ranking) }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                    heading("Ranking switch")
                    Panel {
                        RankingSwitch(infoOpen: $infoOpen)
                        if infoOpen { RankingExplainer() }
                    }
                    heading("Info button")
                    Panel {
                        HStack(spacing: 16) {
                            InfoButton(isOpen: $infoClosedDemo, label: "Closed demo", identifier: "info-demo-closed")
                            InfoButton(isOpen: .constant(true), size: 24, label: "Open demo, 24 pt")
                        }
                    }
                    heading("League switch")
                    Panel {
                        SegmentedSwitch(
                            segments: League.allCases.map { .init(value: $0, title: $0.title, dot: $0.dot, selectedInk: $0.ink, identifier: "gallery-league-\($0.rawValue)") },
                            selection: $league, label: "League", identifier: "leagues-control")
                    }
                    heading("Leagues")
                    swatches(League.allCases.map { ($0.title, [("ink", $0.ink), ("dot", $0.dot), ("tint", $0.tint)]) })
                    heading("Content types")
                    swatches(ContentType.allCases.map { ($0.title, [("ink", $0.ink(accent)), ("tint", $0.tint(accent))]) })
                    heading("Other")
                    swatches([("redTint", [("tint", Theme.redTint), ("red", Theme.red)])])
                    heading("Pokémon types")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                        ForEach(Theme.pokemonTypeHex.keys.sorted(), id: \.self) { name in
                            Text(name.uppercased()).font(.figtree(10, .heavy, relativeTo: .caption2)).foregroundStyle(Theme.pokemonTypeText(name))
                                .frame(maxWidth: .infinity, minHeight: 24)
                                .background(Theme.pokemonType(name) ?? .clear, in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.vertical, 12)
            }
            .accessibilityIdentifier("design-gallery-scroll")
        }
        .themeRoot()
    }

    private func heading(_ t: String) -> some View {
        Text(t).paText(.screenTitle).foregroundStyle(Theme.ink).padding(.top, 14).padding(.horizontal, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func swatches(_ rows: [(String, [(String, Color)])]) -> some View {
        Panel(spacing: 8) {
            ForEach(rows, id: \.0) { name, colours in
                HStack(spacing: 8) {
                    Text(name).font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(colours, id: \.0) { label, c in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(c).frame(width: 44, height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line))
                            Text(label).font(.figtree(10, .medium, relativeTo: .caption2)).foregroundStyle(Theme.faint)
                        }
                    }
                }
            }
        }
    }
}
#endif
