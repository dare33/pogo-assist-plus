import SwiftUI
import PogoBox

/// Team Rocket (design pass 2): the leader cards, SUGGESTIONS · Available | Best, YOUR SQUAD FOR <LEADER> as three slot cards that each open a picker, and a row for
/// every grunt with the box's counters in a sideways strip. The three picks for each leader are kept per account (`SquadKeeper`).
struct HubRocketView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var keeper = SquadKeeper()
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var leaderName = ""

    private let hub = try? HubData.bundled()
    private let gm = try? GameMaster.bundled()

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .rocket)) }
        let since = hub?.leaders.first.flatMap { Self.monthYear($0.since, short: true) }
        return HubTypeScreen(type: .rocket, sub: since.map { "Lineups: Leek Duck, \($0)" }, count: count) {
            if let hub, gm != nil {
                let leader = hub.leaders.first { $0.name == leaderName } ?? hub.leaders.first
                leaders(hub, selected: leader)
                if let ctx = model.squadContext() {
                    SuggestionsRow(mode: Binding(get: { keeper.store.mode(for: .rocket) }, set: { m in keeper.update { $0.setMode(m, for: .rocket) } }), noun: "counters")
                    if let leader {
                        RocketSquadView(leader: leader, leaders: hub.leaders, ctx: ctx, keeper: keeper, onLeader: { leaderName = $0 }).id(leader.name)
                    }
                    RocketGrunts(ctx: ctx, mode: keeper.store.mode(for: .rocket))
                } else {
                    HubAdviceGate { _ in EmptyView() }
                }
                Text("Rocket lineups are not announced ahead. They change with each Takeover (every six to eight weeks) and are known a day or two after. Grunt types never change.")
                    .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            } else {
                Text("The Rocket lineups could not be read.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
        }
        .keepsSquads(keeper)
    }

    // MARK: leaders

    @ViewBuilder private func leaders(_ hub: HubData, selected: HubData.Leader?) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) { ForEach(hub.leaders, id: \.name) { leaderButton($0, selected: $0.name == selected?.name) } }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { ForEach(hub.leaders, id: \.name) { leaderButton($0, selected: $0.name == selected?.name) } }
                    .fixedSize(horizontal: false, vertical: true)
            }
            .scrollClipDisabled()
        }
    }

    private func leaderButton(_ l: HubData.Leader, selected on: Bool) -> some View {
        Button { leaderName = l.name } label: { leaderCard(l, selected: on) }
            .buttonStyle(PressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(l.name), leader since \(Self.monthYear(l.since) ?? l.since). \(Self.line(l))")
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("hub-leader-\(l.name)")
    }

    private func leaderCard(_ l: HubData.Leader, selected: Bool) -> some View {
        let ink = ContentType.rocket.ink(accent)
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            Text("LEADER · SINCE \(Self.monthYear(l.since, short: true)?.uppercased() ?? l.since)").font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.08 * 11).opacity(0.8)
            Text(l.name).font(.figtree(17, .heavy, relativeTo: .headline))
            Text(Self.line(l)).font(.figtree(13, .semibold, relativeTo: .footnote)).lineLimit(4)
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Theme.surface : Theme.ink)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(width: typeSize.isAccessibilitySize ? nil : 220, alignment: .topLeading)
        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .topLeading)
        .frame(minHeight: 112, maxHeight: typeSize.isAccessibilitySize ? nil : .infinity, alignment: .topLeading)
        .background(selected ? AnyShapeStyle(ink) : AnyShapeStyle(Theme.surface), in: shape)
        .panelShadow()
        .contentShape(shape)
    }

    /// "Persian → Kangaskhan / Rhyperior / Machamp → Zekrom": the options of each slot, joined by " / ", the slots by " → ". A Shadow's name keeps
    /// its "Shadow" out of the line (every Rocket Pokémon is one).
    static func line(_ l: HubData.Leader) -> String {
        l.slots.map { $0.map { $0.name.hasPrefix("Shadow ") ? String($0.name.dropFirst(7)) : $0.name }.joined(separator: " / ") }.joined(separator: " → ")
    }

    /// "2026-10" or "2026-10-04" as "October 2026" ("Oct 2026" when `short`); nil when it is neither.
    static func monthYear(_ since: String, short: Bool = false) -> String? {
        let p = since.split(separator: "-")
        let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        guard p.count >= 2, let m = Int(p[1]), (1...12).contains(m) else { return nil }
        return "\(short ? String(months[m - 1].prefix(3)) : months[m - 1]) \(p[0])"
    }
}

