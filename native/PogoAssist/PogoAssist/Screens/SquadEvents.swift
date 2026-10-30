import SwiftUI
import PogoBox

// The raid and Max battle pieces (pass 2 README, "Raids" and "Max battles"): what an event says about itself, the raid card, the timeline row and the squad of an
// event with its picker. Raids' Now strip uses the card; Raids' Coming up and both Max segments use the row; both open into `EventSquadView`.

// MARK: what an event says about itself

/// A rotation row as the card and the list row both show it: dates, name, kind chip, readiness, BRING, and the advice line.
struct EventSummary {
    let entry: HubRaidsModel.Entry
    let screen: HubRaidsModel.Screen
    let name: String
    let chip: String
    let bring: [String]
    let dates: (dates: String, when: String)
    let ready: (built: Int, needed: Int, missing: [String])?
    let todo: String

    init(entry: HubRaidsModel.Entry, screen: HubRaidsModel.Screen, hub: HubData, gm: GameMaster, advice: BoxAdvice?, entries: [BoxEntry]) {
        let row = entry.row
        self.entry = entry; self.screen = screen
        name = HubRaidsModel.name(row)
        // D21: five stars as five stars, as in the game.
        let c = HubRaidsModel.kindChip(row.kind)
        chip = c == "5★" ? "★★★★★" : c
        bring = HubRaidsModel.bring(row: row, hub: hub)
        dates = HubRaidsModel.dateColumn(entry)
        ready = advice.map { HubRaidsModel.readiness(row: row, advice: $0, entries: entries, gm: gm, hub: hub, screen: screen) }
        todo = advice.map { HubRaidsModel.toDo(row: row, advice: $0, entries: entries, gm: gm, hub: hub, screen: screen) } ?? (row.bosses.isEmpty ? (row.tba == true ? "Boss not announced yet." : row.note) : "")
    }

    var key: String { SquadStore.eventKey(entry.row) }
    var counters: String? { ready.flatMap { $0.needed > 0 ? ($0.built == $0.needed ? "\($0.needed) of \($0.needed) ready" : "\($0.built) of \($0.needed) counters") : nil } }
    var fraction: Double { ready.map { $0.needed > 0 ? Double($0.built) / Double($0.needed) : 0 } ?? 0 }
    /// A boss to plan a squad against; a Raid Hour or a boss still to be announced has none.
    var hasSquad: Bool { !entry.row.bosses.isEmpty }

    /// The row for VoiceOver: the dates, the name, the chip, the counters and the types to bring (the bring types are read even while the list shows them only when opened).
    func spoken(isSet: Bool) -> String {
        var parts = [HubRaidsModel.spokenDates(entry), name]
        if !chip.isEmpty { parts.append(chip.replacingOccurrences(of: "★★★★★", with: "5 star").lowercased()) }
        if isSet { parts.append("squad set") }
        let types = bring.map(HubRaidsModel.typeName)
        let list = types.count > 1 ? types.dropLast().joined(separator: ", ") + " and " + types[types.count - 1] : types.joined()
        if let counters { parts.append("\(counters), bring \(list)") } else if !types.isEmpty { parts.append("Bring \(list)") }
        if !todo.isEmpty { parts.append(todo) }
        return parts.joined(separator: ". ")
    }
}

