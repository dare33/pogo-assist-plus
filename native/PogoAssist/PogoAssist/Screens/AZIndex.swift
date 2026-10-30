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

/// Scrolls the list for the A-Z index, at most once every `gap` while a finger is dragging down the letters, always with the latest letter. Each jump lays out a
/// screenful of new rows (tens of milliseconds), so a drag that crossed ten letters in a quarter of a second used to queue ten of them and freeze the list; now the
/// letter that is lit follows the finger at once and the list follows at the pace it can keep up with. The first jump of a touch (a tap) goes at once, and the last
/// letter is always scrolled to when the finger lifts.
@MainActor
final class JumpThrottle {
    static let gap: TimeInterval = 0.07
    private var last = Date.distantPast
    private var scrolled: String?
    private var pending: String?
    private var timer: Task<Void, Never>?

    /// Asks for a jump to `id`; `scroll` does it.
    func request(_ id: String, scroll: @escaping (String) -> Void) {
        pending = id
        let wait = Self.gap - Date().timeIntervalSince(last)
        if wait <= 0 { flush(scroll) }
        else if timer == nil {
            timer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                if !Task.isCancelled { self?.flush(scroll) }
            }
        }
    }

    /// Scrolls to the latest letter asked for, if the list is not already there.
    func flush(_ scroll: (String) -> Void) {
        timer?.cancel(); timer = nil
        guard let id = pending else { return }
        pending = nil
        if scrolled != id { scrolled = id; last = Date(); scroll(id) }
    }

    /// The finger lifted: the last letter is scrolled to, and the next touch starts afresh (the list may have been scrolled elsewhere meanwhile).
    func finish(_ scroll: (String) -> Void) { flush(scroll); scrolled = nil; last = .distantPast }
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
    let scrollTo: (String) -> Void
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// True while a finger is on the letters. A gesture state, so a drag the system cancels (a call, a gesture that takes over) puts it back too.
    @GestureState private var dragging = false
    /// The letter the finger is on now: a drag that comes back to a letter after the list was scrolled elsewhere jumps again.
    @State private var dragLetter: String?
    /// The section the list was last sent to, lit in the index. Held here, not in the list's screen: a change to it must rebuild only the letters, not every row on the list.
    @State private var jumped: String?
    @State private var throttle = JumpThrottle()

    private let rowHeight: CGFloat = 14

    private func jump(to label: String) {
        // A letter with nothing under it goes to the next letter that has something.
        guard let at = labels.firstIndex(of: label), let hit = labels[at...].first(where: { present[$0] != nil }) ?? labels.last(where: { present[$0] != nil }), let id = present[hit] else { return }
        if dragLetter != hit { dragLetter = hit; jumped = id; throttle.request(id, scroll: scrollTo) }
    }

    /// The finger lifted: the list goes to the last letter it was asked for.
    private func finishDrag() { throttle.finish(scrollTo); dragLetter = nil }

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
            .onChange(of: dragging) { _, now in if !now { finishDrag() } }   // also when the system cancelled the drag, so the next touch starts afresh
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
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { v in jump(to: labels[min(max(Int(v.location.y / rowHeight), 0), labels.count - 1)]) }
            .onEnded { _ in finishDrag() })
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
