import SwiftUI
import PhotosUI
import PogoBox
import PogoImport

/// Everything the screens need of screenshot import: the staging of a pick, the queue of batches (the picker's and the share extension's), reading them one image at a time,
/// and the hand-over to the review. The rules about what a screenshot may add are `ScreenshotImporter`'s, in the package, where they are tested; this class only runs it on
/// the engine's queue, keeps what the screens show, and decides WHEN (processing starts by itself, a review never opens over another, nothing is saved without the person).
///
/// Every write to a batch's manifest goes through `app.worker`, the one serial queue, so the main actor and the reader never write the same file at once; the main actor only reads.
@MainActor
final class ImportModel: ObservableObject {
    struct Progress: Equatable { var batch: String; var done: Int; var total: Int }

    private unowned let app: AppModel
    let queue: ImportQueue
    let importer: ScreenshotImporter
    /// False when the app group's folder cannot be used (an unsigned build on a device): the share extension could not reach the app either.
    let available: Bool

    @Published private(set) var batches: [ImportManifest] = []
    @Published private(set) var owners: [String: ScreenshotImporter.Owner] = [:]
    /// Damaged batch folders: reported, never deleted for the person.
    @Published private(set) var damaged: [String] = []
    /// Screenshots being copied out of Photos (the picker's, one at a time).
    @Published private(set) var staging: Progress?
    /// Screenshots being read.
    @Published private(set) var reading: Progress?
    /// A batch being merged against the box for its review.
    @Published private(set) var preparing: String?
    /// Reading is paused because the app is not in front. It carries on when it is.
    @Published private(set) var paused = false
    private var gate = ReadingGate() { didSet { paused = gate.paused } }
    /// One line for the sheet: what went wrong or what was done for the person without asking.
    @Published var notice: String?

    private var stagingTask: Task<Void, Never>?
    private var readerTask: Task<Void, Never>?
    private var promptedFor = Set<String>()
    private var reviewAfterSheet: String?

    var isWorking: Bool { staging != nil || reading != nil || preparing != nil }
    /// Batches waiting for the person (everything in the queue has not been saved).
    var waitingCount: Int { batches.count }

    init(app: AppModel) {
        self.app = app
        let container = SharedStore.containerURL
        available = container != nil
        queue = ImportQueue(container: container ?? URL(fileURLWithPath: "/dev/null/pogo-assist-group", isDirectory: true))
        importer = ScreenshotImporter(queue: queue, library: app.library)
    }

    /// Run `work` on the engine's queue (where every manifest write is made) and wait for it.
    private func serial<T>(_ work: @escaping () throws -> T) async throws -> T { try await app.worker.run { _ in try work() } }

    // MARK: the queue

    func refresh() {
        guard available else { return }
        let listing = (try? queue.list()) ?? ImportQueue.Listing(manifests: [], unreadable: [])
        batches = listing.manifests
        damaged = listing.unreadable
        owners = Dictionary(listing.manifests.map { ($0.batchId, importer.owner(of: $0)) }, uniquingKeysWith: { a, _ in a })
    }

    /// The app came to the front (or opened): tidy the queue, and read what the share extension left. The sheet opens by itself for batches the person has not seen, but never in
    /// front of a scan that has finished or is waiting to be reviewed: that comes first, and this is looked at again when it is done (`flowEnded`).
    func activate() {
        guard available else { return }
        let importer = self.importer
        Task {
            let report = try? await serial { importer.queue.cleanup() }
            if let n = report?.removedAbandoned, n > 0 { notice = "\(n) batch\(n == 1 ? "" : "es") of screenshots that you were shown and left alone for two weeks \(n == 1 ? "was" : "were") removed from the phone. The screenshots are still in Photos." }
            refresh()
            guard !batches.isEmpty else { return }
            startReading()
            let unseen = batches.filter { !promptedFor.contains($0.batchId) }
            if ImportPolicy.shouldAutoOpenSheet(unseenBatches: unseen.count, sheetOpen: app.sheet != nil, canOpenReview: app.canOpenImportReview, scanPendingPickup: app.scanPendingPickup) {
                promptedFor.formUnion(unseen.map(\.batchId))
                app.sheet = .screenshots
            }
        }
    }

    /// A scan's review ended: what was queued behind it can be shown now.
    func flowEnded() { activate() }

