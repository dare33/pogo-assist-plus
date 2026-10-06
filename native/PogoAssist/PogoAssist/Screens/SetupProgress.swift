import SwiftUI
import UserNotifications

/// Where the "Get ready to scan" checklist is up to, and whether setup counts as done.
///
/// A step is `checked` when the app itself verified it (notifications authorised in iOS, the command set made on this phone: the app's own record), `said` when the
/// person confirmed it, and `todo` otherwise. The person's confirmations are stored under the AppStorage key `setup.steps` (the step numbers, comma separated), so they
/// survive leaving the app and a relaunch; what the app can verify is re-checked when the app becomes active (`refresh`).
///
/// Setup counts as done (`isDone`) when all six steps are ticked, or a scan paged by the voice command has been saved on this phone (`pagedScanSaved`, below), or the person
/// turned on "My phone is set up" (`phoneSetUp`). The last one makes every step show as "Marked complete" without erasing what the app verified.
@MainActor
final class SetupProgress: ObservableObject {
    static let stepsKey = "setup.steps"
    static let switchesKey = "setup.switches"
    static let phoneSetUpKey = "setup.phoneSetUp"
    /// Set when a scan paged by a command is saved (`AppModel.saveReview`) and, once, from the scans already saved (`backfillFromSavedScans`): a saved scan's summary does
    /// not carry how it was paged, so this flag is the app's own record of "a scan paged by the voice command has completed on this phone".
    static let pagedScanKey = "setup.pagedScanSaved"
    static let count = 6

    enum StepState: Equatable { case checked, said, todo }
    enum NotificationState: Equatable { case unknown, notAsked, denied, authorised }

    @Published private(set) var said: Set<Int>
    @Published private(set) var switches: Set<Int>
    @Published private(set) var notifications: NotificationState = .unknown
    @Published private(set) var pagedScanSaved: Bool
    @Published var phoneSetUp: Bool { didSet { UserDefaults.standard.set(phoneSetUp, forKey: Self.phoneSetUpKey) } }

    /// The command set was made on this phone (the app's record, `AppModel.commandSetMade`).
    private let commandsMade: () -> Bool
    private var backfilled = false

    init(commandsMade: @escaping () -> Bool) {
        let d = UserDefaults.standard
        self.commandsMade = commandsMade
        said = Self.numbers(d.string(forKey: Self.stepsKey) ?? "")
        switches = Self.numbers(d.string(forKey: Self.switchesKey) ?? "")
        phoneSetUp = d.bool(forKey: Self.phoneSetUpKey)
        pagedScanSaved = d.bool(forKey: Self.pagedScanKey)
        refresh()
    }

    private static func numbers(_ raw: String) -> Set<Int> { Set(raw.split(separator: ",").compactMap { Int($0) }) }
    private static func raw(_ set: Set<Int>) -> String { set.sorted().map(String.init).joined(separator: ",") }

    // MARK: state

    func isVerified(_ step: Int) -> Bool {
        switch step {
        case 1: return notifications == .authorised
        case 2: return commandsMade()
        default: return false
        }
    }
    func state(_ step: Int) -> StepState {
        if isVerified(step) { return .checked }
        if phoneSetUp || said.contains(step) { return .said }
        return .todo
    }
    var doneCount: Int { (1...Self.count).filter { state($0) != .todo }.count }
    var stepsLeft: Int { Self.count - doneCount }
    var nextStep: Int? { (1...Self.count).first { state($0) == .todo } }
    var isDone: Bool { doneCount == Self.count || phoneSetUp || pagedScanSaved }

    // MARK: changes

    /// The person says the step is done. What the app verified is not stored: it is checked again each time.
    func confirm(_ step: Int) {
        guard !isVerified(step) else { return }
        said.insert(step)
        UserDefaults.standard.set(Self.raw(said), forKey: Self.stepsKey)
    }
    func toggleSwitch(_ index: Int) {
        if switches.contains(index) { switches.remove(index) } else { switches.insert(index) }
        UserDefaults.standard.set(Self.raw(switches), forKey: Self.switchesKey)
    }

    /// Re-reads what the app can check: the notification permission (the setting the person may have just changed in iOS Settings) and the saved flag.
    func refresh() {
        pagedScanSaved = UserDefaults.standard.bool(forKey: Self.pagedScanKey)
        #if DEBUG
        if let fake = UserDefaults.standard.string(forKey: "fake-notifications") {
            notifications = fake == "authorised" ? .authorised : fake == "denied" ? .denied : .notAsked
            return
        }
        #endif
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let s: NotificationState
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: s = .authorised
            case .denied: s = .denied
            default: s = .notAsked
            }
            Task { @MainActor [weak self] in if self?.notifications != s { self?.notifications = s } }
        }
    }

    /// The system's permission prompt (alert and sound, as the scan notifications need), then a re-check.
    func askForNotifications() {
        UserDefaults.standard.set(true, forKey: "askedForNotifications")
        #if DEBUG
        if UserDefaults.standard.string(forKey: "fake-notifications") != nil { return }
        #endif
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: saved flag

    func notePagedScanSaved() {
        UserDefaults.standard.set(true, forKey: Self.pagedScanKey)
        pagedScanSaved = true
    }

    /// Scans saved before the flag existed: once per launch, if the flag is not set, look at how the account's saved scans were paged (newest first, until one was paged by a
    /// command). The files are read on the engine's one queue, as the store requires.
    func backfillFromSavedScans(model: AppModel) {
        guard !pagedScanSaved, !backfilled, let account = model.account else { return }
        backfilled = true
        let library = model.library
        Task {
            let found = try? await model.worker.run { _ -> Bool in
                let ids = (try? library.store.list(account: account).scans.map(\.id)) ?? []
                return ids.contains { (try? library.store.load(account: account, id: $0))?.paging?.pagedByCommand == true }
            }
            if found == true { notePagedScanSaved() }
        }
    }

    /// The steps' titles and checklist sub-lines, in the design's order and wording.
    struct Info {
        let title: String      // the instruction, as the step screen's title
        let rowTitle: String   // the checklist row
        let rowSub: String
    }
    static let info: [Info] = [
        .init(title: "Allow notifications", rowTitle: "Allow notifications", rowSub: "So a paused or ended scan can tell you"),
        .init(title: "Make the voice commands", rowTitle: "Make the voice commands", rowSub: "One file with all 13 commands"),
        .init(title: "Import the voice commands", rowTitle: "Import them into Voice Control", rowSub: "Voice Control › Commands › Import"),
        .init(title: "Turn off three Voice Control switches", rowTitle: "Three Voice Control switches", rowSub: "Confirmation, hints, attention"),
        .init(title: "A quiet Focus for scanning", rowTitle: "A quiet Focus for scanning", rowSub: "Stops banners covering the CP"),
        .init(title: "Allow alerts while sharing the screen", rowTitle: "Alerts while sharing the screen", rowSub: "So a pause or the end of a scan reaches you"),
    ]
}
