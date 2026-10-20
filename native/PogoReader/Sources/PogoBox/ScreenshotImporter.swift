import Foundation
import PogoReader
import PogoImport

/// Screenshot import, from a queued batch to a saved box: read each staged screenshot once, hold back what is not certain, build the review the app already has, and save it
/// as a partial "Add and update" import. It owns no UI and no thread: the app calls `readNext` one image at a time from the engine's queue (so cancelling between images is
/// possible, and the queue stays free for other work), then `prepareReview`, then `save`.
///
/// What a screenshot can and cannot add (the rules this file enforces; `StillReader` and `StillImport` supply the pieces):
///  - a Pokémon is added only from a screenshot read in full: name, CP, HP and settled appraisal bars, and CP, HP and bars that fit a level. A screenshot without IVs, of another
///    screen, or unreadable adds nothing and is reported with the reason; it never costs the other screenshots anything.
///  - a copy of the same screenshot (same Photos asset or same bytes, in this batch, an older queued batch or an earlier saved import) is not read twice or added twice.
///  - a DIFFERENT screenshot whose Pokémon has the same species, CP, HP and IVs as an earlier one in the batch, or the same species and IVs at another CP, is held back until
///    the person says "this is another Pokémon" (genuine twins exist; so do retakes and a power-up between two screenshots). Nothing is merged on resemblance.
///  - everything else goes through `BoxMerge` as a partial scan: saved Pokémon the screenshots do not show are untouched, uncertain matches become questions, hand corrections stay.
public final class ScreenshotImporter {
    public typealias ImageReader = (_ staged: URL, _ label: String) throws -> StillOutcome

    public static let source = "screenshot import"
    /// An item whose read was started this many times without finishing (the app was ended during it) is not started again on its own.
    public static let maxAttempts = 2

    public enum Failure: Error, LocalizedError, Equatable {
        case noAccount
        case accountGone(String)
        case accountUnknown
        /// The name this batch was made for was renamed away and another account has it now: the person chooses.
        case accountAmbiguous(old: String, renamedTo: String)
        /// The batch's account cannot be confirmed (it was deleted and made again under the same name, or the renames since cannot be followed any more): the person chooses.
        case accountUnconfirmed(String)
        case nothingToImport
        case notYetRead
        /// The account's saved scans could not be read well enough to tell whether this batch was already saved; saving now could make a second copy.
        case cannotTellIfSaved

        public var errorDescription: String? {
            switch self {
            case .noAccount: return "These screenshots are not for any account yet. Choose the account whose box they belong to."
            case .accountGone(let n): return "The account these screenshots were for (\(n)) is no longer on this phone. Choose another account for them, or discard them."
            case .accountUnknown: return "The accounts on this phone could not be listed, so the screenshots cannot be filed yet."
            case .accountUnconfirmed(let why): return why
            case .accountAmbiguous(let old, let now): return "These screenshots were for the account that was called \(old) and is now \(now), but there is another account called \(old) now. Choose which box they belong to."
            case .nothingToImport: return "None of the screenshots gave a Pokémon that can be added."
            case .notYetRead: return "The screenshots have not all been read yet."
            case .cannotTellIfSaved: return "The box could not be checked for an earlier save of these screenshots, so nothing was saved. Try again."
            }
        }
    }

    public let queue: ImportQueue
    public let library: BoxLibrary
    private let customReader: ImageReader?
    private var vision: StillReader?

    public init(queue: ImportQueue, library: BoxLibrary, reader: ImageReader? = nil) {
        self.queue = queue; self.library = library; customReader = reader
    }

    // MARK: account

    public enum Owner: Equatable {
        case account(String), unassigned, gone(String), unknown, ambiguous(old: String, renamedTo: String)
        /// An account of that name exists but it cannot be confirmed to be the one the batch was made for; `why` says so, for the person.
        case unconfirmed(name: String, why: String)
        /// The current name of the account when it is certain, else nil.
        public var name: String? { if case .account(let n) = self { return n } else { return nil } }
    }

