import SwiftUI
import PogoBox

// The pieces the five squad screens (Raids, Max, Gym, Rocket, PvP) share, from the pass 2 handoff's "Shared components": the SUGGESTIONS row, the slot card, the
// picker with its role chips and rows, and the Could get now list. They draw what the screens hand them; the rules (who is listed, in what order, what a role
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
        return .upgrade(cost: cost, label: HubSquads.upgradeLabel(b) ?? "Upgrade available: mark it as Dynamax on its page")
    }

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

// MARK: SUGGESTIONS · Available | Best · (i)

/// The right-aligned row every squad screen carries (rule 3, D18): the caption, the compact Available | Best switch and the "i". One setting per screen, kept per
/// account (`SquadStore.modes`). The explanation opens under the row as a card.
struct SuggestionsRow: View {
    @Binding var mode: SquadMode
    /// What Available and Best mean on this screen ("counters", "defenders", "a squad").
    let noun: String
    @State private var infoOpen = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { caption; control(singleLine: true); info }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .trailing, spacing: 0) { caption; HStack(spacing: 8) { control(singleLine: false); info } }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            if infoOpen {
                SquadExplainer(items: [
                    ("Available", "suggests \(noun) from your Pokémon as they are now: nothing to evolve or mega evolve first."),
                    ("Best", "suggests the strongest \(noun) your box can make, with the work each one needs."),
                ], identifier: "squad-mode-explainer")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var caption: some View {
        Text("SUGGESTIONS").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.faint).accessibilityHidden(true)
    }

    private func control(singleLine: Bool) -> some View {
        SegmentedSwitch(
            segments: [.init(value: SquadMode.available, title: "Available", identifier: "squad-mode-available"),
                       .init(value: SquadMode.best, title: "Best", identifier: "squad-mode-best")],
            selection: $mode, metrics: .compact, label: "Suggestions", identifier: "squad-mode", singleLine: singleLine)
    }

    private var info: some View { InfoButton(isOpen: $infoOpen, label: "About suggestions", identifier: "squad-mode-info") }
}

// MARK: slot cards

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
    /// The whole card for VoiceOver.
    var spoken: String
    var identifier: String
}

/// A slot card (pass 2 README, "Slot card"): radius 16, at least 92 pt; the role row in the role colour with the mark at its trailing end; a 30 pt disc; the name 13/700;
/// the type icons at the foot. Filled = the palette's tint; empty = a 2 pt inset outline; selected = a 2 pt inset outline in the accent.
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
                Text(model.name ?? "Empty").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(filled ? Theme.ink : Theme.muted)
                    .lineLimit(2).multilineTextAlignment(.leading)
                ForEach(model.lines, id: \.self) { Text($0).font(.figtree(11, .regular, relativeTo: .caption2)).foregroundStyle(Theme.muted).lineLimit(4).multilineTextAlignment(.leading) }
                Spacer(minLength: 0)
                if !model.types.isEmpty { TypeIcons(types: model.types, size: 18) }
            }
            .frame(maxWidth: .infinity, minHeight: 76, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(filled ? model.palette.tint : Color.clear, in: shape)
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
    /// An extra line in place of `note` (PvP's graded IV line).
    var noteView: AnyView? = nil
    /// The stacked figures before the end figure (Gym's DEF and HP).
    var stats: AnyView? = nil
    /// The end figure (Gym's BULK, PvP's SCORE).
    var figure: AnyView? = nil
    var spoken: String
}

/// A Could get now entry (rule 6): a top-tier Pokémon the box cannot make and that is attainable now, with where to get it.
struct CouldGetModel: Identifiable {
    var id: String
    var name: String
    var tier: String
    var roles: [String]
    var types: [String]
    var whereTags: [String]
    /// The research's own words, for VoiceOver.
    var why: String
}

extension CouldGetModel {
    init(_ c: HubSquads.CouldGet, types: [String]) {
        self.init(id: c.gap.id, name: c.gap.name, tier: c.gap.tier, roles: c.roles, types: types, whereTags: c.whereTags, why: c.why)
    }
}

