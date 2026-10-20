import SwiftUI
import PhotosUI
import PogoBox
import PogoImport

/// Everything the screens need of screenshot import: the staging of a pick, the queue of batches (the picker's and the share extension's), reading them one image at a time,
/// and the hand-over to the review. The rules about what a screenshot may add are `ScreenshotImporter`'s, in the package, where they are tested; this class only runs it on
/// the engine's queue, keeps what the screens show, and decides WHEN (processing starts by itself, a review never opens over another, nothing is saved without the person).
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
    /// One line for the sheet: what went wrong or what was done for the person without asking.
    @Published var notice: String?

    private var stagingTask: Task<Void, Never>?
    private var readerTask: Task<Void, Never>?
    private var promptedFor = Set<String>()
    private var reviewAfterSheet: String?
    private var didFirstActivation = false

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

    // MARK: the queue

    func refresh() {
        guard available else { return }
        let listing = (try? queue.list()) ?? ImportQueue.Listing(manifests: [], unreadable: [])
        batches = listing.manifests
        damaged = listing.unreadable
        owners = Dictionary(listing.manifests.map { ($0.batchId, importer.owner(of: $0)) }, uniquingKeysWith: { a, _ in a })
    }

    /// The app came to the front (or opened): tidy the queue, and read what the share extension left, showing the sheet when there is something the person has not seen.
    func activate() {
        guard available else { return }
        let report = queue.cleanup()
        if report.removedAbandoned > 0 { notice = "\(report.removedAbandoned) batch\(report.removedAbandoned == 1 ? "" : "es") of screenshots that nobody opened for two weeks \(report.removedAbandoned == 1 ? "was" : "were") removed from the phone. The screenshots are still in Photos." }
        refresh()
        guard !batches.isEmpty else { return }
        startReading()
        if batches.contains(where: { !promptedFor.contains($0.batchId) }) && app.sheet == nil && !app.isReviewing && !app.reviewCoverShown {
            promptedFor.formUnion(batches.map(\.batchId))
            app.sheet = .screenshots
        }
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

    // MARK: picking

    /// The picker returned. Each image is copied out of Photos one at a time (bounded memory), made upright and stripped of its metadata, and the batch is queued; reading then starts.
    func stage(_ picked: [PhotosPickerItem]) {
        guard available, !picked.isEmpty, staging == nil else { return }
        guard let account = app.account else { notice = "Make an account first, then choose screenshots."; return }
        staging = Progress(batch: "", done: 0, total: picked.count)
        notice = nil
        let queue = self.queue
        stagingTask = Task {
            var unusable = 0
            do {
                let builder = try queue.beginBatch(origin: .photoPicker, account: account)
                for (i, item) in picked.enumerated() {
                    if Task.isCancelled { builder.abort(); staging = nil; return }
                    staging?.done = i
                    let asset = item.itemIdentifier
                    guard let data = try? await item.loadTransferable(type: Data.self) else { unusable += 1; continue }
                    // The PNG encode and the hashing are not main-actor work.
                    let ok = await Task.detached(priority: .userInitiated) { (try? builder.add(data: data, assetId: asset)) != nil }.value
                    if !ok { unusable += 1 }
                }
                let m = try builder.commit()
                promptedFor.insert(m.batchId)
                if unusable > 0 { notice = "\(unusable) of the \(picked.count) pictures could not be opened and were left out." }
            } catch {
                notice = unusable == picked.count ? "None of the pictures could be opened. Choose screenshots of Pokémon GO's appraisal screens." : AppModel.plain(error)
            }
            staging = nil
            stagingTask = nil
            refresh()
            startReading()
        }
    }

    // MARK: reading

    /// Read every waiting screenshot, oldest batch first, one image at a time on the engine's queue. Starts by itself; safe to call again while it runs.
    func startReading() {
        guard available, readerTask == nil, batches.contains(where: { !$0.isRead || $0.account == nil }) else { return }
        readerTask = Task {
            let ids = ((try? queue.list())?.manifests ?? []).filter { !$0.isRead || $0.account == nil }.map(\.batchId)
            for id in ids {
                if Task.isCancelled { break }
                await read(batch: id)
                if (try? queue.load(id))?.isRead == false { break }   // stopped or failed outright: leave it queued
            }
            reading = nil
            readerTask = nil
            refresh()
        }
    }

    /// One batch: file it under the selected account if it has none, mark copies, then read the screenshots in turn.
    func read(batch id: String) async {
        let importer = self.importer
        do {
            if let m = try? queue.load(id), m.account == nil, let a = app.account { _ = try? importer.assign(batch: id, to: a) }   // a share made before any account existed
            var m = try await app.worker.run { _ in try importer.prepare(batch: id) }
            let total = m.items.count
            reading = Progress(batch: id, done: total - m.pending.count, total: total)
            refresh()
            while !Task.isCancelled, !m.isRead {
                guard let next = try await app.worker.run({ engine in try importer.readNext(batch: id, engine: engine) }) else { break }
                m = next
                reading = Progress(batch: id, done: total - m.pending.count, total: total)
                refresh()
            }
        } catch {
            notice = AppModel.plain(error)
        }
        reading = nil
        refresh()
    }

    /// Stop after the screenshot being read. What was read is kept; the rest waits in the queue.
    func cancel() {
        stagingTask?.cancel()
        readerTask?.cancel()
        notice = "Stopped. The screenshots that were read are kept; the rest are still queued."
    }

    // MARK: per screenshot and per batch

    func retry(batch: String, item: String? = nil) {
        let importer = self.importer
        Task {
            do {
                _ = try await app.worker.run { _ in
                    if let item { return try importer.retry(batch: batch, item: item) }
                    return try importer.retryAll(batch: batch)
                }
                refresh()
                startReading()
            } catch { notice = AppModel.plain(error) }
        }
    }

    func setIncluded(batch: String, item: String, _ include: Bool) {
        _ = try? importer.setIncluded(batch: batch, item: item, include)
        refresh()
    }

    func assign(batch: String, to account: String) {
        do { _ = try importer.assign(batch: batch, to: account); notice = nil } catch { notice = AppModel.plain(error) }
        refresh()
    }

    func discard(batch: String) {
        try? importer.discard(batch: batch)
        refresh()
        if batches.isEmpty { app.sheet = nil }
    }

    /// The review was closed without saving: nothing was added and the batch stays queued, so a held-back screenshot can still be included, a failed one tried again, or the lot discarded
    /// from the sheet.
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
