import SwiftUI

/// Whether the list is moving, for the A-Z index: it shows while the list scrolls and fades a second after it stops (design pass 3, D24). Kept outside the
/// screen's own state so that a scroll does not rebuild the whole screen, only the index.
@MainActor
final class ScrollActivity: ObservableObject {
    @Published private(set) var moving = false
    private var last: CGFloat?
    private var lastMove = Date.distantPast
    private var timer: Task<Void, Never>?

    /// The list's top offset changed. The first reading is only where the list starts, not a scroll. One timer task runs while the list moves and ends a second after
    /// the last change; a change only stamps the time (no task per frame).
    func offsetChanged(_ y: CGFloat) {
        defer { last = y }
        guard let last, abs(y - last) > 0.5 else { return }
        lastMove = Date()
        if !moving { moving = true }
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while let self, !Task.isCancelled {
                let left = 1.0 - Date().timeIntervalSince(self.lastMove)
                if left <= 0 { break }
                try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000) + 20_000_000)
            }
            self?.moving = false
            self?.timer = nil
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
    /// The letters are drawn only when the list is long enough to want them (three sections or more, no search); the VoiceOver element is always there.
    var lettersShown = true
    @Binding var jumped: String?
    let scrollTo: (String) -> Void
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging = false
    /// The letter the finger is on now: a drag that comes back to a letter after the list was scrolled elsewhere jumps again.
    @State private var dragLetter: String?

    private let rowHeight: CGFloat = 14

    private func jump(to label: String) {
        // A letter with nothing under it goes to the next letter that has something.
        guard let at = labels.firstIndex(of: label), let hit = labels[at...].first(where: { present[$0] != nil }) ?? labels.last(where: { present[$0] != nil }), let id = present[hit] else { return }
        if dragLetter != hit { dragLetter = hit; jumped = id; scrollTo(id) }
    }

    private var shown: Bool { lettersShown && (activity.moving || dragging) }

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
            .onEnded { _ in dragging = false; dragLetter = nil })
    }

    /// Always present, not drawn: the one element VoiceOver finds, whether or not the letters show.
    private var voiceOverElement: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Jump to letter")
            .accessibilityValue(sections.isEmpty ? "No letters" : (jumped.flatMap { id in sections.first { $0.id == id }?.heading } ?? ""))
            .accessibilityIdentifier("az-jump")
            .accessibilityAdjustableAction { direction in
                let ids = sections.map(\.id)
                let at = jumped.flatMap { ids.firstIndex(of: $0) } ?? -1
                let to = direction == .increment ? min(at + 1, ids.count - 1) : max(at - 1, 0)
                if ids.indices.contains(to) { jumped = ids[to]; scrollTo(ids[to]) }
            }
    }
}
