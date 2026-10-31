import SwiftUI
import PogoBox

/// Gym battles (design pass 2): SUGGESTIONS · Available | Best, the six Top defenders as slot cards that each open a picker, then GYM BUILDS and the Gym gaps. The
/// defenders the player picked are kept per account (`SquadKeeper`); a slot with no pick shows the suggestion.
struct HubGymView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var keeper = SquadKeeper()

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .gym)) }
        return HubTypeScreen(type: .gym, count: count) {
            if let ctx = model.squadContext() {
                GymSquadView(ctx: ctx, keeper: keeper)
            } else {
                HubAdviceGate { _ in EmptyView() }
            }
        }
        .keepsSquads(keeper)
    }
}

/// A defender a slot may take: one of the player's builds (with its bulk row) or, under Best, a Pokémon the box lacks.
private struct GymOption {
    let id: String
    let name: String
    let tier: String
    let types: [String]
    let row: HubSquads.GymRow?
    let best: HubSquads.BestRow?
}

private struct GymSquadView: View {
    let ctx: HubContext
    @ObservedObject var keeper: SquadKeeper
    @State private var selected: Int?
    @Environment(\.accent) private var accent

    /// The defenders the screen may use under `mode` (Available: the player's own Gym builds; Best: the Gym table, owned or not) and the six slots filled from them.
    private func resolve(mode: SquadMode, saved: SquadStore.Saved) -> (options: [GymOption], candidates: [HubSquads.BestRow], filled: [FilledSlot]) {
        if mode == .best {
            let rows = HubSquads.bestGymRows(ctx: ctx)
            let options = rows.map { r in GymOption(id: r.entryId, name: r.name, tier: r.tier, types: r.types, row: r.build.map { HubSquads.gymRow($0, ctx: ctx) }, best: r) }
            return (options, rows, HubSquads.bestSquad(slots: saved.slots, rows: rows))
        }
        let rows = HubSquads.gymRows(mode: mode, ctx: ctx)
        let options = rows.map { GymOption(id: $0.build.entryId, name: $0.build.targetName, tier: HubSquads.gymTableTier($0.build, ctx: ctx), types: ctx.gm.byId[$0.build.targetId]?.types ?? [], row: $0, best: nil) }
        return (options, [], HubSquads.gymSquad(slots: saved.slots, rows: rows, placeable: HubSquads.placeable(screen: .gym, mode: mode, ctx: ctx)))
    }

    var body: some View {
        let mode = keeper.store.mode(for: .gym)
        let (options, _, filled) = resolve(mode: mode, saved: keeper.store.gym)
        let byId = Dictionary(options.flatMap { o in [(o.id, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        let cards = filled.enumerated().map { card($0.offset, $0.element, byId: byId) }
        SuggestionsRow(mode: Binding(get: { mode }, set: { m in keeper.update { $0.setMode(m, for: .gym) } }), noun: "defenders")
        VStack(alignment: .leading, spacing: 10) {
            Text("Top defenders").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            if let team = HubSquads.teamStatus(cards.map(\.status)) { SquadStatusLine(status: team) }
            SlotGrid(slots: cards, selected: selected) { i in
                withAnimation(.easeOut(duration: 0.15)) { selected = selected == i ? nil : i }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
        if let i = selected, filled.indices.contains(i) { picker(i, filled: filled, options: options, byId: byId, mode: mode) }
        builds
        HubGapList(gaps: HubModel.gaps(ctx.advice.gaps, for: .gym), type: .gym)
    }

    // MARK: slots

    private func card(_ i: Int, _ f: FilledSlot, byId: [String: GymOption]) -> SlotCardModel {
        let palette = SquadPalette(ink: ContentType.gym.ink(accent), tint: ContentType.gym.tint(accent))
        let id = "hub-gym-slot-\(i + 1)"
        let head = "Slot \(i + 1) of 6"
        guard let pick = f.pickId else {
            return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: nil, status: .empty, spoken: head + ", " + HubSquads.SlotStatus.empty.spoken, identifier: id)
        }
        guard let o = (f.species.flatMap { byId[squadSpeciesPrefix + $0] } ?? byId[pick]) else {
            if let key = f.species {
                let name = ctx.gm.byId[key]?.name ?? "Pokémon"
                return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: name, lines: [HubSquads.BestStatus.unlisted.text], types: ctx.gm.byId[key]?.types ?? [], status: .toGet,
                                     spoken: [head, name, HubSquads.BestStatus.unlisted.text.replacingOccurrences(of: " · ", with: ", "), HubSquads.SlotStatus.toGet.spoken].joined(separator: ", "), identifier: id)
            }
            let name = ctx.entry(pick)?.row.title ?? "Pokémon"
            return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: name, types: ctx.entryTypes(pick), status: .needsWork,
                                 spoken: [head, name, HubSquads.SlotStatus.needsWork.spoken].joined(separator: ", "), identifier: id)
        }
        guard let r = o.row, o.best?.hasBuild != false else {
            return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), best: o.best!, head: head, identifier: id)
        }
        let mark = SquadMark.of(r.build, screen: .gym, ctx: ctx)
        // Rule 29: the Gym table's tier, not the build's own (a Pokémon the table does not list needs work).
        let status = HubSquads.slotStatus(inBox: true, fullStrength: mark == .fullStrength, tier: HubSquads.gymTableTier(r.build, ctx: ctx))
        let line = GymFigures.bulkLine(r)
        let shared = o.best?.statusLine
        let lines = (line.isEmpty ? [] : [line]) + (shared.map { [$0] } ?? [])
        let spoken = [head, o.name, SquadWords.typeList(o.types), line, mark.spoken, o.best?.spokenStatus, status.spoken].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: o.name, lines: lines, types: o.types, mark: mark, status: status, spoken: spoken, identifier: id)
    }