    /// Whose box the batch is for NOW: the account it was made for, followed through the renames made since it was bound (`renameMark`), BEFORE asking whether the name exists, so an
    /// account renamed away and a new one given its old name are told apart by asking the person (`.ambiguous`). Never the account that happens to be selected.
    public func owner(of m: ImportManifest) -> Owner {
        guard let recorded = m.account else { return .unassigned }
        switch library.store.resolveAccount(recorded, since: m.renameMark) {
        case .found(let name):
            // A folder made again under the same name is another account, even though no rename happened.
            if let born = m.accountBorn, let now = library.store.accountCreated(name), abs(now - born) > 0.001 {
                return .unconfirmed(name: name, why: "The account \(name) was deleted and made again since these screenshots were queued, so they may belong to another box. Choose which one.")
            }
            return .account(name)
        case .indeterminate: return .unconfirmed(name: recorded, why: "It is too long since these screenshots were queued to tell what has happened to the account \(recorded) since. Choose which box they belong to.")
        case .gone: return .gone(recorded)
        case .unknown: return .unknown
        case .ambiguous(let old, let now): return .ambiguous(old: old, renamedTo: now)
        }
    }

    /// Give the batch to an account that exists (a share made before the first account, or an account that has gone). Refused for one that does not.
    @discardableResult
    public func assign(batch: String, to account: String) throws -> ImportManifest {
        guard case .found(let name) = library.store.lookupAccount(account), let mark = library.store.renameCount else { throw Failure.accountGone(account) }
        let born = library.store.accountCreated(name)
        return try queue.update(batch) { $0.account = name; $0.renameMark = mark; $0.accountBorn = born }   // bound again, to this account, as the renames stand now
    }

    // MARK: reading

    /// Before a batch is read: mark the screenshots that are copies of others, and of earlier saved imports.
    @discardableResult
    public func prepare(batch: String) throws -> ImportManifest {
        let store = library.store
        try queue.markDuplicates(batch, owner: { [unowned self] in self.owner(of: $0).name }, ledgerAccount: { e in
            // What the entry's account is called now; an entry whose account name has become ambiguous or gone is not counted.
            if case .found(let name) = store.resolveAccount(e.account, since: e.epoch) { return name }
            return nil
        })
        // A share is bound to its account's rename history when the app first sees it.
        if let m = try? queue.load(batch), m.renameMark == nil, let a = m.account, let mark = store.renameCount {
            let born = store.accountCreated(a)
            try queue.update(batch) { $0.renameMark = mark; $0.accountBorn = $0.accountBorn ?? born }
        }
        // A screenshot that was passed over as a copy of one in another batch and is not a copy any more (that batch was discarded) was never read: it is read now.
        return try queue.update(batch) { m in
            for i in m.items.indices where m.items[i].duplicateOf == nil && m.items[i].state == .read && m.items[i].reading == nil {
                m.items[i].state = .pending; m.items[i].detail = nil; m.items[i].attempts = 0
            }
        }
    }

    /// `prepare` for every queued batch, returning those that now have something to read. A batch whose screenshots were all copies of another queued batch's is read as soon as that
    /// batch is discarded or saved, with nobody having to ask.
    public func prepareAll() throws -> [ImportManifest] {
        try queue.list().manifests.compactMap { m in
            guard let p = try? prepare(batch: m.batchId) else { return nil }
            return p.isRead && p.account != nil ? nil : p
        }
    }

    // The read in progress, so the app can give its attempt back when the system is about to suspend it.
    private let flightLock = NSLock()
    private var flight: (batch: String, item: String)?
    public var inFlight: (batch: String, item: String)? { flightLock.lock(); defer { flightLock.unlock() }; return flight }
    private func setInFlight(_ f: (batch: String, item: String)?) { flightLock.lock(); flight = f; flightLock.unlock() }

    /// The system is taking the app's time away mid-read (the background task expired): the read in hand was interrupted, not a read that broke the app, so its attempt is not used.
    /// Safe to call from the main thread while the engine's queue is reading: manifest writes are one step under a lock.
    public func refundInterruptedRead() {
        guard let f = inFlight else { return }
        _ = try? queue.update(f.batch) { if let i = $0.items.firstIndex(where: { $0.id == f.item }), $0.items[i].attempts > 0, $0.items[i].state == .pending { $0.items[i].attempts -= 1 } }
    }

    private func reader() -> ImageReader {
        if let customReader { return customReader }
        return { [unowned self] url, label in
            if self.vision == nil { self.vision = try StillReader() }
            return try self.vision!.read(contentsOf: url, label: label)
        }
    }

