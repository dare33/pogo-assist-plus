import Foundation
import ImageIO
@_exported import PogoImage

public enum ImportQueueError: Error, Equatable, LocalizedError {
    case tooManyInBatch(max: Int)
    case queueFull(max: Int)
    case queueTooLarge(maxMB: Int)
    case noSuchBatch(String)
    case unreadable(String)
    case newerVersion(String)
    case emptyBatch
    case badName(String)

    public var errorDescription: String? {
        switch self {
        case .tooManyInBatch(let n): return "Choose up to \(n) screenshots at a time."
        case .queueFull(let n): return "\(n) screenshots are already waiting. Open Pogo Assist+ and finish those first."
        case .queueTooLarge(let mb): return "The screenshots waiting already take \(mb) MB. Open Pogo Assist+ and finish those first."
        case .noSuchBatch: return "That batch of screenshots is no longer on the phone."
        case .unreadable(let b): return "The record of screenshot batch \(b) is damaged."
        case .newerVersion: return "These screenshots were queued by a newer version of the app. Update the app to open them."
        case .emptyBatch: return "None of the screenshots could be used."
        case .badName(let n): return "\(n) is not a valid batch name."
        }
    }
}

/// The persisted queue of screenshot batches, in a folder of the App Group (`<container>/screenshot-imports`). The share extension adds batches; the app reads, updates and
/// removes them. Nothing here talks to Photos, reads a picture's content or needs more than ImageIO and the file system.
///
/// Layout: `<root>/<batchId>/manifest.json` and the staged PNGs beside it; `<root>/ledger.json` (what earlier imports saved); `<root>/.staging-<batchId>/` (a batch being made).
/// A batch is made in its `.staging-` folder, manifest last, and the folder is renamed to `<batchId>` only when everything is in it: a reader that lists the queue sees a whole
/// batch or none, whichever process died where. Every manifest write is a temporary file renamed over the old one.
public struct ImportQueue {
    public static let maxImagesPerBatch = 50
    /// Staged images waiting across all batches. Each is a few MB, so this bounds the space the queue can take.
    public static let maxQueuedImages = 300
    /// And in bytes (staged PNGs are 1 to 6 MB each): the queue refuses a batch that would take it past this.
    public static let defaultMaxQueuedBytes = 1_000_000_000
    /// A batch nobody has touched for this long is thrown away by `cleanup` (its screenshots are still in Photos).
    public static let abandonedAfter: TimeInterval = 14 * 24 * 3600
    /// A batch folder half made (the process died while staging) is removed after this.
    public static let stagingExpiresAfter: TimeInterval = 3600
    /// The key the app writes the selected account under in the group's defaults (`ReaderSettings.scanAccount`), which the share extension reads to tell whose box a share is for.
    public static let selectedAccountKey = "scanAccount"
    static let manifestName = "manifest.json"
    static let ledgerName = "ledger.json"

    public let root: URL
    /// A test lowers it.
    public var maxQueuedBytes = ImportQueue.defaultMaxQueuedBytes
    private var fm: FileManager { .default }

    public init(root: URL) { self.root = root }

    /// The queue inside an app group container.
    public init(container: URL) { self.init(root: container.appendingPathComponent("screenshot-imports", isDirectory: true)) }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    // MARK: - paths

    static func validName(_ s: String) -> Bool { !s.isEmpty && s.count <= 80 && !s.hasPrefix(".") && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }
    public func batchDirectory(_ id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    func manifestURL(_ id: String) -> URL { batchDirectory(id).appendingPathComponent(Self.manifestName) }
    public func stagedURL(batch: String, item: ImportItem) -> URL { batchDirectory(batch).appendingPathComponent(item.file) }

    /// Write `data` over `url` as a temporary file in the same folder and a rename.
    static func writeAtomically(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.prefix(8)).tmp")
        do {
            try data.write(to: tmp)
            if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: tmp) } else { try fm.moveItem(at: tmp, to: url) }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    // MARK: - making a batch

    /// A batch being staged. Add images one at a time (bounded memory), then `commit`; `abort` removes what was staged.
    public final class Builder: @unchecked Sendable {   // used by one caller at a time: the share extension stages in turn, and the app's picker stages from one task
        public let batchId: String
        public let origin: ImportManifest.Origin
        public let account: String?
        let renameMark: Int?
        let queue: ImportQueue
        let staging: URL
        let createdAt: Date
        public private(set) var items: [ImportItem] = []
        private var finished = false

        private var bytes = 0

