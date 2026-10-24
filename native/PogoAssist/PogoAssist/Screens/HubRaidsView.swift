import SwiftUI
import PogoBox

/// The Raids screen (design handoff section 5, screenshots 10 and 22): a `Now | Coming up` timeline of the raid bosses with how ready
/// the box is for each, then the builds that would close the gaps and a link to the full schedule.
struct HubRaidsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .raids)) }
        return HubTypeScreen(type: .raids, sub: "Bosses to 1 Dec", count: count) {
            HubAdviceGate { advice in
                HubTimeline(screen: .raids, advice: advice, entries: model.entries, closers: true)
            }
            HubScheduleLink()
        }
        .accessibilityIdentifier("hub-screen-raids")
    }
}

/// `Full schedule on pokemongo.com ›`, which opens the news page in the browser.
struct HubScheduleLink: View {
    @Environment(\.accent) private var accent

    var body: some View {
        Link(destination: URL(string: "https://pokemongo.com/news")!) {
            Text("Full schedule on pokemongo.com ›").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .accessibilityIdentifier("hub-schedule-link")
    }
}

/// The timeline both the Raids and the Max screen show: the `Now | Coming up` switch, the list and, for Raids, the builds that close the
/// gaps of the rows on show.
struct HubTimeline: View {
    let screen: HubRaidsModel.Screen
    let advice: BoxAdvice
    let entries: [BoxEntry]
    let closers: Bool
    @Environment(\.accent) private var accent
    @State private var choice: Segment?
    @State private var showAllClosers = false

    enum Segment: Hashable { case now, comingUp }

    private var type: ContentType { screen == .raids ? .raids : .max }
    private var prefix: String { screen == .raids ? "raids" : "max" }