/// A 6 pt rounded bar: `fraction` of the track in `colour` (a 6 pt stub at zero, so the red shows), the rest on `track`.
struct ReadinessBar: View {
    let fraction: Double
    let colour: Color
    var track: Color = Theme.off

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(colour).frame(width: max(6, g.size.width * min(1, fraction)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The readiness bar with its "2 of 4 counters" label; at the accessibility sizes the label goes under the bar.
private struct ReadinessLine: View {
    let s: EventSummary
    let ink: Color
    var onSolid: Color? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let ready = s.ready, let counters = s.counters {
            let colour = onSolid ?? (ready.built == ready.needed ? Theme.greenInk : ready.built == 0 ? Theme.red : ink)
            let bar = ReadinessBar(fraction: s.fraction, colour: colour, track: onSolid.map { $0.opacity(0.32) } ?? Theme.off).frame(height: 6)
            let label = Text(counters).font(.figtree(11, .bold, relativeTo: .caption2)).monospacedDigit().foregroundStyle(colour)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { bar; label }
            } else {
                HStack(spacing: 8) { bar; label.fixedSize() }
            }
        }
    }
}

private struct KindChip: View {
    let text: String
    var tone: Color = Theme.muted
    var fill: Color = Theme.off
    var body: some View {
        Text(text).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.04 * 10).foregroundStyle(tone)
            .padding(.horizontal, 7).padding(.vertical, 2).background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: the raid card

/// A raid card (Raids › Now; 250 pt, radius 22, padding 14 by 16): the dates and "now", the boss and its kind chip, the readiness bar and BRING. Chosen: the raid tint and
/// a 2 pt raid-ink outline. Squad set: filled in the accent, its contents in the accent's on-solid ink; chosen and set: a raid-ink ring outside the card.
struct RaidCardView: View {
    let summary: EventSummary
    let chosen: Bool
    let isSet: Bool
    let identifier: String
    let action: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let s = summary
        let ink = ContentType.raids.ink(accent)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let wide = typeSize.isAccessibilitySize
        let on = accent.onSolid
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(s.dates.dates) · \(s.dates.when)").font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.08 * 11)
                    .foregroundStyle(isSet ? on.opacity(0.85) : ink)
                FlowLayout(spacing: 8) {
                    Text(s.name).font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(isSet ? on : Theme.ink).fixedSize(horizontal: false, vertical: true)
                    if !s.chip.isEmpty { KindChip(text: s.chip, tone: isSet ? on : Theme.muted, fill: isSet ? on.opacity(0.24) : Theme.off) }
                    if isSet { KindChip(text: "SQUAD SET", tone: on, fill: on.opacity(0.24)) }
                }
                ReadinessLine(s: s, ink: ink, onSolid: isSet ? on : nil)
                if !s.bring.isEmpty {
                    HStack(spacing: 6) {
                        Text("BRING").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(isSet ? on.opacity(0.85) : Theme.faint)
                        TypeIcons(types: s.bring, size: 22)
                    }
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(width: wide ? nil : 250, alignment: .topLeading)
            .frame(maxWidth: wide ? .infinity : nil, minHeight: 112, maxHeight: wide ? nil : .infinity, alignment: .topLeading)
            .background(isSet ? AnyShapeStyle(accent.solid) : AnyShapeStyle(chosen ? ContentType.raids.tint(accent) : Theme.surface), in: shape)
            .overlay { if chosen && !isSet { shape.strokeBorder(ink, lineWidth: 2) } }
            .overlay { if chosen && isSet { shape.inset(by: -1).stroke(Theme.bg, lineWidth: 2) } }
            .overlay { if chosen && isSet { shape.inset(by: -3).stroke(ink, lineWidth: 2) } }
            .panelShadow()
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.spoken(isSet: isSet))
        .accessibilityHint(chosen ? "Closes this raid's squad" : "Opens this raid's squad")
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: the timeline row

/// One row of a list timeline (Raids' Coming up, Max's Now and Coming up): the dates, the name with its kind chip, the readiness bar and a chevron. Tapped, it opens
/// into BRING and the squad (`open`); a set row is tinted in the accent.
struct EventRowView<Open: View>: View {
    let summary: EventSummary
    let type: ContentType
    let isOpen: Bool
    let isSet: Bool
    let identifier: String
    let toggle: () -> Void
    @ViewBuilder var open: Open
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let s = summary
        let ink = type.ink(accent)
        let stacked = typeSize.isAccessibilitySize
        let dateColumn = VStack(alignment: .leading, spacing: 2) {
            Text(s.dates.dates).font(.figtree(11, .heavy, relativeTo: .caption2)).foregroundStyle(isSet ? accent.ink : (s.entry.isNow ? ink : Theme.muted))
            Text(s.dates.when).font(.figtree(11, .semibold, relativeTo: .caption2)).foregroundStyle(Theme.muted)
        }
        let details = VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                Text(s.name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if !s.chip.isEmpty { KindChip(text: s.chip) }
                if isSet { KindChip(text: "SQUAD SET", tone: accent.ink, fill: Theme.surface) }
            }
            ReadinessLine(s: s, ink: ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        let head = Button(action: toggle) {
            Group {
                if stacked {
                    VStack(alignment: .leading, spacing: 6) { dateColumn; details }
                } else {
                    HStack(alignment: .top, spacing: 12) { dateColumn.frame(width: 54, alignment: .leading); details }
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "chevron.down").font(.figtree(12, .bold)).foregroundStyle(Theme.faint).rotationEffect(.degrees(isOpen ? 180 : 0)).padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.spoken(isSet: isSet))
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
        VStack(alignment: .leading, spacing: 0) {
            head
            if isOpen { open.padding(.horizontal, 16).padding(.bottom, 14) }
        }
        .background(isSet ? accent.tint : (s.entry.isNow ? type.tint(accent) : Color.clear))
    }
}

// MARK: BRING

/// BRING and the type icons the boss is weak to (22 pt).
struct BringLine: View {
    let types: [String]
    var body: some View {
        if !types.isEmpty {
            HStack(spacing: 6) {
                Text("BRING").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.faint)
                TypeIcons(types: types, size: 22)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bring \(SquadWords.typeList(types))")
        }
    }
}

// MARK: the squad of an event

/// A Pokémon a raid or Max slot may take, with what the picker says about it: one of the player's own builds (Available, and a Best row the box has) or, under Best, a
/// Pokémon the box lacks (`best`, with its availability line).
private struct EventOption: SquadCandidate {
    let build: BoxAdvice.Build?
    let best: HubSquads.BestRow?
    let name: String
    let tier: String
    let roles: [String]
    let types: [String]
    /// The id a slot and a pick hold: the copy's entry id, or `squadSpeciesPrefix` + the species key.
    let id: String
    var entryId: String { id }
    var roleNames: [String] { roles }
}

/// "Your squad – Palkia": the title with its "i", the advice line, the slots (Raids: Mega, Heavy hitter ×3, Bulky hitter ×2; Max: Tank, Healer, Attacker), "Set this
/// squad" / "✓ Squad set" with Undo, and under them the picker of the tapped slot. The squad is kept per account (`SquadKeeper`) and dropped when the event ends.
struct EventSquadView: View {
    let screen: SquadScreen
    let row: HubData.RotationRow
    let title: String
    let advice: String
    let ctx: HubContext
    @ObservedObject var keeper: SquadKeeper
    @State private var selected: Int?
    @State private var infoOpen = false

