import SwiftUI
import PogoBox

// The pieces the five squad screens (Raids, Max, Gym, Rocket, PvP) share, from the pass 2 handoff's "Shared components": the SQUAD tabs, the slot card, the
// picker with its role chips and rows, the squad status line and the status colour of a card. They draw what the screens hand them; the rules (who is listed, in what order, what a role
// allows) are PogoBox's `HubSquads`. Every colour is a Theme token, so light and dark follow.

// MARK: role colours

/// A role's ink and tint (pass 2 README, "Role colours"): pink opener, violet damage, teal staying power, green healing, grey any.
struct SquadPalette {
    let ink: Color
    let tint: Color

    static let pink = SquadPalette(ink: Theme.copiesInk, tint: Theme.copiesTint)
    static let violet = SquadPalette(ink: Theme.changeInk, tint: Theme.changeTint)
    static let teal = SquadPalette(ink: Theme.matchInk, tint: Theme.matchTint)
    static let green = SquadPalette(ink: Theme.greenInk, tint: Theme.greenTint)
    static let grey = SquadPalette(ink: Theme.muted, tint: Theme.off)

    /// Mega and Lead are the openers; Heavy hitter, Attacker and Closer do the damage; Bulky hitter, Tank and Safe swap stay in; Healer heals; All and anything else is grey.
    static func of(_ role: String) -> SquadPalette {
        switch role {
        case "Mega", "Lead": return .pink
        case "Heavy hitter", "Attacker", "Closer": return .violet
        case "Bulky hitter", "Tank", "Safe swap": return .teal
        case "Healer": return .green
        default: return .grey
        }
    }
}

// MARK: the work left on a Pokémon

/// What a slot or picker row says about the Pokémon's build: nothing, Full strength, or Upgrade available with the cost and what the work is.
enum SquadMark: Equatable {
    case none
    case fullStrength
    case upgrade(cost: MyPokemon.Cost?, label: String)

    /// Rules 1 and 2 for a build on a screen.
    static func of(_ b: BoxAdvice.Build, screen: SquadScreen, ctx: HubContext) -> SquadMark {
        if HubSquads.isFullStrength(b, screen: screen, ctx: ctx) { return .fullStrength }
        let c = HubSquads.cost(of: b)
        let cost = c.value.map { MyPokemon.Cost(value: $0, currency: c.currency == .dust ? .dust : .candy) }
        // Only the Dynamax mark is left (Max): there is no upgrade work to name.
        return .upgrade(cost: cost, label: HubSquads.upgradeLabel(b) ?? dynamaxMarkOnly)
    }

    /// The label when only the Dynamax mark is left: nothing to pay for, but not "Free" either (a copy that is not Dynamax cannot be made one).
    static let dynamaxMarkOnly = "Upgrade available: mark it as Dynamax on its page"

    /// The same for a league candidate: Built reads Full strength; else the work is the evolution and power-up the league option needs.
    static func of(_ c: HubTeams.Candidate) -> SquadMark { of(option: c.option, built: c.built, copyTitle: c.copyTitle) }

    static func of(option: BoxAdvice.LeagueRating.Option, built: Bool, copyTitle: String) -> SquadMark {
        if built { return .fullStrength }
        let cost = option.cost.flatMap { k -> MyPokemon.Cost? in
            let v = HubSquads.cost(dust: k.dust, candy: k.candy + k.evolveCandy)
            return v.value.map { MyPokemon.Cost(value: $0, currency: v.currency == .dust ? .dust : .candy) }
        }
        return .upgrade(cost: cost, label: option.isSelf ? "Upgrade available: power up" : "Upgrade available: evolve from \(copyTitle)")
    }

    /// For a VoiceOver label: "full strength", "Upgrade available: power up to level 30, 12k dust".
    var spoken: String? {
        switch self {
        case .none: return nil
        case .fullStrength: return "Full strength"
        case .upgrade(let cost, let label): return cost.map { "\(label), \($0.words)" } ?? label
        }
    }
}

/// The icon for a mark; `showsCost` adds the cost and currency after the upgrade arrow (pickers do, slot cards do not).
struct SquadMarkView: View {
    let mark: SquadMark
    var showsCost = false
    var body: some View {
        switch mark {
        case .none: EmptyView()
        case .fullStrength: FullStrengthBadge()
        case .upgrade(let cost, let label): UpgradeMark(cost: showsCost ? cost : nil, label: label)
        }
    }
}

// MARK: explainers

/// The text an "i" opens: terms in bold in the accent's ink, each with its sentence, one accessibility element.
struct SquadExplainer: View {
    let items: [(term: String, text: String)]
    let identifier: String
    @Environment(\.accent) private var accent

    var body: some View {
        ExplainerCard(identifier: identifier) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    if item.term.isEmpty { Text(item.text) } else { Text(item.term).bold().foregroundStyle(accent.ink) + Text(" " + item.text) }
                }
            }
        }
    }
}

// MARK: slot cards

extension HubSquads.BestRow {
    /// The row's one status (S1) with "same copy as <higher row>" after it when a higher row already shows the copy.
    var statusLine: String { [status.text, sharedWith.map { "same copy as \($0)" }].compactMap { $0 }.joined(separator: " · ") }
    /// The same for VoiceOver: commas, not dots.
    var spokenStatus: String { statusLine.replacingOccurrences(of: " · ", with: ", ") }
}