    /// The sheet is showing: these batches have been seen, which is what starts their two weeks.
    func shown() {
        let ids = batches.map(\.batchId)
        promptedFor.formUnion(ids)
        let importer = self.importer
        Task { _ = try? await serial { importer.markSeen(ids) } }
    }

    /// The sheet went away: open the review the person asked for, or look again at what is waiting.
    func sheetClosed() {
        guard let batch = reviewAfterSheet else { return }
        reviewAfterSheet = nil
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)   // let the sheet finish leaving before the review covers the screen
            await review(batch: batch)
        }
    }

    /// The app moved between the front and the background. Reading stops after the screenshot in hand when it leaves (that one is finished under a background task, so an
    /// interruption never leaves a half-read image that would count against its retries) and carries on when it returns.
    func scenePhaseChanged(background: Bool) {
        if gate.scenePhaseChanged(background: background) { startReading() }
    }

    // MARK: picking

    /// The picker returned. Each image is copied out of Photos one at a time (bounded memory), made upright, scaled to what the reader needs and stripped of its metadata, and the
    /// batch is queued; reading then starts. A pick that is cancelled commits nothing.
    func stage(_ picked: [PhotosPickerItem]) {
        guard available, !picked.isEmpty, staging == nil else { return }
        guard let account = app.account else { notice = "Make an account first, then choose screenshots."; return }
        staging = Progress(batch: "", done: 0, total: picked.count)
        notice = nil
        let queue = self.queue, mark = app.library.store.renameCount, born = app.library.store.accountCreated(account)
        stagingTask = Task {
            defer { staging = nil; stagingTask = nil }
            let builder: ImportQueue.Builder
            do { builder = try queue.beginBatch(origin: .photoPicker, account: account, renameMark: mark, accountBorn: born) } catch { notice = AppModel.plain(error); return }
            let result = await PickStager.stage(count: picked.count, builder: builder,
                load: { i in
                    guard let data = try? await picked[i].loadTransferable(type: Data.self) else { return nil }
                    return (data, picked[i].itemIdentifier)
                },
                isCancelled: { Task.isCancelled },
                progress: { [weak self] i in Task { @MainActor in self?.staging?.done = i } })
            switch result {
            case .cancelled:
                notice = "Cancelled. Nothing was added."
                return
            case .committed(let m, let unusable):
                promptedFor.insert(m.batchId)
                if unusable > 0 { notice = "\(unusable) of the \(picked.count) pictures could not be opened and \(unusable == 1 ? "was" : "were") left out." }
            case .failed(let error, let unusable):
                notice = unusable == picked.count ? "None of the pictures could be opened. Choose screenshots of Pokémon GO's appraisal screens." : AppModel.plain(error)
            }
            refresh()
            startReading()
        }
    }

    // MARK: reading

    /// Read every waiting screenshot, oldest batch first, one image at a time on the engine's queue. Starts by itself; safe to call again while it runs. First every batch is
    /// looked at again, so one whose screenshots were copies of a batch that has since gone is read now.
    func startReading() {
        guard available, readerTask == nil, gate.mayRead else { return }
        let importer = self.importer
        readerTask = Task {
            defer { reading = nil; readerTask = nil; refresh() }
            // Look again after each round: finishing one batch (or the person discarding one meanwhile) can make another readable, and nothing should be left waiting for a nudge.
            var done = Set<String>()
            while !Task.isCancelled, gate.mayRead {
                let waiting = (try? await serial { try importer.prepareAll() }) ?? []
                refresh()
                let loose = ((try? queue.list())?.manifests ?? []).filter { !$0.isRead || $0.account == nil }.map(\.batchId)
                var seen = Set<String>()
                let next = (waiting.map(\.batchId) + loose).filter { seen.insert($0).inserted && !done.contains($0) }
                guard !next.isEmpty else { break }
                for id in next {
                    if Task.isCancelled || !gate.mayRead { break }
                    done.insert(id)
                    await read(batch: id)
                    if (try? queue.load(id))?.isRead == false { break }   // stopped, paused or failed outright: leave it queued
                }
            }
        }
    }

    /// One batch: file it under the selected account if it has none, mark copies, then read the screenshots in turn.
    func read(batch id: String) async {
        let importer = self.importer
        defer { reading = nil; refresh() }
        do {
            if let m = try? queue.load(id), m.account == nil, let a = app.account { _ = try? await serial { try importer.assign(batch: id, to: a) } }   // a share made before any account existed
            var m = try await serial { try importer.prepare(batch: id) }
            let total = m.items.count
            reading = Progress(batch: id, done: total - m.pending.count, total: total)
            refresh()
            while !Task.isCancelled, gate.mayRead, !m.isRead {
                // A screenshot that has been started is finished even if the app leaves the front: iOS is asked for time to do it.
                // If the time runs out mid-read the read is not counted against its retries, and nothing further starts.
                var task = UIBackgroundTaskIdentifier.invalid
                task = UIApplication.shared.beginBackgroundTask(withName: "pogo-read-screenshot") { [weak self] in
                    MainActor.assumeIsolated {
                        self?.importer.refundInterruptedRead()
                        self?.gate.timeExpired()
                        if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
                    }
                }
                defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task) } }
                guard let next = try await app.worker.run({ engine in try importer.readNext(batch: id, engine: engine) }) else { break }
                m = next
                reading = Progress(batch: id, done: total - m.pending.count, total: total)
                refresh()
            }
        } catch {
            notice = AppModel.plain(error)
        }
    }

    /// Stop after the screenshot being read. What was read is kept; the rest waits in the queue.
    func cancel() {
        if stagingTask != nil { stagingTask?.cancel() }   // the pick says what became of it
        if readerTask != nil {
            readerTask?.cancel()
            notice = "Stopped. The screenshots that were read are kept; the rest are still queued."
        }
    }

    // MARK: per screenshot and per batch

    func retry(batch: String, item: String? = nil) {
        let importer = self.importer
        Task {
            do {
                _ = try await serial {
                    if let item { return try importer.retry(batch: batch, item: item) }
                    return try importer.retryAll(batch: batch)
                }
                refresh()
                startReading()
            } catch { notice = AppModel.plain(error) }
        }
    }

    func setIncluded(batch: String, item: String, _ include: Bool) {
        let importer = self.importer
        Task { _ = try? await serial { try importer.setIncluded(batch: batch, item: item, include) }; refresh() }
    }

    /// Throw one screenshot away (a held-back leftover, say); the batch goes with its last one.
    func discardItem(batch: String, item: String) {
        let importer = self.importer
        Task { _ = try? await serial { try importer.discardItem(batch: batch, item: item) }; refresh(); if batches.isEmpty { app.sheet = nil } }
    }

    func assign(batch: String, to account: String) {
        let importer = self.importer
        Task {
            do { _ = try await serial { try importer.assign(batch: batch, to: account) }; notice = nil } catch { notice = AppModel.plain(error) }
            refresh()
        }
    }

    func discard(batch: String) {
        let importer = self.importer
        Task {
            try? await serial { try importer.discard(batch: batch) }
            refresh()
            if batches.isEmpty { app.sheet = nil } else { startReading() }   // what was a copy of it can be read now
        }
    }

    /// The review was closed without saving: nothing was added and the batch stays queued, so a held-back screenshot can still be included, a failed one tried again, or the lot
    /// discarded from the sheet.
    func reviewClosedWithoutSaving() {
        refresh()
        notice = "Nothing was added. The screenshots are still here: change your mind about a held-back one, or discard them."
        Task { try? await Task.sleep(nanoseconds: 450_000_000); if app.sheet == nil && !app.isReviewing { app.sheet = .screenshots } }
    }

    // MARK: review

    /// The person pressed "Review": close the sheet, then open the review (`sheetClosed`).
    func openReview(batch: String) {
        if app.sheet == nil { Task { await review(batch: batch) } } else { reviewAfterSheet = batch; app.sheet = nil }
    }

    /// Merge a read batch against its account's box and open the review. Reads whatever is still waiting first.
    func review(batch id: String) async {
        guard preparing == nil else { return }
        guard app.canOpenImportReview else {
            notice = "Another scan or an unfinished change to the box needs your attention first. The screenshots stay queued."
            app.sheet = .screenshots
            return
        }
        preparing = id
        await readerTask?.value   // the reading that is already under way, if any
        if (try? queue.load(id))?.isRead != true { await read(batch: id) }
        let importer = self.importer
        let t0 = Date()
        do {
            let p = try await app.worker.run { engine in try importer.prepareReview(batch: id, engine: engine) }
            preparing = nil
            app.presentImportReview(p, seconds: Date().timeIntervalSince(t0))
        } catch {
            preparing = nil
            notice = AppModel.plain(error)
            refresh()
            app.sheet = .screenshots
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
