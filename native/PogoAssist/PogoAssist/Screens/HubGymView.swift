import SwiftUI
import PogoBox

/// Gym battles (design pass 2): SQUAD · Current | Available | Best, the six Top defenders as slot cards that each open a picker, then GYM BUILDS and the Gym gaps. The
/// defenders the player picked are kept per account (`SquadKeeper`); a slot with no pick shows the suggestion.
struct HubGymView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var keeper = SquadKeeper()
    @StateObject private var workspace = SquadWorkspace()

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .gym)) }
        return HubTypeScreen(type: .gym, count: count) {
            if let ctx = model.squadContext() {
                GymSquadView(ctx: ctx, keeper: keeper, workspace: workspace)
            } else {
                HubAdviceGate { _ in EmptyView() }
            }
        }
        .keepsSquads(keeper, workspace)
    }
}

/// A defender a slot may take: one of the player's builds (with its bulk row) or, under Best, a Pokémon the box lacks.
struct GymOption {
    let id: String
    let name: String
    let tier: String
    let types: [String]
    let row: HubSquads.GymRow?
    let best: HubSquads.BestRow?
    /// Current only: a Best row listed because a kept slot holds that species (so the slot is drawn as the Best row it is). Never offered by the picker.
    var extra = false
}

/// The rows of a Gym picker, built from the box and the tables alone (no view state), so a test can read what every picker would show.
struct GymPickerBuilder {
    let ctx: HubContext
    /// Drawing a Current squad (pass 2-5): no mode placement rule hides a kept pick, and a kept species pick is drawn as the Best row it is.
    var kept = false

    /// The defenders the screen may use under `mode` (Available: the player's own Gym builds; Best: the Gym table, owned or not) and the six slots filled from them.
    func resolve(mode: SquadMode, saved: SquadStore.Saved) -> (options: [GymOption], candidates: [HubSquads.BestRow], filled: [FilledSlot]) {
        if mode == .best {
            let rows = HubSquads.bestGymRows(ctx: ctx)
            let options = rows.map { r in GymOption(id: r.entryId, name: r.name, tier: r.tier, types: r.types, row: r.build.map { HubSquads.gymRow($0, ctx: ctx) }, best: r) }
            return (options, rows, HubSquads.bestSquad(slots: saved.slots, rows: rows))
        }
        let rows = HubSquads.gymRows(mode: mode, ctx: ctx)
        // Current: the Best rows of the squad's kept species picks. A kept species pick and an owned copy of it are the same Pokémon (no other slot refills with that copy).
        let keptSpecies = kept ? Set(saved.slots.compactMap(\.species)) : []
        let keptRows = keptSpecies.isEmpty ? [] : HubSquads.bestGymRows(ctx: ctx).filter { keptSpecies.contains($0.key) }
        var options = rows.map { GymOption(id: $0.build.entryId, name: $0.build.targetName, tier: HubSquads.gymTableTier($0.build, ctx: ctx), types: ctx.gm.byId[$0.build.targetId]?.types ?? [], row: $0, best: nil) }
        options += keptRows.map { r in
            GymOption(id: r.entryId, name: r.name, tier: r.tier, types: r.types, row: r.build.map { HubSquads.gymRow($0, ctx: ctx) }, best: r, extra: true)
        }
        return (options, [], HubSquads.gymSquad(slots: saved.slots, rows: rows, placeable: kept ? { _, _ in true } : HubSquads.placeable(screen: .gym, mode: mode, ctx: ctx),
                                                copyOf: HubSquads.copyResolver(rows: keptRows)))
    }

    struct Content { var rows: [PickerRowModel]; var boxHasOptions: Bool }