/// One slot of a squad as the card draws it.
struct SlotCardModel: Identifiable {
    var id: Int
    /// The role row's text ("Heavy hitter", drawn in capitals); nil on Gym and Rocket, which have no role row (the mark sits in the corner).
    var role: String?
    var palette: SquadPalette
    /// The empty card's outline.
    var emptyOutline: Color
    /// The disc's text when the slot is empty (and when no name): the slot's number, or "+".
    var disc: String
    var name: String?
    /// Muted lines under the name ("beats 2 of 3", "vs Zekrom", "level not read").
    var lines: [String] = []
    var types: [String] = []
    var mark: SquadMark = .none
    /// How ready the slot is (CONCEPTS rule 29): the card's background is a soft tint of it.
    var status: HubSquads.SlotStatus
    /// The whole card for VoiceOver.
    var spoken: String
    var identifier: String
}

extension HubSquads.SlotStatus {
    /// The card's background and the status line's badge: Theme's soft green, amber and red (the tints keep the ink readable in light and dark).
    var tint: Color {
        switch self {
        case .ready: return Theme.statusGreenTint
        case .needsWork: return Theme.statusAmberTint
        case .toGet, .empty: return Theme.statusRedTint
        }
    }
    /// The word and icon a card carries so its status is not told by colour alone.
    var word: String {
        switch self {
        case .ready: return "Ready"
        case .needsWork: return "Needs work"
        case .toGet: return "To get"
        case .empty: return "Empty"
        }
    }
    var icon: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .needsWork: return "exclamationmark.triangle.fill"
        case .toGet: return "arrow.down.circle.fill"
        case .empty: return "circle.dashed"
        }
    }
    /// The status line's dot.
    var dot: Color {
        switch self {
        case .ready: return Theme.green
        case .needsWork: return Theme.orange
        case .toGet, .empty: return Theme.red
        }
    }
}

extension HubSquads.TeamStatus {
    var tint: Color { level == .green ? Theme.statusGreenTint : level == .amber ? Theme.statusAmberTint : Theme.statusRedTint }
    var dot: Color { level == .green ? Theme.green : level == .amber ? Theme.orange : Theme.red }
}

/// The squad's one-line status over its slots (CONCEPTS rule 30): a dot and "Ready", "Nearly ready: 2 need work" or "Not ready: 2 to get, 1 empty".
struct SquadStatusLine: View {
    let status: HubSquads.TeamStatus
    @ScaledMetric(relativeTo: .footnote) private var dotSize: CGFloat = 10

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(status.dot).frame(width: dotSize, height: dotSize).accessibilityHidden(true)
            Text(status.text).font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(status.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))   // not a capsule: the text wraps at the accessibility sizes
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.text)
        .accessibilityIdentifier("squad-status")
    }
}

/// The squad's strength bar (CONCEPTS rule 32), under the status line: "Squad strength 78% of best" (the squad's slot figures over the Best squad's; "Matches the best squad" at or over it) and "92% after upgrades" over one bar drawn as a picker row's bar is (solid = now, faint
/// = after the suggested upgrades), and "5 of 6 slots scored" when a slot has no figure. VoiceOver reads the words as one element; the bar is hidden from it. `strength` is nil
/// while it is being worked out (off the main thread): the row keeps its height with an empty track, so nothing below it moves. At accessibility text sizes the two labels stack.
struct SquadStrengthLine: View {
    let strength: SquadStrength?
    let type: ContentType
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    /// What the row is laid out with while the figure is worked out: a typical finished row (the words, the "after" words and a bar), drawn as a redacted placeholder, so the
    /// slots below keep their place at every text size when the figure arrives.
    private var sample: SquadStrength { SquadStrength(kind: type == .pvp ? .score : .damage, now: 0.5, after: 0.6, scored: 6, total: 6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            do {
                let strength = strength ?? sample
                let words = Group {
                    Text(strength.text).font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
                    if let after = strength.afterText { Text(after).font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted) }
                }
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) { words }.fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { words }.fixedSize(horizontal: false, vertical: true)
                }
                if strength.now != nil { StrengthBar(strength: strength.strength, ink: type.ink(accent)).frame(maxWidth: .infinity) }
                if let scored = strength.scoredText { Text(scored).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted) }
            }
        }
        .redacted(reason: self.strength == nil ? .placeholder : [])
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strength?.spoken ?? "Squad strength, working it out")
        .accessibilityIdentifier("squad-strength")
    }
}

/// Counts a change to the box or its advice, so a figure worked out from them is worked out again (the strength bar's key reads it). Applied to a squad screen with the context it draws from.
struct TracksBox: ViewModifier {
    let ctx: HubContext
    @Binding var generation: Int
    func body(content: Content) -> some View {
        content
            .onChange(of: ctx.advice) { _, _ in generation &+= 1 }
            .onChange(of: ctx.entries) { _, _ in generation &+= 1 }
    }
}

extension View {
    func tracksBox(_ ctx: HubContext, generation: Binding<Int>) -> some View { modifier(TracksBox(ctx: ctx, generation: generation)) }
}