// MARK: the squad

/// YOUR SQUAD FOR <LEADER> with Change leader, and "Slot by slot": three slot cards, each against one slot of the leader's lineup.
private struct RocketSquadView: View {
    let leader: HubData.Leader
    let leaders: [HubData.Leader]
    let ctx: HubContext
    @ObservedObject var keeper: SquadKeeper
    let onLeader: (String) -> Void
    @State private var selected: Int?
    @Environment(\.accent) private var accent

    /// What a slot's card or picker row says about a Pokémon for that slot: one of the player's builds or, under Best, a Pokémon the box lacks.
    private struct Entry {
        var id: String
        var name: String
        var tier: String
        var build: BoxAdvice.Build?
        var best: HubSquads.BestRow?
        var hits: Int
        var flags: [PickerType]
        var line: String?
        var notWeak = false
    }

    private typealias SlotLists = (rows: [Entry], next: [Entry])

    var body: some View {
        let mode = keeper.store.mode(for: .rocket)
        let saved = keeper.store.rocketSquad(leader: leader.name)
        let filled = mode == .best ? HubSquads.bestRocketSquad(leader: leader, slots: saved.slots, ctx: ctx) : HubSquads.rocketSquad(leader: leader, slots: saved.slots, mode: mode, ctx: ctx)
        let lists = leader.slots.map { entries(for: $0, mode: mode) }
        let cards = filled.enumerated().map { card($0.offset, $0.element, lists: lists) }
        HubHeaderLine("YOUR SQUAD FOR \(leader.name.uppercased())") {
            Menu {
                ForEach(leaders, id: \.name) { l in
                    Button { onLeader(l.name) } label: {
                        if l.name == leader.name { Label(l.name, systemImage: "checkmark") } else { Text(l.name) }
                    }
                }
            } label: {
                Text("Change leader").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink).frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("hub-change-leader")
        }
        VStack(alignment: .leading, spacing: 10) {
            Text("Slot by slot").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            if let team = HubSquads.teamStatus(cards.map(\.status)) { SquadStatusLine(status: team) }
            SlotGrid(slots: cards, selected: selected) { i in
                withAnimation(.easeOut(duration: 0.15)) { selected = selected == i ? nil : i }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
        if let i = selected, filled.indices.contains(i) { picker(i, filled: filled, lists: lists, mode: mode) }
    }

    private func options(_ i: Int) -> String { leader.slots[i].map { HubTeams.plain($0.name) }.joined(separator: " / ") }

    /// The picker's rows for a slot (rule 16 under Available, the Rocket table under Best, rule 6) and, when there are none, the Next best rows (rule 18), each with what
    /// it says for the slot.
    private func entries(for slot: [HubData.Boss], mode: SquadMode) -> SlotLists {
        func flags(_ b: BoxAdvice.Build) -> [PickerType] {
            HubTeams.types(of: b, gm: ctx.gm).map { t in PickerType(type: t, grey: !slot.contains { ctx.hub.beats([t], $0.types) }) }
        }
        let rows: [Entry]
        if mode == .best {
            rows = HubSquads.bestRocketRows(options: slot, ctx: ctx).map {
                Entry(id: $0.entryId, name: $0.name, tier: $0.tier, build: $0.build, best: $0, hits: $0.hits, flags: $0.typeFlags.map { PickerType(type: $0.type, grey: !$0.hits) }, line: $0.slotLine)
            }
        } else {
            rows = HubSquads.rocketPicker(options: slot, mode: mode, ctx: ctx).map {
                Entry(id: $0.entryId, name: $0.build.targetName, tier: $0.build.tier, build: $0.build, best: nil, hits: $0.hits, flags: $0.typeFlags.map { PickerType(type: $0.type, grey: !$0.hits) }, line: $0.slotLine)
            }
        }
        let next = rows.isEmpty ? HubSquads.rocketNextBest(options: slot, mode: mode, ctx: ctx).map {
            Entry(id: $0.build.entryId, name: $0.build.targetName, tier: $0.build.tier, build: $0.build, best: nil, hits: 0, flags: flags($0.build), line: $0.notWeak ? "Not weak to this slot" : nil, notWeak: $0.notWeak)
        } : []
        return (rows, next)
    }

    private func find(_ f: FilledSlot, in lists: SlotLists) -> Entry? {
        let all = lists.rows + lists.next
        if let key = f.species, let e = all.first(where: { $0.best?.key == key }) { return e }
        return f.pickId.flatMap { id in all.first { $0.id == id } }
    }

    // MARK: cards

    private func card(_ i: Int, _ f: FilledSlot, lists: [SlotLists]) -> SlotCardModel {
        let palette = SquadPalette(ink: ContentType.rocket.ink(accent), tint: ContentType.rocket.tint(accent))
        let id = "hub-rocket-slot-\(i + 1)"
        let vs = "vs \(options(i))"
        let head = "Slot \(i + 1) of \(leader.slots.count)"
        guard let pick = f.pickId else {
            return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: nil, lines: ["No counter", vs], status: .empty,
                                 spoken: "\(head), \(HubSquads.SlotStatus.empty.spoken). No counter in your box, against \(options(i))", identifier: id)
        }
        let e = find(f, in: lists[i]) ?? f.entryId.flatMap { entryId in ctx.advice.builds.first { $0.entryId == entryId } }.map {
            // A pick the lists no longer offer (it stopped beating the slot): the slot still names it.
            let hits = HubTeams.beaten(by: $0, options: leader.slots[i], gm: ctx.gm, hub: ctx.hub).count
            return Entry(id: $0.entryId, name: $0.targetName, tier: $0.tier, build: $0, best: nil, hits: hits, flags: [], line: HubSquads.slotLine(hits: hits, of: leader.slots[i].count))
        }
        guard let e else {
            if let key = f.species {
                let name = ctx.gm.byId[key]?.name ?? ctx.gm.byId[key.replacingOccurrences(of: "_shadow", with: "")]?.name ?? "Pokémon"
                return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: name, lines: ["Not in your box", vs], types: ctx.gm.byId[key]?.types ?? [], status: .toGet,
                                     spoken: [head, name, HubSquads.SlotStatus.toGet.spoken, "against \(options(i))"].joined(separator: ", "), identifier: id)
            }
            let name = f.entryId.flatMap { ctx.entry($0)?.row.title } ?? "Pokémon"
            return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: name, lines: [vs], types: f.entryId.map(ctx.entryTypes) ?? [], status: .needsWork,
                                 spoken: "\(head), \(name), \(HubSquads.SlotStatus.needsWork.spoken), against \(options(i))", identifier: id)
        }
        guard let build = e.build, e.best?.hasBuild != false else {
            return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), best: e.best!, extra: (e.line.map { [$0] } ?? []) + [vs], spokenExtra: [e.line, "against \(options(i))"].compactMap { $0 }, head: head, identifier: id)
        }
        let mark = SquadMark.of(build, screen: .rocket, ctx: ctx)
        // Rule 29: the Rocket table's tier (a Pokémon the table does not list needs work), not the build's tier from another area.
        let status = HubSquads.slotStatus(inBox: true, fullStrength: mark == .fullStrength, tier: HubSquads.rocketTableTier(build, ctx: ctx))
        let shared = e.best?.sharedWith.map { "same copy as \($0)" }
        let lines = (e.line.map { [$0] } ?? []) + (shared.map { [$0] } ?? []) + [vs]
        let types = e.best?.types ?? HubTeams.types(of: build, gm: ctx.gm)
        let spoken = [head, e.name, SquadWords.typeList(types), e.line, shared, "against \(options(i))", mark.spoken, status.spoken].compactMap { $0 }.joined(separator: ", ")
        return SlotCardModel(id: i, role: nil, palette: palette, emptyOutline: Theme.line, disc: String(i + 1), name: e.name, lines: lines, types: types, mark: mark, status: status, spoken: spoken, identifier: id)
    }

    // MARK: picker

    private func picker(_ i: Int, filled: [FilledSlot], lists: [SlotLists], mode: SquadMode) -> some View {
        let l = lists[i]
        let showsNext = l.rows.isEmpty && !l.next.isEmpty
        let source = showsNext ? l.next : l.rows
        // Only a Pokémon the player chose in another slot leaves this list (D28): the app's own suggestions stay.
        let excluded = HubSquads.excluded(by: filled, editing: i, onlyChosen: true)
        var ids = source.map(\.id)
        let boxHasOptions = !ids.isEmpty
        if let own = filled[i].pickId, filled[i].ids.isDisjoint(with: ids) { ids.insert(own, at: 0) }
        let listed = HubSquads.picker(candidates: ids, excluded: excluded, ownIds: filled[i].ids)
        let byId = Dictionary(source.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [PickerRowModel] = listed.compactMap { r in
            guard let e = byId[r.entryId] else { return PickerRowModel.keptPick(id: r.entryId, ticked: r.ticked, screen: .rocket, ctx: ctx) }
            if e.build == nil || e.best?.hasBuild == false, let best = e.best {
                return PickerRowModel(best: best, ticked: r.ticked, types: e.flags, extraSpoken: {
                    let hitting = e.flags.filter { !$0.grey }.map(\.type)
                    return hitting.isEmpty ? nil : "\(SquadWords.typeList(hitting)) hits this slot"
                }())
            }
            let mark = SquadMark.of(e.build!, screen: .rocket, ctx: ctx)
            let types = e.flags
            let hitting = types.filter { !$0.grey }.map(\.type)
            let spoken = [e.name, e.line, hitting.isEmpty ? nil : "\(SquadWords.typeList(hitting)) hits this slot", mark.spoken, r.ticked ? "in this slot" : nil]
                .compactMap { $0 }.joined(separator: ", ")
            let note = [e.line, e.best?.sharedWith.map { "same copy as \($0)" }].compactMap { $0 }.joined(separator: " · ")
            return PickerRowModel(id: r.entryId, name: e.name, ticked: r.ticked, mark: mark, tier: e.tier, types: types, note: note.isEmpty ? nil : note, spoken: spoken)
        }
        if mode == .available { rows = PickerRowModel.availableUpgradesLast(rows) }
        return SquadPicker(
            title: "Slot \(i + 1) · vs \(options(i))", type: .rocket, heading: showsNext ? "Next best" : nil, rows: rows,
            emptyText: SquadWords.emptyPicker(mode: mode, boxHasOptions: boxHasOptions, none: mode == .available ? "Nothing in your box beats this slot." : "Nothing listed beats this slot."),
            onChoose: { id in
                keeper.update { s in
                    var saved = s.rocketSquad(leader: leader.name)
                    saved.choose(id, at: i, alsoClearing: HubSquads.equivalents(of: id, rows: source.compactMap(\.best)))
                    s.rocket[leader.name] = saved
                }
            },
            onDone: { withAnimation(.easeOut(duration: 0.15)) { selected = nil } },
            info: {
                if mode == .best {
                    SquadExplainer(items: [
                        ("Ranked from our Rocket table:", "every Pokémon it lists that beats at least one of the Pokémon the leader may bring in this slot (a type that hits them for more than normal damage), S then A then B, whether or not you have it. Ones you do not have say when they might be available."),
                        ("Type icons:", "in colour when that type hits one of the slot's Pokémon for more than normal damage, grey when it does not."),
                    ], identifier: "squad-picker-explainer")
                } else {
                    SquadExplainer(items: [
                        ("Best first:", "beats the most of the Pokémon the leader may bring in this slot (a type that hits them for more than normal damage), then built before to build, then Rocket counters before raid attackers, then tier and score."),
                        ("Type icons:", "in colour when that type hits one of the slot's Pokémon for more than normal damage, grey when it does not."),
                        ("Next best:", "when nothing in your box beats the slot: the Pokémon that take the least extra damage from it, up to three."),
                    ], identifier: "squad-picker-explainer")
                }
            })
    }
}

