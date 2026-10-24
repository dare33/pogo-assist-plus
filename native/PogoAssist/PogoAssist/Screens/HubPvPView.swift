import SwiftUI
import PogoBox

/// PvP leagues (design handoff section 5, screenshot 13): a league switch, a suggested team of three from the box with the types it covers, and
/// the other candidates. Read-only suggestions worked out by `HubTeams`; the design's slot picker is not built (a manager call for this PR).
struct HubPvPView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue
    @Environment(\.accent) private var accent
    @State private var league = "gl"
    @State private var showAll = false

    private let hub = try? HubData.bundled()
    private let gm = try? GameMaster.bundled()
    /// The other candidates listed before "All N" is tapped.
    private let preview = 5

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .pvp)) }
        return HubTypeScreen(type: .pvp, sub: "A \(LeaguePanel.name(league)) team from your box", count: count) {
            SegmentedSwitch(
                segments: LeaguePanel.keys.map { k in
                    let l = League(rawValue: k) ?? .gl
                    return .init(value: k, title: LeaguePanel.shortName(k), dot: l.dot, selectedInk: l.ink, identifier: "hub-pvp-league-\(k)")
                },
                selection: $league, label: "League", identifier: "hub-pvp-league")
            if let hub, let gm {
                HubAdviceGate { advice in screen(advice, hub: hub, gm: gm) }
                Text(seasonNote(hub)).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            } else {
                Text("The type chart could not be read.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityIdentifier("hub-screen-pvp")
        .onChange(of: league) { _, _ in showAll = false }
    }

    @ViewBuilder private func screen(_ advice: BoxAdvice, hub: HubData, gm: GameMaster) -> some View {
        let candidates = HubTeams.candidates(league: league, advice: advice, pogoAssist: rankingRaw == Ranking.pogoAssist.rawValue)
        let team = HubTeams.suggestedTeam(candidates: candidates, gm: gm, hub: hub)
        let others = HubTeams.others(candidates: candidates, team: team)
        if candidates.isEmpty {
            Text("No \(LeaguePanel.name(league)) candidate in your box scores \(Int(HubTeams.bFloor)) or more.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("hub-pvp-none")
        } else {
            let covered = HubTeams.coverage(team: team, gm: gm, hub: hub)
            VStack(alignment: .leading, spacing: 10) {
                HubSlotsPanel(title: "Suggested team", type: .pvp) {
                    ForEach(0..<3, id: \.self) { i in
                        if team.indices.contains(i) {
                            let c = team[i]
                            let types = (gm.byId[c.speciesId]?.types ?? []).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "/")
                            let sub = types + (i == 0 ? " · lead" : "")
                            HubSlotTile(type: .pvp, disc: String(c.name.prefix(1)), name: c.name, sub: sub, filled: true, label: "Slot \(i + 1), \(c.name), \(sub)")
                                .accessibilityIdentifier("hub-pvp-slot-\(i + 1)")
                        } else {
                            HubSlotTile(type: .pvp, disc: "+", name: "Empty", sub: "No other candidate", filled: false, label: "Slot \(i + 1), empty")
                                .accessibilityIdentifier("hub-pvp-slot-\(i + 1)")
                        }
                    }
                } trailing: {
                    Text("Coverage \(covered) of 18 types").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("hub-pvp-coverage")
                }
                Text(HubTeams.weaknessNote(team: team, candidates: others, gm: gm, hub: hub)).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4).accessibilityIdentifier("hub-pvp-weakness")
            }
            if !others.isEmpty {
                HubHeaderLine("OTHER CANDIDATES") {
                    if others.count > preview {
                        Button { withAnimation(.easeOut(duration: 0.15)) { showAll.toggle() } } label: {
                            Text(showAll ? "Fewer" : "All \(others.count)").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink).frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("hub-pvp-all")
                    }
                }
                candidateList(showAll ? others : Array(others.prefix(preview)))
            }
        }
    }

    // MARK: candidates

    private func candidateList(_ list: [HubTeams.Candidate]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                NavigationLink(value: c.entryId) { row(c) }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("hub-pvp-candidate")
                if i < list.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
    }

    private func row(_ c: HubTeams.Candidate) -> some View {
        let score = LeaguePanel.oneDecimal(c.score)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(c.name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineLimit(2)
                    if !c.tier.isEmpty { TierChip(tier: c.tier, type: .pvp) }
                }
                if let from = c.fromText { Text(from).font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.ink) }
                Text(c.subText).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                Text(score).font(.figtree(14, .heavy, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink)
                Text("SCORE").font(.figtree(10, .bold, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.muted)
            }
            Image(systemName: "chevron.right").font(.figtree(13, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(c.name), tier \(c.tier). \(c.fromText.map { $0 + ". " } ?? "")\(c.subText)")
        .accessibilityValue("score \(score)")
    }

    // MARK: season

    private func seasonNote(_ hub: HubData) -> String {
        let base = "GO Battle League seasons announce their league rotation at season start"
        let today = HubModel.dayKey(Date())
        guard let season = hub.events.first(where: { $0.tie == "pvp" && $0.title.hasPrefix("GO Battle League") && $0.to >= today }) else { return base + "." }
        let end = HubModel.span(from: season.to, to: season.to, today: "0000-00-00").spoken
        return base + "; the current season is \(season.title), ending \(end)."
    }
}