/// A slot card (pass 2 README, "Slot card"): radius 16, at least 92 pt; the role row in the role colour with the mark at its trailing end; a 30 pt disc; the name 13/700;
/// the type icons at the foot. The background is the slot's status tint (green ready, amber needs work, red to get or empty; the disc and the role text keep the role
/// colour); an empty card also keeps a 2 pt inset outline; selected = a 2 pt inset outline in the accent.
struct SlotCardView: View {
    let model: SlotCardModel
    let selected: Bool
    let action: () -> Void
    @Environment(\.accent) private var accent
    /// The disc grows with the text, so an initial or a number never spills out of it at the accessibility sizes.
    @ScaledMetric(relativeTo: .subheadline) private var discSize: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let filled = model.name != nil
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                if let role = model.role {
                    HStack(alignment: .top, spacing: 4) {
                        Text(role.uppercased()).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(model.palette.ink)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        SquadMarkView(mark: model.mark)
                    }
                    .frame(minHeight: 18)
                } else {
                    HStack(spacing: 0) { Spacer(minLength: 0); SquadMarkView(mark: model.mark) }.frame(minHeight: 18)
                }
                Text(filled ? String(model.name!.prefix(1)) : model.disc)
                    .font(.figtree(filled ? 14 : 18, .heavy, relativeTo: .subheadline))
                    .foregroundStyle(filled ? Theme.surface : model.palette.ink)
                    .frame(width: min(discSize, 80), height: min(discSize, 80))
                    .background(Circle().fill(filled ? model.palette.ink : Theme.off))
                    .accessibilityHidden(true)
                Text(model.name ?? "Empty").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(filled ? Theme.ink : Theme.mutedOnTint)
                    .lineLimit(2).multilineTextAlignment(.leading)
                ForEach(model.lines, id: \.self) { Text($0).font(.figtree(11, .regular, relativeTo: .caption2)).foregroundStyle(Theme.mutedOnTint).lineLimit(4).multilineTextAlignment(.leading) }
                // The work's cost, as a picker row shows it beside the mark (Greg: the needs-work status and its cost are shown); under the name so it never crowds the role.
                // A step that costs nothing (Mega Evolve alone) reads "Free"; only the Dynamax mark left shows no cost line.
                if case .upgrade(let cost, let label) = model.mark, cost != nil || label != SquadMark.dynamaxMarkOnly {
                    Text(cost?.words ?? "Free").font(.figtree(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.orangeInk).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if !model.types.isEmpty { TypeIcons(types: model.types, size: 18) }
                HStack(spacing: 4) {
                    Image(systemName: model.status.icon).font(.figtree(11, .bold, relativeTo: .caption2))
                    Text(model.status.word).font(.figtree(11, .heavy, relativeTo: .caption2))
                }
                .foregroundStyle(Theme.ink).padding(.top, 2).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 76, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(model.status.tint, in: shape)
            .overlay { if !filled { shape.strokeBorder(model.emptyOutline, lineWidth: 2) } }
            .overlay { if selected { shape.strokeBorder(accent.solid, lineWidth: 2) } }
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.spoken)
        .accessibilityHint(selected ? "Closes the picker" : "Opens the picker")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(model.identifier)
    }
}

/// The cards in rows of three (one to a row at the accessibility sizes), each row as tall as its tallest card.
struct SlotGrid: View {
    let slots: [SlotCardModel]
    let selected: Int?
    let onTap: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let per = typeSize.isAccessibilitySize ? 1 : 3
        let rows = stride(from: 0, to: slots.count, by: per).map { Array(slots[$0..<min($0 + per, slots.count)]) }
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { s in SlotCardView(model: s, selected: selected == s.id) { onTap(s.id) } }
                    // A short last row keeps the cards at the same width as the rows above it.
                    ForEach(0..<(per - row.count), id: \.self) { _ in Color.clear.frame(height: 0) }
                }
            }
        }
    }
}

// MARK: picker

/// One type icon on a picker row: in colour, or grey when it is not in play (Rocket: it does not hit the slot).
struct PickerType: Equatable {
    var type: String
    var grey = false
}

struct PickerRowModel: Identifiable {
    var id: String
    var name: String
    /// The slot's own Pokémon is ticked.
    var ticked: Bool
    var mark: SquadMark = .none
    /// The role word, drawn in its colour.
    var role: String? = nil
    var tier: String? = nil
    var types: [PickerType] = []
    /// A muted line under the first ("From Eevee", "Not weak to this slot").
    var note: String? = nil
    /// The note is drawn in the amber ink ("In your box · needs upgrade · no build for this").
    var noteAmber = false
    /// An extra line in place of `note` (PvP's graded IV line).
    var noteView: AnyView? = nil
    /// The stacked figures before the end figure (Gym's DEF and HP).
    var stats: AnyView? = nil
    /// The end figure (Gym's BULK, PvP's SCORE).
    var figure: AnyView? = nil
    /// A heading over this row ("Available upgrades:").
    var sectionHeading: String? = nil
    /// The copy's CP and IVs as it is now ("CP 3,412 · 15/14/15"); nil for a Pokémon the box lacks (phone run 2, P1).
    var cpIv: String? = nil
    /// The strength bar: a solid part for the copy now, a faint one up to after its upgrade. nil draws no bar.
    var strength: Strength? = nil
    /// The Pokémon is in another slot of the squad (1-based): choosing it swaps the two (CONCEPTS rule 27).
    var swapSlot: Int? = nil
    /// The edited slot is empty: choosing it moves the Pokémon here and its slot refills.
    var movesHere = false
    var spoken: String
}

extension PickerRowModel {
    /// The CP and IV line and the strength bar of a row (phone run 2, P1), with what VoiceOver adds for them ("CP 3412, IVs 15, 14, 15, estimated damage 62 percent of the best,
    /// 85 percent after upgrade"). The row's spoken label keeps "in this slot" last. `copy` is nil for a Pokémon the box lacks (no CP line); `ivs: false` leaves the IVs out
    /// (PvP has its own graded IV line); `speaksStrength: false` leaves the bar's words out where the row already says the figure (PvP's score).
    func adding(copy: BoxEntry?, ivs: Bool = true, strength: Strength?, speaksStrength: Bool = true) -> PickerRowModel {
        var m = self
        let line = copy.map { DamageEstimate.cpIvLine($0, ivs: ivs) }
        m.cpIv = line?.text
        m.strength = strength.flatMap { $0.isEmpty ? nil : $0 }
        let extra = [line?.spoken, speaksStrength ? strength?.spoken : nil].compactMap { $0 }
        let tail = ", in this slot"
        let ticked = spoken.hasSuffix(tail)
        let base = ticked ? String(spoken.dropLast(tail.count)) : spoken
        // Spoken text uses ", " where the screen writes " · " (a PvP row's "IV rank 552 · 97.6%", "Lead · Safe swap").
        m.spoken = (([base] + extra).filter { !$0.isEmpty }.joined(separator: ", ") + (ticked ? tail : "")).replacingOccurrences(of: " · ", with: ", ")
        return m
    }

