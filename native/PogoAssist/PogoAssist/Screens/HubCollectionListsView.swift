import SwiftUI
import PogoBox

/// The Collection lists screen (pass 2 README "Collection lists", board `Everything.dc.html`; was Everything): a Builds | Gaps | Duplicates switch with the title following it.
/// Builds holds the three headline cards, the stardust card, the builds that fit the stardust and the whole build list (no SHOW ALL); Gaps and Duplicates are as before.
struct HubCollectionListsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var tab: CollectionTab
    @State private var asking = false
    @State private var entry = ""
    /// The last entry was rejected; cleared by the next valid one.
    @State private var rejected = false

    init(tab: CollectionTab = .builds) { _tab = State(initialValue: tab) }

    var body: some View {
        HubTypeScreen(type: .everything, title: tab.label, count: chip) {
            SegmentedSwitch(
                segments: CollectionTab.allCases.map { .init(value: $0, title: $0.label, identifier: "collection-tab-\($0.rawValue)") },
                selection: $tab, label: "List", identifier: "collection-lists-switch")
            if case .ready(let advice) = model.advice {
                switch tab {
                case .builds: builds(advice)
                case .gaps: HubGapList(gaps: advice.gaps, type: .everything, alwaysShowsHeader: true)
                case .duplicates: duplicates(advice)
                }
            } else {
                if tab == .builds { stardustCard(builds: []); problemLine }
                HubAdviceGate { _ in EmptyView() }
            }
        }
        .alert("Stardust", isPresented: $asking) {
            TextField("Stardust", text: $entry).keyboardType(.numberPad).accessibilityIdentifier("hub-stardust-field")
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("How much stardust you have in the game. Leave it empty to clear it.") }
    }

    /// The chip follows the tab: builds, gaps (S and A together) or species with duplicates.
    private var chip: String? {
        guard case .ready(let a) = model.advice else { return nil }
        switch tab {
        case .builds: return buildsText(a.builds.count)
        case .gaps: return "\(a.gaps.filter { $0.tier == "S" || $0.tier == "A" }.count) gaps"
        case .duplicates: return "\(a.duplicates.count) species"
        }
    }

    // MARK: builds

    @ViewBuilder private func builds(_ a: BoxAdvice) -> some View {
        let stardust = model.stardust
        let heads = HubModel.headlines(a.builds, stardust: stardust)
        if heads.doFirst != nil { headlineStrip(heads) }
        let fit = stardust.map { HubModel.fitting(a.builds, stardust: $0) }
        stardustCard(builds: fit?.fits ?? [], used: fit?.used, left: fit?.left)
        problemLine
        if a.builds.isEmpty {
            Text("The advisor found nothing worth building in this box.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        }
        if let fit {
            HubHeaderLine("THESE FIT")
            if fit.fits.isEmpty {
                Text("No build fits this stardust.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            } else {
                HubBuildList(builds: fit.fits, type: .everything, highlightFirst: true)
            }
        }
        if !a.builds.isEmpty {
            HubHeaderLine("ALL \(a.builds.count) BUILDS")
            HubBuildList(builds: a.builds, type: .everything, highlightFirst: fit == nil)
        }
    }

    // MARK: headline cards

    private func headlineStrip(_ h: (doFirst: BoxAdvice.Build?, cheapWin: BoxAdvice.Build?, worthSavingFor: BoxAdvice.Build?)) -> some View {
        let cards: [(String, BoxAdvice.Build?, Color)] = [
            ("DO FIRST", h.doFirst, ContentType.raids.solid(accent)),
            ("CHEAP WIN", h.cheapWin, League.gl.solid),
            ("WORTH SAVING FOR", h.worthSavingFor, League.ml.solid),
        ]
        return HubCardStrip {
                ForEach(cards.indices, id: \.self) { i in
                    if let b = cards[i].1 {
                        NavigationLink(value: b.entryId) {
                            HubCard(kicker: cards[i].0, title: HubModel.headline(for: b), line: HubModel.cardLine(for: b), base: cards[i].2)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(cards[i].0.capitalized), \(HubModel.headline(for: b)), \(HubModel.cardLine(for: b))")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("hub-card-\(i)")
                    }
                }
        }
    }

    // MARK: stardust

    private func stardustCard(builds: [BoxAdvice.Build], used: Int? = nil, left: Int? = nil) -> some View {
        let stardust = model.stardust
        let icon = Image(systemName: "sparkle").font(.figtree(20, .bold)).foregroundStyle(ContentType.max.ink(accent))
            .frame(width: 44, height: 44).background(Circle().fill(Theme.surface2)).accessibilityHidden(true)
        let details = VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) { figure(stardust); Spacer(minLength: 8); change }
                VStack(alignment: .leading, spacing: 0) { figure(stardust); change }
            }
            if let stardust, stardust > 0, !builds.isEmpty {
                StardustBar(builds: builds, stardust: stardust).frame(height: 8).accessibilityHidden(true)
            }
            Text(stardust != nil && used != nil && left != nil
                 ? "The builds below fit: \(HubModel.dustShort(used ?? 0)) of it, \(HubModel.dustShort(left ?? 0)) left over."
                 : "Enter your stardust to see which builds fit.")
                .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
        }
        // At accessibility text sizes the icon sits above the words instead of taking a column from them.
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { icon; details }
            } else {
                HStack(alignment: .top, spacing: 12) { icon; details }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .panelShadow()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub-stardust-card")
    }

    private func figure(_ stardust: Int?) -> some View {
        ViewThatFits(in: .horizontal) {
            figureLine(stardust, stacked: false)
            figureLine(stardust, stacked: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func figureLine(_ stardust: Int?, stacked: Bool) -> some View {
        let value = Group {
            if let stardust {
                Text(HubModel.grouped(stardust)).font(.figtree(22, .heavy, relativeTo: .title2)).monospacedDigit().foregroundStyle(Theme.ink)
            } else {
                Text("Not set").font(.figtree(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.muted)
            }
        }
        let label = Text("STARDUST").font(.figtree(12, .bold, relativeTo: .caption)).tracking(0.05 * 12).foregroundStyle(Theme.muted)
        if stacked {
            VStack(alignment: .leading, spacing: 0) { value; label }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) { value; label }
        }
    }

    private var change: some View {
        Button { entry = model.stardust.map(String.init) ?? ""; asking = true } label: {
            Text("Change").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("hub-stardust-change")
    }

    @ViewBuilder private var problemLine: some View {
        if rejected {
            Text("Stardust must be a whole number, up to 999,999,999.").font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.red)
                .padding(.horizontal, 4)
                .accessibilityIdentifier("hub-stardust-problem")
        }
    }

    /// Digits only (commas and spaces are fine, at most nine digits); empty clears; anything else leaves it as it was and says so.
    private func save() {
        let trimmed = entry.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { model.stardust = nil; rejected = false; return }
        let digits = trimmed.filter { $0 != "," && $0 != " " }
        if !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), digits.count <= 9, let n = Int(digits) { model.stardust = n; rejected = false } else { rejected = true }
    }

    // MARK: duplicates

    @ViewBuilder private func duplicates(_ a: BoxAdvice) -> some View {
        if !a.duplicates.isEmpty {
            HubHeaderLine("DUPLICATES (\(a.duplicates.count) SPECIES)")
            VStack(spacing: 0) {
                let shown = Array(a.duplicates.prefix(15))
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, d in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(d.name), \(d.count) copies").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                        Text("Keep: \(d.keep.joined(separator: "; "))").font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
                        Text("Transfer \(d.transfer.count)").font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    if i < shown.count - 1 || a.duplicates.count > 15 { Rectangle().fill(Theme.line).frame(height: 1) }
                }
                if a.duplicates.count > 15 {
                    Text("Plus \(a.duplicates.count - 15) more species.").font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .panelShadow()
        }
    }
}

/// The share of the stardust each fitting build takes, in the colour of its first area, 2 pt gaps between, the rest `off`.
private struct StardustBar: View {
    let builds: [BoxAdvice.Build]
    let stardust: Int
    @Environment(\.accent) private var accent

    /// The Hub screen a build's first area belongs to (the leagues are PvP).
    static func type(of b: BoxAdvice.Build) -> ContentType {
        switch b.areas.first {
        case "Raids": return .raids
        case "Gym": return .gym
        case "Rocket": return .rocket
        case "Max": return .max
        case "GL", "UL", "ML": return .pvp
        default: return .everything
        }
    }

    var body: some View {
        let parts = builds.filter { $0.dust > 0 }.map { (Double($0.dust) / Double(stardust), Self.type(of: $0).ink(accent)) }
        return Canvas { ctx, size in
            ctx.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4))
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.off))
            var x: CGFloat = 0
            for (share, colour) in parts {
                let w = size.width * share
                ctx.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)), with: .color(colour))
                ctx.fill(Path(CGRect(x: x + w - 2, y: 0, width: 2, height: size.height)), with: .color(Theme.surface))
                x += w
            }
        }
    }
}
