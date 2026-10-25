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

    /// Widest the content gets. The screens are laid out as a phone (the widest is about 440 pt); in a regular-width
    /// iPad window they stay that shape in one centred column and the margins grow with the device, rather than
    /// stretching to 1000 pt or more. A compact-width window (an iPad split view, a phone) is narrower than this, so
    /// the column does nothing there and the layout is the phone's as it is.
    static let columnMax: CGFloat = 640

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
    /// Behind the "over cap" indicator.
    static let redTint = pair(0xFBE4E6, rgba: (255, 107, 118, 0.16))

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
    /// Max battles: a Dynamax-style magenta pink (Greg, 25 Oct 2026; it was the change purple). Distinct from `copies` (a rose). Contrast, computed with
    /// `Theme.contrast`: the light ink BE1E7E is 5.71:1 with white text on it and 4.84:1 on the light tint FDE6F3; the dark ink FF8FCB is 8.15:1 on
    /// the dark surface 181C26 (the dark tint is translucent, so the text sits on surface plus 18 per cent pink).
    static let maxInkLight: UInt32 = 0xBE1E7E
    static let maxInk = pair(maxInkLight, 0xFF8FCB)
    static let maxTint = pair(0xFDE6F3, rgba: (255, 110, 190, 0.18))

    // MARK: building colours

    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }
    /// Both values given as rgba (the league tints are translucent in light mode too).
    static func pair(rgba l: (CGFloat, CGFloat, CGFloat, CGFloat), dark d: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { c in
            let v = c.userInterfaceStyle == .dark ? d : l
            return UIColor(red: v.0 / 255, green: v.1 / 255, blue: v.2 / 255, alpha: v.3)
        })
    }
    /// A dark value given as the design's rgba (tints are translucent in dark mode).
    static func pair(_ light: UInt32, rgba d: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: d.0 / 255, green: d.1 / 255, blue: d.2 / 255, alpha: d.3) : rgb(light) })
    }
}

/// The three PvP leagues, coloured after GO Battle League (design handoff of 22 Oct 2026, "New tokens").
enum League: String, CaseIterable, Identifiable {
    case gl, ul, ml
    var id: String { rawValue }
    var title: String { switch self { case .gl: return "Great"; case .ul: return "Ultra"; case .ml: return "Master" } }
    /// Text in the league's colour.
    var ink: Color {
        switch self {
        case .gl: return Theme.pair(0x1F5FD1, 0x8FB0FF)
        case .ul: return Theme.pair(0x8A5A00, 0xF0C33C)
        case .ml: return Theme.pair(0x7A2FB5, 0xD1A3FF)
        }
    }
    /// The light-mode ink as a fixed colour in both modes: the background of a Hub card, under white text (white on it: GL 5.81, ML 7.24).
    var solid: Color {
        switch self {
        case .gl: return Color(uiColor: Theme.rgb(0x1F5FD1))
        case .ul: return Color(uiColor: Theme.rgb(0x8A5A00))
        case .ml: return Color(uiColor: Theme.rgb(0x7A2FB5))
        }
    }
    /// The dot and the tile's left border.
    var dot: Color {
        switch self {
        case .gl: return Theme.pair(0x3B82F6, 0x6FA3FF)
        case .ul: return Theme.pair(0xE0A82A, 0xF0C33C)
        case .ml: return Theme.pair(0xA855F7, 0xC58CFF)
        }
    }
    var tint: Color {
        switch self {
        case .gl: return Theme.pair(rgba: (59, 130, 246, 0.10), dark: (111, 163, 255, 0.14))
        case .ul: return Theme.pair(rgba: (224, 168, 42, 0.14), dark: (240, 195, 60, 0.14))
        case .ml: return Theme.pair(rgba: (168, 85, 247, 0.10), dark: (197, 140, 255, 0.14))
        }
    }
}