    /// Marks the rows whose Pokémon sits in another slot ("In slot 2 · choosing it swaps the two", or "... moves it here" when the edited slot is empty). `slotOf` gives that
    /// slot for a row's id, nil when it is in none; the slot's own (ticked) row is left alone.
    static func marking(_ rows: [PickerRowModel], moves: Bool = false, slotOf: (String) -> Int?) -> [PickerRowModel] {
        rows.map { r in
            guard !r.ticked, let n = slotOf(r.id) else { return r }
            var m = r
            m.swapSlot = n
            m.movesHere = moves
            m.spoken += ", in slot \(n), choosing it \(moves ? "moves it here" : "swaps the two")"
            return m
        }
    }

    static let upgradesHeading = "Available upgrades:"
    static let otherRolesHeading = "Other roles:"

    /// An Available picker (S1): the slot's own role's options first, at Full strength first then under "Available upgrades:", then every other unused Pokémon under
    /// "Other roles:", each showing its role, in the order the squad is filled in.
    static func availableGroups(own: [PickerRowModel], other: [PickerRowModel]) -> [PickerRowModel] {
        var rest = other
        if !rest.isEmpty { rest[0].sectionHeading = otherRolesHeading }
        return availableUpgradesLast(own) + rest
    }

    /// CONCEPTS rule 28: an Available picker lists the Pokémon at Full strength first and, under "Available upgrades:", those whose build still needs work. Each group
    /// keeps the slot's order.
    static func availableUpgradesLast(_ rows: [PickerRowModel]) -> [PickerRowModel] {
        let done = rows.filter { $0.mark == .fullStrength }
        var work = rows.filter { $0.mark != .fullStrength }
        if !work.isEmpty { work[0].sectionHeading = upgradesHeading }
        return done + work
    }

    /// The note under a Best row (S1): the row's one status ("In your box", "In your box · needs upgrade", "Can get now · Raid boss now", "Not available now · Raids from
    /// 9 Nov"), plus "same copy as <higher row>" when a higher row already shows that copy. Amber for a copy no build of the area serves.
    static func bestNote(_ r: HubSquads.BestRow) -> (text: String, amber: Bool) { (r.statusLine, r.inBox && !r.hasBuild) }

