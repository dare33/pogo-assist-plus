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
struct EventOption: SquadCandidate {
    let build: BoxAdvice.Build?
    let best: HubSquads.BestRow?
    let name: String
    let tier: String
    let roles: [String]
    let types: [String]
    /// Available, raids: the copy's Mega view, used in the Mega slot only (`build`, `tier` and `roles` are the plain Pokémon's everywhere else).
    var mega: HubSquads.MegaView? = nil
    /// Max: one of its types hits the boss (the Attacker role lists those first, as the squad fills them).
    var hitsBoss = false
    /// The id a slot and a pick hold: the copy's entry id, or `squadSpeciesPrefix` + the species key.
    let id: String
    /// Current only: a Best row listed because a kept slot holds that species (so the slot can be drawn as the Best row it is). It is never offered by a picker.
    var extra = false
    var entryId: String { id }
    var roleNames: [String] { roles }
}

/// The rows of a raid or Max picker, built from the box and the schedule alone (no view state), so a test can read what every picker would show.
struct EventPickerBuilder {
    let screen: SquadScreen
    let row: HubData.RotationRow
    let ctx: HubContext
    /// Drawing a Current squad (pass 2-5): no mode placement rule hides a kept pick, and a kept species pick is drawn as the Best row it is.
    var kept = false

    /// The Pokémon the slots may take under `mode`, and the slots filled from the player's picks and the suggestions (rules 3, 4, 6, 10, 12). Available: the player's own
    /// builds. Best: the tier tables' rows for the boss, owned or not.
    func resolve(slots: [SquadSlot], mode: SquadMode) -> (options: [EventOption], filled: [FilledSlot]) {
        if mode == .best {
            let rows = screen == .raids ? HubSquads.bestRaidRows(row: row, ctx: ctx) : HubSquads.bestMaxRows(row: row, ctx: ctx)
            let options = rows.map { EventOption(build: $0.build, best: $0, name: $0.name, tier: $0.tier, roles: $0.roles, types: $0.types, id: $0.entryId) }
            // Raids Best fills a slot whose role has run out as Available does (another role's listed row), so Max damage never leaves a slot empty while rows remain.
            return (options, HubSquads.bestSquad(slots: slots, rows: rows, fallback: screen == .raids, oneMega: screen == .raids))
        }
        // S1: Available fills every slot from the box, whatever upgrade the Pokémon needs, taking the strongest unused one of another role when a role runs out.
        let placeable: (String, String) -> Bool = kept ? { _, _ in true } : HubSquads.placeable(screen: screen, mode: mode, ctx: ctx)
        // A kept species pick (a Pokémon the box lacked when it was picked) is drawn as its Best row; the row is not offered by any picker.
        let keptSpecies = Set(slots.compactMap(\.species))
        let keptRows: [HubSquads.BestRow] = kept && !keptSpecies.isEmpty
            ? (screen == .raids ? HubSquads.bestRaidRows(row: row, ctx: ctx) : HubSquads.bestMaxRows(row: row, ctx: ctx)).filter { keptSpecies.contains($0.key) } : []
        // A kept species pick and an owned copy of it are the same Pokémon: no other slot refills with that copy while the pick holds it.
        let copyOf = HubSquads.copyResolver(rows: keptRows)
        func extras(_ rows: [HubSquads.BestRow]) -> [EventOption] {
            guard kept, !keptSpecies.isEmpty else { return [] }
            return rows.map { r in
                var o = EventOption(build: r.build, best: r, name: r.name, tier: r.tier, roles: r.roles, types: r.types, id: r.entryId)
                o.extra = true
                return o
            }
        }
        func option(_ b: BoxAdvice.Build, _ tier: String, _ roles: [String], hits: Bool = false) -> EventOption {
            EventOption(build: b, best: nil, name: b.targetName, tier: tier, roles: roles, types: ctx.gm.byId[b.targetId]?.types ?? [], hitsBoss: hits, id: b.entryId)
        }
        if screen == .raids {
            let c = HubSquads.raidCandidates(row: row, mode: mode, ctx: ctx)
            return (c.map { var o = option($0.build, $0.tier, $0.roleNames); o.mega = $0.mega; return o } + extras(keptRows),
                    HubSquads.raidSquad(slots: slots, candidates: c, fillAnyRole: true, placeable: placeable, copyOf: copyOf))
        }
        let c = HubSquads.maxCandidates(row: row, mode: mode, ctx: ctx)
        return (c.map { option($0.build, $0.tier, $0.roleNames, hits: $0.hitsBoss) } + extras(keptRows),
                HubSquads.maxSquad(slots: slots, candidates: c, fillAnyRole: true, placeable: placeable, copyOf: copyOf))
    }

