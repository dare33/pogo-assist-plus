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
    /// The record of what was imported (the ledger) is there but cannot be read: it is never treated as empty or written over.
    case ledgerUnreadable

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
        case .ledgerUnreadable: return "The record of what has been imported could not be read, so nothing was saved. The damaged file was kept."
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
    /// Tests: runs at the start of every ledger write and may throw.
    public var ledgerFailure: (() throws -> Void)?
    /// Tests: runs at the start of confirming or removing provisional entries only (the writes made AFTER the box), so a failure there leaves the box written and the ledger not finished.
    public var ledgerConfirmFailure: (() throws -> Void)?
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
        let accountBorn: Double?
        let queue: ImportQueue
        let staging: URL
        let createdAt: Date
        public private(set) var items: [ImportItem] = []
        private var finished = false

        private var bytes = 0

        init(queue: ImportQueue, origin: ImportManifest.Origin, account: String?, renameMark: Int?, accountBorn: Double?, now: Date) throws {
            self.queue = queue; self.origin = origin; self.account = account; self.renameMark = renameMark; self.accountBorn = accountBorn; createdAt = now
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
            manifest.renameMark = renameMark; manifest.accountBorn = accountBorn
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

    public func beginBatch(origin: ImportManifest.Origin, account: String?, renameMark: Int? = nil, accountBorn: Double? = nil, now: Date = Date()) throws -> Builder {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return try Builder(queue: self, origin: origin, account: account, renameMark: renameMark, accountBorn: accountBorn, now: now)
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
            // A batch with no screenshots left is finished, and so is a folder whose removal was cut off after its manifest went: neither is listed (the folder stays hidden, and `cleanup` tries again).
            do { let m = try load(name); if !m.items.isEmpty { out.append(m) } } catch { if manifestState(name) != .missing { bad.append(name) } }
        }
        out.sort { ($0.createdAt, $0.batchId) < ($1.createdAt, $1.batchId) }
        return Listing(manifests: out, unreadable: bad)
    }

    enum ManifestState { case present, missing, inaccessible }

    /// Missing only when the system says there is no such file; any other failure (an unreadable batch folder, a permission error) is `inaccessible`, which is damaged and never gone. `fileExists`
    /// cannot tell the two apart, since it is false for both.
    func manifestState(_ id: String) -> ManifestState {
        do { _ = try fm.attributesOfItem(atPath: manifestURL(id).path); return .present } catch {
            let e = error as NSError
            if (e.domain == NSCocoaErrorDomain && (e.code == NSFileNoSuchFileError || e.code == NSFileReadNoSuchFileError)) || (e.domain == NSPOSIXErrorDomain && e.code == Int(ENOENT)) { return .missing }
            if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain, u.code == Int(ENOENT) { return .missing }
            return .inaccessible
        }
    }

    public func load(_ id: String) throws -> ImportManifest {
        guard Self.validName(id) else { throw ImportQueueError.badName(id) }
        guard manifestState(id) != .missing else { throw ImportQueueError.noSuchBatch(id) }
        guard let data = try? Data(contentsOf: manifestURL(id)) else { throw ImportQueueError.unreadable(id) }   // there but not readable: damaged, never "gone"
        struct VersionOnly: Decodable { var version: Int? }
        if let v = (try? Self.decoder.decode(VersionOnly.self, from: data))?.version, v > ImportManifest.currentVersion { throw ImportQueueError.newerVersion(id) }
        do {
            let m = try Self.decoder.decode(ImportManifest.self, from: data)
            guard m.batchId == id else { throw ImportQueueError.unreadable(id) }
            return m
        } catch let e as ImportQueueError { throw e } catch { throw ImportQueueError.unreadable(id) }
    }

    /// Read the batch, let `change` alter it, write it back whole. One writer at a time (the app's coordinator); the share extension never touches a committed batch.
    ///
    /// Read-modify-write is one step under a process-wide lock, so two callers (the engine's queue, and the main thread when the system is about to suspend the app) cannot lose each other's
    /// change. Nothing is written when `change` altered nothing, so a look at an unchanged batch costs no write.
    @discardableResult
    public func update(_ id: String, now: Date = Date(), _ change: (inout ImportManifest) -> Void) throws -> ImportManifest {
        Self.writeLock.lock(); defer { Self.writeLock.unlock() }
        let before = try load(id)
        var m = before
        change(&m)
        if m == before { return before }
        m.updatedAt = now
        try Self.writeAtomically(try Self.encoder.encode(m), to: manifestURL(id))
        return m
    }

    private static let writeLock = NSLock()

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
        // Finished batches whose folder could not be removed then (the parent was not writable, a file was in use): removed now if they can be, hidden meanwhile (`list`).
        for name in names where Self.validName(name) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.appendingPathComponent(name).path, isDirectory: &isDir), isDir.boolValue else { continue }
            // No manifest file at all: removal got as far as deleting it. A manifest that is there but cannot be read is damaged, and is kept.
            let finished: Bool
            switch manifestState(name) { case .missing: finished = true; case .present: finished = (try? load(name))?.items.isEmpty ?? false; case .inaccessible: finished = false }
            if finished, (try? remove(name)) != nil { report.removedSaved += 1 }
        }
        for m in (try? list().manifests) ?? [] {
            if m.savedAt != nil { if (try? remove(m.batchId)) != nil { report.removedSaved += 1 } }
            else if let seen = m.seenAt, now.timeIntervalSince(seen) > Self.abandonedAfter { if (try? remove(m.batchId)) != nil { report.removedAbandoned += 1 } }
        }
        return report
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
        /// The account folder's birth date when this was saved: an account made again under the same name is another account and does not inherit what was saved into the old one.
        public var born: Double?
        /// The save this entry belongs to (`import:<batch>[.<generation>]`), and whether that save is still unconfirmed. A PROVISIONAL entry is written BEFORE the box is, so the keys of a save that
        /// is cut off, whose batch is discarded or whose clean-up fails are still held; it counts as "already imported" like a confirmed one. Recovery confirms it (some account holds a scan with
        /// the signature) or removes it (every account was read and none does).
        public var signature: String?
        public var provisional: Bool?
    }
    public var version = 1
    public var entries: [Entry] = []
    public static let keepFor: TimeInterval = 365 * 24 * 3600
    public static let maxEntries = 20_000
    /// A provisional entry nobody could settle (a box that cannot be read) for this long becomes a confirmed one: the conservative way, which holds a later copy for review rather than
    /// allowing a double save.
    public static let provisionalKeepFor: TimeInterval = 30 * 24 * 3600

    /// When any of `keys` was saved into `account`. `currentName` says what an entry's account is called now (nil: it cannot be told, so the entry is not counted); `excluding` leaves
    /// out a batch's own entries (a save cut off between the ledger and the removal must not make the batch's own screenshots look already imported).
    public func savedAt(account: String, keys: [String], excluding: String? = nil, currentName: (Entry) -> String? = { $0.account }) -> Date? { hold(account: account, keys: keys, excluding: excluding, currentName: currentName)?.date }

    /// The latest entry that holds one of `keys` for `account`, and whether EVERY entry that does is provisional (a save that may or may not have reached the box).
    public func hold(account: String, keys: [String], excluding: String? = nil, currentName: (Entry) -> String? = { $0.account }) -> (date: Date, provisionalOnly: Bool)? {
        let wanted = Set(keys)
        let hits = entries.filter { $0.batchId != excluding && wanted.contains($0.key) && currentName($0) == account }
        guard let date = hits.map(\.savedAt).max() else { return nil }
        return (date, hits.allSatisfy { $0.provisional == true })
    }

    /// Keep to `maxEntries`, by the recency of each KEY, not of each entry: a key's protection lasts as long as its most recent import. One pass finds, for each (account, folder birth date, key), its
    /// single newest CONFIRMED entry (a tie in date goes to the later one written, since dates are whole seconds); every other confirmed entry of that key is a duplicate and goes. If it is still
    /// over, the keys whose newest entry is oldest go, one entry each now. A key with any provisional entry is never evicted (it may be the only thing standing between a screenshot and a second
    /// save), and its confirmed entry stays too. One pass and one rebuild, however far over it is.
    mutating func trim() {
        guard entries.count > Self.maxEntries else { return }
        struct K: Hashable { var account: String; var born: Double?; var key: String }
        func k(_ e: Entry) -> K { K(account: e.account, born: e.born, key: e.key) }
        var newest = [K: Int]()
        var protected = Set<K>()
        for (i, e) in entries.enumerated() {
            if e.provisional == true { protected.insert(k(e)); continue }
            if let j = newest[k(e)], entries[j].savedAt > e.savedAt { continue }
            newest[k(e)] = i
        }
        var drop = Set<Int>()
        for (i, e) in entries.enumerated() where e.provisional != true && newest[k(e)] != i { drop.insert(i) }
        var over = entries.count - drop.count - Self.maxEntries
        if over > 0 {
            for (key, i) in newest.sorted(by: { (entries[$0.value].savedAt, $0.value) < (entries[$1.value].savedAt, $1.value) }) where over > 0 && !protected.contains(key) { drop.insert(i); over -= 1 }
        }
        guard !drop.isEmpty else { return }
        entries = entries.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
    }
}

