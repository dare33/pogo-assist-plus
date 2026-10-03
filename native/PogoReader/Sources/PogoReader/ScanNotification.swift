import Foundation

/// The local notifications of a command scan, built in one place for both the broadcast extension and the app (the app posts the same one when it sees the event and the
/// extension's notification was not delivered). Plain text, tested in the package; posting is the app's and the extension's job. Nothing here touches the network.
public struct ScanNotification: Equatable {
    public var identifier: String
    /// The scan this is about (its start time in whole seconds, `BroadcastState.scanId`): in the identifier, so one scan's event never replaces or hides another's, and in the
    /// notification's user info, so its "Finish scan" action can only finish THAT scan.
    public var scanId: Int
    public var title: String
    public var body: String
    /// Notifications of a pause carry the "Finish scan" action.
    public var offersFinish: Bool

    public static let finishActionID = "pogo.finish"
    public static let pausedCategoryID = "pogo.scan.paused"
    /// Every pause notification's identifier starts with this (`paused`), so they can be found and removed.
    public static let pausedIdentifierPrefix = "pogo.scan.paused."

    /// Whether a delivered or pending notification is a pause notification of `scan` (of any scan when nil): the ones removed when the scan resumes or finishes and when a new scan starts.
    public static func isPause(_ identifier: String, scan: Int? = nil) -> Bool {
        guard identifier.hasPrefix(pausedIdentifierPrefix) else { return false }
        guard let scan else { return true }
        return identifier.hasPrefix("\(pausedIdentifierPrefix)\(scan).")
    }

    /// Whether a "Finish scan" request is honoured: only when it names the scan that is running and that scan is paused. A request for an old scan, or one made when the scan
    /// is not paused, does nothing (the caller clears it either way).
    public static func finishRequestHonoured(asked: Int, runningScan: Int, paused: Bool) -> Bool { paused && asked == runningScan }

    /// How the time limit reads in the notification and on the Scan screen ("3 minutes"), from the one constant.
    public static var pauseLimitText: String {
        let m = Int((ScanEndDecision.pauseTimeoutSeconds / 60).rounded())
        return m == 1 ? "1 minute" : "\(m) minutes"
    }

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
    /// stopped. It finishes by itself in 3 minutes if no new Pokémon is read." (size: the smallest covering M - N). With no count: "…<N> read. If that was not your last Pokémon, reopen its appraisal…".
    public static func paused(scan: Int, event: Int, read: Int, storageCount: Int?, eggCount: Int? = nil, lastName: String?, lastCP: Int?, sizes: [Int]) -> ScanNotification {
        let at = Self.last(lastName, lastCP).map { "Paused at \($0): " } ?? "Paused: "
        let body: String
        if let shown = storageCount, shown > 0 {
            // M: the Pokémon expected, the game's count less the eggs the person typed; with no egg count, the count as shown.
            let m = StorageCountRules.expected(count: shown, eggs: eggCount) ?? shown
            let command = commandName(covering: max(1, m - read), sizes: sizes).map { "say \"\($0)\"" } ?? "say the command again"
            body = "\(at)\(read) of about \(m) read. Reopen its appraisal to carry on, or \(command) if the taps have stopped. It finishes by itself in \(pauseLimitText) if no new Pokémon is read."
        } else {
            body = "\(at)\(read) read. If that was not your last Pokémon, reopen its appraisal to carry on, or say the command again if the taps have stopped. It finishes by itself in \(pauseLimitText) if no new Pokémon is read."
        }
        return ScanNotification(identifier: "\(pausedIdentifierPrefix)\(scan).\(event)", scanId: scan, title: "Scan paused", body: body, offersFinish: true)
    }
}
