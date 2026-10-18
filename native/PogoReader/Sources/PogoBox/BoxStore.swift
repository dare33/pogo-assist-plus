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

        public var errorDescription: String? {
            switch self {
            case .notFound(let a, let i): return "no scan \(i) for account \(a)"
            case .corrupt(let f, let r): return "saved scan \(f) cannot be read: \(r)"
            case .badAccountName: return "The account name is empty. Type a name."
            case .accountExists(let n): return "There is already an account called \(n). Choose a different name."
            case .noSuchAccount(let n): return "There is no account called \(n)."
            case .notImplemented(let m): return "not implemented: \(m)"
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
        return try fm.contentsOfDirectory(atPath: root.path).compactMap { $0.removingPercentEncoding }.sorted()
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

    /// For tests: called at each step of a rename ("stage", "swap", "rollback", "moveBack" with the file's path) and may throw to stand in for a disk failure.
    var renameFault: ((_ phase: String, _ path: String) throws -> Void)?

    /// Rename an account: its folder, and the account name written inside each scan file (and, through `alsoRewrite`, inside other files
    /// of the folder, which is how `BoxLibrary` rewrites its box versions), so the data, the saved scans and their replay logs all follow.
    /// Refuses an empty name or another account's name (compared ignoring case and surrounding spaces; a change of capitals alone on the
    /// same account is allowed). It is all or nothing: each rewritten file is written beside the original as it is made (one in memory at a time),
    /// then the folder moves, then each original is set aside under a backup name and its rewrite put in its place. A failure while staging leaves
    /// the account exactly as it was; one in the swap puts the originals and the folder back, and if that cannot be done either, `Failure.renameIncomplete`
    /// says which name the account now has. A file that cannot be read as a scan (damaged, or from a newer app) is left as it is.
    /// `alsoRewrite` is given the old folder and a `write(path, data)` to call for each file it rewrites (path relative to the folder).
    public func renameAccount(from old: String, to new: String, alsoRewrite extra: (_ folder: URL, _ write: (_ path: String, _ data: Data) throws -> Void) throws -> Void = { _, _ in }) throws {
        let newName = new.trimmingCharacters(in: .whitespacesAndNewlines), oldName = old.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { throw Failure.badAccountName }
        let from = try accountDirectory(oldName, create: false)
        guard fm.fileExists(atPath: from.path) else { throw Failure.noSuchAccount(oldName) }
        for other in try accounts() where other != oldName && other.lowercased() == newName.lowercased() { throw Failure.accountExists(other) }
        if newName == oldName { return }
        let to = try accountDirectory(newName, create: false)
        let caseOnly = newName.lowercased() == oldName.lowercased()
        if !caseOnly { guard !fm.fileExists(atPath: to.path) else { throw Failure.accountExists(newName) } }

        let temp = ".renaming", backup = ".renaming-old"
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
        } catch { removeTemps(in: from); throw error }
        do { try moveFolder(from, to, caseOnly: caseOnly) } catch { removeTemps(in: from); throw error }

        var touched = [String]()   // swapped, or started to be
        do {
            for p in staged {
                try renameFault?("swap", p)
                let file = to.appendingPathComponent(p)
                touched.append(p)
                try fm.moveItem(at: file, to: to.appendingPathComponent(p + backup))
                try fm.moveItem(at: to.appendingPathComponent(p + temp), to: file)
            }
        } catch {
            // Put every original back, report anything that cannot be, then move the folder back.
            var problems = [String]()
            for p in touched.reversed() {
                let file = to.appendingPathComponent(p), saved = to.appendingPathComponent(p + backup)
                do {
                    try renameFault?("rollback", p)
                    if fm.fileExists(atPath: saved.path) {
                        if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
                        try fm.moveItem(at: saved, to: file)
                    }
                } catch { problems.append("\(p): \(error.localizedDescription)") }
            }
            removeTemps(in: to)
            do {
                try renameFault?("moveBack", to.lastPathComponent)
                try moveFolder(to, from, caseOnly: caseOnly)
            } catch {
                throw Failure.renameIncomplete(accountNow: newName, detail: (problems + ["the folder could not be moved back: \(error.localizedDescription)"]).joined(separator: "; "))
            }
            if !problems.isEmpty { throw Failure.renameIncomplete(accountNow: oldName, detail: problems.joined(separator: "; ")) }
            throw error
        }
        for p in staged { try? fm.removeItem(at: to.appendingPathComponent(p + backup)) }
    }

    /// Move an account folder. On a case-insensitive disk a change of capitals alone goes through a temporary name; if the second step fails the first is undone.
    private func moveFolder(_ from: URL, _ to: URL, caseOnly: Bool) throws {
        guard caseOnly else { try fm.moveItem(at: from, to: to); return }
        let temp = root.appendingPathComponent(".rename-\(UUID().uuidString)", isDirectory: true)
        try fm.moveItem(at: from, to: temp)
        do { try fm.moveItem(at: temp, to: to) } catch { try? fm.moveItem(at: temp, to: from); throw error }
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