        init(queue: ImportQueue, origin: ImportManifest.Origin, account: String?, renameMark: Int?, now: Date) throws {
            self.queue = queue; self.origin = origin; self.account = account; self.renameMark = renameMark; createdAt = now
            let stamp = ISO8601DateFormatter().string(from: now).filter { $0.isNumber }
            batchId = "\(stamp)-\(UUID().uuidString.lowercased().prefix(8))"
            staging = queue.root.appendingPathComponent(".staging-\(batchId)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        }

        /// Stage one image from a file: hash its bytes, then keep an upright, metadata-free PNG of it. Throws `ImageStagingError` for something that is not a usable image;
        /// the batch is unaffected by that.
        @discardableResult
        public func add(contentsOf url: URL, assetId: String? = nil) throws -> ImportItem {
            if items.count >= ImportQueue.maxImagesPerBatch { throw ImportQueueError.tooManyInBatch(max: ImportQueue.maxImagesPerBatch) }
            let sourceHash = try ImageNormalising.sha256(of: url)
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ImageStagingError.cannotDecode }
            return try stage(src, sourceHash: sourceHash, assetId: assetId)
        }

        @discardableResult
        public func add(data: Data, assetId: String? = nil) throws -> ImportItem {
            if items.count >= ImportQueue.maxImagesPerBatch { throw ImportQueueError.tooManyInBatch(max: ImportQueue.maxImagesPerBatch) }
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { throw ImageStagingError.cannotDecode }
            return try stage(src, sourceHash: ImageNormalising.sha256(of: data), assetId: assetId)
        }

        private func stage(_ src: CGImageSource, sourceHash: String, assetId: String?) throws -> ImportItem {
            let png = try ImageNormalising.stagedPNG(from: src)
            let id = UUID().uuidString.lowercased()
            let file = String(format: "%03d-%@.png", items.count + 1, String(id.prefix(8)))
            try png.data.write(to: staging.appendingPathComponent(file))
            bytes += png.data.count
            let item = ImportItem(id: id, file: file, assetId: assetId, sourceHash: sourceHash, stagedHash: ImageNormalising.sha256(of: png.data), width: png.width, height: png.height)
            items.append(item)
            return item
        }

        /// Write the manifest and make the batch visible to readers of the queue. Refused when nothing was staged or the queue would hold too many images.
        @discardableResult
        public func commit(now: Date = Date()) throws -> ImportManifest {
            defer { if !finished { abort() } }
            guard !items.isEmpty else { throw ImportQueueError.emptyBatch }
            let waiting = (try? queue.list().manifests.reduce(0) { $0 + $1.items.count }) ?? 0
            if waiting + items.count > ImportQueue.maxQueuedImages { throw ImportQueueError.queueFull(max: ImportQueue.maxQueuedImages) }
            if queue.stagedBytes() + bytes > queue.maxQueuedBytes { throw ImportQueueError.queueTooLarge(maxMB: queue.maxQueuedBytes / 1_000_000) }
            var manifest = ImportManifest(batchId: batchId, createdAt: createdAt, origin: origin, account: account, items: items)
            manifest.updatedAt = now
            manifest.renameMark = renameMark
            try ImportQueue.writeAtomically(try ImportQueue.encoder.encode(manifest), to: staging.appendingPathComponent(ImportQueue.manifestName))
            try FileManager.default.moveItem(at: staging, to: queue.batchDirectory(batchId))   // the one step that makes the batch exist
            finished = true
            return manifest
        }

        public func abort() {
            finished = true
            try? FileManager.default.removeItem(at: staging)
        }
    }

    public func beginBatch(origin: ImportManifest.Origin, account: String?, renameMark: Int? = nil, now: Date = Date()) throws -> Builder {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return try Builder(queue: self, origin: origin, account: account, renameMark: renameMark, now: now)
    }

    /// Bytes of staged images in every batch of the queue.
    public func stagedBytes() -> Int {
        guard let batches = try? list().manifests else { return 0 }
        var total = 0
        for m in batches { for item in m.items { total += ((try? fm.attributesOfItem(atPath: stagedURL(batch: m.batchId, item: item).path))?[.size] as? Int) ?? 0 } }
        return total
    }

    /// The person has been shown these batches (or acted on one): clean-up counts its fourteen days from here, and never removes a batch that was not shown.
    public func markSeen(_ ids: [String], now: Date = Date()) {
        for id in ids { _ = try? update(id, now: now) { $0.seenAt = now } }
    }

    // MARK: - reading the queue

    public struct Listing {
        /// Oldest first.
        public var manifests: [ImportManifest]
        /// Batch folders whose manifest cannot be read (damaged, or written by a newer app): kept, never deleted for the person.
        public var unreadable: [String]
        public init(manifests: [ImportManifest], unreadable: [String]) { self.manifests = manifests; self.unreadable = unreadable }
    }

