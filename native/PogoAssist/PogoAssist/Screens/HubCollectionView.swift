import SwiftUI
import PogoBox
import PogoReader

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
    var sets: [HubCollection.SpecialSet]
    /// Each set's strip: its best Pokémon for its activity first (`HubCollection.strip`). Empty for a set with no Pokémon and for one that is coming soon.
    var strips: [HubCollection.SetKind: [HubCollection.StripPick]]
    /// Evolvable first, then dex order: the order of the full Missing list.
    var missing: [HubCollection.MissingSpecies]
    var missingSummary: HubCollection.MissingSummary
    var gm: GameMaster

    static func make(entries: [BoxEntry], advice: BoxAdvice?, gm: GameMaster, pogoAssist: Bool = false) -> CollectionData {
        let missing = HubCollection.missingSpecies(entries: entries, advice: advice ?? BoxAdvice(), gm: gm)
        // One pass over the box for every set's copies (the card's count and the strip read the same `Membership`).
        let membership = HubCollection.Membership(entries: entries, gm: gm)
        var members = [HubCollection.SetKind: [BoxEntry]]()
        for e in entries { for k in membership.kinds(of: e) { members[k, default: []].append(e) } }
        let strips = Dictionary(uniqueKeysWithValues: HubCollection.SetKind.allCases.map { k in
            (k, HubCollection.strip(kind: k, members: members[k] ?? [], gm: gm, advice: advice ?? BoxAdvice(), pogoAssist: pogoAssist))
        })
        return CollectionData(overview: HubCollection.overview(entries: entries, gm: gm),
                              sets: HubCollection.specialSets(entries: entries, gm: gm, isLucky: HubCollection.isLuckyMarked),
                              strips: strips,
                              missing: missing.filter { $0.evolvesFrom != nil } + missing.filter { $0.evolvesFrom == nil },
                              missingSummary: HubCollection.missingSummary(missing),
                              gm: gm)
    }
}

