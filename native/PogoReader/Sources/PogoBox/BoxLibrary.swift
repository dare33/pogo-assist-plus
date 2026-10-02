import Foundation

/// One version of an account's box: every entry as it stood after a scan was saved, a hand correction was made or an
/// older version was restored. Versions are never changed or deleted; `BoxLibrary` only adds.
public struct BoxSnapshot: Codable, Equatable {
    public enum Reason: String, Codable { case scan, edit, restore }

    public var schema: Int
    /// 1, 2, 3 ... per account. The newest version is the box.
    public var seq: Int
    public var account: String
    public var createdAt: Date
    public var reason: Reason
    /// One line for the history list ("Full scan, 51 Pokémon", "Restored version 3").
    public var note: String
    /// The scan this version came from (`BoxStore` scan id), for a scan.
    public var scanId: String?
    public var scanKind: BoxStore.Kind?
    public var scanDate: Date?
    /// For a restore: the version whose entries were copied.
    public var restoredFrom: Int?
    public var entries: [BoxEntry]

    /// The version without its entries, for the history list.
    public struct Header: Codable, Equatable {
        public var seq: Int
        public var createdAt: Date
        public var reason: Reason
        public var note: String
        public var restoredFrom: Int?
        /// The scan this version came from, for a version a scan made.
        public var scanId: String?
    }
    public var header: Header { Header(seq: seq, createdAt: createdAt, reason: reason, note: note, restoredFrom: restoredFrom, scanId: scanId) }
}

/// The versioned box of each account, beside the scans `BoxStore` keeps: `<account folder>/box/<seq>.json`. The newest file
/// is the current box. Writes are atomic. Not thread-safe: use the one queue.
public final class BoxLibrary {
    public static let schemaVersion = 1
    public let store: BoxStore
    private let fm = FileManager.default

    public init(store: BoxStore) { self.store = store }
    public convenience init(root: URL) { self.init(store: BoxStore(root: root)) }

    public enum Failure: Error, LocalizedError, Equatable {
        case noSuchVersion(Int)
        case nothingToRestore
        /// The box changed since this action was prepared.
        case boxChanged
        case nothingReadable
        public var errorDescription: String? {
            switch self {
            case .noSuchVersion(let n): return "Version \(n) of this box is not on the device."
            case .nothingToRestore: return "There is no earlier box to go back to."
            case .boxChanged: return "The box changed while this was open."
            case .nothingReadable: return "None of the saved versions of this box can be read."
            }
        }
    }

    // MARK: - accounts

    public func accounts() throws -> [String] { try store.accounts() }

    /// Make an account (an empty folder). Fine to call for one that exists.
    public func createAccount(_ name: String) throws { _ = try store.accountDirectory(name, create: true) }

    /// Rename an account (see `BoxStore.renameAccount`); its box versions follow, with the new name written into each.
    public func renameAccount(from old: String, to new: String) throws {
        try store.renameAccount(from: old, to: new)
        let newName = new.trimmingCharacters(in: .whitespacesAndNewlines)
        for seq in (try? seqs(newName)) ?? [] {
            guard let f = try? file(newName, seq), var snap = try? load(account: newName, seq: seq) else { continue }
            snap.account = newName
            try? Self.encoder.encode(snap).write(to: f, options: .atomic)
        }
    }

    // MARK: - versions

    public func current(account: String) throws -> BoxSnapshot? {
        guard let seq = try seqs(account).last else { return nil }
        return try load(account: account, seq: seq)
    }

    public func load(account: String, seq: Int) throws -> BoxSnapshot {
        let file = try file(account, seq)
        guard fm.fileExists(atPath: file.path) else { throw Failure.noSuchVersion(seq) }
        do { return try Self.decoder.decode(BoxSnapshot.self, from: Data(contentsOf: file)) }
        catch { throw BoxStore.Failure.corrupt(file: file.lastPathComponent, reason: "\(error)") }
    }

    /// Every version, newest first. A file that cannot be read is left out (it shows in `unreadable` of a fuller listing later).
    public func history(account: String) throws -> [BoxSnapshot.Header] {
        struct HeaderOnly: Decodable { var seq: Int; var createdAt: Date; var reason: BoxSnapshot.Reason; var note: String; var restoredFrom: Int?; var scanId: String? }
        var out = [BoxSnapshot.Header]()
        for seq in try seqs(account).reversed() {
            if let data = try? Data(contentsOf: file(account, seq)), let h = try? Self.decoder.decode(HeaderOnly.self, from: data) {
                out.append(BoxSnapshot.Header(seq: h.seq, createdAt: h.createdAt, reason: h.reason, note: h.note, restoredFrom: h.restoredFrom, scanId: h.scanId))
            }
        }
        return out
    }

