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

// MARK: status chips (pass 2-6, rule 35)

/// One status chip: a capsule with a sign and one word. Colour is never the only sign; the chip is hidden from VoiceOver, because the row's or card's own label carries the full words
/// ("In your box, needs upgrade, 206k dust", "Can get now, Easy", "In slot 5, choosing it swaps the two").
struct StatusChipModel: Equatable, Hashable {
    enum Kind: Equatable { case ready, upgrade, getNow, notNow, swap }
    var kind: Kind
    var text: String
    /// An upgrade chip with a cost draws the dust or candy icon after the value, as the arrow badge does.
    var currency: MyPokemon.Currency? = nil

    var ink: Color {
        switch kind {
        case .ready: return Theme.greenInk
        case .upgrade: return Theme.orangeInk
        case .getNow: return League.gl.ink
        case .notNow, .swap: return Theme.muted
        }
    }
    var tint: Color {
        switch kind {
        case .ready: return Theme.greenTint
        case .upgrade: return Theme.orangeTint
        case .getNow: return League.gl.tint
        case .notNow: return Theme.off
        case .swap: return Theme.surface2
        }
    }

    static let ready = StatusChipModel(kind: .ready, text: "✓ Ready")
    static let noBuild = StatusChipModel(kind: .upgrade, text: "↑ No build")
    static let getNow = StatusChipModel(kind: .getNow, text: "◎ Get now")
    /// "↑ 206k" with the cost, "↑ Upgrade" when the work has none to name (Mega Evolve alone, the Dynamax mark).
    static func upgrade(_ cost: MyPokemon.Cost?) -> StatusChipModel {
        cost.map { StatusChipModel(kind: .upgrade, text: "↑ " + $0.value, currency: $0.currency) } ?? StatusChipModel(kind: .upgrade, text: "↑ Upgrade")
    }
    static func meter(_ d: HubSquads.ObtainDifficulty) -> StatusChipModel { StatusChipModel(kind: .getNow, text: d.meter + " " + d.word) }
    static func notNow(when: String?) -> StatusChipModel { StatusChipModel(kind: .notNow, text: when.map { "◌ Not now · " + $0 } ?? "◌ Not now") }
    /// "⇄ Slot 5", or "⇄ Empty slot" when the edited slot is empty and choosing the Pokémon moves it here.
    static func swap(slot n: Int, moves: Bool) -> StatusChipModel { StatusChipModel(kind: .swap, text: moves ? "⇄ Empty slot" : "⇄ Slot \(n)") }

    /// The chips for a Pokémon: a Best row's one status (in the box: Ready, or the upgrade with its cost, or "No build" for a copy no build of the area serves; the box lacks it: Get now
    /// with the meter when the research gives one, else Not now with the month when the schedule knows it), or, for one of the player's own builds with no Best row, its mark.
    static func chips(best r: HubSquads.BestRow?, mark: SquadMark, today: String) -> [StatusChipModel] {
        func ofMark() -> [StatusChipModel] {
            switch mark {
            case .none: return []
            case .fullStrength: return [.ready]
            case .upgrade(let cost, _): return [.upgrade(cost)]
            }
        }
        guard let r else { return ofMark() }
        switch r.status.kind {
        case .inBox:
            if !r.hasBuild { return [.noBuild] }
            let m = ofMark()
            return m.isEmpty ? [r.status.needsUpgrade ? .upgrade(nil) : .ready] : m
        case .canGetNow:
            return [.getNow] + (r.difficulty.map { [.meter($0)] } ?? [])
        case .notAvailableNow:
            return [.notNow(when: HubSquads.notNowWhen(rotationLine: r.rotationLine, today: today))]
        }
    }
}

struct StatusChip: View {
    let model: StatusChipModel

