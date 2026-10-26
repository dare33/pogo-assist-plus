import SwiftUI
import PogoBox

/// The Raids screen (design pass 2): a `Now | Coming up` switch, SUGGESTIONS · Available | Best, the raids on now as a sideways strip of cards (the first chosen on
/// opening; tapping the chosen card closes its squad) or the coming ones as a list, the chosen raid's squad with its picker, then the builds that would close the
/// gaps and a link to the full schedule.
struct HubRaidsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .raids)) }
        let sub = (try? HubData.bundled()).flatMap { HubRaidsModel.lastDay(rows: $0.rotation, screen: .raids) }.map { "Bosses to \($0)" }
        return HubTypeScreen(type: .raids, sub: sub, count: count) {
            HubTimeline(screen: .raids, closers: true)
            HubAdviceGate { _ in EmptyView() }
            HubScheduleLink()
        }
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

/// The timeline both the Raids and the Max screen show: the `Now | Coming up` switch, SUGGESTIONS, the cards or the list with the squads, and, for Raids, the builds
/// that close the gaps of the rows on show.
struct HubTimeline: View {
    let screen: HubRaidsModel.Screen
    let closers: Bool
    /// False shows the rows as a plain schedule, with no squad to plan (the Max screen until its squads are switched on).
    var squads = true
    @EnvironmentObject private var model: AppModel
    @StateObject private var keeper = SquadKeeper()
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var choice: Segment?
    @State private var showAllClosers = false
    /// Raids › Now: the card whose squad is shown, and whether the player closed it. Coming up and Max: the row that is open.
    @State private var chosenKey: String?
    @State private var cardsClosed = false
    @State private var openKey: String?

    enum Segment: Hashable { case now, comingUp }

    private var type: ContentType { screen == .raids ? .raids : .max }
    private var squadScreen: SquadScreen { screen == .raids ? .raids : .max }
    private var prefix: String { screen == .raids ? "raids" : "max" }

    private var mode: Binding<SquadMode> {
        Binding(get: { keeper.store.mode(for: squadScreen) }, set: { m in keeper.update { $0.setMode(m, for: squadScreen) } })
    }

    var body: some View {
        Group {
            if let hub = try? HubData.bundled(), let gm = try? GameMaster.bundled() { content(hub: hub, gm: gm) } else {
                Text("The Hub's schedule could not be read.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
        }
        .keepsSquads(keeper)
    }

    @ViewBuilder private func content(hub: HubData, gm: GameMaster) -> some View {
        let advice = model.hubAdvice
        let ctx = model.squadContext()
        let line = HubRaidsModel.timeline(rows: hub.rotation, screen: screen, today: HubModel.today())
        let segment = choice ?? (line.now.isEmpty ? .comingUp : .now)
        let shown = segment == .now ? line.now : line.comingUp
        let summaries = shown.map { EventSummary(entry: $0, screen: screen, hub: hub, gm: gm, advice: advice, entries: model.entries) }
        SegmentedSwitch(
            segments: [.init(value: Segment.now, title: "Now"), .init(value: Segment.comingUp, title: "Coming up")],
            selection: Binding(get: { segment }, set: { choice = $0; chosenKey = nil; cardsClosed = false; openKey = nil }), label: "Timeline", identifier: "hub-\(prefix)-segment")
        if squads, ctx != nil { SuggestionsRow(mode: mode, noun: "squads") }
        if shown.isEmpty {
            Text("Nothing listed.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("hub-\(prefix)-empty")
        } else if screen == .raids && segment == .now {
            cards(summaries, ctx: ctx)
        } else {
            list(summaries, ctx: ctx, hub: hub)
        }
        if closers, let advice { gapClosers(rows: shown.map(\.row), advice: advice, hub: hub, gm: gm) }
    }

    private func isSet(_ s: EventSummary) -> Bool { squads && keeper.store.eventSquad(s.entry.row, screen: squadScreen).isSet }

    // MARK: Raids › Now

    @ViewBuilder private func cards(_ summaries: [EventSummary], ctx: HubContext?) -> some View {
        let chosen = cardsClosed ? nil : (summaries.first { $0.key == chosenKey } ?? summaries.first)
        let build = { (i: Int, s: EventSummary) in
            RaidCardView(summary: s, chosen: chosen?.key == s.key, isSet: isSet(s), identifier: "hub-raid-row-\(i)") {
                withAnimation(.easeOut(duration: 0.15)) {
                    if chosen?.key == s.key { cardsClosed = true } else { chosenKey = s.key; cardsClosed = false }
                }
            }
        }
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) { ForEach(Array(summaries.enumerated()), id: \.offset) { build($0.offset, $0.element) } }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) { ForEach(Array(summaries.enumerated()), id: \.offset) { build($0.offset, $0.element) } }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
        if let chosen, squads, let ctx, chosen.hasSquad {
            EventSquadView(screen: .raids, row: chosen.entry.row, title: "Your squad – \(chosen.name)", advice: chosen.todo, ctx: ctx, keeper: keeper)
                .id(chosen.key)
        } else if let chosen, !chosen.todo.isEmpty, !chosen.hasSquad {
            Text(chosen.todo).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
    }

    // MARK: the list

    @ViewBuilder private func list(_ summaries: [EventSummary], ctx: HubContext?, hub: HubData) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(summaries.enumerated()), id: \.offset) { i, s in
                EventRowView(summary: s, type: type, isOpen: squads && openKey == s.key, isSet: isSet(s),
                             identifier: "hub-\(screen == .raids ? "raid" : "max")-row-\(i)", toggle: {
                    guard squads else { return }
                    withAnimation(.easeOut(duration: 0.15)) { openKey = openKey == s.key ? nil : s.key }
                }) {
                    VStack(alignment: .leading, spacing: 10) {
                        BringLine(types: s.bring).padding(.leading, typeSize.isAccessibilitySize ? 0 : 66)
                        if s.hasSquad, let ctx {
                            EventSquadView(screen: squadScreen, row: s.entry.row, title: "Your squad – \(s.name)", advice: s.todo, ctx: ctx, keeper: keeper)
                        } else if !s.todo.isEmpty {
                            Text(s.todo).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                if i < summaries.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
    }

    // MARK: gap closers

    @ViewBuilder private func gapClosers(rows: [HubData.RotationRow], advice: BoxAdvice, hub: HubData, gm: GameMaster) -> some View {
        let all = HubRaidsModel.gapClosers(rows: rows, advice: advice, entries: model.entries, gm: gm, hub: hub, screen: screen)
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

extension AppModel {
    /// The advice once it is ready; nil while it is being worked out or when there is none.
    var hubAdvice: BoxAdvice? { if case .ready(let a) = advice { return a } else { return nil } }
}
