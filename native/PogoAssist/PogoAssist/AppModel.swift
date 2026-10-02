import SwiftUI
import PogoBox
import PogoReader

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
    @Published var shareURLs: [URL] = []
    @Published var busy: String?

    @Published var scanKind: BoxStore.Kind { didSet { UserDefaults.standard.set(scanKind.rawValue, forKey: Keys.kind) } }
    @Published var storageCountText: String { didSet { UserDefaults.standard.set(storageCountText, forKey: Keys.count) } }

    // The broadcast, as the extension last reported it.
    @Published var broadcast: BroadcastState?
    @Published var now = Date()
    enum Sheet: String, Identifiable { case settings, diagnostics; var id: String { rawValue } }
    /// Settings or Diagnostics. While one is open a finished scan waits (it cannot be presented underneath); it is picked up on close.
    @Published var sheet: Sheet? { didSet { if sheet == nil { checkForFinishedScan() } } }
    private var holdReview: Bool { sheet != nil }
    private var timer: Timer?

    private enum Keys { static let account = "selectedAccount", kind = "scanKind", count = "storageCount", pace = "voicePaceV2", voice = "voiceLast." }

    // MARK: - the Voice Control command

    /// What the last command made for an account was built for. The app cannot know whether it was imported on the phone.
    struct VoiceRecord: Codable, Equatable { var storageCount: Int; var covers: Int; var pace: VoiceCommandFile.Pace; var date: Date }

    @Published var pace: VoiceCommandFile.Pace { didSet { UserDefaults.standard.set(pace.rawValue, forKey: Keys.pace) } }
    /// The last command made for each mode of the selected account: each mode is its own command in Voice Control.
    @Published var voiceRecords: [VoiceCommandFile.Pace: VoiceRecord] = [:]
    var voiceLast: VoiceRecord? { voiceRecords[pace] }

    /// What the Scan screen should warn about for the chosen mode, or nil: no command made for it yet, or one made for fewer
    /// Pokémon than the typed count needs.
    var commandWarning: String? {
        guard let count = storageCount else { return nil }
        guard let last = voiceRecords[pace] else { return "No \(pace.title) command has been made yet. Get the command and import it, or Voice Control will not know \"\(pace.commandName)\"." }
        if VoiceCommandFile.steps(storageCount: count) > last.covers { return "Your count is higher than the \(pace.title) command covers. Get the command again and import it, or Voice Control will play the old one." }
        return nil
    }

    /// Screen size in points, for the tap position check.
    var screenSize: CGSize { UIScreen.main.bounds.size }
    var offeredPaces: [VoiceCommandFile.Pace] { VoiceCommandFile.Pace.offered(tapAvailable: tapAvailable) }
    var tapAvailable: Bool { VoiceCommandFile.tapPoint(width: Double(screenSize.width), height: Double(screenSize.height)) != nil }

    var storageCount: Int? { Int(storageCountText.trimmingCharacters(in: .whitespaces)).flatMap { $0 >= 1 ? $0 : nil } }

    func loadVoiceRecord() {
        voiceRecords = [:]
        guard let a = account else { return }
        for p in VoiceCommandFile.Pace.allCases {
            if let data = UserDefaults.standard.data(forKey: Keys.voice + a + "." + p.rawValue), let r = try? JSONDecoder().decode(VoiceRecord.self, from: data) { voiceRecords[p] = r }
        }
    }

    /// The device's language for the command, as Voice Control writes it (en_AU).
    static var voiceLocale: String {
        Locale.current.identifier.split(separator: "@").first.map { $0.replacingOccurrences(of: "-", with: "_") } ?? "en_AU"
    }

    /// Make the commands file for the typed storage count and hand it to the share sheet (Save to Files, AirDrop).
    func getCommand() async {
        guard let count = storageCount else { message = "Type how many Pokémon are in your storage first."; return }
        var pace = self.pace
        if !offeredPaces.contains(pace) { pace = offeredPaces[0]; self.pace = pace }
        let size = VoiceCommandFile.sizing(storageCount: count, pace: pace)
        let tap = pace.isTap ? VoiceCommandFile.tapPoint(width: Double(screenSize.width), height: Double(screenSize.height)) : nil
        let width = Double(screenSize.width), locale = Self.voiceLocale
        busy = "Making the command"
        defer { busy = nil }
        do {
            let url = try await worker.run { _ -> URL in
                let data = try VoiceCommandFile.make(count: size.steps, pace: pace, batch: size.batch, locale: locale, tap: tap, screenWidth: width)
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent(pace.fileName(count: count))
                try data.write(to: url, options: .atomic)
                return url
            }
            if let a = account {
                let rec = VoiceRecord(storageCount: count, covers: size.covers, pace: pace, date: Date())
                if let d = try? JSONEncoder().encode(rec) { UserDefaults.standard.set(d, forKey: Keys.voice + a + "." + pace.rawValue) }
                voiceRecords[pace] = rec
            }
            shareURLs = [url]
        } catch { message = "The command could not be made: \(Self.plain(error))" }
    }

    init() {
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
        storageCountText = UserDefaults.standard.string(forKey: Keys.count) ?? ""
        // Tap is the default where it is available (the owner's choice after testing); the setting is stored under a new key so it applies once.
        let tapOK = VoiceCommandFile.tapPoint(width: Double(UIScreen.main.bounds.width), height: Double(UIScreen.main.bounds.height)) != nil
        let offered = VoiceCommandFile.Pace.offered(tapAvailable: tapOK)
        let stored = VoiceCommandFile.Pace(rawValue: UserDefaults.standard.string(forKey: Keys.pace) ?? "")
        pace = stored.flatMap { offered.contains($0) ? $0 : nil } ?? offered[0]
        account = UserDefaults.standard.string(forKey: Keys.account)
        reloadAccounts()
        loadBox()
        loadVoiceRecord()
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
        guard let a = account else { snapshot = nil; advice = .none; history = []; previous = nil; return }
        do {
            snapshot = try library.current(account: a)
            history = try library.history(account: a)
            previous = try library.previousVersion(account: a)
        } catch {
            snapshot = nil; history = []; previous = nil
            message = "The box for \(a) could not be read: \(error.localizedDescription) Your other versions may still be restorable from Settings."
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

    func correct(_ id: String, _ edit: BoxMerge.Edit) async -> CorrectionResult {
        guard let a = account, let snap = snapshot, let e = snap.entries.first(where: { $0.id == id }) else { return CorrectionResult(error: "That Pokémon is no longer in the box.", notice: nil) }
        let lib = library
        do {
            let (new, notice) = try await worker.run { engine -> (BoxSnapshot, String?) in
                var fixed = try BoxMerge.correct(e, with: edit, gameMaster: try .bundled())
                // The level and dust follow the corrected values: the JavaScript solver is run again for this Pokémon.
                var notice: String?
                if edit.ivs != nil || edit.cp != nil || edit.hp != nil || edit.speciesName != nil { (fixed, notice) = LevelSolve.apply(to: fixed, engine: engine) }
                var entries = snap.entries
                if let i = entries.firstIndex(where: { $0.id == id }) { entries[i] = fixed }
                return (try lib.commit(account: a, entries: entries, reason: .edit, note: "Corrected \(fixed.row.title)", scanKind: snap.scanKind, scanDate: snap.scanDate), notice)
            }
            afterCommit(new)
            return CorrectionResult(error: nil, notice: notice)
        } catch { return CorrectionResult(error: Self.plain(error), notice: nil) }
    }

    /// Remove one Pokémon from the box, as a new box version (the earlier version still has it).
    func deleteEntry(_ id: String) async {
        guard let a = account, let snap = snapshot, let e = snap.entries.first(where: { $0.id == id }) else { return }
        let lib = library
        do {
            let new = try await worker.run { _ in
                try lib.commit(account: a, entries: snap.entries.filter { $0.id != id }, reason: .edit, note: "Removed \(e.row.title), CP \(e.row.cp)", scanKind: snap.scanKind, scanDate: snap.scanDate)
            }
            afterCommit(new)
        } catch { message = "The Pokémon could not be removed: \(Self.plain(error))" }
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
            if account == old { account = name; loadBox(); loadVoiceRecord() }
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

    func markChecked(_ id: String) async {
        guard let a = account, let snap = snapshot, let e = snap.entries.first(where: { $0.id == id }) else { return }
        let lib = library
        do {
            let new = try await worker.run { _ -> BoxSnapshot in
                var entries = snap.entries
                if let i = entries.firstIndex(where: { $0.id == id }) { entries[i] = BoxMerge.markChecked(e) }
                return try lib.commit(account: a, entries: entries, reason: .edit, note: "Checked \(e.row.title)", scanKind: snap.scanKind, scanDate: snap.scanDate)
            }
            afterCommit(new)
        } catch { message = Self.plain(error) }
    }

    private func afterCommit(_ snap: BoxSnapshot) {
        snapshot = snap
        history = (try? library.history(account: snap.account)) ?? history
        previous = try? library.previousVersion(account: snap.account)
        loadAdvice()
        loadScans()
    }

    // MARK: - history

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
        checkForFinishedScan()
    }

    var secondsSinceUpdate: Double { max(0, now.timeIntervalSince(broadcast?.updated ?? now)) }
    var endedWithoutFinish: Bool { broadcast.map { !$0.finished && secondsSinceUpdate >= Tuning.staleStateSeconds } ?? false }
    var live: Bool { broadcast.map { !$0.finished && !endedWithoutFinish } ?? false }

    // MARK: - scan review

    var isReviewing: Bool { if case .idle = flow { return false } else { return true } }

    /// A broadcast has finished (or died without saying so) and its replay log has not been through review yet: read it.
    func checkForFinishedScan() {
        guard !holdReview, account != nil, !isReviewing, !live, let state = broadcast, state.finished || endedWithoutFinish,
              let sig = ReplayMarker.unprocessedSignature() else { return }
        startReview(signature: sig)
    }

    func startReview(signature: String) {
        guard let url = SharedStore.replayURL, let a = account else { return }
        flow = .processing("Reading the scan")
        let entries = entries, kind = scanKind, date = Date()
        let count = Int(storageCountText.trimmingCharacters(in: .whitespaces))
        Task {
            do {
                let (outcome, plan, seconds) = try await worker.run { engine -> (ScanPipeline.Outcome, BoxMerge.Plan, Double) in
                    let outcome = try ScanPipeline.process(replay: url, engine: engine)
                    let t = Date()
                    let plan = BoxMerge.plan(scanned: outcome.scan.rows, into: entries, kind: kind, scanDate: date, gameMaster: try .bundled())
                    return (outcome, plan, Date().timeIntervalSince(t))
                }
                let t = outcome.timings
                NSLog("pogo timings: load %.2f finish %.2f refine %.2f merge %.2f s, %d rows", t.load, t.finish, t.refine, seconds, outcome.scan.rows.count)
                flow = .review(Review(account: a, kind: kind, outcome: outcome, plan: plan, base: entries, storageCount: count, signature: signature, mergeSeconds: seconds))
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
        let plan = try? await worker.run { _ in BoxMerge.plan(scanned: rows, into: base, kind: kind, scanDate: date, gameMaster: try .bundled()) }
        guard let plan, case .review = flow else { return }
        r.kind = kind; r.plan = plan; r.resolutions = [:]
        flow = .review(r)
    }

    func resolve(_ scanned: Int, _ resolution: BoxMerge.Resolution?) {
        guard case .review(var r) = flow else { return }
        r.resolutions[scanned] = resolution
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
            let snap = try await worker.run { _ -> BoxSnapshot in
                let entries = try BoxMerge.apply(r.plan, resolutions: r.resolutions, to: r.base)
                let log = SharedStore.replayURL.flatMap { try? Data(contentsOf: $0) }
                let scan = try lib.store.save(r.outcome.scan, account: r.account, scanDate: r.plan.scanDate, source: "broadcast", kind: r.kind, storageCount: r.storageCount, replayLog: log)
                let n = r.outcome.scan.rows.count
                let note = (r.kind == .full ? "Full scan" : "Add and update") + ", \(n) Pokémon"
                return try lib.commit(account: r.account, entries: entries, reason: .scan, note: note, scanId: scan.id, scanKind: r.kind, scanDate: r.plan.scanDate)
            }
            ReplayMarker.markProcessed(r.signature)
            flow = .idle
            if r.account == account { afterCommit(snap) }
        } catch {
            message = "The scan could not be saved: \(Self.plain(error)) Nothing in the box has changed. You can try again or discard the scan."
        }
    }

    func discardReview() {
        switch flow {
        case .review(let r): ReplayMarker.markProcessed(r.signature)
        case .failed(_, let sig): ReplayMarker.markProcessed(sig)
        default: break
        }
        flow = .idle
    }

    func retryReview() {
        if case .failed(_, let sig) = flow { startReview(signature: sig) }
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