    /// A Best row without a build: a Pokémon the box lacks, or a copy of it that no build of the area serves.
    init(best r: HubSquads.BestRow, ticked: Bool, role: String? = nil, types: [PickerType]? = nil, extraSpoken: String? = nil) {
        let n = PickerRowModel.bestNote(r)
        let spoken = [r.name, role, "tier \(r.tier)", SquadWords.typeList(r.types), n.text.replacingOccurrences(of: " · ", with: ", "), extraSpoken, ticked ? "in this slot" : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        self.init(id: r.entryId, name: r.name, ticked: ticked, role: role, tier: r.tier, types: types ?? r.types.map { PickerType(type: $0) }, note: n.text, noteAmber: n.amber, spoken: spoken)
    }

    /// The row of a pick the lists do not offer (a copy chosen under the other mode, or whose build is gone): the copy, with its build's mark when it has one.
    static func keptPick(id: String, ticked: Bool, screen: SquadScreen, ctx: HubContext) -> PickerRowModel? {
        guard !id.hasPrefix(squadSpeciesPrefix), let e = ctx.entry(id) else { return nil }
        let area = ["raids": "Raids", "max": "Max", "gym": "Gym", "rocket": "Rocket", "pvp": "PvP"][screen.rawValue] ?? ""
        // Only Raids has a Mega slot: every other screen judges a copy on its plain form.
        let build = ctx.advice.builds.first { $0.entryId == id && ($0.areas.contains(area) || (screen == .rocket && $0.areas.contains("Raids"))) }.map { screen == .raids ? $0 : HubSquads.plainBuilds([$0])[0] }
        let mark = build.map { SquadMark.of($0, screen: screen, ctx: ctx) } ?? .none
        let types = ctx.entryTypes(id)
        let note = build == nil ? "In your box · needs upgrade · no build for this" : nil
        let spoken = [e.row.title, SquadWords.typeList(types), mark.spoken, note?.replacingOccurrences(of: " · ", with: ", "), ticked ? "in this slot" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return PickerRowModel(id: id, name: e.row.title, ticked: ticked, mark: mark, types: types.map { PickerType(type: $0) }, note: note, noteAmber: note != nil, spoken: spoken)
    }
}

extension SlotCardModel {
    /// The card of a Best row without a build: a Pokémon the box lacks (red, with the short rotation date when there is one; VoiceOver carries the whole availability
    /// line), or a copy no build of the area serves (amber).
    init(id: Int, role: String?, palette: SquadPalette, emptyOutline: Color, disc: String, best r: HubSquads.BestRow, extra: [String] = [], spokenExtra: [String] = [], head: String, identifier: String) {
        let status: HubSquads.SlotStatus = r.inBox ? .needsWork : .toGet
        let own = [r.statusLine]
        let said = [r.spokenStatus]
        let spoken = ([head, r.name, SquadWords.typeList(r.types)] + spokenExtra + said + [status.spoken]).filter { !$0.isEmpty }.joined(separator: ", ")
        self.init(id: id, role: role, palette: palette, emptyOutline: emptyOutline, disc: disc, name: r.name, lines: own + extra, types: r.types, status: status, spoken: spoken, identifier: identifier)
    }
}

/// The picker under a squad (README, "Picker"): `surface`, a 2 pt inset accent outline, radius 20, padding 12; the title with the "i" and Done; the role chips; the
/// rows. A row is a button with a selected state; choosing one puts the Pokémon in the slot and ticks it.
struct SquadPicker<Info: View>: View {
    let title: String
    let type: ContentType
    /// Role chips (the slot's roles and All); nil on screens whose slots have none (Gym, Rocket).
    var roles: [String]? = nil
    var role = ""
    var onRole: (String) -> Void = { _ in }
    /// A heading over the rows ("Next best").
    var heading: String? = nil
    let rows: [PickerRowModel]
    /// What to say when there is no row.
    let emptyText: String
    let onChoose: (String) -> Void
    let onDone: () -> Void
    @ViewBuilder var info: Info
    @State private var infoOpen = false
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text(title).font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                InfoButton(isOpen: $infoOpen, label: "How this list is ordered", identifier: "squad-picker-info")
                Button(action: onDone) {
                    Text("Done").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("squad-picker-done")
            }
            if infoOpen { info.frame(maxWidth: .infinity, alignment: .leading) }
            if let roles { roleChips(roles) }
            VStack(alignment: .leading, spacing: 0) {
                if let heading, !rows.isEmpty {
                    Text(heading).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.vertical, 6).padding(.horizontal, 2)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(rows) { row in
                    if let h = row.sectionHeading {
                        Text(h).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.top, 10).padding(.bottom, 4).padding(.horizontal, 2)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier(h == PickerRowModel.otherRolesHeading ? "squad-picker-other-roles" : "squad-picker-upgrades")
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                    rowView(row)
                }
                if rows.isEmpty {
                    Text(emptyText)
                        .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.vertical, 6).padding(.horizontal, 2)
                        .accessibilityIdentifier("squad-picker-empty")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: shape)
        .overlay { shape.strokeBorder(accent.solid, lineWidth: 2) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("squad-picker")
    }

    // MARK: role chips

    private func roleChips(_ roles: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ROLE FOR THIS SLOT").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.faint)
            FlowLayout(spacing: 6) {
                ForEach(roles, id: \.self) { r in
                    let on = r == role, p = SquadPalette.of(r)
                    Button { onRole(r) } label: {
                        Text(r).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(on ? p.ink : Theme.ink)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(on ? p.tint : Theme.off, in: Capsule())
                            .overlay { if on { Capsule().strokeBorder(p.ink.opacity(0.45), lineWidth: 1.5) } }
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("squad-role-\(r)")
                }
            }
        }
    }

    // MARK: rows

    private func rowView(_ row: PickerRowModel) -> some View {
        // At the accessibility sizes the mark goes under the name: beside it, it squeezes the name until a long one breaks inside a word ("Xurkitr / ee").
        let name = Text(row.name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        let head = Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) { name; SquadMarkView(mark: row.mark, showsCost: true) }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) { name; SquadMarkView(mark: row.mark, showsCost: true) }
            }
        }
        // The tier sits at the end of the strength bar when the row has one, else beside the types as before.
        let bar = row.strength
        let tier = row.tier.flatMap { $0.isEmpty ? nil : $0 }
        let roleText = row.role.map { role in
            Text(role).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(SquadPalette.of(role.components(separatedBy: " · ").first ?? role).ink)
        }
        // One wrapping line: the role word, the copy's CP and IVs, the types (and the tier when there is no bar to carry it).
        let line = FlowLayout(spacing: 6) {
            if let roleText { roleText }
            if let cpIv = row.cpIv {
                Text(cpIv).font(.figtree(12, .semibold, relativeTo: .caption)).monospacedDigit().foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 2)
            }
            if bar == nil, let tier { TierChip(tier: tier, type: type) }
            ForEach(Array(row.types.enumerated()), id: \.offset) { _, t in TypeIcon(type: t.type, size: 22, grey: t.grey) }
        }
        // The strength bar and its note sit under the head line and span the whole text column, so every bar of a picker starts and ends at the same x whether or not
        // its row has a tier chip, a CP line or Gym's and PvP's figures (those sit beside the head line only).
        let top = VStack(alignment: .leading, spacing: 4) {
            head
            line
        }
        let tail = VStack(alignment: .leading, spacing: 4) {
            if let bar { strengthLine(bar, tier: tier) }
            if let n = row.swapSlot { Text("In slot \(n) · choosing it \(row.movesHere ? "moves it here" : "swaps the two")").font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true) }
            if let v = row.noteView { v } else if let n = row.note { Text(n).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(row.noteAmber ? Theme.orangeInk : Theme.muted).fixedSize(horizontal: false, vertical: true) }
        }
        return Button { onChoose(row.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                tick(row.ticked)
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        top
                        tail
                        if let s = row.stats { s }
                        if let f = row.figure { f }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 10) {
                            top.frame(maxWidth: .infinity, alignment: .leading)
                            if let s = row.stats { s }
                            if let f = row.figure { f }
                        }
                        tail
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
        .accessibilityAddTraits(row.ticked ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("squad-picker-row")
    }

    /// The strength bar across the text column with the tier chip at its end; at the accessibility sizes the chip goes under the bar.
    @ViewBuilder private func strengthLine(_ strength: Strength, tier: String?) -> some View {
        let bar = StrengthBar(strength: strength, ink: type.ink(accent)).frame(maxWidth: .infinity)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                bar
                if let tier { TierChip(tier: tier, type: type) }
            }
        } else {
            HStack(spacing: 8) {
                bar
                // The chip's place is kept when a row has no tier (a hidden chip of the widest letter sizes it), so every bar is as long as the others.
                ZStack {
                    TierChip(tier: "M", type: type).hidden()
                    if let tier { TierChip(tier: tier, type: type) }
                }
            }
        }
    }

    private func tick(_ on: Bool) -> some View {
        SVGGlyph(data: Glyph.tick)
            .stroke(on ? accent.onSolid : Color.clear, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            .padding(4.5)
            .frame(width: 22, height: 22)
            .background(Circle().fill(on ? accent.solid : Color.clear))
            .overlay { if !on { Circle().strokeBorder(Theme.line, lineWidth: 2) } }
            .padding(.top, 1)
            .accessibilityHidden(true)
    }
}

