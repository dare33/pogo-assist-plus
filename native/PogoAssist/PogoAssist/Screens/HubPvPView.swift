import SwiftUI
import PogoBox

/// PvP leagues (design pass 2): a league switch, SUGGESTIONS · Available | Best, a Suggested squad of three by role (Lead, Safe swap, Closer) with the types it covers,
/// the weakness line, a picker with role chips, the other candidates and the season. The picks and roles for each league are kept per account (`SquadKeeper`).
struct HubPvPView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var keeper = SquadKeeper()
    @Environment(\.accent) private var accent
    @State private var league = "gl"

    private let hub = try? HubData.bundled()

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .pvp)) }
        return HubTypeScreen(type: .pvp, sub: "\(league == "ul" ? "An" : "A") \(LeaguePanel.name(league)) squad from your box", count: count) {
            SegmentedSwitch(
                segments: LeaguePanel.keys.map { k in
                    let l = League(rawValue: k) ?? .gl
                    return .init(value: k, title: LeaguePanel.shortName(k), dot: l.dot, selectedInk: l.ink, identifier: "hub-pvp-league-\(k)")
                },
                selection: $league, label: "League", identifier: "hub-pvp-league")
            if let hub {
                if let ctx = model.squadContext() {
                    PvPSquadView(league: league, ctx: ctx, keeper: keeper).id(league)
                } else {
                    HubAdviceGate { _ in EmptyView() }
                }
                if let line = seasonLine(hub) {
                    Text(line).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                        .accessibilityIdentifier("hub-pvp-season")
                }
            } else {
                Text("The type chart could not be read.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
        }
        .keepsSquads(keeper)
        .accessibilityIdentifier("hub-screen-pvp")
    }

    // MARK: season

    /// "Current Season: GO Battle League: Twilight Trails. Ends 1 December, 2026."; nil when the Hub's data names no season under way.
    private func seasonLine(_ hub: HubData) -> String? {
        let today = HubModel.today()
        guard let season = hub.events.first(where: { $0.tie == "pvp" && $0.title.hasPrefix("GO Battle League") && $0.to >= today }) else { return nil }
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        let p = season.to.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return "Current Season: \(season.title)." }
        return "Current Season: \(season.title). Ends \(p[2]) \(months[p[1] - 1]), \(p[0])."
    }
}

// MARK: the squad of a league

private struct PvPSquadView: View {
    let league: String
    let ctx: HubContext
    @ObservedObject var keeper: SquadKeeper
    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue
    @Environment(\.accent) private var accent
    @State private var selected: Int?
    @State private var showAll = false
    @State private var squadInfo = false

    /// The other candidates listed before "All N" is tapped.
    private let preview = 5
    private let chips = HubSquads.PvpRole.allCases.map(\.rawValue) + [squadRoleAll]

    var body: some View {
        let mode = keeper.store.mode(for: .pvp)
        let candidates = HubSquads.pvpCandidates(league: league, mode: mode, pogoAssist: rankingRaw == Ranking.pogoAssist.rawValue, ctx: ctx)
        let saved = keeper.store.pvpSquad(league: league)
        let pogoAssist = rankingRaw == Ranking.pogoAssist.rawValue
        let filled = HubSquads.pvpSquad(slots: saved.slots, candidates: candidates, placeable: PvPPlacement.placeable(league: league, mode: mode, pogoAssist: pogoAssist, ctx: ctx))
        let byId = Dictionary(candidates.map { ($0.entryId, $0) }, uniquingKeysWith: { a, _ in a })
        SuggestionsRow(mode: Binding(get: { mode }, set: { m in keeper.update { $0.setMode(m, for: .pvp) } }), noun: "squads")
        if candidates.isEmpty {
            // The squad still shows, with its empty slots: a slot's picker lists what could be got now (READBACK 1.15).
            Text("No \(LeaguePanel.name(league)) candidate in your box scores \(Int(HubTeams.candidateFloor)) or more\(mode == .available ? " as it is" : "").")
                .font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("hub-pvp-none")
        }
        squad(filled: filled, candidates: candidates, byId: byId, pogoAssist: pogoAssist)
        if let i = selected, filled.indices.contains(i) { picker(i, filled: filled, candidates: candidates, byId: byId, pogoAssist: pogoAssist) }
        others(candidates: candidates, filled: filled)
    }

    // MARK: members

