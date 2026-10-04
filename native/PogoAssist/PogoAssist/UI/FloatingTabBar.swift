import SwiftUI

enum AppTab: String { case box, next }

/// The floating tab bar (design handoff component 10): a Box pill, the 96 pt scan button (the scan mark, with an
/// 8 pt accent-tint halo) and a Next pill, over a gradient that fades the screen into the background.
/// The accessibility labels are "Box", "Scan" and "Next".
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var scanDisabled = false
    var onScan: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.colorScheme) private var scheme

    /// Room a screen should leave at its bottom so nothing scrolls under the bar.
    static let clearance: CGFloat = 112

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(stops: [.init(color: Theme.bg.opacity(0), location: 0), .init(color: Theme.bg, location: 0.4), .init(color: Theme.bg, location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            HStack {
                pill("Box", "square.grid.2x2", .box)
                Spacer(minLength: 8)
                scanButton
                Spacer(minLength: 8)
                pill("Next", "list.number", .next)
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.bottom, 4)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func pill(_ title: String, _ symbol: String, _ tab: AppTab) -> some View {
        let on = selection == tab
        return Button { selection = tab } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.figtree(15, .bold)).accessibilityHidden(true)
                Text(title).font(.figtree(14, .bold, relativeTo: .subheadline))
            }
            .foregroundStyle(on ? accent.ink : Theme.muted)
            .frame(minWidth: 88, idealWidth: 118, maxWidth: 118, minHeight: 54)
            .background(Capsule().fill(on ? accent.tint : Theme.surface))
            .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255).opacity(scheme == .dark ? 0 : 0.1), radius: 8, x: 0, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var scanButton: some View {
        Button(action: onScan) {
            ScanMark().frame(width: 80, height: 80)
                .foregroundStyle(accent.onSolid)
                .frame(width: 96, height: 96)
                .background(Circle().fill(accent.solid))
                .background(Circle().fill(accent.tint).padding(-8))
                .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255).opacity(scheme == .dark ? 0 : 0.25), radius: 13, x: 0, y: 10)
                .opacity(scanDisabled ? 0.45 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(scanDisabled)
        .padding(.bottom, 10)
        .accessibilityLabel("Scan")
    }
}

// MARK: hiding the bar

struct HidesTabBarKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// A pushed screen that wants the floating tab bar gone (detail, scan, review) says so with this.
    func hidesTabBar(_ hides: Bool = true) -> some View { preference(key: HidesTabBarKey.self, value: hides) }
}
