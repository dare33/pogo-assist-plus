import Foundation

/// A box per account, kept as JSON files: `<root>/<account>/<scan id>.json`, one file per saved scan.
/// Holds the Pokémon inventory only (rows, review list, unmatched list, when and where it was scanned);
/// no names, emails or device identifiers. Writes are atomic (a temporary file, then a rename), so a
/// crash mid-write leaves the old file or none, never half a file. Writes are not thread-safe: use one queue. The reads (`list`, `load`, `files`) keep no state of their
/// own and only read files that writes replace atomically, so they may be called from another queue (the app lists scans off the main actor).
///
/// The "current box" is the latest FULL scan of the account by scan date. A second scan is stored as a
/// new scan; it does not touch the earlier ones. Merging a later partial scan into the box is not built
/// (`mergeIncremental`).
/// How a scan was paged, as `PagingHint` says it (kept apart so the stored scan does not depend on the refine code).
public struct StoredPaging: Codable, Equatable {
    public var pagedByCommand: Bool
    public var expectedPeriod: Double?
    public var joinExtraSeconds: Double?
    public init(pagedByCommand: Bool, expectedPeriod: Double? = nil, joinExtraSeconds: Double? = nil) { self.pagedByCommand = pagedByCommand; self.expectedPeriod = expectedPeriod; self.joinExtraSeconds = joinExtraSeconds }
}

public final class BoxStore {
    public enum Kind: String, Codable { case full, partial }

    public enum Failure: Error, LocalizedError, Equatable {
        case notFound(account: String, id: String)
        /// The file exists but is not a readable scan (truncated, hand-edited, written by a newer app).
        case corrupt(file: String, reason: String)
        case badAccountName
        case accountExists(String)
        case noSuchAccount(String)
        case notImplemented(String)
        /// A rename could not be completed and could not be fully undone either: the account is now called `accountNow`, and `detail` says what is wrong.
        case renameIncomplete(accountNow: String, detail: String)
        /// A rename journal exists that cannot be read, and the disk shows a rename may have been cut off: nothing is guessed or deleted.
        case renameJournalUnreadable

        public var errorDescription: String? {
            switch self {
            case .notFound(let a, let i): return "no scan \(i) for account \(a)"
            case .corrupt(let f, let r): return "saved scan \(f) cannot be read: \(r)"
            case .badAccountName: return "The account name is empty. Type a name."
            case .accountExists(let n): return "There is already an account called \(n). Choose a different name."
            case .noSuchAccount(let n): return "There is no account called \(n)."
            case .notImplemented(let m): return "not implemented: \(m)"
            case .renameJournalUnreadable: return "An earlier rename was cut off and its record cannot be read, so it cannot be finished or undone automatically. Nothing has been changed or deleted."
            case .renameIncomplete(let now, let why): return "The account could not be renamed cleanly (\(why)). It is now called \(now). Check that your boxes and scans are all there."
            }
        }
    }

    public struct StoredScan: Codable, Equatable {
        public var schema: Int
        public var id: String
        public var account: String
        public var scanDate: Date
        public var savedAt: Date
        /// Free text about where the readings came from ("broadcast", "replay marathon-phone.json").
        public var source: String
        public var kind: Kind
        public var rows: [ScanRow]
        public var review: [ReviewEntry]
        public var unmatched: [Unmatched]
        /// The storage count the player typed before the scan, if any (kept with the scan; nothing reads it yet).
        public var storageCount: Int?
        /// How the scan was paged (a generated command at some pace, or by hand), kept so it can be read again the same way.
        public var paging: StoredPaging?
        /// When the scan was last read again with newer rules (`BoxLibrary.commitReread`), if ever.
        public var lastReread: Date?
        /// What Refine changed, one line each (kept so a report can include it).
        public var refineChanges: [String]?
        /// What the person answered at review (unsure rows, rows left out, entries kept from "gone").
        public var reviewActions: [String]?
        /// When this scan's report was sent ("Make scans better"), and a hash of what was sent, so the same scan is not sent twice unchanged.
        public var reportSentAt: Date?
        public var reportHash: String?
        /// The signature of the replay log this scan was read from (the app's marker for "this log has been through review"), so a save that was interrupted before the app
        /// noted it is not made twice. Nil for scans saved before it existed.
        public var sourceSignature: String?
    }

    public struct Summary: Equatable {
        public var id: String
        public var scanDate: Date
        public var savedAt: Date
        public var source: String
        public var kind: Kind
        public var rows: Int
        public var flagged: Int
        public var unmatched: Int
        public var lastReread: Date?
        public var reportSentAt: Date?
        public var sourceSignature: String?
    }

    /// `scans` newest first by scan date (read from each file's header fields and array lengths only, not the rows); `unreadable` the file names that could not be read.
    public struct Listing: Equatable {
        public var scans: [Summary]
        public var unreadable: [String]
    }

    public static let schemaVersion = 1
    public let root: URL
    private let fm = FileManager.default

    public init(root: URL) { self.root = root }

    // MARK: - Save / load

