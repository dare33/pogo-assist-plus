import Foundation

/// Which queued batches the reader should look at next. A batch is a candidate while it has something to read (or no account yet); it is offered again when what is waiting in it
/// CHANGES (a screenshot that was a copy of a discarded batch's is readable again), but never twice for the same waiting set, so a batch that cannot be finished (stopped, failing)
/// does not make the reader spin. `rescanRequested` is for something that happened while the reader was busy (a batch was discarded): it asks for one more pass before stopping.
public struct ReadPlanner: Equatable {
    private var tried = [String: String]()
    public private(set) var rescanRequested = false
    public init() {}

    /// What is waiting in a batch, as one value: it changes when the waiting set does.
    public static func token(_ m: ImportManifest) -> String { m.items.filter(\.needsReading).map(\.id).joined(separator: ",") + (m.account == nil ? "|noaccount" : "") }
    public static func isCandidate(_ m: ImportManifest) -> Bool { !m.isRead || m.account == nil }

    public mutating func requestRescan() { rescanRequested = true }

    /// The batches to read now, oldest first, and a note that they were tried. Empty means the reader can stop (unless a rescan was asked for: then it is cleared and the caller looks again).
    public mutating func next(from batches: [ImportManifest]) -> [String] {
        let ids = batches.filter(Self.isCandidate).filter { tried[$0.batchId] != Self.token($0) }.map(\.batchId)
        for m in batches where ids.contains(m.batchId) { tried[m.batchId] = Self.token(m) }
        return ids
    }

    /// True once if a rescan was asked for; the caller then goes round again.
    public mutating func takeRescan() -> Bool { defer { rescanRequested = false }; return rescanRequested }
}
