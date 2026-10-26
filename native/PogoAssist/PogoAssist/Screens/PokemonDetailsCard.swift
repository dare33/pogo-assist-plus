import SwiftUI
import PogoBox
import PogoReader

/// The details card at the top of the Pokémon page (design pass 3, D4, D22, D26): name, types and CP, level and HP with the three marks, the IV bars, and
/// the advanced details below a hairline when open. Every mark and chip makes its edit through `apply`, which the page saves as a box version.
struct PokemonDetailsCard: View {
    let entry: BoxEntry
    /// The Mega form the page shows now, if any: its name, CP, level and HP replace the entry's, the IVs and marks stay the entry's.
    let mega: MegaForm?
    @Binding var advancedOpen: Bool
    /// Takes the edit as a function of the row as it is when the edit is applied, so two quick edits (each replacing the whole details) both persist.
    let apply: (@escaping (ScanRow) -> BoxMerge.Edit) -> Void
    @Environment(\.accent) private var accent

    private var row: ScanRow { entry.row }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            top
            metaAndMarks
            bars
            if advancedOpen {
                Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 4)
                AdvancedDetailsView(entry: entry, apply: apply)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .panelShadow()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("details-card")
    }

    // MARK: name, types, CP

    private var title: String { mega?.title ?? row.title }
    private var cp: Int { mega?.cp ?? row.cp }
    /// The Mega form's own types while the page shows it, else the entry's.
    private var types: [String] { PokemonPage.types(of: mega?.speciesId ?? row.speciesId, fallback: row.speciesId, gm: try? GameMaster.bundled()) }

    private var nameLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.figtree(28, .heavy, relativeTo: .title)).tracking(-0.025 * 28).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            TypeIcons(types: types, size: 22)
        }
    }

    private var cpFigure: some View {
        // One text so VoiceOver and the tests read "CP 782" (the board sets the CP small beside the figure).
        (Text("CP ").font(.figtree(12, .heavy, relativeTo: .caption)).foregroundStyle(Theme.muted)
            + Text(cp > 0 ? String(cp) : "not known").font(.figtree(cp > 0 ? 22 : 15, .heavy, relativeTo: .title2)).monospacedDigit().foregroundStyle(Theme.ink))
            .fixedSize()
    }

    private var top: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) { nameLine; Spacer(minLength: 8); cpFigure }
            VStack(alignment: .leading, spacing: 4) { nameLine; cpFigure }
        }
    }

    // MARK: level, HP and the marks

    private var meta: String {
        let level = mega != nil ? Fmt.level(mega?.level, mega?.levelMax) : Fmt.level(row), hp = mega != nil ? mega?.hp : row.hp
        return [level.map { "Level \($0)" } ?? "Level not known", hp.map { "HP \($0)" } ?? "HP not read"].joined(separator: " · ")
    }

    private var metaAndMarks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { metaText; Spacer(minLength: 8); marks }
            VStack(alignment: .leading, spacing: 0) { metaText; marks }
        }
    }

    private var metaText: some View {
        Text(meta).font(.figtree(14, .semibold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Three 32 pt round marks with 44 pt tap areas: Dynamax, Shadow, Advanced details (D22, D26).
    private var marks: some View {
        HStack(spacing: 0) {
            MarkButton(kind: .dynamax, on: row.dynamax == true, name: "Dynamax", identifier: "mark-dynamax",
                       hint: row.dynamax == true ? "Clears the mark" : "Marks it as caught as Dynamax") { apply { PokemonPage.toggleDynamax($0) } }
            MarkButton(kind: .shadow, on: row.shadow == 1, name: "Shadow", identifier: "mark-shadow",
                       hint: row.shadow == 1 ? "Clears the mark" : "Marks it as a Shadow Pokémon") { apply { PokemonPage.toggleShadow($0) } }
            MarkButton(kind: .advanced, on: advancedOpen, name: "Advanced details", identifier: "mark-advanced", isToggle: false,
                       hint: advancedOpen ? "Closes the section" : "Opens moves, Max move levels, the Mega level and more") {
                withAnimation(.easeOut(duration: 0.2)) { advancedOpen.toggle() }
            }
        }
    }

    // MARK: IV bars

    @ViewBuilder private var bars: some View {
        if let i = row.ivs {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { bar("Attack", i.atk); bar("Defence", i.def); bar("HP", i.hp) }
                VStack(spacing: 8) { bar("Attack", i.atk); bar("Defence", i.def); bar("HP", i.hp) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("iv-bars")
        } else {
            Text("IVs not read").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        }
    }

    private func bar(_ label: String, _ v: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(label + " ").font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted)
                + Text("\(v)").font(.figtree(15, .heavy, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink))
            GeometryReader { g in
                Capsule().fill(Theme.off)
                    .overlay(alignment: .leading) { Capsule().fill(Theme.orange).frame(width: g.size.width * CGFloat(min(max(v, 0), 15)) / 15) }
                    .clipShape(Capsule())
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) IV")
        .accessibilityValue("\(v) of 15")
    }
}

// MARK: marks

/// A round mark on the details card (README "Marks"): 32 pt, 44 pt tap area. Off is the `off` circle with a `faint` glyph; Dynamax on takes the Max tint and
/// ink, Shadow on a purple, Advanced details open the accent's tint and ink; on has a 2 pt inset ring. A button for VoiceOver with its state as the value (On, Off; Expanded, Collapsed): the `.isToggle` trait would make UI tests see a switch whose value is 0 or 1.
struct MarkButton: View {
    enum Kind { case dynamax, shadow, advanced }
    let kind: Kind
    let on: Bool
    let name: String
    let identifier: String
    var isToggle = true
    let hint: String
    let action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            glyph
                .frame(width: 32, height: 32)
                .background(Circle().fill(on ? tint : Theme.off))
                .overlay { if on { Circle().strokeBorder(ink, lineWidth: 2) } }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(isToggle ? (on ? "On" : "Off") : (on ? "Expanded" : "Collapsed"))
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    private var ink: Color {
        switch kind {
        case .dynamax: return Theme.maxInk
        case .shadow: return Theme.pair(0x6A2DAF, 0xC9A3FF)
        case .advanced: return accent.ink
        }
    }
    private var tint: Color {
        switch kind {
        case .dynamax: return Theme.maxTint
        case .shadow: return Theme.pair(0xEFE6FA, rgba: (160, 110, 230, 0.2))
        case .advanced: return accent.tint
        }
    }
    /// `muted`, not `faint`: the off glyph keeps 3:1 against the off circle in dark mode.
    private var stroke: Color { on ? ink : Theme.muted }

    @ViewBuilder private var glyph: some View {
        switch kind {
        case .dynamax:
            SVGGlyph(data: "M7 15a4 4 0 0 1-.6-7.95A5.5 5.5 0 0 1 17 6.5a4.25 4.25 0 0 1 .5 8.5zM12 22v-8M8.5 17.5L12 14l3.5 3.5")
                .stroke(stroke, style: StrokeStyle(lineWidth: 2.2 * 17 / 24, lineCap: .round, lineJoin: .round)).frame(width: 17, height: 17)
        case .shadow:
            SVGGlyph(data: Glyph.types["fire"] ?? "").fill(stroke).frame(width: 16, height: 16)
        case .advanced:
            SVGGlyph(data: "M4 7h10M18 7h2M4 17h4M12 17h8M13.8 7a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0-4.4 0M7.8 17a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0-4.4 0")
                .stroke(stroke, style: StrokeStyle(lineWidth: 2.4 * 16 / 24, lineCap: .round)).frame(width: 16, height: 16)
        }
    }
}

// MARK: advanced details

/// The advanced details (CONCEPTS rule 17, D26): moves, Max moves (only while Dynamax is on), the Mega level (only for a species with a Mega form) and the
/// flag chips. A move or level the player has not chosen shows its default and is not saved until a tap (rule 18).
struct AdvancedDetailsView: View {
    let entry: BoxEntry
    /// Takes the edit as a function of the row as it is when the edit is applied, so two quick edits (each replacing the whole details) both persist.
    let apply: (@escaping (ScanRow) -> BoxMerge.Edit) -> Void
    @Environment(\.accent) private var accent

    private var row: ScanRow { entry.row }
    private var gm: GameMaster? { try? GameMaster.bundled() }

    var body: some View {
        if let gm {
            let id = row.speciesId
            let moves = PokemonPage.moves(row.details, speciesId: id, gm: gm)
            VStack(alignment: .leading, spacing: 14) {
                section("FAST MOVE", id: "adv-fast") {
                    ForEach(AdvancedDetails.fastMoves(of: id, gm: gm), id: \.id) { m in
                        moveChip(m, selected: moves.fast == m.id, identifier: "move-fast-\(m.id)") {
                            apply { r in BoxMerge.Edit(details: PokemonPage.choosing(m.id, for: .fast, details: r.details, speciesId: r.speciesId, gm: gm)) }
                        }
                    }
                }
                section("CHARGED MOVE", id: "adv-charged") {
                    ForEach(AdvancedDetails.firstChargedOptions(of: id, second: moves.charged2, gm: gm), id: \.id) { m in
                        moveChip(m, selected: moves.charged1 == m.id, identifier: "move-charged-\(m.id)") {
                            apply { r in BoxMerge.Edit(details: PokemonPage.choosing(m.id, for: .charged, details: r.details, speciesId: r.speciesId, gm: gm)) }
                        }
                    }
                }
                section("SECOND CHARGED MOVE", id: "adv-charged2") {
                    chip("Not unlocked", selected: moves.charged2 == nil, identifier: "move-charged2-none") {
                        apply { r in BoxMerge.Edit(details: PokemonPage.choosing(nil, for: .charged2, details: r.details, speciesId: r.speciesId, gm: gm)) }
                    }
                    ForEach(AdvancedDetails.secondChargedOptions(of: id, first: moves.charged1, gm: gm), id: \.id) { m in
                        moveChip(m, selected: moves.charged2 == m.id, identifier: "move-charged2-\(m.id)") {
                            apply { r in BoxMerge.Edit(details: PokemonPage.choosing(m.id, for: .charged2, details: r.details, speciesId: r.speciesId, gm: gm)) }
                        }
                    }
                }
                if AdvancedDetails.showsMaxMoves(dynamax: row.dynamax) { maxMoves(moves, gm: gm) }
                if AdvancedDetails.showsMegaLevel(speciesId: id, gm: gm) { megaLevel(gm: gm) }
                section("MORE", id: "adv-more") {
                    ForEach(PokemonPage.flags(for: row), id: \.self) { f in
                        chip(f.rawValue, selected: PokemonPage.isOn(f, row), identifier: "flag-\(f.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))") {
                            apply { PokemonPage.toggle(f, $0) }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("advanced-details")
        }
    }

    // MARK: sections and chips

    private func section<C: View>(_ caption: String, id: String, ink: Color = Theme.faint, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsCaption(caption, ink: ink)
            FlowLayout(spacing: 6) { content() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }

    /// A chip (32 pt, `surface2`); chosen it is the accent tint with a 2 pt ring.
    private func chip(_ title: String, selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipFace(selected: selected) { Text(title).font(.figtree(13, .bold, relativeTo: .footnote)) } }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier(identifier)
    }

    private func moveChip(_ m: AdvancedDetails.MoveOption, selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipFace(selected: selected, leading: 7) {
                HStack(spacing: 5) {
                    TypeIcon(type: m.type, size: 18)
                    Text(m.name).font(.figtree(13, .bold, relativeTo: .footnote))
                    if m.elite {
                        Text("ELITE").font(.figtree(9, .heavy, relativeTo: .caption2)).tracking(0.4).foregroundStyle(Theme.orangeInk)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(Theme.orangeTint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.name), \(m.type.capitalized)" + (m.elite ? ", Elite" : ""))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }

    private func chipFace<C: View>(selected: Bool, leading: CGFloat = 11, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .foregroundStyle(selected ? accent.ink : Theme.ink)
            .padding(.leading, leading).padding(.trailing, 11)
            .frame(minHeight: 32)
            .background(selected ? accent.tint : Theme.surface2, in: Capsule())
            .overlay { if selected { Capsule().strokeBorder(accent.ink, lineWidth: 2) } }
            .padding(.vertical, 6).contentShape(Rectangle()).padding(.vertical, -6)
    }

    // MARK: Max moves and the Mega level

    private func maxMoves(_ moves: AdvancedDetails.Defaults, gm: GameMaster) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CapsCaption("MAX MOVES", ink: Theme.maxInk)
            levelRow(AdvancedDetails.maxAttackName(fastMove: moves.fast, speciesId: row.speciesId, gm: gm), "Max Attack · its type follows the fast move", move: .attack, id: "max-attack")
            levelRow("Max Guard", "Shields the team", move: .guardMove, id: "max-guard")
            levelRow("Max Spirit", "Heals the team", move: .spirit, id: "max-spirit")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adv-max")
    }

    private func levelRow(_ name: String, _ sub: String, move: PokemonPage.MaxMove, id: String) -> some View {
        let now = PokemonPage.level(of: move, row.details)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { levelName(name, sub).frame(maxWidth: .infinity, alignment: .leading); levels(PokemonPage.levels(of: move), now: now, name: name, id: id) { n in
                apply { r in BoxMerge.Edit(details: PokemonPage.setting(n, of: move, r.details)) }
            } }
            VStack(alignment: .leading, spacing: 4) { levelName(name, sub); levels(PokemonPage.levels(of: move), now: now, name: name, id: id) { n in
                apply { r in BoxMerge.Edit(details: PokemonPage.setting(n, of: move, r.details)) }
            } }
        }
        .frame(minHeight: 40)
    }

    private func levelName(_ name: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
            Text(sub).font(.figtree(12, .medium, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
    }

    /// A row of level buttons on an `off` capsule track, the chosen one on `surface`; each at least 44 pt tall to hit.
    private func levels(_ values: [Int], now: Int, name: String, id: String, pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { n in
                levelButton(n == 0 ? "–" : String(n), selected: n == now, minWidth: 34, label: "\(name) " + (n == 0 ? "not unlocked" : "level \(n)"), identifier: "\(id)-\(n)") { pick(n) }
            }
        }
        .padding(3).background(Theme.off, in: Capsule())
    }

    private func levelButton(_ text: String, selected: Bool, minWidth: CGFloat, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(selected ? Theme.ink : Theme.muted)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 8).frame(minWidth: minWidth, minHeight: 28)
                .background(selected ? Theme.surface : Color.clear, in: Capsule())
                .padding(.vertical, 8).contentShape(Rectangle()).padding(.vertical, -8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(identifier)
    }

    private func megaLevel(gm: GameMaster) -> some View {
        let now = PokemonPage.megaLevel(row.details)
        let names = AdvancedDetails.megaForms(of: row.speciesId, gm: gm).joined(separator: " / ")
        return VStack(alignment: .leading, spacing: 8) {
            CapsCaption("MEGA LEVEL · \(names)", ink: Theme.copiesInk)
            HStack(spacing: 0) {
                ForEach(CopyDetails.MegaLevel.allCases, id: \.self) { l in
                    levelButton(l.title, selected: l == now, minWidth: 56, label: "Mega level \(l.title)", identifier: "mega-level-\(l.rawValue)") {
                        apply { r in BoxMerge.Edit(details: PokemonPage.setting(megaLevel: l, r.details)) }
                    }
                }
            }
            .padding(3).background(Theme.off, in: Capsule())
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adv-mega")
    }
}