    @discardableResult
    public func save(_ result: ScanResult, account: String, scanDate: Date = Date(), source: String, kind: Kind = .full,
                     storageCount: Int? = nil, replayLog: Data? = nil, paging: StoredPaging? = nil,
                     refineChanges: [String]? = nil, reviewActions: [String]? = nil, reportSentAt: Date? = nil, reportHash: String? = nil, sourceSignature: String? = nil) throws -> Summary {
        let dir = try accountDirectory(account, create: true)
        let id = Self.makeID(scanDate)
        let scan = StoredScan(schema: Self.schemaVersion, id: id, account: account, scanDate: scanDate, savedAt: Date(), source: source, kind: kind,
                              rows: result.rows, review: result.review, unmatched: result.unmatched, storageCount: storageCount, paging: paging, lastReread: nil, refineChanges: refineChanges, reviewActions: reviewActions,
                              reportSentAt: reportSentAt, reportHash: reportHash, sourceSignature: sourceSignature)
        // The replay log goes first: if the scan file is then written, the log it rebuilds from is already there.
        if let log = replayLog { try log.write(to: dir.appendingPathComponent("\(id).replay.jsonl"), options: .atomic) }
        try Self.encoder.encode(scan).write(to: dir.appendingPathComponent("\(id).json"), options: .atomic)
        return Self.summary(scan)
    }

    /// Record that a saved scan was read again, now. Rewrites the scan file with only that field changed.
    public func markReread(account: String, id: String, at date: Date = Date()) throws {
        var scan = try load(account: account, id: id)
        scan.lastReread = date
        let file = try accountDirectory(account, create: false).appendingPathComponent("\(Self.safeFileStem(id)).json")
        try Self.encoder.encode(scan).write(to: file, options: .atomic)
    }

    /// Record that a scan's report was sent, and what was sent (a hash), so the same unchanged scan is not sent again.
    public func markReportSent(account: String, id: String, at date: Date, hash: String) throws {
        var scan = try load(account: account, id: id)
        scan.reportSentAt = date; scan.reportHash = hash
        let file = try accountDirectory(account, create: false).appendingPathComponent("\(Self.safeFileStem(id)).json")
        try Self.encoder.encode(scan).write(to: file, options: .atomic)
    }

    /// The replay log saved beside a scan (`save(replayLog:)`), or nil if that scan has none.
    public func replayLog(account: String, id: String) throws -> Data? {
        let file = try accountDirectory(account, create: false).appendingPathComponent("\(Self.safeFileStem(id)).replay.jsonl")
        return fm.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
    }

    public func accounts() throws -> [String] {
        guard fm.fileExists(atPath: root.path) else { return [] }
        // A name that begins with a dot is never an account (`accountDirectory` encodes such a name): it is the rename journal, its history or a rename's temporary folder.
        return try fm.contentsOfDirectory(atPath: root.path).filter { !$0.hasPrefix(".") }.compactMap { $0.removingPercentEncoding }.sorted()
    }

    public func list(account: String) throws -> Listing {
        let dir = try accountDirectory(account, create: false)
        guard fm.fileExists(atPath: dir.path) else { return Listing(scans: [], unreadable: []) }
        var scans: [Summary] = [], bad: [String] = []
        for name in try fm.contentsOfDirectory(atPath: dir.path).sorted() where name.hasSuffix(".json") {
            if let summary = try? readSummary(dir.appendingPathComponent(name)) { scans.append(summary) } else { bad.append(name) }
        }
        scans.sort { ($0.scanDate, $0.savedAt, $0.id) > ($1.scanDate, $1.savedAt, $1.id) }
        return Listing(scans: scans, unreadable: bad)
    }

    public func load(account: String, id: String) throws -> StoredScan {
        let file = try accountDirectory(account, create: false).appendingPathComponent("\(Self.safeFileStem(id)).json")
        guard fm.fileExists(atPath: file.path) else { throw Failure.notFound(account: account, id: id) }
        return try read(file)
    }

    /// The latest full scan that can be read, or nil if there is none. An unreadable newer file is skipped
    /// here and shows in `list(account:).unreadable`; the caller decides whether that matters.
    public func currentBox(account: String) throws -> StoredScan? {
        for s in try list(account: account).scans where s.kind == .full {
            if let scan = try? load(account: account, id: s.id) { return scan }
        }
        return nil
    }

    // MARK: - Export / delete

    /// The scan as a Poke Genie CSV, scan-date columns from the scan's own date.
    public func exportCSV(_ scan: StoredScan, using engine: CoreEngine) throws -> String {
        try engine.csv(rows: scan.rows, scanDate: scan.scanDate)
    }

    public func exportCSV(_ scan: StoredScan, using engine: CoreEngine, to url: URL) throws {
        try Data(try exportCSV(scan, using: engine).utf8).write(to: url, options: .atomic)
    }

    public func delete(account: String, id: String) throws {
        let file = try accountDirectory(account, create: false).appendingPathComponent("\(Self.safeFileStem(id)).json")
        guard fm.fileExists(atPath: file.path) else { throw Failure.notFound(account: account, id: id) }
        try fm.removeItem(at: file)
        try? fm.removeItem(at: file.deletingPathExtension().appendingPathExtension("replay.jsonl"))
    }

