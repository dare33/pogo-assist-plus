import SwiftUI
import PogoBox

/// Team Rocket (design handoff section 5, screenshot 12): the four leaders, the player's team for the chosen one slot by slot, and a counter for
/// every grunt. Everything is a read-only suggestion worked out by `HubTeams`; the design's slot picker is not built (a manager call for this PR).
struct HubRocketView: View {
    @EnvironmentObject var model: AppModel
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
            if let hub, let gm {
                let leader = hub.leaders.first { $0.name == leaderName } ?? hub.leaders.first
                leaders(hub, selected: leader)
                if let leader {
                    HubAdviceGate { advice in team(leader, advice: advice, hub: hub, gm: gm) }
                }
                HubAdviceGate { advice in grunts(advice, hub: hub, gm: gm) }
                Text("Rocket lineups are not announced ahead. They change with each Takeover (every six to eight weeks) and are known a day or two after. Grunt types never change.")
                    .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            } else {
                Text("The Rocket lineups could not be read.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityIdentifier("hub-screen-rocket")
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

    // MARK: the team

    @ViewBuilder private func team(_ leader: HubData.Leader, advice: BoxAdvice, hub: HubData, gm: GameMaster) -> some View {
        let counters = HubTeams.leaderTeam(leader: leader, builds: advice.builds, gaps: advice.gaps, gm: gm, hub: hub)
        HubHeaderLine("YOUR TEAM FOR \(leader.name.uppercased())") {
            Menu {
                ForEach(hub.leaders, id: \.name) { l in
                    Button { leaderName = l.name } label: {
                        if l.name == leader.name { Label(l.name, systemImage: "checkmark") } else { Text(l.name) }
                    }
                }
            } label: {
                Text("Change leader").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink).frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityIdentifier("hub-change-leader")
        }
        HubSlotsPanel(title: "Slot by slot", type: .rocket) {
            ForEach(Array(counters.enumerated()), id: \.offset) { i, c in
                let slot = leader.slots[i]
                let options = slot.map { HubTeams.plain($0.name) }.joined(separator: " / ")
                let beats = c.build.map { HubTeams.beatsText(by: $0, options: slot, gm: gm, hub: hub) }
                let state = c.isBuilt ? "built" : (c.gapText ?? "no counter")
                HubSlotTile(type: .rocket, disc: String(i + 1), name: c.name,
                            sub: beats ?? c.gapText ?? "no counter",
                            extra: (beats != nil ? c.gapText.map { [$0] } ?? [] : []) + ["vs \(options)"],
                            filled: c.isBuilt,
                            label: "Slot \(i + 1), \(c.name == "—" ? "" : c.name + ", ")\(state)\(beats.map { ", " + $0 } ?? ""), against \(options)")
                    .accessibilityIdentifier("hub-rocket-slot-\(i + 1)")
            }
        }
    }

    // MARK: grunts

    @ViewBuilder private func grunts(_ advice: BoxAdvice, hub: HubData, gm: GameMaster) -> some View {
        HubHeaderLine("GRUNTS · WHAT THEY SAY, WHO YOU BRING")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
            ForEach(Array(hub.grunts.enumerated()), id: \.offset) { _, g in
                gruntTile(g, HubTeams.gruntCounter(type: g.type, builds: advice.builds, gaps: advice.gaps, gm: gm, hub: hub))
            }
        }
        .accessibilityIdentifier("hub-grunts")
    }

    private func gruntTile(_ g: HubData.Grunt, _ c: HubTeams.Counter) -> some View {
        let word = g.type.isEmpty ? g.label : g.type.prefix(1).uppercased() + g.type.dropFirst()
        let sub: String
        switch c {
        case .built: sub = "\(word) · built"
        case .toBuild(let b): sub = "\(word) · \(HubTeams.todo(b))"
        case .gap, .none: sub = "\(word) · \(c.gapText ?? "no counter")"
        case .anyAttacker: sub = "\(word) · any strong attacker"
        }
        let value = c == .anyAttacker ? "—" : c.name
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let bar = c.isBuilt ? ContentType.rocket.ink(accent) : Theme.line
        return VStack(alignment: .leading, spacing: 2) {
            Text("“\(word)”".uppercased()).font(.figtree(11, .heavy, relativeTo: .caption2)).foregroundStyle(Theme.muted).lineLimit(1)
            Text(value).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineLimit(2)
            Text(sub).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted).lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(.leading, 12 + 3).padding(.trailing, 10).padding(.vertical, 10)
        .background(Theme.surface, in: shape)
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16).fill(bar).frame(width: 3) }
        .clipShape(shape)
        .panelShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c == .anyAttacker ? "\(g.quote) \(word). Any strong attacker" : "\(g.quote) \(word). \(value == "—" ? "No counter" : value), \(sub)")
    }
}
