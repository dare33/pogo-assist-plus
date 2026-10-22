import SwiftUI
import UIKit

// The ranking switch and its parts (design handoff of 22 Oct 2026): a segmented switch in the style of the Mega
// form switch, the round "i" button, the explainer card, and the labelled switch that puts them together. The switch
// is one app-wide preference (PrefKey.ranking); the "i" open state belongs to the screen that shows it.

// MARK: SegmentedSwitch

/// Sizes of a SegmentedSwitch. The League control uses the defaults (15/700, 38 pt segments); `.compact` is the ranking switch.
struct SegmentedSwitchMetrics {
    var fontSize: CGFloat = 15
    var segmentMinHeight: CGFloat = 38
    var horizontalPadding: CGFloat = 0
    var trackPadding: CGFloat = 4
    /// Segments share the width equally; false sizes the switch to its titles.
    var fillsWidth = true
    static let league = SegmentedSwitchMetrics()
    static let compact = SegmentedSwitchMetrics(fontSize: 12, segmentMinHeight: 26, horizontalPadding: 9, fillsWidth: false)
}

/// Two or more segments on a `Theme.off` capsule track, the selected one on `Theme.surface`. The League control
/// uses the defaults (15/700, 38 pt segments, a dot per segment); `.compact` is the ranking switch's size.
/// Drawn sizes stay as designed; each segment (and the whole switch) is still at least 44 pt tall to hit.
struct SegmentedSwitch<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        /// An 8 pt dot before the title.
        var dot: Color? = nil
        /// The title's colour when selected; `Theme.ink` when nil.
        var selectedInk: Color? = nil
        var identifier: String? = nil
        var id: Value { value }
    }
    let segments: [Segment]
    @Binding var selection: Value
    var metrics = SegmentedSwitchMetrics.league
    /// The accessibility label of the whole switch.
    let label: String
    var identifier: String? = nil
    /// One adjustable element (VoiceOver swipes up and down) instead of a row of buttons.
    var adjustable = false
    /// Keep each title on one line (the caller falls back to a layout that fits when it cannot).
    var singleLine = false

    private let hit: CGFloat = 44

    var body: some View {
        let track = HStack(spacing: 0) { ForEach(segments) { segment($0) } }
            .padding(metrics.trackPadding)
            .background(Theme.off, in: Capsule())
            .frame(minHeight: hit)
        if adjustable {
            track
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(segments.first { $0.value == selection }?.title ?? "")
                .accessibilityAdjustableAction(step)
                .accessibilityIdentifier(identifier ?? "")
        } else {
            track
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier ?? "")
        }
    }

    private func step(_ direction: AccessibilityAdjustmentDirection) {
        let values = segments.map(\.value)
        guard let i = values.firstIndex(of: selection) else { return }
        selection = Self.stepped(in: values, from: i, by: direction)
    }

    /// The value one step from index `i` (VoiceOver increment / decrement), staying put at either end. Pure, so it can be
    /// unit-tested once the app has a unit-test target (it has none yet).
    static func stepped(in values: [Value], from i: Int, by direction: AccessibilityAdjustmentDirection) -> Value {
        switch direction {
        case .increment: return i + 1 < values.count ? values[i + 1] : values[i]
        case .decrement: return i > 0 ? values[i - 1] : values[i]
        @unknown default: return values[i]
        }
    }

    private func segment(_ s: Segment) -> some View {
        let selected = s.value == selection
        // The tappable area grows to `hit` through negative vertical padding on the drawn segment's frame, so the
        // track keeps the designed height.
        let extra = max(0, hit - metrics.segmentMinHeight)
        return Button { selection = s.value } label: {
            HStack(spacing: 8) {
                if let dot = s.dot { Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true) }
                Text(s.title).font(.figtree(metrics.fontSize, .bold, relativeTo: .subheadline))
                    // Wrapped (very large text): shrink a title onto one line rather than break it mid-word ("Defau/lt").
                    .lineLimit(1)
                    .minimumScaleFactor(singleLine ? 1 : 0.5)
                    .fixedSize(horizontal: singleLine, vertical: true)
            }
            .foregroundStyle(selected ? (s.selectedInk ?? Theme.ink) : Theme.ink)
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(maxWidth: metrics.fillsWidth ? .infinity : nil, minHeight: metrics.segmentMinHeight)
            .background(selected ? Theme.surface : Color.clear, in: Capsule())
            .padding(.vertical, extra / 2)
            .contentShape(Rectangle())
            .padding(.vertical, -extra / 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(s.identifier ?? "")
    }
}

