import SwiftUI

/// Sets the notification delegate and the "Finish scan" category as the process launches, before any screen exists, so a cold launch from the notification's action is handled.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationActions.install()
        return true
    }
}

@main
struct PogoAssistApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup { RootView() }
    }
}