    private var prefix: String { screen == .raids ? "hub-raids" : "hub-max" }
    private var chips: [String] { (screen == .raids ? PogoRules.RaidRole.allCases.map(\.rawValue) : PogoRules.MaxRole.allCases.map(\.rawValue)) + [squadRoleAll] }

    var body: some View {
        let mode = keeper.store.mode(for: screen)
        let saved = keeper.store.eventSquad(row, screen: screen)
        let (options, filled) = resolve(saved: saved, mode: mode)
        let byId = Dictionary(options.map { ($0.entryId, $0) }, uniquingKeysWith: { a, _ in a })
        let cards = filled.enumerated().map { card($0.offset, $0.element, byId: byId, count: filled.count) }
        let team = HubSquads.teamStatus(cards.map(\.status))
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(title).font(.figtree(16, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                InfoButton(isOpen: $infoOpen, label: "About the suggested squad", identifier: "squad-info")
            }
            if !advice.isEmpty {
                Text(advice).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -4).accessibilityIdentifier("\(prefix)-advice")
            }
            if infoOpen { squadInfo.frame(maxWidth: .infinity, alignment: .leading) }
            if let team { SquadStatusLine(status: team) }
            SlotGrid(slots: cards, selected: selected) { i in withAnimation(.easeOut(duration: 0.15)) { selected = selected == i ? nil : i } }
            SetSquadFooter(isSet: saved.isSet, onSet: { edit { $0.isSet = true } }, onUndo: { edit { $0.isSet = false } })
            if let i = selected, filled.indices.contains(i) {
                picker(i, filled: filled, options: options, byId: byId, saved: saved, mode: mode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: the squad as shown

    /// The Pokémon the slots may take under `mode`, and the slots filled from the player's picks and the suggestions (rules 3, 4, 6, 10, 12). Available: the player's own
    /// builds. Best: the tier tables' rows for the boss, owned or not.
    private func resolve(saved: SquadStore.Saved, mode: SquadMode) -> (options: [EventOption], filled: [FilledSlot]) {
        if mode == .best {
            let rows = screen == .raids ? HubSquads.bestRaidRows(row: row, ctx: ctx) : HubSquads.bestMaxRows(row: row, ctx: ctx)
            let options = rows.map { EventOption(build: $0.build, best: $0, name: $0.name, tier: $0.tier, roles: $0.roles, types: $0.types, id: $0.entryId) }
            return (options, HubSquads.bestSquad(slots: saved.slots, rows: rows))
        }
        let placeable = HubSquads.placeable(screen: screen, mode: mode, ctx: ctx)
        func option(_ b: BoxAdvice.Build, _ tier: String, _ roles: [String]) -> EventOption {
            EventOption(build: b, best: nil, name: b.targetName, tier: tier, roles: roles, types: ctx.gm.byId[b.targetId]?.types ?? [], id: b.entryId)
        }
        if screen == .raids {
            let c = HubSquads.raidCandidates(row: row, mode: mode, ctx: ctx)
            return (c.map { option($0.build, $0.tier, $0.roleNames) }, HubSquads.raidSquad(slots: saved.slots, candidates: c, placeable: placeable))
        }
        let c = HubSquads.maxCandidates(row: row, mode: mode, ctx: ctx)
        return (c.map { option($0.build, $0.tier, $0.roleNames) }, HubSquads.maxSquad(slots: saved.slots, candidates: c, placeable: placeable))
    }

    // MARK: edits

    private func edit(_ change: (inout SquadStore.Saved) -> Void) {
        keeper.update { store in
            var s = store.eventSquad(row, screen: screen)
            change(&s)
            store.saveEventSquad(s, row: row, screen: screen)
        }
    }

    // MARK: slots

    private func card(_ i: Int, _ f: FilledSlot, byId: [String: EventOption], count: Int) -> SlotCardModel {
        let palette = SquadPalette.of(f.role)
        let head = "Slot \(i + 1) of \(count), \(f.role)"
        let identifier = "\(prefix)-slot-\(i + 1)"
        guard let id = f.pickId else {
            return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: nil, status: .empty, spoken: head + ", " + HubSquads.SlotStatus.empty.spoken, identifier: identifier)
        }
        guard let o = byId[id] else {
            // A pick the list no longer offers (its build is gone from the advice, or the species is not on this boss's list): the slot still names it.
            if let key = f.species {
                let name = ctx.gm.byId[key]?.name ?? ctx.gm.byId[key.replacingOccurrences(of: "_shadow", with: "")]?.name ?? "Pokémon"
                return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: name, lines: ["Not in your box"], types: ctx.gm.byId[key]?.types ?? [], status: .toGet,
                                     spoken: [head, name, HubSquads.SlotStatus.toGet.spoken].joined(separator: ", "), identifier: identifier)
            }
            let name = ctx.entry(id)?.row.title ?? "Pokémon"
            return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: name, types: ctx.entryTypes(id), status: .needsWork,
                                 spoken: [head, name, HubSquads.SlotStatus.needsWork.spoken].joined(separator: ", "), identifier: identifier)
        }
        guard let build = o.build else {
            return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", notOwned: o.best!, head: head, identifier: identifier)
        }
        let mark = SquadMark.of(build, screen: screen, ctx: ctx)
        let status = HubSquads.slotStatus(inBox: true, fullStrength: mark == .fullStrength, tier: o.tier)
        let spoken = [head, o.name, SquadWords.typeList(o.types), mark.spoken, status.spoken].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: o.name, types: o.types, mark: mark, status: status, spoken: spoken, identifier: identifier)
    }

