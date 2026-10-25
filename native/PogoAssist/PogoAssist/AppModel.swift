import SwiftUI
import Combine
import UserNotifications
import PogoBox
import PogoReader
import PogoImport

/// Receives the pause notification's "End scan" action (the app is woken for it) and lets notifications show while the app is open.
final class NotificationActions: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationActions()
    /// Set at launch (the app delegate), never from a view-owned object: when the system launches the app only to deliver the "End scan" action, no screen exists yet, and the
    /// delegate must already be in place for the response to be delivered.
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
        ScanNotifier.registerCategories()
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Scoped to the scan the notification was about: an old notification's action does nothing to a later scan.
        if response.actionIdentifier == ScanNotification.finishActionID, let scan = response.notification.request.content.userInfo["scan"] as? Int { ReaderSettings.requestFinish(scan: scan) }
        completionHandler()
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

/// Everything the screens share: the accounts, the selected account's box and its advice, the scan in progress and the
/// scan waiting for review. All heavy work (JavaScript, merge, advice, file writes) runs on `worker`'s one queue; this class
/// only holds results and starts that work.
@MainActor
final class AppModel: ObservableObject {
    enum AdviceState: Equatable { case none, computing, ready(BoxAdvice), failed(String) }

    /// A finished scan, read and merged against the selected account's box, waiting for Save or Discard.
    struct Review {
        var account: String
        var kind: BoxStore.Kind
        var outcome: ScanPipeline.Outcome
        var plan: BoxMerge.Plan
        /// Changes whenever `plan` or `base` is replaced (a new review, another scan kind, a refresh against a changed box), so what the screens derive from them can be kept until then.
        var planToken = UUID()
        var resolutions: [Int: BoxMerge.Resolution] = [:]
        var base: [BoxEntry]
        var storageCount: Int?
        var signature: String
        var mergeSeconds: Double
        /// How the scan was paged, kept with the saved scan.
        var paging: StoredPaging?
        /// Set when this is a saved scan being read again: the box is the one before that scan was saved.
        var reread: RereadPlan?
        /// Saved Pokémon the scan did not see that the person marked for removal. Nothing is marked at first: they are all kept (the owner's rule: nothing is
        /// removed without the person choosing it).
        var markedForRemoval: Set<String> = []
        /// What `BoxMerge.apply` is given: every not-seen Pokémon that is not marked.
        var keepGone: Set<String> { BoxMerge.keepSet(plan: plan, resolutions: resolutions, markedForRemoval: markedForRemoval) }
        /// When this unsaved scan's report was sent, and what was sent; recorded on the scan when it is saved.
        var reportSentAt: Date?
        var reportHash: String?
        /// The current box version this review was prepared against (nil: there was none). A save is refused if the box has moved on.
        var boxSeq: Int?
        /// A filtered pass (`plan.pass`) whose rows mostly matched nothing in the box asks "Was this a <kind> search?" before it is saved. `searchConfirmed`: the person said yes.
        var searchConfirmed = false
        var askingSearch = false
        /// The extension ended this scan itself because the end of the list was reached.
        var endedAtListEnd = false
        /// The person ended the scan, or a pause went unanswered until the time limit (`BroadcastState`); both are false for a saved scan read again, whose end the replay log tells (`ScanEnding`).
        var stoppedByPerson = false
        var stoppedByTimeout = false
        /// Why the review chose Add and update although a full scan was asked for (`ScanKindAdvice`), or nil.
        var kindNote: String?
        /// What `ScanKindAdvice` said about a full scan of this result (nil for a saved scan read again).
        var advice: ScanKindAdvice.Decision?
        /// This review's own copy of the scan's replay log (`PendingScanStore.take`, kept on disk until the review is saved or discarded): the review reads, saves, reports and shares only from it, because the shared log is
        /// rewritten by the next broadcast. Nil for a saved scan read again (its log is the saved one) and for the DEBUG seeded reviews.
        var log: URL?
        /// Where a scan the extension ended itself stopped and what to do (`ScanStop.summary`), shown once at the top of the review.
        var stopSummary: String?
        /// Set when this review is a screenshot import (`ScreenshotImporter`): the batch, its screenshots and the rows' origins. It is always an Add and update review, saved through the
        /// importer (never `commitScan` with a replay log), and its source is "screenshot import", not "broadcast".
        var importPrepared: ScreenshotImporter.Prepared?
    }

    enum ScanFlow {
        case idle
        case processing(String)
        case review(Review)
        /// The log could not be read or the engine failed. `signature` is the log, so Discard can mark it done.
        case failed(message: String, signature: String)
    }

