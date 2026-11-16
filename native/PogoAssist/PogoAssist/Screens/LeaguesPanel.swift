import SwiftUI
import PogoBox

/// The PvP tab of the Pokémon page (design pass 3, D3, D4, CONCEPTS rules 9 and 19): PVP LEAGUES with the "i" (the Classic | Pogo Assist switch and its
/// explanation inside it), three league tiles, one muted worth line for the chosen league and, folded at first, its family and details (the other members,
/// the cost, the moves). All sentences and figures come from `LeaguePanel` and `PokemonPage` (PogoBox); nothing is rated again here.
struct LeaguesPanel: View {
    let ratings: [String: BoxAdvice.LeagueRating]
    /// The Pokémon's own level; nil when not known.
    let level: Double?
    /// "Pogo Assist is currently unable to detect Shadow Pokémon." while this copy's Shadow status is unknown.
    let showsShadowNote: Bool
    /// This copy's own Advice builds: a tile's cost mark reads the ones that cover its league, and its spoken label says "Advice builds it".
    let builds: [BoxAdvice.Build]
    /// No build of its own and hygiene would transfer it: the Weak sentence may then say "better kept for trading or transferring".
    let transfers: Bool
    /// The chosen league tile (a league key). Owned by the page.
    @Binding var selected: String

    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accent) private var accent
    @State private var infoOpen = false
    @State private var famOpen = false
    @State private var expanded: [String: String] = [:]

    private var pogoAssist: Bool { rankingRaw == Ranking.pogoAssist.rawValue }
    private var oneColumn: Bool { typeSize.isAccessibilitySize }
    private var keys: [String] { LeaguePanel.keys.filter { ratings[$0] != nil } }
    private var chosen: String { keys.contains(selected) ? selected : (keys.first ?? selected) }

    var body: some View {
        Panel(padding: 16, spacing: 12) {
            header
            if infoOpen { explainer.transition(.opacity) }
            tiles
            if let r = ratings[chosen] { detail(chosen, r) }
        }
        .animation(.easeOut(duration: 0.2), value: infoOpen)
        .animation(.easeOut(duration: 0.2), value: famOpen)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pvp-tab")
    }

    // MARK: header and the "i"

    private var header: some View {
        HStack(spacing: 8) {
            Text("PVP LEAGUES").font(.figtree(13, .heavy, relativeTo: .footnote)).tracking(0.5).foregroundStyle(ContentType.pvp.ink(accent))
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("leagues-panel")
            Spacer(minLength: 8)
            InfoButton(isOpen: $infoOpen, label: "Ranking and how the picks are made", identifier: "leagues-scoring-info")
        }
        .padding(.vertical, -6)
    }

    /// The Classic | Pogo Assist switch lives inside the "i" (D4), above its explanation.
    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { rankingLabel; Spacer(minLength: 8); rankingSwitch }
                VStack(alignment: .leading, spacing: 4) { rankingLabel; rankingSwitch }
            }
            RankingExplainer(identifier: "leagues-scoring-explainer")
            if showsShadowNote {
                Text("Pogo Assist is currently unable to detect Shadow Pokémon.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("leagues-shadow-note")
            }
        }
    }

    private var rankingLabel: some View {
        Text("RANKING").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.6).foregroundStyle(Theme.faint).accessibilityHidden(true)
    }

    private var rankingSwitch: some View {
        SegmentedSwitch(
            segments: Ranking.allCases.map { .init(value: $0, title: $0.title) },
            selection: Binding(get: { Ranking(rawValue: rankingRaw) ?? .default }, set: { rankingRaw = $0.rawValue }),
            metrics: .compact, label: "Ranking", identifier: "leagues-scoring", adjustable: true, singleLine: !oneColumn)
    }

    // MARK: the tiles

    private func card(_ key: String, _ r: BoxAdvice.LeagueRating) -> LeaguePanel.Card {
        LeaguePanel.card(r, shown: LeaguePanel.shownIndex(r, pogoAssist: pogoAssist), key: key, level: level, builds: builds)
    }

    private var tiles: some View {
        Group {
            if oneColumn { VStack(spacing: 8) { ForEach(keys, id: \.self) { tile($0) } } }
            else { HStack(alignment: .top, spacing: 8) { ForEach(keys, id: \.self) { tile($0) } } }
        }
    }

    /// A league tile (surface2, radius 16, a 2 pt ring in the league's ink when chosen): the pick with its types, its score and rank, this copy's IV % and rank,
    /// the worth tag and the cost mark.
    private func tile(_ key: String) -> some View {
        let r = ratings[key]!
        let c = card(key, r), league = League(rawValue: key) ?? .gl, on = key == chosen
        let species = try? GameMaster.bundled()
        let mark = MyPokemon.copyMark(builds: builds.filter { $0.areas.contains(BoxAdvice.areaLabel[key] ?? key) })
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button { selected = key } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Circle().fill(league.dot).frame(width: 8, height: 8)
                    Text(BoxAdvice.areaLabel[key] ?? key.uppercased()).font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.5)
                }
                .foregroundStyle(league.ink)
                Text(c.title).font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineLimit(oneColumn ? nil : 2).multilineTextAlignment(.leading)
                TypeIcons(types: species?.byId[c.option.speciesId]?.types ?? [], size: 16)
                if c.status == .noViable {
                    Text("Over the cap").font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.red).multilineTextAlignment(.leading)
                } else {
                    fig(c.scoreText, MyPokemon.scoreGrade(c.option.strength?.score), c.rankText)
                    fig(c.ivText, MyPokemon.rankGrade(c.status == .fits ? c.option.iv?.rank : nil), c.ivRankText)
                }
                if let w = c.worth { worthTag(w) }
                Spacer(minLength: 0)
                PlanMark(mark: mark, label: nil).frame(minHeight: 18)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: oneColumn ? 0 : 150, alignment: .topLeading)
            .background(Theme.surface2, in: shape)
            .overlay { if on { shape.strokeBorder(league.ink, lineWidth: 2) } }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LeaguePanel.spoken(c, key: key, chip: LeaguePanel.chipText(pogoAssist: pogoAssist)))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("league-\(key)-pick")
    }

    private func fig(_ value: String, _ grade: MyPokemon.Grade, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GradedNumber(value, grade, size: 15, plain: .heavy, relativeTo: .subheadline).foregroundStyle(value == "—" ? Theme.faint : Theme.ink)
            if !sub.isEmpty { Text(sub).font(.figtree(11, .semibold, relativeTo: .caption2)).foregroundStyle(Theme.muted).monospacedDigit() }
        }
    }

    /// TOP, GOOD or WEAK (the app's worth words) in the card's tag style.
    private func worthTag(_ w: LeaguePanel.Worth) -> some View {
        let style = WorthTag.style(for: w)
        let (ink, tint): (Color, Color) = w == .strong ? (Theme.greenInk, Theme.greenTint) : w == .ok ? (Theme.greenInk, Theme.greenTint.opacity(style.tintOpacity)) : (Theme.muted, Theme.off)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Text(w.label.uppercased()).font(.figtree(10, .bold, relativeTo: .caption2)).tracking(0.6).foregroundStyle(ink)
            .padding(.horizontal, 6).padding(.vertical, 2).background(tint, in: shape)
            .overlay { if let border = style.borderOpacity { shape.strokeBorder(ink.opacity(border), lineWidth: 1) } }
    }

    // MARK: the chosen league

    private func detail(_ key: String, _ r: BoxAdvice.LeagueRating) -> some View {
        let c = card(key, r)
        let rows = LeaguePanel.listed(r, headline: LeaguePanel.headlineIndex(r, shown: LeaguePanel.shownIndex(r, pogoAssist: pogoAssist)))
        return VStack(alignment: .leading, spacing: 10) {
            mutedLine(PokemonPage.worthLine(c, key: key, transfers: transfers)).accessibilityIdentifier("league-worth-line")
            Button { withAnimation(.easeOut(duration: 0.2)) { famOpen.toggle() } } label: {
                HStack {
                    Text(PokemonPage.familyLabel(key: key, more: rows.count)).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.figtree(13, .heavy)).foregroundStyle(accent.ink).rotationEffect(.degrees(famOpen ? 90 : 0)).accessibilityHidden(true)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityValue(famOpen ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("league-family-toggle")
            if famOpen { fold(key, c, rows) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("league-\(key)")
    }

    private func mutedLine(_ text: String) -> some View {
        Text(text).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }

    /// What the old league view showed under its card: the stronger-species note, the over-cap count, the cost, the moves and the other family members.
    private func fold(_ key: String, _ c: LeaguePanel.Card, _ rows: [BoxAdvice.LeagueRating.Option]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let note = c.bestAvailableNote { mutedLine(note) }
            if c.overCapCount > 0 {
                Text("▲ \(c.overCapCount) over cap").font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.04 * 11)
                    .foregroundStyle(Theme.red).padding(.horizontal, 7).padding(.vertical, 3).background(Theme.redTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if !c.costItems.isEmpty { costList(c.costItems) }
            if let n = c.costNote { mutedLine(n) }
            if !c.moves.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(c.moves.enumerated()), id: \.offset) { _, m in
                        Text(m.text).font(.figtree(12, .bold, relativeTo: .caption)).monospacedDigit()
                            .foregroundStyle(m.missing ? Theme.orangeInk : Theme.muted).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(m.missing ? Theme.orangeTint : Theme.off, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    }
                }
            }
            if !rows.isEmpty { optionList(key, rows) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("league-family")
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

    // MARK: the other members

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
                // The tiles' bands (rule 9): top 92+ or IV rank 1 to 100, good 90+ or 101 to 500; never the cards' older 88 / 80th-percentile cut.
                let g = PokemonPage.grades(row)
                cell(row.score, row.rank, grade: g.score, dim: row.score == "—", width: Self.figureWidths[0])
                cell(row.ivPct, row.ivRank, grade: g.iv, dim: row.ivPct == "—", width: Self.figureWidths[1])
                cell(row.dust, row.candy, grade: .plain, ink: row.dustMuted ? Theme.muted : Theme.ink, width: Self.figureWidths[2])
            }
        }
    }

    private func cell(_ value: String, _ sub: String, grade: MyPokemon.Grade, dim: Bool = false, ink: Color = Theme.ink, width: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            GradedNumber(value, grade, size: 15, plain: .bold, relativeTo: .subheadline).foregroundStyle(dim ? Theme.faint : ink)
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
                let g = PokemonPage.grades(row)
                ForEach([("Species", row.score, row.rank, g.score), ("This copy", row.ivPct, row.ivRank, g.iv), ("Dust", row.dust, row.candy, MyPokemon.Grade.plain)], id: \.0) { label, value, sub, grade in
                    FlowLayout(spacing: 4) {
                        Text("\(label): ").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                        GradedNumber(value, grade, size: 14, plain: .bold, relativeTo: .subheadline).foregroundStyle(Theme.ink)
                        if !sub.isEmpty { Text("· " + sub).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink) }
                    }
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