    /// A Pokémon in a slot as the screen names it. A pick that is still in the box but no longer heads the candidate list (a better copy of its species now does, or
    /// it scores under the floor) has no `candidate`: it is read from the copy's own league rating, so its slot still names it and the coverage still counts it.
    private struct Member {
        var name: String
        var types: [String]
        var mark: SquadMark
        var candidate: HubTeams.Candidate?
        var option: BoxAdvice.LeagueRating.Option?
        var copyTitle = ""
    }

    private func types(_ speciesId: String) -> [String] { ctx.gm.byId[speciesId]?.types ?? [] }

    private func member(_ id: String, byId: [String: HubSquads.PvpCandidate], pogoAssist: Bool) -> Member? {
        if let c = byId[id]?.candidate { return Member(name: c.displayName, types: types(c.speciesId), mark: SquadMark.of(c), candidate: c, option: c.option, copyTitle: c.copyTitle) }
        if let r = ctx.advice.leagues[id]?[league] {
            let o = r.options[LeaguePanel.shownIndex(r, pogoAssist: pogoAssist)]
            let c = o.cost
            let built = o.isSelf && c != nil && c!.dust == 0 && c!.candy == 0 && c!.xl == 0 && (o.needs ?? []).isEmpty
            let copy = r.options.first(where: \.isSelf)?.name ?? ""
            return Member(name: o.genderLocked.map { "\(o.name), if it is \($0)" } ?? o.name, types: types(o.speciesId), mark: SquadMark.of(option: o, built: built, copyTitle: copy), candidate: nil, option: o, copyTitle: copy)
        }
        return ctx.entry(id).map { Member(name: $0.row.title, types: [], mark: .none, candidate: nil, option: nil) }
    }

    // MARK: the squad

