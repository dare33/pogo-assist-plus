import SwiftUI

/// Whether the list is moving, for the A-Z index: it shows while the list scrolls and fades a second after it stops (design pass 3, D24). Kept outside the
/// screen's own state so that a scroll does not rebuild the whole screen, only the index.
@MainActor
final class ScrollActivity: ObservableObject {
    @Published private(set) var moving = false
    private var last: CGFloat?
    private var hide: Task<Void, Never>?

    /// The list's top offset changed. The first reading is only where the list starts, not a scroll.
    func offsetChanged(_ y: CGFloat) {
        defer { last = y }
        guard let last, abs(y - last) > 0.5 else { return }
        if !moving { moving = true }
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { self?.moving = false }
        }
    }
}

/// The A-Z index in the right gutter (22 pt wide). The letters are drawn only while the list moves (or the index is being dragged); VoiceOver always has it, as
/// one adjustable "Jump to letter" element, even while the letters are hidden (READBACK Q4). With Reduce Motion on, the letters appear and go without a fade.
struct AZIndex: View {
    @ObservedObject var activity: ScrollActivity
    /// The letters (or CP bands) top to bottom.
    let labels: [String]
    /// A letter's section id, for the letters that have one.
    let present: [String: String]
    /// Every section in order, for the adjustable action and its spoken value.
    let sections: [(id: String, heading: String)]
    @Binding var jumped: String?
    let scrollTo: (String) -> Void
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging = false

    private let rowHeight: CGFloat = 14

    private func jump(to label: String) {
        // A letter with nothing under it goes to the next letter that has something.
        guard let at = labels.firstIndex(of: label), let hit = labels[at...].first(where: { present[$0] != nil }) ?? labels.last(where: { present[$0] != nil }), let id = present[hit] else { return }
        if jumped != id { jumped = id; scrollTo(id) }
    }

    private var shown: Bool { activity.moving || dragging }

    var body: some View {
        letters
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: shown)
            .allowsHitTesting(shown)
            .accessibilityHidden(true)
            .frame(width: 22)
            .overlay { voiceOverElement }
            .padding(.trailing, 1)
            .accessibilityElement(children: .contain)
    }

    private var letters: some View {
        VStack(spacing: 0) {
            ForEach(labels, id: \.self) { l in
                let on = present[l] != nil && present[l] == jumped
                Text(l).font(.figtree(10, .heavy, relativeTo: .caption2)).dynamicTypeSize(.large)
                    .foregroundStyle(on ? accent.onSolid : (present[l] != nil ? accent.ink : Theme.faint.opacity(0.6)))
                    .frame(width: 16, height: rowHeight)
                    .background { if on { Capsule().fill(accent.solid) } }
            }
        }
        .frame(width: 22)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in dragging = true; jump(to: labels[min(max(Int(v.location.y / rowHeight), 0), labels.count - 1)]) }
            .onEnded { _ in dragging = false })
    }

    /// Always present, not drawn: the one element VoiceOver finds, whether or not the letters show.
    private var voiceOverElement: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Jump to letter")
            .accessibilityValue(jumped.flatMap { id in sections.first { $0.id == id }?.heading } ?? "")
            .accessibilityIdentifier("az-jump")
            .accessibilityAdjustableAction { direction in
                let ids = sections.map(\.id)
                let at = jumped.flatMap { ids.firstIndex(of: $0) } ?? -1
                let to = direction == .increment ? min(at + 1, ids.count - 1) : max(at - 1, 0)
                if ids.indices.contains(to) { jumped = ids[to]; scrollTo(ids[to]) }
            }
    }
}
