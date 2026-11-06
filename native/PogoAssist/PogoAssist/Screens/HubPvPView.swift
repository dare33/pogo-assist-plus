import SwiftUI
import PogoBox

/// PvP leagues (design pass 2): a league switch, SQUAD · Current | Available | Best, a Suggested squad of three by role (Lead, Safe swap, Closer) with the types it covers,
/// the weakness line, a picker with role chips, the other candidates and the season. The picks and roles for each league are kept per account (`SquadKeeper`).
struct HubPvPView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var keeper = SquadKeeper()
    @StateObject private var workspace = SquadWorkspace()
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
                    PvPSquadView(league: league, ctx: ctx, keeper: keeper, workspace: workspace).id(league)
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
        .keepsSquads(keeper, workspace)
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

/// The rows of a PvP picker, built from the box, the league and the tables alone (no view state), so a test can read what every picker would show.
struct PvPPickerBuilder {
    let league: String
    let ctx: HubContext
    let pogoAssist: Bool
    /// Drawing a Current squad (pass 2-5): no mode placement rule hides a kept pick, and a kept species pick is drawn as the Best row it is.
    var kept = false

    /// The league's candidates, the Best rows (under Best), the three slots filled and the candidates by id, for `slots`.
    func resolve(mode: SquadMode, slots: [SquadSlot]) -> (candidates: [HubSquads.PvpCandidate], best: [HubSquads.BestRow], filled: [FilledSlot], byId: [String: HubSquads.PvpCandidate]) {
        let candidates = HubSquads.pvpCandidates(league: league, mode: mode, pogoAssist: pogoAssist, ctx: ctx)
        // Best: the league table's rows, owned or not (rule 6). Available: the player's own candidates.
        // Current: only the Best rows of the squad's kept species picks, so a slot can be drawn as the row it holds (no list offers them).
        let keptKeys = kept ? Set(slots.compactMap(\.species)) : []
        let best = mode == .best ? HubSquads.bestPvpRows(league: league, pogoAssist: pogoAssist, ctx: ctx)
            : keptKeys.isEmpty ? [] : HubSquads.bestPvpRows(league: league, pogoAssist: pogoAssist, ctx: ctx).filter { keptKeys.contains($0.key) }
        let filled: [FilledSlot] = mode == .best
            ? PvPPlacement.squad(slots: HubSquads.resolvingSpecies(slots, rows: best), pool: { HubSquads.pool(role: $0, in: best) }, all: best.map(\.entryId),
                                 placeable: { _, _ in true }, species: { speciesId($0) })
            : PvPPlacement.squad(slots: kept ? HubSquads.resolvingSpecies(slots, rows: best) : slots, candidates: candidates,
                                 placeable: kept ? { _, _ in true } : PvPPlacement.placeable(league: league, mode: mode, pogoAssist: pogoAssist, ctx: ctx), species: { speciesId($0) })
        let byId = Dictionary(candidates.map { ($0.entryId, $0) }, uniquingKeysWith: { a, _ in a })
        return (candidates, best, filled, byId)
    }

    /// A Pokémon in a slot as the screen names it. A pick that is still in the box but no longer heads the candidate list (a better copy of its species now does, or
    /// it scores under the floor) has no `candidate`: it is read from the copy's own league rating, so its slot still names it and the coverage still counts it.
    struct Member {
        var name: String
        var types: [String]
        var mark: SquadMark
        var candidate: HubTeams.Candidate?
        var option: BoxAdvice.LeagueRating.Option?
        var copyTitle = ""
        /// The league tier the screen shows for it (`HubSquads.pvpTier`).
        var tier = ""
        /// Best: a Pokémon the box lacks (`candidate` and `option` are nil).
        /// Best: the row of a Pokémon the box lacks, or of a copy no league candidate serves.
        var notOwned: HubSquads.BestRow?
        /// Best: the row that shows an owned candidate, for its one status (S1).
        var bestRow: HubSquads.BestRow?
        /// The roles it is listed for in the league table (shown on a slot it fills from another role).
        var roles: [String] = []
    }

    func types(_ speciesId: String) -> [String] { ctx.gm.byId[speciesId]?.types ?? [] }