    var body: some View {
        HStack(spacing: 3) {
            Text(model.text).font(.figtree(10.5, .bold, relativeTo: .caption2)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            if let c = model.currency { CurrencyIcon(currency: c) }
        }
        .foregroundStyle(model.ink)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(model.tint, in: Capsule())
        .accessibilityHidden(true)
    }
}

/// The chips of a row or a card in one wrapping line.
struct StatusChips: View {
    let chips: [StatusChipModel]
    var body: some View {
        if !chips.isEmpty { FlowLayout(spacing: 4) { ForEach(Array(chips.enumerated()), id: \.offset) { _, c in StatusChip(model: c) } } }
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
    /// The row's one status (S1) with "same copy as <higher row>" after it when a higher row already shows the copy: the words VoiceOver reads (the screen draws the status as chips).
    var statusLine: String { [status.text, sharedWith.map { "same copy as \($0)" }].compactMap { $0 }.joined(separator: " · ") }
    /// The muted line a row or card keeps when a higher row already shows the copy.
    var sharedLine: String? { sharedWith.map { "Same copy as \($0)" } }
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
    /// Muted lines under the name ("beats 2 of 3", "vs Zekrom", "level not read", "Same copy as …"): not a status, which the chips say.
    var lines: [String] = []
    var types: [String] = []
    var mark: SquadMark = .none
    /// The slot's status as chips in a wrapping row after the name (pass 2-6, rule 35). The card's colour (rule 29) is `status`.
    var chips: [StatusChipModel] = []
    /// The slot's Pokémon is one the box lacks (a Best species pick): its strip chip draws a hollow number and a dashed edge.
    var notInBox = false
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

/// The squad's strength bar (CONCEPTS rule 32), under the status line: "Squad strength 78% of best" (the squad's slot figures over the Best squad's; "Squad strength 100%" at or over it) and "92% after upgrades" over one bar drawn as a picker row's bar is (solid = now, faint
/// = after the suggested upgrades), and "5 of 6 slots scored" when a slot has no figure. VoiceOver reads the words as one element; the bar is hidden from it. `strength` is nil
/// while it is being worked out (off the main thread): the row keeps its height with an empty track, so nothing below it moves. Pass 2-6: one label, "Squad strength 41% of best ·
/// 87% after upgrades", in one tone with the two figures bold, the after part only when the bar draws its faint part; at accessibility text sizes it wraps.
struct SquadStrengthLine: View {
    let strength: SquadStrength?
    let type: ContentType
    @Environment(\.accent) private var accent

    /// The label's words split into runs, each marked bold when it is a figure ("41%").
    static func runs(_ s: SquadStrength) -> [(text: String, bold: Bool)] {
        let full = [s.text, s.afterText].compactMap { $0 }.joined(separator: " · ")
        guard let re = try? NSRegularExpression(pattern: #"\d+%"#) else { return [(full, false)] }
        var out = [(text: String, bold: Bool)](), at = full.startIndex
        for m in re.matches(in: full, range: NSRange(full.startIndex..., in: full)) {
            guard let r = Range(m.range, in: full) else { continue }
            if at < r.lowerBound { out.append((String(full[at..<r.lowerBound]), false)) }
            out.append((String(full[r]), true))
            at = r.upperBound
        }
        if at < full.endIndex { out.append((String(full[at...]), false)) }
        return out
    }

    /// What the row is laid out with while the figure is worked out: a typical finished row (the words, the "after" words and a bar), drawn as a redacted placeholder, so the
    /// slots below keep their place at every text size when the figure arrives.
    private var sample: SquadStrength { SquadStrength(kind: type == .pvp ? .score : .damage, now: 0.5, after: 0.6, scored: 6, total: 6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            do {
                let strength = strength ?? sample
                let words = Self.runs(strength).reduce(Text("")) { $0 + Text($1.text).font(.figtree(13, $1.bold ? .heavy : .medium, relativeTo: .footnote)) }
                words.foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
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
        let name = model.name.map(SquadWords.boxName)
        let filled = name != nil
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                if let role = model.role {
                    Text(role.uppercased()).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(model.palette.ink)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                }
                Text(filled ? String(name!.prefix(1)) : model.disc)
                    .font(.figtree(filled ? 14 : 18, .heavy, relativeTo: .subheadline))
                    .foregroundStyle(filled ? Theme.surface : model.palette.ink)
                    .frame(width: min(discSize, 80), height: min(discSize, 80))
                    .background(Circle().fill(filled ? model.palette.ink : Theme.off))
                    .accessibilityHidden(true)
                Text(name ?? "Empty").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(filled ? Theme.ink : Theme.mutedOnTint)
                    .lineLimit(2).multilineTextAlignment(.leading)
                // The status, once, as chips (a sign, a colour, one word); VoiceOver gets the card's own words.
                StatusChips(chips: model.chips)
                ForEach(model.lines, id: \.self) { Text($0).font(.figtree(11, .regular, relativeTo: .caption2)).foregroundStyle(Theme.mutedOnTint).lineLimit(4).multilineTextAlignment(.leading) }
                Spacer(minLength: 0)
                if !model.types.isEmpty { TypeIcons(types: model.types, size: 18) }
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
        .accessibilityLabel(SquadWords.spokenBox(model.spoken))
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
        // D72: where the cards are in the screen's scroll area, so the pinned strip shows only once they have scrolled off the top (`HubTypeScreen`).
        .background { GeometryReader { Color.clear.preference(key: SquadCardsFrameKey.self, value: $0.frame(in: .named(squadScrollSpace))) } }
    }
}

/// The name of the coordinate space `HubTypeScreen` gives its scroll view; the slot cards report their frame in it.
let squadScrollSpace = "squad-scroll"

/// The frame of the squad's slot cards in the scroll view's space (nil on a screen without them).
struct SquadCardsFrameKey: PreferenceKey {
    static var defaultValue: CGRect? { nil }
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { if let n = nextValue() { value = n } }
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
    /// A muted line under the first ("From Eevee", "Not weak to this slot", "Same copy as …"): not a status, which the chips say.
    var note: String? = nil
    /// The row's status as chips in one wrapping row under the name line (pass 2-6, rule 35); a row in another slot also carries "⇄ Slot 5".
    var chips: [StatusChipModel] = []
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
    /// The mark at the head of a picker row (H5): not the full-strength tick when the "✓ Ready" chip says it.
    var headMark: SquadMark { mark == .fullStrength && chips.contains(.ready) ? .none : mark }

    /// The chips a picker row draws (H5): an upgrade chip reads "↑ Upgrade" because the head carries the cost; "↑ No build" and the rest are as they are.
    var pickerChips: [StatusChipModel] {
        guard case .upgrade = mark else { return chips }
        return chips.map { $0.kind == .upgrade && $0 != .noBuild ? .upgrade(nil) : $0 }
    }

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
            m.chips.append(.swap(slot: n, moves: moves))
            m.spoken += ", in slot \(n), choosing it \(moves ? "moves it here" : "swaps the two")"
            return m
        }
    }

    static let upgradesHeading = "Available upgrades:"
    static let otherRolesHeading = "Other roles:"

    /// D73: the rows by the strength figure the bar shows, strongest first: the figure after the upgrade (the figure now when there is none), ties by the figure now, then the order given.
    /// A row with no figure goes last.
    static func orderedByStrength(_ rows: [PickerRowModel]) -> [PickerRowModel] {
        func figures(_ r: PickerRowModel) -> (after: Double, now: Double) {
            let now = r.strength?.now, after = r.strength?.after ?? now
            return (after ?? -1, now ?? -1)
        }
        return rows.enumerated().sorted { a, b in
            let x = figures(a.element), y = figures(b.element)
            if x.after != y.after { return x.after > y.after }
            if x.now != y.now { return x.now > y.now }
            return a.offset < b.offset
        }.map(\.element)
    }

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

    /// A Best row without a build: a Pokémon the box lacks, or a copy of it that no build of the area serves. The status is the row's chips; VoiceOver keeps the words
    /// ("In your box, needs upgrade, no build for this").
    init(best r: HubSquads.BestRow, ticked: Bool, role: String? = nil, types: [PickerType]? = nil, extraSpoken: String? = nil, today: String) {
        let spoken = [r.name, role, "tier \(r.tier)", SquadWords.typeList(r.types), r.statusLine.replacingOccurrences(of: " · ", with: ", "), extraSpoken, ticked ? "in this slot" : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        self.init(id: r.entryId, name: r.name, ticked: ticked, role: role, tier: r.tier, types: types ?? r.types.map { PickerType(type: $0) }, note: r.sharedLine,
                  chips: StatusChipModel.chips(best: r, mark: .none, today: today), spoken: spoken)
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
        return PickerRowModel(id: id, name: e.row.title, ticked: ticked, mark: mark, types: types.map { PickerType(type: $0) }, chips: build == nil ? [.noBuild] : StatusChipModel.chips(best: nil, mark: mark, today: ""), spoken: spoken)
    }
}

extension SlotCardModel {
    /// The card of a Best row without a build: a Pokémon the box lacks (red, with the short rotation date when there is one; VoiceOver carries the whole availability
    /// line), or a copy no build of the area serves (amber).
    init(id: Int, role: String?, palette: SquadPalette, emptyOutline: Color, disc: String, best r: HubSquads.BestRow, extra: [String] = [], spokenExtra: [String] = [], head: String, today: String, identifier: String) {
        let status: HubSquads.SlotStatus = r.inBox ? .needsWork : .toGet
        let said = [r.spokenStatus]
        let spoken = ([head, r.name, SquadWords.typeList(r.types)] + spokenExtra + said + [status.spoken]).filter { !$0.isEmpty }.joined(separator: ", ")
        self.init(id: id, role: role, palette: palette, emptyOutline: emptyOutline, disc: disc, name: SquadWords.boxName(r.name), lines: (r.sharedLine.map { [$0] } ?? []) + extra, types: r.types,
                  chips: StatusChipModel.chips(best: r, mark: .none, today: today), notInBox: !r.inBox, status: status, spoken: spoken, identifier: identifier)
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
    /// Pass 2-6, rule 10: the Mega chip is chosen on a slot that is not the squad's Mega while another slot holds one. The rows area then shows only the one line, in place of the rows and
    /// of the empty text.
    var oneMegaMessage = false
    /// The chip drawn as chosen when it is not the slot's role (the Mega chip while it only shows the one-Mega message).
    var chipShown: String? = nil
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
            if oneMegaMessage {
                Text(SquadWords.oneMega).font(.figtree(13.5, .heavy, relativeTo: .footnote)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("squad-picker-one-mega")
            } else {
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
                    let on = r == (chipShown ?? role), p = SquadPalette.of(r)
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
        let name = Text(SquadWords.boxName(row.name)).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        // Each status once (H5, the panel's rows): an upgrade keeps the cost badge at the head and its chip reads "↑ Upgrade"; a Ready row has the "✓ Ready" chip and no tick at the head.
        let mark = row.headMark
        let head = Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) { name; SquadMarkView(mark: mark, showsCost: true) }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) { name; SquadMarkView(mark: mark, showsCost: true) }
            }
        }
        // The tier sits at the end of the strength bar when the row has one, else beside the types as before.
        let bar = row.strength
        let tier = row.tier.flatMap { $0.isEmpty ? nil : $0 }
        // The role word is drawn only while the chosen role chip is All (pass 2-6): under a role the chip already says it.
        let roleText = (role == squadRoleAll ? row.role : nil).map { role in
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
            StatusChips(chips: row.pickerChips)
            line
        }
        let tail = VStack(alignment: .leading, spacing: 4) {
            if let bar { strengthLine(bar, tier: tier) }
            if let v = row.noteView { v } else if let n = row.note { Text(n).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
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
        .accessibilityLabel(SquadWords.spokenBox(row.spoken))
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

    /// Pass 2-6, rule 14 / word check (D69, H3): a Shadow Pokémon is named as the box names it, "Gardevoir (Shadow)", on every squad screen. The Raids table (and so every Best row but
    /// the Raids damage-ranked ones) names it "Shadow Gardevoir": a leading "Shadow " becomes the " (Shadow)" suffix. A Mega or Primal the game master writes as a bracket is written
    /// in front, as the game does (`SquadNames.display`: "Rayquaza (Mega)" is "Mega Rayquaza", "Charizard (Mega X)" is "Mega Charizard X"). Every other name stays as it is.
    static func boxName(_ name: String) -> String {
        guard name.hasPrefix("Shadow "), !name.hasSuffix("(Shadow)") else { return SquadNames.display(name) }
        return String(name.dropFirst("Shadow ".count)) + " (Shadow)"
    }

    /// The same for a spoken label, whose parts are separated by ", ".
    static func spokenBox(_ spoken: String) -> String { spoken.components(separatedBy: ", ").map(boxName).joined(separator: ", ") }

    /// The picker's line when the Mega chip is chosen for a slot while another slot holds the squad's Mega (rule 10); also an empty Mega slot's line.
    static let oneMega = "You can only have 1 Mega slot"

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

// MARK: Available | Best | Current  (pass 2-6, rule 27)

/// The row every squad screen carries over its squad: the compact Available | Best switch with Current as a third segment on the right once the squad has one (no caption, no "i" of its
/// own: the title's "i" explains the tabs). On Raids the style switch shares the row, tabs left and style right; if both do not fit on one line the style goes under the tabs,
/// right-aligned, and at the largest text sizes both become stacked choices. Available and Best are the suggestions (the player's edits are kept, `SquadStore.edits`); the choice
/// between them is remembered per account (`SquadStore.modes`).
struct SquadTabsRow: View {
    @Binding var tab: SquadTab
    let hasCurrent: Bool
    /// Raids only (rule 33): Balanced | Max damage.
    var style: Binding<RaidStyle>? = nil

    private var tabs: [SquadTab] { hasCurrent ? [.available, .best, .current] : [.available, .best] }
    private func styleId(_ s: RaidStyle) -> String { "squad-style-\(s == .balanced ? "balanced" : "max-damage")" }

    var body: some View {
        // The labels always render at one size (never shrunk one by one): on one line when they fit, else the style under the tabs, else stacked, one to a line.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                tabsControl
                Spacer(minLength: 8)
                if style != nil { styleControl }
            }
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 0) { tabsControl; Spacer(minLength: 0) }
                if style != nil { styleControl }
            }
            VStack(alignment: .leading, spacing: 8) {
                StackedChoice(options: tabs.map { .init(value: $0, title: $0.title, identifier: "squad-tab-\($0.rawValue)") }, selection: $tab, label: "Squad", identifier: "squad-mode")
                if let style {
                    StackedChoice(options: RaidStyle.allCases.map { .init(value: $0, title: $0.title, identifier: styleId($0)) }, selection: style, label: "Raids style", identifier: "squad-style")
                }
            }
        }
    }

    private var tabsControl: some View {
        SegmentedSwitch(segments: tabs.map { .init(value: $0, title: $0.title, identifier: "squad-tab-\($0.rawValue)") },
                        selection: $tab, metrics: .compact, label: "Squad", identifier: "squad-mode", singleLine: true)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var styleControl: some View {
        if let style {
            SegmentedSwitch(segments: RaidStyle.allCases.map { .init(value: $0, title: $0.title, identifier: styleId($0)) },
                            selection: style, metrics: .compact, label: "Raids style", identifier: "squad-style", singleLine: true)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// A choice between a few options drawn as a column of full-width buttons: what a segmented switch becomes when its titles cannot fit on one line at the accessibility text sizes
/// (the titles keep whole words and one size). The same identifiers, labels and selected trait as the switch; the chosen option is on the accent tint in the accent ink, as the
/// switch draws it.
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
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 4) {
            ForEach(options) { o in
                let on = o.value == selection
                Button { selection = o.value } label: {
                    Text(o.title).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(on ? accent.ink : Theme.ink).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? accent.tint : Color.clear, in: Capsule()).contentShape(Capsule())
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

// MARK: the pill and the row under the switches

/// The one pill (rule 27.8): "Set this squad" (solid accent) when the tab's squad as drawn is not the Current, "✓ Squad set" (accent tint, a 1.5 pt accent outline, accent ink) when
/// it is. Same height, padding and shape in both states, so nothing moves. Tapping it sets or unsets at once; the toast the screen shows offers Undo.
struct SetSquadPill: View {
    let isSet: Bool
    let onSet: () -> Void
    let onUnset: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button { if isSet { onUnset() } else { onSet() } } label: {
            Text(isSet ? "✓ Squad set" : "Set this squad").font(.figtree(14, isSet ? .heavy : .bold, relativeTo: .subheadline))
                .foregroundStyle(isSet ? accent.ink : accent.onSolid)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(isSet ? accent.tint : accent.solid, in: Capsule())
                .overlay { Capsule().strokeBorder(isSet ? accent.solid : Color.clear, lineWidth: 1.5) }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isSet ? "Squad set" : "Set this squad")
        .accessibilityHint(isSet ? "Tap to unset" : "Makes this your current squad")
        .accessibilityAddTraits(isSet ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("squad-set")
    }
}

/// The row under the switches: the squad's status on the left and, on Available and Best, the pill on the right. At the accessibility sizes the pill goes under the status.
struct SquadStatusRow: View {
    let team: HubSquads.TeamStatus?
    /// nil on the Current tab (no pill).
    var pill: SetSquadPill? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if team != nil || pill != nil {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { status; if let pill { pill } }
            } else {
                HStack(alignment: .center, spacing: 8) { status; if let pill { pill } }
            }
        }
    }

    @ViewBuilder private var status: some View {
        if let team { SquadStatusLine(status: team) } else { Spacer(minLength: 0) }
    }
}

/// Under the slots of an Available or Best tab whose edit differs from the suggestion: "Reset to suggestion", which drops the kept edit at once (no question).
struct SquadResetLink: View {
    let onReset: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        HStack {
            Button(action: onReset) {
                Text("Reset to suggestion").font(.figtree(14, .bold, relativeTo: .subheadline)).underline().foregroundStyle(accent.ink)
                    .padding(.horizontal, 4).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityHint("Drops your changes to this squad and shows the suggestion again")
            .accessibilityIdentifier("squad-reset-draft")
            Spacer(minLength: 0)
        }
    }
}

/// "Delete current squad" on the Current tab: asks first ("Delete current squad?" with Delete and Cancel and no message), then the Current moves to the history. Available and Best are
/// not changed.
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
            Button("Delete", role: .destructive, action: action).accessibilityIdentifier("squad-delete-current-confirm")
            Button("Cancel", role: .cancel) {}.accessibilityIdentifier("squad-delete-current-cancel")
        }
    }
}

// MARK: Earlier current squads (pass 2-6, rule 27.10)

/// One slot of a history row: an 18 pt disc in the slot's role colours with the Pokémon's first letter; a dashed hollow disc in muted ink for a Pokémon no longer in the box (with "?" when
/// nothing remembers its name); a grey disc with no letter for an empty slot.
struct HistoryDisc {
    var name: String?
    var palette: SquadPalette
    /// The copy is still in the box (a species pick counts as present).
    var present = true

    var letter: String? { name.map { String(SquadWords.boxName($0).prefix(1)) } ?? (present ? nil : "?") }
    /// For VoiceOver: "Gardevoir", "Zacian not in your box", "empty slot".
    var spoken: String {
        guard let name else { return present ? "empty slot" : "a Pokémon not in your box" }
        return SquadWords.boxName(name) + (present ? "" : " not in your box")
    }
}

struct HistoryRowModel: Identifiable {
    /// 0 for the newest entry; the row's identifiers count from 1.
    var index: Int
    var when: String
    var discs: [HistoryDisc]
    /// "41%", or "—" when the figure was not worked out.
    var percent: String
    var id: Int { index }

    var spoken: String {
        let figure = percent == "—" ? "no figure" : (percent == "100%" ? "100%" : percent + " of best")
        return ([when] + discs.map(\.spoken) + [figure]).joined(separator: ", ")
    }
}

extension HistoryRowModel {
    /// "Today 10:16", "Yesterday 18:40", else "5 Nov 09:12", in the device's locale and 12 or 24 hour style.
    static func when(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = DateFormatter()
        time.locale = locale; time.calendar = calendar; time.timeZone = calendar.timeZone
        time.setLocalizedDateFormatFromTemplate("jm")
        let t = time.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "Today " + t }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday " + t }
        let day = DateFormatter()
        day.locale = locale; day.calendar = calendar; day.timeZone = calendar.timeZone
        day.setLocalizedDateFormatFromTemplate("dMMM")
        return day.string(from: date) + " " + t
    }

    static func rows(_ entries: [HistoryEntry], now: Date, disc: (SquadSlot) -> HistoryDisc) -> [HistoryRowModel] {
        entries.enumerated().map { i, e in
            HistoryRowModel(index: i, when: when(e.date, now: now), discs: e.slots.map(disc), percent: e.strength.map { "\($0)%" } ?? "—")
        }
    }
}

/// EARLIER CURRENT SQUADS and its rows (newest first, up to ten). Shown only when there is one. A row is one VoiceOver element (the date, each Pokémon, the figure) with "Set squad"
/// as its action; the discs are not tappable.
struct SquadHistoryList: View {
    let rows: [HistoryRowModel]
    let onSet: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("EARLIER CURRENT SQUADS").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.faint)
                    .padding(.top, 4).padding(.bottom, 2).accessibilityAddTraits(.isHeader)
                ForEach(rows) { r in
                    Rectangle().fill(Theme.line).frame(height: 1)
                    row(r)
                }
            }
        }
    }

    private func row(_ r: HistoryRowModel) -> some View {
        let n = r.index + 1
        let date = Text(r.when).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.ink).lineLimit(2)
        let discs = HStack(spacing: 3) { ForEach(Array(r.discs.enumerated()), id: \.offset) { _, d in HistoryDiscView(disc: d) } }
        let percent = Text(r.percent).font(.figtree(11.5, .bold, relativeTo: .caption)).foregroundStyle(Theme.muted).monospacedDigit()
        let pill = Button { onSet(r.index) } label: {
            HistoryPill().frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityHidden(true)
        .accessibilityIdentifier("squad-history-set-\(n)")
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { date; Spacer(minLength: 8); percent }
                    discs
                    HStack { Spacer(minLength: 0); pill }
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 8) {
                    date.frame(minWidth: 54, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    discs
                    percent.lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(minWidth: 32, alignment: .trailing)
                    Spacer(minLength: 0)
                    pill
                }
                .frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SquadWords.spokenBox(r.spoken))
        .accessibilityAction(named: "Set squad") { onSet(r.index) }
        .accessibilityIdentifier("squad-history-row-\(n)")
    }
}