    /// `only` limits the rows to those ids and `bulk` is the best Gym bulk when the caller has worked it out: the squad strength bar needs one slot's own row, and its six slots share one hash.
    func content(slot i: Int, filled: [FilledSlot], options: [GymOption], byId: [String: GymOption], mode: SquadMode, only: Set<String>? = nil, bulk: Double? = nil) -> Content {
        var ids = options.filter { !$0.extra }.map(\.id)
        let boxHasOptions = !ids.isEmpty
        let bestRows = options.compactMap(\.best)
        let copyOf = HubSquads.copyResolver(rows: bestRows)
        let ticks = HubSquads.tickIds(filled[i], rows: bestRows)
        if let own = ticks.first ?? filled[i].pickId, ticks.isDisjoint(with: ids) { ids.insert(own, at: 0) }
        // A defender in another slot is listed, marked with its slot: choosing it swaps the two (rule 27).
        let held = HubSquads.otherSlots(of: filled, editing: i, copyOf: copyOf)
        let listed = HubSquads.picker(candidates: only.map { o in ids.filter(o.contains) } ?? ids, excluded: held.blocked, ownIds: ticks, copyOf: copyOf)
        // P1: the bar is the Bulk against the best Gym bulk in the game.
        // It hashes the whole game master, so it is worked out once for the picker, not once per row.
        let bestBulk = bulk ?? DamageEstimate.bestGymBulk(gm: ctx.gm)
        func bar(_ copy: BoxEntry?, _ row: HubSquads.GymRow?, species: String? = nil) -> Strength { DamageEstimate.gymStrength(copy: copy, row: row, speciesId: species, gm: ctx.gm, bestBulk: bestBulk) }
        var models: [PickerRowModel] = listed.compactMap { l in
            guard let o = byId[l.entryId] else {
                let copy = ctx.entry(l.entryId)
                return PickerRowModel.keptPick(id: l.entryId, ticked: l.ticked, screen: .gym, ctx: ctx)?.adding(copy: copy, strength: bar(copy, nil))
            }
            guard let r = o.row, o.best?.hasBuild != false else {
                let best = o.best!, copy = best.inBox ? (best.copy ?? best.ownedEntryId.flatMap(ctx.entry)) : nil
                return PickerRowModel(best: best, ticked: l.ticked).adding(copy: copy, strength: bar(copy, nil, species: best.speciesId))
            }
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
                spoken: spoken.joined(separator: ", ")).adding(copy: ctx.entry(r.build.entryId), strength: bar(ctx.entry(r.build.entryId), r))
        }
        if mode == .available { models = PickerRowModel.availableUpgradesLast(models) }
        return Content(rows: PickerRowModel.marking(models, moves: held.moves) { held.swap[$0] ?? copyOf($0).flatMap { held.swap[$0] } }, boxHasOptions: boxHasOptions)
    }

    /// The squad's strength bar (rule 32): each slot's figure is the Bulk its Pokémon shows as a row in that slot's picker, so it is read from that row (built alone), over the
    /// Best squad's full-build Bulk (`reference`).
    func squadStrength(filled: [FilledSlot], options: [GymOption], byId: [String: GymOption], mode: SquadMode) -> SquadStrength {
        let bestRows = options.compactMap(\.best), bulk = DamageEstimate.bestGymBulk(gm: ctx.gm)
        return SquadStrength.against(figures: filled.indices.map { i in
            guard filled[i].pickId != nil else { return nil }
            let rows = content(slot: i, filled: filled, options: options, byId: byId, mode: mode, only: HubSquads.tickIds(filled[i], rows: bestRows), bulk: bulk).rows
            return rows.first(where: \.ticked)?.strength ?? Strength(kind: .bulk, now: nil, after: nil)
        }, reference: reference(bulk: bulk), kind: .bulk)
    }

    /// The Gym's Best squad (unedited) with each slot at its full build: the Bulk of that Pokémon at level 50 with 15/15/15, whether or not the box holds a copy.
    func reference(bulk: Double? = nil) -> [Double?] {
        let rows = HubSquads.bestGymRows(ctx: ctx), best = HubSquads.bestSquad(slots: HubSquads.defaultGymSlots(), rows: rows)
        let bestBulk = bulk ?? DamageEstimate.bestGymBulk(gm: ctx.gm)
        return best.map { f in
            guard let id = f.pickId, let r = rows.first(where: { $0.entryId == id || $0.ids.contains(id) }) else { return nil }
            return DamageEstimate.gymStrength(copy: nil, row: nil, speciesId: r.speciesId, gm: ctx.gm, bestBulk: bestBulk).now
        }
    }

    /// Every slot's picker rows for the default squad under `mode` (what a test reads).
    func allSlotRows(mode: SquadMode) -> [[PickerRowModel]] {
        let (options, _, filled) = resolve(mode: mode, saved: SquadStore.Saved(slots: HubSquads.defaultGymSlots()))
        let byId = Dictionary(options.flatMap { o in [(o.id, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        return filled.indices.map { content(slot: $0, filled: filled, options: options, byId: byId, mode: mode).rows }
    }
}

struct GymSquadView: View {
    let ctx: HubContext
    @ObservedObject var keeper: SquadKeeper
    @ObservedObject var workspace: SquadWorkspace
    @State private var selected: Int?
    @Environment(\.accent) private var accent

    private func builder(kept: Bool) -> GymPickerBuilder { GymPickerBuilder(ctx: ctx, kept: kept) }
    @State private var rowsCache = PickerRowsCache<GymPickerBuilder.Content>()
    @State private var strength: (key: String, value: SquadStrength)?
    @State private var boxGeneration = 0

    var body: some View {
        let base = workspace.surface(.gym, store: keeper.store, defaults: HubSquads.defaultGymSlots())
        let mode = base.mode
        let builder = builder(kept: base.kept)
        let (options, _, filled) = builder.resolve(mode: mode, saved: base.squad)
        let surface = base.with(edited: base.isEdited(filled: filled, suggested: { builder.resolve(mode: mode, saved: SquadStore.Saved(slots: HubSquads.defaultGymSlots())).filled }))
        let byId = Dictionary(options.flatMap { o in [(o.id, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        let cards = filled.enumerated().map { card($0.offset, $0.element, byId: byId) }
        // Worked out off the main thread (`.task` below), once for the squad as drawn; the bar fills in when it is ready.
        let strengthKey = "strength|\(surface.tab.rawValue)|\(surface.isBestSuggestion)|" + FilledSlot.cacheKey(filled) + "|" + options.map(\.id).joined(separator: ",") + "|\(ctx.today)|\(boxGeneration)"
        let adoptKey = surface.squad.needsAdopting(filled) ? FilledSlot.cacheKey(filled) : ""
        SquadTabsRow(tab: Binding(get: { surface.tab }, set: { workspace.select($0, ref: .gym, keeper: keeper) }), hasCurrent: surface.hasCurrent, noun: "defenders")
        VStack(alignment: .leading, spacing: 10) {
            Text("Top defenders").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            if let team = HubSquads.teamStatus(cards.map(\.status)) { SquadStatusLine(status: team) }
            SquadStrengthLine(strength: strength?.key == strengthKey ? strength?.value : nil, type: .gym)
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
        .squadStrip(cards: cards, selected: selected, ink: ContentType.gym.ink(accent), tint: ContentType.gym.tint(accent)) { i in withAnimation(.easeOut(duration: 0.15)) { selected = i } }
        .task(id: strengthKey) {
            let b = builder
            let bestUnedited = surface.isBestSuggestion
            let value = await Task.detached(priority: .userInitiated) {
                bestUnedited ? SquadStrength.bestSquad(reference: b.reference(), kind: .bulk) : b.squadStrength(filled: filled, options: options, byId: byId, mode: mode)
            }.value
            if !Task.isCancelled { strength = (strengthKey, value) }
        }
        // A slot of a changed squad that refilled is kept as shown, so it does not change again.
        .task(id: adoptKey) { if !adoptKey.isEmpty, !Task.isCancelled { workspace.edit(surface, keeper: keeper) { $0.adoptRefills(filled) } } }
        .tracksBox(ctx, generation: $boxGeneration)
        if let i = selected, filled.indices.contains(i) { picker(i, filled: filled, options: options, byId: byId, surface: surface, builder: builder) }
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

    private func picker(_ i: Int, filled: [FilledSlot], options: [GymOption], byId: [String: GymOption], surface: SquadSurface, builder: GymPickerBuilder) -> some View {
        let mode = surface.mode
        // The rows are built once and kept until the box, the advice or what the slot sees changes.
        let key = "\(surface.tab.rawValue)|\(i)|" + FilledSlot.cacheKey(filled) + "|" + options.map(\.id).joined(separator: ",")
        let content = rowsCache.get(ctx: ctx, key: key) { builder.content(slot: i, filled: filled, options: options, byId: byId, mode: mode) }
        let models = content.rows, boxHasOptions = content.boxHasOptions
        return SquadPicker(
            title: "Slot \(i + 1) · \(HubSquads.gymSlotRole)", type: .gym, rows: models,
            emptyText: SquadWords.emptyPicker(mode: mode, boxHasOptions: boxHasOptions, none: mode == .available ? "No Gym build in your box." : "No Gym defender listed."),
            onChoose: { id in workspace.edit(surface, keeper: keeper) { $0.choose(id, at: i, alsoClearing: HubSquads.equivalents(of: id, rows: HubSquads.bestGymRows(ctx: ctx)), shown: filled) } },
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