    let worker = EngineWorker()
    let library: BoxLibrary
    /// "Get ready to scan" progress (`SetupProgress`) and taking the player back to the game after a broadcast starts (`GameOpener`).
    /// Both are made on first use (after a test's reset of the defaults) and tell the screens that watch the model when they change.
    private var forwarded: [AnyCancellable] = []
    lazy var setup: SetupProgress = {
        let s = SetupProgress(commandsMade: { [unowned self] in self.commandSetMade })
        forwarded.append(s.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
        return s
    }()
    lazy var game: GameOpener = {
        let g = GameOpener()
        forwarded.append(g.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
        return g
    }()

    @Published var accounts: [String] = []
    @Published var account: String? { didSet { UserDefaults.standard.set(account, forKey: Keys.account); ReaderSettings.scanAccount = account; if account != oldValue { rescanCount = nil } } }
    @Published var snapshot: BoxSnapshot?
    @Published var advice: AdviceState = .none
    @Published var flow: ScanFlow = .idle { didSet { if case .idle = flow { scanDonePending = false; dropCopy(); screenshots.flowEnded() } } }
    /// The review's private copy of its scan's log, kept on disk (`PendingScanStore`) until that review is saved or discarded, so it survives a relaunch. `state` is the
    /// broadcast's state file as it was when the scan ended, which the next broadcast overwrites; `kind` and `date` are what the scan was asked to be and when it ended.
    private struct ScanCopy { var signature: String; var url: URL; var state: BroadcastState?; var kind: BoxStore.Kind; var date: Date?; var account: String; var pass: String? }
    private var scanCopy: ScanCopy?
    /// A copy is being made off the main actor, or a waiting scan is being looked at: the one-second timer starts nothing else, and a rename waits.
    private var copying = false
    private var reopening = false
    private var busyWithScan: Bool { copying || reopening }
    /// A reading of the scan under review is going on (for the unfinished-reading mark, `scenePhaseChanged`).
    private var readingScan = false
    /// A copy that failed is not retried before this, and its failure is said once per scan.
    private var copyRetryAfter: Date?
    private var copyFailureShownFor: String?
    /// A scan kept on disk that is not open for review: left by an earlier run, or finished while its account or box was not ready. No other scan is started until it is saved or
    /// discarded. Read from disk once when found, not every second. `damaged`: something is kept that cannot be opened (the person can only discard it).
    struct WaitingScan: Equatable { var signature: String; var account: String; var damaged: Bool; var reason: String? = nil }
    @Published private(set) var waitingScan: WaitingScan?
    private var waitingShownFor: String?
    private var autoSelectedFor: String?
    private let pendingStore: PendingScanStore
    static let damagedScanSignature = "pending-damaged"
    private static var damagedPrefix: String { damagedScanSignature }
    /// A scan that has just ended is being read or has been read, and its Done screen has not been left for the review yet (`ScanDone`): the review cover stays
    /// closed until `openReview()`. Cleared when the flow ends, and when reading fails (the failed state goes straight to the cover). Other entries to the review
    /// (a saved scan read again, retry after a failure) never set it.
    @Published var scanDonePending = false
    @Published var message: String?
    @Published var history: [BoxSnapshot.Header] = []
    @Published var previous: BoxSnapshot.Header?
    /// What the last Save changed, for the Saved panel at the top of Box (see `SaveSummary`).
    @Published var lastSave: SaveSummary?
    @Published var exportURL: URL?
    /// Files to hand to the share sheet (a saved scan's log and result).
    /// What the share sheet is offering; the notification permission is asked when it is dismissed (never over the sheet).
    @Published var shareURLs: [URL] = [] { didSet { if !oldValue.isEmpty, shareURLs.isEmpty, !pagedByHand, commandSetMade { askForNotificationsOnce() } } }
    @Published var busy: String?
    /// The box could not be read: set instead of showing an empty box. Scans cannot be reviewed or saved until it is resolved.
    @Published var boxProblem: String?
    /// The newest version came from a newer app: no restore is offered (it would roll the box back), only "update the app".
    @Published var boxNeedsNewerApp = false
    /// Application Support could not be resolved at launch, so there is nowhere to keep a box (`BoxExportFile.boxesRoot`). Shown as a box problem.
    private(set) var storageMissing = false
    /// A rename that was cut off could not be finished or undone (`BoxStore.recoverRename` failed): shown as a box problem, scanning is paused, and no new rename starts. The journal
    /// is kept and the recovery tried again at every box load.
    @Published private(set) var recoveryProblem: String?
    nonisolated static func recoveryText(_ error: Error) -> String { "A rename of an account was cut off and could not be finished yet (\(plain(error))) Your boxes have not been deleted. The app tries again each time it opens a box." }

    @Published var scanKind: BoxStore.Kind { didSet { UserDefaults.standard.set(scanKind.rawValue, forKey: Keys.kind); if scanKind == .full { scanPass = nil }; refreshReaderSettings(); if scanKind != oldValue { rescanCount = nil } } }
    /// The filtered pass chosen on the Scan screen ("Special scan"), or nil. A pass is a partial scan: choosing one sets Add and update underneath, and choosing Full scan clears it.
    @Published var scanPass: ScanPass? {
        didSet {
            if let scanPass { UserDefaults.standard.set(scanPass.rawValue, forKey: Keys.pass) } else { UserDefaults.standard.removeObject(forKey: Keys.pass) }
            if scanPass != nil, scanKind != .partial { scanKind = .partial }
            refreshReaderSettings()
            if scanPass != oldValue { rescanCount = nil }
        }
    }
    /// "Re-scan N" was pressed in the Box: how many Pokémon are to be checked. Held only for the next scan and never saved. It goes when a scan starts, when the scan kind or the
    /// options change, when the account changes and when the Scan screen closes (see `startRescan`), so it cannot name a command for a later, unrelated scan.
    @Published var rescanCount: Int? { didSet { if rescanCount == nil { rescanShown = nil } } }
    /// How many Pokémon the re-scan's game search shows (the ones to check it covers plus the others it also matches); the command is sized from this. Lives and dies with `rescanCount`.
    private(set) var rescanShown: Int?
    /// The command size a re-scan is sized for (nil: above the largest, or no re-scan).
    var rescanCommandSize: Int? { rescanShown.flatMap { VoiceCommandFile.rescanSize(shown: $0) } }
    /// Sets Add and update and records the re-scan; the root view opens the Scan screen on the change. The kind is set first because changing it drops the count.
    /// `shown` sizes the command (`ScanWords.current`) without writing into the remembered Add and update number, so the next ordinary scan is not sized for this one.
    func startRescan(count: Int, shown: Int) {
        scanPass = nil
        scanKind = .partial
        rescanCount = count
        rescanShown = shown
    }
    /// The storage count of a full scan, remembered per account (editable); it picks which command to say.
    @Published var storageCountText: String { didSet { if let a = account { UserDefaults.standard.set(storageCountText, forKey: Keys.count + "." + a) }; refreshReaderSettings(); if storageCountText != oldValue { rescanCount = nil } } }

    /// "How many Pokémon to scan?" for Add and update, remembered per account like the storage count; empty means `defaultPartialCount`.
    @Published var partialCountText: String { didSet { if let a = account { UserDefaults.standard.set(partialCountText, forKey: Keys.partial + "." + a) }; if partialCountText != oldValue { rescanCount = nil } } }
    nonisolated static let defaultPartialCount = 200

    /// The eggs shown in the game's storage, typed for a Full scan (0 to `StorageCountRules.maxEggSlots`), remembered per account; empty means the flat allowance.
    @Published var eggText: String { didSet { if let a = account { UserDefaults.standard.set(eggText, forKey: Keys.eggs + "." + a) }; refreshReaderSettings(); if eggText != oldValue { rescanCount = nil } } }

    /// The stardust the person has, typed on the Hub's Everything screen and remembered per account; nil until entered. It is not read from the game.
    var stardust: Int? {
        get { account.flatMap { UserDefaults.standard.object(forKey: Keys.stardust + "." + $0) as? Int } }
        set {
            guard let a = account else { return }
            objectWillChange.send()
            if let n = newValue { UserDefaults.standard.set(n, forKey: Keys.stardust + "." + a) } else { UserDefaults.standard.removeObject(forKey: Keys.stardust + "." + a) }
        }
    }

    // The broadcast, as the extension last reported it.
    /// A scan going live ends a re-scan suggestion (`rescanCount`).
    @Published var broadcast: BroadcastState? { didSet { if rescanCount != nil, live { rescanCount = nil } } }
    @Published var now = Date()
    enum Sheet: String, Identifiable { case settings, diagnostics, screenshots; var id: String { rawValue } }
    /// Settings, Diagnostics or the screenshot import. While one is open a finished scan waits (it cannot be presented underneath); it is picked up on close.
    @Published var sheet: Sheet? { didSet { if sheet == nil { checkForFinishedScan(); screenshots.sheetClosed() } } }
    /// Screenshot import: the picker's staging, the queue of batches (including those the share extension made), reading and the hand-over to the review.
    lazy var screenshots: ImportModel = {
        let m = ImportModel(app: self)
        forwarded.append(m.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
        return m
    }()
    /// A broadcast scan has finished (or died) and has not been through review yet: it is about to be picked up, and screenshots must not open in front of it.
    var scanPendingPickup: Bool { (broadcast.map { $0.finished || endedWithoutFinish } ?? false) && ReplayMarker.unprocessedSignature() != nil }
    /// A screenshot review can be opened now: nothing else holds the review screen, the box files or the account names.
    var canOpenImportReview: Bool { !isReviewing && !renaming && !busyWithScan && !live && waitingScan == nil && recoveryProblem == nil && !storageMissing }
    private var holdReview: Bool { sheet != nil }
    private var timer: Timer?

    private enum Keys { static let account = "selectedAccount", kind = "scanKind", pass = "scanPass", count = "storageCount", partial = "partialCount", eggs = "eggCount", stardust = "stardust", pace = "voicePaceV2", hand = "pagedByHand", voice = "voiceLast.", set = "voiceSet." }

    // MARK: - "Make scans better"

    /// Which scan a report is about: the one on the review screen (not saved yet), or a saved scan.
    enum ReportTarget: Identifiable, Equatable {
        case review
        case saved(String)
        var id: String { if case .saved(let s) = self { return s } else { return "review" } }
    }
    enum ReportState: Equatable { case idle, sending, sent, failed(String) }

    @Published var reportTarget: ReportTarget? { didSet { reportState = .idle } }
    @Published var reportState: ReportState = .idle
    private let ledger = DefaultsLedger()

    /// The button is shown only when the upload store is configured in this build.
    var reportsEnabled: Bool { ReportSupport.config != nil }

    /// The report's input for a target, with the user's note. Reads files, so call it on the worker's queue or accept a short pause.
    private func reportInput(_ target: ReportTarget, note: String?) throws -> (input: ScanReportInput, previousHash: String?, previousSentAt: Date?) {
        let app = ReportSupport.appInfo, device = ReportSupport.deviceInfo
        switch target {
        case .review:
            guard case .review(let r) = flow else { throw BoxStore.Failure.notFound(account: "", id: "review") }
            let url = r.reread?.replayURL ?? r.log
            let log = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            let changes = r.outcome.changes.map { "\($0.kind.rawValue): \($0.detail)" }
            let input = ScanReportInput(replayLog: log, result: r.outcome.scan, kind: r.kind, scanDate: r.plan.scanDate, storageCount: r.storageCount, paging: r.paging, pace: r.outcome.pace,
                                        refineChanges: changes, review: ScanReportBuilder.reviewLines(plan: r.plan, resolutions: r.resolutions, keepGone: r.keepGone, base: r.base),
                                        afterwards: [], notIncluded: ["The scan was not saved yet, so nothing is known about what happens after it."], note: note, app: app, device: device)
            return (input, r.reportHash, r.reportSentAt)
        case .saved(let id):
            guard let a = account else { throw BoxStore.Failure.badAccountName }
            let scan = try library.store.load(account: a, id: id)
            let files = try library.store.files(account: a, id: id)
            let log = try files.replay.map { try String(contentsOf: $0, encoding: .utf8) } ?? ""
            var missing = [String]()
            if files.replay == nil { missing.append("The replay log was not kept for this scan.") }
            if scan.reviewActions == nil { missing.append("What was answered at review was not kept for this scan.") }
            let input = ScanReportInput(replayLog: log, result: ScanResult(rows: scan.rows, review: scan.review, unmatched: scan.unmatched), kind: scan.kind, scanDate: scan.scanDate, storageCount: scan.storageCount,
                                        paging: scan.paging, pace: ScanPace.measure(rows: scan.rows), refineChanges: scan.refineChanges ?? [], review: scan.reviewActions ?? [],
                                        afterwards: (try? library.editsAfter(account: a, scanId: id)) ?? [],
                                        notIncluded: missing + ["Corrections made to Pokémon from earlier scans, and 'These values are right'."], note: note, app: app, device: device)
            return (input, scan.reportHash, scan.reportSentAt)
        }
    }

    func sendReport(_ target: ReportTarget, note: String) async {
        guard let config = ReportSupport.config else { reportState = .failed(ScanReportUploader.Failure.notConfigured.localizedDescription); return }
        reportState = .sending
        do {
            let (input, previousHash, previousSentAt) = try reportInput(target, note: note)
            let built = try await worker.run { _ in try ScanReportBuilder.build(input) }
            let uploader = ScanReportUploader(config: config, transport: ReportSupport.transport, ledger: ledger)
            _ = try await uploader.send(built, previousHash: previousHash, previousSentAt: previousSentAt)
            let now = Date()
            switch target {
            case .review: if case .review(var r) = flow { r.reportSentAt = now; r.reportHash = built.contentHash; flow = .review(r) }
            case .saved(let id):
                // On the library's one queue, like every other write to the scan files.
                if let a = account { let store = library.store, hash = built.contentHash;
                    do { try await worker.run { _ in try store.markReportSent(account: a, id: id, at: now, hash: hash) } }
                    catch { message = "The report was sent, but the app could not record that it was: \(Self.plain(error)). The same scan may be offered again." }
                    loadScans() }
            }
            reportState = .sent
        } catch {
            reportState = .failed(Self.plain(error))
        }
    }

    /// The files to share instead when sending fails: the saved scan's result and log, or the unsaved scan's log.
    func reportShareFiles(_ target: ReportTarget) -> [URL] {
        switch target {
        case .saved(let id): if let s = scans.first(where: { $0.id == id }) { return shareFiles(for: s) } else { return [] }
        case .review:
            guard case .review(let r) = flow, let url = r.reread?.replayURL ?? r.log else { return [] }
            return [url]
        }
    }

    // MARK: - the Voice Control command

    /// What the last command made for an account was built for. The app cannot know whether it was imported on the phone.
    struct VoiceRecord: Codable, Equatable { var storageCount: Int; var covers: Int; var pace: VoiceCommandFile.Pace; var date: Date; var screen: String? }

    /// What the one-time set was made for on this phone (per account, kept like the single commands' records).
    struct SetRecord: Codable, Equatable { var kind: VoiceCommandFile.SetKind; var date: Date; var screen: String? }

    /// The person paged by hand, not with a command: the paging beat means nothing, so twins are not judged from it. Off by default.
    /// The choice made BEFORE the scan on the Scan screen: "Page with the voice command" (the default) or "Page by hand". Stored; the extension reads it
    /// when the broadcast starts (no automatic end for hand paging) and the review reads what the extension was told.
    @Published var pagedByHand: Bool { didSet { refreshReaderSettings() } }

    /// The person's own choice, stored. Until they choose, the paging is by hand while no command set exists on this phone, and by the command once it does.
    func choosePaging(byHand: Bool) {
        UserDefaults.standard.set(byHand, forKey: Keys.hand); pagedByHand = byHand
        if !byHand { askForNotificationsOnce() }
    }

    /// Asked once, when the person first chooses to page with the voice command or makes the commands (not at launch): the broadcast extension posts a local notification with
    /// sound when it ends a scan by itself. A refusal changes nothing else: the scan still ends and the result is waiting in the app. Nothing is sent anywhere.
    func askForNotificationsOnce() {
        guard !UserDefaults.standard.bool(forKey: "askedForNotifications") else { return }
        UserDefaults.standard.set(true, forKey: "askedForNotifications")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    func restorePaging() { pagedByHand = (UserDefaults.standard.object(forKey: Keys.hand) as? Bool) ?? ScanKindAdvice.defaultsToHand(commandSetMade: commandSetMade) }
    /// The command set was made on this phone (any account) for this screen kind.
    var commandSetMade: Bool { deviceSetCache.values.joined().contains { $0.kind == setKind && (setKind == .swipe || $0.screen == screenLabel) } }

    /// Tell the broadcast extension whether the next scan is paged by a command (it then ends the scan itself at the end of the list) and at what period.
    func refreshReaderSettings() {
        ReaderSettings.autoEndPeriod = ScanKindAdvice.autoEndPeriod(wantsCommand: !pagedByHand, commandSetMade: commandSetMade, pace: pace)
        // Only a Full scan uses the count and the eggs, and only a Full scan may pause; an Add-and-update scan ends at the end wait and remembers neither.
        ReaderSettings.scanIsFull = scanKind == .full
        ReaderSettings.scanKind = scanKind.rawValue
        ReaderSettings.scanPass = scanPass?.rawValue
        ReaderSettings.scanAccount = account   // an account chosen in an earlier run is set at launch without going through its didSet
        ReaderSettings.storageCount = scanKind == .full ? storageCount : nil
        ReaderSettings.eggCount = scanKind == .full ? eggCount : nil
        ReaderSettings.commandSizes = VoiceCommandFile.setSizes
    }

    /// "Finish now" while a scan is paused: the extension ends it on its next heartbeat.
    func finishPausedScanNow() { if let id = broadcast?.scanId, id != 0 { ReaderSettings.requestFinish(scan: id) } }

    // MARK: - notifications the extension may not get shown

    /// The event (this scan's start time and its event number) the fallback has already dealt with, kept across launches so a relaunch never posts an old event again. The
    /// event number restarts at 1 with each scan, so the scan's start time is part of the key.
    private static let handledKey = "handledScanEvent"
    /// How long the fallback waits before it looks for the extension's own notification: the extension writes its state first and posts a moment after.
    static let fallbackGraceSeconds = 6.0

    /// The extension posts its own notification at a pause or an end (iOS delivers it, seen on a device, but silently under Do Not Disturb unless the app is allowed through).
    /// When the app sees the event (alive in the background, or opened) it waits a few seconds, and posts the same notification itself only if none with that identifier is
    /// delivered or pending. Same identifier, so even a race leaves one; the handled key makes it once per event.
    func postFallbackNotificationIfNeeded(_ s: BroadcastState?) {
        guard let s, s.eventSeq > 0, s.scanId != 0, s.commandPeriod != nil else { return }
        // Resumed or finished: no pause notification (or its button) is left behind. Done once, on the change from paused to not paused, not on every refresh.
        if s.paused { pausedScanSeen = s.scanId } else if pausedScanSeen == s.scanId { pausedScanSeen = nil; ScanNotifier.removePauseNotifications(scan: s.scanId) }
        let key = "\(s.scanId)#\(s.eventSeq)"
        guard UserDefaults.standard.string(forKey: Self.handledKey) != key else { return }
        let n: ScanNotification
        if s.paused {
            n = .paused(scan: s.scanId, event: s.eventSeq, read: s.readCount, storageCount: s.storageCount, eggCount: s.eggCount, lastName: s.pausedCard, lastCP: nil, sizes: VoiceCommandFile.setSizes, limitSeconds: s.pauseLimitSeconds)
        } else if s.endedAtListEnd || s.stoppedByTimeout {
            let last = s.rows.last
            n = .stopped(scan: s.scanId, event: s.eventSeq, read: s.rows.count, lastName: last?.name, lastCP: last?.cp)
        } else { return }
        UserDefaults.standard.set(key, forKey: Self.handledKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fallbackGraceSeconds) {
            // The state is read again first: a pause notice is only posted if that pause is still the current, unresumed one (the scan may have resumed, finished or been
            // replaced while the app waited); a stop notice only if that scan is still the one that ended.
            // The same test is repeated after the notification lookup, which is asynchronous: the pause may have ended while it ran.
            func stillCurrent() -> Bool {
                guard let now = SharedStore.read(), now.scanId == s.scanId else { return false }
                if s.paused { return now.paused && now.eventSeq == s.eventSeq }
                return now.endedAtListEnd || now.stoppedByTimeout
            }
            guard stillCurrent() else { return }
            ScanNotifier.exists(n.identifier) { exists in if !exists, stillCurrent() { ScanNotifier.post(n) } }
        }
    }
    private var pausedScanSeen: Int?
    /// The last command made for each single mode of the selected account (older app versions made one file per scan; still checked for the wrong-screen warning).
    @Published var voiceRecords: [VoiceCommandFile.Pace: VoiceRecord] = [:]
    @Published var setRecord: SetRecord?
    /// The records of every account on this phone, read from UserDefaults when they change (not on every render).
    private var deviceVoiceCache = [String: [(pace: VoiceCommandFile.Pace, screen: String?)]]()
    private var deviceSetCache = [String: [(kind: VoiceCommandFile.SetKind, screen: String?)]]()
    private func refreshDeviceRecords() { deviceVoiceCache = Self.deviceVoiceRecords(); deviceSetCache = Self.deviceSetRecords() }

    /// Tap on a checked screen, swipe elsewhere: the set's kind, and the pace every command of it pages at (the hint the reader gets).
    var setKind: VoiceCommandFile.SetKind { .forScreen(tapAvailable: tapAvailable) }
    var pace: VoiceCommandFile.Pace { setKind.pace }

    /// The command to say for a full scan: the smallest size covering the typed count, nil when no count (or one above 5,000, see `countAboveLargest`).
    var commandSize: Int? { storageCount.flatMap { VoiceCommandFile.setSize(covering: $0) } }
    /// The typed Add and update number, 1 to 10,000; nil when empty or not usable (`partialCountProblem` says why).
    var partialCount: Int? { if case .valid(let n) = StorageCount.parse(partialCountText) { return n } else { return nil } }
    var partialCountProblem: String? { StorageCount.problem(for: partialCountText) }
    /// What the Add and update command has to cover: the typed number, else 200.
    var partialWanted: Int { partialCount ?? Self.defaultPartialCount }
    var countAboveLargest: Bool { (storageCount ?? 0) > (VoiceCommandFile.setSizes.last ?? 0) }
    /// Minutes the command of this size takes, as the Python's estimate has it.
    func estimatedMinutes(size: Int) -> Int { Int((VoiceCommandFile.setSizing(size: size, kind: setKind).estimatedSeconds / 60).rounded()) }

    /// What the Scan screen says about the set, or nil: it has not been made on this phone yet (by any account, for this screen kind).
    var commandWarning: String? {
        let made = deviceSetCache.values.joined().contains { $0.kind == setKind && (setKind == .swipe || $0.screen == screenLabel) }
        return made ? nil : "The command set has not been made on this phone yet. Get the commands and import them, or Voice Control will not know \"Pogo scan 300\" and the others."
    }

    /// Screen size in points, for the tap position check.
    var screenSize: CGSize { UIScreen.main.bounds.size }
    var offeredPaces: [VoiceCommandFile.Pace] { VoiceCommandFile.Pace.offered(tapAvailable: tapAvailable) }
    var tapAvailable: Bool { VoiceCommandFile.tapPoint(width: Double(screenSize.width), height: Double(screenSize.height)) != nil }

    /// The typed storage count, 1 to 10,000, read without overflow; nil when empty or not usable (`storageCountProblem` says why).
    var storageCount: Int? { if case .valid(let n) = StorageCount.parse(storageCountText) { return n } else { return nil } }
    /// A Full scan cannot be started until the count the game shows is typed (and usable).
    var fullScanNeedsCount: Bool { ScanEndDecision.fullScanNeedsCount(isFull: scanKind == .full, storageCount: storageCount) }
    var storageCountProblem: String? { StorageCount.problem(for: storageCountText) }
    /// The typed egg count, 0 to `maxEggSlots`; nil when empty or not usable (`eggProblem` says why).
    var eggCount: Int? { Int(eggText.trimmingCharacters(in: .whitespaces)).flatMap { StorageCountRules.validEggs($0) } }
    var eggProblem: String? {
        let t = eggText.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || eggCount != nil ? nil : "Type a whole number of eggs from 0 to \(StorageCountRules.maxEggSlots)."
    }

    /// "440x956 iPhone": the screen this command would be made for.
    var screenLabel: String { VoiceCommandFile.screenLabel(width: Double(screenSize.width), height: Double(screenSize.height), isPad: UIDevice.current.userInterfaceIdiom == .pad) }

    /// Every tap command made for this account is checked against the current screen, whatever pace is selected: on an unchecked
    /// screen the pace is forced to Swipe, but a tap command made earlier (Display Zoom turned on since, a restore onto another phone) is
    /// still installed in Voice Control.
    var tapCommandsOnOtherScreens: [VoiceCommandFile.Pace] {
        var all = deviceVoiceCache
        // What was just made for the selected account counts even before it is read back.
        all[account ?? "", default: []].append(contentsOf: voiceRecords.map { (pace: $0.key, screen: $0.value.screen) })
        return TapCommandCheck.onOtherScreens(accounts: all, current: screenLabel)
    }

    /// The voice records of every account on this device (Voice Control's commands are device-wide), from the stored keys `voiceLast.<account>.<pace>`.
    static func deviceVoiceRecords() -> [String: [(pace: VoiceCommandFile.Pace, screen: String?)]] {
        var out = [String: [(pace: VoiceCommandFile.Pace, screen: String?)]]()
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix(Keys.voice) {
            let rest = key.dropFirst(Keys.voice.count)
            guard let dot = rest.lastIndex(of: "."), let pace = VoiceCommandFile.Pace(rawValue: String(rest[rest.index(after: dot)...])),
                  let data = value as? Data, let rec = try? JSONDecoder().decode(VoiceRecord.self, from: data) else { continue }
            out[String(rest[..<dot]), default: []].append((pace: pace, screen: rec.screen))
        }
        return out
    }
    /// A TAP set made for another screen, on any account of this device.
    var tapSetOnOtherScreen: Bool {
        var all = deviceSetCache
        if let r = setRecord { all[account ?? "", default: []].append((kind: r.kind, screen: r.screen)) }
        return TapCommandCheck.setOnOtherScreens(records: all.values.flatMap { $0 }, current: screenLabel)
    }
    var tapCommandWarning: String? { TapCommandCheck.warning(for: tapCommandsOnOtherScreens, set: tapSetOnOtherScreen) }

    /// The set records of every account on this device, from the stored keys `voiceSet.<account>`.
    static func deviceSetRecords() -> [String: [(kind: VoiceCommandFile.SetKind, screen: String?)]] {
        var out = [String: [(kind: VoiceCommandFile.SetKind, screen: String?)]]()
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix(Keys.set) {
            guard let data = value as? Data, let rec = try? JSONDecoder().decode(SetRecord.self, from: data) else { continue }
            out[String(key.dropFirst(Keys.set.count)), default: []].append((kind: rec.kind, screen: rec.screen))
        }
        return out
    }

    func loadVoiceRecord() {
        voiceRecords = [:]; setRecord = nil
        defer { refreshDeviceRecords() }
        guard let a = account else { return }
        eggText = UserDefaults.standard.string(forKey: Keys.eggs + "." + a) ?? ""
        storageCountText = UserDefaults.standard.string(forKey: Keys.count + "." + a) ?? ""
        partialCountText = UserDefaults.standard.string(forKey: Keys.partial + "." + a) ?? ""
        setRecord = UserDefaults.standard.data(forKey: Keys.set + a).flatMap { try? JSONDecoder().decode(SetRecord.self, from: $0) }
        for p in VoiceCommandFile.Pace.allCases {
            if let data = UserDefaults.standard.data(forKey: Keys.voice + a + "." + p.rawValue), let r = try? JSONDecoder().decode(VoiceRecord.self, from: data) { voiceRecords[p] = r }
        }
    }

    /// The device's language for the command, as Voice Control writes it (en_AU).
    static var voiceLocale: String {
        Locale.current.identifier.split(separator: "@").first.map { $0.replacingOccurrences(of: "-", with: "_") } ?? "en_AU"
    }

    /// Make the one file with the whole set of commands and hand it to the share sheet (Save to Files, AirDrop). Done once per phone.
    func getCommandSet() async {
        let kind = setKind
        let tap = kind == .tap ? VoiceCommandFile.tapPoint(width: Double(screenSize.width), height: Double(screenSize.height)) : nil
        let width = Double(screenSize.width), height = Double(screenSize.height), locale = Self.voiceLocale, label = screenLabel
        busy = "Making the commands"
        defer { busy = nil }
        do {
            let url = try await worker.run { _ -> URL in
                let data = try VoiceCommandFile.makeSet(kind: kind, locale: locale, tap: tap, screenWidth: width, screenHeight: height)
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent(VoiceCommandFile.setFileName(kind: kind, screen: label))
                try data.write(to: url, options: .atomic)
                return url
            }
            if let a = account {
                let rec = SetRecord(kind: kind, date: Date(), screen: label)
                if let d = try? JSONEncoder().encode(rec) { UserDefaults.standard.set(d, forKey: Keys.set + a) }
                setRecord = rec
                refreshDeviceRecords()
                restorePaging()   // the commands now exist: the default choice becomes the command
            }
            shareURLs = [url]
        } catch { message = "The commands could not be made: \(Self.plain(error))" }
    }

    init() {
        let root = BoxExportFile.boxesRoot
        // No place for the boxes: the library points at a path nothing can be written to (never the temporary folder), and `loadBox` shows the problem.
        storageMissing = root == nil
        let libraryRoot = root ?? URL(fileURLWithPath: "/dev/null/pogo-assist-boxes", isDirectory: true)
        // The UI test starts from a clean install each time: it passes this argument and the app forgets everything first.
        if CommandLine.arguments.contains("-uitest-reset") {
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            if let root { try? FileManager.default.removeItem(at: root) }
            if let d = BoxExportFile.pendingDirectory { PendingScanStore(directory: d).clear() }
            SharedStore.clear()
            if let c = SharedStore.containerURL {
                try? FileManager.default.removeItem(at: c.appendingPathComponent("replay.processed"))
                try? FileManager.default.removeItem(at: ImportQueue(container: c).root)   // queued screenshots
            }
        }
        library = BoxLibrary(root: libraryRoot)
        pendingStore = PendingScanStore(directory: BoxExportFile.pendingDirectory ?? URL(fileURLWithPath: "/dev/null/pogo-assist-pending", isDirectory: true))
        let storedKind = BoxStore.Kind(rawValue: UserDefaults.standard.string(forKey: Keys.kind) ?? "") ?? .full
        scanKind = storedKind
        scanPass = storedKind == .partial ? ScanPass(stored: UserDefaults.standard.string(forKey: Keys.pass)) : nil
        eggText = ""
        partialCountText = ""
        storageCountText = ""   // read per account by loadVoiceRecord once the account is known
        pagedByHand = true   // restorePaging() below: by hand until the commands exist, unless the person chose
        // A rename that was cut off by the app being ended is finished or undone before accounts are listed. Nothing else is running yet, so it is safe here.
        do { if let r = try library.recoverRename(pending: pendingStore) { applyRecovered(r) } } catch { recoveryProblem = Self.recoveryText(error) }
        account = UserDefaults.standard.string(forKey: Keys.account)
        reloadAccounts()
        // After the account is chosen (reloadAccounts picks the first when none was stored): before the count was per account it was one global value: carry it over to the current account, once.
        if let old = UserDefaults.standard.string(forKey: Keys.count), let a = account {
            if UserDefaults.standard.string(forKey: Keys.count + "." + a) == nil { UserDefaults.standard.set(old, forKey: Keys.count + "." + a) }
            UserDefaults.standard.removeObject(forKey: Keys.count)
        }
        loadBox()
        loadVoiceRecord()
        restorePaging()
        refreshReaderSettings()
        // A scan left unsaved by an earlier run comes before anything in the shared log: it is known to be waiting before the first look at the log (refreshBroadcast), and opened
        // as soon as its account is chosen and no scan is live.
        Self.removeOldTemporaryCopies()
        pendingStore.removeStrayTemporaries()
        adoptWaiting()
        refreshBroadcast()
        reopenPendingScan()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer else { return }
            let model = Unmanaged<AppModel>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { model.refreshBroadcast() } }
        }, SharedStore.notificationName as CFString, nil, .deliverImmediately)
    }

    // MARK: - accounts

    func reloadAccounts() {
        accounts = (try? library.accounts()) ?? []
        if let a = account, !accounts.contains(a) { account = nil }
        if account == nil { account = accounts.first }
    }

    func createAccount(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !storageMissing else { message = BoxExportFile.storageUnavailableText; return }
        guard !name.isEmpty else { message = "Type a name for the account, such as your trainer name."; return }
        if accounts.contains(where: { $0.lowercased() == name.lowercased() }) { message = "There is already an account called \(name). Choose a different name."; return }
        do { try library.createAccount(name) } catch { message = "The account could not be created: \(Self.plain(error))"; return }
        reloadAccounts()
        select(name)
    }

    func select(_ name: String) {
        guard name != account else { return }
        account = name
        loadBox()
        loadVoiceRecord()
    }

    // MARK: - box

    /// False until the selected account's box has been read (so the Box says it is loading and a scan is not planned against a box that is not known yet).
    @Published var boxLoaded = false
    private var boxToken = 0
    private var boxAccount: String?
    private enum BoxLoad { case newer(Int), ok(BoxSnapshot?), damaged(String) }

    /// Read the selected account's current box (and its cached advice, or start computing it), off the main actor: every version file is read once to see whether a newer app
    /// wrote it, and the newest in full. Interrupted renames are repaired first. A newer call, or another account, makes an older read's answer unwanted.
    func loadBox() {
        boxToken += 1
        if storageMissing { snapshot = nil; advice = .none; clearHistory(); scans = []; scansLoaded = true; boxNeedsNewerApp = false; boxProblem = BoxExportFile.storageUnavailableText; boxAccount = nil; boxLoaded = true; return }
        guard let a = account else { snapshot = nil; advice = .none; clearHistory(); scans = []; scansLoaded = true; boxProblem = nil; boxNeedsNewerApp = false; boxAccount = nil; boxLoaded = true; return }
        if boxAccount != a { snapshot = nil; advice = .none; boxProblem = nil; boxNeedsNewerApp = false; boxAccount = a }
        boxLoaded = false
        let token = boxToken, lib = library
        let ps = pendingStore
        Task {
            // On the library's queue, so it never overlaps a rename: finish or undo a rename that was cut off, and put right any copies it left.
            let (recovered, problem) = (try? await worker.run { _ -> (BoxStore.RecoveredRename?, String?) in
                var did: BoxStore.RecoveredRename?, problem: String?
                do { did = try lib.recoverRename(pending: ps) } catch { problem = Self.recoveryText(error) }
                _ = try? lib.store.repairInterruptedRename(account: a)
                return (did, problem)
            }) ?? (nil, nil)
            // What the recovery did is applied whether or not this load is still the latest: a finished rename's settings are never thrown away.
            recoveryProblem = problem
            var disk = accounts
            if let r = recovered {
                disk = (try? lib.accounts()) ?? accounts
                accounts = disk
                if waitingScan != nil { adoptWaiting() }
                applyRecovered(r)   // the settings and the selection follow a rename the recovery finished
            }
            // A recovery that moved the selection, or left it on an account that is not there, is followed by a fresh load even if this one is no longer the latest (the new one supersedes
            // it; its own recovery finds nothing to do, so it does not reload again).
            if recovered != nil, account != a || !disk.contains(account ?? "") {
                if let acc = account, !disk.contains(acc) { account = disk.first }
                loadBox(); loadVoiceRecord(); return
            }
            guard token == boxToken else { return }   // a newer load is already running
            guard account == a else { loadBox(); return }   // the selection moved under this load without asking for one
            let result = await Task.detached(priority: .userInitiated) { () -> BoxLoad in
                // Always asked, not only when the newest version fails to load: any version from a newer app means nothing may be written on top of it.
                if let n = lib.newerVersion(account: a) { return .newer(n) }
                do { return .ok(try lib.current(account: a)) } catch { return .damaged(Self.plain(error)) }
            }.value
            guard token == boxToken, account == a else { return }
            switch result {
            case .newer(let n):
                snapshot = nil; loadHistory(for: a, withPrevious: false)
                boxNeedsNewerApp = true
                boxProblem = "Version \(n) of the box for \(a) was saved by a newer version of the app, so this version cannot open this box. Update the app. Nothing has been changed, and scanning and saving are paused."
            case .ok(let snap):
                snapshot = snap
                loadHistory(for: a, withPrevious: true)
                boxProblem = nil; boxNeedsNewerApp = false
            case .damaged(let why):
                // Not an empty box: the newest version is damaged. Nothing is saved on top of it until the person restores a readable one.
                snapshot = nil; loadHistory(for: a, withPrevious: false)
                boxNeedsNewerApp = false
                boxProblem = "The newest saved version of the box for \(a) cannot be read (\(why)). Your earlier versions are still on this device."
            }
            if let p = recoveryProblem { boxProblem = p }   // an unfinished rename pauses scanning and saving like any box problem
            boxLoaded = true
            loadAdvice()
            loadScans()
            if waitingScan != nil { reopenPendingScan() }   // the box has been read: a scan that was waiting for it can be opened
        }
    }

    private var historyToken = 0
    private var historyAccount: String?
    /// False until the history of the selected account has been read (so Settings says it is loading instead of "No saved versions yet").
    @Published var historyLoaded = false

    private func clearHistory() { historyToken += 1; history = []; previous = nil; historyAccount = nil; historyLoaded = true }   // nothing to load

    /// The version list, read once and off the main actor (it reads every version file); `previous` comes from the same list. A newer call, or another account, makes an older read's answer unwanted.
    private func loadHistory(for a: String, withPrevious: Bool) {
        historyToken += 1
        if historyAccount != a { history = []; previous = nil; historyAccount = a; historyLoaded = false }
        if !withPrevious { previous = nil }
        let token = historyToken, lib = library
        Task {
            let list = await Task.detached(priority: .userInitiated) { (try? lib.history(account: a)) ?? [] }.value
            guard token == historyToken, account == a else { return }
            history = list
            previous = withPrevious ? BoxLibrary.previous(in: list) : nil
            historyLoaded = true
        }
    }

    var entries: [BoxEntry] { snapshot?.entries ?? [] }

    func entry(_ id: String) -> BoxEntry? { entries.first { $0.id == id } }

    func loadAdvice() {
        guard let a = account, let snap = snapshot else { advice = .none; return }
        if let cached = library.loadAdvice(account: a, seq: snap.seq) { advice = .ready(cached); return }
        advice = .computing
        let lib = library, entries = snap.entries, seq = snap.seq
        Task {
            do {
                let result = try await worker.run { engine -> BoxAdvice in
                    let t = Date()
                    let rows = Self.csvRows(entries)
                    let report = try engine.advise(rows: rows, scanDate: snap.scanDate ?? snap.createdAt)
                    let adv = BoxAdvice.make(from: report, entries: entries)
                    NSLog("pogo timings: advise (engine, model) %.2f s", Date().timeIntervalSince(t))
                    try? lib.saveAdvice(adv, account: a, seq: seq)
                    return adv
                }
                if self.snapshot?.seq == seq && self.account == a { self.advice = .ready(result) }
            } catch {
                if self.snapshot?.seq == seq && self.account == a { self.advice = .failed(Self.plain(error)) }
            }
        }
    }

    /// The entries as scan rows for the advisor and the CSV: Index is the position plus one, which is how a build is tied back.
    nonisolated static func csvRows(_ entries: [BoxEntry]) -> [ScanRow] {
        entries.enumerated().map { i, e in var r = e.row; r.index = i + 1; return r }
    }

    // MARK: - hand corrections

    /// What a hand correction came to: `error` when it was refused (nothing saved), `notice` when it was saved but the person
    /// should be told something (no level fits the new values).
    struct CorrectionResult { var error: String?; var notice: String? }

    /// The three actions below each read the CURRENT box inside the one call on the worker's queue that writes the new version
    /// (`BoxLibrary.mutate`), never a copy taken before waiting, so two quick actions cannot drop each other.
    func correct(_ id: String, _ edit: BoxMerge.Edit) async -> CorrectionResult {
        guard let a = account else { return CorrectionResult(error: "There is no account.", notice: nil) }
        let lib = library, label = entry(id)?.row.title ?? "a Pokémon"   // the history note only; the values come from the box inside the call
        // An edit of the hand-set marks only (Dynamax, Gigantamax, Shadow/Purified, Lucky, details) is a setting, not a correction of a read value.
        let marksOnly = edit.marksOnly && (edit.dynamax != nil || edit.gigantamax != nil || edit.lucky != nil || edit.shadow != nil || edit.details != nil)
        do {
            let (new, notice) = try await worker.run { engine -> (BoxSnapshot, String?) in
                var notice: String?
                let snap = try lib.mutate(account: a, reason: .edit, note: marksOnly ? "Marks set for \(label)" : "Corrected \(label)") { entries in
                    guard let i = entries.firstIndex(where: { $0.id == id }) else { throw BoxMerge.EditFailure.badValue("That Pokémon is no longer in the box.") }
                    var fixed = try BoxMerge.correct(entries[i], with: edit, gameMaster: try .bundled())
                    // The level and dust follow the corrected values: the JavaScript solver is run again for this Pokémon.
                    if edit.ivs != nil || edit.cp != nil || edit.hp != nil || edit.speciesName != nil { (fixed, notice) = LevelSolve.apply(to: fixed, engine: engine) }
                    var out = entries; out[i] = fixed
                    return out
                }
                return (snap, notice)
            }
            afterCommit(new)
            return CorrectionResult(error: nil, notice: notice)
        } catch { return CorrectionResult(error: Self.plain(error), notice: nil) }
    }

    /// Remove one Pokémon from the box, as a new box version (the earlier version still has it).
    func deleteEntry(_ id: String) async {
        guard let a = account else { return }
        let lib = library, label = entry(id).map { "\($0.row.title), \(Fmt.cp($0.row.cp))" } ?? "a Pokémon"
        do {
            let new = try await worker.run { _ in
                try lib.mutate(account: a, reason: .edit, note: "Removed \(label)") { entries in
                    guard entries.contains(where: { $0.id == id }) else { throw BoxMerge.EditFailure.badValue("That Pokémon is no longer in the box.") }
                    return entries.filter { $0.id != id }
                }
            }
            afterCommit(new)
        } catch { message = "The Pokémon could not be removed: \(Self.plain(error))" }
    }

    func markChecked(_ id: String) async {
        guard let a = account else { return }
        let lib = library, label = entry(id)?.row.title ?? "a Pokémon"
        do {
            let new = try await worker.run { _ in
                try lib.mutate(account: a, reason: .edit, note: "Checked \(label)") { entries in
                    guard let i = entries.firstIndex(where: { $0.id == id }) else { throw BoxMerge.EditFailure.badValue("That Pokémon is no longer in the box.") }
                    var out = entries; out[i] = BoxMerge.markChecked(entries[i]); return out
                }
            }
            afterCommit(new)
        } catch { message = Self.plain(error) }
    }

    // MARK: - rename, saved scans

    private var renaming = false

    /// The per-account settings follow the account's name: the voice records, the one-time set record and the remembered counts and eggs. The old-name records go, so a stale tap-set
    /// record under the old name cannot keep the wrong-screen warning on. Used by a rename made here and by one that a recovery finished.
    static func moveAccountKeys(from old: String, to new: String) {
        let d = UserDefaults.standard
        for p in VoiceCommandFile.Pace.allCases {
            let k = { (a: String) in Keys.voice + a + "." + p.rawValue }
            if let v = d.data(forKey: k(old)) { d.set(v, forKey: k(new)); d.removeObject(forKey: k(old)) }
        }
        for key in [Keys.set, Keys.count + ".", Keys.partial + ".", Keys.eggs + ".", Keys.stardust + "."] {
            if let v = d.object(forKey: key + old) { d.set(v, forKey: key + new); d.removeObject(forKey: key + old) }
        }
    }

    /// A recovery finished a rename: the settings and the selection follow it exactly as for a rename made here. (An undone rename changes nothing here: nothing had moved.)
    private func applyRecovered(_ r: BoxStore.RecoveredRename) {
        guard r.finished else { return }
        Self.moveAccountKeys(from: r.old, to: r.new)
        if UserDefaults.standard.string(forKey: Keys.account) == r.old { UserDefaults.standard.set(r.new, forKey: Keys.account) }   // at launch, before `account` is read
        if account == r.old { account = r.new }
    }

    /// Returns nil on success, else the reason in plain words (also when the rename could not be fully undone: the sentence then says which name the account has).
    func renameAccount(_ old: String, to new: String) async -> String? {
        // A pending review holds the old name (`Review.account`): saving it after the rename would file the scan under a folder that no longer exists.
        if isReviewing { return "Finish or discard the open scan first, then rename the account." }
        if screenshots.isWorking { return "Screenshots are being read or prepared. Try again in a moment." }
        if live { return "A scan is running. Rename the account when it has finished." }
        if recoveryProblem != nil { return "An earlier rename of an account has not been finished yet, so no account can be renamed now. The app tries again each time it opens a box." }
        if copying { return "A finished scan is being kept for review. Try again in a moment." }
        if reopening { return "A waiting scan is being checked. Try again in a moment." }
        renaming = true   // a scan that ends while the folder moves waits (checkForFinishedScan), so it is not filed under the old name
        defer { renaming = false; if waitingScan != nil { reopenPendingScan() } }
        let lib = library, name = new.trimmingCharacters(in: .whitespacesAndNewlines)
        // The waiting scan, if it is this account's, is retargeted inside the rename's journal (BoxStore.renameAccount) and put back with it if the rename fails.
        let ps = pendingStore
        var actual = name, warning: String?
        let renameResult: Result<Void, Error> = await { do { try await worker.run { _ in try lib.renameAccount(from: old, to: new, pending: ps) }; return .success(()) } catch { return .failure(error) } }()
        // An earlier cut-off rename that this one finished first: its settings move too, whatever became of this rename.
        if let r = try? await worker.run({ _ in lib.takeRecoveredByRename() }) {
            let before = account
            applyRecovered(r)
            accounts = (try? library.accounts()) ?? accounts
            if waitingScan != nil { adoptWaiting() }
            if account != before { loadBox(); loadVoiceRecord() }   // before this rename's own error is handled
        }
        do { try renameResult.get() }
        catch BoxStore.Failure.renameIncomplete(let now, let why) {
            // The rename could not be undone completely: whatever is on disk is the truth, so the lists and the selection follow it, and the next load puts the rest right.
            actual = now; warning = Self.plain(BoxStore.Failure.renameIncomplete(accountNow: now, detail: why))
        } catch { return Self.plain(error) }
        accounts = (try? library.accounts()) ?? accounts
        if waitingScan != nil { adoptWaiting() }
        // Only a rename that went through moves the settings and the selection. One that could not be completed or undone is settled by the recovery the next box load runs (which moves
        // them itself if it finishes the rename), so they are not moved to a name that may be undone.
        if warning == nil, actual != old { Self.moveAccountKeys(from: old, to: actual) }
        if account == old { if warning == nil, actual != old { account = actual }; loadBox(); loadVoiceRecord() } else { refreshDeviceRecords() }
        return warning
    }

    @Published var scans: [BoxStore.Summary] = []

    /// False until the saved scans of the selected account have been read, so the list can say it is loading rather than that there are none.
    @Published var scansLoaded = false
    private var scansToken = 0
    private var scansAccount: String?

    /// The saved scans' summaries, read off the main actor (each file's header and array lengths only, `BoxStore.list`); the list fills in a moment later. A newer call, or another
    /// account, makes an older read's answer unwanted.
    func loadScans() {
        scansToken += 1
        guard let a = account else { scans = []; scansAccount = nil; scansLoaded = false; return }
        if scansAccount != a { scans = []; scansAccount = a; scansLoaded = false }
        let token = scansToken, store = library.store
        Task {
            let list = await Task.detached(priority: .userInitiated) { (try? store.list(account: a).scans) ?? [] }.value
            if token == scansToken { scans = list; scansLoaded = true }
        }
    }

    /// The saved scan's result file and its replay log, copied to the temporary folder under names that say what they are.
    func shareFiles(for scan: BoxStore.Summary) -> [URL] {
        guard let a = account, let f = try? library.store.files(account: a, id: scan.id) else { message = "That scan's files could not be found."; return [] }
        let tmp = FileManager.default.temporaryDirectory
        var out = [URL]()
        let result = tmp.appendingPathComponent("\(scan.id).result.json")
        try? FileManager.default.removeItem(at: result)
        if (try? FileManager.default.copyItem(at: f.result, to: result)) != nil { out.append(result) }
        if let r = f.replay {
            let log = tmp.appendingPathComponent("\(scan.id).replay.jsonl")
            try? FileManager.default.removeItem(at: log)
            if (try? FileManager.default.copyItem(at: r, to: log)) != nil { out.append(log) }
        }
        return out
    }

    private func afterCommit(_ snap: BoxSnapshot) {
        boxToken += 1   // a box read still in flight began before this and must not put an older snapshot back
        boxLoaded = true
        snapshot = snap
        loadHistory(for: snap.account, withPrevious: true)
        loadAdvice()
        loadScans()
    }

    // MARK: - history

    /// Make the newest version that can be read the current box again (the newest one is damaged).
    /// A restore wrote a readable newest version: a damaged box is a box again, and a scan that was waiting for it can open.
    private func boxRestored() {
        if !boxNeedsNewerApp { boxProblem = nil }
        if waitingScan != nil { reopenPendingScan() }
    }

    func restoreLatestReadable() async {
        guard let a = account else { return }
        let lib = library
        do {
            let snap = try await worker.run { _ in try lib.restoreLatestReadable(account: a) }
            afterCommit(snap)
            boxRestored()
            message = "Restored version \(snap.restoredFrom ?? 0), the newest one that can be read."
        } catch { message = "No saved version of this box could be restored: \(Self.plain(error))" }
    }

    func restore(seq: Int) async {
        guard let a = account else { return }
        let lib = library
        do {
            let snap = try await worker.run { _ in try lib.restore(account: a, seq: seq) }
            afterCommit(snap)
            boxRestored()
            message = "Restored version \(seq) of the box for \(a)."
        } catch { message = Self.plain(error) }
    }

    func restorePrevious() async {
        guard let a = account else { return }
        let lib = library
        do {
            let snap = try await worker.run { _ in try lib.restorePrevious(account: a) }
            afterCommit(snap)
            boxRestored()
            message = "Went back to version \(snap.restoredFrom ?? 0) of the box for \(a)."
        } catch { message = Self.plain(error) }
    }

    // MARK: - export

    /// The whole box, or only the entries with these ids (Box's select mode), as a CSV or as the Markdown file for a chat model. Both go to the share sheet.
    func export(_ format: ExportFormat, only ids: Set<String>? = nil) async {
        guard let snap = snapshot, !snap.entries.isEmpty else { message = "There is nothing to export yet. Scan some Pokémon first."; return }
        busy = format == .csv ? "Making the CSV" : "Making the file"
        defer { busy = nil }
        let lib = library
        do {
            exportURL = try await worker.run { engine in try BoxExportFile.write(format, snap: snap, only: ids, library: lib, engine: engine) }
        } catch { message = "The \(format == .csv ? "CSV" : "file") could not be made: \(Self.plain(error))" }
    }

    // MARK: - the broadcast

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshBroadcast() } }
    }
    func stopTimer() { timer?.invalidate(); timer = nil }

    func refreshBroadcast() {
        now = Date()
        let s = SharedStore.read()
        if s != broadcast { broadcast = s }
        postFallbackNotificationIfNeeded(s)
        checkForFinishedScan()
    }

    var secondsSinceUpdate: Double { max(0, now.timeIntervalSince(broadcast?.updated ?? now)) }
    var endedWithoutFinish: Bool { broadcast.map { !$0.finished && secondsSinceUpdate >= Tuning.staleStateSeconds } ?? false }
    var live: Bool { broadcast.map { !$0.finished && !endedWithoutFinish } ?? false }

    // MARK: - scan review

    var isReviewing: Bool { if case .idle = flow { return false } else { return true } }
    /// The review cover is up: a review (or its reading, or its failure) is in progress and the Done screen is not waiting for the person.
    var reviewCoverShown: Bool { isReviewing && !scanDonePending }
    /// The person leaves the Done screen for the review.
    func openReview() {
        scanDonePending = false
        if scanCopy != nil { _ = try? pendingStore.update { $0.doneFirst = false } }   // a relaunch goes straight to the review
    }

    /// A broadcast has finished (or died without saying so) and its replay log has not been through review yet: read it. One scan is kept at a time: while another waits to be
    /// reviewed (or is being), a newer one is left in the shared log, with a message, and is read after that one is saved or discarded, unless another broadcast replaces the log first.
    func checkForFinishedScan() {
        if waitingScan != nil { reopenPendingScan() }
        guard !holdReview, !renaming, !busyWithScan, !isReviewing, !live, let state = broadcast, state.finished || endedWithoutFinish,
              let sig = ReplayMarker.unprocessedSignature() else { return }
        if waitingScan != nil || scanCopy != nil {
            if waitingScan?.signature != sig, waitingShownFor != sig {
                waitingShownFor = sig
                let who = waitingScan.map { $0.damaged ? "a scan from earlier" : "a scan for \($0.account)" } ?? "a scan"
                message = "Another scan is still waiting to be reviewed (\(who)). Review or discard it first. The newer scan stays in the shared log and is read after it, unless you start another scan before then: that would replace it."
            }
            return
        }
        let scanAccount: String
        switch accountOfScan(state) {
        case .account(let name): scanAccount = name
        case .waiting: return   // no account yet: the scan stays in the shared log and is picked up once there is one
        case .storageProblem:
            if waitingShownFor != sig {
                waitingShownFor = sig
                message = accountUnknownText
            }
            return
        case .gone(let name):
            // The account this scan was started under is positively gone: it is not given to whichever account is selected.
            if waitingShownFor != sig { waitingShownFor = sig; flow = .failed(message: Self.accountGoneText(name), signature: sig) }
            return
        }
        if let after = copyRetryAfter, Date() < after { return }
        if scanAccount == account, !boxLoaded || boxProblem != nil { return }
        startReview(signature: sig, doneFirst: true, state: state)
    }

    /// Which account a finished scan belongs to. `waiting`: no account is known yet (a first-time user started a broadcast before creating one): nothing is said, the scan is
    /// picked up once an account exists. `storageProblem`: the accounts cannot be listed, which says nothing about the recorded account. `gone`: the listing worked and the
    /// recorded account is neither there nor the result of a recorded rename.
    private enum ScanAccount { case account(String), waiting, storageProblem, gone(String) }

    /// The one selected when its broadcast started (recorded in the state), whatever is selected now, followed through renames; the selected one for a state that does not say.
    private func accountOfScan(_ state: BroadcastState?) -> ScanAccount {
        guard let recorded = state?.account else { return account.map { .account($0) } ?? .waiting }
        if storageMissing { return .storageProblem }
        switch library.store.lookupAccount(recorded) {
        case .found(let name): return .account(name)
        case .gone: return .gone(recorded)
        case .unknown: return recoveryProblem != nil ? .waiting : .storageProblem   // an unresolved rename is already shown as a box problem
        }
    }

    private static func encode(_ state: BroadcastState?) -> Data? { state.flatMap { try? JSONEncoder().encode($0) } }
    private static func decode(_ data: Data?) -> BroadcastState? { data.flatMap { try? JSONDecoder().decode(BroadcastState.self, from: $0) } }

    /// What is kept on disk and not open yet, read once when it is found (not every second).
    private func adoptWaiting() {
        switch pendingStore.load() {
        case .none: waitingScan = nil
        case .ready(let m, _): waitingScan = WaitingScan(signature: m.signature, account: m.account, damaged: false)
        case .damaged(let why): waitingScan = WaitingScan(signature: "", account: "", damaged: true, reason: why)
        }
    }

    /// `doneFirst`: a scan that has just ended shows its Done screen before the review opens (`scanDonePending`); a retry after a failure opens the review directly.
    /// `state` is the broadcast's state for this scan (nil: the copy's own, else the current one).
    func startReview(signature: String, doneFirst: Bool = false, state: BroadcastState? = nil) {
        guard let shared = SharedStore.replayURL, !busyWithScan else { return }
        // The review works from its own copy of the log, kept on disk: the next broadcast truncates and rewrites the shared one, and a finished scan can wait for the person for a
        // long time. A retry after a failure reuses the copy it made. If the shared log is no longer this scan's (a newer broadcast has rewritten it), nothing is presented: the
        // newer scan is picked up when this one is done with.
        if let c = scanCopy {
            if c.signature != signature { return }   // one scan at a time
            if FileManager.default.fileExists(atPath: c.url.path) {
                switch library.store.lookupAccount(c.account) {
                case .gone: flow = .failed(message: Self.accountGoneText(c.account), signature: signature); return
                case .unknown: message = accountUnknownText; return   // cannot tell: not "gone", and the person is told why nothing happened
                case .found(let now):
                    if now != c.account { scanCopy?.account = now; _ = try? pendingStore.update { $0.account = now } }
                }
                beginReading(signature: signature, doneFirst: doneFirst, copy: scanCopy ?? c, state: state ?? c.state ?? broadcast)
                return
            }
            dropCopy()
        }
        let st = state ?? broadcast
        guard case .account(let a) = accountOfScan(st) else { return }
        if a == account, !boxLoaded || boxProblem != nil { return }
        let kind = st?.kind.flatMap(BoxStore.Kind.init(rawValue:)) ?? scanKind   // what the scan was started as, not the preference now
        // The pass is what the scan was started as, from its state; a state without a kind (the sample scan) takes the one chosen now, as the kind does.
        let pass = ScanPass(stored: st?.pass) ?? (st?.kind == nil ? scanPass : nil)
        let meta = PendingScanMeta(signature: signature, account: a, kind: pass == nil ? kind : .partial, scanDate: st?.updated, doneFirst: doneFirst, attempts: 0, state: Self.encode(st), pass: pass?.rawValue)
        let store = pendingStore
        copying = true
        Task {
            // Up to 16 MB is read and written: not on the main actor.
            let result = await Task.detached(priority: .userInitiated) { store.take(from: shared, meta: meta, currentSignature: { ReplayMarker.signature() }) }.value
            copying = false
            switch result {
            case .copied(let url):
                // Still wanted? A rename, a review that began meanwhile or a log already reviewed mean this copy is not read now and is taken back out; a retry from the failure
                // screen for this very scan is wanted. The selected account changing is not a reason: the scan belongs to the account it was started under.
                var retrying = false
                if case .failed(_, let s) = flow, s == signature { retrying = true }
                guard !renaming, !isReviewing || retrying, ReplayMarker.processedSignature() != signature else { store.clear(ifSignature: signature); return }
                copyRetryAfter = nil
                if account == a, boxLoaded, boxProblem == nil {
                    let c = ScanCopy(signature: signature, url: url, state: st, kind: meta.kind, date: meta.scanDate, account: a, pass: meta.pass)
                    scanCopy = c
                    beginReading(signature: signature, doneFirst: doneFirst, copy: c, state: st)
                } else {
                    // Its account is not the one on screen, or that box is not ready: the kept scan opens when it is (reopenPendingScan).
                    adoptWaiting()
                    if account != a { select(a) }
                }
            case .replaced:
                if case .failed = flow { flow = .failed(message: "The log of this scan has been replaced by a newer scan, so it cannot be read again. Discard it.", signature: signature) }
            case .occupied:
                adoptWaiting()   // another scan is kept: it is opened first, this one follows
                reopenPendingScan()
            case .failed(let why):
                // Said once per scan; the copy is tried again after a pause, not every second.
                copyRetryAfter = Date().addingTimeInterval(30)
                if copyFailureShownFor != signature {
                    copyFailureShownFor = signature
                    message = "The finished scan could not be kept for review: \(why) The app will try again."
                }
            }
        }
    }

    private static func accountGoneText(_ name: String) -> String { "The account this scan belonged to (\(name)) is no longer on this phone, so the scan cannot be reviewed. Discard it." }

    private var reopenAgain = false
    /// `reopenPendingScan` once more, but never from inside that second call: the depth is one.
    private func reopenOnce(selecting: Bool) {
        guard !reopenAgain else { return }
        reopenAgain = true; defer { reopenAgain = false }
        reopenPendingScan(selecting: selecting)
    }

    /// Why a scan's account cannot be told right now, in words (a retry or the message about a finished scan says it).
    private var accountUnknownText: String {
        if storageMissing { return BoxExportFile.storageUnavailableText }
        if let p = recoveryProblem { return p }
        if library.store.renameJournalExists { return "A rename of an account was not finished, so the account this scan belongs to cannot be told yet. Open the account's box or restart the app to finish the rename; the scan is kept and is opened by itself once the account is known. Do not start another scan until then: it would replace this one." }
        return "The account this scan belongs to cannot be told right now: the list of accounts or the record of renamed accounts could not be read. The scan is kept and the app keeps trying by itself. Do not start another scan until then: it would replace this one."
    }

    /// A scan kept on disk is opened for review (by an earlier run, or after the account or the box was not ready): before anything in the shared log, once no scan is live, its
    /// account is selected (it is selected for it) and that box has been read. It is not read on its own again if the last reading of it never finished (the app was ended during
    /// it): it opens as a failure with Try again and Discard. A scan already saved (the app was ended between the save and the note that it had been) is not saved twice; if that
    /// cannot be told, the review opens with a line saying so.
    func reopenPendingScan(selecting: Bool = false) {
        guard let w = waitingScan, !busyWithScan, !renaming, !isReviewing, scanCopy == nil, !live else { return }
        if w.damaged {
            flow = .failed(message: "A scan left from earlier cannot be opened: \(w.reason ?? "it is damaged") It is still on the phone until you discard it.", signature: Self.damagedPrefix)
            return
        }
        if ReplayMarker.processedSignature() == w.signature { pendingStore.clear(ifSignature: w.signature); waitingScan = nil; return }
        if !accounts.contains(w.account) {
            // The cached list may only be stale: read it again first, and go on if the account is there. (Asked again at most once, `reopenOnce`.)
            accounts = (try? library.accounts()) ?? accounts
            if accounts.contains(w.account) { reopenOnce(selecting: selecting); return }
            // Renamed since it was kept (and not retargeted): follow the rename; otherwise the account is gone.
            switch library.store.lookupAccount(w.account) {
            case .unknown: return   // the accounts cannot be listed: say nothing, ask again later
            case .found(let now):
                // Only a real change is followed, and it asks again only when the refreshed list holds the new name.
                if now != w.account, (try? pendingStore.update { $0.account = now }) != nil {
                    waitingScan?.account = now
                    if accounts.contains(now) { reopenOnce(selecting: selecting) }
                }
                return
            case .gone: break
            }
            guard case .ready(let meta, let copy) = pendingStore.load() else { adoptWaiting(); return }
            scanCopy = ScanCopy(signature: meta.signature, url: copy, state: Self.decode(meta.state), kind: meta.kind, date: meta.scanDate, account: meta.account, pass: meta.pass)
            waitingScan = nil
            flow = .failed(message: Self.accountGoneText(meta.account), signature: meta.signature)
            return
        }
        if account != w.account {
            // Its account is selected for it once; if the person goes elsewhere afterwards (to fix that box, say) they are not pulled back every second, only by "Review it".
            if selecting || autoSelectedFor != w.signature { autoSelectedFor = w.signature; select(w.account) }
            return   // the box load that follows asks again
        }
        guard boxLoaded, boxProblem == nil else { return }
        guard case .ready(let meta, let copy) = pendingStore.load() else { adoptWaiting(); return }
        reopening = true
        let lib = library, a = meta.account, sig = meta.signature
        Task {
            // On the library's queue: it may take back a scan record left without its box version.
            let saved = (try? await worker.run { _ in lib.scanAlreadySaved(account: a, signature: sig) }) ?? .unknown
            reopening = false
            guard !isReviewing, !renaming, scanCopy == nil, account == a, boxProblem == nil, !live, waitingScan?.signature == sig else { return }   // still waiting (or discarded meanwhile); the next event asks again
            if saved == .saved { ReplayMarker.markProcessed(sig); pendingStore.clear(ifSignature: sig); waitingScan = nil; return }
            waitingScan = nil
            let c = ScanCopy(signature: sig, url: copy, state: Self.decode(meta.state), kind: meta.kind, date: meta.scanDate, account: a, pass: meta.pass)
            scanCopy = c
            if saved == .unknown { message = "This scan may already have been saved before the app closed. Look at the version history in Settings before saving it again." }
            if meta.attempts > 0 {
                scanDonePending = false
                flow = .failed(message: "Reading this scan did not finish last time (the app may have run out of memory or been closed). The scan is still here: try reading it again. Discard it only if it fails again.", signature: sig)
            } else {
                beginReading(signature: sig, doneFirst: meta.doneFirst, copy: c, state: c.state)
            }
        }
    }

    /// The person chose to review the waiting scan: its account is selected and it opens.
    func openWaitingScan() { reopenPendingScan(selecting: true) }

    /// Throw the waiting scan away without needing its box to be readable, so a scan that cannot be opened can never stop scanning for good.
    func discardWaitingScan() {
        guard let w = waitingScan else { return }
        if w.damaged { pendingStore.clear() } else { ReplayMarker.markProcessed(w.signature); pendingStore.clear(ifSignature: w.signature) }
        waitingScan = nil
    }

    /// Copies of the log that earlier builds left in the temporary folder.
    private static func removeOldTemporaryCopies() {
        let dir = FileManager.default.temporaryDirectory
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasPrefix("pogo-review-") { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
    }

    /// The scene moved: a reading the app does not outlive in the background (iOS ends it) is not a crash, so the unfinished-reading mark is only held while the app is in front.
    func scenePhaseChanged(background: Bool) {
        guard readingScan else { return }
        _ = try? pendingStore.update { $0.attempts = background ? 0 : 1 }
    }

    private func beginReading(signature: String, doneFirst: Bool, copy: ScanCopy, state: BroadcastState?) {
        let a = copy.account, url = copy.url
        // Counted on disk before the reading and cleared when it ends: a reading the app did not survive is not started again on its own at the next launch. If it cannot be
        // written the reading does not start by itself.
        do { try pendingStore.update { $0.attempts += 1 } } catch {
            scanDonePending = false
            flow = .failed(message: "The scan could not be marked as being read, so it was not read automatically. Try again, or discard it.", signature: signature)
            return
        }
        readingScan = true
        let store = pendingStore
        flow = .processing("Reading the scan")
        scanDonePending = doneFirst
        // The kind asked and the date of the scan are the ones it was copied with (a relaunch must not use today's preference or time): the date is when the broadcast last wrote, i.e. ended.
        let asked = copy.kind, date = copy.date ?? Date(), lib = library, pass = ScanPass(stored: copy.pass)
        // How the scan was paged is what the extension was told when it started (a command at its period, or by hand), not a setting changed since.
        let period: Double? = { if let b = state { return b.commandPeriod }; return pagedByHand ? nil : pace.every }()
        let paging = period == nil ? PagingHint(pagedByCommand: false) : PagingHint(pagedByCommand: true, expectedPeriod: period, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
        let ended = state?.endedAtListEnd ?? false, byPerson = state?.stoppedByPerson ?? false, byTimeout = state?.stoppedByTimeout ?? false, logFull = state?.replayLogTruncated ?? false, logFailed = state?.replayLogFailed ?? false
        // The count the scan was started with (captured in its state), not the field as it reads now: it may have been edited since.
        let typed = state.map { $0.storageCount } ?? storageCount
        let eggs = state.map { $0.eggCount } ?? eggCount
        Task {
            do {
                let (outcome, plan, seconds, base, seq, kind, note, advice, stop) = try await worker.run { engine -> (ScanPipeline.Outcome, BoxMerge.Plan, Double, [BoxEntry], Int?, BoxStore.Kind, String?, ScanKindAdvice.Decision, String?) in
                    let outcome = try ScanPipeline.process(replay: url, engine: engine, paging: paging)
                    // A full scan lists everything unseen as "Not seen in this scan" (all kept unless marked), but it is only the default when the list can be known to have ended.
                    var kind = asked, note: String?
                    let d = ScanKindAdvice.decide(endedAtListEnd: ended, pokemonRead: outcome.scan.rows.count, typedCount: typed, logTruncated: logFull, logFailed: logFailed, commandPeriod: period, eggCount: eggs, endedByTimeout: byTimeout)
                    if asked == .full && !d.fullIsSound { kind = .partial; note = d.reason }
                    if pass != nil { kind = .partial; note = nil }   // a pass removes nothing and is not judged as a Full scan
                    let current = try lib.current(account: a)   // the box as it is when the plan is made
                    let entries = current?.entries ?? []
                    let t = Date()
                    let plan = BoxMerge.plan(scanned: outcome.scan.rows, unmatched: outcome.scan.unmatched, into: entries, kind: kind, scanDate: date, gameMaster: try .bundled(), pass: pass)
                    // Where it stopped: the last Pokémon, how many, whether the appraisal had closed (from the whole log, the tail the end marker cuts included).
                    var stop: String?
                    if ended || byPerson || byTimeout {
                        let last = outcome.scan.rows.last
                        let closed = ScanStop.appraisalClosed(lines: ReplayLog.lines(in: url))
                        let ran = ScanStop.ranOut(read: outcome.scan.rows.count, typedCount: typed, full: asked == .full, commandPeriod: period)
                        stop = ScanStop.summary(lastName: last?.display, lastCP: last?.cp, read: outcome.scan.rows.count, appraisalClosed: closed, ranOut: ran,
                                                commandKnown: asked == .full && typed != nil, nearestSize: ScanStop.nearestSize(read: outcome.scan.rows.count, commandPeriod: period),
                                                matchSentence: ScanKindAdvice.matchSentence(pokemonRead: outcome.scan.rows.count, decision: d, eggCount: eggs),
                                                paused: ScanStop.pauseNames(outcome.pauses, rows: outcome.scan.rows, finishedByPerson: byPerson), byPerson: byPerson, byTimeout: byTimeout)
                    }
                    return (outcome, plan, Date().timeIntervalSince(t), entries, current?.seq, kind, note, d, stop)
                }
                let t = outcome.timings
                NSLog("pogo timings: load %.2f finish %.2f refine %.2f merge %.2f s, %d rows", t.load, t.finish, t.refine, seconds, outcome.scan.rows.count)
                var review = Review(account: a, kind: kind, outcome: outcome, plan: plan, base: base, storageCount: asked == .full ? typed : nil, signature: signature, mergeSeconds: seconds, paging: StoredPaging(paging), boxSeq: seq)
                review.log = url; review.endedAtListEnd = ended; review.stoppedByPerson = byPerson; review.stoppedByTimeout = byTimeout; review.kindNote = note; review.advice = advice; review.stopSummary = stop
                readingScan = false
                _ = try? store.update { $0.attempts = 0 }
                flow = .review(review)
            } catch {
                readingScan = false
                _ = try? store.update { $0.attempts = 0 }
                scanDonePending = false
                flow = .failed(message: Self.plain(error), signature: signature)
            }
        }
    }

    // MARK: - screenshot import review

    /// Open the review for a prepared screenshot import. Its signature is the batch's, so nothing that looks at a broadcast's log mistakes it for one.
    func presentImportReview(_ p: ScreenshotImporter.Prepared, seconds: Double) {
        guard !isReviewing else { return }
        var review = Review(account: p.account, kind: .partial, outcome: p.outcome, plan: p.plan, base: p.base, storageCount: nil, signature: p.manifest.signature, mergeSeconds: seconds, paging: nil, boxSeq: p.boxSeq)
        review.importPrepared = p
        flow = .review(review)
    }

    /// Save a screenshot import through the importer: one box version and one scan record, once, whatever the number of taps or relaunches (`ScreenshotImporter.save`).
    private func saveImport(_ r: Review) async {
        guard let p = r.importPrepared else { return }
        busy = "Saving to the box"
        defer { busy = nil }
        let importer = screenshots.importer
        do {
            let result = try await worker.run { engine in try importer.save(p, resolutions: r.resolutions, engine: engine) }
            flow = .idle
            switch result {
            case .saved(let snap):
                lastSave = SaveSummary(base: r.base, saved: snap, showsCounts: true)
                if r.account == account { afterCommit(snap) }
            case .nothingToSave:
                message = "Nothing was added. The screenshots you left out were cleared; any that are held back, unread or failed stay in Import screenshots."
                if r.account == account { loadBox() }
            case .alreadySaved:
                message = "These screenshots had already been saved, so nothing was added again."
                if r.account == account { loadBox() }
            }
            screenshots.refresh()
        } catch BoxLibrary.Failure.boxChanged {
            message = "The box changed while this was open, so nothing was saved. The result has been worked out again against the box as it is now: check it and save again."
            await refreshReview(r)
        } catch let failure as ScreenshotImporter.Failure where { if case .finishingLastSave = failure { return true } else { return false } }() {
            // An earlier save of this batch is not finished: nothing was added again. Whether it is in the box is what the message says (found, or may be): it is the importer's wording.
            flow = .idle
            message = Self.plain(failure)
            screenshots.refresh()
        } catch ScreenshotImporter.Failure.staleReview {
            flow = .idle
            message = Self.plain(ScreenshotImporter.Failure.staleReview)
            screenshots.refresh()
        } catch ScreenshotImporter.Failure.importRecordUnreadable {
            message = Self.plain(ScreenshotImporter.Failure.importRecordUnreadable) + " Open Import screenshots to start a new import record."
        } catch ScreenshotImporter.Failure.cannotTellIfSaved {
            message = Self.plain(ScreenshotImporter.Failure.cannotTellIfSaved)   // trying again will not change it: the text says what to do
        } catch ScreenshotImporter.Failure.couldNotUpdateBatch {
            message = Self.plain(ScreenshotImporter.Failure.couldNotUpdateBatch) + " Nothing was saved; you can try again."
        } catch ScreenshotImporter.Failure.couldNotRecordSave {
            message = Self.plain(ScreenshotImporter.Failure.couldNotRecordSave)   // nothing was written; the review stays open to try again
        } catch {
            message = "The screenshots could not be saved: \(Self.plain(error)) Nothing in the box has changed. You can try again or discard them."
        }
    }

    /// Change the scan kind on the review screen; the merge is recomputed (it is pure and quick).
    func setReviewKind(_ kind: BoxStore.Kind) async {
        guard case .review(var r) = flow, r.kind != kind, r.importPrepared == nil, r.plan.pass == nil else { return }   // a screenshot import is always Add and update
        scanKind = kind
        let base = r.base, rows = r.outcome.scan.rows, date = r.plan.scanDate
        let unmatched = r.outcome.scan.unmatched
        let plan = try? await worker.run { _ in BoxMerge.plan(scanned: rows, unmatched: unmatched, into: base, kind: kind, scanDate: date, gameMaster: try .bundled()) }
        guard let plan, case .review = flow else { return }
        r.kind = kind; r.plan = plan; r.planToken = UUID(); r.resolutions = [:]; r.markedForRemoval = []
        flow = .review(r)
    }

    func resolve(_ scanned: Int, _ resolution: BoxMerge.Resolution?) {
        guard case .review(var r) = flow else { return }
        r.resolutions[scanned] = resolution
        flow = .review(r)
    }

    /// The answer to "Was this a <kind> search?": yes saves it as the pass; no saves it as an ordinary Add and update scan (nothing is marked); cancelling leaves the review open.
    func answerPassSearch(yes: Bool?) async {
        guard case .review(var r) = flow else { return }
        r.askingSearch = false
        guard let yes else { flow = .review(r); return }
        r.searchConfirmed = true
        if !yes { r.plan.pass = nil; r.planToken = UUID() }
        flow = .review(r)
        await saveReview()
    }

    func setRemove(_ id: String, _ remove: Bool) {
        guard case .review(var r) = flow else { return }
        if remove { r.markedForRemoval.insert(id) } else { r.markedForRemoval.remove(id) }
        flow = .review(r)
    }

    /// Mark every Pokémon the scan did not see for removal (the person chose "Remove all not seen").
    func removeAllNotSeen() {
        guard case .review(var r) = flow else { return }
        r.markedForRemoval = Set(BoxMerge.goneReport(r.plan, resolutions: r.resolutions).gone)
        flow = .review(r)
    }

    func keepAllNotSeen() {
        guard case .review(var r) = flow else { return }
        r.markedForRemoval = []
        flow = .review(r)
    }

    /// Why Save is not available yet, in words, or nil when it is.
    func saveBlocker(_ r: Review) -> String? {
        do { try BoxMerge.validate(r.plan, resolutions: r.resolutions); return nil } catch { return error.localizedDescription }
    }

    func saveReview() async {
        guard case .review(let r) = flow else { return }
        if let why = saveBlocker(r) { message = why; return }
        if r.importPrepared != nil { await saveImport(r); return }
        // A pass whose rows mostly match nothing in the box was probably searched for wrongly: ask first (a read-again scan was asked when it was first saved).
        if r.reread == nil, !r.searchConfirmed, BoxMerge.passSearchLooksWrong(r.plan) {
            var asking = r; asking.askingSearch = true
            flow = .review(asking)
            return
        }
        busy = "Saving to the box"
        defer { busy = nil }
        let lib = library
        do {
            let snap = try await worker.run { engine -> BoxSnapshot in
                // Refused (not written over it) if the box has changed since this review was prepared.
                let entries = try BoxMerge.apply(r.plan, resolutions: r.resolutions, keepGone: r.keepGone, to: r.base, engine: engine)
                // A scan read again: a new box version from the earlier box plus the new read; the scan itself is not saved twice.
                if let plan = r.reread { return try lib.commitReread(plan, entries: entries, account: r.account, expectedCurrentSeq: .some(r.boxSeq)) }
                let log = r.log.flatMap { try? Data(contentsOf: $0) }
                let n = r.outcome.scan.rows.count
                let note = (r.plan.pass?.passName ?? (r.kind == .full ? "Full scan" : "Add and update")) + ", \(n) Pokémon"
                // The scan record and the box version go in as one step: a version that cannot be written takes the record back out (BoxLibrary.commitScan).
                return try lib.commitScan(r.outcome.scan, entries: entries, account: r.account, scanDate: r.plan.scanDate, source: "broadcast", kind: r.kind, note: note,
                                          expectedCurrentSeq: .some(r.boxSeq), storageCount: r.storageCount, replayLog: log, paging: r.paging,
                                          refineChanges: r.outcome.changes.map { "\($0.kind.rawValue): \($0.detail)" },
                                          reviewActions: ScanReportBuilder.reviewLines(plan: r.plan, resolutions: r.resolutions, keepGone: r.keepGone, base: r.base),
                                          reportSentAt: r.reportSentAt, reportHash: r.reportHash, sourceSignature: r.signature, pass: r.plan.pass?.rawValue).snapshot
            }
            if r.reread == nil { ReplayMarker.markProcessed(r.signature) }
            // A scan paged by the voice command is saved: setup counts as done (`SetupProgress.pagedScanSaved`).
            if r.reread == nil, r.paging?.pagedByCommand == true { setup.notePagedScanSaved() }
            flow = .idle
            // A scan read again was merged into the box as it was BEFORE that scan, so the box it started from is not the box the person had: no counts for it.
            lastSave = SaveSummary(base: r.base, saved: snap, showsCounts: r.reread == nil)
            if r.account == account { afterCommit(snap) }
        } catch BoxLibrary.Failure.boxChanged {
            message = "The box changed while this scan was open, so nothing was saved. The result has been worked out again against the box as it is now: check it and save again."
            await refreshReview(r)
        } catch {
            message = "The scan could not be saved: \(Self.plain(error)) Nothing in the box has changed. You can try again or discard the scan."
        }
    }

    /// Work the merge out again against the box as it is now (after the box changed under an open review); the answers start over.
    private func refreshReview(_ r: Review) async {
        if let plan = r.reread { flow = .idle; rereadScan(id: plan.scan.id); return }
        if let p = r.importPrepared { flow = .idle; await screenshots.review(batch: p.manifest.batchId); return }
        let lib = library, rows = r.outcome.scan.rows, unmatched = r.outcome.scan.unmatched, kind = r.kind, date = r.plan.scanDate, a = r.account, pass = r.plan.pass
        do {
            let (plan, base, seq) = try await worker.run { _ -> (BoxMerge.Plan, [BoxEntry], Int?) in
                let cur = try lib.current(account: a)
                let entries = cur?.entries ?? []
                return (BoxMerge.plan(scanned: rows, unmatched: unmatched, into: entries, kind: kind, scanDate: date, gameMaster: try .bundled(), pass: pass), entries, cur?.seq)
            }
            var n = r; n.plan = plan; n.planToken = UUID(); n.base = base; n.boxSeq = seq; n.resolutions = [:]; n.markedForRemoval = []
            flow = .review(n)
            if a == account { loadBox() }
        } catch { message = "The box could not be read again: \(Self.plain(error))" }
    }

    func discardReview() {
        switch flow {
        case .review(let r) where r.importPrepared != nil: screenshots.reviewClosedWithoutSaving()   // the screenshots stay queued; discarding them is a choice in Import screenshots
        case .review(let r): if r.reread == nil { ReplayMarker.markProcessed(r.signature) }
        case .failed(_, let sig):
            if sig == Self.damagedPrefix { pendingStore.clear(); waitingScan = nil }   // the person's choice: what was kept goes
            else if !sig.hasPrefix(Self.rereadPrefix) { ReplayMarker.markProcessed(sig) }
        default: break
        }
        flow = .idle
    }

    private static let rereadPrefix = "reread:"

    /// The review has ended (saved or discarded): its copy goes, from memory and from disk. Only the scan this model holds the copy of: a different scan kept on disk is never cleared here.
    private func dropCopy() {
        if let c = scanCopy { pendingStore.clear(ifSignature: c.signature) }
        scanCopy = nil
    }

    /// Read a saved scan again with the latest rules, against the box as it was before that scan was saved. Opens the normal review
    /// screen; nothing changes until Save, and Discard changes nothing.
    func rereadScan(_ scan: BoxStore.Summary) { rereadScan(id: scan.id) }

    func rereadScan(id: String) {
        guard let a = account, !isReviewing, boxProblem == nil else { return }
        sheet = nil
        flow = .processing("Reading the saved scan again")
        let lib = library, signature = Self.rereadPrefix + id
        Task {
            do {
                let (plan, outcome, merge, seconds, seq) = try await worker.run { engine -> (RereadPlan, ScanPipeline.Outcome, BoxMerge.Plan, Double, Int?) in
                    let plan = try lib.prepareReread(account: a, scanId: id)
                    let outcome = try ScanPipeline.process(replay: plan.replayURL, engine: engine, paging: plan.paging)
                    let t = Date()
                    let merge = BoxMerge.plan(scanned: outcome.scan.rows, unmatched: outcome.scan.unmatched, into: plan.baseEntries, kind: plan.scan.kind, scanDate: plan.scan.scanDate, gameMaster: try .bundled(), pass: ScanPass(stored: plan.scan.pass))
                    return (plan, outcome, merge, Date().timeIntervalSince(t), try lib.current(account: a)?.seq)
                }
                flow = .review(Review(account: a, kind: plan.scan.kind, outcome: outcome, plan: merge, base: plan.baseEntries, storageCount: plan.scan.storageCount, signature: signature,
                                      mergeSeconds: seconds, paging: plan.scan.paging, reread: plan, boxSeq: seq))
            } catch {
                flow = .failed(message: Self.plain(error), signature: signature)
            }
        }
    }

    func retryReview() {
        guard case .failed(_, let sig) = flow else { return }
        if sig.hasPrefix(Self.rereadPrefix) {
            flow = .idle
            rereadScan(id: String(sig.dropFirst(Self.rereadPrefix.count)))
        } else if sig == Self.damagedPrefix {
            flow = .idle
            reopenPendingScan()
        } else { startReview(signature: sig) }
    }

    // MARK: - plain errors

    nonisolated static func plain(_ error: Error) -> String {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return text.hasSuffix(".") ? text : text + "."
    }
}

/// The review state of the extension's `replay.jsonl`: which log has been through review. The log is identified by its size
/// and modification time, which a new broadcast changes (it truncates the file at start); the marker file sits beside it.
enum ReplayMarker {
    private static var markerURL: URL? { SharedStore.containerURL?.appendingPathComponent("replay.processed") }

    static func signature() -> String? {
        guard let url = SharedStore.replayURL, let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = a[.size] as? Int, let date = a[.modificationDate] as? Date, size > 0 else { return nil }
        return "\(size)-\(Int(date.timeIntervalSince1970 * 1000))"
    }

    /// The signature of the log last marked as reviewed, if any.
    static func processedSignature() -> String? { markerURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } }

    /// The signature of a replay log that exists and has not been reviewed, else nil.
    static func unprocessedSignature() -> String? {
        guard let sig = signature() else { return nil }
        return processedSignature() == sig ? nil : sig
    }

    static func markProcessed(_ signature: String) {
        guard let url = markerURL else { return }
        try? Data(signature.utf8).write(to: url, options: .atomic)
    }
}