/// The small "Set squad" pill: accent tint, accent outline, accent ink, 11.5 pt bold, 6 by 11 pt padding, 32 pt at least.
private struct HistoryPill: View {
    @Environment(\.accent) private var accent
    var body: some View {
        Text("Set squad").font(.figtree(11.5, .bold, relativeTo: .caption)).foregroundStyle(accent.ink)
            .padding(.horizontal, 11).padding(.vertical, 6).frame(minHeight: 32)
            .background(accent.tint, in: Capsule())
            .overlay { Capsule().strokeBorder(accent.solid, lineWidth: 1.5) }
    }
}

private struct HistoryDiscView: View {
    let disc: HistoryDisc
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 18

    var body: some View {
        let d = min(size, 40)
        ZStack {
            if disc.name == nil && disc.present {
                Circle().fill(Theme.off)
            } else if disc.present {
                Circle().fill(disc.palette.ink)
            } else {
                Circle().strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
            }
            if let l = disc.letter {
                Text(l).font(.figtree(10, .heavy, relativeTo: .caption2)).foregroundStyle(disc.present ? Theme.surface : Theme.muted)
            }
        }
        .frame(width: d, height: d)
        .accessibilityHidden(true)
    }
}

// MARK: the pinned squad strip (rule 34)

/// One chip of the pinned strip: a slot's number, the Pokémon's name (or "Empty") and the role colour.
struct SquadStripChip: Equatable, Identifiable {
    var id: Int
    /// The Pokémon's name without a trailing "(Shadow)" ("Gardevoir (Shadow)" is "Gardevoir"), or "Empty".
    var name: String
    var palette: SquadPaletteValue
    var editing: Bool
    /// The slot holds a Pokémon the box lacks (a Best species pick): a hollow number and a dashed edge.
    var notInBox = false
    /// The slot is empty: the chip is grey, never the role or screen palette (H7).
    var empty = false
    var spoken: String