// MARK: InfoButton

/// The round "i": closed it is `Theme.off` with muted ink, open it is the accent's solid with its on-solid ink.
/// Toggles `isOpen`; the caller shows the text it opens.
struct InfoButton: View {
    @Binding var isOpen: Bool
    /// The circle's diameter at the default text size; it scales with the glyph's text style.
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 26
    var label = "About ranking"
    var identifier: String? = nil
    @Environment(\.accent) private var accent

    init(isOpen: Binding<Bool>, size: CGFloat = 26, label: String = "About ranking", identifier: String? = nil) {
        _isOpen = isOpen
        _size = ScaledMetric(wrappedValue: size, relativeTo: .footnote)
        self.label = label
        self.identifier = identifier
    }

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOpen.toggle() } } label: {
            Text("i").font(Self.glyph)
                .foregroundStyle(isOpen ? accent.onSolid : Theme.muted)
                .frame(width: size, height: size)
                .background(Circle().fill(isOpen ? accent.solid : Theme.off))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .accessibilityIdentifier(identifier ?? "")
    }

    /// Georgia bold italic 13 (the design's 800); the system serif italic where Georgia is not installed.
    private static var glyph: Font {
        if UIFont(name: "Georgia-BoldItalic", size: 13) != nil { return .custom("Georgia-BoldItalic", size: 13, relativeTo: .footnote) }
        return .system(.footnote, design: .serif).weight(.heavy).italic()
    }
}

// MARK: RankingSwitch

/// RANKING, the Default | Pogo Assist switch (the one global preference) and the "i" that the caller's `infoOpen`
/// shows `RankingExplainer` for. It hugs its content (the caller places it). Where the row no longer fits (large text)
/// the label goes above the switch and the "i", which stay together in one row.
struct RankingSwitch: View {
    @Binding var infoOpen: Bool
    /// The switch's accessibility identifier; the "i" is "<identifier>-info".
    var identifier = "ranking"
    /// False hides "RANKING" (the Leagues panel header names the switch already).
    var showsCaption = true
    @AppStorage(PrefKey.ranking) private var raw = Ranking.default.rawValue

    private var selection: Binding<Ranking> {
        Binding(get: { Ranking(rawValue: raw) ?? .default }, set: { raw = $0.rawValue })
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                caption
                control(singleLine: true)
                info
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 0) {
                caption
                HStack(spacing: 8) { control(singleLine: false); info }
            }
        }
    }

    @ViewBuilder private var caption: some View {
        if showsCaption {
            Text("RANKING").font(.figtree(10, .heavy, relativeTo: .caption2)).tracking(0.06 * 10)
                .foregroundStyle(Theme.faint)
                .accessibilityHidden(true)
        }
    }

    private func control(singleLine: Bool) -> some View {
        SegmentedSwitch(
            segments: Ranking.allCases.map { .init(value: $0, title: $0.title) },
            selection: selection, metrics: .compact, label: "Ranking",
            identifier: identifier, adjustable: true, singleLine: singleLine)
    }

    private var info: some View { InfoButton(isOpen: $infoOpen, identifier: "\(identifier)-info") }
}

// MARK: RankingExplainer

/// The card the "i" opens. Wording checked against src/leagues.js (pokeGeniePick, chooseMember).
struct RankingExplainer: View {
    var identifier = "ranking-explainer"
    @Environment(\.accent) private var accent

    var body: some View {
        // P1 describes pokeGeniePick (iv.pct); P2 describes chooseMember (rankPct), both in src/leagues.js.
        // "within 3 points" is CLOSE_SCORE in src/leagues.js and must change with it.
        VStack(alignment: .leading, spacing: 8) {
            Text("Default").bold().foregroundStyle(accent.ink)
                + Text(" follows Poke Genie. From a Poke Genie export it uses that export's own pick. Otherwise, in Great and Ultra League, it takes the family member for which this copy's stat product is the highest share of the best possible under the CP cap, preferring species PvPoke ranks. In Master League, or when the IVs are not known, it takes the strongest species.")
            Text("Pogo Assist").bold().foregroundStyle(accent.ink)
                + Text(" weighs the species first. It starts from the member with the best PvPoke score and moves to a weaker one only when that one is within 3 points of the best and this copy's IV rank (out of 4,096 combinations) is higher for it.")
            Text("Both use PvPoke's rankings and this copy's IVs, so they often agree. The choice applies everywhere in the app.")
                .foregroundStyle(Theme.muted)
        }
        .font(.figtree(13, .medium, relativeTo: .footnote))
        .foregroundStyle(Theme.ink)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
