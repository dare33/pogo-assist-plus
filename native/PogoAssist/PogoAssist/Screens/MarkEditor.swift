import SwiftUI
import PogoBox

/// The edits made on the Pokémon page (the marks and every chip of the advanced details), kept apart from the box version so the page answers a tap at once.
///
/// A tap changes `wanted`, the row the marks draw from, on the spot. The box is written afterwards, once the taps have stopped for `settle`, as ONE edit built from
/// the latest wanted values (`PokemonPage.edit(from:to:)`): an even number of taps on a mark is no edit and no save, and a burst of taps is one save. At most one save is
/// in flight; taps made during it wait and go as the next one, always built from the row as it is then, so nothing is replayed stale. If a save fails the page goes back
/// to the saved row and shows the error.
@MainActor final class MarkEditor: ObservableObject {
    /// The row the marks and chips draw from while edits are not yet saved (the saved row with the player's taps applied); nil when nothing waits.
    @Published private(set) var wanted: ScanRow?
    private var lastTap = Date.distantPast
    private var saving = false
    /// How long taps must stop before the save starts: a double tap on one mark then saves nothing.
    let settle: TimeInterval
    private var entry: () -> BoxEntry? = { nil }
    private var save: (BoxMerge.Edit) async -> Bool = { _ in false }

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

    /// `entry` reads the saved copy as it is now; `save` writes an edit as a box version and says whether it was saved (it shows its own error when not).
    func apply(_ make: (ScanRow) -> BoxMerge.Edit, entry: @escaping () -> BoxEntry?, save: @escaping (BoxMerge.Edit) async -> Bool) {
        guard let saved = entry(), let gm = try? GameMaster.bundled() else { return }
        self.entry = entry; self.save = save
        let base = wanted ?? saved.row
        let edit = make(base)
        if PokemonPage.isNoOp(edit, base) { return }
        var from = saved; from.row = base
        guard let next = PokemonPage.row(applying: edit, to: from, gm: gm) else { return }
        PageTimings.tap()
        wanted = next
        lastTap = Date()
        guard !saving else { return }
        saving = true
        Task { await run() }
    }

    private func run() async {
        defer { saving = false }
        while wanted != nil {
            // Wait until the taps have stopped (a tap during the wait moves the end).
            while true {
                let quiet = settle - Date().timeIntervalSince(lastTap)
                if quiet <= 0 { break }
                try? await Task.sleep(for: .seconds(quiet))
            }
            guard let target = wanted, let saved = entry()?.row else { wanted = nil; return }
            let edit = PokemonPage.edit(from: saved, to: target)
            if edit == BoxMerge.Edit() { wanted = nil; return }   // the taps cancelled out
            guard await save(edit) else { wanted = nil; return }   // the marks go back to the saved row
            if let w = wanted, let now = entry()?.row, PokemonPage.sameMarks(w, now) { wanted = nil; return }
        }
    }
}
