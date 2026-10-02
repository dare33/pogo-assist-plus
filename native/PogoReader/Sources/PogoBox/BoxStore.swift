import Foundation

/// A box per account, kept as JSON files: `<root>/<account>/<scan id>.json`, one file per saved scan.
/// Holds the Pokémon inventory only (rows, review list, unmatched list, when and where it was scanned);
/// no names, emails or device identifiers. Writes are atomic (a temporary file, then a rename), so a
/// crash mid-write leaves the old file or none, never half a file. Not thread-safe: use one queue.
///
/// The "current box" is the latest FULL scan of the account by scan date. A second scan is stored as a
/// new scan; it does not touch the earlier ones. Merging a later partial scan into the box is not built
/// (`mergeIncremental`).
public final class BoxStore {
    public enum Kind: String, Codable { case full, partial }

    public enum Failure: Error, LocalizedError, Equatable {
        case notFound(account: String, id: String)
        /// The file exists but is not a readable scan (truncated, hand-edited, written by a newer app).
        case corrupt(file: String, reason: String)
        case badAccountName
        case notImplemented(String)

        public var errorDescription: String? {
            switch self {
            case .notFound(let a, let i): return "no scan \(i) for account \(a)"
            case .corrupt(let f, let r): return "saved scan \(f) cannot be read: \(r)"
            case .badAccountName: return "account name is empty"
            case .notImplemented(let m): return "not implemented: \(m)"
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
    }

    /// `scans` newest first by scan date; `unreadable` the file names that could not be read.
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
                     storageCount: Int? = nil, replayLog: Data? = nil) throws -> Summary {
        let dir = try accountDirectory(account, create: true)
        let id = Self.makeID(scanDate)
        let scan = StoredScan(schema: Self.schemaVersion, id: id, account: account, scanDate: scanDate, savedAt: Date(), source: source, kind: kind,
                              rows: result.rows, review: result.review, unmatched: result.unmatched, storageCount: storageCount)
        // The replay log goes first: if the scan file is then written, the log it rebuilds from is already there.
        if let log = replayLog { try log.write(to: dir.appendingPathComponent("\(id).replay.jsonl"), options: .atomic) }
        try Self.encoder.encode(scan).write(to: dir.appendingPathComponent("\(id).json"), options: .atomic)
        return Self.summary(scan)
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
            if let scan = try? read(dir.appendingPathComponent(name)) { scans.append(Self.summary(scan)) } else { bad.append(name) }
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

    private static func summary(_ s: StoredScan) -> Summary {
        Summary(id: s.id, scanDate: s.scanDate, savedAt: s.savedAt, source: s.source, kind: s.kind, rows: s.rows.count, flagged: s.review.count, unmatched: s.unmatched.count)
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