/// The Collection screen (pass 2 README "Collection", boards `Collection.dc.html`): the species count, the dex by region, the special sets (a strip of copy cards each, best
/// first, with "All N ›" opening the set's list), the missing species as one summary card and three summary cards that open the lists screen. Replaces the Everything screen.
struct HubCollectionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var data: CollectionData?
    /// The Special sets card whose list is open.
    /// Kept whole (not looked up in `data` while the sheet is up): an edit made from the sheet rebuilds `data`, and the sheet must stay on screen meanwhile.
    @State private var openSet: OpenSet?
    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue
    private struct OpenSet: Identifiable { var kind: HubCollection.SetKind; var set: HubCollection.SpecialSet; var id: String { kind.id } }

    private var adviceReady: BoxAdvice? { model.hubAdvice }
    /// The box, the account and whether the advice is in (the Missing "how to get" reads the advice's gaps).
    private var key: String { "\(model.account ?? "")|\(model.snapshot?.seq ?? -1)|\(adviceReady != nil)|\(rankingRaw)" }

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
                specialSets(data)
                missing(data)
                // With an empty box the one scan prompt is the line at the top, so the summary cards (which would repeat it) wait for a box.
                if !model.entries.isEmpty { cleanUp }
            } else if !model.entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .sheet(item: $openSet) { open in
            CollectionSetSheet(kind: open.kind, set: open.set).environmentObject(model).environment(\.accent, accent)
        }
        .task(id: key) {
            guard let gm = try? GameMaster.bundled() else { data = nil; return }
            data = CollectionData.make(entries: model.entries, advice: adviceReady, gm: gm, pogoAssist: rankingRaw == Ranking.pogoAssist.rawValue)
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

    // MARK: special sets

    /// Each set is a strip of copy cards laid out as the Showcase was (Greg, 31 Oct 2026): a title line with the count and "All N ›" (the set's full list, the sheet),
    /// then the cards, the set's best Pokémon for its activity first.
    @ViewBuilder private func specialSets(_ d: CollectionData) -> some View {
        HubHeaderLine("SPECIAL SETS")
        VStack(alignment: .leading, spacing: 18) {
            ForEach(d.sets, id: \.name) { s in
                if let kind = HubCollection.SetKind(rawValue: s.name) {
                    SpecialSetStrip(info: s, kind: kind, picks: d.strips[kind] ?? [], gm: d.gm) { openSet = OpenSet(kind: kind, set: s) }
                }
            }
        }
    }

    // MARK: missing

    /// One summary card (Greg, 31 Oct 2026): the count and a short breakdown; it opens the full list.
    @ViewBuilder private func missing(_ d: CollectionData) -> some View {
        HubHeaderLine("MISSING")
        let m = d.missingSummary
        if m.count == 0 {
            Text("You have every species released in Pokémon GO.").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .panelShadow()
                .accessibilityIdentifier("collection-missing-card")
        } else {
            let line = m.parts.joined(separator: " · ")
            NavigationLink(value: CollectionRoute.missing) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(HubModel.grouped(m.count)) species").font(.figtree(20, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink)
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
            .accessibilityLabel("\(m.count) species missing. \(m.parts.joined(separator: ", "))")
            .accessibilityHint("Opens the list of missing species")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("collection-missing-card")
        }
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
        return "\(HubModel.grouped(n)) \(n == 1 ? "copy" : "copies") you can transfer or trade."
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

/// One special set: its title line, then its strip of copy cards. The title line reads the count as the card did ("14 of 52 species", "6 copies"), with "All N ›" when the set
/// has Pokémon, a button that opens the set's full list (`CollectionSetSheet`). Shiny and Background show one "Coming soon" card; a set with no Pokémon says so.
private struct SpecialSetStrip: View {
    let info: HubCollection.SpecialSet
    let kind: HubCollection.SetKind
    let picks: [HubCollection.StripPick]
    let gm: GameMaster
    let open: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The identifier suffix: the set's name as a word, lower case with hyphens ("ultra-beasts").
    private var slug: String { kind.name.lowercased().replacingOccurrences(of: " ", with: "-") }
    private var figure: String { info.note ?? (info.owned.map { n in info.total.map { "\(n) of \($0)" } ?? HubModel.grouped(n) } ?? "") }
    /// "All 14 ›": the species or copies the card counts.
    private var allCount: Int { info.owned ?? 0 }
    private var hasList: Bool { !kind.isComingSoon && allCount > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // At the accessibility text sizes the title, the count and "All N ›" stack, so no word has to break to fit one line.
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) { titleText; countText; allButton }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { titleText; countText; Spacer(minLength: 8); allButton }
                }
            }
            .accessibilityElement(children: .contain)
            if kind.isComingSoon {
                strip { SetCard(title: nil, headline: "Coming soon", line: "Not scanned yet", rank: nil, types: [], id: "collection-set-coming-soon-\(slug)", entryId: nil, setName: info.name) }
            } else if picks.isEmpty {
                Text(info.note ?? "No Pokémon in this set yet.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("collection-set-empty-\(slug)")
            } else {
                strip {
                    ForEach(picks, id: \.entry.id) { p in
                        SetCard(title: p.entry.row.display, ivs: p.entry.row.ivs, cp: p.entry.row.cp, rank: p.rank.level == 0 ? nil : p.rank.words,
                                types: gm.byId[p.entry.row.speciesId]?.types ?? [], id: "collection-strip-card", entryId: p.entry.id)
                    }
                }
                .accessibilityIdentifier("collection-strip-\(slug)")
            }
        }
    }

    private var titleText: some View {
        Text(info.name).font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
    }

    private var countText: some View {
        Text(info.note == nil ? "\(figure) \(info.unitWord)" : (kind.isComingSoon ? figure : "")).font(.figtree(13, .semibold, relativeTo: .footnote)).monospacedDigit().foregroundStyle(Theme.muted)
    }

    /// "All 14 ›". Spoken as shown ("All 14") so Voice Control's "tap All 14" works, then the set it opens; "All Legendary" works too.
    @ViewBuilder private var allButton: some View {
        if hasList {
            let n = HubModel.grouped(allCount)
            Button(action: open) {
                Text("All \(n) ›").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink).frame(minHeight: 44)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("All \(n), \(info.name), \(figure) \(info.unitWord)")
            .accessibilityInputLabels(["All \(n)", "All \(info.name)", "All \(n) \(info.name)"])
            .accessibilityHint("Opens the full list")
            .accessibilityIdentifier("collection-set-\(slug)")
        }
    }

    private func strip<Content: View>(@ViewBuilder _ cards: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) { cards() }
                .fixedSize(horizontal: false, vertical: true)
        }
        .scrollClipDisabled()
    }
}