    @discardableResult
    public func commit(account: String, entries: [BoxEntry], reason: BoxSnapshot.Reason, note: String, scanId: String? = nil, scanKind: BoxStore.Kind? = nil,
                       scanDate: Date? = nil, restoredFrom: Int? = nil, expectedCurrentSeq: Int?? = nil, now: Date = Date()) throws -> BoxSnapshot {
        let last = try seqs(account).last
        // A save prepared against a box that has since changed is refused, not written over it.
        if let expected = expectedCurrentSeq, expected != last { throw Failure.boxChanged }
        let next = (last ?? 0) + 1
        let snap = BoxSnapshot(schema: Self.schemaVersion, seq: next, account: account, createdAt: now, reason: reason, note: note, scanId: scanId, scanKind: scanKind,
                               scanDate: scanDate, restoredFrom: restoredFrom, entries: entries)
        try fm.createDirectory(at: try boxFolder(account), withIntermediateDirectories: true)
        try Self.encoder.encode(snap).write(to: file(account, next), options: .atomic)
        return snap
    }

    /// Change the box: `transform` is given the CURRENT entries, read here, and what it returns is written as the next version, all in
    /// one call, so two quick actions each see the other's result and neither drops it. A `transform` that throws writes nothing. Run it
    /// on the one queue the box is written from.
    @discardableResult
    public func mutate(account: String, reason: BoxSnapshot.Reason, note: String, now: Date = Date(), _ transform: ([BoxEntry]) throws -> [BoxEntry]) throws -> BoxSnapshot {
        let cur = try current(account: account)
        let entries = try transform(cur?.entries ?? [])
        return try commit(account: account, entries: entries, reason: reason, note: note, scanKind: cur?.scanKind, scanDate: cur?.scanDate, expectedCurrentSeq: .some(cur?.seq), now: now)
    }

    /// The newest version that can be read, skipping any that cannot.
    public func latestReadable(account: String) throws -> BoxSnapshot? {
        for seq in try seqs(account).reversed() { if let snap = try? load(account: account, seq: seq) { return snap } }
        return nil
    }

    /// Make the newest readable version the current box again, as a new version (for when the newest one is damaged).
    @discardableResult
    public func restoreLatestReadable(account: String, now: Date = Date()) throws -> BoxSnapshot {
        guard let snap = try latestReadable(account: account) else { throw Failure.nothingReadable }
        return try restore(account: account, seq: snap.seq, now: now)
    }

    /// Make an older version the current box again, as a new version (so the restore can itself be undone).
    @discardableResult
    public func restore(account: String, seq: Int, now: Date = Date()) throws -> BoxSnapshot {
        let old = try load(account: account, seq: seq)
        return try commit(account: account, entries: old.entries, reason: .restore, note: "Restored version \(seq)", scanKind: old.scanKind, scanDate: old.scanDate, restoredFrom: seq, now: now)
    }

    /// The version "Restore previous box" would restore: the one just before the current version, which holds the content that was current
    /// before the latest change (after [1 scan, 2 edit, 3 restore of 1, 4 scan] it is 3, which has the content of 1). Pressing it again
    /// from a restore goes back to what the restore replaced.
    public func previousVersion(account: String) throws -> BoxSnapshot.Header? {
        let all = try history(account: account)
        guard let cur = all.first else { return nil }
        return all.first { $0.seq < cur.seq }
    }

    @discardableResult
    public func restorePrevious(account: String, now: Date = Date()) throws -> BoxSnapshot {
        guard let prev = try previousVersion(account: account) else { throw Failure.nothingToRestore }
        return try restore(account: account, seq: prev.seq, now: now)
    }

    // MARK: - cached advice

    /// The advisor's report for a version, kept beside it so the Next tab opens at once.
    public func saveAdvice(_ advice: BoxAdvice, account: String, seq: Int) throws {
        try fm.createDirectory(at: try boxFolder(account), withIntermediateDirectories: true)
        try Self.encoder.encode(advice).write(to: try adviceFile(account, seq), options: .atomic)
    }

    public func loadAdvice(account: String, seq: Int) -> BoxAdvice? {
        guard let f = try? adviceFile(account, seq), let data = try? Data(contentsOf: f) else { return nil }
        return try? Self.decoder.decode(BoxAdvice.self, from: data)
    }

    // MARK: - files

    private func boxFolder(_ account: String) throws -> URL { try store.accountDirectory(account, create: false).appendingPathComponent("box", isDirectory: true) }
    private func file(_ account: String, _ seq: Int) throws -> URL { try boxFolder(account).appendingPathComponent(String(format: "%06d.json", seq)) }
    private func adviceFile(_ account: String, _ seq: Int) throws -> URL { try boxFolder(account).appendingPathComponent(String(format: "%06d.advice.json", seq)) }

    private func seqs(_ account: String) throws -> [Int] {
        let dir = try boxFolder(account)
        guard fm.fileExists(atPath: dir.path) else { return [] }
        return try fm.contentsOfDirectory(atPath: dir.path).compactMap { n -> Int? in
            guard n.hasSuffix(".json"), !n.hasSuffix(".advice.json") else { return nil }
            return Int(n.dropLast(5))
        }.sorted()
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