    /// Only a trailing " (Shadow)" is dropped (D69: the chip is narrow, and the Shadow is not what tells two chips apart), off a name as `SquadWords.boxName` gives it: "Gardevoir (Shadow)" is
    /// "Gardevoir". Every other bracket stays ("Giratina (Origin)", "Zamazenta (Crowned Shield)"), as does a Mega or Primal in front ("Mega Charizard X"), so two forms never both read the same.
    static func shortName(_ name: String) -> String {
        name.hasSuffix(" (Shadow)") ? String(name.dropLast(" (Shadow)".count)) : name
    }
}

extension SquadStripChip {
    /// The chip of a slot card while the slot `selected` is being edited.
    init(card c: SlotCardModel, selected: Int) {
        let full = c.name.map(SquadWords.boxName) ?? "Empty"
        let editing = c.id == selected
        let missing = c.name != nil && c.notInBox
        self.init(id: c.id, name: c.name == nil ? "Empty" : Self.shortName(full), palette: SquadPaletteValue(role: c.role), editing: editing, notInBox: missing, empty: c.name == nil,
                  spoken: (["Slot \(c.id + 1)", full, c.role].compactMap { $0 } + (missing ? ["not in your box"] : []) + (editing ? ["editing"] : [])).joined(separator: ", "))
    }
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
            SquadStripModel(chips: cards.map { SquadStripChip(card: $0, selected: sel) }, ink: ink, tint: tint, open: open)
        }
        return preference(key: SquadStripKey.self, value: model)
    }
}