/// The picker under a squad (README, "Picker"): `surface`, a 2 pt inset accent outline, radius 20, padding 12; the title with the "i" and Done; the role chips; the
/// rows; then Could get now. A row is a button with a selected state; choosing one puts the Pokémon in the slot and ticks it.
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
    var couldGet: [CouldGetModel] = []
    let onChoose: (String) -> Void
    let onDone: () -> Void
    @ViewBuilder var info: Info
    @State private var infoOpen = false
    @State private var couldGetOpen: Bool?
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
                    Rectangle().fill(Theme.line).frame(height: 1)
                    rowView(row)
                }
                if rows.isEmpty {
                    Text(couldGet.isEmpty ? emptyText : emptyText + " You could get these now:")
                        .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.vertical, 6).padding(.horizontal, 2)
                        .accessibilityIdentifier("squad-picker-empty")
                }
            }
            if !couldGet.isEmpty { couldGetView }
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
        let head = HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            SquadMarkView(mark: row.mark, showsCost: true)
        }
        let line = FlowLayout(spacing: 6) {
            if let role = row.role {
                Text(role).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(SquadPalette.of(role.components(separatedBy: " · ").first ?? role).ink)
            }
            if let tier = row.tier, !tier.isEmpty { TierChip(tier: tier, type: type) }
            ForEach(Array(row.types.enumerated()), id: \.offset) { _, t in TypeIcon(type: t.type, size: 22, grey: t.grey) }
        }
        let main = VStack(alignment: .leading, spacing: 4) {
            head
            line
            if let v = row.noteView { v } else if let n = row.note { Text(n).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
        }
        return Button { onChoose(row.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                tick(row.ticked)
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        main
                        if let s = row.stats { s }
                        if let f = row.figure { f }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    main.frame(maxWidth: .infinity, alignment: .leading)
                    if let s = row.stats { s }
                    if let f = row.figure { f }
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

    // MARK: Could get now

    private var couldGetView: some View {
        // Open when the box has no option for the slot; Next best rows are the closest options, not ones that fit, so it stays open under them too (D48).
        let open = couldGetOpen ?? (rows.isEmpty || heading != nil)
        return Group {
            if !open {
                Button { withAnimation(.easeOut(duration: 0.15)) { couldGetOpen = true } } label: {
                    Text("Could get now (\(couldGet.count)) ›").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink)
                        .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("squad-couldget-toggle")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("YOU COULD GET NOW").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.faint).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        // With no option in the box the list stays open: there is nothing to hide it behind.
                        if !rows.isEmpty && heading == nil {
                            Button { withAnimation(.easeOut(duration: 0.15)) { couldGetOpen = false } } label: {
                                Text("Hide").font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(accent.ink).frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityIdentifier("squad-couldget-hide")
                        }
                    }
                    ForEach(couldGet) { g in
                        Rectangle().fill(Theme.line).frame(height: 1)
                        couldGetRow(g)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("squad-couldget")
            }
        }
    }

    private func couldGetRow(_ g: CouldGetModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(g.name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                TierChip(tier: g.tier, type: type)
            }
            FlowLayout(spacing: 6) {
                ForEach(g.roles, id: \.self) { r in Text(r).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(SquadPalette.of(r).ink) }
                ForEach(Array(g.types.enumerated()), id: \.offset) { _, t in TypeIcon(type: t, size: 22) }
            }
            FlowLayout(spacing: 4) {
                ForEach(g.whereTags, id: \.self) { w in
                    let now = w == "Raids now"
                    Text(w.uppercased()).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.04 * 10)
                        .foregroundStyle(now ? accent.ink : Theme.ink)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(now ? accent.tint : Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(g.name), tier \(g.tier)\(g.roles.isEmpty ? "" : ", " + g.roles.joined(separator: " and ")). \(g.types.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " and ")). \(g.why). \(g.whereTags.joined(separator: ", "))")
    }
}

// MARK: Set this squad

/// "Set this squad" (accent button) or "✓ Squad set" with an underlined Undo (D26, D42, D55): the player's own mark that the raid or Max squad is ready.
struct SetSquadFooter: View {
    let isSet: Bool
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
                .accessibilityIdentifier("squad-set")
            }
        }
    }
}

// MARK: shared words

enum SquadWords {
    /// "Rock and Dark" for a VoiceOver label.
    static func typeList(_ types: [String]) -> String {
        let names = types.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1] : names.joined()
    }
}