    /// The build and tier a slot of this role judges a Pokémon on: the Mega view in the Mega slot under Available, the plain Pokémon everywhere else (S1).
    func view(_ o: EventOption, role: String, mode: SquadMode) -> (build: BoxAdvice.Build?, tier: String) {
        if mode == .available, screen == .raids, role == PogoRules.RaidRole.mega.rawValue, let m = o.mega { return (m.build, m.tier) }
        return (o.build, o.tier)
    }

    /// The role a row is drawn with: "Mega" in the Mega slot, the plain Pokémon's own role under Available, every role the table gives it under Best.
    func roleWord(_ o: EventOption, role: String, mode: SquadMode) -> String {
        guard mode == .available, screen == .raids else { return o.roles.joined(separator: " · ") }
        return role == PogoRules.RaidRole.mega.rawValue && o.mega != nil ? role : o.roles.first ?? ""
    }

    /// What a slot's picker shows: its rows and whether the box has any option for it.
    struct Content { var rows: [PickerRowModel]; var boxHasOptions: Bool }

    private var strengthMode: StrengthScale.Mode { screen == .raids ? .raids : .max }

    func strengthScale() -> StrengthScale? {
        guard let pve = try? PveMoves.bundled() else { return nil }
        return StrengthScale.shared(mode: strengthMode, bosses: row.bosses, ctx: ctx, pve: pve)
    }

    /// Whether a row is judged as a Mega: only in the raid Mega slot, on the copy's Mega build, whichever mode lists it. Under Best a Mega entry shown under another role's
    /// slot (the All chip) is judged as the plain Pokémon, the rule in force being that Mega builds appear only in the Mega slot.
    func judgesAsMega(build: BoxAdvice.Build, role: String, mode: SquadMode, option o: EventOption) -> Bool {
        guard screen == .raids, role == PogoRules.RaidRole.mega.rawValue else { return false }
        return mode == .best ? build.viaMega : o.mega != nil
    }

