import SwiftUI

/// When the window is wide the tab screens use the width instead of the phone-shaped column. Keyed on the width the tab content
/// has and the text size, nothing else (never the device, the idiom, the hinge or the orientation), so an iPad window and the opened Duo get the same layouts.
/// The functions are pure so the thresholds and counts are unit-tested; every one returns today's value when `wide` is false.
enum WideLayout {
    /// The width from which the tab screens count as wide: the opened Duo turned wide (about 867 pt without its strip) and an iPad 11-inch in portrait (834 pt) are; the Duo turned tall (669), an iPad split-view half and a phone are not.
    static let minWidth: CGFloat = 800
    /// Widest the content gets when wide (`Theme.columnMax` otherwise): room for three Hub tiles or six squad slots in a row.
    static let columnMax: CGFloat = 1040

    static func isWide(_ width: CGFloat) -> Bool { width >= minWidth }

    /// Whether the tab stacks lay out wide: the window is wide and the text is not at an accessibility size. At those sizes every screen keeps
    /// the 640 pt column and its one-to-a-row layouts, as before, so `\.wideLayout` is false there.
    static func lays(wide: Bool, typeSize: DynamicTypeSize) -> Bool { wide && !typeSize.isAccessibilitySize }

    static func column(wide: Bool) -> CGFloat { wide ? columnMax : Theme.columnMax }

    /// Hub tiles per row: three when wide, otherwise two; one at the accessibility text sizes either way.
    static func hubTilesPerRow(wide: Bool, typeSize: DynamicTypeSize) -> Int {
        wide && !typeSize.isAccessibilitySize ? 3 : (typeSize >= .accessibility1 ? 1 : 2)
    }

    /// Squad slot cards per row: otherwise three, and one at the accessibility text sizes. When wide, six for a squad of more than three slots
    /// (Raids, Gym), so its slots are one row; a squad of three (Max, Rocket, PvP) stays three to a row and its cards fill the width.
    static func slotsPerRow(wide: Bool, typeSize: DynamicTypeSize, count: Int) -> Int {
        wide && !typeSize.isAccessibilitySize && count > 3 ? 6 : (typeSize.isAccessibilitySize ? 1 : 3)
    }

    /// Columns of special sets in the Collection: two when wide, otherwise one; one at the accessibility text sizes either way.
    static func collectionColumns(wide: Bool, typeSize: DynamicTypeSize) -> Int {
        wide && !typeSize.isAccessibilitySize ? 2 : 1
    }

    /// Items cut into rows of `per` (the last row may be short).
    static func rows<T>(_ items: [T], per: Int) -> [[T]] {
        guard per > 0 else { return [items] }
        return stride(from: 0, to: items.count, by: per).map { Array(items[$0..<min($0 + per, items.count)]) }
    }
}

private struct WideLayoutKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// The tab stacks lay out wide (`WideLayout.lays`: the window is wide and the text is below the accessibility sizes). Set on the two tab stacks only; a sheet or cover presented from inside them resets it to false, so presentations keep their own layout.
    var wideLayout: Bool {
        get { self[WideLayoutKey.self] }
        set { self[WideLayoutKey.self] = newValue }
    }
}
