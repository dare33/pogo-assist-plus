import SwiftUI
import PogoBox

/// Where the Collection's links go (pass 2 README "Collection"): the lists screen on one of its three tabs, and the full list of missing species.
enum CollectionRoute: Hashable {
    case lists(CollectionTab)
    case missing
}

/// The three lists behind the Collection's summary cards.
enum CollectionTab: String, CaseIterable, Hashable {
    case builds, gaps, duplicates
    var label: String { rawValue.capitalized }
}

/// Everything the Collection screen shows that comes from the box and the game master (`HubCollection`), worked out once per box rather than on every redraw.
struct CollectionData {
    var overview: HubCollection.Overview
    var showcase: [BoxEntry]
    var sets: [HubCollection.SpecialSet]
    /// Evolvable first, then dex order: the first six are the screen's preview and the full list keeps the same order.
    var missing: [HubCollection.MissingSpecies]
    var gm: GameMaster

    static func make(entries: [BoxEntry], advice: BoxAdvice?, gm: GameMaster) -> CollectionData {
        let missing = HubCollection.missingSpecies(entries: entries, advice: advice ?? BoxAdvice(), gm: gm)
        return CollectionData(overview: HubCollection.overview(entries: entries, gm: gm),
                              showcase: HubCollection.showcase(entries: entries, gm: gm),
                              sets: HubCollection.specialSets(entries: entries, gm: gm, isLucky: { $0.row.lucky == true }),
                              missing: missing.filter { $0.evolvesFrom != nil } + missing.filter { $0.evolvesFrom == nil },
                              gm: gm)
    }
}

