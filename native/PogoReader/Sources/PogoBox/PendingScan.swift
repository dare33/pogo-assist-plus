import Foundation

/// What a scan that has been read for review and not yet saved or discarded needs to be opened again after the app was closed: whose it is, which log it came from
/// and what the broadcast and the person had set when it ended. `state` is the broadcast's state file as the app encoded it (opaque here), which the next broadcast
/// overwrites. Decoding is tolerant: a field this build does not know is ignored and one it expects but the file lacks takes its default, so an app update does not lose a
/// waiting scan. Only `signature` and `account` are required.
public struct PendingScanMeta: Codable, Equatable {
    public var signature: String
    public var account: String
    public var kind: BoxStore.Kind
    /// When the scan ended (the broadcast's last update), the date its Pokémon were seen; nil: use the time it is read.
    public var scanDate: Date?
    /// The Done screen has not been left for the review yet.
    public var doneFirst: Bool
    /// Times a reading of this scan was started and did not finish (the app was ended during it). A scan whose last reading never finished is not read again on its own.
    public var attempts: Int
    public var state: Data?

    public init(signature: String, account: String, kind: BoxStore.Kind = .full, scanDate: Date? = nil, doneFirst: Bool = false, attempts: Int = 0, state: Data? = nil) {
        self.signature = signature; self.account = account; self.kind = kind; self.scanDate = scanDate; self.doneFirst = doneFirst; self.attempts = attempts; self.state = state
    }

    private enum CodingKeys: String, CodingKey { case signature, account, kind, scanDate, doneFirst, attempts, state }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        signature = try c.decode(String.self, forKey: .signature)
        account = try c.decode(String.self, forKey: .account)
        kind = (try? c.decodeIfPresent(BoxStore.Kind.self, forKey: .kind)) ?? .full
        scanDate = try? c.decodeIfPresent(Date.self, forKey: .scanDate)
        doneFirst = (try? c.decodeIfPresent(Bool.self, forKey: .doneFirst)) ?? false
        attempts = (try? c.decodeIfPresent(Int.self, forKey: .attempts)) ?? 0
        state = try? c.decodeIfPresent(Data.self, forKey: .state)
    }
}

/// The one scan left unsaved, kept on disk beside the boxes: `<directory>/replay.jsonl` (the review's private copy of the shared replay log) and `<directory>/meta.json`.
/// The two are made together in a temporary folder and moved into place in one step, so a copy never sits beside the meta of another scan. At most one scan is kept: a
/// second `take` is refused while one is there, so a scan waiting for the person is never overwritten by a later broadcast. Reads and writes whole logs (up to 16 MB): call
/// it off the main actor. It holds no state of its own, so it may be used from any queue.
public struct PendingScanStore {
    public let directory: URL
    private var parent: URL { directory.deletingLastPathComponent() }
    private var copyURL: URL { directory.appendingPathComponent("replay.jsonl") }
    private var metaURL: URL { directory.appendingPathComponent("meta.json") }

    public init(directory: URL) { self.directory = directory }

    public enum Loaded: Equatable {
        case none
        case ready(PendingScanMeta, copy: URL)
        /// Something is kept but cannot be opened (no readable meta, or a log of another length than its signature says). Nothing is deleted: the person decides.
        case damaged(String)
    }

    public enum CopyResult: Equatable {
        case copied(URL)
        /// The shared log is not (any longer) the scan with that signature.
        case replaced
        /// Another scan is already waiting (or something damaged is kept): this one is not copied.
        case occupied
        case failed(String)
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: directory.path) }

    public func load() -> Loaded {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return .none }
        guard let data = try? Data(contentsOf: metaURL), let meta = try? Self.decoder.decode(PendingScanMeta.self, from: data) else {
            return .damaged("The record of this scan could not be read.")
        }
        guard let size = (try? fm.attributesOfItem(atPath: copyURL.path))?[.size] as? Int, String(size) == meta.signature.prefix(while: { $0 != "-" }) else {
            return .damaged("The saved log of this scan is missing or incomplete.")
        }
        return .ready(meta, copy: copyURL)
    }

    /// Copy the shared log for `meta.signature`. `currentSignature` is the shared log's signature now; it is asked before the read and after it, and the bytes read must be as
    /// long as the signature says, so a log rewritten underneath never gives a mixed copy. If the scan with this signature is already kept, that copy is returned.
    public func take(from shared: URL, meta: PendingScanMeta, currentSignature: () -> String?) -> CopyResult {
        let fm = FileManager.default
        switch load() {
        case .ready(let kept, let copy): return kept.signature == meta.signature ? .copied(copy) : .occupied
        case .damaged: return .occupied
        case .none: break
        }
        guard currentSignature() == meta.signature, let data = try? Data(contentsOf: shared),
              String(data.count) == meta.signature.prefix(while: { $0 != "-" }), currentSignature() == meta.signature else { return .replaced }
        let temp = parent.appendingPathComponent(directory.lastPathComponent + ".tmp-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            try data.write(to: temp.appendingPathComponent("replay.jsonl"), options: .atomic)
            try Self.encoder.encode(meta).write(to: temp.appendingPathComponent("meta.json"), options: .atomic)
            try fm.moveItem(at: temp, to: directory)   // fails if another scan arrived meanwhile: nothing is overwritten
            return .copied(copyURL)
        } catch {
            try? fm.removeItem(at: temp)
            if exists { return .occupied }
            return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Change the kept meta (attempts, the Done screen, a renamed account). Throws if nothing readable is kept.
    @discardableResult
    public func update(_ edit: (inout PendingScanMeta) -> Void) throws -> PendingScanMeta {
        guard case .ready(var meta, _) = load() else { throw CocoaError(.fileNoSuchFile) }
        edit(&meta)
        try Self.encoder.encode(meta).write(to: metaURL, options: .atomic)
        return meta
    }

    /// Remove what is kept, but only the scan with this signature (nil: whatever is kept, for a damaged one the person chose to discard).
    public func clear(ifSignature signature: String? = nil) {
        if let signature {
            guard case .ready(let meta, _) = load(), meta.signature == signature else { return }
        }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Leftovers of a `take` that was ended half way.
    public func removeStrayTemporaries() {
        let fm = FileManager.default
        for n in (try? fm.contentsOfDirectory(atPath: parent.path)) ?? [] where n.hasPrefix(directory.lastPathComponent + ".tmp-") { try? fm.removeItem(at: parent.appendingPathComponent(n)) }
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