    @ViewBuilder private func squad(filled: [FilledSlot], candidates: [HubSquads.PvpCandidate], byId: [String: HubSquads.PvpCandidate], pogoAssist: Bool) -> some View {
        let members = filled.map { f in f.entryId.flatMap { member($0, byId: byId, pogoAssist: pogoAssist) } }
        // The types the squad hits for more than normal damage, over every member named in a slot (shown, not used to pick: D57).
        let mine = Array(Set(members.compactMap { $0 }.flatMap(\.types)))
        let covered = HubData.typeOrder.filter { ctx.hub.beats(mine, [$0]) }.count
        let team = members.compactMap { $0?.candidate }
        let rest = candidates.filter { c in !filled.contains { $0.entryId == c.entryId } }.map(\.candidate)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Suggested squad").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Text("Coverage \(covered) of 18 types").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("hub-pvp-coverage")
                    InfoButton(isOpen: $squadInfo, label: "About the suggested squad", identifier: "squad-info")
                }
                if squadInfo {
                    SquadExplainer(items: [
                        ("Lead", "opens the battle; Safe swap comes in when the lead's matchup is bad; Closer finishes once shields are gone."),
                        ("", "Each slot takes the best-scoring candidate our league table lists for that role. Coverage counts the types the squad hits for more than normal damage; it is shown, not used to pick. Change any slot's role in its picker; All lets you put in any Pokémon."),
                    ], identifier: "squad-explainer")
                }
                SlotGrid(slots: filled.enumerated().map { card($0.offset, $0.element, member: members[$0.offset]) }, selected: selected) { i in
                    withAnimation(.easeOut(duration: 0.15)) { selected = selected == i ? nil : i }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .panelShadow()
            let note = HubTeams.weaknessNote(team: team, candidates: rest, gm: ctx.gm, hub: ctx.hub)
            if !note.isEmpty {
                Text(note).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.horizontal, 4).accessibilityIdentifier("hub-pvp-weakness")
            }
        }
    }

    private func card(_ i: Int, _ f: FilledSlot, member m: Member?) -> SlotCardModel {
        let palette = SquadPalette.of(f.role)
        let head = "Slot \(i + 1) of 3, \(f.role)"
        let id = "hub-pvp-slot-\(i + 1)"
        guard let m else {
            return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: nil, lines: ["No candidate"], spoken: head + ", empty", identifier: id)
        }
        let spoken = [head, m.name, SquadWords.typeList(m.types), m.mark.spoken].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: m.name, types: m.types, mark: m.mark, spoken: spoken, identifier: id)
    }

    // MARK: picker

    private func picker(_ i: Int, filled: [FilledSlot], candidates: [HubSquads.PvpCandidate], byId: [String: HubSquads.PvpCandidate], pogoAssist: Bool) -> some View {
        let role = filled[i].role
        var ids = HubSquads.pool(role: role, in: candidates)
        // The slot's own Pokémon is always listed, ticked, even when it came from outside the role's pool (the fallback) or is no longer a candidate.
        if let own = filled[i].entryId, !ids.contains(own) { ids.insert(own, at: 0) }
        let listed = HubSquads.picker(candidates: ids, excluded: HubSquads.excluded(by: filled, editing: i, onlyChosen: false), own: filled[i].entryId)
        let rows: [PickerRowModel] = listed.compactMap { l in
            if let pc = byId[l.entryId] { return row(pc, ticked: l.ticked) }
            guard let m = member(l.entryId, byId: byId, pogoAssist: pogoAssist) else { return nil }
            return fallbackRow(l.entryId, m, ticked: l.ticked)
        }
        let could = HubSquads.pvpCouldGet(league: league, role: role, ctx: ctx).map { CouldGetModel($0, types: ctx.gm.byId[$0.gap.speciesId ?? ""]?.types ?? []) }
        return SquadPicker(
            title: "Slot \(i + 1) · \(role)", type: .pvp, roles: chips, role: role,
            onRole: { new in keeper.update { s in
                var saved = s.pvpSquad(league: league)
                saved.changeRole(at: i, to: new) { HubSquads.fits($0, role: new, in: candidates) }
                s.pvp[league] = saved
            } },
            rows: rows, emptyText: "No candidate in your box for this role.", couldGet: could,
            onChoose: { id in keeper.update { s in
                var saved = s.pvpSquad(league: league)
                saved.choose(id, at: i)
                s.pvp[league] = saved
            } },
            onDone: { withAnimation(.easeOut(duration: 0.15)) { selected = nil } },
            info: {
                SquadExplainer(items: [
                    ("Best first:", "the higher league score (our PvPoke-based score for this copy in this league)."),
                    ("Roles", "come from our league table's role column: lead, safe swap or switch, closer."),
                    ("Green numbers", "mark a top pick (boxed: score 92 or more, or an IV rank in the top 100) and a good pick (green: score 90 or more, or an IV rank in the top 500)."),
                ], identifier: "squad-picker-explainer")
            })
    }

    /// A row for a Pokémon that is in a slot but not on the candidate list, read from its own league rating.
    private func fallbackRow(_ id: String, _ m: Member, ticked: Bool) -> PickerRowModel {
        let score = m.option?.strength?.score
        let roles = (m.option.map { o in HubSquads.PvpRole.allCases.filter(ctx.table.entries(for: o.speciesId, area: league).flatMap { HubSquads.pvpRoles($0.role ?? "") }.contains) } ?? []).map(\.rawValue).joined(separator: " · ")
        let iv = m.option?.iv.map { "#\(LeaguePanel.grouped($0.rank)) · \(LeaguePanel.oneDecimal($0.pct))%" } ?? "IVs not read"
        let grade = MyPokemon.rankGrade(m.option?.iv?.rank)
        let scoreText = score.map(LeaguePanel.oneDecimal) ?? "—"
        let sGrade = MyPokemon.scoreGrade(score)
        let tier = score.map { HubTeams.tier(score: $0) } ?? ""
        let spoken = [m.name, roles, tier.isEmpty ? nil : "tier \(tier)", m.mark.spoken, "IV " + iv.replacingOccurrences(of: "#", with: "rank "), "score \(scoreText)", ticked ? "in this slot" : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return PickerRowModel(
            id: id, name: m.name, ticked: ticked, mark: m.mark, role: roles.isEmpty ? nil : roles, tier: tier, types: m.types.map { PickerType(type: $0) },
            noteView: AnyView(HStack(spacing: 4) {
                if !m.copyTitle.isEmpty, m.option?.isSelf == false { Text("From \(m.copyTitle) ·").font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted) }
                GradedNumber(iv, grade, size: 12, plain: .regular, relativeTo: .caption).foregroundStyle(grade == .plain ? Theme.muted : Theme.greenInk)
            }),
            figure: AnyView(VStack(alignment: .trailing, spacing: 0) {
                GradedNumber(scoreText, sGrade, size: 14, plain: .heavy, relativeTo: .subheadline)
                Text("SCORE").font(.figtree(10, .bold, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.muted)
            }.fixedSize()),
            spoken: spoken)
    }

    private func row(_ pc: HubSquads.PvpCandidate, ticked: Bool) -> PickerRowModel {
        let c = pc.candidate
        let types = ctx.gm.byId[c.speciesId]?.types ?? []
        let mark = SquadMark.of(c)
        let score = LeaguePanel.oneDecimal(c.score), scoreGrade = MyPokemon.scoreGrade(c.score), rankGrade = MyPokemon.rankGrade(c.ivRank)
        let roles = pc.roles.map(\.rawValue).joined(separator: " · ")
        let spoken = [c.displayName, roles, c.tier.isEmpty ? nil : "tier \(c.tier)", mark.spoken, c.fromText, "IV " + c.subText.replacingOccurrences(of: "#", with: "rank "),
                      "score \(score)" + (scoreGrade.spoken.isEmpty ? "" : ", \(scoreGrade.spoken) pick"), ticked ? "in this slot" : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return PickerRowModel(
            id: c.entryId, name: c.displayName, ticked: ticked, mark: mark, role: roles.isEmpty ? nil : roles, tier: c.tier, types: types.map { PickerType(type: $0) },
            noteView: AnyView(ivLine(c, grade: rankGrade)),
            figure: AnyView(VStack(alignment: .trailing, spacing: 0) {
                GradedNumber(score, scoreGrade, size: 14, plain: .heavy, relativeTo: .subheadline)
                Text("SCORE").font(.figtree(10, .bold, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.muted)
            }.fixedSize()),
            spoken: spoken)
    }

    /// "From Eevee · #528 · 96.8%", the IV part graded by its rank.
    private func ivLine(_ c: HubTeams.Candidate, grade: MyPokemon.Grade) -> some View {
        HStack(spacing: 4) {
            if let from = c.fromText { Text(from + " ·").font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted) }
            GradedNumber(c.subText, grade, size: 12, plain: .regular, relativeTo: .caption).foregroundStyle(grade == .plain ? Theme.muted : Theme.greenInk)
        }
    }

    // MARK: OTHER CANDIDATES

    @ViewBuilder private func others(candidates: [HubSquads.PvpCandidate], filled: [FilledSlot]) -> some View {
        let used = Set(filled.compactMap(\.entryId))
        let list = candidates.filter { !used.contains($0.entryId) }
        if !list.isEmpty {
            HubHeaderLine("OTHER CANDIDATES") {
                if list.count > preview {
                    Button { withAnimation(.easeOut(duration: 0.15)) { showAll.toggle() } } label: {
                        Text(showAll ? "Fewer" : "All \(list.count)").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("hub-pvp-all")
                }
            }
            let shown = showAll ? list : Array(list.prefix(preview))
            LazyVStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.entryId) { i, c in
                    NavigationLink(value: c.entryId) { candidateRow(c) }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("hub-pvp-candidate")
                    if i < shown.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .panelShadow()
        }
    }

    private func candidateRow(_ pc: HubSquads.PvpCandidate) -> some View {
        let c = pc.candidate
        let score = LeaguePanel.oneDecimal(c.score), scoreGrade = MyPokemon.scoreGrade(c.score), rankGrade = MyPokemon.rankGrade(c.ivRank)
        let mark = SquadMark.of(c)
        let roles = pc.roles.map(\.rawValue).joined(separator: " · ")
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(c.displayName).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineLimit(2)
                    if !c.tier.isEmpty { TierChip(tier: c.tier, type: .pvp) }
                    SquadMarkView(mark: mark)
                }
                if !roles.isEmpty {
                    Text(roles).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(SquadPalette.of(pc.roles.first?.rawValue ?? "").ink)
                }
                ivLine(c, grade: rankGrade)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                GradedNumber(score, scoreGrade, size: 14, plain: .heavy, relativeTo: .subheadline)
                Text("SCORE").font(.figtree(10, .bold, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.muted)
            }
            Image(systemName: "chevron.right").font(.figtree(13, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([c.displayName, c.tier.isEmpty ? nil : "tier \(c.tier)", mark.spoken, roles.isEmpty ? nil : roles, c.fromText, c.subText].compactMap { $0 }.joined(separator: ". "))
        .accessibilityValue("score \(score)\(scoreGrade.spoken.isEmpty ? "" : ", \(scoreGrade.spoken) pick")")
    }
}