/// The Collection screen (pass 2 README "Collection", boards `Collection.dc.html`): the species count, the dex by region, the Showcase of the best copies, the special
/// sets, the missing species and three summary cards that open the lists screen. Replaces the Everything screen.
struct HubCollectionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var data: CollectionData?

    private var adviceReady: BoxAdvice? { model.hubAdvice }
    /// The box, the account and whether the advice is in (the Missing "how to get" reads the advice's gaps).
    private var key: String { "\(model.account ?? "")|\(model.snapshot?.seq ?? -1)|\(adviceReady != nil)" }

    var body: some View {
        let o = data?.overview
        return HubTypeScreen(type: .everything,
                             sub: model.entries.isEmpty ? nil : "\(HubModel.grouped(model.entries.count)) Pokémon in your box",
                             count: o.map { "\($0.owned) of \($0.released)" },
                             countSpoken: o.map { "\($0.owned) of \($0.released) species" }) {
            // An empty box still shows the species panel, the regions and Missing (all at zero); the prompt is an extra line on top.
            if model.entries.isEmpty {
                Text("Scan your Pokémon and the Collection will fill in").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("collection-empty")
            }
            if let data {
                species(data.overview)
                regions(data.overview)
                showcase(data)
                specialSets(data)
                missing(data)
                cleanUp
            } else if !model.entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task(id: key) {
            guard let gm = try? GameMaster.bundled() else { data = nil; return }
            data = CollectionData.make(entries: model.entries, advice: adviceReady, gm: gm)
        }
    }

    // MARK: species

    private func species(_ o: HubCollection.Overview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: String(o.owned)).font(.figtree(28, .heavy, relativeTo: .title)).monospacedDigit().foregroundStyle(Theme.ink)
                Text("of \(o.released) species").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
            CollectionBar(fraction: o.released == 0 ? 0 : Double(o.owned) / Double(o.released), height: 8)
            Text("\(o.percent)% of the species in Pokémon GO. \(o.canEvolve) more you can evolve now.")
                .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(o.owned) of \(o.released) species. \(o.percent)% of the species in Pokémon GO. \(o.canEvolve) more you can evolve now.")
        .accessibilityIdentifier("collection-species")
    }

    // MARK: dex by region

    @ViewBuilder private func regions(_ o: HubCollection.Overview) -> some View {
        HubHeaderLine("DEX BY REGION")
        VStack(spacing: 0) {
            ForEach(Array(o.regions.enumerated()), id: \.element.name) { i, r in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        Text("\(r.owned) of \(r.total)").font(.figtree(13, .bold, relativeTo: .footnote)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                    CollectionBar(fraction: r.total == 0 ? 0 : Double(r.owned) / Double(r.total), height: 6)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.owned) of \(r.total) \(r.name) species")
                .accessibilityIdentifier("collection-region-row")
                if i < o.regions.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
    }

    // MARK: showcase

    @ViewBuilder private func showcase(_ d: CollectionData) -> some View {
        HubHeaderLine("SHOWCASE · YOUR BEST COPIES")
        if d.showcase.isEmpty {
            Text("No copy has its IVs read yet.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(d.showcase) { ShowcaseCard(entry: $0, types: d.gm.byId[$0.row.speciesId]?.types ?? []) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .scrollClipDisabled()
            .accessibilityIdentifier("collection-showcase")
        }
    }

    // MARK: special sets

    @ViewBuilder private func specialSets(_ d: CollectionData) -> some View {
        HubHeaderLine("SPECIAL SETS")
        let per = typeSize.isAccessibilitySize ? 1 : 2
        // Rows of a Grid (not lazy), so the two tiles of a row are as tall as the taller one and every tile is in the accessibility tree.
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: d.sets.count, by: per)), id: \.self) { start in
                GridRow {
                    ForEach(d.sets[start..<min(start + per, d.sets.count)], id: \.name) { SpecialSetTile(set: $0) }
                }
            }
        }
    }

    // MARK: missing

    @ViewBuilder private func missing(_ d: CollectionData) -> some View {
        HubHeaderLine("MISSING") {
            if !d.missing.isEmpty {
                NavigationLink(value: CollectionRoute.missing) {
                    Text("All \(HubModel.grouped(d.missing.count)) ›").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink).frame(minHeight: 44)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("All \(d.missing.count) missing species")
                .accessibilityIdentifier("collection-missing-all")
            }
        }
        MissingPanel(missing: d.missing, evolvable: d.overview.canEvolve, shown: 6)
    }

    // MARK: builds and clean-up

    @ViewBuilder private var cleanUp: some View {
        HubHeaderLine("BUILDS AND CLEAN-UP")
        if let a = adviceReady {
            VStack(spacing: 10) {
                summaryCard(.builds, kicker: "BUILDS", figure: buildsText(a.builds.count), line: buildsLine(a))
                summaryCard(.gaps, kicker: "GAPS", figure: gapsFigure(a), line: gapsLine(a))
                summaryCard(.duplicates, kicker: "DUPLICATES", figure: "\(a.duplicates.count) species", line: duplicatesLine(a))
            }
        } else {
            HubAdviceGate { _ in EmptyView() }
        }
    }

    private func summaryCard(_ tab: CollectionTab, kicker: String, figure: String, line: String) -> some View {
        NavigationLink(value: CollectionRoute.lists(tab)) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kicker).font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.08 * 11).foregroundStyle(accent.ink)
                    Text(figure).font(.figtree(20, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink)
                    Text(line).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.figtree(13, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .panelShadow()
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kicker.capitalized), \(figure). \(line)")
        .accessibilityHint("Opens the \(tab.label) list")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("collection-card-\(tab.rawValue)")
    }

    private func buildsLine(_ a: BoxAdvice) -> String {
        guard !a.builds.isEmpty else { return "The advisor found nothing worth building in this box." }
        var line = ""
        if let first = HubModel.headlines(a.builds, stardust: model.stardust).doFirst { line = "Do first: \(HubModel.headline(for: first)). " }
        let dust = a.builds.reduce(0) { $0 + $1.dust }
        return line + (dust > 0 ? "\(HubModel.dustShort(dust)) dust for all of them." : "Nothing to spend in dust.")
    }

    private func gapsFigure(_ a: BoxAdvice) -> String {
        "\(a.gaps.filter { $0.tier == "S" }.count) S tier · \(a.gaps.filter { $0.tier == "A" }.count) A tier"
    }

    private func gapsLine(_ a: BoxAdvice) -> String {
        guard let top = a.gaps.first(where: { $0.tier == "S" }) else { return "Top-tier Pokémon that nothing in your box can become." }
        return "Top-tier Pokémon nothing in your box can become, such as \(top.name)."
    }

    private func duplicatesLine(_ a: BoxAdvice) -> String {
        let n = a.duplicates.reduce(0) { $0 + $1.transfer.count }
        return "\(HubModel.grouped(n)) \(n == 1 ? "copy" : "copies") you can transfer."
    }
}

// MARK: pieces

/// A progress bar: `off` track, the accent's solid colour for the share. The fill never shrinks below a dot, so a species owned reads as started.
struct CollectionBar: View {
    let fraction: Double
    var height: CGFloat = 8
    @Environment(\.accent) private var accent