/// The kinds of content on the Pogo Hub. Each has an ink and a tint; `.everything` follows the accent, so both take it.
enum ContentType: String, CaseIterable, Identifiable {
    case everything, raids, gym, rocket, pvp, max
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everything: return "Everything"
        case .raids: return "Raids"
        case .gym: return "Gym battles"
        case .rocket: return "Team Rocket"
        case .pvp: return "PvP leagues"
        case .max: return "Max battles"
        }
    }
    func ink(_ accent: Accent) -> Color {
        switch self {
        case .everything: return accent.ink
        case .raids: return Theme.orangeInk
        case .gym: return Theme.greenInk
        case .rocket: return Theme.pair(0x2A3042, 0xB5BBCB)
        case .pvp: return Theme.pair(0x7A2FB5, 0xD1A3FF)
        case .max: return Theme.maxInk
        }
    }
    /// The type's light-mode ink as ONE colour in both modes (the darker colour of its pair): the background of a Hub card or a highlighted
    /// rank disc, under white text. White on it: raids 5.28, gym 5.38, rocket 13.13, pvp 7.24, max 6.72; everything is the accent's light
    /// ink (`Accent.inkLight`: blue 6.78, indigo 10.81, sky 6.04, teal 5.64, forest 8.88, berry 6.49, plum 9.74, graphite 13.13).
    func solid(_ accent: Accent) -> Color {
        switch self {
        case .everything: return accent.inkLight
        case .raids: return Color(uiColor: Theme.rgb(0xB34D00))
        case .gym: return Color(uiColor: Theme.rgb(0x1C7A3E))
        case .rocket: return Color(uiColor: Theme.rgb(0x2A3042))
        case .pvp: return Color(uiColor: Theme.rgb(0x7A2FB5))
        case .max: return Color(uiColor: Theme.rgb(0x5B3FD6))
        }
    }
    func tint(_ accent: Accent) -> Color {
        switch self {
        case .everything: return accent.tint
        case .raids: return Theme.orangeTint
        case .gym: return Theme.greenTint
        case .rocket: return Theme.pair(0xE9EBF0, rgba: (90, 98, 118, 0.3))
        case .pvp: return Theme.pair(0xEFEBFF, rgba: (156, 131, 255, 0.2))
        case .max: return Theme.maxTint
        }
    }
}

