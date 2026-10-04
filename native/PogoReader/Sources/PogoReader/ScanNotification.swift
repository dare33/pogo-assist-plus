import Foundation

/// The local notifications of a command scan, built in one place for both the broadcast extension and the app (the app posts the same one when it sees the event and the
/// extension's notification was not delivered). Plain text, tested in the package; posting is the app's and the extension's job. Nothing here touches the network.
public struct ScanNotification: Equatable {
    public var identifier: String
    /// The scan this is about (its start time in whole seconds, `BroadcastState.scanId`): in the identifier, so one scan's event never replaces or hides another's, and in the
    /// notification's user info, so its "End scan" action can only finish THAT scan.
    public var scanId: Int
    public var title: String
    public var body: String
    /// Notifications of a pause carry the "End scan" action.
    public var offersFinish: Bool

    public static let finishActionID = "pogo.finish"
    /// The pause notification's action button ("End scan"); the in-app control is "Finish now".
    public static let finishActionTitle = "End scan"
    public static let pausedCategoryID = "pogo.scan.paused"
    /// Every pause notification's identifier starts with this (`paused`), so they can be found and removed.
    public static let pausedIdentifierPrefix = "pogo.scan.paused."

    /// Whether a delivered or pending notification is a pause notification of `scan` (of any scan when nil): the ones removed when the scan resumes or finishes and when a new scan starts.
    public static func isPause(_ identifier: String, scan: Int? = nil) -> Bool {
        guard identifier.hasPrefix(pausedIdentifierPrefix) else { return false }
        guard let scan else { return true }
        return identifier.hasPrefix("\(pausedIdentifierPrefix)\(scan).")
    }

    /// (A "End scan" request is judged by `finishRequestVerdict` below: this scan's and paused, honoured; this scan's and not paused, kept for a short grace; anything else dropped.)
    public enum FinishRequestVerdict: Equatable { case honour, keep, drop }
    /// How long a request for the running scan waits when the scan is momentarily not paused (a pause that resumed and paused again on the same stall within the end wait must not lose the
    /// tap). Longer than the end wait (6 periods), far shorter than a pause.
    public static let finishRequestGraceSeconds = 20.0
    /// What the extension does with a pending request: `honour` (this scan, paused), `keep` (this scan, not paused right now, and the request is younger than the grace), or `drop` (another
    /// scan's, or too old: an old notification's tap never ends a later pause).
    public static func finishRequestVerdict(asked: Int, runningScan: Int, paused: Bool, ageSeconds: Double) -> FinishRequestVerdict {
        guard asked == runningScan else { return .drop }
        if paused { return .honour }
        return ageSeconds >= 0 && ageSeconds <= finishRequestGraceSeconds ? .keep : .drop
    }

    /// A duration as the notification and the Scan screen say it: a whole number of minutes in minutes ("2 minutes"), otherwise seconds rounded to the nearest 10 ("90 seconds"), and
    /// "less than 10 seconds" at the bottom.
    public static func durationText(_ seconds: Double) -> String {
        let r = (max(0, seconds) / 10).rounded() * 10
        if r < 10 { return "less than 10 seconds" }
        if r.truncatingRemainder(dividingBy: 60) == 0 { let m = Int(r / 60); return m == 1 ? "1 minute" : "\(m) minutes" }
        return "\(Int(r)) seconds"
    }
    /// The remaining time as the notification says it (`durationText`); nil means the whole pause window.
    public static func limitText(seconds: Double?) -> String { seconds.map(durationText) ?? pauseLimitText }

    /// How the time limit reads in the notification and on the Scan screen ("90 seconds"), from the one constant.
    public static var pauseLimitText: String { durationText(ScanEndDecision.pauseTimeoutSeconds) }

    private static func last(_ name: String?, _ cp: Int?) -> String? {
        let n = (name?.isEmpty == false) ? name : nil
        switch (n, cp) {
        case let (n?, c?): return "\(n) CP \(c)"
        case let (n?, nil): return n
        case let (nil, c?): return "CP \(c)"
        default: return nil
        }
    }

    /// The smallest command size that covers `remaining` Pokémon (the largest when none does), from the sizes the app wrote: "Pogo scan <size>".
    public static func commandName(covering remaining: Int, sizes: [Int]) -> String? {
        guard !sizes.isEmpty else { return nil }
        let size = sizes.sorted().first { $0 >= remaining } ?? sizes.max()!
        return "Pogo scan \(size)"
    }

    /// The scan ended by itself: "<N> read, last <name> CP <cp>. If the command is still tapping, say "Go to sleep". Open Pogo Assist for what to do next." It does not claim to know
    /// where to continue from: the app's review says that.
    public static func stopped(scan: Int, event: Int, read: Int, lastName: String?, lastCP: Int?) -> ScanNotification {
        let last = Self.last(lastName, lastCP).map { ", last \($0)" } ?? ""
        return ScanNotification(identifier: "pogo.scan.stopped.\(scan).\(event)", scanId: scan, title: "Scan stopped",
                                body: "\(read) read\(last). If the command is still tapping, say \"Go to sleep\". Open Pogo Assist for what to do next.", offersFinish: false)
    }

    /// The scan paused at a card that is not clearly the end: "Paused at <name> CP <cp>: <N> of <M> read. Reopen its appraisal to carry on, or say "Pogo scan <size>" if the taps have
    /// stopped. It finishes by itself in 90 seconds if no new Pokémon is read." (size: the smallest covering M - N). With no count: "…<N> read. If that was not your last Pokémon, reopen its appraisal…".
    public static func paused(scan: Int, event: Int, read: Int, storageCount: Int?, eggCount: Int? = nil, lastName: String?, lastCP: Int?, sizes: [Int], limitSeconds: Double? = nil) -> ScanNotification {
        let at = Self.last(lastName, lastCP).map { "Paused at \($0): " } ?? "Paused: "
        let body: String
        if let shown = storageCount, shown > 0 {
            // M: the Pokémon expected, the game's count less the eggs the person typed; with no egg count, the count as shown.
            let m = StorageCountRules.expected(count: shown, eggs: eggCount) ?? shown
            let command = commandName(covering: max(1, m - read), sizes: sizes).map { "say \"\($0)\"" } ?? "say the command again"
            body = "\(at)\(read) of about \(m) read. Reopen its appraisal to carry on, or \(command) if the taps have stopped. It finishes by itself in \(limitText(seconds: limitSeconds)) if no new Pokémon is read."
        } else {
            body = "\(at)\(read) read. If that was not your last Pokémon, reopen its appraisal to carry on, or say the command again if the taps have stopped. It finishes by itself in \(limitText(seconds: limitSeconds)) if no new Pokémon is read."
        }
        return ScanNotification(identifier: "\(pausedIdentifierPrefix)\(scan).\(event)", scanId: scan, title: "Scan paused", body: body, offersFinish: true)
    }
}
