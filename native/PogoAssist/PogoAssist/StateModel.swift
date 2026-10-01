import SwiftUI

/// Re-reads the extension's state file on its Darwin notification and on a 1 s timer while the app
/// is in the foreground.
@MainActor
final class StateModel: ObservableObject {
    @Published var state = BroadcastState()
    @Published var hasState = false
    private var timer: Timer?

    init() {
        reload()
        // The extension posts this after each write; the callback must not capture, so the model
        // travels as the observer pointer.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer = observer else { return }
            let model = Unmanaged<StateModel>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { model.reload() }
        }, SharedStore.notificationName as CFString, nil, .deliverImmediately)
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func stopTimer() { timer?.invalidate(); timer = nil }

    func reload() {
        if let s = SharedStore.read() { state = s; hasState = true } else { state = BroadcastState(); hasState = false }
    }

    func clear() {
        SharedStore.clear()
        reload()
    }
}