/// A card of a set's strip, laid out as the Showcase card was: 150 pt wide (it grows with the text size), type icons, the name, the IV % (22/800, green at 100%), the IVs with the
/// CP, and the rank the strip was ordered by ("Raids S"). Opens the Pokémon's page. With no entry it is the "Coming soon" card of Shiny and Background (not a button).
private struct SetCard: View {
    var title: String?
    var headline: String?
    var line: String?
    var ivs: IVs?
    var cp: Int?
    var rank: String?
    let types: [String]
    let id: String
    let entryId: String?
    /// The set a "Coming soon" card stands for, so its spoken label names it.
    var setName: String?
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    init(title: String?, headline: String? = nil, line: String? = nil, ivs: IVs? = nil, cp: Int? = nil, rank: String?, types: [String], id: String, entryId: String?, setName: String? = nil) {
        self.title = title; self.headline = headline; self.line = line; self.ivs = ivs; self.cp = cp; self.rank = rank; self.types = types; self.id = id; self.entryId = entryId; self.setName = setName
    }

    private var sum: Int? { ivs.map { $0.atk + $0.def + $0.hp } }
    private var percent: String { sum.map { "\(Int((Double($0) / 45 * 100).rounded()))%" } ?? "IVs?" }
    private var detail: String {
        let iv = ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" }
        let cpText = cp.map { "CP \(HubModel.grouped($0))" }
        return line ?? [iv, cpText].compactMap { $0 }.joined(separator: " · ")
    }
    private var spoken: String {
        guard let title else { return "Coming soon" }
        let iv = ivs.map { "\(percent) IVs, \($0.atk), \($0.def), \($0.hp) IVs," } ?? "IVs not read,"
        return "\(title), \(iv) \(cp.map { "CP \(HubModel.grouped($0))" } ?? ""). " + (rank.map { "\($0). " } ?? "") + types.map { $0.capitalized }.joined(separator: " and ")
    }

    var body: some View {
        if let entryId {
            NavigationLink(value: entryId) { card }
                .buttonStyle(PressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(id)
        } else {
            card
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(setName.map { $0 + ", " } ?? "")\(headline?.lowercased() ?? ""). \(line ?? "")")
                .accessibilityIdentifier(id)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !types.isEmpty { TypeIcons(types: types, size: 18) }
            if let title { Text(title).font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineLimit(2) }
            if let headline {
                Text(headline).font(.figtree(18, .heavy, relativeTo: .headline)).foregroundStyle(Theme.muted)
            } else {
                Text(percent).font(.figtree(22, .heavy, relativeTo: .title2)).monospacedDigit().foregroundStyle(sum == 45 ? Theme.greenInk : Theme.ink)
            }
            Text(detail).font(.figtree(12, .medium, relativeTo: .caption)).foregroundStyle(Theme.muted)
            if let rank { Text(rank).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: min(150 * scale, 330), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .panelShadow()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// The missing species as a panel: the count and the evolvable count on top, then the first `shown` (all of them when nil) with the dex number, the region and how to get it.
struct MissingPanel: View {
    let missing: [HubCollection.MissingSpecies]
    let evolvable: Int
    var shown: Int? = nil

    var body: some View {
        if missing.isEmpty {
            Text("You have every species released in Pokémon GO.").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .panelShadow()
                .accessibilityIdentifier("collection-missing-head")
        } else {
            list
        }
    }

    @ViewBuilder private var list: some View {
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
