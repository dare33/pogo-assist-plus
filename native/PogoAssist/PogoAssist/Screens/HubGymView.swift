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
        .accessibilityIdentifier("hub-screen-gym")
    }
}

private struct GymSquadView: View {
    let ctx: HubContext
    @ObservedObject var keeper: SquadKeeper
    @State private var selected: Int?
    @Environment(\.accent) private var accent

    var body: some View {
        let mode = keeper.store.mode(for: .gym)
        let saved = keeper.store.gym
        let rows = HubSquads.gymRows(mode: mode, ctx: ctx)
        let filled = HubSquads.gymSquad(slots: saved.slots, rows: rows, placeable: HubSquads.placeable(screen: .gym, mode: mode, ctx: ctx))
        let byId = Dictionary(rows.map { ($0.build.entryId, $0) }, uniquingKeysWith: { a, _ in a })
        SuggestionsRow(mode: Binding(get: { mode }, set: { m in keeper.update { $0.setMode(m, for: .gym) } }), noun: "defenders")
        VStack(alignment: .leading, spacing: 10) {
            Text("Top defenders").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            SlotGrid(slots: filled.enumerated().map { card($0.offset, $0.element, byId: byId) }, selected: selected) { i in
                withAnimation(.easeOut(duration: 0.15)) { selected = selected == i ? nil : i }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
        if let i = selected, filled.indices.contains(i) { picker(i, filled: filled, rows: rows, byId: byId) }
        builds
        HubGapList(gaps: HubModel.gaps(ctx.advice.gaps, for: .gym), type: .gym)
    }

    // MARK: slots

    private func card(_ i: Int, _ f: FilledSlot, byId: [String: HubSquads.GymRow]) -> SlotCardModel {
        let palette = SquadPalette(ink: ContentType.gym.ink(accent), tint: ContentType.gym.tint(accent))
        let id = "hub-gym-slot-\(i + 1)"
        guard let entryId = f.entryId else {
            return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: nil, spoken: "Slot \(i + 1) of 6, empty", identifier: id)
        }
        guard let r = byId[entryId] else {
            let name = ctx.entry(entryId)?.row.title ?? "Pokémon"
            return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: name, spoken: "Slot \(i + 1) of 6, \(name)", identifier: id)
        }
        let types = ctx.gm.byId[r.build.targetId]?.types ?? []
        let mark = SquadMark.of(r.build, screen: .gym, ctx: ctx)
        let line = GymFigures.bulkLine(r)
        let spoken = ["Slot \(i + 1) of 6", r.build.targetName, SquadWords.typeList(types), line, mark.spoken].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: r.build.targetName, lines: line.isEmpty ? [] : [line], types: types, mark: mark, spoken: spoken, identifier: id)
    }

    // MARK: picker

    private func picker(_ i: Int, filled: [FilledSlot], rows: [HubSquads.GymRow], byId: [String: HubSquads.GymRow]) -> some View {
        let listed = HubSquads.picker(candidates: rows.map { $0.build.entryId }, excluded: HubSquads.excluded(by: filled, editing: i, onlyChosen: false), own: filled[i].entryId)
        let models: [PickerRowModel] = listed.compactMap { l in
            guard let r = byId[l.entryId] else { return nil }
            let types = ctx.gm.byId[r.build.targetId]?.types ?? []
            let mark = SquadMark.of(r.build, screen: .gym, ctx: ctx)
            let stats = GymFigures.stats(r, ctx: ctx)
            let level = r.level.map { "at level \(GymFigures.levelText($0))" }
            var spoken = [r.build.targetName, "tier \(r.tier)", SquadWords.typeList(types), mark.spoken].compactMap { $0 }
            if let stats { spoken.append("Defence \(stats.def), HP \(stats.hp)") }
            spoken.append(GymFigures.bulkLine(r))
            if let level { spoken.append(level) }
            if l.ticked { spoken.append("in this slot") }
            return PickerRowModel(
                id: l.entryId, name: r.build.targetName, ticked: l.ticked, mark: mark, tier: r.tier, types: types.map { PickerType(type: $0) },
                note: stats == nil ? GymFigures.bulkLine(r) : nil,
                stats: stats.map { AnyView(GymStatsColumn(def: $0.def, hp: $0.hp)) },
                figure: stats == nil ? nil : AnyView(GymBulkFigure(text: GymFigures.bulkShort(r.bulk))),
                spoken: spoken.joined(separator: ", "))
        }
        return SquadPicker(
            title: "Slot \(i + 1) · \(HubSquads.gymSlotRole)", type: .gym, rows: models, emptyText: "No Gym build in your box.",
            couldGet: HubSquads.gymCouldGet(ctx: ctx).map { CouldGetModel($0, types: ctx.gm.byId[$0.gap.speciesId ?? ""]?.types ?? []) },
            onChoose: { id in keeper.update { $0.gym.choose(id, at: i) } },
            onDone: { withAnimation(.easeOut(duration: 0.15)) { selected = nil } },
            info: {
                SquadExplainer(items: [
                    ("Best defenders first:", "the tier our gym table gives it, then this copy's bulk: its Defence × HP with its own IVs, at the level its build reaches (its level now if nothing is left to do)."),
                    ("", "Bulk is how long it lasts against attackers. Defence and HP count equally. CP is left out: it is mostly Attack, and high CP makes a defender lose motivation faster."),
                    ("", "A copy whose level the scan did not read comes after the others in its tier and reads level not read: no level is assumed."),
                ], identifier: "squad-picker-explainer")
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