    // MARK: picker

    private func picker(_ i: Int, filled: [FilledSlot], options: [EventOption], byId: [String: EventOption], saved: SquadStore.Saved, mode: SquadMode) -> some View {
        let role = filled[i].role
        let excluded = HubSquads.excluded(by: filled, editing: i, onlyChosen: false)
        let listed = HubSquads.picker(candidates: HubSquads.pool(role: role, in: options), excluded: excluded, own: filled[i].pickId)
        var rows: [PickerRowModel] = listed.compactMap { r in
            guard let o = byId[r.entryId] else { return nil }
            let roleWord = o.roles.joined(separator: " · ")
            guard let build = o.build else { return PickerRowModel(notOwned: o.best!, ticked: r.ticked, role: roleWord) }
            let mark = SquadMark.of(build, screen: screen, ctx: ctx)
            let spoken = [o.name, roleWord, o.tier.isEmpty ? nil : "tier \(o.tier)", SquadWords.typeList(o.types), mark.spoken, r.ticked ? "in this slot" : nil]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            return PickerRowModel(id: r.entryId, name: o.name, ticked: r.ticked, mark: mark, role: roleWord, tier: o.tier, types: o.types.map { PickerType(type: $0) }, spoken: spoken)
        }
        if mode == .available { rows = PickerRowModel.availableUpgradesLast(rows) }
        return SquadPicker(
            title: "Slot \(i + 1) · \(role)", type: screen == .raids ? .raids : .max, roles: chips, role: role,
            onRole: { new in edit { $0.changeRole(at: i, to: new) { HubSquads.fits($0, role: new, in: options) } } },
            rows: rows, emptyText: mode == .available ? "Nothing in your box for this role." : "Nothing listed for this role.",
            onChoose: { id in edit { $0.choose(id, at: i) } },
            onDone: { withAnimation(.easeOut(duration: 0.15)) { selected = nil } },
            info: { pickerInfo(mode) })
    }