extension ImportQueue {
    var ledgerURL: URL { root.appendingPathComponent(Self.ledgerName) }

    /// The ledger as it is, for looking at (tests, the sheet): an unreadable one shows as empty here. Everything that decides or writes uses `loadLedger`.
    public func ledger() -> ImportLedger { (try? loadLedger()) ?? ImportLedger() }

    /// The ledger; absent is empty, but one that is there and cannot be decoded THROWS (`ledgerUnreadable`) and is copied aside once (`ledger.damaged.json`; `startNewLedger` keeps any further damaged file as `ledger.damaged-<n>.json`), never treated as empty and never
    /// written over.
    public func loadLedger() throws -> ImportLedger {
        guard fm.fileExists(atPath: ledgerURL.path) else { return ImportLedger() }
        if let data = try? Data(contentsOf: ledgerURL), let l = try? Self.decoder.decode(ImportLedger.self, from: data) { return l }
        let copy = root.appendingPathComponent("ledger.damaged.json")
        if !fm.fileExists(atPath: copy.path) { try? fm.copyItem(at: ledgerURL, to: copy) }
        throw ImportQueueError.ledgerUnreadable
    }

    /// Remember that these items were saved into `account`. Called after the box write succeeded; a failure here only means the same screenshot is not recognised later.
    public func recordSaved(_ items: [ImportItem], batchId: String, account: String, epoch: Int? = nil, born: Double? = nil, now: Date = Date()) throws {
        try ledgerFailure?()
        var l = try loadLedger()
        l.entries.removeAll { now.timeIntervalSince($0.savedAt) > ImportLedger.keepFor && $0.provisional != true }
        let known = Set(l.entries.filter { $0.account == account && $0.provisional != true }.map(\.key))
        for item in items { for k in item.keys where !known.contains(k) { l.entries.append(.init(account: account, key: k, batchId: batchId, savedAt: now, epoch: epoch, born: born)) } }
        l.trim()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.writeAtomically(try Self.encoder.encode(l), to: ledgerURL)
    }

