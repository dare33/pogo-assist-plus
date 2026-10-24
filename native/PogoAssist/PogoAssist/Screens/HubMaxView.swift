import SwiftUI
import PogoBox

/// The Max battles screen (design handoff section 5, screenshot 14): the `Now | Coming up` timeline of Max Mondays and Dynamax Trails,
/// then the Pokémon marked Dynamax with the role the Max table gives each. Readiness counts those copies only.
struct HubMaxView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .max)) }
        let sub = (try? HubData.bundled()).flatMap { HubRaidsModel.lastDay(rows: $0.rotation, screen: .max) }.map { "Max Mondays and events to \($0)" }
        return HubTypeScreen(type: .max, sub: sub, count: count) {
            HubTimeline(screen: .max, advice: model.hubAdvice, entries: model.entries, closers: false)
            HubAdviceGate { advice in roster(advice) }
            HubScheduleLink()
        }
        .accessibilityIdentifier("hub-screen-max")
    }

    @ViewBuilder private func roster(_ advice: BoxAdvice) -> some View {
        let roster = HubRaidsModel.maxRoster(entries: model.entries, advice: advice)
        HubHeaderLine("YOUR MAX ROSTER")
        if roster.tiles.isEmpty {
            Text("No Pokémon are marked Dynamax yet.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("hub-max-roster-empty")
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(roster.tiles, id: \.entryId) { RosterTileView(tile: $0) }
            }
        }
        if roster.unsetCount > 0 {
            Text("\(roster.unsetCount) Pokémon not set: mark Dynamax on each Pokémon's page")
                .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("hub-max-unset")
        }
        Text("Only Pokémon caught as Dynamax can take part; the readiness bar counts the copies you have marked.")
            .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
    }
}

/// A roster tile: radius 16, a 3 pt left border in the Max ink, the name in small caps, the build line, the CP. Opens the Pokémon's page.
private struct RosterTileView: View {
    let tile: HubRaidsModel.RosterTile
    @Environment(\.accent) private var accent

    var body: some View {
        NavigationLink(value: tile.entryId) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tile.name.uppercased()).font(.figtree(11, .heavy, relativeTo: .caption2)).tracking(0.05 * 11).foregroundStyle(Theme.muted).lineLimit(2)
                Text(tile.line).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(tile.hasUse ? Theme.ink : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tile.state.isEmpty ? "CP \(tile.cp)" : "\(tile.state) · CP \(tile.cp)").font(.figtree(12, .regular, relativeTo: .caption)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .leading) { Rectangle().fill(ContentType.max.ink(accent)).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .panelShadow()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name), \(tile.line)\(tile.state.isEmpty ? "" : ", \(tile.state)"), CP \(tile.cp)")
        .accessibilityIdentifier("hub-max-tile")
    }
}
