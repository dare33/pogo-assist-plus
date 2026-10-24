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
    @Environment(\.dynamicTypeSize) private var typeSize
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
    /// The tags, tiles, lines and best-of areas all come from the insight, which holds them itself: a rebuild of the advice for the same account (a hand fix) leaves the
    /// insight on show, and the tags and their lines with it, so nothing here reads the advice.
    private var insight: BoxInsight? { store.insight(forAccount: model.account) }

    /// A copy's tag for the chip: the league's or the activity's. A copy over the cap for a league has no worth of its own and reads Weak; no tag where the copy has no rating.
    private func chipWorth(_ id: String) -> LeaguePanel.Worth? {
        guard let a = activity, let copy = insight?.copies[id] else { return nil }
        if let w = copy.worth(a, pogoAssist: pogoAssist) { return w }
        return a.league.flatMap { copy.slot($0, pogoAssist: pogoAssist) } != nil ? .weak : nil
    }

    /// Every copy that passes the search, best IVs first. Under an activity chip all of them stay, Strong then OK then Weak (each group still best IVs first), so the list
    /// reads as a ranking and the Weak copies are last.
    private var members: [Int] {
        let ms = index.members(of: route.title, query: route.query, chip: route.chip)
        guard activity != nil, insight != nil else { return ms }
        func rank(_ i: Int) -> Int { switch chipWorth(index.items[i].id) { case .strong?: return 0; case .ok?: return 1; default: return 2 } }
        return ms.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// "Moltres · 6", or under an activity or league chip with its advice "Moltres · 3 of 6 for Raids": the copies that are Strong or OK for it, of those listed. Both
    /// numbers count the listed copies, so with a search on, the 6 is what the search keeps, not what the box holds.
    private func headerTitle(_ ms: [Int]) -> String {
        guard let a = activity, insight != nil else { return "\(route.title) · \(ms.count.formatted())" }
        let suit = ms.filter { chipWorth(index.items[$0].id).map { $0 == .strong || $0 == .ok } ?? false }.count
        return "\(route.title) · \(suit.formatted()) of \(ms.count.formatted()) for \(a.league != nil ? a.title + " League" : a.title)"
    }

    var body: some View {
        let ms = members
        let ids = ms.map { index.items[$0].id }
        VStack(spacing: 0) {
            header(count: ms.count, title: headerTitle(ms), ids: ids)
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

    @ViewBuilder private func header(count: Int, title: String, ids: [String]) -> some View {
        HStack(spacing: 8) {
            if selecting {
                HeaderTextButton(title: "Cancel") { selecting = false; picked = [] }
                Text("\(picked.count) selected").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                HeaderTextButton(title: picked.count == count ? "None" : "All \(count.formatted())") { picked = picked.count == count ? [] : Set(ids) }
            } else {
                IconButton(systemImage: "chevron.left", kind: .floating, label: "Back") { dismiss() }
                Text(title).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
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
            // Chosen by the width that is there, at every text size: the label and the captioned switch on one line; else the label and the switch without its RANKING caption;
            // else stacked. The label never shrinks or truncates.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { order; Spacer(minLength: 4); RankingSwitch(infoOpen: $rankingInfo, identifier: "species-scoring") }
                HStack(spacing: 8) { order; Spacer(minLength: 4); RankingSwitch(infoOpen: $rankingInfo, identifier: "species-scoring", showsCaption: false) }
                VStack(alignment: .leading, spacing: 0) { order; RankingSwitch(infoOpen: $rankingInfo, identifier: "species-scoring") }
            }
            if rankingInfo { RankingExplainer(identifier: "species-scoring-explainer").transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.15), value: rankingInfo)
        .padding(.horizontal, 6)
    }

    private var order: some View {
        Label(activity.flatMap { a in insight == nil ? nil : "\(a.league != nil ? a.title + " League" : a.title) first" } ?? "Best IVs first", systemImage: "arrow.down").labelStyle(.titleAndIcon)
            .font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink)
            .frame(minHeight: 44, alignment: .leading)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
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
    /// the species' best for. Both follow the ranking where it matters (the leagues). Read from the insight alone.
    private func bestTags(_ it: BoxIndex.Item) -> [TagItem] {
        var out = [TagItem]()
        guard let insight, let copy = insight.copies[it.id] else { return out }
        for key in LeaguePanel.keys {
            guard insight.tile(title: route.title, league: key, pogoAssist: pogoAssist)?.copyId == it.id, let slot = copy.slot(key, pogoAssist: pogoAssist), slot.status == .fits,
                  let a = BoxInsight.Activity(rawValue: key) else { continue }
            out.append(TagItem(id: "\(it.id)|\(key)", kind: .league(key, a, slot.member, slot.pct.map(LeaguePanel.percent) ?? "")))
        }
        for b in copy.best {
            guard let a = BoxInsight.Activity(rawValue: b.area) else { continue }
            out.append(TagItem(id: "\(it.id)|\(b.area)", kind: .activity(a, b.asName)))
        }
        return out
    }

    /// The activity a tag is for (a league tag's is the league's chip).
    private func area(_ t: TagItem) -> BoxInsight.Activity {
        switch t.kind { case .league(_, let a, _, _), .activity(let a, _): return a }
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

    /// The sentence a tap on the chip's tag opens: the activity's `fit` line, or the league card's tier-and-roll sentence, both kept in the insight.
    private func tagLine(_ it: BoxIndex.Item, _ a: BoxInsight.Activity) -> String? {
        insight?.copies[it.id]?.line(a, pogoAssist: pogoAssist)
    }

    /// The Strong / OK / Weak tag for the chosen activity, a button that opens its line (plain while Select mode is on, when a tap picks the row). `best` is the
    /// merged "best as Tyranitar (Shadow)" when the copy is also the species' best for the same area. "Not rated" has no line to open, so it is plain text, not a button.
    @ViewBuilder private func statusTag(_ it: BoxIndex.Item, _ a: BoxInsight.Activity, _ w: LeaguePanel.Worth?, best: String?) -> some View {
        let spokenBest = best.map { ", " + $0 } ?? ""
        if selecting {
            WorthTag(activity: a, worth: w, best: best).accessibilityHidden(true)
        } else if w == nil {
            WorthTag(activity: a, worth: w, best: best)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Not rated for \(a.title)" + spokenBest)
                .accessibilityIdentifier("pokemon-tag-unrated")
        } else {
            Button { if lineOpen.contains(it.id) { lineOpen.remove(it.id) } else { lineOpen.insert(it.id) } } label: {
                // The hit area grows by 6 pt above and below the chip (half the 12 pt gap between rows, so it never reaches the neighbour's chip or the IVs line):
                // padded out, shaped, then padded back so the layout does not change. The chip is about 20 pt tall, so a tap lands within about 32 pt.
                WorthTag(activity: a, worth: w, best: best).padding(.vertical, 6).contentShape(Rectangle()).padding(.vertical, -6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(w?.label ?? "Not rated") for \(a.title)" + spokenBest)
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
        // Under a chip with its advice every copy has a status tag (Strong, OK, Weak or Not rated). A "best for" tag for the same area is merged into it.
        let status: (BoxInsight.Activity, LeaguePanel.Worth?)? = insight == nil ? nil : activity.map { ($0, chipWorth(it.id)) }
        let shown = best.filter { t in status.map { area(t) != $0.0 } ?? true }
        // The status tag and a "best for" tag of the same area are one chip: "RAIDS · OK · best as Tyranitar (Shadow)", "GL · Strong · best: Flareon 97.2%".
        let mergedBest: String? = status.flatMap { insight?.bestText(of: it.id, title: route.title, $0.0, pogoAssist: pogoAssist) }
        var spoken = "\(it.title), \(it.cp > 0 ? "CP \(it.cp)" : "CP not known"), \(ivs)\(it.hasMega ? ", has a Mega form" : "")\(it.needsCheck ? ", to check" : "")\(it.fixed ? ", fixed by hand" : "")"
        // Select mode hides the tags from VoiceOver as separate elements, so the status is read with the row.
        if selecting, let (a, w) = status { spoken += ". \(w?.label ?? "Not rated") for \(a.title)" }
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
                        if let (a, w) = status { statusTag(it, a, w, best: mergedBest) }
                        ForEach(shown) { tagView($0).accessibilityHidden(true) }
                    }
                    if let (a, w) = status, w != nil, lineOpen.contains(it.id), !selecting, let line = tagLine(it, a) {
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
