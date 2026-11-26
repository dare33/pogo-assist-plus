import SwiftUI

/// Sets the notification delegate and the "End scan" category as the process launches, before any screen exists, so a cold launch from the notification's action is handled.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationActions.install()
        return true
    }
}

/// Reports the size of the screen the window is on, and whether it is an iPad idiom. `UIScreen.main` is not used: on the foldable
/// iPhone Duo it keeps reporting the outer screen after the phone is opened, while the window scene's screen is right in every posture
/// (and a window on an external display is on another screen than `UIScreen.main` names).
struct ScreenReader: UIViewRepresentable {
    var report: (CGSize, Bool) -> Void

    final class ReaderView: UIView {
        var report: (CGSize, Bool) -> Void = { _, _ in }
        override func didMoveToWindow() { super.didMoveToWindow(); read() }
        // The window relays out when the Duo is folded or opened, so this keeps reporting while the app runs.
        override func layoutSubviews() { super.layoutSubviews(); read() }
        private func read() {
            guard let size = window?.windowScene?.screen.bounds.size else { return }
            // The scene's traits, not this view's own, which can lag a move between screens.
            let pad = window?.windowScene?.traitCollection.userInterfaceIdiom == .pad
            // Not inside the layout pass: the report changes SwiftUI state.
            DispatchQueue.main.async { [report] in report(size, pad) }
        }
    }

    func makeUIView(context: Context) -> ReaderView {
        let v = ReaderView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        v.report = report
        return v
    }
    func updateUIView(_ v: ReaderView, context: Context) { v.report = report }
}

extension View {
    /// Keeps `report` told of the window's screen. A full-screen cover takes the view that presented it out of the window, so each cover
    /// that has the model attaches this too, or a fold while it is up would not reach the model until it closes.
    func reportsScreen(_ report: @escaping (CGSize, Bool) -> Void) -> some View { background(ScreenReader(report: report)) }
    func reportsScreen(to model: AppModel) -> some View { reportsScreen { model.screenChanged(size: $0, isPad: $1) } }
}

/// Holds the app back until the screen is known, because the model restores its paging at creation and that depends on the screen.
private struct ScreenGate<Content: View>: View {
    @ViewBuilder var content: (CGSize, Bool) -> Content
    @AppStorage(PrefKey.appearance) private var appearanceRaw = Appearance.auto.rawValue
    @State private var screen: (size: CGSize, isPad: Bool)?

    var body: some View {
        ZStack {
            if let screen { content(screen.size, screen.isPad) } else { Theme.bg.ignoresSafeArea() }
        }
        // The reader fills the root view's area (the safe-area region), so it is laid out again (and reads again) whenever that area changes: a fold, an unfold, a resized window.
        .reportsScreen { size, pad in
            if screen?.size != size || screen?.isPad != pad { screen = (size, pad) }
        }
        // The stored light/dark choice reaches the windows as the placeholder appears, as it did when RootView was first on screen.
        // Not `themeRoot()`: the content applies its own, and a second one here would add a second toast host.
        .onAppear { Appearance.applyToWindows(appearanceRaw) }
    }
}

@main
struct PogoAssistApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CommandLine.arguments.contains("-ui-gallery") { ScreenGate { ComponentGallery(screenSize: $0, isPad: $1) } }
            else if CommandLine.arguments.contains("-design-gallery") { DesignGallery() }
            else { ScreenGate { RootView(screenSize: $0, isPad: $1) } }
            #else
            ScreenGate { RootView(screenSize: $0, isPad: $1) }
            #endif
        }
    }
}
