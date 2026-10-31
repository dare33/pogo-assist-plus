import SwiftUI
import UIKit
import PogoBox

/// The Pogo Hub, the second tab (design handoff section 4): what is on in Pokémon GO, then six tiles that open the Collection and the squad screens
/// (`HubTypeScreen`). It replaces the old Next list, whose builds now live on the Collection lists screen.
struct HubView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var rankingInfo = false
    /// Owned and released species for the Collection tile's chip, worked out when the box changes (the rule is `HubCollection.overview`).
    @State private var species: (owned: Int, released: Int)?
    /// False while another tab is showing. The two tabs stay alive under each other, and a menu (the account and More buttons) stays
    /// reachable by accessibility even from a hidden stack, so the header's menus are left out until this tab is the one shown.
    var active = true

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    eventsHeader
                    eventsStrip
                    squadsAndCollection
                    if rankingInfo { RankingExplainer(identifier: "hub-ranking-explainer") }
                    adviceLine
                    tiles
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.bottom, 16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: String.self) { PokemonDetailView(id: $0) }
        .navigationDestination(for: ContentType.self) { HubTypeDestination(type: $0) }
        .navigationDestination(for: CollectionRoute.self) { route in
            switch route {
            case .lists(let tab): HubCollectionListsView(tab: tab)
            case .missing: HubMissingView()
            }
        }
        .task(id: "\(model.account ?? "")|\(model.snapshot?.seq ?? -1)") {
            // An empty box still counts: "0/951" (the screen then asks for a scan on top).
            guard let gm = try? GameMaster.bundled() else { species = nil; return }
            let o = HubCollection.overview(entries: model.entries, gm: gm)
            species = (o.owned, o.released)
        }
    }

    // MARK: header

    /// The shared tab header (Greg, 26 Oct 2026): the account name small on the left with its chevron (it opens the account menu), "Pogo Hub" centred, the More circle.
    private var header: some View {
        TabHeader(title: "Pogo Hub", showsAccount: active) {
            if active { MoreButton() }
        }
    }

    // MARK: events

    private var eventsHeader: some View {
        HubHeaderLine("HAPPENING NOW IN POKÉMON GO") {
            Link(destination: URL(string: "https://pokemongo.com/news")!) {
                Text("All news ›").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink).frame(minHeight: 44)
            }
            .accessibilityIdentifier("hub-all-news")
        }
    }

    @ViewBuilder private var eventsStrip: some View {
        let today = HubModel.today()   // the Gregorian day in the device zone; a DEBUG build honours -uitest-today (HubRaidsModel.swift)
        if let hub = try? HubData.bundled() {
            let events = HubModel.upcoming(hub.events, today: today)
            if events.isEmpty {
                Text("Nothing on right now").font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("hub-no-events")
            } else {
                HubCardStrip { ForEach(events.indices, id: \.self) { eventCard(events[$0], today: today) } }
                    .accessibilityIdentifier("hub-events")
            }
        } else {
            Text("The events list could not be read.").font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private func eventCard(_ e: HubData.Event, today: String) -> some View {
        let tie = ContentType(rawValue: e.tie)
        let span = HubModel.span(from: e.from, to: e.to, today: today)
        let card = HubCard(kicker: span.kicker, title: e.title, line: e.line, pill: tie.flatMap(Self.pillText), base: (tie ?? .everything).solid(accent))
        if let tie {
            NavigationLink(value: tie) { card }.buttonStyle(PressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(e.title), \(span.spoken), \(e.line), opens \(tie.title)")
                .accessibilityAddTraits(.isButton)
        } else {
            card.accessibilityElement(children: .ignore).accessibilityLabel("\(e.title), \(span.spoken), \(e.line)")
        }
    }

    static func pillText(_ type: ContentType) -> String? {
        switch type {
        case .everything: return nil
        case .raids: return "See raid picks"
        case .pvp: return "See PvP picks"
        case .max: return "See Max picks"
        case .gym: return "See gym picks"
        case .rocket: return "See Rocket picks"
        }
    }

    // MARK: squads and collection

    private var squadsAndCollection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text("SQUADS AND COLLECTION").modifier(HubHeaderStyle())
                Spacer(minLength: 8)
                RankingSwitch(infoOpen: $rankingInfo, identifier: "hub-ranking")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("SQUADS AND COLLECTION").modifier(HubHeaderStyle())
                RankingSwitch(infoOpen: $rankingInfo, identifier: "hub-ranking")
            }
        }
    }

    @ViewBuilder private var adviceLine: some View {
        switch model.advice {
        case .none:
            Text("Scan your Pokémon and the Hub will fill in").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("hub-advice-none")
        case .computing:
            HStack(spacing: 10) { ProgressView(); Text("Working out advice").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted) }
                .accessibilityElement(children: .combine)
        case .failed(let message):
            Text("Advice could not be worked out: \(message)").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        case .ready: EmptyView()
        }
    }

    // MARK: tiles

    /// The Collection tile's chip is owned/released species ("347/951"); the others count their builds, once the advice is ready.
    private func tile(_ type: ContentType, builds: [BoxAdvice.Build]?) -> HubTile {
        if type == .everything {
            guard let species else { return HubTile(type: type, chip: nil, spoken: nil) }
            return HubTile(type: type, chip: "\(species.owned)/\(species.released)", spoken: "\(species.owned) of \(species.released) species")
        }
        guard let builds else { return HubTile(type: type, chip: nil, spoken: nil) }
        let n = HubModel.count(builds, for: type.key)
        return HubTile(type: type, chip: String(n), spoken: buildsText(n))
    }

    private var tiles: some View {
        let per = typeSize >= .accessibility1 ? 1 : 2
        var builds: [BoxAdvice.Build]?
        if case .ready(let a) = model.advice { builds = a.builds }
        let types = ContentType.allCases
        // Rows of a Grid, so the two tiles of a row are as tall as the taller one.
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: types.count, by: per)), id: \.self) { start in
                GridRow {
                    ForEach(types[start..<min(start + per, types.count)]) { type in
                        NavigationLink(value: type) { tile(type, builds: builds) }
                            .buttonStyle(PressStyle())
                            .accessibilityIdentifier("hub-tile-\(type.rawValue)")
                    }
                }
            }
        }
    }
}