    /// For tests: called at each step of a rename ("stage", "swap", "rollback", "moveBack", "caseSecond", "caseUndo" with the file's path) and may throw to stand in for a disk failure
    /// the rename then reacts to (it rolls back).
    var renameFault: ((_ phase: String, _ path: String) throws -> Void)?
    /// For tests: the rename stops dead at this point ("journal", "staged", "retargeted", "moving", "caseTemp", "moved", "swap1", "swapped"), as if the app had been killed there: nothing
    /// is rolled back, so a fresh `recoverInterruptedRename` has to put the account right.
    var renameKill: String?
    private struct RenameKilled: Error {}
    private var recoveredByRename: RecoveredRename?
    /// The earlier cut-off rename that `renameAccount` finished or undid before starting its own, once (nil if none). Read on the same queue.
    public func takeRecoveredByRename() -> RecoveredRename? { defer { recoveredByRename = nil }; return recoveredByRename }
    /// A rename journal is on disk: a rename is unresolved, so an account that looks missing may be mid-rename.
    public var renameJournalExists: Bool { fm.fileExists(atPath: journalURL.path) }
    private func point(_ name: String) throws { if renameKill == name { throw RenameKilled() } }

    // MARK: - rename journal

    /// What a rename is doing, written (and synced) to the boxes root before it touches anything and updated at each phase; deleted only when the rename has completed or been
    /// rolled back. If the app is ended in the middle, the next load finds it and finishes or undoes the rename (`recoverInterruptedRename`), so the folder's name, every record's
    /// account and the waiting scan's account cannot be left disagreeing.
    struct RenameJournal: Codable, Equatable {
        var old: String
        var new: String
        /// The temporary folder name a case-only rename passes through (begins with a dot, so it is never listed as an account).
        var caseTemp: String?
        var phase: String
        /// The waiting scan whose account is being moved along with the rename.
        var waitingSignature: String?
    }
    private var journalURL: URL { root.appendingPathComponent(".rename-journal.json") }
    private var historyURL: URL { root.appendingPathComponent(".rename-history.json") }

    private func writeJournal(_ j: RenameJournal) throws {
        try renameFault?("journal", j.phase)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(j).write(to: journalURL, options: .atomic)
        let h = try FileHandle(forWritingTo: journalURL)
        defer { try? h.close() }
        try h.synchronize()   // on disk before the rename touches anything
    }
    private func readJournal() -> RenameJournal? { (try? Data(contentsOf: journalURL)).flatMap { try? JSONDecoder().decode(RenameJournal.self, from: $0) } }
    private func deleteJournal() throws { if fm.fileExists(atPath: journalURL.path) { try fm.removeItem(at: journalURL) } }

    /// Every completed rename (old name to new name), newest last, so a name recorded earlier (the account a scan was started under) can be followed to what it is called now.
    private func appendHistory(old: String, new: String) {
        var all = (try? Data(contentsOf: historyURL)).flatMap { try? JSONDecoder().decode([[String]].self, from: $0) } ?? []
        // The history keeps only the last 50 renames, so a position in it is not a stable number: `renameSequence` counts every rename ever recorded and never goes down.
        // A counter that cannot be read must not send the sequence backwards (a stamp already made would then point at the wrong place): it restarts a million above anything the history
        // can say, so every earlier stamp is older than the oldest rename on record and is asked about. The counter is written BEFORE the history: a failure between the two leaves it one
        // too high, which also only makes stamps look older (asked about), never newer.
        var total = renameSequence ?? (all.count + Self.counterRecoveryJump)
        if all.last != [old, new] { all.append([old, new]); total += 1 }
        try? Data(String(total).utf8).write(to: sequenceURL, options: .atomic)
        try? JSONEncoder().encode(Array(all.suffix(50))).write(to: historyURL, options: .atomic)
    }

