import SwiftUI
import PogoBox

/// The Summary tab of the Pokémon page (design pass 3, D14 to D20, rules 15 and 16): one row per activity with its verdict, the facts behind it and its cost,
/// then the Advice. All words come from `PokemonActivities.summary` and `PokemonPage` (PogoBox); this file lays them out.
struct SummaryRowsPanel: View {
    let rows: [PokemonActivities.SummaryRow]
    let open: (PokemonActivities.Tab) -> Void

    var body: some View {
        Panel(padding: 0, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.activity) { n, row in
                    if n > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    SummaryRowView(row: row) { open(PokemonPage.tab(row.activity)) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summary-rows")
    }
}

/// A row (D20): the glyph in its colour over both lines; the name 15/700 in its colour and, flush right, the verdict; under them the detail lines (13/500
/// muted, one fact each, league letters in their colours and top or good scores graded), the cost slot and the chevron.
struct SummaryRowView: View {
    let row: PokemonActivities.SummaryRow
    let action: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    private var content: ContentType { row.activity.content }
    private var tab: PokemonActivities.Tab { PokemonPage.tab(row.activity) }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ActivityGlyph(tab: tab, size: 17, ink: content.ink(accent)).padding(.top, 2).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    // At the accessibility sizes the verdict goes under the name rather than squeezing it into a broken word.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) { nameText; Spacer(minLength: 8); VerdictText(verdict: row.verdict) }
                        VStack(alignment: .leading, spacing: 2) { nameText; VerdictText(verdict: row.verdict) }
                    }
                    // At the accessibility sizes the cost and chevron take their own line, so the facts keep the row's width and wrap at word boundaries.
                    let lines = VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(row.lines.enumerated()), id: \.offset) { _, l in lineView(l) }
                    }
                    let trailing = HStack(spacing: 8) {
                        PlanMark(mark: PokemonPage.buildMark(row.mark), label: PokemonPage.upgradeLabel(row.mark))
                        Image(systemName: "chevron.right").font(.figtree(13, .heavy)).foregroundStyle(Theme.faint).accessibilityHidden(true)
                    }
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) { lines; HStack { Spacer(minLength: 0); trailing } }
                    } else {
                        HStack(alignment: .bottom, spacing: 8) { lines; Spacer(minLength: 0); trailing }
                    }
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Opens the \(tab.title) tab")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("summary-row-\(row.activity.rawValue)")
    }

    private var nameText: some View {
        Text(PokemonPage.name(row.activity)).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(content.ink(accent)).fixedSize(horizontal: false, vertical: true)
    }

    private var spoken: String {
        var parts = [PokemonPage.name(row.activity), row.verdict.text.lowercased()]
        parts += row.lines.map { l in l.plain + (l.icons.isEmpty ? "" : " " + l.icons.map { $0.capitalized }.joined(separator: ", ") + " grunts") }
        switch row.mark {
        case .fullStrength: parts.append("Full strength")
        case .upgrade(_, let cost, let label): parts.append(label + (cost.value.map { ", " + $0 + (cost.currency == .candy ? " candy" : " dust") } ?? ""))
        case .none: break
        }
        return parts.joined(separator: ". ")
    }

    private func lineView(_ l: PokemonActivities.Line) -> some View {
        FlowLayout(spacing: 4) {
            if let lead = l.lead {
                let league = League(rawValue: lead.lowercased())
                Text(lead).font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(league?.ink ?? Theme.muted)
            }
            Text(l.text).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            if let score = l.score {
                GradedNumber(score, MyPokemon.scoreGrade(Double(score)), size: 13, plain: .medium).foregroundStyle(Theme.muted)
            }
            if !l.icons.isEmpty { TypeIcons(types: l.icons, size: 16) }
        }
    }
}

// MARK: the Advice

/// The Advice panel (D4): each build is two lines, the target with its type icons and cost or tick, then one muted line with the area in its colour, the tier and
/// the work; the spare and keep or transfer notes are one line, the full sentences behind the "i".
struct AdvicePanel: View {
    let entry: BoxEntry
    let advice: BoxAdvice
    @State private var infoOpen = false
    @Environment(\.accent) private var accent