    /// `only` limits the rows to those ids: the squad strength bar needs one slot's own row, not the whole list. `given` is the boss's scale when the caller has worked it out (it hashes
    /// the game master and the tables, so the strength bar's six slots share one).
    func content(slot i: Int, filled: [FilledSlot], options: [EventOption], byId: [String: EventOption], mode: SquadMode, only: Set<String>? = nil, scale given: StrengthScale? = nil) -> Content {
        let role = filled[i].role
        let bestRows = options.compactMap(\.best)
        // A copy sits in one slot however many rows show it (Primal Kyogre and Kyogre): rows are hidden by the copy they stand for.
        let copyOf = HubSquads.copyResolver(rows: bestRows)
        // A Pokémon in another slot is listed, marked with its slot, only when the swap can happen: the edited slot's Pokémon must fit the other slot's role (Available: be placeable
        // there, the Mega slot taking Mega candidates only; Best: be listed for the role) and the other slot's Pokémon this slot's (rule 27). An empty slot just moves it.
        let place: (String, String) -> Bool = kept ? { _, _ in true } : HubSquads.placeable(screen: screen, mode: mode, ctx: ctx)
        // The Pokémon a picker offers: not the Best rows a Current squad holds only to draw its kept species picks.
        let listed = options.filter { !$0.extra }
        let held = HubSquads.otherSlots(of: filled, editing: i, copyOf: copyOf, canHold: { f, j in
            // Available: placeable in the slot. Best: the row the player picked (its species row, else its copy's) is listed for the slot's role.
            mode == .available ? (f.pickId.map { place($0, filled[j].role) } ?? true)
                : HubSquads.tickIds(f, rows: bestRows).contains { HubSquads.fits($0, role: filled[j].role, in: options) }
        })
        // A raid squad holds one Mega: under Best the picker offers no other Mega row while another slot holds one; a swap exchanges two Pokémon, so the Mega that slot holds stays listed.
        let megaHidden: Set<String> = screen == .raids && mode == .best ? HubSquads.megaExcluded(by: filled, editing: i, rows: bestRows).filter { held.swap[$0] == nil && copyOf($0).flatMap { held.swap[$0] } == nil } : []
        let excluded: Set<String> = megaHidden.union(held.blocked)
        // Available (S1): the slot's own role's options first, then every other unused Pokémon ("Other roles:"); the Mega slot lists Mega candidates only. Best: the
        // table's rows for the role.
        var own: [String]
        if mode == .available, screen == .raids {
            own = role == PogoRules.RaidRole.mega.rawValue ? listed.filter { $0.mega != nil }.sorted { ($0.mega?.order ?? 0) < ($1.mega?.order ?? 0) }.map(\.entryId) : HubSquads.pool(role: role, in: listed)
        } else if screen == .max {
            let hits = Set(listed.filter(\.hitsBoss).map(\.entryId))
            let pooled = HubSquads.pool(role: role, in: listed)
            own = mode == .available && role == PogoRules.MaxRole.attacker.rawValue ? pooled.filter(hits.contains) + pooled.filter { !hits.contains($0) } : pooled
        } else {
            own = HubSquads.pool(role: role, in: listed)
        }
        let groups = mode == .available
            ? HubSquads.pickerGroups(own: own, all: listed.map(\.entryId), allowsOther: !(screen == .raids && role == PogoRules.RaidRole.mega.rawValue))
            : (own: own, other: [])
        let boxHasOptions = !(groups.own + groups.other).isEmpty
        let ticks = HubSquads.tickIds(filled[i], rows: bestRows)
        // The slot's own Pokémon is always listed, ticked, even when this mode's list does not hold it (a copy chosen under the other mode).
        var ownIds = groups.own
        if let tick = ticks.first ?? filled[i].pickId, ticks.isDisjoint(with: groups.own + groups.other) { ownIds.insert(tick, at: 0) }
        // P1: the strength bar's scale, worked out once for the boss.
        let scale = given ?? strengthScale()
        func rows(_ ids: [String]) -> [PickerRowModel] {
            HubSquads.picker(candidates: only.map { o in ids.filter(o.contains) } ?? ids, excluded: excluded, ownIds: ticks, copyOf: copyOf).compactMap { r in
                guard let o = byId[r.entryId] else {
                    let copy = ctx.entry(r.entryId)
                    return PickerRowModel.keptPick(id: r.entryId, ticked: r.ticked, screen: screen, ctx: ctx)?.adding(copy: copy, strength: scale?.strength(.init(copy: copy, build: nil, built: false)))
                }
                let word = roleWord(o, role: role, mode: mode)
                let shown = view(o, role: role, mode: mode)
                guard let build = shown.build, o.best?.hasBuild != false else {
                    // A copy no build serves has its own figures; a Pokémon the box lacks has one bar at level 50 with 15/15/15 and no CP line.
                    let best = o.best!, copy = best.inBox ? (best.copy ?? best.ownedEntryId.flatMap(ctx.entry)) : nil
                    // Best lists no Gigantamax entry on Max today (rule 12), so the Gigantamax flag is false on every row that reaches here; the engine takes it for a row that would.
                    // Only the raid Mega slot judges a Mega or Primal entry as one; every other slot judges the plain Pokémon.
                    let megaSlot = screen == .raids && role == PogoRules.RaidRole.mega.rawValue
                    let lacking = copy == nil ? HubSquads.lacking(of: best, area: screen == .raids ? "raids" : "max", megaSlot: megaSlot, gigantamax: HubRaidsModel.isGigantamaxName(best.name), ctx: ctx) : nil
                    return PickerRowModel(best: best, ticked: r.ticked, role: word).adding(copy: copy, strength: scale?.strength(.init(copy: copy, build: nil, built: false, species: lacking)))
                }
                let mark = SquadMark.of(build, screen: screen, ctx: ctx)
                let shared = o.best?.statusLine
                let spoken = [o.name, word, shown.tier.isEmpty ? nil : "tier \(shown.tier)", SquadWords.typeList(o.types), mark.spoken, o.best?.spokenStatus, r.ticked ? "in this slot" : nil]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                let copy = ctx.entry(build.entryId)
                let strength = scale?.strength(.init(copy: copy, build: build, built: mark == .fullStrength, megaSlot: judgesAsMega(build: build, role: role, mode: mode, option: o)))
                return PickerRowModel(id: r.entryId, name: o.name, ticked: r.ticked, mark: mark, role: word, tier: shown.tier, types: o.types.map { PickerType(type: $0) }, note: shared, spoken: spoken)
                    .adding(copy: copy, strength: strength)
            }
        }
        let shownRows = mode == .available ? PickerRowModel.availableGroups(own: rows(ownIds), other: rows(groups.other)) : rows(ownIds)
        return Content(rows: PickerRowModel.marking(shownRows, moves: held.moves) { held.swap[$0] ?? copyOf($0).flatMap { held.swap[$0] } }, boxHasOptions: boxHasOptions)
    }