    /// Write the keys of a save that is ABOUT to be made, as provisional entries tagged with its signature and the destination account's identity. Called before the box is written; if it
    /// fails the box is not written. Every key of the save is written under THIS save's signature and date, whoever else already holds it (a key another unresolved save has only provisionally must
    /// still be written for this one, and a screenshot saved again renews its protection); a key already written under this signature for this account is not written twice.
    public func recordProvisional(_ items: [ImportItem], batchId: String, signature: String, account: String, epoch: Int?, born: Double?, now: Date = Date()) throws {
        try ledgerFailure?()
        var l = try loadLedger()
        l.entries.removeAll { now.timeIntervalSince($0.savedAt) > ImportLedger.keepFor && $0.provisional != true }
        // Every key of this save is written under ITS signature and date, whoever else already holds it: a key another unresolved save has only provisionally must still be written for this one (or
        // removing that save's entries would lose it), and a screenshot saved again ("Import it again") renews its protection, so the pruning of an older entry cannot leave it unprotected.
        let mine = Set(l.entries.filter { $0.signature == signature && $0.account == account }.map(\.key))
        for item in items { for k in item.keys where !mine.contains(k) {
            l.entries.append(.init(account: account, key: k, batchId: batchId, savedAt: now, epoch: epoch, born: born, signature: signature, provisional: true))
        } }
        // not trimmed here: a provisional entry's key is protected, and the older entries of that key are only redundant once the save is CONFIRMED (a save that never happens must not have cost
        // them). The overflow is as big as the saves still unresolved; `confirmProvisional` trims.
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.writeAtomically(try Self.encoder.encode(l), to: ledgerURL)
    }