    /// The species a copy is shown as in this league under the ranking in use.
    func speciesId(_ id: String) -> String? {
        ctx.advice.leagues[id]?[league].map { $0.options[LeaguePanel.shownIndex($0, pogoAssist: pogoAssist)].speciesId }
    }

    func member(_ id: String, byId: [String: HubSquads.PvpCandidate], best: [HubSquads.BestRow]) -> Member? {
        if id.hasPrefix(squadSpeciesPrefix) {
            // Best: a Pokémon the box lacks.
            let key = String(id.dropFirst(squadSpeciesPrefix.count))
            if let r = best.first(where: { $0.entryId == id }) { return Member(name: r.name, types: r.types, mark: .none, candidate: nil, option: nil, tier: r.tier, notOwned: r) }
            let name = ctx.gm.byId[key]?.name ?? "Pokémon"
            let r = HubSquads.BestRow(key: key, name: name, speciesId: key, tier: "", roles: [], types: types(key), availability: "")
            return Member(name: name, types: r.types, mark: .none, candidate: nil, option: nil, notOwned: r)
        }
        // A copy of a table Pokémon that no league candidate serves (it scores under the floor, or is past the cap): "In your box · no build for this".
        if byId[id] == nil, let r = best.first(where: { $0.ownedEntryId == id && !$0.hasBuild }) { return Member(name: r.name, types: r.types, mark: .none, candidate: nil, option: nil, tier: "", notOwned: r) }
        if let c = byId[id]?.candidate { return Member(name: c.displayName, types: types(c.speciesId), mark: SquadMark.of(c), candidate: c, option: c.option, copyTitle: c.copyTitle,
                                                       tier: HubSquads.pvpTier(speciesId: c.speciesId, league: league, score: c.score), bestRow: best.first { $0.ownedEntryId == id },
                                                       roles: byId[id]?.roles.map(\.rawValue) ?? []) }
        if let r = ctx.advice.leagues[id]?[league] {
            let o = r.options[LeaguePanel.shownIndex(r, pogoAssist: pogoAssist)]
            let c = o.cost
            let built = o.isSelf && c != nil && c!.dust == 0 && c!.candy == 0 && c!.xl == 0 && (o.needs ?? []).isEmpty
            let copy = r.options.first(where: \.isSelf)?.name ?? ""
            return Member(name: o.genderLocked.map { "\(o.name), if it is \($0)" } ?? o.name, types: types(o.speciesId), mark: SquadMark.of(option: o, built: built, copyTitle: copy), candidate: nil, option: o, copyTitle: copy,
                          tier: HubSquads.pvpTier(speciesId: o.speciesId, league: league, score: o.strength?.score))
        }
        return ctx.entry(id).map { Member(name: $0.row.title, types: [], mark: .none, candidate: nil, option: nil) }
    }

    struct Content { var rows: [PickerRowModel]; var boxHasOptions: Bool; var speciesRuleOnly: Bool }