    /// The squad's strength bar (rule 32): each slot's figure is the one its Pokémon shows as a row in that slot's picker, so it is read from that row (built alone), over the Best
    /// squad's full-build figures (`reference`).
    func squadStrength(filled: [FilledSlot], options: [EventOption], byId: [String: EventOption], mode: SquadMode, reference: [Double?]) -> SquadStrength {
        let bestRows = options.compactMap(\.best), scale = strengthScale()
        return SquadStrength.against(figures: filled.indices.map { i in
            guard filled[i].pickId != nil else { return nil }
            let rows = content(slot: i, filled: filled, options: options, byId: byId, mode: mode, only: HubSquads.tickIds(filled[i], rows: bestRows), scale: scale).rows
            return rows.first(where: \.ticked)?.strength ?? Strength(kind: .damage, now: nil, after: nil)
        }, reference: reference)
    }

    /// The squad's Best suggestion (unedited, in `style`) with each slot taken at its full build: the figure a Pokémon the box lacks gets, whether or not the box holds a copy
    /// (rule 32). nil for a slot the Best squad leaves empty or whose figure cannot be worked out.
    func reference(style: RaidStyle) -> [Double?] {
        let rows = screen == .raids ? HubSquads.bestRaidRows(row: row, ctx: ctx) : HubSquads.bestMaxRows(row: row, ctx: ctx)
        let best = HubSquads.bestSquad(slots: screen == .raids ? HubSquads.defaultRaidSlots(style: style) : HubSquads.defaultMaxSlots(), rows: rows, fallback: screen == .raids, oneMega: screen == .raids)
        guard let scale = strengthScale() else { return best.map { _ in nil } }
        return best.map { f in
            guard let id = f.pickId, let r = rows.first(where: { $0.entryId == id || $0.ids.contains(id) }) else { return nil }
            let lacking = HubSquads.lacking(of: r, area: screen == .raids ? "raids" : "max", megaSlot: screen == .raids && f.role == PogoRules.RaidRole.mega.rawValue,
                                            gigantamax: HubRaidsModel.isGigantamaxName(r.name), ctx: ctx)
            return scale.strength(.init(copy: nil, build: nil, built: false, species: lacking)).now
        }
    }