    public func list() throws -> Listing {
        guard fm.fileExists(atPath: root.path) else { return Listing(manifests: [], unreadable: []) }
        var out = [ImportManifest](), bad = [String]()
        for name in try fm.contentsOfDirectory(atPath: root.path).sorted() where Self.validName(name) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.appendingPathComponent(name).path, isDirectory: &isDir), isDir.boolValue else { continue }
            do { out.append(try load(name)) } catch { bad.append(name) }
        }
        out.sort { ($0.createdAt, $0.batchId) < ($1.createdAt, $1.batchId) }
        return Listing(manifests: out, unreadable: bad)
    }

    public func load(_ id: String) throws -> ImportManifest {
        guard Self.validName(id) else { throw ImportQueueError.badName(id) }
        guard let data = try? Data(contentsOf: manifestURL(id)) else { throw ImportQueueError.noSuchBatch(id) }
        struct VersionOnly: Decodable { var version: Int? }
        if let v = (try? Self.decoder.decode(VersionOnly.self, from: data))?.version, v > ImportManifest.currentVersion { throw ImportQueueError.newerVersion(id) }
        do {
            let m = try Self.decoder.decode(ImportManifest.self, from: data)
            guard m.batchId == id else { throw ImportQueueError.unreadable(id) }
            return m
        } catch let e as ImportQueueError { throw e } catch { throw ImportQueueError.unreadable(id) }
    }

    /// Read the batch, let `change` alter it, write it back whole. One writer at a time (the app's coordinator); the share extension never touches a committed batch.
    @discardableResult
    public func update(_ id: String, now: Date = Date(), _ change: (inout ImportManifest) -> Void) throws -> ImportManifest {
        var m = try load(id)
        change(&m)
        m.updatedAt = now
        try Self.writeAtomically(try Self.encoder.encode(m), to: manifestURL(id))
        return m
    }

    /// Remove a batch and its staged images (a save finished, or the person discarded it).
    public func remove(_ id: String) throws {
        guard Self.validName(id) else { throw ImportQueueError.badName(id) }
        let dir = batchDirectory(id)
        if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
    }

    // MARK: - clean-up

    public struct CleanupReport: Equatable {
        public var removedStaging = 0
        public var removedSaved = 0
        public var removedAbandoned = 0
        public var removedDamaged = 0
    }

    /// Housekeeping, run at launch and on coming to the front: half-made batch folders, batches whose save finished but whose removal was cut off, and batches the person was
    /// shown and then left alone for `abandonedAfter` (counted from the last time one was shown or acted on). A batch that was never shown is never removed, and neither is one this
    /// build cannot read (damaged, or from a newer app): the person is told it is there.
    @discardableResult
    public func cleanup(now: Date = Date()) -> CleanupReport {
        var report = CleanupReport()
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return report }
        for name in names where name.hasPrefix(".staging-") {
            let url = root.appendingPathComponent(name)
            let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? now
            if now.timeIntervalSince(modified) > Self.stagingExpiresAfter, (try? fm.removeItem(at: url)) != nil { report.removedStaging += 1 }
        }
        for m in (try? list().manifests) ?? [] {
            if m.savedAt != nil { if (try? remove(m.batchId)) != nil { report.removedSaved += 1 } }
            else if let seen = m.seenAt, now.timeIntervalSince(seen) > Self.abandonedAfter { if (try? remove(m.batchId)) != nil { report.removedAbandoned += 1 } }
        }
        return report
    }

    private static func error(of body: () throws -> Void) -> ImportQueueError? {
        do { try body(); return nil } catch let e as ImportQueueError { return e } catch { return nil }
    }
}

// MARK: - duplicates and the ledger of saved imports

/// What earlier imports saved, per account, kept beside the queue so a screenshot imported once is recognised when it comes again (a retried share, the same picture picked
/// next week). Keys are the item's identity keys (asset id, hashes), never what the Pokémon looks like. Bounded in age and size.
public struct ImportLedger: Codable, Equatable {
    public struct Entry: Codable, Equatable {
        public var account: String
        public var key: String
        public var batchId: String
        public var savedAt: Date
        /// How many renames the box had recorded when this was saved, so the account name can be followed to what it is called now (nil: an older entry, taken by name).
        public var epoch: Int?
    }
    public var version = 1
    public var entries: [Entry] = []
    public static let keepFor: TimeInterval = 365 * 24 * 3600
    public static let maxEntries = 20_000

    /// When any of `keys` was saved into `account`. `currentName` says what an entry's account is called now (nil: it cannot be told, so the entry is not counted); `excluding` leaves
    /// out a batch's own entries (a save cut off between the ledger and the removal must not make the batch's own screenshots look already imported).
    public func savedAt(account: String, keys: [String], excluding: String? = nil, currentName: (Entry) -> String? = { $0.account }) -> Date? {
        let wanted = Set(keys)
        return entries.filter { $0.batchId != excluding && wanted.contains($0.key) && currentName($0) == account }.map(\.savedAt).max()
    }
}

