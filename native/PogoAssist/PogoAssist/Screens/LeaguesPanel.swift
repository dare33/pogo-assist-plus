import SwiftUI
import PogoBox

/// The Pokémon page's LEAGUES panel (design handoff of 22 Oct 2026, section 3): one pick card per league, and the league view
/// the card opens in the same panel (the league's card, the other family members as a list). All sentences and figures come from
/// `LeaguePanel` (PogoBox), which `swift test` pins; this file lays them out. State is per page: the open league, which lists
/// are shown, which option row is open, and whether the ranking explainer is open.
struct LeaguesPanel: View {
    let ratings: [String: BoxAdvice.LeagueRating]
    /// The Pokémon's own level; nil when not known.
    let level: Double?
    /// "Pogo Assist is currently unable to detect Shadow Pokémon." while this copy's Shadow status is unknown.
    let showsShadowNote: Bool

    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accent) private var accent
    /// nil is the base state (one card per league); otherwise the league the view shows. Owned by the Pokémon page, which drops its
    /// Advice panel while a league view is open.
    @Binding var mode: String?
    /// Leagues whose option list was collapsed with "Show less": the list is open by default in the league view.
    @State private var collapsed: Set<String> = []
    @State private var expanded: [String: String] = [:]
    @State private var infoOpen = false

    private var pogoAssist: Bool { rankingRaw == Ranking.pogoAssist.rawValue }
    private var oneColumn: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        Panel(padding: 18, spacing: 14) {
            header
            if infoOpen { RankingExplainer(identifier: "leagues-scoring-explainer").transition(.opacity) }
            if let key = mode, let r = ratings[key] {
                leagueView(key, r).transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(LeaguePanel.keys, id: \.self) { key in
                        if let r = ratings[key] { block(key, r) }
                    }
                }
                .transition(.opacity)
            }
            if showsShadowNote {
                Text("Pogo Assist is currently unable to detect Shadow Pokémon.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("leagues-shadow-note")
            }
        }
        .animation(.easeOut(duration: 0.2), value: mode)
        .animation(.easeOut(duration: 0.2), value: infoOpen)
    }

    // MARK: header

    /// LEAGUES (with the back circle in the league view) and the ranking switch: one row, or from the sizes where the switch no longer
    /// fits beside the label, the label above the switch.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { title; Spacer(minLength: 8); rankingSwitch }
            VStack(alignment: .leading, spacing: 4) { title; rankingSwitch }
        }
        .frame(minHeight: 30)
    }

    private var rankingSwitch: some View { RankingSwitch(infoOpen: $infoOpen, identifier: "leagues-scoring", showsCaption: false) }

    private var title: some View {
        HStack(spacing: 8) {
            if mode != nil {
                Button { mode = nil } label: {
                    Image(systemName: "chevron.left").font(.figtree(13, .heavy)).foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 30).background(Circle().fill(Theme.surface2))
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, -8).padding(.trailing, -6)
                .accessibilityLabel("All leagues")
                .accessibilityIdentifier("leagues-back")
            }
            Text("LEAGUES").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.muted).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("leagues-panel")
        }
    }

    // MARK: base state

    private func block(_ key: String, _ r: BoxAdvice.LeagueRating) -> some View {
        let league = League(rawValue: key) ?? .gl
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(league.dot).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(LeaguePanel.name(key)).font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(league.ink)
                Spacer(minLength: 8)
                Text(LeaguePanel.capText(key)).font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(league.ink)
            }
            .accessibilityHidden(true)
            Button { mode = key } label: { pickCard(key, r, tappable: true) }
                .buttonStyle(PressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(key, r))
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("league-\(key)-pick")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("league-\(key)")
    }

    private func card(_ key: String, _ r: BoxAdvice.LeagueRating) -> LeaguePanel.Card {
        LeaguePanel.card(r, shown: LeaguePanel.shownIndex(r, pogoAssist: pogoAssist), key: key, level: level)
    }

    private func spoken(_ key: String, _ r: BoxAdvice.LeagueRating) -> String {
        LeaguePanel.spoken(card(key, r), key: key, chip: LeaguePanel.chipText(pogoAssist: pogoAssist))
    }

    // MARK: the pick card

    private func pickCard(_ key: String, _ r: BoxAdvice.LeagueRating, tappable: Bool) -> some View {
        let c = card(key, r)
        return VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                Text(c.title).font(.figtree(19, .heavy, relativeTo: .title3)).tracking(-0.01 * 19).foregroundStyle(Theme.ink)
                Text(LeaguePanel.chipText(pogoAssist: pogoAssist).uppercased()).font(.figtree(12, .bold, relativeTo: .caption)).tracking(0.07 * 12)
                    .foregroundStyle(accent.ink).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accent.tint, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                if c.overCapCount > 0 {
                    Text("▲ \(c.overCapCount) over cap").font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.04 * 11)
                        .foregroundStyle(Theme.red).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.redTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.trailing, tappable ? 22 : 0)
            if let note = c.bestAvailableNote {
                Text(note).font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            if c.status == .noViable {
                Text("No viable option").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.red)
                if let b = c.blockedText { Text(b).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true) }
            } else {
                figures(c)
                if !c.costItems.isEmpty { costList(c.costItems) }
                if let n = c.costNote {
                    Text(n).font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let n = c.notWorthText {
                Text(n).font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("league-\(key)-not-worth")
            }
            if !c.moves.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(c.moves.enumerated()), id: \.offset) { _, m in
                        Text(m.text).font(.figtree(12, .bold, relativeTo: .caption)).monospacedDigit()
                            .foregroundStyle(m.missing ? Theme.orangeInk : Theme.muted).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(m.missing ? Theme.orangeTint : Theme.off, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.insetRow, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if tappable { Image(systemName: "chevron.right").font(.figtree(13, .heavy)).foregroundStyle(Theme.faint).padding(.top, 20).padding(.trailing, 16).accessibilityHidden(true) }
        }
    }

    /// SPECIES and THIS COPY: two columns, one from the first accessibility text size.
    private func figures(_ c: LeaguePanel.Card) -> some View {
        let species = figure("Species", c.scoreText, c.rankText, strong: c.scoreStrong, dim: c.scoreText == "—")
        let copy = figure("This copy", c.ivText, c.ivRankText, strong: c.ivStrong, dim: c.ivText == "—")
        return Group {
            if oneColumn { VStack(alignment: .leading, spacing: 8) { species; copy } }
            else { HStack(alignment: .top, spacing: 8) { species.frame(maxWidth: .infinity, alignment: .leading); copy.frame(maxWidth: .infinity, alignment: .leading) } }
        }
    }

    private func figure(_ label: String, _ value: String, _ sub: String, strong: Bool, dim: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.figtree(11, .bold, relativeTo: .caption2)).tracking(0.06 * 11).foregroundStyle(Theme.muted)
            Text(value).font(.figtree(17, .heavy, relativeTo: .headline)).monospacedDigit().foregroundStyle(dim ? Theme.faint : (strong ? Theme.greenInk : Theme.ink))
            if !sub.isEmpty { Text(sub).font(.figtree(12, .medium, relativeTo: .caption)).monospacedDigit().foregroundStyle(Theme.muted) }
        }
    }

    private func costList(_ items: [LeaguePanel.CostItem]) -> some View {
        let rows = stride(from: 0, to: items.count, by: oneColumn ? 1 : 2).map { Array(items[$0..<min($0 + (oneColumn ? 1 : 2), items.count)]) }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, item in
                        (Text(item.label).font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                            + Text(item.value).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if row.count == 1 && !oneColumn { Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    // MARK: league view

    private func leagueView(_ key: String, _ r: BoxAdvice.LeagueRating) -> some View {
        let selection = Binding<String>(get: { mode ?? key }, set: { mode = $0 })
        let rows = LeaguePanel.listed(r, headline: LeaguePanel.headlineIndex(r, shown: LeaguePanel.shownIndex(r, pogoAssist: pogoAssist)))
        let open = !collapsed.contains(key)
        return VStack(alignment: .leading, spacing: 14) {
            SegmentedSwitch(
                segments: LeaguePanel.keys.map { k in
                    let league = League(rawValue: k) ?? .gl
                    return .init(value: k, title: LeaguePanel.shortName(k), dot: league.dot, selectedInk: league.ink, identifier: "leagues-control-\(k)")
                },
                selection: selection, label: "League", identifier: "leagues-control", singleLine: !oneColumn)
            pickCard(key, r, tappable: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(key, r))
                .accessibilityIdentifier("league-\(key)-pick")
            if !rows.isEmpty {
                Button { withAnimation(.easeOut(duration: 0.2)) { if open { collapsed.insert(key) } else { collapsed.remove(key) } } } label: {
                    HStack {
                        Text(open ? "Show less" : "Show more").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink)
                        Spacer()
                        Image(systemName: "chevron.down").font(.figtree(13, .bold)).foregroundStyle(accent.ink).rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .padding(.horizontal, 2).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(open ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("league-\(key)-more")
                if open { optionList(key, rows) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("league-\(key)")
    }

    private static let figureWidths: [CGFloat] = [64, 64, 78]

    private func optionList(_ key: String, _ options: [BoxAdvice.LeagueRating.Option]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !oneColumn {
                HStack(spacing: 8) {
                    Text("OPTION").frame(maxWidth: .infinity, alignment: .leading)
                    Text("SPECIES").frame(width: Self.figureWidths[0], alignment: .trailing)
                    Text("THIS COPY").frame(width: Self.figureWidths[1], alignment: .trailing)
                    Text("DUST").frame(width: Self.figureWidths[2], alignment: .trailing)
                }
                .font(.figtree(11, .bold, relativeTo: .caption2)).tracking(0.06 * 11).foregroundStyle(Theme.faint).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 2).padding(.bottom, 6)
                .accessibilityHidden(true)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            ForEach(options, id: \.speciesId) { o in
                optionRow(key, LeaguePanel.row(o, key: key, level: level))
            }
        }
    }

    private func optionRow(_ key: String, _ row: LeaguePanel.Row) -> some View {
        let id = row.option.speciesId
        let open = expanded[key] == id
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { expanded[key] = open ? nil : id } } label: {
                Group {
                    if oneColumn { stackedRow(row) } else { gridRow(row) }
                }
                .frame(minHeight: 48)
                .padding(.horizontal, open ? 10 : 2).padding(.vertical, 8)
                .background(open ? Theme.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.vertical, 2).padding(.horizontal, open ? 0 : 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LeaguePanel.spoken(row))
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("league-\(key)-option-\(id)")
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.detailLevel)
                    if let s = row.detailCost { Text(s) }
                    if let m = row.detailMoves { Text(m) }
                }
                .font(.figtree(14, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2).padding(.top, 4).padding(.bottom, 12)
                .accessibilityIdentifier("league-\(key)-option-\(id)-detail")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func nameBlock(_ row: LeaguePanel.Row) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(row.option.name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(row.blockedText != nil ? Theme.muted : Theme.ink).lineLimit(oneColumn ? nil : 1)
            if !row.sub.isEmpty { Text(row.sub).font(.figtree(12, .medium, relativeTo: .caption)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(oneColumn ? nil : 1) }
        }
    }

    private func gridRow(_ row: LeaguePanel.Row) -> some View {
        HStack(spacing: 8) {
            nameBlock(row).frame(maxWidth: .infinity, alignment: .leading)
            if let b = row.blockedText {
                Text(b).font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.red).multilineTextAlignment(.trailing)
                    .frame(width: Self.figureWidths.reduce(16, +), alignment: .trailing)
            } else {
                cell(row.score, row.rank, ink: row.score == "—" ? Theme.faint : (row.scoreStrong ? Theme.greenInk : Theme.ink), width: Self.figureWidths[0])
                cell(row.ivPct, row.ivRank, ink: row.ivPct == "—" ? Theme.faint : (row.ivStrong ? Theme.greenInk : Theme.ink), width: Self.figureWidths[1])
                cell(row.dust, row.candy, ink: row.dustMuted ? Theme.muted : Theme.ink, width: Self.figureWidths[2])
            }
        }
    }

    private func cell(_ value: String, _ sub: String, ink: Color, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(.figtree(15, .bold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(ink)
            Text(sub).font(.figtree(11, .medium, relativeTo: .caption2)).foregroundStyle(Theme.muted).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: width, alignment: .trailing)
    }

    /// From the first accessibility size the figures go under the name, one line each.
    private func stackedRow(_ row: LeaguePanel.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            nameBlock(row)
            if let b = row.blockedText {
                Text(b).font(.figtree(14, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.red).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach([("Species", row.score, row.rank), ("This copy", row.ivPct, row.ivRank), ("Dust", row.dust, row.candy)], id: \.0) { label, value, sub in
                    Text("\(label): ").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                        + Text(value + (sub.isEmpty ? "" : " · " + sub)).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Wrapping rows of views (CSS flex-wrap): each subview keeps its own size and moves to the next line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    private func lines(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames = [CGRect](), x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            // The half point forgives rounding: placement is offered exactly the width this layout reported for the same row.
            if x > 0 && x + size.width > width + 0.5 { y += lineHeight + spacing; x = 0; lineHeight = 0 }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing; lineHeight = max(lineHeight, size.height); maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { lines(proposal.width ?? .infinity, subviews).size }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = lines(bounds.width, subviews)
        // Centre each subview on its line.
        var lineTop: [CGFloat: CGFloat] = [:]
        for f in laid.frames { lineTop[f.minY] = max(lineTop[f.minY] ?? 0, f.height) }
        for (s, f) in zip(subviews, laid.frames) {
            s.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY + ((lineTop[f.minY] ?? f.height) - f.height) / 2), proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}