    /// Whether the ledger has any entry, provisional or confirmed, under this save's signature: the record that a save was started. nil when the ledger cannot be read (nothing can be said).
    public func hasRecord(ofSave signature: String) -> Bool? {
        guard let l = try? loadLedger() else { return nil }
        return l.entries.contains { $0.signature == signature }
    }

    /// Put an unreadable ledger aside and start an empty one: the damaged file is kept (`ledger.damaged.json`, numbered if one is there already) and nothing is deleted. Earlier imports are no
    /// longer recognised afterwards. Returns where the damaged file went, or nil when the ledger was readable (nothing is done to a good one).
    @discardableResult
    public func startNewLedger() throws -> URL? {
        guard fm.fileExists(atPath: ledgerURL.path) else { return nil }
        if (try? loadLedger()) != nil { return nil }
        var n = 1
        var target = root.appendingPathComponent("ledger.damaged.json")
        // the copy loadLedger keeps stays; the file itself is moved to the next free name
        while fm.fileExists(atPath: target.path) && (try? Data(contentsOf: target)) != (try? Data(contentsOf: ledgerURL)) { n += 1; target = root.appendingPathComponent("ledger.damaged-\(n).json") }
        if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: ledgerURL, to: target) }
        try Self.writeAtomically(try Self.encoder.encode(ImportLedger()), to: ledgerURL)
        return target
    }

    /// The save with this signature reached the box: its provisional entries are confirmed.
    public func confirmProvisional(signature: String) throws {
        try ledgerFailure?(); try ledgerConfirmFailure?()
        var l = try loadLedger()
        guard l.entries.contains(where: { $0.signature == signature && $0.provisional == true }) else { return }
        for i in l.entries.indices where l.entries[i].signature == signature { l.entries[i].provisional = nil }
        l.trim()
        try Self.writeAtomically(try Self.encoder.encode(l), to: ledgerURL)
    }

    /// The save with this signature never reached the box: its provisional entries go, so its screenshots are not held back for something that did not happen.
    public func removeProvisional(signature: String) throws {
        try ledgerFailure?(); try ledgerConfirmFailure?()
        var l = try loadLedger()
        let before = l.entries.count
        l.entries.removeAll { $0.signature == signature && $0.provisional == true }
        guard l.entries.count != before else { return }
        try Self.writeAtomically(try Self.encoder.encode(l), to: ledgerURL)
    }

    /// Provisional entries by save signature, oldest first within each.
    public func provisionalSignatures() -> [String: [ImportLedger.Entry]] {
        Dictionary(grouping: ledger().entries.filter { $0.provisional == true && $0.signature != nil }, by: { $0.signature! })
    }

    /// Mark, in the batch's manifest, every item that is the same screenshot as an earlier one: in this batch, in an older batch still waiting for the same account, or in the
    /// ledger of what that account has saved. Identity is the asset id or the bytes; two screenshots of Pokémon with the same species, CP and IVs are NOT the same screenshot.
    /// An earlier item that failed (or could not be read) does not claim its screenshot: sharing it again is the retry. Idempotent. Returns the updated manifest.
    /// `ledgerAccount` says what a ledger entry's account is called now (see `ImportLedger.savedAt`).
    @discardableResult
    public func markDuplicates(_ batchId: String, now: Date = Date(), owner: @escaping (ImportManifest) -> String? = { $0.account },
                               ledgerAccount: @escaping (ImportLedger.Entry) -> String? = { $0.account }) throws -> ImportManifest {
        // A batch whose last save is unfinished is not an earlier copy of anything: its screenshots are in the box already, and a share of the same screenshot must not wait behind it.
        let others = try list().manifests.filter { $0.batchId != batchId && $0.savedAt == nil && $0.pendingSave == nil }
        // An unreadable ledger is not an empty one: every screenshot is held for the person's say until it can be read.
        let loaded = try? loadLedger()
        let ledger = loaded ?? ImportLedger()
        return try update(batchId, now: now) { m in
            // Batches are compared by whose box they are for NOW (`owner`, from the rename history), never by the name each happened to record; a batch with no known owner is compared with all.
            let mine = owner(m)
            let older = others.filter { o in
                guard (o.createdAt, o.batchId) < (m.createdAt, m.batchId) else { return false }
                let theirs = owner(o)
                return theirs == nil || mine == nil || theirs == mine
            }
            var seen = [String: String]()   // key -> the id that item is known by
            for o in older { for item in o.items where item.duplicateOf == nil && !item.canRetry { for k in item.keys { seen[k] = seen[k] ?? "\(o.batchId)/\(item.id)" } } }
            for i in m.items.indices {
                let item = m.items[i]
                m.items[i].duplicateOf = item.keys.compactMap { seen[$0] }.first
                if m.items[i].duplicateOf == nil && !item.canRetry { for k in item.keys { seen[k] = item.id } }
                let hold = mine.flatMap { ledger.hold(account: $0, keys: item.keys, excluding: m.batchId, currentName: ledgerAccount) }
                m.items[i].alreadyImported = hold?.date
                m.items[i].alreadyImportedMaybe = hold.map { $0.provisionalOnly ? true : nil } ?? nil
                m.items[i].ledgerUnknown = loaded == nil ? true : nil
            }
        }
    }

    /// After a save: keep what still needs the person, delete the staged files of the rest, and remove the batch when nothing is left. Kept: screenshots waiting to be read, failed or
    /// unreadable ones (worth another try), held-back ones, copies that follow a kept one, and any screenshot that was NOT part of the save and was not left out (one the person said to
    /// include after the save was written down stays for the next save). Cleared: what was saved (`saved`), what the person left out (`dropped`), copies of those, screenshots without IVs and
    /// unsupported screens. The next save of what is kept is a new scan, so it gets its own signature (`generation`). Returns the manifest that is left, or nil when the batch was removed.
    @discardableResult
    public func retire(_ batchId: String, saved: Set<String>, dropped: Set<String> = [], now: Date = Date()) throws -> ImportManifest? {
        var gone = [ImportItem]()
        let m = try update(batchId, now: now) { m in
            let finished = saved.union(dropped)
            var keep = Set(m.items.filter { item in
                guard !finished.contains(item.id) else { return false }
                return item.needsReading || item.canRetry || item.heldBack || (item.state == .read && item.duplicateOf == nil)
            }.map(\.id))
            // a copy of a screenshot that stays follows it; a copy of one in another batch waits on that batch; a copy of one that was saved or left out is finished
            for item in m.items where !finished.contains(item.id) && !keep.contains(item.id) {
                if let of = item.duplicateOf, of.contains("/") || keep.contains(of) { keep.insert(item.id) }
            }
            gone = m.items.filter { !keep.contains($0.id) }
            m.items = m.items.filter { keep.contains($0.id) }
            // A hold on a repeat is lifted whenever the screenshot it was a repeat of is no longer in the batch, whether it was saved or left out: a hold pointing at a screenshot that
            // is gone can never be answered. What the repeat is, then, is the box merge's to say (an exact match to a saved Pokémon is that Pokémon, unchanged; a power-up is a
            // question), as for Auto Scan. It is marked, so the repeats are not held against each other again at the next look.
            let kept = Set(m.items.map(\.id))
            for i in m.items.indices { if let r = m.items[i].repeatOf, !kept.contains(r) { m.items[i].repeatOf = nil; m.items[i].holdLifted = true } }
            m.generation += 1
            m.pendingSave = nil
            if m.items.isEmpty { m.savedAt = now }
        }
        for item in gone { try? fm.removeItem(at: stagedURL(batch: batchId, item: item)) }
        if m.items.isEmpty { try? remove(batchId); return nil }
        return m
    }
}

extension ImportQueue {
    /// The person discards one screenshot of a batch (a held-back leftover, say). The batch goes with its last one.
    @discardableResult
    public func removeItem(_ batchId: String, item id: String, now: Date = Date()) throws -> ImportManifest? {
        var gone: ImportItem?
        let m = try update(batchId, now: now) { m in
            gone = m.items.first { $0.id == id }
            m.items.removeAll { $0.id == id }
            for i in m.items.indices where m.items[i].repeatOf == id { m.items[i].repeatOf = nil; m.items[i].holdLifted = true }
        }
        if let gone { try? fm.removeItem(at: stagedURL(batch: batchId, item: gone)) }
        if m.items.isEmpty { try? remove(batchId); return nil }
        return m
    }
}