// MARK: grunts

/// GRUNTS · WHAT THEY SAY, WHO YOU BRING: one row per grunt in two lines. Line 1: the type icon, the type word, the quote and the types that beat it. Line 2: a sideways
/// strip of the box's counters (up to eight; the first, the app's own pick, on the Rocket tint), "Any strong attacker" for a typeless grunt or "Not in your box".
private struct RocketGrunts: View {
    let ctx: HubContext
    let mode: SquadMode
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HubHeaderLine("GRUNTS · WHAT THEY SAY, WHO YOU BRING")
        VStack(spacing: 0) {
            ForEach(Array(ctx.hub.grunts.enumerated()), id: \.offset) { i, g in
                row(g)
                if i < ctx.hub.grunts.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
        .accessibilityIdentifier("hub-grunts")
    }

    private func row(_ g: HubData.Grunt) -> some View {
        let word = g.type.isEmpty ? g.label : g.type.prefix(1).uppercased() + g.type.dropFirst()
        let counters = HubSquads.gruntCounters(type: g.type, mode: mode, ctx: ctx)
        let beaten = HubSquads.beatenBy(gruntType: g.type, hub: ctx.hub)
        let wide = typeSize.isAccessibilitySize
        let head = HStack(alignment: wide ? .top : .center, spacing: 8) {
            if !g.type.isEmpty { TypeIcon(type: g.type, size: 22) }
            Text(word).font(.figtree(13, .heavy, relativeTo: .footnote)).foregroundStyle(Theme.ink)
            Text("“\(g.quote)”").font(.figtree(12, .regular, relativeTo: .caption)).italic().foregroundStyle(Theme.muted)
                .lineLimit(wide ? nil : 1).frame(maxWidth: .infinity, alignment: .leading)
            if !beaten.isEmpty { TypeIcons(types: beaten, size: 13) }
        }
        let spokenCounters: String = counters.anyAttacker ? "Any strong attacker"
            : counters.builds.isEmpty ? "Not in your box"
            : "Counters: " + counters.builds.map { b in
                let m = SquadMark.of(b, screen: .rocket, ctx: ctx).spoken.map { ", " + $0.lowercased() } ?? ""
                return b.targetName + m
            }.joined(separator: "; ")
        return VStack(alignment: .leading, spacing: 8) {
            head
            if counters.anyAttacker {
                Text("Any strong attacker").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            } else if counters.builds.isEmpty {
                Text("Not in your box").font(.figtree(11, .heavy, relativeTo: .caption2)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.off, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if wide {
                FlowLayout(spacing: 6) { ForEach(Array(counters.builds.enumerated()), id: \.offset) { pill($0.element, first: $0.offset == 0) } }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(Array(counters.builds.enumerated()), id: \.offset) { pill($0.element, first: $0.offset == 0) } }
                }
                .scrollClipDisabled()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(counters.anyAttacker ? "\(g.quote) \(word). Any strong attacker"
                            : "\(g.quote) \(word). \(spokenCounters)\(beaten.isEmpty ? "" : ". Beaten by \(SquadWords.typeList(beaten))")")
        .accessibilityIdentifier("hub-grunt-row")
    }

    private func pill(_ b: BoxAdvice.Build, first: Bool) -> some View {
        HStack(spacing: 5) {
            Text(b.targetName).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.ink).lineLimit(1)
            SquadMarkView(mark: SquadMark.of(b, screen: .rocket, ctx: ctx))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(first ? ContentType.rocket.tint(accent) : Theme.off, in: Capsule())
    }
}
