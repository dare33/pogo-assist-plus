import SwiftUI

/// Takes the player back to Pokémon GO after the Scan screen started a broadcast (repo rule, Greg's decision of 4 Oct 2026): the app opens `pokemongo://` with no path and
/// no parameters, once per started broadcast. It only brings the game to the front; nothing is passed to it and nothing in it is read or changed. Never from the extension.
///
/// When it is asked: the person pressed this app's own start control (the mark button's broadcast picker, also fired by "Scan anyway" on the setup sheet; see `noteStartPressed`)
/// no more than `pressWindow` before the broadcast started, so a broadcast started from Control Centre never counts; a broadcast goes live while the Scan screen is up and showed
/// no scan running (so a scan already running when the screen was opened never counts), the broadcast started in the last `freshSeconds` (a person who switched to the game
/// themselves and comes back later is not thrown back into it), and the app is active again.
/// While the system's broadcast sheet is up the app is inactive, which is why it waits for active (`consider` is called again when the app becomes active).
@MainActor
final class GameOpener: ObservableObject {
    static let url = URL(string: "pokemongo://")!
    static let freshSeconds = 30.0
    /// How long before the broadcast went live the start control may have been pressed (the system's picker, its countdown and the extension's start take a few seconds).
    static let pressWindow = 60.0
    static let failedKey = "game.openFailed"
    static let fallbackLine = "Now switch to Pokémon GO."

    /// The test seam: how the URL is opened, and whether the app is active. In a DEBUG build `-fake-open-game ok|fail` answers instead of calling the system; either way `requests` records what was asked.
    var open: (URL, @escaping (Bool) -> Void) -> Void = { url, done in UIApplication.shared.open(url, options: [:], completionHandler: done) }
    var isActive: () -> Bool = { UIApplication.shared.applicationState == .active }

    /// Every URL this object asked to open: the tests assert exactly one, and exactly `pokemongo://`.
    @Published private(set) var requests: [URL] = []
    /// The last attempt could not open the game (not installed, or refused): the fallback line is shown instead of "We'll take you back".
    @Published private(set) var failed: Bool
    private var openedFor: Int?
    private var pressedAt: Date?

    /// The person pressed the start control of this app's Scan screen (the system picker was triggered from here). Not a start from Control Centre.
    func noteStartPressed() { pressedAt = Date() }

    init() {
        failed = UserDefaults.standard.bool(forKey: Self.failedKey)
        #if DEBUG
        if let mode = UserDefaults.standard.string(forKey: "fake-open-game") {
            let succeeds = mode == "ok"
            open = { _, done in done(succeeds) }
        }
        #endif
    }

    /// The start control was pressed shortly before this broadcast started (a little slack for the two clocks being read apart).
    private func startedFromHere(_ s: BroadcastState) -> Bool {
        guard let p = pressedAt else { return false }
        let lag = s.started.timeIntervalSince(p)
        return lag >= -2 && lag < Self.pressWindow
    }

    /// Whether the broadcast `state` is one to take the person back from, and if so does it (once).
    func consider(_ state: BroadcastState?, screenSawNoScan: Bool) {
        guard screenSawNoScan, let s = state, !s.finished, s.scanId != 0, s.scanId != openedFor,
              Date().timeIntervalSince(s.started) < Self.freshSeconds, startedFromHere(s), isActive() else { return }
        openedFor = s.scanId
        requests.append(Self.url)
        open(Self.url) { [weak self] ok in
            Task { @MainActor in
                self?.failed = !ok
                UserDefaults.standard.set(!ok, forKey: Self.failedKey)
            }
        }
    }
}