    // MARK: picker

    private func picker(_ i: Int, filled: [FilledSlot], options: [GymOption], byId: [String: GymOption], mode: SquadMode) -> some View {
        var ids = options.map(\.id)
        let boxHasOptions = !ids.isEmpty
        let bestRows = options.compactMap(\.best)
        let copyOf = HubSquads.copyResolver(rows: bestRows)
        let ticks = HubSquads.tickIds(filled[i], rows: bestRows)
        if let own = ticks.first ?? filled[i].pickId, ticks.isDisjoint(with: ids) { ids.insert(own, at: 0) }
        let listed = HubSquads.picker(candidates: ids, excluded: HubSquads.excluded(by: filled, editing: i, onlyChosen: false, copyOf: copyOf), ownIds: ticks, copyOf: copyOf)
        var models: [PickerRowModel] = listed.compactMap { l in
            guard let o = byId[l.entryId] else { return PickerRowModel.keptPick(id: l.entryId, ticked: l.ticked, screen: .gym, ctx: ctx) }
            guard let r = o.row, o.best?.hasBuild != false else { return PickerRowModel(best: o.best!, ticked: l.ticked) }
            let shared = o.best?.statusLine
            let mark = SquadMark.of(r.build, screen: .gym, ctx: ctx)
            let stats = GymFigures.stats(r, ctx: ctx)
            let level = r.level.map { "at level \(GymFigures.levelText($0))" }
            var spoken = [o.name, "tier \(o.tier)", SquadWords.typeList(o.types), mark.spoken, o.best?.spokenStatus].compactMap { $0 }
            if let stats { spoken.append("Defence \(stats.def), HP \(stats.hp)") }
            spoken.append(GymFigures.bulkLine(r))
            if let level { spoken.append(level) }
            if l.ticked { spoken.append("in this slot") }
            return PickerRowModel(
                id: l.entryId, name: o.name, ticked: l.ticked, mark: mark, tier: o.tier, types: o.types.map { PickerType(type: $0) },
                note: [stats == nil ? GymFigures.bulkLine(r) : nil, shared].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty,
                stats: stats.map { AnyView(GymStatsColumn(def: $0.def, hp: $0.hp)) },
                figure: stats == nil ? nil : AnyView(GymBulkFigure(text: GymFigures.bulkShort(r.bulk))),
                spoken: spoken.joined(separator: ", "))
        }
        if mode == .available { models = PickerRowModel.availableUpgradesLast(models) }
        return SquadPicker(
            title: "Slot \(i + 1) · \(HubSquads.gymSlotRole)", type: .gym, rows: models,
            emptyText: SquadWords.emptyPicker(mode: mode, boxHasOptions: boxHasOptions, none: mode == .available ? "No Gym build in your box." : "No Gym defender listed."),
            onChoose: { id in keeper.update { $0.gym.choose(id, at: i, alsoClearing: HubSquads.equivalents(of: id, rows: HubSquads.bestGymRows(ctx: ctx))) } },
            onDone: { withAnimation(.easeOut(duration: 0.15)) { selected = nil } },
            info: {
                if mode == .best {
                    SquadExplainer(items: [
                        ("Ranked from our gym table:", "every defender it lists, S then A then B, in the table's order, whether or not you have it. Each says whether you have it, can get it now, or cannot, with the date when the schedule has one."),
                        ("", "Ones you have show your best copy and the work it needs, with its bulk: Defence × HP with its own IVs."),
                    ], identifier: "squad-picker-explainer")
                } else {
                    SquadExplainer(items: [
                        ("Best defenders first:", "the tier our gym table gives it, then this copy's bulk: its Defence × HP with its own IVs, at the level its build reaches (its level now if nothing is left to do)."),
                        ("", "Bulk is how long it lasts against attackers. Defence and HP count equally. CP is left out: it is mostly Attack, and high CP makes a defender lose motivation faster."),
                        ("", "A copy whose level the scan did not read comes after the others in its tier and reads level not read: no level is assumed."),
                    ], identifier: "squad-picker-explainer")
                }
            })
    }