    /// Read the next screenshot that has not been read, write the result, and say what the batch looks like now; nil when none is waiting. A copy of another screenshot is
    /// not read at all. When the last one is done, the repeats in the batch are worked out.
    @discardableResult
    public func readNext(batch: String, engine: CoreEngine) throws -> ImportManifest? {
        let m = try queue.load(batch)
        guard let item = m.items.first(where: { $0.needsReading }) else { return nil }
        if item.duplicateOf != nil {
            // Same screenshot as another: nothing to read. It keeps the state `read` only so the batch counts as finished; it is never included (`isIncluded`).
            return try finishIfDone(engine, try queue.update(batch) { if let i = $0.items.firstIndex(where: { $0.id == item.id }) { $0.items[i].state = .read; $0.items[i].detail = "Same screenshot as another one." } })
        }
        if item.attempts >= Self.maxAttempts {
            return try finishIfDone(engine, try set(batch, item.id, .failed, "Reading this screenshot was cut off twice (the app was closed). Try it again."))
        }
        // Counted on disk BEFORE the read: a read that ends the app is not started a third time by itself.
        try queue.update(batch) { if let i = $0.items.firstIndex(where: { $0.id == item.id }) { $0.items[i].attempts += 1 } }
        setInFlight((batch, item.id))
        defer { setInFlight(nil) }
        let url = queue.stagedURL(batch: batch, item: item)
        let outcome: StillOutcome
        do { outcome = try reader()(url, item.id) }
        catch { return try finishIfDone(engine, try set(batch, item.id, .failed, "The staged copy of this screenshot could not be opened (\(error)). Choose it again.")) }
        switch outcome {
        case .unsupported(let why): return try finishIfDone(engine, try set(batch, item.id, .unsupported, why))
        case .unreadable(let why): return try finishIfDone(engine, try set(batch, item.id, .unreadable, why))
        case .fault(let why): return try finishIfDone(engine, try set(batch, item.id, .failed, why))
        case .ivsMissing(let reading, let why):
            return try finishIfDone(engine, try set(batch, item.id, .ivsMissing, why.message, reading: reading))
        case .read(let reading):
            switch StillImport.solve(reading, engine: engine) {
            case .row: return try finishIfDone(engine, try set(batch, item.id, .read, nil, reading: reading))
            case .ivsMissing(let why): return try finishIfDone(engine, try set(batch, item.id, .ivsMissing, why, reading: reading))
            case .unreadable(let why): return try finishIfDone(engine, try set(batch, item.id, .unreadable, why, reading: reading))
            }
        }
    }

    private func set(_ batch: String, _ itemId: String, _ state: ImportItem.State, _ detail: String?, reading: FrameReading? = nil) throws -> ImportManifest {
        let data = reading.flatMap { try? JSONEncoder().encode($0) }
        return try queue.update(batch) {
            guard let i = $0.items.firstIndex(where: { $0.id == itemId }) else { return }
            $0.items[i].state = state; $0.items[i].detail = detail; $0.items[i].reading = data
        }
    }

    private func finishIfDone(_ engine: CoreEngine, _ m: ImportManifest) throws -> ImportManifest {
        guard m.isRead else { return m }
        return try markRepeats(m, engine: engine)
    }

    /// Work out which items repeat an earlier one in the batch. Needs the solver to see each row, so it runs when a batch has been read in full and again after a retry.
    private func markRepeats(_ m: ImportManifest, engine: CoreEngine) throws -> ImportManifest {
        let rows = rows(of: m.items.filter { $0.state == .read }, engine: engine)
        let found = StillImport.repeats(items: m.items, rows: rows)
        return try queue.update(m.batchId) { m in
            let ids = Set(m.items.map(\.id))
            for i in m.items.indices {
                // A hold the person has not answered stays while the screenshot it points at is still in the batch, even if that one cannot be read at this moment (it was retried and
                // failed): a hold is only ever lifted by the person, by the other screenshot being saved (`ImportQueue.retire`), or by the two no longer being alike.
                let id = m.items[i].id
                if let now = found[id] { m.items[i].repeatOf = now }
                else if let was = m.items[i].repeatOf, m.items[i].includeAnyway == nil, ids.contains(was), !(rows[was] != nil && rows[id] != nil) { /* keep */ }
                else { m.items[i].repeatOf = nil }
            }
        }
    }

