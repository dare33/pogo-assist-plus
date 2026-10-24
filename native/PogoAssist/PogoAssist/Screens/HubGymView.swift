import SwiftUI
import PogoBox

/// Gym battles (design handoff section 5, screenshot 11): the six best built defenders as read-only slots, then every Gym build and the
/// Gym gaps. The design's tap-a-slot picker is not built (a manager call for this PR): the slots are suggestions the app works out itself.
struct HubGymView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        var count: String?
        if case .ready(let a) = model.advice { count = buildsText(HubModel.count(a.builds, for: .gym)) }
        return HubTypeScreen(type: .gym, count: count) {
            HubAdviceGate { advice in
                let defenders = HubTeams.topDefenders(builds: advice.builds)
                let hints = HubTeams.gymEmptyHints(builds: advice.builds, slots: 6 - defenders.count)
                HubSlotsPanel(title: "Top defenders", type: .gym) {
                    ForEach(0..<6, id: \.self) { i in
                        if defenders.indices.contains(i) {
                            let b = defenders[i]
                            HubSlotTile(type: .gym, disc: String(b.targetName.prefix(1)), name: b.targetName, sub: "CP \(b.cp)", filled: true,
                                        label: "Slot \(i + 1), \(b.targetName), CP \(b.cp)")
                                .accessibilityIdentifier("hub-gym-slot-\(i + 1)")
                        } else {
                            let hint = hints[i - defenders.count]
                            HubSlotTile(type: .gym, disc: "+", name: "Empty", sub: hint ?? "No Gym build yet", filled: false,
                                        label: "Slot \(i + 1), empty. \(hint ?? "No Gym build yet")")
                                .accessibilityIdentifier("hub-gym-slot-\(i + 1)")
                        }
                    }
                }
                let available = HubTeams.gymAvailable(builds: advice.builds)
                HubHeaderLine("TOP AVAILABLE")
                if available.isEmpty {
                    Text("The advisor has no Gym build in your box.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                } else {
                    HubBuildList(builds: available, type: .gym, highlightFirst: true)
                }
                HubGapList(gaps: HubModel.gaps(advice.gaps, for: .gym), type: .gym)
            }
        }
        .accessibilityIdentifier("hub-screen-gym")
    }
}

// MARK: slots, shared with the Rocket and PvP screens

/// A surface panel (radius 24, padding 14) titled 15/800, with a 3-column grid of slot tiles under it and an optional trailing note in the
/// title line (the PvP team's coverage).
struct HubSlotsPanel<Tiles: View, Trailing: View>: View {
    let title: String
    let type: ContentType
    @ViewBuilder var tiles: Tiles
    @ViewBuilder var trailing: Trailing

    init(title: String, type: ContentType, @ViewBuilder tiles: () -> Tiles, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.type = type; self.tiles = tiles(); self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 3), spacing: 8) { tiles }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
    }
}

extension HubSlotsPanel where Trailing == EmptyView {
    init(title: String, type: ContentType, @ViewBuilder tiles: () -> Tiles) { self.init(title: title, type: type, tiles: tiles, trailing: { EmptyView() }) }
}

/// One read-only slot (radius 16, at least 84 pt tall). Filled: the type's tint, a 34 pt disc in its ink holding `disc`, the name 13/700 and a
/// 11 muted line. Not filled: a 2 pt dashed hairline, the disc on `off`. `label` is the whole tile for VoiceOver.
struct HubSlotTile: View {
    let type: ContentType
    let disc: String
    let name: String
    var sub: String
    var sub2: String? = nil
    let filled: Bool
    let label: String
    @Environment(\.accent) private var accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Text(disc).font(.figtree(filled ? 15 : 20, .heavy, relativeTo: .subheadline))
                .foregroundStyle(filled ? Theme.surface : Theme.muted)
                .frame(width: 34, height: 34)
                .background(Circle().fill(filled ? type.ink(accent) : Theme.off))
                .accessibilityHidden(true)
            Text(name).font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(filled ? Theme.ink : Theme.muted).lineLimit(2)
            Text(sub).font(.figtree(11, .regular, relativeTo: .caption2)).foregroundStyle(Theme.muted).lineLimit(2)
            if let sub2 { Text(sub2).font(.figtree(11, .regular, relativeTo: .caption2)).foregroundStyle(Theme.muted).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(filled ? type.tint(accent) : Color.clear, in: shape)
        .overlay { if !filled { shape.strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [5, 4])) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
