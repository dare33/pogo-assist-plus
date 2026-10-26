import SwiftUI
import PogoBox

/// The chrome every Hub type screen shares (design handoff section 5): the tab bar hidden, a back circle, the title with an optional
/// sub line, a count chip, and a content column the caller fills. The Collection screens use it, and so do the squad screens.
struct HubTypeScreen<Content: View>: View {
    let type: ContentType
    /// Replaces the type's name as the title (the Collection lists follow their switch).
    var title: String? = nil
    var sub: String? = nil
    /// The chip's text, "38 builds"; nil hides it.
    var count: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility text sizes the header is tall (the title and sub line wrap under the back circle), so it scrolls with the page rather than
        // taking half the screen for good.
        let big = typeSize.isAccessibilitySize
        VStack(spacing: 0) {
            if !big { header }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if big { header.padding(.horizontal, -Theme.Space.screen) }
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.screen)
                .padding(.bottom, 16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Two lines at most beside the back circle; on its own line at accessibility sizes it wraps at word boundaries and is never cut.
            Text(title ?? type.title).font(.figtree(20, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let sub { Text(sub).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
        }
    }

    private var chip: some View {
        Group {
            if let count {
                Text(count).font(.figtree(12, .heavy, relativeTo: .caption)).monospacedDigit().foregroundStyle(type.ink(accent))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(type.tint(accent), in: Capsule())
                    .accessibilityIdentifier("hub-type-count")
            }
        }
    }

    private var back: some View {
        IconButton(systemImage: "chevron.left", kind: .floating, label: "Back", identifier: "hub-back") { dismiss() }
    }

    @ViewBuilder private var header: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack { back; Spacer(minLength: 8); chip }
                titles
            }
            .padding(.horizontal, Theme.Space.screen)
            .frame(minHeight: 52)
        } else {
            HStack(spacing: 8) {
                back
                titles
                Spacer(minLength: 8)
                chip
            }
            .padding(.horizontal, Theme.Space.screen)
            .frame(minHeight: 52)
        }
    }
}

/// Where a tile or an event card goes: every content type has its own screen.
struct HubTypeDestination: View {
    let type: ContentType
    var body: some View {
        switch type {
        case .everything: HubCollectionView()
        case .raids: HubRaidsView()
        case .max: HubMaxView()
        case .gym: HubGymView()
        case .rocket: HubRocketView()
        case .pvp: HubPvPView()
        }
    }
}

/// The advice for a type screen, or the line that says why there is none.
struct HubAdviceGate<Content: View>: View {
    @EnvironmentObject var model: AppModel
    @ViewBuilder var content: (BoxAdvice) -> Content

    var body: some View {
        switch model.advice {
        case .ready(let a): content(a)
        case .computing:
            HStack(spacing: 10) { ProgressView(); Text("Working out advice").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted) }
                .accessibilityElement(children: .combine)
        case .failed(let m): Text("Advice could not be worked out: \(m)").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        case .none: Text("Scan your Pokémon and the Hub will fill in").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        }
    }
}

// MARK: shared blocks