extension ImportQueue {
    var ledgerURL: URL { root.appendingPathComponent(Self.ledgerName) }

    public func ledger() -> ImportLedger {
        guard let data = try? Data(contentsOf: ledgerURL), let l = try? Self.decoder.decode(ImportLedger.self, from: data) else { return ImportLedger() }
        return l
    }

    /// Remember that these items were saved into `account`. Called after the box write succeeded; a failure here only means the same screenshot is not recognised later.
    public func recordSaved(_ items: [ImportItem], batchId: String, account: String, epoch: Int? = nil, now: Date = Date()) throws {
        var l = ledger()
        l.entries.removeAll { now.timeIntervalSince($0.savedAt) > ImportLedger.keepFor }
        let known = Set(l.entries.filter { $0.account == account }.map(\.key))
        for item in items { for k in item.keys where !known.contains(k) { l.entries.append(.init(account: account, key: k, batchId: batchId, savedAt: now, epoch: epoch)) } }
        if l.entries.count > ImportLedger.maxEntries { l.entries.removeFirst(l.entries.count - ImportLedger.maxEntries) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.writeAtomically(try Self.encoder.encode(l), to: ledgerURL)
    }

    /// Mark, in the batch's manifest, every item that is the same screenshot as an earlier one: in this batch, in an older batch still waiting for the same account, or in the
    /// ledger of what that account has saved. Identity is the asset id or the bytes; two screenshots of Pokémon with the same species, CP and IVs are NOT the same screenshot.
    /// An earlier item that failed (or could not be read) does not claim its screenshot: sharing it again is the retry. Idempotent. Returns the updated manifest.
    /// `ledgerAccount` says what a ledger entry's account is called now (see `ImportLedger.savedAt`).
    @discardableResult
    public func markDuplicates(_ batchId: String, now: Date = Date(), ledgerAccount: @escaping (ImportLedger.Entry) -> String? = { $0.account }) throws -> ImportManifest {
        let others = try list().manifests.filter { $0.batchId != batchId && $0.savedAt == nil }
        let ledger = self.ledger()
        return try update(batchId, now: now) { m in
            let older = others.filter { ($0.createdAt, $0.batchId) < (m.createdAt, m.batchId) && ($0.account == nil || m.account == nil || $0.account == m.account) }
            var seen = [String: String]()   // key -> the id that item is known by
            for o in older { for item in o.items where item.duplicateOf == nil && !item.canRetry { for k in item.keys { seen[k] = seen[k] ?? "\(o.batchId)/\(item.id)" } } }
            for i in m.items.indices {
                let item = m.items[i]
                m.items[i].duplicateOf = item.keys.compactMap { seen[$0] }.first
                if m.items[i].duplicateOf == nil && !item.canRetry { for k in item.keys { seen[k] = item.id } }
                m.items[i].alreadyImported = m.account.flatMap { ledger.savedAt(account: $0, keys: item.keys, excluding: m.batchId, currentName: ledgerAccount) }
            }
        }
    }

    /// After a save: keep only the screenshots that still need the person (held back, waiting to be read, or failed and worth trying again, and the copies that follow them), and
    /// delete the staged files of the rest. When nothing is left the whole batch goes. The next save of what is kept is a new scan, so it gets its own signature (`generation`).
    /// Returns the manifest that is left, or nil when the batch was removed.
    @discardableResult
    public func retire(_ batchId: String, saved: Set<String>, now: Date = Date()) throws -> ImportManifest? {
        var gone = [ImportItem]()
        let m = try update(batchId, now: now) { m in
            var keep = Set(m.items.filter { !saved.contains($0.id) && ($0.needsReading || $0.canRetry || $0.heldBack) }.map(\.id))
            // a copy of a screenshot that stays follows it; a copy of one in another batch waits on that batch; a copy of one that was saved is finished
            for item in m.items where !saved.contains(item.id) && !keep.contains(item.id) {
                if let of = item.duplicateOf, of.contains("/") || keep.contains(of) { keep.insert(item.id) }
            }
            gone = m.items.filter { !keep.contains($0.id) }
            m.items = m.items.filter { keep.contains($0.id) }
            m.generation += 1
            if m.items.isEmpty { m.savedAt = now }
        }
        for item in gone { try? fm.removeItem(at: stagedURL(batch: batchId, item: item)) }
        if m.items.isEmpty { try? remove(batchId); return nil }
        return m
    }
}
