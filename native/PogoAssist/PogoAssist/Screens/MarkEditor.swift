import SwiftUI
import PogoBox

/// The edits made on the Pokémon page (the marks and every chip of the advanced details), kept apart from the box version so the page answers a tap at once.
///
/// A tap changes `wanted`, the row the marks draw from, on the spot. The box is written afterwards, once the taps have stopped for `settle`, as ONE edit built from
/// the latest wanted values of the fields the player touched (`PokemonPage.edit(from:to:touching:)`), diffed against the row as it is saved then: an even number of taps
/// on a mark is no edit and no save, a burst of taps is one save, a field the player did not touch is never written, and at most one save is in flight; taps made
/// during it go as the next one. If a save fails, or the copy or the account is no longer there when it runs, the page goes back to the saved row and says so.
@MainActor final class MarkEditor: ObservableObject {
    /// What the editor reads and does in the app; the app's model behind it (or a stand-in in the tests).
    struct Backing {
        /// The saved copy as it is now.
        var entry: () -> BoxEntry?
        /// The account showing now.
        var account: () -> String?
        /// Writes an edit as a box version and says whether it was saved (it shows its own error when not).
        var save: (BoxMerge.Edit) async -> Bool
        /// Tells the player something the editor decided (a change dropped, a save that would not settle).
        var tell: (String) -> Void
    }

    /// The row the marks and chips draw from while edits are not yet saved (the saved row with the player's taps applied); nil when nothing waits.
    @Published private(set) var wanted: ScanRow?
    private var lastTap = Date.distantPast
    private var saving = false
    /// The fields the player has touched and not yet saved, and the account they were touched in.
    private var touched = Set<PokemonPage.MarkField>()
    private var pendingAccount: String?
    private var backing: Backing?
    /// How long taps must stop before the save starts: a double tap on one mark then saves nothing.
    let settle: TimeInterval

    init(settle: TimeInterval = MarkEditor.launchSettle) { self.settle = settle }

    /// A DEBUG build honours `-uitest-mark-settle <seconds>`, so a UI test can make two taps (which it can only send a few tenths of a second apart) one burst, and can
    /// see a mark drawn before its save could have begun.
    nonisolated static var launchSettle: TimeInterval {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-uitest-mark-settle"), i + 1 < args.count, let t = TimeInterval(args[i + 1]) { return t }
        #endif
        return 0.3
    }

    func apply(_ make: (ScanRow) -> BoxMerge.Edit, _ backing: Backing) {
        guard let saved = backing.entry(), let gm = try? GameMaster.bundled() else { return }
        self.backing = backing
        let base = wanted ?? saved.row
        let edit = make(base)
        if PokemonPage.isNoOp(edit, base) { return }
        var from = saved; from.row = base
        guard let next = PokemonPage.row(applying: edit, to: from, gm: gm) else { return }
        PageTimings.tap()
        if wanted == nil { pendingAccount = backing.account(); touched = [] }
        touched.formUnion(PokemonPage.touched(from: base, to: next))
        wanted = next
        lastTap = Date()
        guard !saving else { return }
        saving = true
        Task { await run() }
    }

    /// Back to the saved row, with nothing waiting; `message` (if any) tells the player why.
    private func giveUp(_ message: String? = nil) {
        wanted = nil; touched = []; pendingAccount = nil
        if let message { backing?.tell(message) }
    }

    private func run() async {
        defer { saving = false }
        var retried = false
        while wanted != nil {
            // Wait until the taps have stopped (a tap during the wait moves the end).
            while true {
                let quiet = settle - Date().timeIntervalSince(lastTap)
                if quiet <= 0 { break }
                try? await Task.sleep(for: .seconds(quiet))
            }
            guard let backing, let target = wanted else { return }
            guard backing.account() == pendingAccount, let saved = backing.entry()?.row else {
                return giveUp("Your mark change was not saved: that Pokémon is no longer in this box.")
            }
            let mine = touched
            let edit = PokemonPage.edit(from: saved, to: target, touching: mine)
            if edit == BoxMerge.Edit() { return giveUp() }   // the taps cancelled out
            touched = []   // taps from here on are for the next save
            guard await backing.save(edit) else { return giveUp() }   // the marks go back to the saved row
            if !touched.isEmpty { retried = false; continue }         // taps came during the save: they go next
            guard let now = backing.entry()?.row, let target = wanted else { return giveUp() }
            if PokemonPage.edit(from: now, to: target, touching: mine) == BoxMerge.Edit() { return giveUp() }   // saved: the shown row is the saved row again
            // Saved, yet the row does not read as wanted: try once more, then say so rather than loop.
            if retried { return giveUp("Your mark change could not be saved. Try tapping it again.") }
            retried = true; touched = mine
        }
    }
}