/// A surface list of builds, best first: rank disc, name and tier, what to do, where it counts and what it costs. A row opens the Pokémon's page.
struct HubBuildList: View {
    let builds: [BoxAdvice.Build]
    let type: ContentType
    var highlightFirst = false
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(builds.enumerated()), id: \.element.id) { i, b in
                NavigationLink(value: b.entryId) { row(i, b) }
                    .buttonStyle(PressStyle())
                    .accessibilityIdentifier("hub-build-row")
                if i < builds.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
    }

    private func row(_ i: Int, _ b: BoxAdvice.Build) -> some View {
        let lit = highlightFirst && i == 0
        let figure = Self.figure(b)
        // Rule 15: a built row shows the Full strength badge where the cost was, and its sub line has no " · Free".
        let built = HubSquads.buildRow(b)
        let big = typeSize.isAccessibilitySize
        let rank = Text(verbatim: String(i + 1)).font(.figtree(13, .heavy, relativeTo: .footnote)).monospacedDigit()
            .foregroundStyle(lit ? Color.white : Theme.muted)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // the disc is a fixed 28 pt
            .frame(width: 28, height: 28)
            .background(Circle().fill(lit ? type.solid(accent) : Theme.surface2))
            .accessibilityHidden(true)
        let title = Text(b.title).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineLimit(big ? nil : 2)
        let texts = VStack(alignment: .leading, spacing: 2) {
            if big {
                title.fixedSize(horizontal: false, vertical: true)
                TierChip(tier: b.tier, type: type)
            } else {
                HStack(spacing: 8) { title; TierChip(tier: b.tier, type: type) }
            }
            Text(b.action).font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Text(built.subLine).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        let cost = Group {
            if built.showsFullStrength {
                FullStrengthBadge(size: 26).accessibilityHidden(true)
            } else {
                VStack(alignment: big ? .leading : .trailing, spacing: 0) {
                    Text(figure.value).font(.figtree(14, .heavy, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink)
                    if !figure.label.isEmpty { Text(figure.label).font(.figtree(10, .bold, relativeTo: .caption2)).tracking(0.06 * 10).foregroundStyle(Theme.muted) }
                }
            }
        }
        let chevron = Image(systemName: "chevron.right").font(.figtree(13, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
        // At accessibility text sizes the cost drops under the words (a column beside them would leave the title a few letters wide).
        return Group {
            if big {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) { rank; texts; chevron }
                    cost.padding(.leading, 40)
                }
            } else {
                HStack(spacing: 12) { rank; texts; cost; chevron }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(i + 1). \(b.title), tier \(b.tier). \(b.action). \(built.subLine)")
        .accessibilityValue(built.showsFullStrength ? "Full strength" : figure.label.isEmpty ? figure.value : "\(figure.value) \(figure.label.lowercased())")
    }

    /// Dust (short) over DUST; candy over CANDY when there is no dust; Free over nothing when both are 0.
    static func figure(_ b: BoxAdvice.Build) -> (value: String, label: String) {
        if b.dust > 0 { return (HubModel.dustShort(b.dust), "DUST") }
        if b.candy > 0 { return (String(b.candy), "CANDY") }
        return ("Free", "")
    }
}

/// `S` in the type's ink on its tint; `A` and `B` muted on the off colour.
struct TierChip: View {
    let tier: String
    let type: ContentType
    @Environment(\.accent) private var accent

    var body: some View {
        let top = tier == "S"
        Text(tier).font(.figtree(11, .heavy, relativeTo: .caption2))
            .foregroundStyle(top ? type.ink(accent) : Theme.muted)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(top ? type.tint(accent) : Theme.off, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Top-tier Pokémon that nothing in the box can become: the S tier by name with how to get it, and a count of the A tier.
struct HubGapList: View {
    let gaps: [BoxAdvice.Gap]
    let type: ContentType
    /// The Collection lists screen shows the header and its count even with no gaps, as the old Next list did.
    var alwaysShowsHeader = false

    var body: some View {
        let top = gaps.filter { $0.tier == "S" }, others = gaps.filter { $0.tier == "A" }.count
        if !top.isEmpty || others > 0 || alwaysShowsHeader { HubHeaderLine("GAPS (\(top.count) S TIER)") }
        if !top.isEmpty || others > 0 {
            VStack(spacing: 0) {
                ForEach(Array(top.enumerated()), id: \.element.id) { i, g in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) { Text(g.name).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink); TierChip(tier: g.tier, type: type) }
                        Text("\(g.area)\(g.section.map { ", \($0)" } ?? "")" + (g.obtain.map { ": \($0)" } ?? "")).font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    if i < top.count - 1 || others > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                }
                if others > 0 {
                    Text("Plus \(others) A-tier gaps.").font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .panelShadow()
            Text("Top-tier Pokémon that nothing in the box can become.").font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
        }
    }
}
