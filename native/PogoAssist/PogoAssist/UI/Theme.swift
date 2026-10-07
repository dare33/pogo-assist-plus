import SwiftUI
import UIKit

/// Design tokens for UI v1 (design handoff README, "Design tokens"). Every colour is a light/dark pair resolved
/// by the system, so a screen never branches on the colour scheme. Orange (look in the game), green (done) and
/// red (destructive) never follow the accent.
enum Theme {
    enum Radius {
        static let panel: CGFloat = 28
        static let insetRow: CGFloat = 16
        static let chip: CGFloat = 10
        static let sheet: CGFloat = 40
    }
    enum Space {
        static let screen: CGFloat = 14
        static let panelGap: CGFloat = 12
    }

    static let bg = pair(0xF3F5F9, 0x0E1118)
    static let surface = pair(0xFFFFFF, 0x181C26)
    static let surface2 = pair(0xF3F5F9, 0x20242F)
    static let ink = pair(0x15192B, 0xEEF1F8)
    static let muted = pair(0x6A7085, 0x9097AB)
    static let faint = pair(0x8A90A3, 0x6D7489)
    static let line = pair(0xE6E9F0, 0x262B38)
    static let off = pair(0xE3E7EF, 0x232836)

    static let orange = pair(0xFF8A1F, 0xFF9A3C)
    static let orangeInk = pair(0xB34D00, 0xFFB273)
    static let orangeTint = pair(0xFFF1E3, rgba: (255, 150, 60, 0.16))
    static let green = pair(0x22A55A, 0x3DCB7A)
    static let greenInk = pair(0x1C7A3E, 0x6FD796)
    static let greenTint = pair(0xE6F6EC, rgba: (80, 200, 120, 0.16))
    static let red = pair(0xD92D3A, 0xFF6B76)

    /// Question kind: match to one you have.
    static let match = pair(0x0E9AA7, 0x2EC4CF)
    static let matchInk = pair(0x087680, 0x6FDDE4)
    static let matchTint = pair(0xE0F5F6, rgba: (46, 196, 207, 0.18))
    /// Question kind: evolved / powered up.
    static let change = pair(0x7C5CFA, 0x9C83FF)
    static let changeInk = pair(0x5B3FD6, 0xBFAEFF)
    static let changeTint = pair(0xEFEBFF, rgba: (156, 131, 255, 0.2))
    /// Question kind: one or two (twin, Mega pair).
    static let copies = pair(0xE0457B, 0xF06595)
    static let copiesInk = pair(0xB02A5B, 0xFF9EC0)
    static let copiesTint = pair(0xFDE8EF, rgba: (240, 101, 149, 0.18))

    // MARK: building colours

    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }
    /// A dark value given as the design's rgba (tints are translucent in dark mode).
    static func pair(_ light: UInt32, rgba d: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: d.0 / 255, green: d.1 / 255, blue: d.2 / 255, alpha: d.3) : rgb(light) })
    }
}

/// The user's accent: solid (buttons, progress), ink (text on tint), tint (panels, secondary buttons) and the
/// text colour on the solid. Values are the README's table, light then dark.
enum Accent: String, CaseIterable, Identifiable {
    case blue, indigo, sky, teal, forest, berry, plum, graphite
    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var solid: Color { Theme.pair(t.ls, t.ds) }
    var ink: Color { Theme.pair(t.li, t.di) }
    var tint: Color { Theme.pair(t.lt, rgba: t.dt) }
    /// On the light solid the text is always white; in dark mode it is per accent.
    var onSolid: Color { Theme.pair(0xFFFFFF, t.on) }

    /// The mark's ring and the on-disc ink in dark mode: a navy, not the background. White in light mode, and in dark mode for the accents whose onSolid is already white.
    var markInk: Color { Theme.pair(0xFFFFFF, t.on == 0xFFFFFF ? 0xFFFFFF : 0x1B2A4E) }