/// The strip itself: the squad's chips in rows of three, each chip a third of the width, so a six-slot squad is two rows and a three-slot squad one, with no sideways scrolling. At the
/// accessibility sizes the rows stay, a chip's name wraps to two lines and the strip grows (the list below is inset by its height).
struct SquadStripView: View {
    let model: SquadStripModel
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The slot-number disc grows with the text, so the digit is never clipped at the accessibility sizes.
    @ScaledMetric(relativeTo: .footnote) private var disc: CGFloat = 20

    private static let perRow = 3

    var body: some View {
        let rows = stride(from: 0, to: model.chips.count, by: Self.perRow).map { Array(model.chips[$0..<min($0 + Self.perRow, model.chips.count)]) }
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { chip($0) }
                    // A short last row keeps its chips a third of the width.
                    ForEach(0..<(Self.perRow - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, minHeight: 1) }
                }
            }
        }
        .padding(.horizontal, Theme.Space.screen).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("squad-strip")
    }

    private func chip(_ c: SquadStripChip) -> some View {
        // An empty slot's chip is grey, as an Empty slot card is, whatever the role or the screen's own palette (H7).
        let p = c.empty ? SquadPalette.grey : c.palette.palette
        let ink = c.empty ? p.ink : (model.ink ?? p.ink), tint = c.empty ? p.tint : (model.tint ?? p.tint)
        let d = min(disc, 44)
        return Button { model.open(c.id) } label: {
            HStack(spacing: 6) {
                Text("\(c.id + 1)").font(.figtree(12, .heavy, relativeTo: .caption)).foregroundStyle(c.notInBox ? ink : Theme.surface)
                    .frame(minWidth: d, minHeight: d)
                    .background { if c.notInBox { Circle().strokeBorder(ink, lineWidth: 2) } else { Circle().fill(ink) } }
                    .accessibilityHidden(true)
                Text(c.name).font(.figtree(13, c.editing ? .heavy : .bold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
                    .lineLimit(2).truncationMode(.tail).minimumScaleFactor(typeSize.isAccessibilitySize ? 0.6 : 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(tint, in: Capsule())
            .overlay { if c.notInBox { Capsule().strokeBorder(ink, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) } }
            .overlay { if c.editing { Capsule().strokeBorder(accent.solid, lineWidth: 2.5) } }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.spoken)
        .accessibilityAddTraits(c.editing ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("squad-strip-chip-\(c.id + 1)")
    }
}

// MARK: the title's (i) and the history's names (pass 2-6)

/// The lines every squad screen's (i) opens with: what the three tabs are, how the squad is set, then one line per status chip sign (rule 35). The screen adds its suggestion (and, on
/// Raids, the style) between them.
enum SquadInfo {
    static func tabs(noun: String) -> [(term: String, text: String)] {
        [("Current", "is the squad you have set. Changes to it are kept straight away. While the squad has one, the earlier current squads are listed under it, and Set squad on one makes it the current squad again."),
         ("Available", "picks \(noun) from the Pokémon in your box right now: the strongest you own for each slot, even if it still needs a power up, an evolution or a Mega Evolution first. Tap a slot for other choices from your box."),
         ("Best", "lists the best Pokémon in the game for each slot, whether or not you have them. Each says if it is in your box, can be got now, or is not available now.")]
    }

    static let setting: (term: String, text: String) = ("", "Changes you make to Available and Best are kept as you make them; Reset to suggestion drops them. Set this squad makes the squad you are looking at your Current, and tapping Squad set unsets it.")

    static let signs: [(term: String, text: String)] = [
        ("✓ Ready:", "nothing left to do."),
        ("↑ with a cost:", "a power up, evolution or Mega Evolution still to do."),
        ("◎ Get now:", "a boss on now, or easy to obtain (the bars show how hard)."),
        ("◌ Not now:", "not obtainable now; a month shows when it is next on."),
        ("⇄ Slot N:", "this Pokémon is in another slot; choosing it swaps the two."),
    ]
}

extension HubContext {
    /// A species pick's name ("Gardevoir (Shadow)" for `gardevoir_shadow`, "Mega Rayquaza" for `rayquaza_mega`).
    func speciesName(_ key: String) -> String {
        if let n = gm.byId[key]?.name { return SquadNames.display(n) }
        if key.hasSuffix("_shadow"), let n = gm.byId[String(key.dropLast("_shadow".count))]?.name { return n + " (Shadow)" }
        return "Pokémon"
    }

    /// The name a squad screen gives a copy: the target of its build for THIS screen's area, as the slot card names it, else the box title (H3: a disc's letter matches the slot card).
    func pickName(_ id: String, screen: SquadScreen) -> String? {
        squadPickName(id, entries: entries, builds: advice.builds, screen: screen)
    }
}

extension SquadStore {
    /// One slot of a history row. A copy still in the box is named as a slot card names it; one that left is named from what the store remembered while it was there and drawn hollow; a
    /// species pick counts as present; an empty slot is grey.
    func historyDisc(_ slot: SquadSlot, ctx: HubContext, palette: SquadPalette, screen: SquadScreen) -> HistoryDisc {
        if let p = slot.pick {
            if ctx.entry(p) != nil { return HistoryDisc(name: ctx.pickName(p, screen: screen), palette: palette) }
            return HistoryDisc(name: pickName(for: p, area: screen.rawValue), palette: palette, present: false)
        }
        if let key = slot.species { return HistoryDisc(name: ctx.speciesName(key), palette: palette) }
        return HistoryDisc(name: nil, palette: palette)
    }

    /// The history rows of a squad for the Current tab.
    func historyRows(_ ref: SquadRef, ctx: HubContext, now: Date = Date(), palette: @escaping (SquadSlot) -> SquadPalette) -> [HistoryRowModel] {
        HistoryRowModel.rows(history[ref.key] ?? [], now: now) { historyDisc($0, ctx: ctx, palette: palette($0), screen: ref.screen) }
    }
}