    var body: some View {
        Capsule().fill(Theme.off)
            .frame(height: height)
            .overlay {
                GeometryReader { g in
                    Capsule().fill(accent.solid).frame(width: fraction > 0 ? max(height, g.size.width * min(1, fraction)) : 0)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A Showcase card: 150 pt wide (it grows with the text size), type icons, the name, the IV % (22/800, green at 100%) and the IVs with the CP. Opens the Pokémon's page.
private struct ShowcaseCard: View {
    let entry: BoxEntry
    let types: [String]
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let ivs = entry.row.ivs
        let sum = ivs.map { $0.atk + $0.def + $0.hp } ?? 0
        let percent = Int((Double(sum) / 45 * 100).rounded())
        let perfect = sum == 45
        let spokenIVs = ivs.map { "\($0.atk), \($0.def), \($0.hp) IVs," } ?? ""
        let line = "\(ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "") · CP \(HubModel.grouped(entry.row.cp))"
        NavigationLink(value: entry.id) {
            VStack(alignment: .leading, spacing: 4) {
                TypeIcons(types: types, size: 18)
                Text(entry.row.display).font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineLimit(2)
                Text("\(percent)%").font(.figtree(22, .heavy, relativeTo: .title2)).monospacedDigit().foregroundStyle(perfect ? Theme.greenInk : Theme.ink)
                Text(line).font(.figtree(12, .medium, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(width: min(150 * scale, 330), alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .panelShadow()
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.row.display), \(percent)% IVs, \(spokenIVs) CP \(HubModel.grouped(entry.row.cp)). \(types.map { $0.capitalized }.joined(separator: " and "))")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("collection-showcase-card")
    }
}

/// A special set: its name, "14 of 52" (or a plain count) and a bar when there is a total; Lucky reads "Not in your scans yet" until a copy is marked.
private struct SpecialSetTile: View {
    let set: HubCollection.SpecialSet

    var body: some View {
        let figure = set.note ?? (set.owned.map { n in set.total.map { "\(n) of \($0)" } ?? HubModel.grouped(n) } ?? "")
        VStack(alignment: .leading, spacing: 6) {
            Text(set.name).font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            if set.note != nil {
                Text(figure).font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            } else {
                Text(figure).font(.figtree(18, .heavy, relativeTo: .headline)).monospacedDigit().foregroundStyle(Theme.ink)
            }
            if let owned = set.owned, let total = set.total { CollectionBar(fraction: total == 0 ? 0 : Double(owned) / Double(total), height: 6) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .panelShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(set.note.map { "\(set.name). \($0)" } ?? "\(set.name), \(figure) \(set.unit)")
        .accessibilityIdentifier("collection-set")
    }
}

/// The missing species as a panel: the count and the evolvable count on top, then the first `shown` (all of them when nil) with the dex number, the region and how to get it.
struct MissingPanel: View {
    let missing: [HubCollection.MissingSpecies]
    let evolvable: Int
    var shown: Int? = nil

    var body: some View {
        let rows = shown.map { Array(missing.prefix($0)) } ?? missing
        // The preview is a few rows, all in the accessibility tree; the full list (hundreds) is lazy.
        let content = VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(HubModel.grouped(missing.count)) species missing").font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink)
                Text("\(evolvable) you can evolve from one you have. A species lists how to get it where our research says.")
                    .font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("collection-missing-head")
            if shown == nil {
                LazyVStack(spacing: 0) { ForEach(rows, id: \.dex) { row($0) } }
            } else {
                ForEach(rows, id: \.dex) { row($0) }
            }
        }
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .panelShadow()
    }

    private func row(_ m: HubCollection.MissingSpecies) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(m.name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                    Text("#\(m.dex) · \(m.region)").font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.faint)
                }
                if !m.how.isEmpty { Text(m.how).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("collection-missing-row")
        }
    }
}

/// All the missing species, in the Collection's order (the ones you can evolve first).
struct HubMissingView: View {
    @EnvironmentObject var model: AppModel
    @State private var data: CollectionData?

    var body: some View {
        HubTypeScreen(type: .everything, title: "Missing", sub: "Species with no copy in your box", count: data.map { "\($0.missing.count) species" }) {
            if let data { MissingPanel(missing: data.missing, evolvable: data.overview.canEvolve) }
        }
        .task(id: "\(model.account ?? "")|\(model.snapshot?.seq ?? -1)|\(model.hubAdvice != nil)") {
            guard let gm = try? GameMaster.bundled() else { data = nil; return }
            data = CollectionData.make(entries: model.entries, advice: model.hubAdvice, gm: gm)
        }
    }
}