extension Theme {
    /// The game's type colours for Pokémon type chips (text from `pokemonTypeText`), the same in light and dark. Keyed by the
    /// type name as the game master spells it: lowercase.
    static let pokemonTypeHex: [String: UInt32] = [
        "normal": 0x9FA19F, "fire": 0xE62829, "water": 0x2980EF, "electric": 0xFAC000, "grass": 0x3FA129,
        "ice": 0x3DCEF3, "fighting": 0xFF8000, "poison": 0x9141CB, "ground": 0x915121, "flying": 0x81B9EF,
        "psychic": 0xEF4179, "bug": 0x91A119, "rock": 0xAFA981, "ghost": 0x704170, "dragon": 0x5060E1,
        "dark": 0x624D4E, "steel": 0x60A1B8, "fairy": 0xEF70EF,
    ]
    /// The text colour for a type chip: white or Theme ink's light value (#15192B, fixed, not dynamic), whichever has the
    /// higher WCAG contrast against the fill. Computed from the hex values above (each pair is chosen / other):
    /// white: fire 4.47/3.90, poison 5.49/3.17, ground 6.17/2.82, ghost 7.84/2.22, dragon 5.12/3.40, dark 7.80/2.23.
    /// ink: normal 6.69/2.60, water 4.50/3.87, electric 10.45/1.67, grass 5.26/3.31, ice 9.39/1.85, fighting 6.92/2.52,
    /// flying 8.39/2.08, psychic 4.73/3.68, bug 6.07/2.87, rock 7.31/2.38, steel 6.04/2.88, fairy 6.83/2.55.
    /// Fire keeps white at 4.47:1 (the better of the two, and the game's own look) by decision, though it is under 4.5.
    /// White for a name that is not a type.
    static func pokemonTypeText(_ type: String) -> Color {
        guard let hex = pokemonTypeHex[type.lowercased()] else { return .white }
        let ink: UInt32 = 0x15192B
        return contrast(0xFFFFFF, hex) >= contrast(ink, hex) ? .white : Color(uiColor: rgb(ink))
    }
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
    /// nil for a name that is not one of the 18 types.
    static func pokemonType(_ name: String) -> Color? {
        pokemonTypeHex[name.lowercased()].map { Color(uiColor: rgb($0)) }
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
    /// The light-mode ink, the same in dark mode (see `ContentType.solid`).
    var inkLight: Color { Color(uiColor: Theme.rgb(t.li)) }
    var tint: Color { Theme.pair(t.lt, rgba: t.dt) }
    /// On the light solid the text is always white; in dark mode it is per accent.
    var onSolid: Color { Theme.pair(0xFFFFFF, t.on) }
    /// The glyph on the solid where the "i" is open: `onSolid` when it reaches 4.5:1 against the solid, otherwise the
    /// darker of ink-light (#15192B) and black, whichever contrasts more. Chosen per accent and mode from the hex values:
    ///   light: blue black 4.67 (onSolid 4.50, just under), sky black 5.13 (4.09), teal black 5.61 (3.74); the rest onSolid
    ///   (indigo 8.16, forest 6.47, berry 4.62, plum 6.87, graphite 9.68).
    ///   dark: forest black 4.86 (onSolid 4.32); the rest onSolid (blue 5.97, indigo 5.01, sky 8.47, teal 8.69, berry 6.30,
    ///   plum 5.53, graphite 6.10).
    var openGlyph: Color {
        func pick(_ solid: UInt32, _ on: UInt32) -> UInt32 {
            if Theme.contrast(on, solid) >= 4.5 { return on }
            let ink: UInt32 = 0x15192B
            return Theme.contrast(ink, solid) >= Theme.contrast(0, solid) ? ink : 0
        }
        return Theme.pair(pick(t.ls, 0xFFFFFF), pick(t.ds, t.on))
    }

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

/// The preferences, stored in AppStorage under these keys.
enum PrefKey {
    static let accent = "accent"
    static let appearance = "appearance"
    static let helpLevel = "helpLevel"
    /// Which form of a Pokémon with a Mega form its page shows first: `MegaDefault`.
    static let megaDefault = "megaDefault"
    /// How the family member for a league is chosen, app-wide: `Ranking`.
    static let ranking = "ranking"
}

/// The global ranking choice. Nothing ranks by it yet; the switch and its raw value are here for the screens that will.
enum Ranking: String, CaseIterable, Identifiable {
    case `default`, pogoAssist
    var id: String { rawValue }
    var title: String { self == .default ? "Classic" : "Pogo Assist" }
}

enum Appearance: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var interfaceStyle: UIUserInterfaceStyle { switch self { case .auto: return .unspecified; case .light: return .light; case .dark: return .dark } }

    /// Light, Dark or Auto is set on the app's windows, not with `preferredColorScheme`: SwiftUI does not undo an explicit scheme
    /// when it goes back to nil inside a sheet that is already open, so Dark then Auto left Settings dark on a light phone.
    /// Every sheet is in the same window, so all of them follow.
    @MainActor static func applyToWindows(_ raw: String) {
        let style = (Appearance(rawValue: raw) ?? .auto).interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] { window.overrideUserInterfaceStyle = style }
        }
    }
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
/// `.tint` (so stock controls follow the accent) and the toast host. The colour scheme is set on the windows (`Appearance.applyToWindows`),
/// so it follows for every presentation, sheets and covers included; a new presentation still needs `themeRoot()` for the accent, help level and toast host.
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
            .toastHost()
            .onAppear { Appearance.applyToWindows(appearanceRaw) }
            .onChange(of: appearanceRaw) { _, new in Appearance.applyToWindows(new) }
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
