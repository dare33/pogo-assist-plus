import SwiftUI

/// Figtree (OFL, `Resources/Fonts/Figtree-Variable.ttf`, registered through UIAppFonts) and the README type table.
///
/// How the weights work: the file is one variable font. iOS lists its named instances as separate faces
/// ("Figtree-Regular", "-Medium", "-SemiBold", "-Bold", "-ExtraBold", ...), and `Font.custom(face, size:relativeTo:)`
/// on a face scales with Dynamic Type. Do NOT use `Font.custom("Figtree", ...).weight(...)`: the weight modifier does
/// not move a custom face along the weight axis, so every weight would render alike.
///
/// Use `Font.figtree(size, weight, relativeTo:)` for anything else, or a role:
///   `Text(x).paText(.rowTitle)`  sets the font, tracking and line spacing of a role (preferred),
///   `Font.rowTitle` etc. are the bare fonts of the same roles (no tracking or line height).
/// Roles (size / weight / line height): heroFigure 48/800/52 tracking -0.03em, screenTitle 32/800/37 -0.02em,
/// questionTitle 19/700/25 (questionTitleGuide 25/800/31 for the Guide me level), rowTitle 16/600, button 16/700,
/// secondary 14/500/20 (colour it `Theme.muted` yourself), chipLabel 12/700 caps +0.07em.
/// Numbers are tabular: every role applies `.monospacedDigit()`.
extension Font {
    static let figtreeFamily = "Figtree"

    static func figtree(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(faceName(weight), size: size, relativeTo: style)
    }

    /// The PostScript name of the named instance nearest the weight.
    static func faceName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: return "Figtree-Light"
        case .regular: return "Figtree-Regular"
        case .medium: return "Figtree-Medium"
        case .semibold: return "Figtree-SemiBold"
        case .bold: return "Figtree-Bold"
        case .heavy: return "Figtree-ExtraBold"
        default: return "Figtree-Black"
        }
    }

    static let heroFigure = Font.figtree(48, .heavy, relativeTo: .largeTitle).monospacedDigit()
    static let screenTitle = Font.figtree(32, .heavy, relativeTo: .largeTitle).monospacedDigit()
    static let questionTitle = Font.figtree(19, .bold, relativeTo: .title3).monospacedDigit()
    static let questionTitleGuide = Font.figtree(25, .heavy, relativeTo: .title2).monospacedDigit()
    static let rowTitle = Font.figtree(16, .semibold, relativeTo: .body).monospacedDigit()
    static let button = Font.figtree(16, .bold, relativeTo: .body).monospacedDigit()
    static let secondary = Font.figtree(14, .medium, relativeTo: .subheadline).monospacedDigit()
    static let chipLabel = Font.figtree(12, .bold, relativeTo: .caption).monospacedDigit()
}

/// A type role with its font, tracking (em) and line height.
enum PAFont: CaseIterable {
    case heroFigure, screenTitle, questionTitle, questionTitleGuide, rowTitle, button, secondary, chipLabel

    var font: Font {
        switch self {
        case .heroFigure: return .heroFigure
        case .screenTitle: return .screenTitle
        case .questionTitle: return .questionTitle
        case .questionTitleGuide: return .questionTitleGuide
        case .rowTitle: return .rowTitle
        case .button: return .button
        case .secondary: return .secondary
        case .chipLabel: return .chipLabel
        }
    }
    var size: CGFloat {
        switch self {
        case .heroFigure: return 48
        case .screenTitle: return 32
        case .questionTitle: return 19
        case .questionTitleGuide: return 25
        case .rowTitle, .button: return 16
        case .secondary: return 14
        case .chipLabel: return 12
        }
    }
    var tracking: CGFloat {
        switch self {
        case .heroFigure: return -0.03 * 48
        case .screenTitle: return -0.02 * 32
        case .chipLabel: return 0.07 * 12
        default: return 0
        }
    }
    /// Line height in points, or nil to leave the font's own.
    var lineHeight: CGFloat? {
        switch self {
        case .heroFigure: return 52
        case .screenTitle: return 37
        case .questionTitle: return 25
        case .questionTitleGuide: return 31
        case .secondary: return 20
        default: return nil
        }
    }
    var name: String {
        switch self {
        case .heroFigure: return "heroFigure"
        case .screenTitle: return "screenTitle"
        case .questionTitle: return "questionTitle"
        case .questionTitleGuide: return "questionTitleGuide"
        case .rowTitle: return "rowTitle"
        case .button: return "button"
        case .secondary: return "secondary"
        case .chipLabel: return "chipLabel"
        }
    }
}

private struct PAText: ViewModifier {
    let role: PAFont
    @ScaledMetric private var scale: CGFloat = 1
    func body(content: Content) -> some View {
        // Extra line spacing is the role's line height less the font's natural one (about 1.2 em), scaled with the text.
        let extra = role.lineHeight.map { max(0, ($0 - role.size * 1.2) * scale) } ?? 0
        content.font(role.font).tracking(role.tracking * scale).lineSpacing(extra)
    }
}
extension View {
    /// Font, tracking and line spacing of a type role. Colour is the caller's.
    func paText(_ role: PAFont) -> some View { modifier(PAText(role: role)) }
}