    static let counterRecoveryJump = 1_000_000
    private var sequenceURL: URL { root.appendingPathComponent(".renames-recorded") }
    /// How many renames have ever been recorded (nil: the record cannot be read). Absent counter: the length of the history (a store from before the counter).
    var renameSequence: Int? {
        if let data = try? Data(contentsOf: sequenceURL) { return Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0 >= 0 ? $0 : nil } }
        guard fm.fileExists(atPath: historyURL.path) else { return 0 }
        guard let data = try? Data(contentsOf: historyURL), let all = try? JSONDecoder().decode([[String]].self, from: data) else { return nil }
        return all.count
    }

    public enum AccountLookup: Equatable {
        case found(String)
        /// The listing worked and the name is neither an account nor the result of a recorded rename: positively gone.
        case gone
        /// The accounts could not be listed (a storage problem): nothing can be said about the name.
        case unknown
    }

    /// The account a recorded name stands for now: itself if it still exists, else what a completed rename turned it into (followed through several renames), else `gone`; `unknown`
    /// when the folder cannot be listed, which is not the same as the account being gone.
    public func lookupAccount(_ recorded: String) -> AccountLookup {
        guard let list = try? accounts() else { return .unknown }
        let existing = Set(list)
        if existing.contains(recorded) { return .found(recorded) }
        // While a rename is unresolved, or if the record of renames exists and cannot be read, a missing account cannot be called gone.
        if renameJournalExists { return .unknown }
        var all = [[String]]()
        if fm.fileExists(atPath: historyURL.path) {
            guard let data = try? Data(contentsOf: historyURL), let decoded = try? JSONDecoder().decode([[String]].self, from: data) else { return .unknown }
            all = decoded
        }
        var name = recorded
        for _ in 0..<all.count + 1 {
            guard let step = all.last(where: { $0.count == 2 && $0[0] == name }) else { return .gone }
            name = step[1]
            if existing.contains(name) { return .found(name) }
        }
        return .gone
    }

    /// How many renames have been recorded in all: the "epoch" a binding is stamped with. It only goes up, whatever is trimmed from the history.
    public var renameCount: Int? { renameSequence }

    /// When an account's folder was made. A rename moves the folder and keeps this; deleting an account and making another of the same name does not.
    public func accountCreated(_ name: String) -> Double? {
        guard let dir = try? accountDirectory(name, create: false) else { return nil }
        return ((try? fm.attributesOfItem(atPath: dir.path))?[.creationDate] as? Date)?.timeIntervalSince1970
    }

    public enum AccountResolution: Equatable {
        case found(String)
        case gone
        case unknown
        /// `old` was renamed to `renamedTo` after the binding was made, and an account called `old` exists again: which of the two the binding means cannot be told, so the person says.
        case ambiguous(old: String, renamedTo: String)
        /// The binding is older than the oldest rename still on record, so what happened to the name since cannot be followed: the person says.
        case indeterminate
    }

    /// Whose account a name recorded at rename-sequence `since` means NOW. Renames made after `since` are followed first, before asking whether the name exists, because a name that was
    /// renamed away and then used for a new account is not the same account. With `since` nil (an older record) this is `lookupAccount`. A `since` older than the oldest rename the
    /// history still holds is `indeterminate`, unless no rename has happened since (then there is nothing to follow).
    public func resolveAccount(_ recorded: String, since: Int?) -> AccountResolution {
        guard let since else {
            switch lookupAccount(recorded) { case .found(let n): return .found(n); case .gone: return .gone; case .unknown: return .unknown }
        }
        guard let list = try? accounts() else { return .unknown }
        if renameJournalExists { return .unknown }
        var all = [[String]]()
        if fm.fileExists(atPath: historyURL.path) {
            guard let data = try? Data(contentsOf: historyURL), let decoded = try? JSONDecoder().decode([[String]].self, from: data) else { return .unknown }
            all = decoded
        }
        guard let total = renameSequence else { return .indeterminate }   // the counter cannot be read: nothing can be followed, so the person is asked
        let first = max(0, total - all.count)   // the position, in all renames ever, of the first one still held
        if since < first { return .indeterminate }
        var name = recorded, moved = false
        for step in all.dropFirst(max(0, min(since - first, all.count))) where step.count == 2 && step[0] == name { name = step[1]; moved = true }
        let existing = Set(list)
        guard moved else { return existing.contains(recorded) ? .found(recorded) : .gone }
        guard existing.contains(name) else { return .gone }
        return existing.contains(recorded) && recorded != name ? .ambiguous(old: recorded, renamedTo: name) : .found(name)
    }

    /// `lookupAccount` as a name or nil (gone, or not known).
    public func accountNamed(_ recorded: String) throws -> String? {
        if case .found(let n) = lookupAccount(recorded) { return n }
        return nil
    }

    // MARK: - rename

    /// Rename an account: its folder, and the account name written inside each scan file (and, through `alsoRewrite`, inside other files
    /// of the folder, which is how `BoxLibrary` rewrites its box versions), so the data, the saved scans and their replay logs all follow; `pending`, the waiting
    /// scan (`PendingScanStore`), follows too when it is this account's. Refuses an empty name or another account's name (compared ignoring case and surrounding spaces; a
    /// change of capitals alone on the same account is allowed). It is all or nothing and crash-safe: a journal is written first (see `RenameJournal`), each rewritten file is
    /// written beside the original as it is made (one in memory at a time), the waiting scan is retargeted, the folder moves, then each original is set aside under a backup
    /// name and its rewrite put in its place. A failure while staging or moving leaves the account as it was; one in the swap puts the originals and the folder back, and if that
    /// cannot be done either, the journal stays for the next load and `Failure.renameIncomplete` says so. A file that cannot be read as a scan (damaged, or from a newer app) is
    /// left as it is. `alsoRewrite` is given the old folder and a `write(path, data)` to call for each file it rewrites (path relative to the folder).
    public func renameAccount(from old: String, to new: String, pending: PendingScanStore? = nil,
                              alsoRewrite extra: (_ folder: URL, _ write: (_ path: String, _ data: Data) throws -> Void) throws -> Void = { _, _ in }) throws {
        let newName = new.trimmingCharacters(in: .whitespacesAndNewlines), oldName = old.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { throw Failure.badAccountName }
        let from = try accountDirectory(oldName, create: false)
        guard fm.fileExists(atPath: from.path) else { throw Failure.noSuchAccount(oldName) }
        for other in try accounts() where other != oldName && other.lowercased() == newName.lowercased() { throw Failure.accountExists(other) }
        if newName == oldName { return }
        let to = try accountDirectory(newName, create: false)
        let caseOnly = newName.lowercased() == oldName.lowercased()
        if !caseOnly { guard !fm.fileExists(atPath: to.path) else { throw Failure.accountExists(newName) } }
        // A rename that was cut off earlier is finished or undone first, so nothing it left can be mistaken for this one's.
        // Remembered for the caller (`takeRecoveredByRename`): finishing an earlier rename here moves that account, and the app moves its settings for it.
        recoveredByRename = try recoverRename(pending: pending) ?? recoveredByRename
        _ = try repairInterruptedRename(account: oldName)

        let temp = Self.renamingSuffix
        var waiting: String?
        if let pending, case .ready(let m, _) = pending.load(), m.account == oldName { waiting = m.signature }
        var journal = RenameJournal(old: oldName, new: newName, caseTemp: caseOnly ? ".rename-\(UUID().uuidString)" : nil, phase: "staging", waitingSignature: waiting)
        try writeJournal(journal)
        try point("journal")
        func advance(_ phase: String) throws { journal.phase = phase; try writeJournal(journal) }
        func abandon(_ error: Error) throws -> Never {   // nothing has moved: take the journal away and report
            if error is RenameKilled { throw error }
            try? deleteJournal()
            throw error
        }

        var staged = [String]()
        func removeTemps(in folder: URL) { for p in staged { try? fm.removeItem(at: folder.appendingPathComponent(p + temp)) } }
        func stage(_ path: String, _ data: Data) throws {
            try renameFault?("stage", path)
            try data.write(to: from.appendingPathComponent(path + temp), options: .atomic)
            staged.append(path)
        }
        do {
            for name in try fm.contentsOfDirectory(atPath: from.path).sorted() where name.hasSuffix(".json") {
                guard var scan = try? read(from.appendingPathComponent(name)) else { continue }
                scan.account = newName
                try stage(name, try Self.encoder.encode(scan))
            }
            try extra(from, stage)
            try advance("staged")
            try point("staged")
        } catch { if !(error is RenameKilled) { removeTemps(in: from) }; try abandon(error) }

        if let pending, waiting != nil {
            do { try pending.update { $0.account = newName } } catch { removeTemps(in: from); try abandon(error) }
        }
        do { try point("retargeted"); try advance("moving"); try point("moving") } catch { if !(error is RenameKilled) { removeTemps(in: from); try? retarget(pending, to: oldName, ifSignature: waiting) }; try abandon(error) }

        do { try moveFolder(from, to, journal: journal) }
        catch {
            if error is RenameKilled { throw error }
            // The folder did not move (or could not be put back): undo what was done before it.
            if case Failure.renameIncomplete = error { throw error }
            removeTemps(in: from)
            try? retarget(pending, to: oldName, ifSignature: waiting)
            try abandon(error)
        }
        // The phases "moved" and "swapped" only inform: recovery works from what is on disk, so a journal write that fails here changes nothing (the swap goes on, and a completed
        // swap is a success). "undoing" is different: it must be on disk before anything is undone (see `swapIn`).
        try? advance("moved")
        try point("moved")

        do { try swapIn(to, staged, beforeUndo: { try advance("undoing") }); try? advance("swapped"); try point("swapped") }
        catch {
            if error is RenameKilled { throw error }
            let problems = (error as? SwapFailure)?.problems ?? []
            let cause = (error as? SwapFailure)?.cause ?? error
            // The undo could not be recorded, so nothing was undone: the rename stays finishable and the next load finishes it.
            if (error as? SwapFailure)?.notStarted == true { throw Failure.renameIncomplete(accountNow: newName, detail: (problems).joined(separator: "; ")) }
            removeTemps(in: to)
            do {
                try renameFault?("moveBack", to.lastPathComponent)
                try moveFolder(to, from, journal: journal)
            } catch let back {
                if case Failure.renameIncomplete(let now, let why) = back { throw Failure.renameIncomplete(accountNow: now, detail: (problems + [why]).joined(separator: "; ")) }
                throw Failure.renameIncomplete(accountNow: newName, detail: (problems + ["the folder could not be moved back: \(back.localizedDescription)"]).joined(separator: "; "))
            }
            try? retarget(pending, to: oldName, ifSignature: waiting)
            if !problems.isEmpty { throw Failure.renameIncomplete(accountNow: oldName, detail: problems.joined(separator: "; ")) }
            try? deleteJournal()
            throw cause
        }
        appendHistory(old: oldName, new: newName)
        for p in staged { try? fm.removeItem(at: to.appendingPathComponent(p + Self.renamingOldSuffix)) }
        try deleteJournal()
    }

    private func retarget(_ pending: PendingScanStore?, to name: String, ifSignature sig: String?) throws {
        guard let pending, let sig, case .ready(let m, _) = pending.load(), m.signature == sig, m.account != name else { return }
        try pending.update { $0.account = name }
    }

    private struct SwapFailure: Error { var cause: Error; var problems: [String]; var notStarted = false }

    /// Put each staged rewrite (`<path>.renaming`) in place of its original, which is set aside as `<path>.renaming-old` first. A file is recorded as touched only after its original
    /// is moved aside, and a failure puts back exactly those; what cannot be put back is reported in the thrown `SwapFailure`.
    private func swapIn(_ folder: URL, _ paths: [String], beforeUndo: () throws -> Void) throws {
        var touched = [String](), done = 0
        do {
            for p in paths {
                try renameFault?("swap", p)
                let file = folder.appendingPathComponent(p), saved = folder.appendingPathComponent(p + Self.renamingOldSuffix), tmp = folder.appendingPathComponent(p + Self.renamingSuffix)
                if fm.fileExists(atPath: file.path) {
                    try fm.moveItem(at: file, to: saved)
                    touched.append(p)
                }
                try fm.moveItem(at: tmp, to: file)
                done += 1
                if done == 1 { try point("swap1") }
            }
        } catch {
            if error is RenameKilled { throw error }
            // Undoing a swap destroys the rewrites already put in place, so the journal says "undoing" first: from then on recovery only ever goes back. If that cannot be written
            // nothing is touched, and the rename is still finishable.
            do { try beforeUndo() } catch let mark {
                throw SwapFailure(cause: error, problems: ["the rename could not be marked as being undone (\(mark.localizedDescription)); it is finished the next time the box loads"], notStarted: true)
            }
            var problems = [String]()
            for p in touched.reversed() {
                let file = folder.appendingPathComponent(p), saved = folder.appendingPathComponent(p + Self.renamingOldSuffix)
                do {
                    try renameFault?("rollback", p)
                    if fm.fileExists(atPath: saved.path) {
                        if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
                        try fm.moveItem(at: saved, to: file)
                    }
                } catch { problems.append("\(p): \(error.localizedDescription)") }
            }
            throw SwapFailure(cause: error, problems: problems)
        }
    }

    /// Move an account folder. A change of capitals alone goes through the journal's temporary name; if the second step fails the first is undone, and if that fails too the
    /// journal stays and the next load puts the folder back (the temporary name is never shown as an account).
    private func moveFolder(_ from: URL, _ to: URL, journal: RenameJournal?) throws {
        let caseTemp = journal?.caseTemp ?? (from.lastPathComponent.lowercased() == to.lastPathComponent.lowercased() ? ".rename-\(UUID().uuidString)" : nil)
        guard let caseTemp else { try fm.moveItem(at: from, to: to); return }
        let temp = root.appendingPathComponent(caseTemp, isDirectory: true)
        try fm.moveItem(at: from, to: temp)
        try point("caseTemp")
        do {
            try renameFault?("caseSecond", to.lastPathComponent)
            try fm.moveItem(at: temp, to: to)
        } catch {
            if error is RenameKilled { throw error }
            do {
                try renameFault?("caseUndo", from.lastPathComponent)
                try fm.moveItem(at: temp, to: from)
            } catch let undo {
                throw Failure.renameIncomplete(accountNow: from.lastPathComponent.removingPercentEncoding ?? from.lastPathComponent,
                                               detail: "the folder could not be renamed (\(error.localizedDescription)) or put back (\(undo.localizedDescription)); it is put right the next time the box is loaded")
            }
            throw error
        }
    }

    public struct RecoveredRename: Equatable {
        public var old: String, new: String
        /// True: the rename was finished (the account now has the new name); false: it was undone (the old name).
        public var finished: Bool
    }

    /// Finish or undo a rename that was cut off (the journal is still there). The rule: a journal whose phase is "undoing" is always rolled back, never forward (the undo had begun,
    /// so some rewrites may already be gone); any other journal is rolled forward if the folder has already moved to the new name (the remaining rewrites are put in place, and
    /// if that fails everything is undone, "undoing" first) and rolled back if it has not. Rolling back puts the folder (and a case-only rename's temporary folder) back under
    /// the old name, restores every original set aside as `.renaming-old` over whatever is in its place, removes leftover copies and points the waiting scan at the old account.
    /// Either way the folder's name, every record's account and the waiting scan agree afterwards, and the journal is deleted last, so a recovery that is itself cut off is simply
    /// run again. A journal that cannot be read is never deleted unless the disk shows nothing in flight (no rename temporary folder, no `.renaming` or `.renaming-old` file in
    /// any account); otherwise `Failure.renameJournalUnreadable` is thrown and everything is left alone. Run it on the one queue the boxes are written from, never while a rename
    /// is running. Returns what it did, or nil when there was nothing to do.
    @discardableResult
    public func recoverRename(pending: PendingScanStore? = nil) throws -> RecoveredRename? {
        guard fm.fileExists(atPath: journalURL.path) else { return nil }
        guard let j = readJournal() else {
            if try diskShowsNothingInFlight() { try deleteJournal(); return nil }
            throw Failure.renameJournalUnreadable
        }
        let names = Set((try? fm.contentsOfDirectory(atPath: root.path)) ?? [])
        let oldDir = try accountDirectory(j.old, create: false), newDir = try accountDirectory(j.new, create: false)
        let tempThere = j.caseTemp.map { names.contains($0) } ?? false
        let moved = names.contains(newDir.lastPathComponent) && (j.caseTemp != nil ? !tempThere : !names.contains(oldDir.lastPathComponent))

        func rollBack() throws -> RecoveredRename {
            if moved {
                _ = try repairInterruptedRenameFiles(newDir, preferBackups: true)
                try point("recoverUndo1")
                try moveFolder(newDir, oldDir, journal: j)
            } else {
                if let t = j.caseTemp, tempThere { try fm.moveItem(at: root.appendingPathComponent(t, isDirectory: true), to: oldDir) }
                _ = try repairInterruptedRenameFiles(oldDir, preferBackups: true)
            }
            try point("recoverUndo2")
            try retarget(pending, to: j.old, ifSignature: j.waitingSignature)
            try deleteJournal()
            return RecoveredRename(old: j.old, new: j.new, finished: false)
        }

        if !moved || j.phase == "undoing" { return try rollBack() }
        // Roll forward: every rewrite still waiting beside its original goes in.
        var staged = [String]()
        for dir in ["", "box/"] {
            for n in ((try? fm.contentsOfDirectory(atPath: newDir.appendingPathComponent(dir).path)) ?? []).sorted() where n.hasSuffix(Self.renamingSuffix) {
                staged.append(dir + String(n.dropLast(Self.renamingSuffix.count)))
            }
        }
        do { try swapIn(newDir, staged, beforeUndo: { var u = j; u.phase = "undoing"; try writeJournal(u) }) }
        catch {
            if error is RenameKilled { throw error }
            let f = error as? SwapFailure
            // Could not finish and could not even record that it is being undone: leave it for the next load.
            if f?.notStarted == true { throw Failure.renameIncomplete(accountNow: j.new, detail: (f?.problems ?? []).joined(separator: "; ")) }
            // Undoing has begun (the journal says so): finish it.
            return try rollBack()
        }
        _ = try repairInterruptedRenameFiles(newDir)
        try retarget(pending, to: j.new, ifSignature: j.waitingSignature)
        appendHistory(old: j.old, new: j.new)
        try deleteJournal()
        return RecoveredRename(old: j.old, new: j.new, finished: true)
    }

    /// Whether the disk shows no rename in flight: no `.rename-` temporary folder in the boxes folder and no `.renaming` / `.renaming-old` file in any account.
    private func diskShowsNothingInFlight() throws -> Bool {
        let top = try fm.contentsOfDirectory(atPath: root.path)
        if top.contains(where: { $0.hasPrefix(".rename-") && $0 != ".rename-journal.json" && $0 != ".rename-history.json" }) { return false }
        for a in try accounts() {
            let folder = try accountDirectory(a, create: false)
            for dir in [folder, folder.appendingPathComponent("box", isDirectory: true)] {
                if ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).contains(where: { $0.hasSuffix(Self.renamingSuffix) || $0.hasSuffix(Self.renamingOldSuffix) }) { return false }
            }
        }
        return true
    }

    /// `recoverRename` as a yes/no: whether there was anything to do.
    @discardableResult
    public func recoverInterruptedRename(pending: PendingScanStore? = nil) throws -> Bool { try recoverRename(pending: pending) != nil }

    static let renamingSuffix = ".renaming", renamingOldSuffix = ".renaming-old"

    /// Put right what a rename that was cut off (a crash, a kill) left in the account's folder and its `box` folder: an original set aside under `<name>.renaming-old` whose file
    /// is missing is put back; a backup beside a file that exists is deleted (the file is the live one, a backup never overwrites it); half-written `<name>.renaming` copies are
    /// deleted. Returns how many files it touched. Safe to run at any time except during a rename (the app runs it at load, before one starts).
    @discardableResult
    public func repairInterruptedRename(account: String) throws -> Int {
        // While a journal is there the rename it describes is finished or undone first (`recoverInterruptedRename`): its copies are not leftovers.
        guard !fm.fileExists(atPath: journalURL.path) else { return 0 }
        let folder = try accountDirectory(account, create: false)
        guard fm.fileExists(atPath: folder.path) else { return 0 }
        return try repairInterruptedRenameFiles(folder)
    }

    /// `preferBackups`: the rename is being undone, so an original set aside as `.renaming-old` is the truth and replaces what is in its place (which may be the rewrite).
    private func repairInterruptedRenameFiles(_ folder: URL, preferBackups: Bool = false) throws -> Int {
        var touched = 0
        for dir in [folder, folder.appendingPathComponent("box", isDirectory: true)] {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for n in names.sorted() {
                let url = dir.appendingPathComponent(n)
                if n.hasSuffix(Self.renamingOldSuffix) {
                    let live = dir.appendingPathComponent(String(n.dropLast(Self.renamingOldSuffix.count)))
                    if fm.fileExists(atPath: live.path) {
                        if preferBackups { try fm.removeItem(at: live); try fm.moveItem(at: url, to: live) } else { try fm.removeItem(at: url) }
                    } else { try fm.moveItem(at: url, to: live) }
                    touched += 1
                } else if n.hasSuffix(Self.renamingSuffix) {
                    try fm.removeItem(at: url); touched += 1
                }
            }
        }
        return touched
    }

    /// Where a saved scan's files are, for sharing: the result file and the replay log (nil if that scan kept none).
    public func files(account: String, id: String) throws -> (result: URL, replay: URL?) {
        let dir = try accountDirectory(account, create: false), stem = Self.safeFileStem(id)
        let result = dir.appendingPathComponent("\(stem).json"), replay = dir.appendingPathComponent("\(stem).replay.jsonl")
        guard fm.fileExists(atPath: result.path) else { throw Failure.notFound(account: account, id: id) }
        return (result, fm.fileExists(atPath: replay.path) ? replay : nil)
    }

    public func deleteAccount(_ account: String) throws {
        let dir = try accountDirectory(account, create: false)
        if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
    }

    // MARK: - Not built

    /// NOT IMPLEMENTED, on purpose. Adding a later, partial scan (only the new Pokémon) to the box needs a
    /// decision this code must not guess: how a row in the new scan is matched to a row already in the box
    /// (the box has no Pokémon id: name, CP and IVs change when a Pokémon is powered up or evolved, and two
    /// identical Pokémon are indistinguishable), what happens to a box row that is absent from the new scan
    /// (kept, or transferred away), and how flags and review state carry over. Until then a second scan is
    /// stored as its own scan and `currentBox` is the latest full one.
    public func mergeIncremental(into base: StoredScan, with scan: ScanResult) throws -> ScanResult {
        throw Failure.notImplemented("incremental box merge: matching rule for new scans against the saved box is undecided")
    }

    // MARK: - Files

    /// The folder of an account (percent-encoded name). Internal: `BoxLibrary` keeps its box versions in a subfolder of it.
    func accountDirectory(_ account: String, create: Bool) throws -> URL {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.badAccountName }
        // Percent-encoding keeps every distinct account name a distinct, safe directory name ("." and ".." included).
        var name = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? trimmed
        if name.hasPrefix(".") { name = "%2E" + name.dropFirst() }
        let dir = root.appendingPathComponent(name, isDirectory: true)
        if create { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        return dir
    }

    private func read(_ file: URL) throws -> StoredScan {
        do {
            let scan = try Self.decoder.decode(StoredScan.self, from: Data(contentsOf: file))
            guard scan.schema <= Self.schemaVersion else { throw Failure.corrupt(file: file.lastPathComponent, reason: "written by a newer version (schema \(scan.schema))") }
            return scan
        } catch let f as Failure { throw f }
        catch { throw Failure.corrupt(file: file.lastPathComponent, reason: "\(error)") }
    }

    /// What the list needs from a scan file, without building its rows: the arrays are only counted. A file whose rows are damaged but whose header is fine is listed here
    /// and fails when it is opened (`load`), which says so in words.
    private struct SummaryOnly: Decodable {
        struct Skipped: Decodable { init(from decoder: Decoder) throws {} }
        var schema: Int, id: String, scanDate: Date, savedAt: Date, source: String, kind: Kind
        var rows: [Skipped], review: [Skipped], unmatched: [Skipped]
        var lastReread: Date?, reportSentAt: Date?, sourceSignature: String?
    }

    private func readSummary(_ file: URL) throws -> Summary {
        do {
            let s = try Self.decoder.decode(SummaryOnly.self, from: Data(contentsOf: file))
            guard s.schema <= Self.schemaVersion else { throw Failure.corrupt(file: file.lastPathComponent, reason: "written by a newer version (schema \(s.schema))") }
            return Summary(id: s.id, scanDate: s.scanDate, savedAt: s.savedAt, source: s.source, kind: s.kind, rows: s.rows.count, flagged: s.review.count, unmatched: s.unmatched.count, lastReread: s.lastReread, reportSentAt: s.reportSentAt, sourceSignature: s.sourceSignature)
        } catch let f as Failure { throw f }
        catch { throw Failure.corrupt(file: file.lastPathComponent, reason: "\(error)") }
    }

    private static func summary(_ s: StoredScan) -> Summary {
        Summary(id: s.id, scanDate: s.scanDate, savedAt: s.savedAt, source: s.source, kind: s.kind, rows: s.rows.count, flagged: s.review.count, unmatched: s.unmatched.count, lastReread: s.lastReread, reportSentAt: s.reportSentAt, sourceSignature: s.sourceSignature)
    }

    private static func makeID(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return "scan-\(f.string(from: date))-\(UUID().uuidString.prefix(8).lowercased())"
    }

    /// An id from a caller must be a bare file name (no path pieces).
    private static func safeFileStem(_ id: String) -> String { id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