// MARK: strength bar

/// A picker row's strength bar (phone run 2, P1): 8 pt high, the full width it is given. The solid part is the copy as it is now; the faint part continues it to the figure after
/// the suggested upgrade, drawn as a pale fill with a dashed outline so it does not rest on colour alone. The solid part is the screen's ink on the `off` track: measured contrast 4.26 or more
/// in light and 7.03 or more in dark for every screen (Raids 4.26 / 8.31, Gym 4.34 / 8.29, Rocket 10.59 / 7.66, PvP 5.84 / 7.28, Max 4.61 / 7.03), above the 3:1 a graphic needs. Hidden from VoiceOver: the row's label says the figures.
struct StrengthBar: View {
    let strength: Strength
    let ink: Color

    var body: some View {
        GeometryReader { g in
            let solid = strength.now == nil ? 0 : max(8, g.size.width * strength.barSolid)
            // The faint part is at least 6 pt long so a small gain can be seen.
            let end = min(g.size.width, max(strength.hasFaint ? solid + 6 : solid, g.size.width * strength.barEnd))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.off)
                if strength.hasFaint {
                    Capsule().fill(ink.opacity(0.22)).frame(width: end)
                    Capsule().strokeBorder(ink, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: end)
                }
                if solid > 0 { Capsule().fill(ink).frame(width: solid) }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: Set this squad

/// "Set this squad" (accent button) or "✓ Squad set" with an underlined Undo (D26, D42, D55): the player's own mark that the raid or Max squad is ready.
struct SetSquadFooter: View {
    let isSet: Bool
    /// What "Set this squad" does when it is not just the mark (on Available and Best it saves the squad to Current first).
    var hint: String? = nil
    let onSet: () -> Void
    let onUndo: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if isSet {
                Text("✓ Squad set").font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(accent.ink)
                    .accessibilityIdentifier("squad-set-state")
                Button(action: onUndo) {
                    Text("Undo").font(.figtree(14, .bold, relativeTo: .subheadline)).underline().foregroundStyle(Theme.muted).padding(.horizontal, 4)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("squad-undo")
            } else {
                Button(action: onSet) {
                    Text("Set this squad").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(accent.onSolid)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(accent.solid, in: Capsule()).contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityHint(hint ?? "Marks this squad as ready")
                .accessibilityIdentifier("squad-set")
            }
        }
    }
}

// MARK: shared words

enum SquadWords {
    /// An empty picker's text, true to what the box has: when the box has options for the slot but they are all in other slots, it says so; "none" only when the box
    /// truly has none (and under Best, where the list is the table's).
    static func emptyPicker(mode: SquadMode, boxHasOptions: Bool, speciesRuleOnly: Bool = false, none: String) -> String {
        if speciesRuleOnly { return "Your other options are the same species as a Pokémon already in this squad." }
        return mode == .available && boxHasOptions ? "Everything in your box for this slot is already in your squad." : none
    }

    /// The line a slot filled from another role carries (S1): the role the Pokémon is listed for, so the player sees why it sits in this slot.
    static func otherRoleLine(_ roles: [String]) -> String { roles.isEmpty ? "No listed role" : "Its role: " + roles.joined(separator: ", ") }

    /// "Rock and Dark" for a VoiceOver label.
    static func typeList(_ types: [String]) -> String {
        let names = types.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1] : names.joined()
    }
}

extension HubContext {
    /// The types of a copy's own species, for a slot that names a kept pick the current lists no longer offer.
    func entryTypes(_ id: String) -> [String] { entry(id).flatMap { gm.byId[$0.row.speciesId]?.types } ?? [] }
}

// MARK: rows kept between redraws

/// A picker's rows, built once and kept until what they are built from changes: the box and its advice (compared whole, they are value types), the day, and `key`
/// (the screen, mode, slot, squad and options). A SwiftUI body runs on every state change; the rows are not worked out again unless one of these differs.
final class PickerRowsCache<T> {
    private var last: (advice: BoxAdvice, entries: [BoxEntry], today: String, key: String)?
    private var value: T?

    func get(ctx: HubContext, key: String, build: () -> T) -> T {
        if let l = last, let v = value, l.key == key, l.today == ctx.today, l.advice == ctx.advice, l.entries == ctx.entries { return v }
        let v = build()
        last = (ctx.advice, ctx.entries, ctx.today, key)
        value = v
        return v
    }
}

// MARK: SQUAD · Current | Available | Best · (i)  (pass 2-5, rule 27)

/// The row every squad screen carries over its squad: the caption, the compact Current | Available | Best switch and the "i". Current shows only for a squad that has one. Available
/// and Best are the suggestions (edits to them are drafts); the choice between them is remembered per account (`SquadStore.modes`).
struct SquadTabsRow: View {
    @Binding var tab: SquadTab
    let hasCurrent: Bool
    /// What Available and Best mean on this screen ("counters", "defenders", "a squad").
    let noun: String
    @State private var infoOpen = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // The three labels always render at one size (never shrunk one by one): on one line when they fit, else under the caption, else stacked, one to a line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { caption; control(singleLine: true); info }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .trailing, spacing: 0) { caption; HStack(spacing: 8) { control(singleLine: true); info } }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .trailing, spacing: 4) { HStack(spacing: 8) { caption; Spacer(minLength: 0); info }; stacked }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            if infoOpen {
                SquadExplainer(items: [
                    ("Current", "is the squad you saved. Changes to it are kept straight away."),
                    ("Available", "picks \(noun) from the Pokémon in your box right now: the strongest you own for each slot, even if it still needs a power up, an evolution or a Mega Evolution first. Tap a slot for other choices from your box."),
                    ("Best", "lists the best Pokémon in the game for each slot, whether or not you have them. Each says if it is in your box, can be got now, or is not available now."),
                    ("", "Available and Best always start from the suggestion. Changes you make to them last until you leave this screen; Save to Current keeps them."),
                ], identifier: "squad-mode-explainer")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var caption: some View {
        Text("SQUAD").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.faint).accessibilityHidden(true)
    }