    private func rows(of items: [ImportItem], engine: CoreEngine) -> [String: ScanRow] {
        var out = [String: ScanRow]()
        for item in items where item.duplicateOf == nil {
            guard let reading = StillImport.decode(item), case .row(let row) = StillImport.solve(reading, engine: engine) else { continue }
            out[item.id] = row
        }
        return out
    }

    /// Everything a read screenshot needs to be tried again (a failure, or an unreadable). The person's choice; the read is not repeated by itself.
    @discardableResult
    public func retry(batch: String, item: String) throws -> ImportManifest {
        try queue.update(batch) {
            guard let i = $0.items.firstIndex(where: { $0.id == item }), $0.items[i].canRetry else { return }
            $0.items[i].state = .pending; $0.items[i].detail = nil; $0.items[i].reading = nil; $0.items[i].attempts = 0; $0.items[i].repeatOf = nil
        }
    }

    /// Retry everything that can be tried again.
    @discardableResult
    public func retryAll(batch: String) throws -> ImportManifest {
        let m = try queue.load(batch)
        var last = m
        for item in m.items where item.canRetry { last = try retry(batch: batch, item: item.id) }
        return last
    }

    /// The person's answer for a held-back screenshot: it is another Pokémon / import it again (`true`), or leave it out (`false`).
    @discardableResult
    public func setIncluded(batch: String, item: String, _ include: Bool) throws -> ImportManifest {
        try queue.update(batch) { if let i = $0.items.firstIndex(where: { $0.id == item }) { $0.items[i].includeAnyway = include ? true : nil } }
    }

    /// Read every pending screenshot in turn; `shouldStop` is asked between screenshots. For callers that are not in a hurry to give the engine's queue back (the tests, a tool).
    @discardableResult
    public func readAll(batch: String, engine: CoreEngine, shouldStop: () -> Bool = { false }) throws -> ImportManifest {
        try prepare(batch: batch)
        while !shouldStop(), try readNext(batch: batch, engine: engine) != nil {}
        return try queue.load(batch)
    }

    // MARK: review

    /// A batch read and merged against its account's box, ready for the review screen.
    public struct Prepared {
        public var manifest: ImportManifest
        public var account: String
        public var outcome: ScanPipeline.Outcome
        public var plan: BoxMerge.Plan
        public var base: [BoxEntry]
        public var boxSeq: Int?
        /// The item each scanned row came from, row by row (so a question can say which screenshot it is about).
        public var rowItems: [String]
        /// Screenshots that were included when read but did not solve again (the app's rules changed in between): reported, not added.
        public var dropped: [String]
    }

    public func prepareReview(batch: String, engine: CoreEngine) throws -> Prepared {
        var m = try prepare(batch: batch)
        guard m.isRead else { throw Failure.notYetRead }
        guard case .account(let account) = owner(of: m) else {
            switch owner(of: m) {
            case .unassigned: throw Failure.noAccount
            case .gone(let n): throw Failure.accountGone(n)
            case .ambiguous(let old, let now): throw Failure.accountAmbiguous(old: old, renamedTo: now)
            case .unconfirmed(_, let why): throw Failure.accountUnconfirmed(why)
            default: throw Failure.accountUnknown
            }
        }
        if m.account != account { m = try queue.update(batch) { $0.account = account; $0.renameMark = library.store.renameCount; $0.accountBorn = library.store.accountCreated(account) } }   // followed a rename: keep the new name
        var rows = [ScanRow](), ids = [String](), dropped = [String]()
        for item in m.items where item.isIncluded {
            guard let reading = StillImport.decode(item), case .row(var row) = StillImport.solve(reading, engine: engine) else { dropped.append(item.id); continue }
            row.frames = row.frames.map { var f = $0; f.frame = item.id; return f }
            rows.append(row); ids.append(item.id)
        }
        guard !rows.isEmpty else { throw Failure.nothingToImport }
        let current = try library.current(account: account)
        let base = current?.entries ?? []
        let outcome = StillImport.outcome(rows: rows, screenshots: m.items.count)
        let plan = BoxMerge.plan(scanned: outcome.scan.rows, unmatched: [], into: base, kind: .partial, scanDate: m.createdAt, gameMaster: try .bundled())
        return Prepared(manifest: m, account: account, outcome: outcome, plan: plan, base: base, boxSeq: current?.seq, rowItems: ids, dropped: dropped)
    }