    // MARK: GYM BUILDS

    @ViewBuilder private var builds: some View {
        let all = HubTeams.gymAvailable(builds: ctx.advice.builds)
        HubHeaderLine("GYM BUILDS")
        if all.isEmpty {
            Text("The advisor has no Gym build in your box.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        } else {
            GymBuildList(builds: all)
        }
    }
}

// MARK: figures

enum GymFigures {
    /// "49k" for 49,300; "980" under a thousand.
    static func bulkShort(_ b: PogoRules.Bulk) -> String {
        guard let v = b.value else { return "" }
        return v >= 1000 ? "\(Int((v / 1000).rounded()))k" : "\(Int(v.rounded()))"
    }

    /// The bulk as a line: "49k bulk", or why there is none ("level not read", "IVs not read").
    static func bulkLine(_ r: HubSquads.GymRow) -> String {
        switch r.bulk {
        case .known: return "\(bulkShort(r.bulk)) bulk"
        case .levelNotRead: return "level not read"
        case .ivsNotRead: return "IVs not read"
        case .unknownSpecies: return ""
        }
    }

    static func levelText(_ level: Double) -> String { level == level.rounded() ? String(Int(level)) : String(level) }

    /// The Defence and HP the bulk was worked from, as the game shows them at that level; nil when the bulk is not known.
    static func stats(_ r: HubSquads.GymRow, ctx: HubContext) -> (def: Int, hp: Int)? {
        guard r.bulk.isKnown, let level = r.level, let m = PogoRules.cpm(level), let base = ctx.gm.byId[r.build.targetId]?.baseStats, let ivs = ctx.entry(r.build.entryId)?.row.ivs else { return nil }
        return (Int((Double(base.def + ivs.def) * m).rounded()), Int((Double(base.hp + ivs.hp) * m).rounded(.down)))
    }
}

/// "153 DEF" over "429 HP".
private struct GymStatsColumn: View {
    let def: Int
    let hp: Int
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            stat(def, "DEF")
            stat(hp, "HP")
        }
        .fixedSize()
    }
    private func stat(_ n: Int, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text("\(n)").font(.figtree(12, .heavy, relativeTo: .caption)).monospacedDigit().foregroundStyle(Theme.ink)
            Text(label).font(.figtree(10, .bold, relativeTo: .caption2)).foregroundStyle(Theme.muted)
        }
    }
}

/// "49k" over BULK.
private struct GymBulkFigure: View {
    let text: String
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(text).font(.figtree(14, .heavy, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink)
            Text("BULK").font(.figtree(10, .bold, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.muted)
        }
        .fixedSize()
        .frame(minWidth: 40, alignment: .trailing)
    }
}

// MARK: the build list

/// The Gym's build list (rule 15): rank, name and tier, what to do, where it counts; a built row carries the Full strength badge in place of the cost figure and its
/// sub line drops " · Free". A row opens the Pokémon's page.
private struct GymBuildList: View {
    let builds: [BoxAdvice.Build]
    @Environment(\.accent) private var accent

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(builds.enumerated()), id: \.element.id) { i, b in
                NavigationLink(value: b.entryId) { row(i, HubSquads.buildRow(b)) }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("hub-build-row")
                if i < builds.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
    }

    private func row(_ i: Int, _ r: HubSquads.BuildRow) -> some View {
        let b = r.build
        let lit = i == 0
        return HStack(spacing: 12) {
            Text(verbatim: String(i + 1)).font(.figtree(13, .heavy, relativeTo: .footnote)).monospacedDigit()
                .foregroundStyle(lit ? Color.white : Theme.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(lit ? ContentType.gym.solid(accent) : Theme.surface2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(b.title).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineLimit(2)
                    TierChip(tier: b.tier, type: .gym)
                }
                Text(b.action).font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                Text(r.subLine).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if r.showsFullStrength {
                FullStrengthBadge(size: 26)
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(r.cost.value ?? "Free").font(.figtree(14, .heavy, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink)
                    if r.cost.currency != .free { Text(r.cost.currency == .dust ? "DUST" : "CANDY").font(.figtree(10, .bold, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.muted) }
                }
            }
            Image(systemName: "chevron.right").font(.figtree(13, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(i + 1). \(b.title), tier \(b.tier). \(b.action). \(r.subLine)")
        .accessibilityValue(r.showsFullStrength ? "Full strength" : (r.cost.value.map { "\($0) \(r.cost.currency == .dust ? "dust" : "candy")" } ?? "Free"))
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