// MARK: content types

extension ContentType {
    /// The advisor areas this screen is for (`HubModel` counts and filters by it).
    var key: ContentKey { ContentKey(rawValue: rawValue) ?? .everything }

    var blurb: String {
        switch self {
        case .everything: return "Dex, sets and builds"
        case .raids: return "Attackers for raid bosses"
        case .gym: return "Defenders and gym attackers"
        case .rocket: return "Counters for grunts and leaders"
        case .pvp: return "Great, Ultra and Master picks"
        case .max: return "Dynamax and Gigantamax"
        }
    }
}

/// "5 builds" / "1 build".
func buildsText(_ n: Int) -> String { "\(n) \(n == 1 ? "build" : "builds")" }

struct HubTile: View {
    let type: ContentType
    /// The chip's text; nil while what it counts is not ready: no chip.
    let chip: String?
    /// What the chip says aloud ("38 builds", "347 of 951 species").
    let spoken: String?
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                HubTileGlyph(type: type)
                Spacer(minLength: 8)
                if let chip {
                    Text(verbatim: chip).font(.figtree(12, .heavy, relativeTo: .caption)).monospacedDigit().foregroundStyle(Theme.muted)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.surface2, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            Text(type.title).font(.figtree(16, .heavy, relativeTo: .body)).foregroundStyle(Theme.ink)
            Text(type.blurb).font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .panelShadow()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken.map { "\(type.title), \($0). \(type.blurb)" } ?? "\(type.title). \(type.blurb)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: shared pieces

/// 13/700 muted caps: the section headers on the Hub and the type screens.
struct HubHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.figtree(13, .bold, relativeTo: .footnote)).tracking(0.04 * 13).foregroundStyle(Theme.muted).accessibilityAddTraits(.isHeader)
    }
}

/// A header line (13/700 muted, .04em) with an optional trailing control (a link in the accent's ink).
struct HubHeaderLine<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing) { self.text = text; self.trailing = trailing() }

    var body: some View {
        // The link drops under the heading when both do not fit on a line (accessibility text sizes), rather than the heading breaking mid-word.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(text).modifier(HubHeaderStyle())
                Spacer(minLength: 8)
                trailing
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(text).modifier(HubHeaderStyle())
                trailing
            }
        }
    }
}

extension HubHeaderLine where Trailing == EmptyView {
    init(_ text: String) { self.init(text) { EmptyView() } }
}

/// A card of the Hub's strips (the events, the Collection lists' headlines): 236 pt wide, radius 22, padding 14 by 16, at least 112 pt
/// tall, white text on `base`, the type's fixed light-mode ink (`ContentType.solid`, 5.28:1 or better in white). In light mode a gradient
/// that darkens towards the far corner, in dark mode the plain solid; the same colour in both, because the dark-mode ink values are pale
/// and white on a 30% wash of them fell under 4.5:1. The pill is black at 22% (white text 7.6:1 or better; the design's white at 22%
/// leaves white text at 3.5 to 4.5:1 on several of the colours). At accessibility text sizes the card is full width and nothing is cut off.
struct HubCard: View {
    let kicker: String
    let title: String
    let line: String
    var pill: String? = nil
    let base: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let big = typeSize.isAccessibilitySize
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker).font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.08 * 11)
            Text(title).font(.figtree(17, .heavy, relativeTo: .headline)).lineLimit(big ? nil : 2).fixedSize(horizontal: false, vertical: big)
            Text(line).font(.figtree(13, .semibold, relativeTo: .footnote)).lineLimit(big ? nil : 2).fixedSize(horizontal: false, vertical: big)
            Spacer(minLength: 6)
            if let pill {
                Text(pill).font(.figtree(11, .heavy, relativeTo: .caption2))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.black.opacity(0.22), in: Capsule())
            }
        }
        .foregroundStyle(Color.white)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(width: big ? nil : 236, alignment: .topLeading)
        .frame(maxWidth: big ? .infinity : nil, minHeight: 112, maxHeight: big ? nil : .infinity, alignment: .topLeading)
        .background {
            if scheme == .dark {
                shape.fill(base)
            } else {
                shape.fill(LinearGradient(colors: [base, Self.darker(base, 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .contentShape(shape)
    }

    /// `c` with its channels scaled towards black (the gradient's far corner stays at least as dark as its start, so white keeps its contrast).
    private static func darker(_ c: Color, _ f: CGFloat) -> Color {
        Color(uiColor: UIColor { trait in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).resolvedColor(with: trait).getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: r * (1 - f), green: g * (1 - f), blue: b * (1 - f), alpha: a)
        })
    }
}

/// The cards side by side in a strip that scrolls sideways and bleeds to the screen edge; at accessibility text sizes they stack, full width.
struct HubCardStrip<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) { content }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { content }.fixedSize(horizontal: false, vertical: true)
            }
            .scrollClipDisabled()
        }
    }
}