    var body: some View {
        if let hub = try? HubData.bundled(), let gm = try? GameMaster.bundled() {
            let line = HubRaidsModel.timeline(rows: hub.rotation, screen: screen, today: HubModel.dayKey(Date()))
            let segment = choice ?? (line.now.isEmpty ? .comingUp : .now)
            let shown = segment == .now ? line.now : line.comingUp
            SegmentedSwitch(
                segments: [.init(value: Segment.now, title: "Now"), .init(value: Segment.comingUp, title: "Coming up")],
                selection: Binding(get: { segment }, set: { choice = $0 }), label: "Timeline", identifier: "hub-\(prefix)-segment")
            if shown.isEmpty {
                Text("Nothing listed.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("hub-\(prefix)-empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, e in
                        HubTimelineRow(entry: e, type: type, hub: hub, gm: gm, advice: advice, entries: entries, screen: screen)
                            .accessibilityIdentifier("hub-\(screen == .raids ? "raid" : "max")-row-\(i)")
                        if i < shown.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .panelShadow()
            }
            if closers { gapClosers(rows: shown.map(\.row), hub: hub, gm: gm) }
        } else {
            Text("The Hub's schedule could not be read.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private func gapClosers(rows: [HubData.RotationRow], hub: HubData, gm: GameMaster) -> some View {
        let all = HubRaidsModel.gapClosers(rows: rows, builds: advice.builds, entries: entries, gm: gm, hub: hub, screen: screen)
        HubHeaderLine("BUILDS THAT CLOSE THE GAPS") {
            if all.count > 3 {
                Button { withAnimation(.easeOut(duration: 0.15)) { showAllClosers.toggle() } } label: {
                    Text(showAllClosers ? "Top 3" : "All \(all.count)").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("hub-raids-all")
                .accessibilityAddTraits(showAllClosers ? .isSelected : [])
            }
        }
        if all.isEmpty {
            Text("No build of yours would close a gap for these bosses.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        } else {
            HubBuildList(builds: showAllClosers ? all : Array(all.prefix(3)), type: type, highlightFirst: true)
        }
    }
}

/// One timeline row: the dates, the name with its kind chip, the readiness bar, the types to bring and what to do next.
private struct HubTimelineRow: View {
    let entry: HubRaidsModel.Entry
    let type: ContentType
    let hub: HubData
    let gm: GameMaster
    let advice: BoxAdvice
    let entries: [BoxEntry]
    let screen: HubRaidsModel.Screen
    @Environment(\.accent) private var accent

    var body: some View {
        let row = entry.row
        let dates = HubRaidsModel.dateColumn(entry)
        let name = HubRaidsModel.name(row)
        let chip = HubRaidsModel.kindChip(row.kind)
        let bring = HubRaidsModel.bring(row: row, hub: hub)
        let ready = HubRaidsModel.readiness(row: row, builds: advice.builds, entries: entries, gm: gm, hub: hub, screen: screen)
        let todo = HubRaidsModel.toDo(row: row, builds: advice.builds, entries: entries, gm: gm, hub: hub, screen: screen)
        let counters = ready.built == ready.needed ? "\(ready.needed) of \(ready.needed) ready" : "\(ready.built) of \(ready.needed) counters"
        let ink = type.ink(accent)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dates.dates).font(.figtree(11, .heavy, relativeTo: .caption2)).foregroundStyle(entry.isNow ? ink : Theme.muted)
                Text(dates.when).font(.figtree(11, .semibold, relativeTo: .caption2)).foregroundStyle(Theme.muted)
            }
            .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    if !chip.isEmpty {
                        Text(chip).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.04 * 10).foregroundStyle(Theme.muted)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.off, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .fixedSize()
                    }
                }
                if ready.needed > 0 {
                    HStack(spacing: 8) {
                        ReadinessBar(fraction: Double(ready.built) / Double(ready.needed),
                                     colour: ready.built == ready.needed ? Theme.greenInk : ready.built == 0 ? Theme.red : ink)
                            .frame(height: 6)
                        Text(counters).font(.figtree(11, .bold, relativeTo: .caption2)).monospacedDigit().foregroundStyle(Theme.muted).fixedSize()
                    }
                    WrapLayout(spacing: 6) {
                        Text("BRING").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.faint)
                        ForEach(bring, id: \.self) { t in
                            Text(t.uppercased()).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.04 * 10)
                                .foregroundStyle(Theme.pokemonTypeText(t)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Theme.pokemonType(t) ?? Theme.off, in: Capsule())
                        }
                    }
                }
                if !todo.isEmpty {
                    Text(todo).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.isNow ? type.tint(accent) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(dates: dates, name: name, chip: chip, counters: ready.needed > 0 ? counters : nil, bring: bring, todo: todo))
    }

    private func spoken(dates: (dates: String, when: String), name: String, chip: String, counters: String?, bring: [String], todo: String) -> String {
        var parts = ["\(dates.dates), \(dates.when)", name]
        if !chip.isEmpty { parts.append(chip.replacingOccurrences(of: "5★", with: "5 star").lowercased()) }
        if let counters {
            let types = bring.map(HubRaidsModel.typeName)
            let list = types.count > 1 ? types.dropLast().joined(separator: ", ") + " and " + types[types.count - 1] : types.joined()
            parts.append("\(counters), bring \(list)")
        }
        if !todo.isEmpty { parts.append(todo) }
        return parts.joined(separator: ". ")
    }
}

/// A 6 pt rounded bar: `fraction` of the track in `colour`, the rest on the `off` colour.
private struct ReadinessBar: View {
    let fraction: Double
    let colour: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.off)
                if fraction > 0 { Capsule().fill(colour).frame(width: max(6, g.size.width * min(1, fraction))) }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Lays its children out left to right and starts a new line when one does not fit, so the type chips stay readable at large text sizes.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in laid.origins.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified) }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], size: CGSize) {
        var origins = [CGPoint](), x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing; lineHeight = max(lineHeight, size.height); widest = max(widest, x - spacing)
        }
        return (origins, CGSize(width: widest, height: y + lineHeight))
    }
}