    /// `only` limits the rows to those ids: the squad strength bar needs one slot's own row, not the whole list.
    func content(slot i: Int, filled: [FilledSlot], candidates: [HubSquads.PvpCandidate], byId: [String: HubSquads.PvpCandidate], best: [HubSquads.BestRow], mode: SquadMode, only: Set<String>? = nil) -> Content {
        let role = filled[i].role
        // Available (S1): the slot's own role first, then every other unused candidate ("Other roles:"), in the order the squad is filled in.
        let groups = mode == .best ? (own: HubSquads.pool(role: role, in: best), other: [String]())
            : HubSquads.pickerGroups(own: HubSquads.pool(role: role, in: candidates), all: candidates.map(\.entryId), allowsOther: true)
        var ids = groups.own
        let boxHasOptions = !(groups.own + groups.other).isEmpty
        // The slot's own Pokémon is always listed, ticked, even when it came from outside the role's pool (the fallback) or is no longer a candidate.
        let ticks = HubSquads.tickIds(filled[i], rows: best)
        if let own = ticks.first ?? filled[i].pickId, ticks.isDisjoint(with: groups.own + groups.other) { ids.insert(own, at: 0) }
        let allIds = mode == .best ? best.map(\.entryId) : candidates.map(\.entryId)
        // A Pokémon in another slot is listed, marked with its slot: choosing it swaps the two (rule 27). Another copy of a species the squad holds is still not offered.
        // Only a swap that can happen: each Pokémon must fit the slot it goes to (Available: be rated in the league; Best: be listed for the role).
        let held = HubSquads.otherSlots(of: filled, editing: i, canHold: { f, j in
            mode == .best ? HubSquads.tickIds(f, rows: best).contains { HubSquads.fits($0, role: filled[j].role, in: best) } : kept || (f.pickId.map { ctx.advice.leagues[$0]?[league] != nil } ?? true)
        })
        let excluded = PvPPlacement.excluded(by: filled, editing: i, ids: allIds, species: { speciesId($0) }).subtracting(held.swap.keys).union(held.blocked)
        func limited(_ list: [String]) -> [String] { only.map { o in list.filter(o.contains) } ?? list }
        let listed = HubSquads.picker(candidates: limited(ids), excluded: excluded, ownIds: ticks)
        let listedOther = HubSquads.picker(candidates: limited(groups.other), excluded: excluded, ownIds: ticks)
        // Options hidden by the one-species rule alone (none is in another slot) are told apart from options that are all in the squad.
        let inSquad = HubSquads.excluded(by: filled, editing: i, onlyChosen: false)
        let speciesRuleOnly = boxHasOptions && listed.isEmpty && listedOther.isEmpty && (ids + groups.other).allSatisfy { !inSquad.contains($0) }
        func model(_ l: HubSquads.PickerRow) -> PickerRowModel? {
            if let r = best.first(where: { $0.entryId == l.entryId }), !r.hasBuild {
                // A copy no league rating serves shows its CP and IVs; with or without a copy the bar is PvPoke's score for the species in this league, else "score not known".
                return PickerRowModel(best: r, ticked: l.ticked, role: r.roles.isEmpty ? nil : r.roles.joined(separator: " · ")).adding(copy: r.inBox ? (r.copy ?? r.ownedEntryId.flatMap(ctx.entry)) : nil, strength: leagueScore(r.speciesId))
            }
            if let pc = byId[l.entryId] { return row(pc, ticked: l.ticked, status: best.first { $0.ownedEntryId == l.entryId }?.statusLine) }
            guard let m = member(l.entryId, byId: byId, best: best) else { return PickerRowModel.keptPick(id: l.entryId, ticked: l.ticked, screen: .pvp, ctx: ctx)?.adding(copy: ctx.entry(l.entryId), strength: leagueScore(ctx.entry(l.entryId)?.row.speciesId ?? "")) }
            if let r = m.notOwned {
                return PickerRowModel(best: r, ticked: l.ticked, role: r.roles.isEmpty ? nil : r.roles.joined(separator: " · ")).adding(copy: r.inBox ? (r.copy ?? r.ownedEntryId.flatMap(ctx.entry)) : nil, strength: leagueScore(r.speciesId))
            }
            return fallbackRow(l.entryId, m, ticked: l.ticked)
        }
        let rows: [PickerRowModel] = mode == .available
            ? PickerRowModel.availableGroups(own: listed.compactMap(model), other: listedOther.compactMap(model))
            : listed.compactMap(model)
        return Content(rows: PickerRowModel.marking(rows, moves: held.moves) { held.swap[$0] }, boxHasOptions: boxHasOptions, speciesRuleOnly: speciesRuleOnly)
    }

    /// The squad's strength bar (rule 32): each slot's figure is the Score its Pokémon shows as a row in that slot's picker, so it is read from that row (built alone), over the
    /// Best squad's Scores (`reference`). A Score is already of the built option, so the bar has no faint part; a Pokémon with no Score in the league is left out ("score not known").
    func squadStrength(filled: [FilledSlot], candidates: [HubSquads.PvpCandidate], byId: [String: HubSquads.PvpCandidate], best: [HubSquads.BestRow], mode: SquadMode) -> SquadStrength {
        SquadStrength.against(figures: filled.indices.map { i in
            guard filled[i].pickId != nil else { return nil }
            let rows = content(slot: i, filled: filled, candidates: candidates, byId: byId, best: best, mode: mode, only: HubSquads.tickIds(filled[i], rows: best)).rows
            return rows.first(where: \.ticked)?.strength ?? Strength.scoreNotKnown
        }, reference: reference(), kind: .score)
    }

