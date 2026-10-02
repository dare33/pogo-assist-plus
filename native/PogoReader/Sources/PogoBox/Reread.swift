import Foundation

extension PagingHint {
    public init(_ stored: StoredPaging) { self.init(pagedByCommand: stored.pagedByCommand, expectedPeriod: stored.expectedPeriod, joinExtraSeconds: stored.joinExtraSeconds) }
}
extension StoredPaging {
    public init(_ hint: PagingHint) { self.init(pagedByCommand: hint.pagedByCommand, expectedPeriod: hint.expectedPeriod, joinExtraSeconds: hint.joinExtraSeconds) }
}

/// Reading a saved scan again with the rules the app has now. The scan keeps its replay log, kind and paging; the box it is merged into
/// is the box as it was before that scan was saved (the version before the first version the scan made). Nothing is changed until the
/// new read is saved; saving adds one box version built from that earlier box plus the new read.
public struct RereadPlan {
    public var scan: BoxStore.StoredScan
    public var replayURL: URL
    public var paging: PagingHint?
    /// The box before the scan was saved (empty when the scan made the first version).
    public var baseEntries: [BoxEntry]
    /// The version those entries come from, nil when there was none.
    public var baseSeq: Int?
    /// The first box version the scan made.
    public var scanSeq: Int
    /// Other scans saved after this one, and box corrections made after it. Saving drops both from the current box (the versions stay
    /// in the history): they are not re-applied.
    public var laterScans: Int
    public var laterEdits: Int
    public var hasLaterChanges: Bool { laterScans > 0 || laterEdits > 0 }
}

extension BoxLibrary {
    public enum RereadFailure: Error, LocalizedError, Equatable {
        case noReplayLog
        case notInTheHistory
        public var errorDescription: String? {
            switch self {
            case .noReplayLog: return "This scan did not keep its replay log, so it cannot be read again."
            case .notInTheHistory: return "This scan is not in the box history, so there is no earlier box to read it against."
            }
        }
    }

    /// What it takes to read a saved scan again. The scan's first box version is the lowest one that names it, so a scan that has
    /// already been read again still points at the box it was first saved onto.
    public func prepareReread(account: String, scanId: String) throws -> RereadPlan {
        let scan = try store.load(account: account, id: scanId)
        guard let replay = try store.files(account: account, id: scanId).replay else { throw RereadFailure.noReplayLog }
        let headers = try history(account: account).sorted { $0.seq < $1.seq }
        guard let first = headers.first(where: { $0.scanId == scanId && $0.reason == .scan }) else { throw RereadFailure.notInTheHistory }
        let later = headers.filter { $0.seq > first.seq }
        let otherScans = Set(later.filter { $0.reason == .scan }.compactMap { $0.scanId }.filter { $0 != scanId })
        let baseSeq = headers.last { $0.seq < first.seq }?.seq
        let base = try baseSeq.map { try load(account: account, seq: $0).entries } ?? []
        return RereadPlan(scan: scan, replayURL: replay, paging: scan.paging.map(PagingHint.init), baseEntries: base, baseSeq: baseSeq, scanSeq: first.seq,
                          laterScans: otherScans.count, laterEdits: later.filter { $0.reason == .edit }.count)
    }

    /// Save the new read: a new box version (the earlier box plus the re-read scan) and the scan's `lastReread`.
    @discardableResult
    public func commitReread(_ plan: RereadPlan, entries: [BoxEntry], account: String, expectedCurrentSeq: Int?? = nil, now: Date = Date()) throws -> BoxSnapshot {
        let snap = try commit(account: account, entries: entries, reason: .scan, note: "Read again: \(plan.scan.kind == .full ? "full scan" : "add and update"), \(entries.count) Pokémon",
                              scanId: plan.scan.id, scanKind: plan.scan.kind, scanDate: plan.scan.scanDate, expectedCurrentSeq: expectedCurrentSeq, now: now)
        try store.markReread(account: account, id: plan.scan.id, at: now)
        return snap
    }
}

extension BoxLibrary {
    /// What happened to the Pokémon that first came from a scan after it was saved, as the box versions record it: hand corrections and
    /// removals, one line each. A Pokémon "came from" the scan when it was first seen on the scan's date. Edits to Pokémon from earlier
    /// scans, and "These values are right", are not included (an edit version only keeps the box, not what the person did).
    public func editsAfter(account: String, scanId: String) throws -> [String] {
        let headers = try history(account: account).sorted { $0.seq < $1.seq }
        guard let first = headers.first(where: { $0.scanId == scanId && $0.reason == .scan }) else { return [] }
        let scan = try store.load(account: account, id: scanId)
        var lines = [String]()
        var before = try load(account: account, seq: first.seq).entries
        for h in headers where h.seq > first.seq {
            let after = try load(account: account, seq: h.seq).entries
            guard h.reason == .edit else { before = after; continue }
            let afterById = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for e in before where e.firstSeen == scan.scanDate {
                guard let now = afterById[e.id] else { lines.append("Removed from the box: \(e.row.title), CP \(e.row.cp)."); continue }
                var changes = [String]()
                if now.row.cp != e.row.cp { changes.append("CP \(e.row.cp) to \(now.row.cp)") }
                if now.row.hp != e.row.hp { changes.append("HP \(e.row.hp.map(String.init) ?? "none") to \(now.row.hp.map(String.init) ?? "none")") }
                if now.row.ivs != e.row.ivs { changes.append("IVs \(e.row.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "none") to \(now.row.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "none")") }
                if now.row.speciesId != e.row.speciesId { changes.append("species \(e.row.speciesId) to \(now.row.speciesId)") }
                if !changes.isEmpty { lines.append("Corrected by hand: \(e.row.title): \(changes.joined(separator: ", ")).") }
            }
            before = after
        }
        return lines
    }
}
