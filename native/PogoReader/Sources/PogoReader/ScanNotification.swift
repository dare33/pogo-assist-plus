import Foundation

/// The local notifications of a command scan, built in one place for both the broadcast extension and the app (the app posts the same one when it sees the event and the
/// extension's notification was not delivered). Plain text, tested in the package; posting is the app's and the extension's job. Nothing here touches the network.
public struct ScanNotification: Equatable {
    public var identifier: String
    public var title: String
    public var body: String
    /// Notifications of a pause carry the "Finish scan" action.
    public var offersFinish: Bool

    public static let finishActionID = "pogo.finish"
    public static let pausedCategoryID = "pogo.scan.paused"

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

    /// The scan ended by itself: "<N> Pokémon read, last: <name> CP <cp>. Say "Go to sleep" to stop the command, then continue from that Pokémon."
    public static func stopped(event: Int, read: Int, lastName: String?, lastCP: Int?) -> ScanNotification {
        let last = Self.last(lastName, lastCP).map { ", last: \($0)" } ?? ""
        return ScanNotification(identifier: "pogo.scan.stopped.\(event)", title: "Scan stopped",
                                body: "\(read) Pokémon read\(last). Say \"Go to sleep\" to stop the command, then continue from that Pokémon.", offersFinish: false)
    }

    /// The scan paused at a card that is not clearly the end: "Paused at <name> CP <cp>: <N> of <M> read. Reopen its appraisal to carry on, or say "Pogo scan <size>" if the taps have
    /// stopped." (size: the smallest covering M - N). With no count: "…<N> read. If that was not your last Pokémon, reopen its appraisal…".
    public static func paused(event: Int, read: Int, storageCount: Int?, lastName: String?, lastCP: Int?, sizes: [Int]) -> ScanNotification {
        let at = Self.last(lastName, lastCP).map { "Paused at \($0): " } ?? "Paused: "
        let body: String
        if let m = storageCount, m > 0 {
            let command = commandName(covering: max(1, m - read), sizes: sizes).map { "say \"\($0)\"" } ?? "say the command again"
            body = "\(at)\(read) of \(m) read. Reopen its appraisal to carry on, or \(command) if the taps have stopped."
        } else {
            body = "\(at)\(read) read. If that was not your last Pokémon, reopen its appraisal to carry on, or say the command again if the taps have stopped."
        }
        return ScanNotification(identifier: "pogo.scan.paused.\(event)", title: "Scan paused", body: body, offersFinish: true)
    }
}