    private func control(singleLine: Bool) -> some View {
        let all: [SquadTab] = hasCurrent ? [.current, .available, .best] : [.available, .best]
        return SegmentedSwitch(
            segments: all.map { .init(value: $0, title: $0.title, identifier: "squad-tab-\($0.rawValue)") },
            selection: $tab, metrics: .compact, label: "Suggestions", identifier: "squad-mode", singleLine: singleLine)
    }

    private var stacked: some View {
        let all: [SquadTab] = hasCurrent ? [.current, .available, .best] : [.available, .best]
        return StackedChoice(options: all.map { .init(value: $0, title: $0.title, identifier: "squad-tab-\($0.rawValue)") }, selection: $tab, label: "Suggestions", identifier: "squad-mode")
    }

    private var info: some View { InfoButton(isOpen: $infoOpen, label: "About suggestions", identifier: "squad-mode-info") }
}

/// A choice between a few options drawn as a column of full-width buttons: what a segmented switch becomes when its titles cannot fit on one line at the accessibility text sizes
/// (the titles keep whole words and one size). The same identifiers, labels and selected trait as the switch.
struct StackedChoice<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var identifier: String
        var id: Value { value }
    }
    let options: [Option]
    @Binding var selection: Value
    let label: String
    var identifier: String = ""

    var body: some View {
        VStack(spacing: 4) {
            ForEach(options) { o in
                let on = o.value == selection
                Button { selection = o.value } label: {
                    Text(o.title).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Theme.surface : Color.clear, in: Capsule()).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(o.title)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier(o.identifier)
            }
        }
        .padding(4)
        .background(Theme.off, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// "Replace your current squad?": asked before a draft is saved over a squad that already has a Current.
extension View {
    func replaceCurrentDialog(isPresented: Binding<Bool>, onReplace: @escaping () -> Void) -> some View {
        confirmationDialog("Replace your current squad?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Replace", role: .destructive, action: onReplace).accessibilityIdentifier("squad-save-current-confirm")
            Button("Cancel", role: .cancel) {}.accessibilityIdentifier("squad-save-current-cancel")
        } message: {
            Text("Your saved changes are replaced by this squad.")
        }
    }
}

/// Under the slots of an edited Available or Best squad: Save to Current and Reset, or "Saved to Current" once it is saved. Shown once the squad as drawn differs from the suggestion
/// (the status also while an unedited squad has just been saved by "Set this squad"). Save asks first only when it would replace a Current that is a different squad (`replaces`).
/// Reset drops the draft at once. The save itself says "Saved to Current" to VoiceOver (`SquadWorkspace.saveToCurrent`).
struct SquadDraftBar: View {
    let differs: Bool
    let justSaved: Bool
    /// Saving would replace a Current that is a different squad.
    let replaces: Bool
    let onSave: () -> Void
    let onReset: () -> Void
    @Environment(\.accent) private var accent
    @State private var asking = false

    var body: some View {
        if differs || justSaved {
            VStack(alignment: .leading, spacing: 2) {
                if justSaved {
                    Text("Saved to Current").font(.figtree(13, .heavy, relativeTo: .footnote)).foregroundStyle(accent.ink).padding(.horizontal, 4)
                        .accessibilityIdentifier("squad-saved-note")
                }
                FlowLayout(spacing: 12) {
                    if !justSaved {
                        Button { if replaces { asking = true } else { onSave() } } label: {
                            Text("Save to Current").font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(accent.onSolid)
                                .padding(.horizontal, 16).frame(minHeight: 44).background(accent.solid, in: Capsule()).contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityHint("Saves this squad as your current squad, asking first if it would replace a different one")
                        .accessibilityIdentifier("squad-save-current")
                    }
                    if differs { Button(action: onReset) {
                        Text("Reset").font(.figtree(14, .bold, relativeTo: .subheadline)).underline().foregroundStyle(accent.ink)
                            .padding(.horizontal, 4).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityHint("Drops your changes to this squad and shows the suggestion again")
                    .accessibilityIdentifier("squad-reset-draft") }
                }
            }
            .replaceCurrentDialog(isPresented: $asking, onReplace: onSave)
        }
    }
}

/// "Delete current squad" on the Current tab: asks first, then removes the Current squad. Available and Best are not changed.
struct DeleteCurrentButton: View {
    let action: () -> Void
    @Environment(\.accent) private var accent
    @State private var asking = false

    var body: some View {
        HStack {
            Button { asking = true } label: {
                Text("Delete current squad").font(.figtree(14, .bold, relativeTo: .subheadline)).underline().foregroundStyle(accent.ink)
                    .padding(.horizontal, 4).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Deletes your current squad, after asking")
            .accessibilityIdentifier("squad-delete-current")
            Spacer(minLength: 0)
        }
        .confirmationDialog("Delete current squad?", isPresented: $asking, titleVisibility: .visible) {
            Button("Delete current squad", role: .destructive, action: action).accessibilityIdentifier("squad-delete-current-confirm")
            Button("Cancel", role: .cancel) {}.accessibilityIdentifier("squad-delete-current-cancel")
        } message: {
            Text("Available and Best are not changed.")
        }
    }
}

/// The Raids style control (rule 33): Balanced | Max damage, remembered per account. It sets the roles of the Available and Best suggestions; the (i) of the squad explains the two.
struct RaidStyleRow: View {
    @Binding var style: RaidStyle

    private func id(_ s: RaidStyle) -> String { "squad-style-\(s == .balanced ? "balanced" : "max-damage")" }
    private var caption: some View { Text("STYLE").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.faint).accessibilityHidden(true) }

    /// Never truncated: on one line beside its caption when it fits, else under it, else stacked (the titles keep whole words).
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { caption; Spacer(minLength: 4); control }.fixedSize(horizontal: true, vertical: false).frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 0) { caption; control }.fixedSize(horizontal: true, vertical: false).frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                caption
                StackedChoice(options: RaidStyle.allCases.map { .init(value: $0, title: $0.title, identifier: id($0)) }, selection: $style, label: "Raids style", identifier: "squad-style")
            }
        }
    }

    private var control: some View {
        SegmentedSwitch(segments: RaidStyle.allCases.map { .init(value: $0, title: $0.title, identifier: id($0)) },
                        selection: $style, metrics: .compact, label: "Raids style", identifier: "squad-style", singleLine: true)
    }
}