    /// The league's Best squad (unedited): the Score of each slot's Pokémon in the league.
    func reference() -> [Double?] {
        let rows = HubSquads.bestPvpRows(league: league, pogoAssist: pogoAssist, ctx: ctx)
        let best = PvPPlacement.squad(slots: HubSquads.resolvingSpecies(HubSquads.defaultPvpSlots(), rows: rows), pool: { HubSquads.pool(role: $0, in: rows) }, all: rows.map(\.entryId),
                                      placeable: { _, _ in true }, species: { speciesId($0) })
        return best.map { f in
            guard let id = f.pickId, let r = rows.first(where: { $0.entryId == id || $0.ids.contains(id) }) else { return nil }
            return leagueScore(r.speciesId).now
        }
    }

    /// The bar of a Pokémon with no league rating of the player's own: PvPoke's score for the species in this league (the same 0 to 100 scale), else no bar and "score not known".
    func leagueScore(_ speciesId: String) -> Strength {
        (try? PvpScores.bundled()).flatMap { $0.score(speciesId: speciesId, league: league) }.map(Strength.score) ?? .scoreNotKnown
    }

    /// A row for a Pokémon that is in a slot but not on the candidate list, read from its own league rating.
    func fallbackRow(_ id: String, _ m: Member, ticked: Bool) -> PickerRowModel {
        let score = m.option?.strength?.score
        let roles = (m.option.map { o in HubSquads.PvpRole.allCases.filter(ctx.table.entries(for: o.speciesId, area: league).flatMap { HubSquads.pvpRoles($0.role ?? "") }.contains) } ?? []).map(\.rawValue).joined(separator: " · ")
        let iv = m.option?.iv.map { "#\(LeaguePanel.grouped($0.rank)) · \(LeaguePanel.oneDecimal($0.pct))%" } ?? "IVs not read"
        let grade = MyPokemon.rankGrade(m.option?.iv?.rank)
        let scoreText = score.map(LeaguePanel.oneDecimal) ?? "—"
        let sGrade = MyPokemon.scoreGrade(score)
        let tier = m.tier
        let spoken = [m.name, roles, tier.isEmpty ? nil : "tier \(tier)", m.mark.spoken, "IV " + iv.replacingOccurrences(of: "#", with: "rank "), "score \(scoreText)", ticked ? "in this slot" : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let model = PickerRowModel(
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
        return model.adding(copy: ctx.entry(id), strength: score.map(Strength.score) ?? .scoreNotKnown, speaksStrength: false)
    }

    func row(_ pc: HubSquads.PvpCandidate, ticked: Bool, status: String? = nil) -> PickerRowModel {
        let c = pc.candidate
        let tier = HubSquads.pvpTier(speciesId: c.speciesId, league: league, score: c.score)
        let types = ctx.gm.byId[c.speciesId]?.types ?? []
        let mark = SquadMark.of(c)
        let score = LeaguePanel.oneDecimal(c.score), scoreGrade = MyPokemon.scoreGrade(c.score), rankGrade = MyPokemon.rankGrade(c.ivRank)
        let roles = pc.roles.map(\.rawValue).joined(separator: " · ")
        let spoken = [c.displayName, roles, tier.isEmpty ? nil : "tier \(tier)", mark.spoken, status?.replacingOccurrences(of: " · ", with: ", "), c.fromText, "IV " + c.subText.replacingOccurrences(of: "#", with: "rank "),
                      "score \(score)" + (scoreGrade.spoken.isEmpty ? "" : ", \(scoreGrade.spoken) pick"), ticked ? "in this slot" : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let model = PickerRowModel(
            id: c.entryId, name: c.displayName, ticked: ticked, mark: mark, role: roles.isEmpty ? nil : roles, tier: tier, types: types.map { PickerType(type: $0) },
            noteView: AnyView(VStack(alignment: .leading, spacing: 2) {
                if let status { Text(status).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                Self.ivLine(c, grade: rankGrade)
            }),
            figure: AnyView(VStack(alignment: .trailing, spacing: 0) {
                GradedNumber(score, scoreGrade, size: 14, plain: .heavy, relativeTo: .subheadline)
                Text("SCORE").font(.figtree(10, .bold, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.muted)
            }.fixedSize()),
            spoken: spoken)
        return model.adding(copy: ctx.entry(c.entryId), strength: Strength.score(c.score), speaksStrength: false)
    }

    /// "From Eevee · #528 · 96.8%", the IV part graded by its rank.
    static func ivLine(_ c: HubTeams.Candidate, grade: MyPokemon.Grade) -> some View {
        HStack(spacing: 4) {
            if let from = c.fromText { Text(from + " ·").font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted) }
            GradedNumber(c.subText, grade, size: 12, plain: .regular, relativeTo: .caption).foregroundStyle(grade == .plain ? Theme.muted : Theme.greenInk)
        }
    }

    /// Every slot's picker rows for the league's default squad under `mode` (what a test reads).
    func allSlotRows(mode: SquadMode) -> [[PickerRowModel]] {
        let r = resolve(mode: mode, slots: HubSquads.defaultPvpSlots())
        return r.filled.indices.map { content(slot: $0, filled: r.filled, candidates: r.candidates, byId: r.byId, best: r.best, mode: mode).rows }
    }
}


struct PvPSquadView: View {
    let league: String
    let ctx: HubContext
    @ObservedObject var keeper: SquadKeeper
    @ObservedObject var workspace: SquadWorkspace
    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue
    @Environment(\.accent) private var accent
    @State private var selected: Int?
    @State private var showAll = false
    @State private var squadInfo = false

    /// The other candidates listed before "All N" is tapped.
    private let preview = 5
    private let chips = HubSquads.PvpRole.allCases.map(\.rawValue) + [squadRoleAll]

    var body: some View {
        let ref = SquadRef.pvp(league: league)
        let base = workspace.surface(ref, store: keeper.store, defaults: HubSquads.defaultPvpSlots())
        let mode = base.mode
        let pogoAssist = rankingRaw == Ranking.pogoAssist.rawValue
        let builder = builder(kept: base.kept)
        let (candidates, best, filled, byId) = builder.resolve(mode: mode, slots: base.squad.slots)
        let surface = base.with(edited: base.isEdited(filled: filled, suggested: { builder.resolve(mode: mode, slots: HubSquads.defaultPvpSlots()).filled }))
        SquadTabsRow(tab: Binding(get: { surface.tab }, set: { workspace.select($0, ref: ref, keeper: keeper) }), hasCurrent: surface.hasCurrent, noun: "squads")
        if candidates.isEmpty && mode == .available {
            // The squad still shows, with its empty slots.
            Text("No \(LeaguePanel.name(league)) candidate in your box scores \(Int(HubTeams.candidateFloor)) or more.")
                .font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("hub-pvp-none")
        }
        squad(filled: filled, candidates: candidates, byId: byId, best: best, surface: surface, pogoAssist: pogoAssist, builder: builder)
        if let i = selected, filled.indices.contains(i) { picker(i, filled: filled, candidates: candidates, byId: byId, best: best, surface: surface, pogoAssist: pogoAssist, builder: builder) }
        others(candidates: candidates, filled: filled)
    }

    typealias Member = PvPPickerBuilder.Member
    private func builder(kept: Bool) -> PvPPickerBuilder { PvPPickerBuilder(league: league, ctx: ctx, pogoAssist: rankingRaw == Ranking.pogoAssist.rawValue, kept: kept) }
    @State private var rowsCache = PickerRowsCache<PvPPickerBuilder.Content>()
    @State private var strength: (key: String, value: SquadStrength)?
    @State private var boxGeneration = 0

    private func types(_ speciesId: String) -> [String] { builder(kept: false).types(speciesId) }
    private func member(_ id: String, byId: [String: HubSquads.PvpCandidate], best: [HubSquads.BestRow], pogoAssist: Bool) -> Member? { builder(kept: false).member(id, byId: byId, best: best) }

    // MARK: the squad

    @ViewBuilder private func squad(filled: [FilledSlot], candidates: [HubSquads.PvpCandidate], byId: [String: HubSquads.PvpCandidate], best: [HubSquads.BestRow], surface: SquadSurface, pogoAssist: Bool, builder: PvPPickerBuilder) -> some View {
        let mode = surface.mode
        let members = filled.map { f in f.pickId.flatMap { member($0, byId: byId, best: best, pogoAssist: pogoAssist) } }
        let cards = filled.enumerated().map { card($0.offset, $0.element, member: members[$0.offset]) }
        // The types the squad hits for more than normal damage, over every member named in a slot (shown, not used to pick: D57).
        let mine = Array(Set(members.compactMap { $0 }.flatMap(\.types)))
        let covered = HubData.typeOrder.filter { ctx.hub.beats(mine, [$0]) }.count
        let named = members.compactMap { $0 }
        let rest = candidates.filter { c in !filled.contains { $0.entryId == c.entryId } }.map(\.candidate)
        // Worked out off the main thread (`.task` below), once for the squad as drawn; the bar fills in when it is ready.
        let strengthKey = "strength|\(league)|\(pogoAssist)|\(surface.tab.rawValue)|\(surface.isBestSuggestion)|" + FilledSlot.cacheKey(filled) + "|" + (mode == .best ? best.map(\.entryId) : candidates.map(\.entryId)).joined(separator: ",") + "|\(ctx.today)|\(boxGeneration)"
        let adoptKey = surface.squad.needsAdopting(filled) ? FilledSlot.cacheKey(filled) : ""
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
                if let team = HubSquads.teamStatus(cards.map(\.status)) { SquadStatusLine(status: team) }
                SquadStrengthLine(strength: strength?.key == strengthKey ? strength?.value : nil, type: .pvp)
                SlotGrid(slots: cards, selected: selected) { i in
                    withAnimation(.easeOut(duration: 0.15)) { selected = selected == i ? nil : i }
                }
                if surface.tab == .current {
                    DeleteCurrentButton { workspace.deleteCurrent(surface, keeper: keeper) }
                } else {
                    SquadDraftBar(differs: surface.differs, justSaved: surface.justSaved, replaces: surface.replaces(filled: filled),
                                  onSave: { workspace.saveToCurrent(surface, keeper: keeper, filled: filled, setMark: false) }, onReset: { workspace.reset(surface) })
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .panelShadow()
            .squadStrip(cards: cards, selected: selected) { i in withAnimation(.easeOut(duration: 0.15)) { selected = i } }
            .task(id: strengthKey) {
                let b = builder
                let bestUnedited = surface.isBestSuggestion
                let value = await Task.detached(priority: .userInitiated) {
                    bestUnedited ? SquadStrength.bestSquad(reference: b.reference(), kind: .score) : b.squadStrength(filled: filled, candidates: candidates, byId: byId, best: best, mode: mode)
                }.value
                if !Task.isCancelled { strength = (strengthKey, value) }
            }
            .tracksBox(ctx, generation: $boxGeneration)
            // A slot of a changed squad that refilled is kept as shown, so it does not change again.
            .task(id: adoptKey) {
                if !adoptKey.isEmpty, !Task.isCancelled { workspace.edit(surface, keeper: keeper) { $0.adoptRefills(filled) } }
            }
            let note = weakness(named, rest: rest)
            if !note.isEmpty {
                Text(note).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.horizontal, 4).accessibilityIdentifier("hub-pvp-weakness")
            }
        }
    }

    /// The weakness line over the members the squad shows (the set the coverage uses). When every member is a candidate the engine's note, with its swap suggestion,
    /// is used; a kept pick that is not a candidate cannot be swapped by it, so the line is then the shared weaknesses alone.
    private func weakness(_ named: [Member], rest: [HubTeams.Candidate]) -> String {
        guard named.count > 1 else { return "" }
        if named.allSatisfy({ $0.candidate != nil }) { return HubTeams.weaknessNote(team: named.compactMap(\.candidate), candidates: rest, gm: ctx.gm, hub: ctx.hub) }
        return PvPPlacement.sharedWeakness(memberTypes: named.map(\.types), hub: ctx.hub)
    }

    private func card(_ i: Int, _ f: FilledSlot, member m: Member?) -> SlotCardModel {
        let palette = SquadPalette.of(f.role)
        let head = "Slot \(i + 1) of 3, \(f.role)"
        let id = "hub-pvp-slot-\(i + 1)"
        guard let m else {
            return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: nil, lines: ["No candidate"], status: .empty, spoken: head + ", " + HubSquads.SlotStatus.empty.spoken, identifier: id)
        }
        if let r = m.notOwned { return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", best: r, head: head, identifier: id) }
        // Rule 29: the league tier shown everywhere (the table's, else the 88-score band), the same under Available and Best.
        let status = HubSquads.slotStatus(inBox: true, fullStrength: m.mark == .fullStrength, tier: m.tier)
        // A slot filled from another role says which role the Pokémon is listed for (S1); under Best the row's one status shows.
        let other = f.fallback && !f.chosen && m.candidate != nil ? SquadWords.otherRoleLine(m.roles) : nil
        let shared = m.bestRow?.statusLine
        let spoken = [head, m.name, other, SquadWords.typeList(m.types), m.mark.spoken, m.bestRow?.spokenStatus, status.spoken].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: m.name, lines: [other, shared].compactMap { $0 }, types: m.types, mark: m.mark, status: status, spoken: spoken, identifier: id)
    }

    // MARK: picker

    private func picker(_ i: Int, filled: [FilledSlot], candidates: [HubSquads.PvpCandidate], byId: [String: HubSquads.PvpCandidate], best: [HubSquads.BestRow], surface: SquadSurface, pogoAssist: Bool, builder: PvPPickerBuilder) -> some View {
        let role = filled[i].role
        let mode = surface.mode
        // The rows are built once and kept until the box, the advice or what the slot sees changes.
        let key = "\(league)|\(pogoAssist)|\(surface.tab.rawValue)|\(i)|" + FilledSlot.cacheKey(filled) + "|" + (mode == .best ? best.map(\.entryId) : candidates.map(\.entryId)).joined(separator: ",")
        let content = rowsCache.get(ctx: ctx, key: key) { builder.content(slot: i, filled: filled, candidates: candidates, byId: byId, best: best, mode: mode) }
        let rows = content.rows, boxHasOptions = content.boxHasOptions, speciesRuleOnly = content.speciesRuleOnly
        return SquadPicker(
            title: "Slot \(i + 1) · \(role)", type: .pvp, roles: chips, role: role,
            onRole: { new in workspace.edit(surface, keeper: keeper) {
                $0.changeRole(at: i, to: new, fits: {
                    // A kept species pick (Current) fits when the league's Best lists it for the new role, as on the other screens; `best` holds only those rows under Current.
                    mode == .best ? HubSquads.fits($0, role: new, in: best) : HubSquads.fits($0, role: new, in: candidates) || HubSquads.fits($0, role: new, in: best)
                }, shown: filled)
            } },
            rows: rows, emptyText: SquadWords.emptyPicker(mode: mode, boxHasOptions: boxHasOptions, speciesRuleOnly: speciesRuleOnly, none: mode == .available ? "No candidate in your box for this role." : "No Pokémon listed for this role."),
            onChoose: { id in workspace.edit(surface, keeper: keeper) {
                $0.choose(id, at: i, alsoClearing: HubSquads.equivalents(of: id, rows: HubSquads.bestPvpRows(league: league, pogoAssist: pogoAssist, ctx: ctx)), shown: filled)
            } },
            onDone: { withAnimation(.easeOut(duration: 0.15)) { selected = nil } },
            info: {
                if mode == .best {
                    SquadExplainer(items: [
                        ("Ranked from our league table:", "every Pokémon it lists for the league, S then A then B, in the table's order, whether or not you have it. Each says whether you have it, can get it now, or cannot, with the date when the schedule has one."),
                        ("Roles", "come from our league table's role column: lead, safe swap or switch, closer."),
                        ("Green numbers", "mark a top pick (boxed: score 92 or more, or an IV rank in the top 100) and a good pick (green: score 90 or more, or an IV rank in the top 500)."),
                    ], identifier: "squad-picker-explainer")
                } else {
                    SquadExplainer(items: [
                        ("Best first:", "the higher league score (our PvPoke-based score for this copy in this league)."),
                        ("Roles", "come from our league table's role column: lead, safe swap or switch, closer."),
                        ("Green numbers", "mark a top pick (boxed: score 92 or more, or an IV rank in the top 100) and a good pick (green: score 90 or more, or an IV rank in the top 500)."),
                    ], identifier: "squad-picker-explainer")
                }
            })
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
                PvPPickerBuilder.ivLine(c, grade: rankGrade)
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
