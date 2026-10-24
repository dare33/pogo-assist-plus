import SwiftUI
import PogoBox

/// One species' Pokémon, best IVs first, with Select mode: pick some and the bottom bar builds one game search for them
/// (design handoff v2 section 1g and the prototype's species screen).
struct SpeciesListView: View {
    let route: SpeciesRoute
    @ObservedObject var store: BoxIndexStore
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.showToast) private var showToast
    @State private var selecting = false
    @State private var choosingExport = false
    @State private var picked = Set<String>()
    @State private var deleting: DeleteTarget?
    @State private var rankingInfo = false
    /// Copies whose activity tag was tapped open: the one line it explains.
    @State private var lineOpen = Set<String>()
    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue

    private var index: BoxIndex { store.index }
    private var pogoAssist: Bool { rankingRaw == Ranking.pogoAssist.rawValue }
    /// The activity chip the list was opened under (nil under All, To check and Fixed by hand).
    private var activity: BoxInsight.Activity? { if case .activity(let a) = route.chip { return a } else { return nil } }
    private var readyAdvice: BoxAdvice? { if case .ready(let a) = model.advice { return a } else { return nil } }

    /// A copy's tag for the chip: the league's or the activity's. A copy over the cap for a league has no worth of its own and reads Weak; no tag where the copy has no rating.
    private func chipWorth(_ id: String) -> LeaguePanel.Worth? {
        guard let a = activity, let copy = store.insight?.copies[id] else { return nil }
        if let w = copy.worth(a, pogoAssist: pogoAssist) { return w }
        return a.league.flatMap { copy.slot($0, pogoAssist: pogoAssist) } != nil ? .weak : nil
    }

    /// Every copy that passes the search, best IVs first. Under an activity chip all of them stay, Strong then OK then Weak (each group still best IVs first), so the list
    /// reads as a ranking and the Weak copies are last.
    private var members: [Int] {
        let ms = index.members(of: route.title, query: route.query, chip: route.chip)
        guard activity != nil, store.insight != nil else { return ms }
        func rank(_ i: Int) -> Int { switch chipWorth(index.items[i].id) { case .strong?: return 0; case .ok?: return 1; default: return 2 } }
        return ms.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    var body: some View {
        let ms = members
        let ids = ms.map { index.items[$0].id }
        VStack(spacing: 0) {
            header(count: ms.count, ids: ids)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                    sortLine
                    rows(ms)
                    Text("Tags mark the copy that is your best for a league, raid, gym, Rocket or Max use, under the scoring chosen above.")
                        .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6)
                        .accessibilityIdentifier("tags-note")
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .animation(nil, value: selecting)
        }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting, !picked.isEmpty { selectBar(ms) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .confirmDelete($deleting)
        .onChange(of: ms.isEmpty) { _, empty in if empty { dismiss() } }
    }

    // MARK: header

    @ViewBuilder private func header(count: Int, ids: [String]) -> some View {
        HStack(spacing: 8) {
            if selecting {
                HeaderTextButton(title: "Cancel") { selecting = false; picked = [] }
                Text("\(picked.count) selected").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                HeaderTextButton(title: picked.count == count ? "None" : "All \(count.formatted())") { picked = picked.count == count ? [] : Set(ids) }
            } else {
                IconButton(systemImage: "chevron.left", kind: .floating, label: "Back") { dismiss() }
                Text("\(route.title) · \(count.formatted())").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                    .lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                HeaderTextButton(title: "Select") { selecting = true }
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .frame(minHeight: 52)
    }

    // MARK: order and scoring

    /// "Best IVs first" on the left, the ranking switch and its "i" on the right, the explainer under them. The tags and the order follow the switch.
    private var sortLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { order; Spacer(minLength: 8); RankingSwitch(infoOpen: $rankingInfo, identifier: "species-scoring") }
                VStack(alignment: .leading, spacing: 0) { order; RankingSwitch(infoOpen: $rankingInfo, identifier: "species-scoring") }
            }
            if rankingInfo { RankingExplainer(identifier: "species-scoring-explainer").transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.15), value: rankingInfo)
        .padding(.horizontal, 6)
    }

    private var order: some View {
        Label(activity.map { "Best for \($0.title) first" } ?? "Best IVs first", systemImage: "arrow.down").labelStyle(.titleAndIcon)
            .font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink)
            .frame(minHeight: 44, alignment: .leading)
            .accessibilityIdentifier("species-order")
    }

    // MARK: tags

    /// One tag a copy carries, with the words VoiceOver reads for it.
    private struct TagItem: Identifiable {
        enum Kind { case league(String, BoxInsight.Activity, String, String), activity(BoxInsight.Activity, String?) }
        var id: String
        var kind: Kind
    }

    /// The copy's tags: a league tag for each league it is the species' best for (the tile's copy), and an activity tag for each area the advisor rates it
    /// the species' best for. Both follow the ranking where it matters (the leagues).
    private func bestTags(_ it: BoxIndex.Item) -> [TagItem] {
        var out = [TagItem]()
        if let insight = store.insight, let copy = insight.copies[it.id] {
            for key in LeaguePanel.keys {
                guard insight.tile(title: route.title, league: key, pogoAssist: pogoAssist)?.copyId == it.id, let slot = copy.slot(key, pogoAssist: pogoAssist), slot.status == .fits,
                      let a = BoxInsight.Activity(rawValue: key) else { continue }
                out.append(TagItem(id: "\(it.id)|\(key)", kind: .league(key, a, slot.member, slot.pct.map(LeaguePanel.percent) ?? "")))
            }
        }
        if let advice = readyAdvice {
            for area in advice.bestOf(for: it.id) {
                guard let a = BoxInsight.Activity(rawValue: area) else { continue }
                out.append(TagItem(id: "\(it.id)|\(area)", kind: .activity(a, area == "max" ? nil : advice.fit(for: it.id)[area]?.asName)))
            }
        }
        return out
    }

    private func words(_ t: TagItem) -> String {
        switch t.kind {
        case .league(let key, _, let member, let pct): return "Best for \(LeaguePanel.name(key)): \(member) \(pct.dropLast()) percent"
        case .activity(let a, let name): return "Best for \(a.title)" + (a == .max ? ", needs a Dynamax copy" : name.map { " as \($0)" } ?? "")
        }
    }

    @ViewBuilder private func tagView(_ t: TagItem) -> some View {
        switch t.kind {
        case .league(let key, let a, let member, let pct):
            let league = League(rawValue: key) ?? .gl
            SoftTag(label: a.tagLabel, detail: "\(member) \(pct)", ink: league.ink, tint: league.tint)
        case .activity(let a, let name):
            SoftTag(label: a.tagLabel, detail: a == .max ? "needs a Dynamax copy" : name.map { "as \($0)" }, ink: a.ink(accent), tint: a.tint(accent))
        }
    }

    /// The sentence a tap on the chip's tag opens: the activity's `fit` line, or the league card's tier-and-roll sentence.
    private func tagLine(_ it: BoxIndex.Item, _ a: BoxInsight.Activity) -> String? {
        guard let advice = readyAdvice else { return nil }
        if let area = a.area { return advice.fit(for: it.id)[area]?.line }
        guard let key = a.league, let r = advice.leagues(for: it.id)[key] else { return nil }
        let c = LeaguePanel.card(r, shown: LeaguePanel.shownIndex(r, pogoAssist: pogoAssist), key: key, level: nil)
        return LeaguePanel.worthSentence(c, key: key) ?? c.blockedText
    }

    /// The Strong / OK / Weak tag for the chosen activity, a button that opens its line (plain while Select mode is on, when a tap picks the row).
    @ViewBuilder private func statusTag(_ it: BoxIndex.Item, _ a: BoxInsight.Activity, _ w: LeaguePanel.Worth) -> some View {
        if selecting {
            WorthTag(activity: a, worth: w).accessibilityHidden(true)
        } else {
            Button { if lineOpen.contains(it.id) { lineOpen.remove(it.id) } else { lineOpen.insert(it.id) } } label: {
                WorthTag(activity: a, worth: w).padding(.vertical, 8).contentShape(Rectangle()).padding(.vertical, -8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(w.label) for \(a.title)")
            .accessibilityHint("Shows why")
            .accessibilityValue(lineOpen.contains(it.id) ? (tagLine(it, a) ?? "") : "")
            .accessibilityAddTraits(lineOpen.contains(it.id) ? .isSelected : [])
            .accessibilityIdentifier("pokemon-tag")
        }
    }

    // MARK: rows

    private func rows(_ ms: [Int]) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        return LazyVStack(spacing: 0) {
            ForEach(Array(ms.enumerated()), id: \.element) { n, i in
                let it = index.items[i]
                Group {
                    if selecting {
                        Button { toggle(it.id) } label: { row(it, last: n == ms.count - 1) }.buttonStyle(PressStyle())
                            .accessibilityAddTraits(picked.contains(it.id) ? .isSelected : [])
                    } else {
                        NavigationLink(value: it.id) { row(it, last: n == ms.count - 1) }.buttonStyle(PressStyle())
                            .contextMenu { Button(role: .destructive) { deleting = DeleteTarget(id: it.id, title: it.title, cp: it.cp) } label: { Label("Delete from box", systemImage: "trash") } }
                    }
                }
                .accessibilityIdentifier("pokemon-row")
            }
        }
        .background(Theme.surface, in: shape)
        .clipShape(shape)
        .panelShadow()
    }

    private func toggle(_ id: String) { if picked.contains(id) { picked.remove(id) } else { picked.insert(id) } }

    private func row(_ it: BoxIndex.Item, last: Bool) -> some View {
        let on = selecting && picked.contains(it.id)
        let ivs = it.ivs.map { "\($0) · \(it.pct ?? 0)%" } ?? "IVs not read"
        let best = bestTags(it)
        let status = activity.flatMap { a in chipWorth(it.id).map { (a, $0) } }
        var spoken = "\(it.title), \(it.cp > 0 ? "CP \(it.cp)" : "CP not known"), \(ivs)\(it.hasMega ? ", has a Mega form" : "")\(it.needsCheck ? ", to check" : "")\(it.fixed ? ", fixed by hand" : "")"
        if !best.isEmpty { spoken += ". " + best.map(words).joined(separator: ". ") }
        return HStack(alignment: .top, spacing: 12) {
            if selecting {
                Image(systemName: "checkmark").font(.figtree(13, .bold)).foregroundStyle(on ? accent.onSolid : .clear)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(on ? accent.solid : .clear))
                    .overlay(Circle().strokeBorder(on ? .clear : Theme.line, lineWidth: 2))
                    .accessibilityHidden(true)
                    .padding(.top, 2)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        if it.hasMega {
                            // The tag beside the name when it fits on one line, under it at large text sizes (a name is never broken to make room).
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) { Text(it.title).paText(.rowTitle).foregroundStyle(Theme.ink).fixedSize(horizontal: true, vertical: false); MegaMarker() }
                                VStack(alignment: .leading, spacing: 4) { Text(it.title).paText(.rowTitle).foregroundStyle(Theme.ink); MegaMarker() }
                            }
                        } else { Text(it.title).paText(.rowTitle).foregroundStyle(Theme.ink) }
                        Text("\(ivs)\(Text(it.needsCheck ? " · To check" : "").fontWeight(.bold).foregroundStyle(Theme.orangeInk))\(it.fixed ? " · Fixed by hand" : "")")
                            .font(.figtree(13, .regular, relativeTo: .footnote)).foregroundStyle(Theme.muted).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CPFigure(cp: it.cp)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                if status != nil || !best.isEmpty {
                    FlowLayout(spacing: 6) {
                        if let (a, w) = status { statusTag(it, a, w) }
                        ForEach(best) { tagView($0).accessibilityHidden(true) }
                    }
                    if let (a, _) = status, lineOpen.contains(it.id), !selecting, let line = tagLine(it, a) {
                        Text(line).font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.muted).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("pokemon-tag-line")
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(on ? accent.tint : .clear)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, selecting ? 54 : 16) } }
    }

    // MARK: select bar

    private func selectBar(_ ms: [Int]) -> some View {
        let order = ms.filter { picked.contains(index.items[$0].id) }
        let search = index.gameSearch(picked: order)
        return VStack(alignment: .leading, spacing: 10) {
            if let text = search.text {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.figtree(16, .bold)).foregroundStyle(Theme.orangeInk).accessibilityHidden(true)
                    Text(text).font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.orangeInk)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
                .background(Theme.orangeTint, in: RoundedRectangle(cornerRadius: Theme.Radius.insetRow, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Search to paste into the game")
                .accessibilityValue(text)
            }
            if search.extra > 0 {
                Text("\(search.extra.formatted()) other Pokémon in your box also \(search.extra == 1 ? "matches" : "match") this search.")
                    .font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.orangeInk)
            }
            if search.notCovered > 0 {
                Text("\(search.notCovered.formatted()) of the picked \(search.notCovered == 1 ? "has" : "have") no CP or HP to search for, so this search leaves \(search.notCovered == 1 ? "it" : "them") out.")
                    .font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.orangeInk)
            }
            HStack(spacing: 8) {
                if let text = search.text {
                    PillButton("Copy search (\(search.covered.formatted()))", systemImage: "doc.on.doc", style: .filled, height: 52) {
                        UIPasteboard.general.string = text
                        showToast("Copied")
                    }
                }
                PillButton("Export", systemImage: "square.and.arrow.up", style: .tint, height: 52, fullWidth: false) { choosingExport = true }
                    .exportChoice(isPresented: $choosingExport) { format in
                        let ids = Set(order.map { index.items[$0].id })
                        Task { await model.export(format, only: ids) }
                    }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255).opacity(0.14), radius: 12, x: 0, y: -4)
        .padding(.horizontal, 8).padding(.bottom, 8)
    }
}
