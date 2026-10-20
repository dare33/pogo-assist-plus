import Foundation

/// One staged screenshot in a batch. Everything the queue knows about it is here, so a batch survives the app being ended at any moment.
public struct ImportItem: Codable, Equatable, Identifiable {
    public enum State: String, Codable {
        /// Staged, not read yet.
        case pending
        /// Read: name, CP, HP and settled bars. `reading` holds the reader's output.
        case read
        /// The Pokémon was read but its IVs were not (bars not showing or not settled). Never added to the box.
        case ivsMissing
        /// Not a screen the reader supports.
        case unsupported
        /// A detail screen whose identifying parts could not be read.
        case unreadable
        /// The file could not be opened or the read broke off (a fault, not a verdict): worth trying again.
        case failed
    }

    public var id: String
    /// The staged file, inside the batch's folder.
    public var file: String
    /// The Photos asset's local identifier when the picker gave one (the share extension is never given one).
    public var assetId: String?
    /// SHA-256 of the original bytes, and of the staged PNG. Either matching marks the same screenshot; species, CP and IVs never do (genuine twins exist).
    public var sourceHash: String
    public var stagedHash: String
    public var width: Int
    public var height: Int
    public var state: State
    /// Why, in words for the person (everything but `read` and `pending`).
    public var detail: String?
    /// The reader's output as JSON (`FrameReading`), kept so a relaunch does not read the picture again. Opaque to this module.
    public var reading: Data?
    /// Times a read of this item was started. Written before the read, so an item whose read killed the app is not retried forever on its own.
    public var attempts: Int
    /// The same screenshot as an earlier item (same asset or same bytes): the id of that item in this batch, or "batchId/itemId" in another queued batch. Not read twice, not added twice.
    public var duplicateOf: String?
    /// The same screenshot was saved by an earlier import into this account, and when.
    public var alreadyImported: Date?
    /// A different screenshot whose Pokémon has the same species, form, CP, HP and IVs as an earlier item of this batch: a retake of it, or a genuine twin. Held back until the person says.
    public var repeatOf: String?
    /// The person's answer to a held-back item ("this is another Pokémon" / "import it again").
    public var includeAnyway: Bool?

    public init(id: String, file: String, assetId: String? = nil, sourceHash: String, stagedHash: String, width: Int, height: Int, state: State = .pending, detail: String? = nil,
                reading: Data? = nil, attempts: Int = 0, duplicateOf: String? = nil, alreadyImported: Date? = nil, repeatOf: String? = nil, includeAnyway: Bool? = nil) {
        self.id = id; self.file = file; self.assetId = assetId; self.sourceHash = sourceHash; self.stagedHash = stagedHash; self.width = width; self.height = height
        self.state = state; self.detail = detail; self.reading = reading; self.attempts = attempts; self.duplicateOf = duplicateOf; self.alreadyImported = alreadyImported
        self.repeatOf = repeatOf; self.includeAnyway = includeAnyway
    }

    /// The identity keys of the screenshot, for duplicate detection.
    public var keys: [String] {
        var k = [String]()
        if !sourceHash.isEmpty { k.append("h:" + sourceHash) }
        if !stagedHash.isEmpty { k.append("s:" + stagedHash) }
        if let a = assetId, !a.isEmpty { k.append("a:" + a) }
        return k
    }

    /// Waiting to be looked at: not read, or broke off.
    public var needsReading: Bool { state == .pending }
    /// Can be tried again by the person.
    public var canRetry: Bool { state == .failed || state == .unreadable }
    /// Held back for the person's say (a repeat or an earlier import of this screenshot).
    public var heldBack: Bool { hasHold && includeAnyway != true }
    /// Something asks for the person's say (a possible repeat, or a screenshot imported before), whether or not it has been answered yet: the control stays so the answer can be taken back.
    public var hasHold: Bool { state == .read && duplicateOf == nil && (repeatOf != nil || alreadyImported != nil) }
    /// A Pokémon this item will contribute to the review: read in full, not a copy of another item, not held back.
    public var isIncluded: Bool { state == .read && duplicateOf == nil && !heldBack }
}

/// A batch of screenshots waiting in the queue: one share or one pick. Written whole and atomically beside its staged files (`ImportQueue`).
public struct ImportManifest: Codable, Equatable, Identifiable {
    public static let currentVersion = 1

    public enum Origin: String, Codable { case photoPicker, shareExtension }

