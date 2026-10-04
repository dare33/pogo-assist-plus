import SwiftUI

/// "Copied" and the like. `\.showToast` is set by `.toastHost()` (applied once at the root by `themeRoot()`);
/// outside a host it does nothing. The toast rises 16 pt in 0.35 s on cubic-bezier(.2,.8,.2,1) and shows for 1.5 s;
/// with Reduce Motion it only fades.
@MainActor
final class ToastPresenter: ObservableObject {
    @Published private(set) var message: String?
    private var hide: Task<Void, Never>?

    func show(_ text: String) {
        hide?.cancel()
        message = text
        AccessibilityNotification.Announcement(text).post()
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { self?.message = nil }
        }
    }
}

private struct ShowToastKey: EnvironmentKey { static let defaultValue: @MainActor (String) -> Void = { _ in } }
extension EnvironmentValues {
    var showToast: @MainActor (String) -> Void {
        get { self[ShowToastKey.self] }
        set { self[ShowToastKey.self] = newValue }
    }
}

struct ToastHost: ViewModifier {
    @StateObject private var presenter = ToastPresenter()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.showToast) { [presenter] in presenter.show($0) }
            .overlay(alignment: .bottom) {
                if let text = presenter.message {
                    ToastView(text: text)
                        .padding(.bottom, 110)
                        .allowsHitTesting(false)
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
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.figtree(16, .bold))
            Text(text).font(.figtree(14, .bold, relativeTo: .subheadline)).lineLimit(2)
        }
        .foregroundStyle(Theme.bg)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