    @ViewBuilder private func pickerInfo(_ mode: SquadMode) -> some View {
        if mode == .best {
            SquadExplainer(items: [
                ("Ranked from our tables:", screen == .raids
                 ? "every Pokémon our raid tables list under the boss's weak types, S then A then B, the strongest weak type first. Ones you do not have say when they might be available."
                 : "every Pokémon our Max tables list for the role, S then A then B, ones that hit the boss first. Ones you do not have say when they might be available."),
                ("Roles:", screen == .raids ? "Mega if it mega evolves; Heavy hitter if it is a Shadow or its Attack is at least 1.3 times its Defence; Bulky hitter otherwise." : "from our Max table: Tank, Healer, or Attacker."),
            ], identifier: "squad-picker-explainer")
        } else if screen == .raids {
            SquadExplainer(items: [
                ("Best for this boss first:", "the tier our raid tables give it against the boss's weak types, then built before to build, then how many of those types it covers."),
                ("Roles:", "Mega if it mega evolves; Heavy hitter if it is a Shadow or its Attack is at least 1.3 times its Defence; Bulky hitter otherwise."),
            ], identifier: "squad-picker-explainer")
        } else {
            SquadExplainer(items: [
                ("Best first:", "the tier our Max tables give it, then a type that hits the boss for more than normal damage."),
                ("Roles:", "from our Max table: Tank, Healer, or Attacker. Only Pokémon marked as Dynamax can take part, so every pick reads Upgrade available until you mark it on its page."),
            ], identifier: "squad-picker-explainer")
        }
    }

    @ViewBuilder private var squadInfo: some View {
        if screen == .raids {
            SquadExplainer(items: [
                ("Suggested for raids:", "1 Mega, which boosts everyone's damage (one per lobby); 3 Heavy hitters, Shadows and glass cannons that do the most damage but faint sooner; 2 Bulky hitters that stay in longer."),
                ("", "Change any slot's role in its picker; All lets you put in any Pokémon."),
            ], identifier: "squad-explainer")
        } else {
            SquadExplainer(items: [
                ("Suggested for Max battles:", "1 Tank to take the hits, 1 Healer to keep the squad up, 1 Attacker that hits the boss."),
                ("", "Change any slot's role in its picker; All lets you put in any Pokémon."),
            ], identifier: "squad-explainer")
        }
    }
}