    var body: some View {
        let a = advice.entries(for: entry.id)
        let gm = try? GameMaster.bundled()
        let sentences = PokemonPage.adviceSentences(a, name: entry.row.title) { BuildRow(build: $0, showName: false).costLine }
        Panel(tint: .accent, padding: 18, spacing: 10) {
            HStack(spacing: 6) {
                Text("ADVICE").font(.figtree(13, .heavy, relativeTo: .footnote)).tracking(0.5).foregroundStyle(accent.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if !sentences.isEmpty { InfoButton(isOpen: $infoOpen, size: 22, label: "Why", identifier: "advice-info") }
            }
            .padding(.vertical, -4)
            if infoOpen {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(sentences.builds.enumerated()), id: \.offset) { n, s in sentence(s, "advice-sentence-\(n)") }
                    if let s = sentences.spare { sentence(s, "advice-spare") }
                    if let s = sentences.verdict { sentence(s, "advice-verdict") }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("advice-sentences")
            }
            if a.isEmpty {
                Text("The advisor has nothing for this Pokémon.").font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
            }
            ForEach(Array(a.builds.enumerated()), id: \.element.id) { n, b in
                if n > 0 { Rectangle().fill(accent.ink.opacity(0.18)).frame(height: 1).padding(.vertical, 2) }
                buildView(b, n: n, gm: gm)
            }
            if let notes = PokemonPage.shortNotes(a, name: a.duplicateOf?.name ?? entry.row.title) {
                Rectangle().fill(accent.ink.opacity(0.18)).frame(height: 1).padding(.vertical, 2)
                Text(notes).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("advice-notes")
            }
        }
    }

    private func sentence(_ text: String, _ id: String) -> some View {
        Text(text).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id)
    }

    private func buildView(_ b: BoxAdvice.Build, n: Int, gm: GameMaster?) -> some View {
        let plan = PokemonPage.planMark(b, built: HubTeams.isBuilt(b))
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(b.targetName + (b.pvp.map { " (\($0))" } ?? "")).font(.figtree(18, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                TypeIcons(types: gm?.byId[b.targetId]?.types ?? [], size: 18)
                Spacer(minLength: 0)
                PlanMark(mark: plan.mark, label: plan.label)
            }
            adviceLine(b)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("advice-build-\(n)")
    }

    /// "Raids · Tier B · Evolve, power up to level 35": the area words in their colours, the tier and the work muted (D13).
    private func adviceLine(_ b: BoxAdvice.Build) -> some View {
        var line = Text("")
        for (i, area) in b.areas.enumerated() {
            line = line + Text(i > 0 ? "/" : "").foregroundStyle(Theme.muted) + Text(area).bold().foregroundStyle(Self.ink(area, accent))
        }
        let rest = (b.tier.isEmpty ? "" : " · Tier \(b.tier)") + " · " + PokemonPage.workLine(b)
        return (line + Text(rest).foregroundStyle(Theme.muted))
            .font(.figtree(13, .medium, relativeTo: .footnote))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The colour of an area word: the Hub's tile colours, the league's own for GL, UL and ML.
    static func ink(_ area: String, _ accent: Accent) -> Color {
        switch area {
        case "Raids": return ContentType.raids.ink(accent)
        case "Gym": return ContentType.gym.ink(accent)
        case "Rocket": return ContentType.rocket.ink(accent)
        case "Max": return ContentType.max.ink(accent)
        case "GL", "UL", "ML": return League(rawValue: area.lowercased())?.ink ?? Theme.muted
        default: return Theme.muted
        }
    }
}

// MARK: under every tab

/// Power-up dust, spare copies and seen in one row of three (D4).
struct PageFacts: View {
    let dust: Int?
    let spares: Int
    let seen: String

    var body: some View {
        Panel(padding: 0, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) { dustFact; fact("SPARE COPIES", spares > 0 ? spares.formatted() : "None"); fact("SEEN", seen) }
                VStack(alignment: .leading, spacing: 10) { dustFact; fact("SPARE COPIES", spares > 0 ? spares.formatted() : "None"); fact("SEEN", seen) }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("page-facts")
    }

    private var dustFact: some View {
        VStack(alignment: .leading, spacing: 2) {
            CapsCaption("POWER-UP")
            HStack(spacing: 4) {
                Text(dust.map { $0.formatted() } ?? "not known").font(.figtree(15, .bold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink)
                if dust != nil { CurrencyIcon(currency: .dust) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power-up dust")
        .accessibilityValue(dust.map { $0.formatted() } ?? "not known")
    }

    private func fact(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CapsCaption(caption)
            Text(value).font(.figtree(15, .bold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption.capitalized)
        .accessibilityValue(value)
    }
}
