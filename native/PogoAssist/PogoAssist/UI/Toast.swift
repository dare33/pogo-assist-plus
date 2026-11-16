import SwiftUI

/// "Copied" and the like. `\.showToast` is set by `.toastHost()` (applied once at the root by `themeRoot()`);
/// outside a host it does nothing. The toast rises 16 pt in 0.35 s on cubic-bezier(.2,.8,.2,1) and shows for 1.5 s;
/// with Reduce Motion it only fades.
/// What a toast offers besides its message (pass 2-6, rule 27.8): one action, "Undo", for five seconds.
struct ToastAction {
    let label: String
    /// Runs the action; true when it did something (an Undo that found nothing to undo returns false, and the toast then says nothing more).
    let perform: @MainActor () -> Bool
}

@MainActor
final class ToastPresenter: ObservableObject {
    @Published private(set) var message: String?
    @Published private(set) var action: ToastAction?
    /// The screen that showed the toast (its keeper's identity), whatever the toast is: it goes when that screen disappears, so its Undo never acts on a closed screen's keeper (H10, J6).
    private(set) var owner: ObjectIdentifier?
    private var hide: Task<Void, Never>?

    /// A plain message for 1.5 s, or, with an `action`, for 5 s. The words are announced to VoiceOver either way.
    func show(_ text: String, owner: ObjectIdentifier? = nil, action: ToastAction? = nil) {
        hide?.cancel()
        message = text
        self.action = action
        self.owner = owner
        AccessibilityNotification.Announcement(text).post()
        let seconds = action == nil ? 1.5 : 5.0
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { self?.clear() }
        }
    }

    private func clear() { message = nil; action = nil; owner = nil }

    /// The screen `owner` disappeared: any toast it showed goes at once, a plain message as well as one with an action (another screen's toast stays).
    func dismiss(owner: ObjectIdentifier) {
        guard self.owner == owner else { return }
        hide?.cancel()
        clear()
    }

    /// The action was tapped: it runs, and the toast says "Undone" (for the same screen) when it did something; when it did not, the toast just goes (J9).
    func perform() {
        guard let action else { return }
        let owner = self.owner
        if action.perform() { show("Undone", owner: owner) } else { hide?.cancel(); clear() }
    }
}

private struct ShowToastKey: EnvironmentKey { static let defaultValue: @MainActor (String) -> Void = { _ in } }
private struct DismissToastKey: EnvironmentKey { static let defaultValue: @MainActor (ObjectIdentifier) -> Void = { _ in } }
private struct ShowOwnedToastKey: EnvironmentKey { static let defaultValue: @MainActor (String, ObjectIdentifier, ToastAction?) -> Void = { _, _, _ in } }
extension EnvironmentValues {
    var showToast: @MainActor (String) -> Void {
        get { self[ShowToastKey.self] }
        set { self[ShowToastKey.self] = newValue }
    }
    /// Drops the toast a screen showed (a plain message or one with an action), when that screen disappears.
    var dismissToast: @MainActor (ObjectIdentifier) -> Void {
        get { self[DismissToastKey.self] }
        set { self[DismissToastKey.self] = newValue }
    }
    /// A toast a screen owns (it goes when the screen does): with an Undo (or other) action it stays five seconds, without one 1.5.
    var showOwnedToast: @MainActor (String, ObjectIdentifier, ToastAction?) -> Void {
        get { self[ShowOwnedToastKey.self] }
        set { self[ShowOwnedToastKey.self] = newValue }
    }
}

struct ToastHost: ViewModifier {
    @StateObject private var presenter = ToastPresenter()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.showToast) { [presenter] in presenter.show($0) }
            .environment(\.showOwnedToast) { [presenter] in presenter.show($0, owner: $1, action: $2) }
            .environment(\.dismissToast) { [presenter] in presenter.dismiss(owner: $0) }
            .overlay(alignment: .bottom) {
                if let text = presenter.message {
                    ToastView(text: text, actionLabel: presenter.action?.label, onAction: { presenter.perform() })
                        .padding(.bottom, 110)
                        .allowsHitTesting(presenter.action != nil)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .offset(y: 16).combined(with: .opacity), removal: .opacity))
                        .id(text)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.25) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35), value: presenter.message)
    }
}

extension View {
    func toastHost() -> some View { modifier(ToastHost()) }
}

struct ToastView: View {
    let text: String
    var actionLabel: String? = nil
    var onAction: () -> Void = {}
    var body: some View {
        // VoiceOver reads the toast as one element, the message, with Undo as a custom action (the message is announced when it appears). The button stays for a sighted tap.
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.figtree(16, .bold)).accessibilityHidden(true)
            Text(text).font(.figtree(14, .bold, relativeTo: .subheadline)).lineLimit(2)
            if let actionLabel {
                Button(action: onAction) {
                    Text(actionLabel).font(.figtree(14, .heavy, relativeTo: .subheadline)).underline().frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Theme.bg)
        .padding(.horizontal, 16).padding(.vertical, actionLabel == nil ? 10 : 0)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("toast")
        .modifier(ToastUndoAction(label: actionLabel, perform: onAction))
    }
}

/// The custom action of a toast that has an action ("Undo"); nothing for a plain message.
private struct ToastUndoAction: ViewModifier {
    let label: String?
    let perform: () -> Void
    func body(content: Content) -> some View {
        if let label { content.accessibilityAction(named: label, perform) } else { content }
    }
}
