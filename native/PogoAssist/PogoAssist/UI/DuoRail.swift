import SwiftUI

// The control rail for the foldable iPhone Duo. Folded, and open wide, the system puts the clock and Wi-Fi icons in a vertical strip at the trailing edge
// and keeps the window's safe area out of it, so the rest of the strip is empty. When that strip exists the app draws its own rail in it: the page's circle
// buttons at the top, navigation and Scan at the bottom. Everywhere else (every other iPhone, iPad, the Duo open and rotated tall) nothing here is active
// and the screens lay out as before.

/// Where the rail sits and what it is made of.
enum Rail {
    /// How far below the top of the screen the page controls start. Measured on the Duo simulator (iOS 27.2): the status icons fill about the top 150 pt of the
    /// strip, and no API reports where they end, so this is the measured figure plus a little air.
    static let controlsTop: CGFloat = 160
    /// The strip's width on the Duo simulator, used only if the window reports a trailing inset of 0 while the rail is active.
    static let fallbackWidth: CGFloat = 84
    /// Room a screen leaves at its bottom for the floating tab bar; none when the navigation is in the rail instead.
    static func clearance(active: Bool) -> CGFloat { active ? 0 : FloatingTabBar.clearance }
}

private struct RailActiveKey: EnvironmentKey { static let defaultValue = false }
private struct RailTabShownKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// The Duo's vertical strip exists, so the control rail is drawn in it (set by `RootView`).
    var railActive: Bool {
        get { self[RailActiveKey.self] }
        set { self[RailActiveKey.self] = newValue }
    }
    /// False inside the tab that is hidden: its screens stay alive but must not put controls in the rail.
    var railTabShown: Bool {
        get { self[RailTabShownKey.self] }
        set { self[RailTabShownKey.self] = newValue }
    }
    /// Room a screen should leave at its bottom so nothing scrolls under the tab bar: `FloatingTabBar.clearance`, or 0 when the navigation is in the rail.
    var tabBarClearance: CGFloat { Rail.clearance(active: railActive) }
}

// MARK: detecting the strip

/// Reports whether the system's vertical bar is on the trailing edge. Read from the window scene's traits (as `ScreenReader` reads the idiom) when the window
/// lays out, which it does again when the Duo is folded, opened or rotated. Never active below iOS 27.1, where the trait does not exist.
struct RailReader: UIViewRepresentable {
    var report: (Bool) -> Void

    final class ReaderView: UIView {
        var report: (Bool) -> Void = { _ in }
        override func didMoveToWindow() { super.didMoveToWindow(); read() }
        override func layoutSubviews() { super.layoutSubviews(); read() }
        private func read() {
            guard let scene = window?.windowScene else { return }
            var active = false
            if #available(iOS 27.1, *) { active = scene.traitCollection.verticalBarEdge == .trailing }
            // Not inside the layout pass: the report changes SwiftUI state.
            DispatchQueue.main.async { [report] in report(active) }
        }
    }

    func makeUIView(context: Context) -> ReaderView {
        let v = ReaderView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.report = report
        return v
    }
    func updateUIView(_ v: ReaderView, context: Context) { v.report = report }
}

// MARK: what the screens publish

/// One screen's controls, built by the screen (so its menus, dialogs, bindings and identifiers keep working) and drawn by the root.
struct RailEntry {
    /// When the screen appeared, from `RailEntries.nextSequence()`: of two screens showing at once (a push or pop under way) the later one owns the rail.
    let sequence: Int
    let view: AnyView
}

enum RailEntries {
    @MainActor private static var counter = 0
    @MainActor static func nextSequence() -> Int { counter += 1; return counter }

    /// The entries to draw: those of the most recently appeared screen, in the order they were published (tree order, so a screen's Back comes before its other buttons).
    /// Nothing published gives an empty rail.
    static func visible(_ entries: [RailEntry]) -> [RailEntry] {
        guard let latest = entries.map(\.sequence).max() else { return [] }
        return entries.filter { $0.sequence == latest }
    }
}

struct RailKey: PreferenceKey {
    static var defaultValue: [RailEntry] = []
    static func reduce(value: inout [RailEntry], nextValue: () -> [RailEntry]) { value += nextValue() }
}

