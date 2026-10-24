import SwiftUI
import PogoBox

/// The Raids screen (design handoff section 5, screenshots 10 and 22): a `Now | Coming up` timeline of the raid bosses with how ready
/// the box is for each, then the builds that would close the gaps and a link to the full schedule.
struct HubRaidsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .raids)) }
        let sub = (try? HubData.bundled()).flatMap { HubRaidsModel.lastDay(rows: $0.rotation, screen: .raids) }.map { "Bosses to \($0)" }
        return HubTypeScreen(type: .raids, sub: sub, count: count) {
            HubTimeline(screen: .raids, advice: model.hubAdvice, entries: model.entries, closers: true)
            HubAdviceGate { _ in EmptyView() }
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
    /// nil while the advice is not ready: the schedule needs none, so the rows show without readiness.
    let advice: BoxAdvice?
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
            let line = HubRaidsModel.timeline(rows: hub.rotation, screen: screen, today: HubModel.today())
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
            if closers, let advice { gapClosers(rows: shown.map(\.row), advice: advice, hub: hub, gm: gm) }
        } else {
            Text("The Hub's schedule could not be read.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private func gapClosers(rows: [HubData.RotationRow], advice: BoxAdvice, hub: HubData, gm: GameMaster) -> some View {
        let all = HubRaidsModel.gapClosers(rows: rows, advice: advice, entries: entries, gm: gm, hub: hub, screen: screen)
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
    let advice: BoxAdvice?
    let entries: [BoxEntry]
    let screen: HubRaidsModel.Screen
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let row = entry.row
        let dates = HubRaidsModel.dateColumn(entry)
        let name = HubRaidsModel.name(row)
        let chip = HubRaidsModel.kindChip(row.kind)
        let bring = HubRaidsModel.bring(row: row, hub: hub)
        let ready = advice.map { HubRaidsModel.readiness(row: row, advice: $0, entries: entries, gm: gm, hub: hub, screen: screen) }
        let todo = advice.map { HubRaidsModel.toDo(row: row, advice: $0, entries: entries, gm: gm, hub: hub, screen: screen) } ?? (row.bosses.isEmpty ? row.note : "")
        let ink = type.ink(accent)
        let counters = ready.map { $0.built == $0.needed ? "\($0.needed) of \($0.needed) ready" : "\($0.built) of \($0.needed) counters" }
        let barColour = ready.map { $0.built == $0.needed ? Theme.greenInk : $0.built == 0 ? Theme.red : ink } ?? ink
        let stacked = typeSize.isAccessibilitySize
        let dateColumn = VStack(alignment: .leading, spacing: 2) {
            Text(dates.dates).font(.figtree(11, .heavy, relativeTo: .caption2)).foregroundStyle(entry.isNow ? ink : Theme.muted)
            Text(dates.when).font(.figtree(11, .semibold, relativeTo: .caption2)).foregroundStyle(Theme.muted)
        }
        let details = VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                Text(name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if !chip.isEmpty {
                    Text(chip).font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.04 * 10).foregroundStyle(Theme.muted)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(Theme.off, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            if let ready, let counters, ready.needed > 0 {
                let label = Text(counters).font(.figtree(11, .bold, relativeTo: .caption2)).monospacedDigit().foregroundStyle(barColour)
                if stacked {
                    VStack(alignment: .leading, spacing: 4) {
                        ReadinessBar(fraction: Double(ready.built) / Double(ready.needed), colour: barColour).frame(height: 6)
                        label
                    }
                } else {
                    HStack(spacing: 8) {
                        ReadinessBar(fraction: Double(ready.built) / Double(ready.needed), colour: barColour).frame(height: 6)
                        label.fixedSize()
                    }
                }
            }
            if !bring.isEmpty {
                FlowLayout(spacing: 6) {
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
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 6) { dateColumn; details }
            } else {
                HStack(alignment: .top, spacing: 12) { dateColumn.frame(width: 54, alignment: .leading); details }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(entry.isNow ? type.tint(accent) : Color.clear)
        // One element for the whole row. The label gives the bring types in words, so nothing depends on the chips inside.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(when: HubRaidsModel.spokenDates(entry), name: name, chip: chip, counters: ready.flatMap { $0.needed > 0 ? counters : nil }, bring: bring, todo: todo))
    }

    private func spoken(when: String, name: String, chip: String, counters: String?, bring: [String], todo: String) -> String {
        var parts = [when, name]
        if !chip.isEmpty { parts.append(chip.replacingOccurrences(of: "5★", with: "5 star").lowercased()) }
        let types = bring.map(HubRaidsModel.typeName)
        let list = types.count > 1 ? types.dropLast().joined(separator: ", ") + " and " + types[types.count - 1] : types.joined()
        if let counters { parts.append("\(counters), bring \(list)") } else if !types.isEmpty { parts.append("Bring \(list)") }
        if !todo.isEmpty { parts.append(todo) }
        return parts.joined(separator: ". ")
    }
}

/// A 6 pt rounded bar: `fraction` of the track in `colour` (a 6 pt stub at zero, so the red shows), the rest on the `off` colour.
private struct ReadinessBar: View {
    let fraction: Double
    let colour: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.off)
                Capsule().fill(colour).frame(width: max(6, g.size.width * min(1, fraction)))
            }
        }
        .accessibilityHidden(true)
    }
}

extension AppModel {
    /// The advice once it is ready; nil while it is being worked out or when there is none.
    var hubAdvice: BoxAdvice? { if case .ready(let a) = advice { return a } else { return nil } }
}
