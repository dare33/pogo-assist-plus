import Foundation

/// How long the Pokémon page takes to answer a tap, written to the log as "pogo timings" lines beside the engine's own: from the tap to the mark being drawn in its new
/// state, and from the tap to the advice on the page being the one for the edited copy. Main actor only; the first draw or advice after a tap is the one logged.
@MainActor enum PageTimings {
    private static var tapped: Date?
    private static var drawnLogged = true

    static func tap() { tapped = Date(); drawnLogged = false }

    /// The page drew the marks as they now are (called when what it draws changes).
    static func drawn() {
        guard let t = tapped, !drawnLogged else { return }
        drawnLogged = true
        NSLog("pogo timings: tap to mark drawn %.3f s", Date().timeIntervalSince(t))
    }

    /// The page got advice for the edited box (`source` says which: the family's or the whole box's).
    static func advice(_ source: String) {
        guard let t = tapped else { return }
        NSLog("pogo timings: tap to advice on the page (%@) %.3f s", source, Date().timeIntervalSince(t))
        if source == "whole box" { tapped = nil }
    }
}