    // MARK: saving

    public enum Saved { case saved(BoxSnapshot), alreadySaved }

    /// Save a reviewed import: one box version and one scan record, once. Asks the account whether this batch (its signature) is already in it first, so a save that was cut off
    /// after the box was written, or a second tap, or a relaunch, finishes the clean-up instead of adding the Pokémon again. `commitFailure` is for tests.
    public func save(_ p: Prepared, resolutions: [Int: BoxMerge.Resolution], engine: CoreEngine, now: Date = Date(), commitFailure: (() throws -> Void)? = nil, afterCommit: (() throws -> Void)? = nil) throws -> Saved {
        switch library.scanAlreadySaved(account: p.account, signature: p.manifest.signature) {
        case .saved: finish(p, saved: (try? queue.load(p.manifest.batchId))?.pendingSave, now: now); return .alreadySaved
        case .unknown: throw Failure.cannotTellIfSaved
        case .notSaved: break
        }
        // Refused (not written over it) if the box has changed since the review was prepared: the caller prepares again.
        let entries = try BoxMerge.apply(p.plan, resolutions: resolutions, keepGone: [], to: p.base, engine: engine)
        // Which screenshots this save contains, written down BEFORE the box is: a save found already made after a cut-off is finished with exactly these.
        let ids = Self.savedItems(p, resolutions: resolutions)
        try queue.update(p.manifest.batchId) { $0.pendingSave = Array(ids).sorted() }
        let n = p.outcome.scan.rows.count
        let note = "Screenshot import, \(n) Pokémon"
        let snapshot = try library.commitScan(p.outcome.scan, entries: entries, account: p.account, scanDate: p.plan.scanDate, source: Self.source, kind: .partial, note: note,
                                              expectedCurrentSeq: .some(p.boxSeq),
                                              reviewActions: ScanReportBuilder.reviewLines(plan: p.plan, resolutions: resolutions, keepGone: [], base: p.base),
                                              sourceSignature: p.manifest.signature, commitFailure: commitFailure).snapshot
        try afterCommit?()   // tests: the app ends here
        finish(p, saved: Array(ids), now: now)
        return .saved(snapshot)
    }

    /// The screenshots a save puts in the box: those whose row was not left out, and the copies in the batch of them.
    static func savedItems(_ p: Prepared, resolutions: [Int: BoxMerge.Resolution]) -> Set<String> {
        let rows = Set(p.rowItems.enumerated().filter { resolutions[$0.offset] != .leaveOut }.map(\.element))
        let copies = p.manifest.items.filter { item in item.duplicateOf.map { !$0.contains("/") && rows.contains($0) } ?? false }.map(\.id)
        return rows.union(copies)
    }

    /// After a save (or the discovery that one was made): remember the screenshots that were saved, then keep only what still needs the person and remove the rest of the batch
    /// (`ImportQueue.retire`). `saved` is what was written down before the box was written; nil (no such record) saves nothing in the ledger and keeps every screenshot, which can
    /// only make the person look at them again. Neither failing undoes the save; a removal cut off is finished by `cleanup`.
    private func finish(_ p: Prepared, saved: [String]?, now: Date) {
        let m = p.manifest
        let ids = Set(saved ?? [])
        if let account = m.account, !ids.isEmpty { try? queue.recordSaved(m.items.filter { ids.contains($0.id) }, batchId: m.batchId, account: account, epoch: library.store.renameCount, now: now) }
        _ = try? queue.retire(m.batchId, saved: ids, now: now)
    }

    /// The person threw the batch away: nothing is added and nothing is remembered.
    public func discard(batch: String) throws { try queue.remove(batch) }

    /// The person discards one screenshot of a batch.
    public func discardItem(batch: String, item: String) throws { try queue.removeItem(batch, item: item) }

    /// The person was shown these batches, or acted on one.
    public func markSeen(_ batches: [String]) { queue.markSeen(batches) }
}
