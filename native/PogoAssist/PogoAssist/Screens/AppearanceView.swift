import SwiftUI

/// Settings > Appearance (design handoff v2 section 1l and the prototype's Settings screen): the accent, light / dark / auto and the help level. Each choice is written to
/// AppStorage and the root (`ThemeRoot`) reads it, so it takes effect at once.
struct AppearanceView: View {
    @AppStorage(PrefKey.accent) private var accentRaw = Accent.blue.rawValue
    @AppStorage(PrefKey.appearance) private var appearanceRaw = Appearance.auto.rawValue
    @AppStorage(PrefKey.helpLevel) private var helpRaw = HelpLevel.standard.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Accent { Accent(rawValue: accentRaw) ?? .blue }
    private var appearance: Appearance { Appearance(rawValue: appearanceRaw) ?? .auto }
    private var help: HelpLevel { HelpLevel(rawValue: helpRaw) ?? .standard }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.panelGap) {
                accentPanel
                modePanel
                helpPanel
            }
            .padding(.horizontal, Theme.Space.screen).padding(.top, 6).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func set(_ apply: () -> Void) { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2), apply) }

    // MARK: accent

    private var accentPanel: some View {
        Panel(padding: 18, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Accent colour").font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(accent.name).font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(Accent.allCases) { a in swatch(a) }
            }
        }
    }

    private func swatch(_ a: Accent) -> some View {
        let on = a == accent
        return Button { set { accentRaw = a.rawValue } } label: {
            VStack(spacing: 4) {
                ZStack {
                    if on { Circle().stroke(a.solid, lineWidth: 2).frame(width: 60, height: 60) }
                    Circle().fill(a.solid).frame(width: 50, height: 50)
                    if on { Image(systemName: "checkmark").font(.figtree(18, .heavy)).foregroundStyle(a.onSolid).accessibilityHidden(true) }
                }
                .frame(width: 60, height: 60)
                Text(a.name).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(a.name)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("accent-\(a.rawValue)")
    }

    // MARK: mode

    private var modePanel: some View {
        Panel(padding: 18, spacing: 12) {
            Text("Mode").font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                ForEach(Appearance.allCases.sorted { $0.order < $1.order }) { m in modeButton(m) }
            }
            .padding(4).background(Theme.off, in: Capsule())
        }
    }

    private func modeButton(_ m: Appearance) -> some View {
        let on = m == appearance
        return Button { set { appearanceRaw = m.rawValue } } label: {
            HStack(spacing: 6) { Image(systemName: m.icon).accessibilityHidden(true); Text(m.title) }
                .font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(on ? Theme.surface : Color.clear, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("mode-\(m.rawValue)")
    }

    // MARK: help level

    private var helpPanel: some View {
        Panel(padding: 18, spacing: 10) {
            Text("Help level").font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            ForEach(HelpLevel.allCases) { h in helpRow(h) }
        }
    }

    private func helpRow(_ h: HelpLevel) -> some View {
        let on = h == help
        return Button { set { helpRaw = h.rawValue } } label: {
            HStack(spacing: 12) {
                Circle().fill(on ? accent.solid : Color.clear).frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(on ? accent.tint : Theme.line, lineWidth: on ? 5 : 2))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(h.title).font(.figtree(16, .bold, relativeTo: .body)).foregroundStyle(Theme.ink)
                    Text(h.summary).font(.figtree(13, .regular, relativeTo: .footnote)).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 56)
            .background(on ? accent.tint : Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("help-\(h.rawValue)")
    }
}

extension Appearance {
    /// The design's order: Light, Dark, Auto.
    fileprivate var order: Int { switch self { case .light: return 0; case .dark: return 1; case .auto: return 2 } }
    fileprivate var title: String { switch self { case .light: return "Light"; case .dark: return "Dark"; case .auto: return "Auto" } }
    fileprivate var icon: String { switch self { case .light: return "sun.max"; case .dark: return "moon"; case .auto: return "circle.lefthalf.filled" } }
}

extension HelpLevel {
    var title: String {
        switch self { case .guide: return "Guide me"; case .standard: return "Standard"; case .essentials: return "Just the essentials" }
    }
    /// The design's line for the level, kept to what this build does. Guide me: the questions go one at a time, and nothing is hidden (the scan steps always show).
    /// Just the essentials: the design also says "no help lines", but only the part-read legend and one sentence of its note are hidden, so that half is left out.
    var summary: String {
        switch self {
        case .guide: return "One question at a time, all help shown"
        case .standard: return "Questions on one screen, help shown"
        case .essentials: return "Questions on one screen"
        }
    }
}