    private struct T { let ls, li, lt, ds, di: UInt32; let dt: (CGFloat, CGFloat, CGFloat, CGFloat); let on: UInt32 }
    private var t: T {
        switch self {
        case .blue: return T(ls: 0x2F6BFF, li: 0x1F4FD1, lt: 0xEAF0FF, ds: 0x5B8CFF, di: 0x8FB0FF, dt: (91, 140, 255, 0.18), on: 0x0E1118)
        case .indigo: return T(ls: 0x3B3FB6, li: 0x2D3091, lt: 0xE8E9F8, ds: 0x5B60E0, di: 0xA9ACF5, dt: (91, 96, 224, 0.22), on: 0xFFFFFF)
        case .sky: return T(ls: 0x0A84C6, li: 0x06689D, lt: 0xE3F3FB, ds: 0x4CB8F0, di: 0x8FD3F7, dt: (76, 184, 240, 0.18), on: 0x0E1118)
        case .teal: return T(ls: 0x0F9488, li: 0x0B746A, lt: 0xDFF4F1, ds: 0x2DC4B4, di: 0x7FE0D5, dt: (45, 196, 180, 0.18), on: 0x0E1118)
        case .forest: return T(ls: 0x1F6B45, li: 0x17543A, lt: 0xE1EFE7, ds: 0x278A58, di: 0x7FD1A6, dt: (39, 138, 88, 0.22), on: 0xFFFFFF)
        case .berry: return T(ls: 0xD6336C, li: 0xB0235A, lt: 0xFCE7EF, ds: 0xF06595, di: 0xF7A1C1, dt: (240, 101, 149, 0.18), on: 0x0E1118)
        case .plum: return T(ls: 0x8E3B7A, li: 0x6E2A5E, lt: 0xF5E6F0, ds: 0x9E4A8A, di: 0xE0A3CF, dt: (158, 74, 138, 0.24), on: 0xFFFFFF)
        case .graphite: return T(ls: 0x3D4459, li: 0x2A3042, lt: 0xE9EBF0, ds: 0x5A6276, di: 0xB5BBCB, dt: (90, 98, 118, 0.3), on: 0xFFFFFF)
        }
    }
}

// MARK: preferences

/// The three preferences, stored in AppStorage under these keys.
enum PrefKey {
    static let accent = "accent"
    static let appearance = "appearance"
    static let helpLevel = "helpLevel"
    /// Which form of a Pokémon with a Mega form its page shows first: `MegaDefault`.
    static let megaDefault = "megaDefault"
}

enum Appearance: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    /// nil follows the system.
    var colorScheme: ColorScheme? { switch self { case .auto: return nil; case .light: return .light; case .dark: return .dark } }
}

enum HelpLevel: String, CaseIterable, Identifiable {
    case guide, standard, essentials
    var id: String { rawValue }
}

private struct AccentKey: EnvironmentKey { static let defaultValue = Accent.blue }
private struct HelpLevelKey: EnvironmentKey { static let defaultValue = HelpLevel.standard }
extension EnvironmentValues {
    /// Set once at the root from the "accent" preference.
    var accent: Accent {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
    /// Set once at the root from the "helpLevel" preference.
    var helpLevel: HelpLevel {
        get { self[HelpLevelKey.self] }
        set { self[HelpLevelKey.self] = newValue }
    }
}

/// Reads the preferences from AppStorage and applies them: the accent and help level in the environment,
/// `.tint` (so stock controls follow the accent), the colour scheme and the toast host. Apply once at the root.
struct ThemeRoot: ViewModifier {
    @AppStorage(PrefKey.accent) private var accentRaw = Accent.blue.rawValue
    @AppStorage(PrefKey.appearance) private var appearanceRaw = Appearance.auto.rawValue
    @AppStorage(PrefKey.helpLevel) private var helpRaw = HelpLevel.standard.rawValue

    func body(content: Content) -> some View {
        let accent = Accent(rawValue: accentRaw) ?? .blue
        content
            .environment(\.accent, accent)
            .environment(\.helpLevel, HelpLevel(rawValue: helpRaw) ?? .standard)
            .tint(accent.solid)
            .preferredColorScheme((Appearance(rawValue: appearanceRaw) ?? .auto).colorScheme)
            .toastHost()
    }
}
extension View {
    func themeRoot() -> some View { modifier(ThemeRoot()) }

    /// Panel shadow: 0 1px 2px rgba(20,30,60,.06) in light, none in dark.
    func panelShadow() -> some View { modifier(PanelShadow()) }
}

private struct PanelShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.shadow(color: scheme == .dark ? .clear : Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255).opacity(0.06), radius: 1, x: 0, y: 1)
    }
}
