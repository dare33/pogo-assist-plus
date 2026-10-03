import SwiftUI
import UserNotifications
import PogoBox
import PogoReader

/// Receives the pause notification's "Finish scan" action (the app is woken for it) and lets notifications show while the app is open.
final class NotificationActions: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Scoped to the scan the notification was about: an old notification's action does nothing to a later scan.
        if response.actionIdentifier == ScanNotification.finishActionID, let scan = response.notification.request.content.userInfo["scan"] as? Int { ReaderSettings.finishRequestedScan = scan }
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
        /// The extension ended this scan itself because the end of the list was reached.
        var endedAtListEnd = false
        /// Why the review chose Add and update although a full scan was asked for (`ScanKindAdvice`), or nil.
        var kindNote: String?
        /// What `ScanKindAdvice` said about a full scan of this result (nil for a saved scan read again).
        var advice: ScanKindAdvice.Decision?
        /// Where a scan the extension ended itself stopped and what to do (`ScanStop.summary`), shown once at the top of the review.
        var stopSummary: String?
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

    @Published var accounts: [String] = []
    @Published var account: String? { didSet { UserDefaults.standard.set(account, forKey: Keys.account) } }
    @Published var snapshot: BoxSnapshot?
    @Published var advice: AdviceState = .none
    @Published var flow: ScanFlow = .idle
    @Published var message: String?
    @Published var history: [BoxSnapshot.Header] = []
    @Published var previous: BoxSnapshot.Header?
    @Published var exportURL: URL?
    /// Files to hand to the share sheet (a saved scan's log and result).
    /// What the share sheet is offering; the notification permission is asked when it is dismissed (never over the sheet).
    @Published var shareURLs: [URL] = [] { didSet { if !oldValue.isEmpty, shareURLs.isEmpty, !pagedByHand, commandSetMade { askForNotificationsOnce() } } }
    @Published var busy: String?
    /// The box could not be read: set instead of showing an empty box. Scans cannot be reviewed or saved until it is resolved.
    @Published var boxProblem: String?
    /// The newest version came from a newer app: no restore is offered (it would roll the box back), only "update the app".
    @Published var boxNeedsNewerApp = false

    @Published var scanKind: BoxStore.Kind { didSet { UserDefaults.standard.set(scanKind.rawValue, forKey: Keys.kind) } }
    /// The storage count of a full scan, remembered per account (editable); it picks which command to say.
    @Published var storageCountText: String { didSet { if let a = account { UserDefaults.standard.set(storageCountText, forKey: Keys.count + "." + a) }; refreshReaderSettings() } }

    // The broadcast, as the extension last reported it.
    @Published var broadcast: BroadcastState?
    @Published var now = Date()
    enum Sheet: String, Identifiable { case settings, diagnostics; var id: String { rawValue } }
    /// Settings or Diagnostics. While one is open a finished scan waits (it cannot be presented underneath); it is picked up on close.
    @Published var sheet: Sheet? { didSet { if sheet == nil { checkForFinishedScan() } } }
    private var holdReview: Bool { sheet != nil }
    private var timer: Timer?

    private enum Keys { static let account = "selectedAccount", kind = "scanKind", count = "storageCount", pace = "voicePaceV2", hand = "pagedByHand", voice = "voiceLast.", set = "voiceSet." }

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
            let url = r.reread?.replayURL ?? SharedStore.replayURL
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
            guard case .review(let r) = flow, let url = r.reread?.replayURL ?? SharedStore.replayURL else { return [] }
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
        ReaderSettings.storageCount = storageCount          // for every scan (progress, and when a command scan finishes or pauses)
        ReaderSettings.commandSizes = VoiceCommandFile.setSizes
    }

    /// "Finish now" while a scan is paused: the extension ends it on its next heartbeat.
    func finishPausedScanNow() { if let id = broadcast?.scanId, id != 0 { ReaderSettings.finishRequestedScan = id } }

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
        let key = "\(s.scanId)#\(s.eventSeq)"
        guard UserDefaults.standard.string(forKey: Self.handledKey) != key else { return }
        let n: ScanNotification
        if s.paused {
            n = .paused(scan: s.scanId, event: s.eventSeq, read: s.readCount, storageCount: s.storageCount, lastName: s.pausedCard, lastCP: nil, sizes: VoiceCommandFile.setSizes)
        } else if s.endedAtListEnd {
            let last = s.rows.last
            n = .stopped(scan: s.scanId, event: s.eventSeq, read: s.rows.count, lastName: last?.name, lastCP: last?.cp)
        } else { return }
        UserDefaults.standard.set(key, forKey: Self.handledKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fallbackGraceSeconds) {
            // The state is read again first: a pause notice is only posted if that pause is still the current, unresumed one (the scan may have resumed, finished or been
            // replaced while the app waited); a stop notice only if that scan is still the one that ended.
            guard let now = SharedStore.read(), now.scanId == s.scanId else { return }
            if s.paused, !(now.paused && now.eventSeq == s.eventSeq) { return }
            if !s.paused, !now.endedAtListEnd { return }
            ScanNotifier.exists(n.identifier) { exists in if !exists { ScanNotifier.post(n) } }
        }
    }
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
    var storageCountProblem: String? { StorageCount.problem(for: storageCountText) }

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
        storageCountText = UserDefaults.standard.string(forKey: Keys.count + "." + a) ?? ""
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

    private let notificationActions = NotificationActions()

    init() {
        UNUserNotificationCenter.current().delegate = notificationActions
        ScanNotifier.registerCategories()
        let root = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
            .appendingPathComponent("PogoAssist", isDirectory: true).appendingPathComponent("boxes", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("boxes", isDirectory: true)
        // The UI test starts from a clean install each time: it passes this argument and the app forgets everything first.
        if CommandLine.arguments.contains("-uitest-reset") {
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            try? FileManager.default.removeItem(at: root)
            SharedStore.clear()
            if let c = SharedStore.containerURL { try? FileManager.default.removeItem(at: c.appendingPathComponent("replay.processed")) }
        }
        library = BoxLibrary(root: root)
        scanKind = BoxStore.Kind(rawValue: UserDefaults.standard.string(forKey: Keys.kind) ?? "") ?? .full
        storageCountText = ""   // read per account by loadVoiceRecord once the account is known
        pagedByHand = true   // restorePaging() below: by hand until the commands exist, unless the person chose
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
        refreshBroadcast()
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

    /// Read the selected account's current box (and its cached advice, or start computing it).
    func loadBox() {
        guard let a = account else { snapshot = nil; advice = .none; history = []; previous = nil; boxProblem = nil; boxNeedsNewerApp = false; return }
        // Always asked, not only when the newest version fails to load: any version from a newer app means nothing may be written on top of it.
        if let n = library.newerVersion(account: a) {
            snapshot = nil; history = (try? library.history(account: a)) ?? []; previous = nil
            boxNeedsNewerApp = true
            boxProblem = "Version \(n) of the box for \(a) was saved by a newer version of the app, so this version cannot open this box. Update the app. Nothing has been changed, and scanning and saving are paused."
            loadAdvice(); loadScans()
            return
        }
        do {
            snapshot = try library.current(account: a)
            history = try library.history(account: a)
            previous = try library.previousVersion(account: a)
            boxProblem = nil; boxNeedsNewerApp = false
        } catch {
            // Not an empty box: the newest version is damaged. Nothing is saved on top of it until the person restores a readable one.
            snapshot = nil; history = (try? library.history(account: a)) ?? []; previous = nil
            boxNeedsNewerApp = false
            boxProblem = "The newest saved version of the box for \(a) cannot be read (\(Self.plain(error))). Your earlier versions are still on this device."
        }
        loadAdvice()
        loadScans()
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
        do {
            let (new, notice) = try await worker.run { engine -> (BoxSnapshot, String?) in
                var notice: String?
                let snap = try lib.mutate(account: a, reason: .edit, note: "Corrected \(label)") { entries in
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

    /// Returns nil on success, else the reason in plain words.
    func renameAccount(_ old: String, to new: String) async -> String? {
        let lib = library
        do {
            try await worker.run { _ in try lib.renameAccount(from: old, to: new) }
            let name = new.trimmingCharacters(in: .whitespacesAndNewlines)
            accounts = (try? library.accounts()) ?? accounts
            for p in VoiceCommandFile.Pace.allCases {
                let k = { (a: String) in Keys.voice + a + "." + p.rawValue }
                if let d = UserDefaults.standard.data(forKey: k(old)) { UserDefaults.standard.set(d, forKey: k(name)); UserDefaults.standard.removeObject(forKey: k(old)) }
            }
            // The one-time set record and the remembered storage count follow the name; the old-name records go, so a stale tap-set record under
            // the old name cannot keep the wrong-screen warning on.
            for key in [Keys.set, Keys.count + "."] {
                if let d = UserDefaults.standard.object(forKey: key + old) { UserDefaults.standard.set(d, forKey: key + name); UserDefaults.standard.removeObject(forKey: key + old) }
            }
            if account == old { account = name; loadBox(); loadVoiceRecord() } else { refreshDeviceRecords() }
            return nil
        } catch { return Self.plain(error) }
    }

    @Published var scans: [BoxStore.Summary] = []

    func loadScans() {
        guard let a = account else { scans = []; return }
        scans = (try? library.store.list(account: a).scans) ?? []
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
        snapshot = snap
        history = (try? library.history(account: snap.account)) ?? history
        previous = try? library.previousVersion(account: snap.account)
        loadAdvice()
        loadScans()
    }

    // MARK: - history

    /// Make the newest version that can be read the current box again (the newest one is damaged).
    func restoreLatestReadable() async {
        guard let a = account else { return }
        let lib = library
        do {
            let snap = try await worker.run { _ in try lib.restoreLatestReadable(account: a) }
            afterCommit(snap)
            boxProblem = nil
            message = "Restored version \(snap.restoredFrom ?? 0), the newest one that can be read."
        } catch { message = "No saved version of this box could be restored: \(Self.plain(error))" }
    }

    func restore(seq: Int) async {
        guard let a = account else { return }
        let lib = library
        do {
            let snap = try await worker.run { _ in try lib.restore(account: a, seq: seq) }
            afterCommit(snap)
            message = "Restored version \(seq) of the box for \(a)."
        } catch { message = Self.plain(error) }
    }

    func restorePrevious() async {
        guard let a = account else { return }
        let lib = library
        do {
            let snap = try await worker.run { _ in try lib.restorePrevious(account: a) }
            afterCommit(snap)
            message = "Went back to version \(snap.restoredFrom ?? 0) of the box for \(a)."
        } catch { message = Self.plain(error) }
    }

    // MARK: - CSV export

    func exportCSV() async {
        guard let snap = snapshot, !snap.entries.isEmpty else { message = "There is nothing to export yet. Scan some Pokémon first."; return }
        busy = "Making the CSV"
        defer { busy = nil }
        let entries = snap.entries, name = snap.account, date = snap.scanDate ?? snap.createdAt
        do {
            let url = try await worker.run { engine -> URL in
                let csv = try engine.csv(rows: Self.csvRows(entries), scanDate: date)
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
                let safe = name.filter { $0.isLetter || $0.isNumber || $0 == "-" }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("pogo-box-\(safe.isEmpty ? "box" : safe)-\(f.string(from: date)).csv")
                try Data(csv.utf8).write(to: url, options: .atomic)
                return url
            }
            exportURL = url
        } catch { message = "The CSV could not be made: \(Self.plain(error))" }
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

    /// A broadcast has finished (or died without saying so) and its replay log has not been through review yet: read it.
    func checkForFinishedScan() {
        guard !holdReview, account != nil, boxProblem == nil, !isReviewing, !live, let state = broadcast, state.finished || endedWithoutFinish,
              let sig = ReplayMarker.unprocessedSignature() else { return }
        startReview(signature: sig)
    }

    func startReview(signature: String) {
        guard let url = SharedStore.replayURL, let a = account, boxProblem == nil else { return }
        flow = .processing("Reading the scan")
        let asked = scanKind, date = Date(), lib = library
        // How the scan was paged is what the extension was told when it started (a command at its period, or by hand), not a setting changed since.
        let period: Double? = { if let b = broadcast { return b.commandPeriod }; return pagedByHand ? nil : pace.every }()
        let paging = period == nil ? PagingHint(pagedByCommand: false) : PagingHint(pagedByCommand: true, expectedPeriod: period, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
        let ended = broadcast?.endedAtListEnd ?? false, byPerson = broadcast?.stoppedByPerson ?? false, logFull = broadcast?.replayLogTruncated ?? false, logFailed = broadcast?.replayLogFailed ?? false
        // The count the scan was started with (captured in its state), not the field as it reads now: it may have been edited since.
        let typed = broadcast.map { $0.storageCount } ?? storageCount
        Task {
            do {
                let (outcome, plan, seconds, base, seq, kind, note, advice, stop) = try await worker.run { engine -> (ScanPipeline.Outcome, BoxMerge.Plan, Double, [BoxEntry], Int?, BoxStore.Kind, String?, ScanKindAdvice.Decision, String?) in
                    let outcome = try ScanPipeline.process(replay: url, engine: engine, paging: paging)
                    // A full scan lists everything unseen as "Not seen in this scan" (all kept unless marked), but it is only the default when the list can be known to have ended.
                    var kind = asked, note: String?
                    let d = ScanKindAdvice.decide(endedAtListEnd: ended, pokemonRead: outcome.scan.rows.count, typedCount: typed, logTruncated: logFull, logFailed: logFailed, commandPeriod: period)
                    if asked == .full && !d.fullIsSound { kind = .partial; note = d.reason }
                    let current = try lib.current(account: a)   // the box as it is when the plan is made
                    let entries = current?.entries ?? []
                    let t = Date()
                    let plan = BoxMerge.plan(scanned: outcome.scan.rows, unmatched: outcome.scan.unmatched, into: entries, kind: kind, scanDate: date, gameMaster: try .bundled())
                    // Where it stopped: the last Pokémon, how many, whether the appraisal had closed (from the whole log, the tail the end marker cuts included).
                    var stop: String?
                    if ended || byPerson {
                        let last = outcome.scan.rows.last
                        let closed = ScanStop.appraisalClosed(lines: ReplayLog.lines(in: url))
                        let ran = ScanStop.ranOut(read: outcome.scan.rows.count, typedCount: typed, full: asked == .full, commandPeriod: period)
                        stop = ScanStop.summary(lastName: last?.display, lastCP: last?.cp, read: outcome.scan.rows.count, appraisalClosed: closed, ranOut: ran,
                                                commandKnown: asked == .full && typed != nil, nearestSize: ScanStop.nearestSize(read: outcome.scan.rows.count, commandPeriod: period),
                                                matchSentence: ScanKindAdvice.matchSentence(pokemonRead: outcome.scan.rows.count, decision: d),
                                                paused: ScanStop.pauseNames(outcome.pauses, rows: outcome.scan.rows, finishedByPerson: byPerson), byPerson: byPerson)
                    }
                    return (outcome, plan, Date().timeIntervalSince(t), entries, current?.seq, kind, note, d, stop)
                }
                let t = outcome.timings
                NSLog("pogo timings: load %.2f finish %.2f refine %.2f merge %.2f s, %d rows", t.load, t.finish, t.refine, seconds, outcome.scan.rows.count)
                var review = Review(account: a, kind: kind, outcome: outcome, plan: plan, base: base, storageCount: asked == .full ? typed : nil, signature: signature, mergeSeconds: seconds, paging: StoredPaging(paging), boxSeq: seq)
                review.endedAtListEnd = ended; review.kindNote = note; review.advice = advice; review.stopSummary = stop
                flow = .review(review)
            } catch {
                flow = .failed(message: Self.plain(error), signature: signature)
            }
        }
    }

    /// Change the scan kind on the review screen; the merge is recomputed (it is pure and quick).
    func setReviewKind(_ kind: BoxStore.Kind) async {
        guard case .review(var r) = flow, r.kind != kind else { return }
        scanKind = kind
        let base = r.base, rows = r.outcome.scan.rows, date = r.plan.scanDate
        let unmatched = r.outcome.scan.unmatched
        let plan = try? await worker.run { _ in BoxMerge.plan(scanned: rows, unmatched: unmatched, into: base, kind: kind, scanDate: date, gameMaster: try .bundled()) }
        guard let plan, case .review = flow else { return }
        r.kind = kind; r.plan = plan; r.resolutions = [:]; r.markedForRemoval = []
        flow = .review(r)
    }

    func resolve(_ scanned: Int, _ resolution: BoxMerge.Resolution?) {
        guard case .review(var r) = flow else { return }
        r.resolutions[scanned] = resolution
        flow = .review(r)
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
        busy = "Saving to the box"
        defer { busy = nil }
        let lib = library
        do {
            let snap = try await worker.run { engine -> BoxSnapshot in
                // Refused (not written over it) if the box has changed since this review was prepared.
                let entries = try BoxMerge.apply(r.plan, resolutions: r.resolutions, keepGone: r.keepGone, to: r.base, engine: engine)
                // A scan read again: a new box version from the earlier box plus the new read; the scan itself is not saved twice.
                if let plan = r.reread { return try lib.commitReread(plan, entries: entries, account: r.account, expectedCurrentSeq: .some(r.boxSeq)) }
                let log = SharedStore.replayURL.flatMap { try? Data(contentsOf: $0) }
                let current = try lib.current(account: r.account)
                guard current?.seq == r.boxSeq else { throw BoxLibrary.Failure.boxChanged }
                let scan = try lib.store.save(r.outcome.scan, account: r.account, scanDate: r.plan.scanDate, source: "broadcast", kind: r.kind, storageCount: r.storageCount, replayLog: log, paging: r.paging,
                                           refineChanges: r.outcome.changes.map { "\($0.kind.rawValue): \($0.detail)" },
                                           reviewActions: ScanReportBuilder.reviewLines(plan: r.plan, resolutions: r.resolutions, keepGone: r.keepGone, base: r.base),
                                           reportSentAt: r.reportSentAt, reportHash: r.reportHash)
                let n = r.outcome.scan.rows.count
                let note = (r.kind == .full ? "Full scan" : "Add and update") + ", \(n) Pokémon"
                return try lib.commit(account: r.account, entries: entries, reason: .scan, note: note, scanId: scan.id, scanKind: r.kind, scanDate: r.plan.scanDate, expectedCurrentSeq: .some(r.boxSeq))
            }
            if r.reread == nil { ReplayMarker.markProcessed(r.signature) }
            flow = .idle
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
        if let plan = r.reread, let a = account, let scan = scans.first(where: { $0.id == plan.scan.id }) { flow = .idle; _ = a; rereadScan(scan); return }
        let lib = library, rows = r.outcome.scan.rows, unmatched = r.outcome.scan.unmatched, kind = r.kind, date = r.plan.scanDate, a = r.account
        do {
            let (plan, base, seq) = try await worker.run { _ -> (BoxMerge.Plan, [BoxEntry], Int?) in
                let cur = try lib.current(account: a)
                let entries = cur?.entries ?? []
                return (BoxMerge.plan(scanned: rows, unmatched: unmatched, into: entries, kind: kind, scanDate: date, gameMaster: try .bundled()), entries, cur?.seq)
            }
            var n = r; n.plan = plan; n.base = base; n.boxSeq = seq; n.resolutions = [:]; n.markedForRemoval = []
            flow = .review(n)
            if a == account { loadBox() }
        } catch { message = "The box could not be read again: \(Self.plain(error))" }
    }

    func discardReview() {
        switch flow {
        case .review(let r): if r.reread == nil { ReplayMarker.markProcessed(r.signature) }
        case .failed(_, let sig): if !sig.hasPrefix(Self.rereadPrefix) { ReplayMarker.markProcessed(sig) }
        default: break
        }
        flow = .idle
    }

    private static let rereadPrefix = "reread:"

    /// Read a saved scan again with the latest rules, against the box as it was before that scan was saved. Opens the normal review
    /// screen; nothing changes until Save, and Discard changes nothing.
    func rereadScan(_ scan: BoxStore.Summary) {
        guard let a = account, !isReviewing, boxProblem == nil else { return }
        sheet = nil
        flow = .processing("Reading the saved scan again")
        let lib = library, signature = Self.rereadPrefix + scan.id
        Task {
            do {
                let (plan, outcome, merge, seconds, seq) = try await worker.run { engine -> (RereadPlan, ScanPipeline.Outcome, BoxMerge.Plan, Double, Int?) in
                    let plan = try lib.prepareReread(account: a, scanId: scan.id)
                    let outcome = try ScanPipeline.process(replay: plan.replayURL, engine: engine, paging: plan.paging)
                    let t = Date()
                    let merge = BoxMerge.plan(scanned: outcome.scan.rows, unmatched: outcome.scan.unmatched, into: plan.baseEntries, kind: plan.scan.kind, scanDate: plan.scan.scanDate, gameMaster: try .bundled())
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
            let id = String(sig.dropFirst(Self.rereadPrefix.count))
            flow = .idle
            if let scan = scans.first(where: { $0.id == id }) { rereadScan(scan) }
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

    /// The signature of a replay log that exists and has not been reviewed, else nil.
    static func unprocessedSignature() -> String? {
        guard let sig = signature() else { return nil }
        let done = markerURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        return done == sig ? nil : sig
    }

    static func markProcessed(_ signature: String) {
        guard let url = markerURL else { return }
        try? Data(signature.utf8).write(to: url, options: .atomic)
    }
}