    /// One slot as its card draws it (a method of the builder so a test can read it).
    func card(_ i: Int, _ f: FilledSlot, byId: [String: EventOption], count: Int, mode: SquadMode) -> SlotCardModel {
        let palette = SquadPalette.of(f.role)
        let head = "Slot \(i + 1) of \(count), \(f.role)"
        let identifier = "\(screen == .raids ? "hub-raids" : "hub-max")-slot-\(i + 1)"
        guard let id = f.pickId else {
            // Empty only when the box has nothing left for the slot; the Mega slot also needs a Mega candidate (rule 3) and says why it is empty.
            var why: String?
            if screen == .raids, f.role == PogoRules.RaidRole.mega.rawValue, mode == .available {
                why = byId.values.contains { $0.mega != nil } ? "You can only have 1 Mega slot" : "No Mega-capable Pokémon in your box"
            }
            return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: nil, lines: why.map { [$0] } ?? [], status: .empty,
                                 spoken: [head, HubSquads.SlotStatus.empty.spoken, why].compactMap { $0 }.joined(separator: ", "), identifier: identifier)
        }
        guard let o = (f.species.flatMap { byId[squadSpeciesPrefix + $0] } ?? byId[id]) else {
            // A pick the list no longer offers (its build is gone from the advice, or it was chosen under the other mode): the slot still names it.
            if let key = f.species {
                let name = ctx.gm.byId[key]?.name ?? ctx.gm.byId[key.replacingOccurrences(of: "_shadow", with: "")]?.name ?? "Pokémon"
                let unlisted = HubSquads.BestStatus.unlisted.text
                return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: name, lines: [unlisted], types: ctx.gm.byId[key]?.types ?? [], status: .toGet,
                                     spoken: [head, name, unlisted.replacingOccurrences(of: " · ", with: ", "), HubSquads.SlotStatus.toGet.spoken].joined(separator: ", "), identifier: identifier)
            }
            let name = ctx.entry(id)?.row.title ?? "Pokémon"
            return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: name, types: ctx.entryTypes(id), status: .needsWork,
                                 spoken: [head, name, HubSquads.SlotStatus.needsWork.spoken].joined(separator: ", "), identifier: identifier)
        }
        let shown = view(o, role: f.role, mode: mode)
        // A slot filled from another role says which role the Pokémon is listed for (S1), whether or not the box has it.
        let other = f.fallback && !f.chosen ? SquadWords.otherRoleLine([roleWord(o, role: f.role, mode: mode)]) : nil
        guard let build = shown.build, o.best?.hasBuild != false else {
            return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", best: o.best!, extra: other.map { [$0] } ?? [], spokenExtra: other.map { [$0] } ?? [], head: head, identifier: identifier)
        }
        let mark = SquadMark.of(build, screen: screen, ctx: ctx)
        let status = HubSquads.slotStatus(inBox: true, fullStrength: mark == .fullStrength, tier: shown.tier)
        let shared = o.best?.statusLine
        let spoken = [head, o.name, other, SquadWords.typeList(o.types), mark.spoken, o.best?.spokenStatus, status.spoken].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return SlotCardModel(id: i, role: f.role, palette: palette, emptyOutline: palette.tint, disc: "+", name: o.name, lines: [other, shared].compactMap { $0 }, types: o.types, mark: mark, status: status, spoken: spoken, identifier: identifier)
    }

    /// Every slot's picker rows for the default squad under `mode` (what a test reads): the rows of each slot as the picker would list them.
    func allSlotRows(mode: SquadMode) -> [[PickerRowModel]] {
        let slots = screen == .raids ? HubSquads.defaultRaidSlots() : HubSquads.defaultMaxSlots()
        let (options, filled) = resolve(slots: slots, mode: mode)
        let byId = Dictionary(options.flatMap { o in [(o.entryId, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        return filled.indices.map { content(slot: $0, filled: filled, options: options, byId: byId, mode: mode).rows }
    }
}

/// "Your squad – Palkia": the title with its "i", the advice line, the tabs (Current | Available | Best, and the Raids style), the slots (Raids: Mega then Heavy and Bulky hitters
/// by the style; Max: Tank, Healer, Attacker), under them Save to Current and Reset (an edited Available or Best) or Delete current squad (Current), "Set this squad" / "✓ Squad set"
/// with Undo, and the picker of the tapped slot. Current is kept per account (`SquadKeeper`) and dropped when the event ends; Available and Best edits are drafts (`SquadWorkspace`).
struct EventSquadView: View {
    let screen: SquadScreen
    let row: HubData.RotationRow
    let title: String
    let advice: String
    let ctx: HubContext
    @ObservedObject var keeper: SquadKeeper
    @ObservedObject var workspace: SquadWorkspace
    @State private var selected: Int?
    @State private var infoOpen = false
    @State private var rowsCache = PickerRowsCache<EventPickerBuilder.Content>()
    @State private var strength: (key: String, value: SquadStrength)?
    @State private var boxGeneration = 0
    @State private var replacingForSet = false

    private func builder(kept: Bool) -> EventPickerBuilder { EventPickerBuilder(screen: screen, row: row, ctx: ctx, kept: kept) }
    private var prefix: String { screen == .raids ? "hub-raids" : "hub-max" }
    private var chips: [String] { (screen == .raids ? PogoRules.RaidRole.allCases.map(\.rawValue) : PogoRules.MaxRole.allCases.map(\.rawValue)) + [squadRoleAll] }

    var body: some View {
        let style = keeper.store.raidStyle
        let ref = SquadRef.event(row: row, screen: screen)
        let defaults = screen == .raids ? HubSquads.defaultRaidSlots(style: style) : HubSquads.defaultMaxSlots()
        let base = workspace.surface(ref, store: keeper.store, defaults: defaults)
        let mode = base.mode
        let builder = builder(kept: base.kept)
        let (options, filled) = builder.resolve(slots: base.squad.slots, mode: mode)
        // Edited means the squad as drawn differs from the suggestion as drawn (rule 27.3); only worked out while a draft exists.
        let surface = base.with(edited: base.isEdited(filled: filled, suggested: { builder.resolve(slots: defaults, mode: mode).filled }))
        let byId = Dictionary(options.flatMap { o in [(o.entryId, o)] + (o.best.map { [(squadSpeciesPrefix + $0.key, o)] } ?? []) }, uniquingKeysWith: { a, _ in a })
        let cards = filled.enumerated().map { builder.card($0.offset, $0.element, byId: byId, count: filled.count, mode: mode) }
        let team = HubSquads.teamStatus(cards.map(\.status))
        // Worked out off the main thread (`.task` below), once for the squad as drawn; the bar fills in when it is ready.
        let strengthKey = "strength|\(screen.rawValue)|\(row.from)|\(row.title)|\(surface.tab.rawValue)|\(style.rawValue)|\(surface.isBestSuggestion)|" + FilledSlot.cacheKey(filled) + "|" + options.map(\.id).joined(separator: ",") + "|\(ctx.today)|\(boxGeneration)"
        let adoptKey = surface.squad.needsAdopting(filled) ? FilledSlot.cacheKey(filled) : ""
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
            SquadTabsRow(tab: Binding(get: { surface.tab }, set: { workspace.select($0, ref: ref, keeper: keeper) }), hasCurrent: surface.hasCurrent, noun: "squads")
            if screen == .raids {
                RaidStyleRow(style: Binding(get: { style }, set: { new in
                    keeper.update { $0.raidStyle = new }
                    // The Available and Best drafts were edits of the other style's suggestion; Current is untouched.
                    workspace.update { $0.resetAll(keyPrefix: "raids|") }
                }))
            }
            if let team { SquadStatusLine(status: team) }
            SquadStrengthLine(strength: strength?.key == strengthKey ? strength?.value : nil, type: screen == .raids ? .raids : .max)
            SlotGrid(slots: cards, selected: selected) { i in withAnimation(.easeOut(duration: 0.15)) { selected = selected == i ? nil : i } }
            if surface.tab == .current {
                DeleteCurrentButton { workspace.deleteCurrent(surface, keeper: keeper) }
            } else {
                SquadDraftBar(differs: surface.differs, justSaved: surface.justSaved, replaces: surface.replaces(filled: filled),
                              onSave: { workspace.saveToCurrent(surface, keeper: keeper, filled: filled, setMark: false) }, onReset: { workspace.reset(surface) })
            }
            SetSquadFooter(isSet: isSet(surface, ref: ref), hint: surface.tab == .current ? nil : "Saves this squad as your current squad and marks it set, asking first only if your current squad is a different one",
                           onSet: {
                               if surface.tab == .current { workspace.edit(surface, keeper: keeper) { $0.markSet(shown: filled) } }
                               else if surface.replaces(filled: filled) { replacingForSet = true }
                               else { workspace.saveToCurrent(surface, keeper: keeper, filled: filled, setMark: true) }
                           },
                           onUndo: { keeper.update { store in if var q = store.current(ref) { q.isSet = false; store.setCurrent(q, ref) } } })
                .replaceCurrentDialog(isPresented: $replacingForSet) { workspace.saveToCurrent(surface, keeper: keeper, filled: filled, setMark: true) }
            if let i = selected, filled.indices.contains(i) {
                picker(i, filled: filled, options: options, byId: byId, surface: surface, builder: builder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .squadStrip(cards: cards, selected: selected) { i in withAnimation(.easeOut(duration: 0.15)) { selected = i } }
        .task(id: strengthKey) {
            let b = builder
            let bestUnedited = surface.isBestSuggestion
            let value = await Task.detached(priority: .userInitiated) {
                bestUnedited ? SquadStrength.bestSquad(reference: b.reference(style: style)) : b.squadStrength(filled: filled, options: options, byId: byId, mode: mode, reference: b.reference(style: style))
            }.value
            if !Task.isCancelled { strength = (strengthKey, value) }
        }
        // A slot of a changed squad that refilled (its copy left the box, or a swap emptied it) is kept as shown, so it does not change again.
        .task(id: adoptKey) { if !adoptKey.isEmpty, !Task.isCancelled { workspace.adopt(surface, keeper: keeper, filled: filled) } }
        .tracksBox(ctx, generation: $boxGeneration)
    }

    /// "✓ Squad set": on Current, its own mark; on Available or Best, only while the squad just saved (and set) to Current is what is shown.
    private func isSet(_ surface: SquadSurface, ref: SquadRef) -> Bool {
        surface.tab == .current ? (surface.current?.isSet ?? false) : (surface.justSaved && (keeper.store.current(ref)?.isSet ?? false))
    }

    // MARK: slots

    // MARK: picker

    private func picker(_ i: Int, filled: [FilledSlot], options: [EventOption], byId: [String: EventOption], surface: SquadSurface, builder: EventPickerBuilder) -> some View {
        let role = filled[i].role
        let mode = surface.mode
        // The rows are built once and kept until the box, the advice or what the slot sees changes (P1: no work on every redraw).
        let key = "\(screen.rawValue)|\(row.from)|\(row.title)|\(surface.tab.rawValue)|\(i)|" + FilledSlot.cacheKey(filled) + "|" + options.map(\.id).joined(separator: ",")
        let content = rowsCache.get(ctx: ctx, key: key) { builder.content(slot: i, filled: filled, options: options, byId: byId, mode: mode) }
        return SquadPicker(
            title: "Slot \(i + 1) · \(role)", type: screen == .raids ? .raids : .max, roles: chips, role: role,
            onRole: { new in workspace.edit(surface, keeper: keeper) { $0.changeRole(at: i, to: new, fits: { HubSquads.fitsThrough($0, role: new, in: options, rows: options.compactMap(\.best)) }, shown: filled) } },
            rows: content.rows, emptyText: SquadWords.emptyPicker(mode: mode, boxHasOptions: content.boxHasOptions, none: mode == .available ? "Nothing in your box for this slot." : "Nothing listed for this role."),
            onChoose: { id in
                // Under Available there are no Best rows on screen, but a species pick stored under Best may resolve to this copy: read the Best rows to clear it.
                let rows = screen == .raids ? HubSquads.bestRaidRows(row: row, ctx: ctx) : HubSquads.bestMaxRows(row: row, ctx: ctx)
                workspace.edit(surface, keeper: keeper) { $0.choose(id, at: i, alsoClearing: HubSquads.equivalents(of: id, rows: rows), shown: filled) }
            },
            onDone: { withAnimation(.easeOut(duration: 0.15)) { selected = nil } },
            info: { pickerInfo(mode) })
    }

    @ViewBuilder private func pickerInfo(_ mode: SquadMode) -> some View {
        if mode == .best {
            SquadExplainer(items: [
                ("Ranked from our tables:", screen == .raids
                 ? "every Pokémon our raid tables list under the boss's weak types, S then A then B, the strongest weak type first. Each says whether you have it, can get it now, or cannot, with the date when the schedule has one."
                 : "every Pokémon our Max tables list for the role, S then A then B, ones that hit the boss first. Each says whether you have it, can get it now, or cannot, with the date when the schedule has one."),
                ("Roles:", screen == .raids ? "Mega if it mega evolves; Heavy hitter if it is a Shadow or its Attack is at least 1.3 times its Defence; Bulky hitter otherwise." : "from our Max table: Tank, Healer, or Attacker."),
            ], identifier: "squad-picker-explainer")
        } else if screen == .raids {
            SquadExplainer(items: [
                ("Best for this boss first:", "the tier our raid tables give it against the boss's weak types, then built before to build, then how many of those types it covers."),
                ("Roles:", "Mega is for a Pokémon that can Mega Evolve (the Mega slot lists only those); Heavy hitter if it is a Shadow or its Attack is at least 1.3 times its Defence; Bulky hitter otherwise. After the slot's own role comes \"Other roles:\", everything else in your box."),
            ], identifier: "squad-picker-explainer")
        } else {
            SquadExplainer(items: [
                ("Best first:", "the tier our Max tables give it, then a type that hits the boss for more than normal damage. After the slot's own role comes \"Other roles:\", everything else in your box."),
                ("Roles:", "from our Max table: Tank, Healer, or Attacker. Only Pokémon marked as Dynamax can take part, so every pick reads Upgrade available until you mark it on its page."),
            ], identifier: "squad-picker-explainer")
        }
    }

    @ViewBuilder private var squadInfo: some View {
        if screen == .raids {
            SquadExplainer(items: [
                ("Suggested for raids:", "1 Mega, which boosts everyone's damage (one per lobby), then Heavy hitters, Shadows and glass cannons that do the most damage but faint sooner, and Bulky hitters that stay in longer. The style decides how many of each."),
                (RaidStyle.balanced.title + ":", RaidStyle.balanced.explanation),
                (RaidStyle.maxDamage.title + ":", RaidStyle.maxDamage.explanation),
                ("", "Under Available the Mega slot takes a Pokémon that can Mega Evolve, judged on its Mega build; every other slot judges a Pokémon as it is, without Mega Evolving. A slot with no Pokémon of its role left takes the strongest one you have left and says its role. Change any slot's role in its picker; All lets you put in any Pokémon."),
            ], identifier: "squad-explainer")
        } else {
            SquadExplainer(items: [
                ("Suggested for Max battles:", "1 Tank to take the hits, 1 Healer to keep the squad up, 1 Attacker that hits the boss."),
                ("", "Under Available a slot with no Pokémon of its role left takes the strongest one you have left and says its role. Change any slot's role in its picker; All lets you put in any Pokémon."),
            ], identifier: "squad-explainer")
        }
    }
}
