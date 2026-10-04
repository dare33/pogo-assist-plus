import SwiftUI

// The shared components of UI v1 (design handoff, "Shared components"), part one: Panel, InsetRow, Chip,
// PillButton, IconButton. Question card, search strip, bars, monogram and tab bar are in the files beside this one.
// Nothing here has a fixed height on text: rows and buttons use minimum heights so Dynamic Type can grow them.

// MARK: Panel

enum PanelTint { case accent, green, orange }

/// A rounded panel on the surface colour (radius 28, light-mode shadow). With `tint:` it is an accent-tint,
/// green or orange panel instead (no shadow). `padding: 0` gives a clipped container for InsetRows.
struct Panel<Content: View>: View {
    var tint: PanelTint? = nil
    var padding: CGFloat = 18
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content
    @Environment(\.accent) private var accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .clipShape(shape)
            .modifier(ShadowIf(on: tint == nil))
    }

    private var fill: Color {
        switch tint {
        case nil: return Theme.surface
        case .accent: return accent.tint
        case .green: return Theme.greenTint
        case .orange: return Theme.orangeTint
        }
    }
}

private struct ShadowIf: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { if on { content.panelShadow() } else { content } }
}

// MARK: InsetRow

/// A row in a panel: optional icon well, title, optional sub-line, a trailing value and/or chevron, and a
/// separator inset to the text (pass `separator: false` on the last row). With `action` the whole row is a button.
struct InsetRow: View {
    let title: String
    var sub: String? = nil
    /// SF Symbol in a 34 pt well.
    var icon: String? = nil
    var iconBackground: Color = Theme.off
    var iconInk: Color = Theme.muted
    var value: String? = nil
    var showsChevron = false
    var separator = true
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { row }.buttonStyle(PressStyle())
        } else {
            row.accessibilityElement(children: .combine)
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.figtree(17, .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(iconInk)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).paText(.rowTitle).foregroundStyle(Theme.ink)
                if let sub { Text(sub).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value { Text(value).font(.figtree(16, .bold)).monospacedDigit().foregroundStyle(Theme.muted) }
            if showsChevron { Image(systemName: "chevron.right").font(.figtree(14, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if separator { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, icon == nil ? 16 : 62) }
        }
    }
}

/// Dims a button a little while it is pressed; used where the stock style would add its own tint.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: Chip

enum ChipTone { case accent, orange, green, match, change, copies, neutral }

/// A tinted label. `.tag` (radius 10) is for state labels such as a tier or a cost; `.pill` is the 36 pt filter chip.
/// `isSelected` (pill only) fills it with the tone's solid colour. State colours only: never use it as a button
/// substitute for PillButton.
struct Chip: View {
    enum Shape { case tag, pill }
    let text: String
    var tone: ChipTone = .accent
    var shape: Shape = .tag
    var caps = false
    var isSelected = false
    @Environment(\.accent) private var accent

    var body: some View {
        let label = Text(caps ? text.uppercased() : text)
            .font(shape == .pill ? .figtree(14, .bold, relativeTo: .subheadline) : .chipLabel)
            .tracking(caps ? 0.07 * 12 : 0)
            .foregroundStyle(isSelected ? onSolid : ink)
            .padding(.horizontal, shape == .pill ? 14 : 8)
            .padding(.vertical, shape == .pill ? 0 : 4)
            .frame(minHeight: shape == .pill ? 36 : nil)
        switch shape {
        case .tag: label.background(isSelected ? solid : tint, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        case .pill: label.background(isSelected ? solid : tint, in: Capsule())
        }
    }

    private var tint: Color {
        switch tone {
        case .accent: return accent.tint
        case .orange: return Theme.orangeTint
        case .green: return Theme.greenTint
        case .match: return Theme.matchTint
        case .change: return Theme.changeTint
        case .copies: return Theme.copiesTint
        case .neutral: return Theme.off
        }
    }
    private var ink: Color {
        switch tone {
        case .accent: return accent.ink
        case .orange: return Theme.orangeInk
        case .green: return Theme.greenInk
        case .match: return Theme.matchInk
        case .change: return Theme.changeInk
        case .copies: return Theme.copiesInk
        case .neutral: return Theme.muted
        }
    }
    private var solid: Color {
        switch tone {
        case .accent: return accent.solid
        case .orange: return Theme.orange
        case .green: return Theme.green
        case .match: return Theme.match
        case .change: return Theme.change
        case .copies: return Theme.copies
        case .neutral: return Theme.muted
        }
    }
    private var onSolid: Color { tone == .accent ? accent.onSolid : Theme.bg }
}

// MARK: PillButton

enum PillStyle { case filled, tint, plain }

/// A full-radius button, 46 to 56 pt tall (grows with Dynamic Type). `.filled` (accent) goes only on the most
/// likely answer and never on a destructive one: `isDestructive` is honoured on `.tint` and `.plain` only.
struct PillButton: View {
    let title: String
    var systemImage: String? = nil
    var style: PillStyle = .tint
    var height: CGFloat = 48
    var fullWidth = true
    var isDestructive = false
    var action: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, systemImage: String? = nil, style: PillStyle = .tint, height: CGFloat = 48, fullWidth: Bool = true, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.style = style
        self.height = min(max(height, 46), 56); self.fullWidth = fullWidth
        self.isDestructive = isDestructive && style != .filled; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.figtree(15, .bold)).accessibilityHidden(true) }
                Text(title).font(.button).multilineTextAlignment(.center)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private var fill: Color {
        guard enabled else { return Theme.off }
        switch style {
        case .filled: return accent.solid
        case .tint: return accent.tint
        case .plain: return Theme.surface
        }
    }
    private var ink: Color {
        guard enabled else { return Theme.faint }
        if isDestructive { return Theme.red }
        switch style {
        case .filled: return accent.onSolid
        case .tint, .plain: return accent.ink
        }
    }
}

// MARK: IconButton

enum IconButtonKind {
    /// Green tint: done, ignore it.
    case done
    /// Accent tint: add it.
    case add
    /// Surface 2: any other action.
    case neutral
    /// Surface with the panel shadow, 40 pt: the circles in a screen header (back, more).
    case floating
}

/// A 38 pt circle (40 for `.floating`) with a 44 pt hit area. `label` is its accessibility label.
struct IconButton: View {
    let systemImage: String
    var kind: IconButtonKind = .neutral
    let label: String
    var action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) { face }
            .buttonStyle(PressStyle())
            .accessibilityLabel(label)
    }

    /// The circle without the button, for use as a Menu's label.
    var face: some View {
        let d: CGFloat = kind == .floating ? 40 : 38
        return Image(systemName: systemImage)
            .font(.figtree(kind == .floating ? 18 : 16, .bold))
            .foregroundStyle(ink)
            .frame(width: d, height: d)
            .background(Circle().fill(fill))
            .modifier(ShadowIf(on: kind == .floating))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    private var fill: Color {
        switch kind {
        case .done: return Theme.greenTint
        case .add: return accent.tint
        case .neutral: return Theme.surface2
        case .floating: return Theme.surface
        }
    }
    private var ink: Color {
        switch kind {
        case .done: return Theme.greenInk
        case .add: return accent.ink
        case .neutral, .floating: return Theme.ink
        }
    }
}