/// A screen's header circle buttons. Rail inactive: `inline` (by default the same content) is drawn where it is, exactly as before. Rail active: nothing is drawn
/// here and the content goes to the rail while this screen is the one showing. Use one per screen, with Back first, so the screen's buttons share one appear
/// sequence and keep their order.
struct RailControls<Buttons: View, Inline: View>: View {
    let rail: Buttons
    let inline: Inline
    @Environment(\.railActive) private var active
    @Environment(\.railTabShown) private var tabShown
    @State private var appeared: Int?

    init(rail: Buttons, inline: Inline) { self.rail = rail; self.inline = inline }

    var body: some View {
        if !active {
            inline
        } else {
            Color.clear.frame(width: 0, height: 0)
                .onAppear { appeared = RailEntries.nextSequence() }
                .onDisappear { appeared = nil }
                .preference(key: RailKey.self, value: tabShown ? appeared.map { [RailEntry(sequence: $0, view: AnyView(rail))] } ?? [] : [])
        }
    }
}

extension RailControls where Inline == Buttons {
    init(@ViewBuilder _ content: () -> Buttons) { let c = content(); self.init(rail: c, inline: c) }
}

extension RailControls {
    /// For a header whose inline layout is not just the buttons in a row (Back, a spacer, then the others): `inline` is what draws when the rail is not active.
    init(@ViewBuilder rail: () -> Buttons, @ViewBuilder inline: () -> Inline) { self.init(rail: rail(), inline: inline()) }
}

// MARK: drawing the rail

/// The rail itself: an opaque strip of `Theme.bg` over the page, the screen's controls from the top, navigation and Scan at the bottom. Drawn by the root over
/// the whole window, past the safe area the system leaves for the strip.
struct RailView: View {
    let entries: [RailEntry]
    @Binding var tab: AppTab
    var showsNavigation: Bool
    var scanDisabled: Bool
    var onScan: () -> Void

    var body: some View {
        GeometryReader { g in
            let width = g.safeAreaInsets.trailing > 0 ? g.safeAreaInsets.trailing : Rail.fallbackWidth
            VStack(spacing: 8) {
                // Page controls first, so VoiceOver reads them before the navigation.
                VStack(spacing: 8) { ForEach(Array(RailEntries.visible(entries).enumerated()), id: \.offset) { $0.element.view } }
                    .padding(.top, Rail.controlsTop)
                Spacer(minLength: 0)
                if showsNavigation {
                    RailNavigation(tab: $tab, scanDisabled: scanDisabled, onScan: onScan)
                        .padding(.bottom, max(g.safeAreaInsets.bottom, 8))
                }
            }
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(Theme.bg)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .ignoresSafeArea()
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// My Pokémon, Scan and Pogo Hub stacked for the rail. The same buttons as `FloatingTabBar`, with the same labels and identifiers, sized for the 84 pt strip.
struct RailNavigation: View {
    @Binding var tab: AppTab
    var scanDisabled: Bool
    var onScan: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 10) {
            tabButton("My Pokémon", "square.grid.2x2", .box, identifier: "tab-box")
            scanButton
            tabButton("Pogo Hub", "line.3.horizontal", .next, identifier: "tab-next")
        }
    }

    private func tabButton(_ title: String, _ symbol: String, _ target: AppTab, identifier: String) -> some View {
        let on = tab == target
        return Button { tab = target } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.figtree(18, .bold)).accessibilityHidden(true)
                    .frame(width: 52, height: 40)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? accent.tint : Theme.surface))
                // At 10 pt "My Pokémon" fits the 84 pt strip with a little shrink; it never truncates to a stub.
                Text(title).font(.figtree(10, .bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? accent.ink : Theme.muted)
            .frame(width: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var scanButton: some View {
        Button(action: onScan) {
            ScanMark().frame(width: 52, height: 52)
                .foregroundStyle(accent.markInk)
                .frame(width: 64, height: 64)
                .background(Circle().fill(accent.solid))
                .opacity(scanDisabled ? 0.45 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(scanDisabled)
        .accessibilityLabel("Scan")
    }
}