    public var version: Int
    public var batchId: String
    public var createdAt: Date
    public var updatedAt: Date
    public var origin: Origin
    /// The account whose box this batch is for: the one selected when it was made. nil only when none was (a share made before the first account); the app fills it in
    /// and shows it before anything is saved.
    public var account: String?
    public var items: [ImportItem]
    /// Set just before a batch's files are removed after a successful save, so a removal that was cut off is finished by the next cleanup, never repeated as a save.
    public var savedAt: Date?
    /// How many times part of this batch has been saved and the rest kept (held-back and unreadable screenshots stay queued). Each save is its own scan record, so each has its own signature.
    public var generation: Int = 0
    /// How many account renames the box had recorded when the batch was bound to its account. A name that was renamed away AFTER this, and is now used by another account, is ambiguous
    /// (`BoxStore.resolveAccount`). nil: not stamped yet (a share, until the app first sees it).
    public var renameMark: Int?
    /// When the batch was first shown to the person (the sheet opened with it in the list), and last acted on. Clean-up never removes a batch that has not been shown.
    public var seenAt: Date?
    /// When the bound account's folder was made (seconds since 1970, at full precision: a date in the manifest keeps whole seconds only). A folder made again under the same name (the account was deleted and recreated) is another account: the person is asked.
    public var accountBorn: Double?
    /// The screenshots (item ids) whose Pokémon the person's answers put in the save, written BEFORE the box is written, so a save found already made on relaunch is finished with
    /// exactly what was saved, not with a guess. Cleared once the batch has been retired.
    public var pendingSave: [String]?

    public var id: String { batchId }

    public init(batchId: String, createdAt: Date, origin: Origin, account: String?, items: [ImportItem], savedAt: Date? = nil) {
        self.version = Self.currentVersion; self.batchId = batchId; self.createdAt = createdAt; self.updatedAt = createdAt; self.origin = origin; self.account = account
        self.items = items; self.savedAt = savedAt
    }

    /// The source tag a saved scan carries: also what makes a repeated save of this batch recognisable.
    public var signature: String { "import:" + batchId + (generation > 0 ? ".\(generation)" : "") }

    public var pending: [ImportItem] { items.filter(\.needsReading) }
    public var isRead: Bool { pending.isEmpty }
    public func item(_ id: String) -> ImportItem? { items.first { $0.id == id } }
    public var included: [ImportItem] { items.filter(\.isIncluded) }
    public var heldBack: [ImportItem] { items.filter(\.heldBack) }
    public var duplicates: [ImportItem] { items.filter { $0.duplicateOf != nil } }

    private enum CodingKeys: String, CodingKey { case version, batchId, createdAt, updatedAt, origin, account, items, savedAt, generation, renameMark, seenAt, accountBorn, pendingSave }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        batchId = try c.decode(String.self, forKey: .batchId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        origin = (try? c.decodeIfPresent(Origin.self, forKey: .origin)) ?? .photoPicker
        account = try c.decodeIfPresent(String.self, forKey: .account)
        items = try c.decodeIfPresent([ImportItem].self, forKey: .items) ?? []
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt)
        generation = try c.decodeIfPresent(Int.self, forKey: .generation) ?? 0
        renameMark = try c.decodeIfPresent(Int.self, forKey: .renameMark)
        seenAt = try c.decodeIfPresent(Date.self, forKey: .seenAt)
        accountBorn = try c.decodeIfPresent(Double.self, forKey: .accountBorn)
        pendingSave = try c.decodeIfPresent([String].self, forKey: .pendingSave)
    }
}

extension ImportItem {
    private enum CodingKeys: String, CodingKey {
        case id, file, assetId, sourceHash, stagedHash, width, height, state, detail, reading, attempts, duplicateOf, alreadyImported, repeatOf, includeAnyway
    }

    /// Tolerant: a field a later build added is ignored, one this build expects but the file lacks takes its default, an unknown state reads as pending (read again).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        file = try c.decode(String.self, forKey: .file)
        assetId = try c.decodeIfPresent(String.self, forKey: .assetId)
        sourceHash = try c.decodeIfPresent(String.self, forKey: .sourceHash) ?? ""
        stagedHash = try c.decodeIfPresent(String.self, forKey: .stagedHash) ?? ""
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
        state = (try? c.decodeIfPresent(State.self, forKey: .state)) ?? .pending
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        reading = try c.decodeIfPresent(Data.self, forKey: .reading)
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        duplicateOf = try c.decodeIfPresent(String.self, forKey: .duplicateOf)
        alreadyImported = try c.decodeIfPresent(Date.self, forKey: .alreadyImported)
        repeatOf = try c.decodeIfPresent(String.self, forKey: .repeatOf)
        includeAnyway = try c.decodeIfPresent(Bool.self, forKey: .includeAnyway)
    }
}
