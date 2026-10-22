import Foundation

/// Which queued batches the reader should look at next. A batch is a candidate while it has something to read (or no account yet). The reader says which it has actually dealt with
/// (`markTried`); a batch is not offered again for the same waiting set, so one that cannot be finished (stopped, failing) does not make the reader spin, but it IS offered again when what is
/// waiting in it changes, and when it was finished and later has something to read once more (a copy of a discarded batch's screenshots is readable again, even with the same ids).
/// `rescanRequested` is for something that happened while the reader was busy (a batch was discarded): it asks for one more pass before stopping, and forgets what was tried.
public struct ReadPlanner: Equatable {
    private var tried = [String: String]()
    public private(set) var rescanRequested = false
    public init() {}

    /// What is waiting in a batch, as one value: it changes when the waiting set does.
    public static func token(_ m: ImportManifest) -> String { m.items.filter(\.needsReading).map(\.id).joined(separator: ",") + (m.account == nil ? "|noaccount" : "") }
    public static func isCandidate(_ m: ImportManifest) -> Bool { !m.isRead || m.account == nil }

    public mutating func requestRescan() { rescanRequested = true; tried.removeAll() }

    /// The batches to read now, oldest first. Nothing is recorded here: a batch the reader never got to (it stopped first) is still waiting to be offered.
    public mutating func next(from batches: [ImportManifest]) -> [String] {
        // a batch that is finished is forgotten, so waiting with the same ids again later is a new wait
        for m in batches where !Self.isCandidate(m) { tried[m.batchId] = nil }
        return batches.filter(Self.isCandidate).filter { tried[$0.batchId] != Self.token($0) }.map(\.batchId)
    }

    /// The reader dealt with this batch (read it, or stopped at it): not offered again until what is waiting in it changes. `m` is the batch as it stands now.
    public mutating func markTried(_ m: ImportManifest) { tried[m.batchId] = Self.isCandidate(m) ? Self.token(m) : nil }

    /// True once if a rescan was asked for; the caller then goes round again.
    public mutating func takeRescan() -> Bool { defer { rescanRequested = false }; return rescanRequested }
}