// MARK: the pinned squad strip (rule 34)

/// One chip of the pinned strip: a slot's number, the Pokémon's name (or "Empty") and the role colour.
struct SquadStripChip: Equatable, Identifiable {
    var id: Int
    var name: String
    var palette: SquadPaletteValue
    var editing: Bool
    var spoken: String
}

/// `SquadPalette` is not Equatable (Color); the strip compares the role it came from.
struct SquadPaletteValue: Equatable {
    var role: String?
    var palette: SquadPalette { role.map(SquadPalette.of) ?? SquadPalette.grey }
}

struct SquadStripModel: Equatable {
    var chips: [SquadStripChip]
    /// The slot number's palette comes from the card: Gym and Rocket have no role, so their chips use the screen's own palette.
    var ink: Color? = nil
    var tint: Color? = nil
    var open: (Int) -> Void = { _ in }
    static func == (l: SquadStripModel, r: SquadStripModel) -> Bool { l.chips == r.chips }
}

struct SquadStripKey: PreferenceKey {
    static var defaultValue: SquadStripModel? { nil }
    static func reduce(value: inout SquadStripModel?, nextValue: () -> SquadStripModel?) { if let n = nextValue() { value = n } }
}

extension View {
    /// While a slot's picker is open (`selected`), asks the screen to pin a strip of the squad's slots at the top of its scroll area; tapping a chip opens that slot's picker.
    func squadStrip(cards: [SlotCardModel], selected: Int?, ink: Color? = nil, tint: Color? = nil, open: @escaping (Int) -> Void) -> some View {
        let model: SquadStripModel? = selected.map { sel in
            SquadStripModel(chips: cards.map { c in
                let name = c.name ?? "Empty"
                let editing = c.id == sel
                return SquadStripChip(id: c.id, name: name, palette: SquadPaletteValue(role: c.role), editing: editing,
                                      spoken: (["Slot \(c.id + 1)", name, c.role].compactMap { $0 } + (editing ? ["editing"] : [])).joined(separator: ", "))
            }, ink: ink, tint: tint, open: open)
        }
        return preference(key: SquadStripKey.self, value: model)
    }
}

/// The strip itself: one line of chips, scrolling sideways when they do not fit, so at the accessibility sizes the chips keep whole words and the strip stays one line tall.
struct SquadStripView: View {
    let model: SquadStripModel
    @Environment(\.accent) private var accent
    /// The slot-number disc grows with the text, so the digit is never clipped at the accessibility sizes.
    @ScaledMetric(relativeTo: .footnote) private var disc: CGFloat = 20

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(model.chips) { chip($0) } }
                    .padding(.horizontal, Theme.Space.screen).padding(.vertical, 6)
            }
            // The slot being edited is kept in view (at the accessibility sizes only a chip or two fits).
            .onAppear { scrollToEditing(proxy) }
            .onChange(of: model.chips.first { $0.editing }?.id) { _, _ in scrollToEditing(proxy) }
        }
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("squad-strip")
    }

    private func scrollToEditing(_ proxy: ScrollViewProxy) {
        if let id = model.chips.first(where: \.editing)?.id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
    }

    private func chip(_ c: SquadStripChip) -> some View {
        let p = c.palette.palette
        let ink = model.ink ?? p.ink, tint = model.tint ?? p.tint
        return Button { model.open(c.id) } label: {
            HStack(spacing: 6) {
                Text("\(c.id + 1)").font(.figtree(12, .heavy, relativeTo: .caption)).foregroundStyle(Theme.surface)
                    .frame(minWidth: disc, minHeight: disc).background(Circle().fill(ink)).accessibilityHidden(true)
                Text(c.name).font(.figtree(13, c.editing ? .heavy : .bold, relativeTo: .footnote)).foregroundStyle(Theme.ink).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(minHeight: 44)
            .background(tint, in: Capsule())
            .overlay { if c.editing { Capsule().strokeBorder(accent.solid, lineWidth: 2.5) } }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.spoken)
        .accessibilityAddTraits(c.editing ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("squad-strip-chip-\(c.id + 1)")
        .id(c.id)
    }
}
