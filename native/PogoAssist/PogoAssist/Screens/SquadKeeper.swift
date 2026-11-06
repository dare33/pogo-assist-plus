import SwiftUI
import PogoBox

/// Design pass 2, CONCEPTS rule 27 (D58): the squads and picks the squad screens keep, per account, on the phone. One `SquadStore` per account is written
/// to `UserDefaults` as JSON under `squads.<account name>` (the way the stardust setting is kept), so a re-scan, a relaunch and leaving a screen all keep it.
/// The rules (what is dropped when an event ends, what empties when a copy leaves the box) are `SquadStore`'s own; this class only loads, applies them and saves.
///
/// Each squad screen owns one keeper (`@StateObject`) and calls `attach` when it appears and when the account or the box changes. Every change is written at once,
/// so a screen opened later reads what the last one left.
@MainActor
final class SquadKeeper: ObservableObject {
    @Published private(set) var store = SquadStore()
    /// The account the store belongs to (nil before the first attach).
    private(set) var account: String?

    /// The defaults key of an account's squads. `AppModel.moveAccountKeys` moves it with a rename.
    nonisolated static let keyPrefix = "squads."

    nonisolated static func key(_ account: String) -> String { keyPrefix + account }

    /// Reads the account's store and applies the keeping rules (`SquadStore.refreshed`) for today's date, the rotation and the box's ids. `boxIds` is nil while the
    /// box is not loaded yet: the picks are then left alone. A loaded box with no copies is an empty set, and every pick is dropped (the last copy was deleted).
    func attach(account: String?, today: String, rotation: [HubData.RotationRow], boxIds: Set<String>?) {
        let changedAccount = account != self.account
        self.account = account
        guard let account else { store = SquadStore(); return }
        var s = changedAccount || store == SquadStore() ? Self.load(account) : store
        if let boxIds { s = s.refreshed(today: today, rotation: rotation, boxIds: boxIds) }
        if s != store { store = s }
        if boxIds != nil { Self.save(s, for: account) }
    }

    /// Changes the store and writes it.
    func update(_ change: (inout SquadStore) -> Void) {
        var s = store
        change(&s)
        guard s != store else { return }
        store = s
        if let account { Self.save(s, for: account) }
    }

    nonisolated static func load(_ account: String) -> SquadStore {
        guard let data = UserDefaults.standard.data(forKey: key(account)), let s = try? JSONDecoder().decode(SquadStore.self, from: data) else { return SquadStore() }
        return s
    }

    nonisolated static func save(_ store: SquadStore, for account: String) {
        if let data = try? JSONEncoder().encode(store) { UserDefaults.standard.set(data, forKey: key(account)) }
    }
}

extension AppModel {
    /// What the squad rules are given: the advice, the box, the game master, the Hub's data, the tier tables and today's date. nil while the advice is not ready or
    /// the bundled data cannot be read.
    func squadContext() -> HubContext? {
        guard let advice = hubAdvice, let hub = try? HubData.bundled(), let gm = try? GameMaster.bundled(), let table = try? TierTable.bundled() else { return nil }
        return HubContext(advice: advice, entries: entries, gm: gm, hub: hub, table: table, today: HubModel.today())
    }
}

/// Loads the keeper's squads when a squad screen appears and applies the keeping rules again when the account, the box or the advice changes (a re-scan saved, a
/// switch of account). The box is waited for: until it is loaded the box ids the rules need are not known.
struct SquadAttach: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var keeper: SquadKeeper
    /// The screen's drafts, which follow the same account and box (nil on a screen with none).
    var workspace: SquadWorkspace? = nil

    func body(content: Content) -> some View {
        content
            .onAppear(perform: attach)
            .onChange(of: model.account) { _, _ in attach() }
            .onChange(of: model.snapshot?.seq) { _, _ in attach() }
            .onChange(of: model.boxLoaded) { _, _ in attach() }
            .onChange(of: model.hubAdvice != nil) { _, _ in attach() }
    }

    private func attach() {
        let loaded = model.boxLoaded && model.boxProblem == nil
        let boxIds: Set<String>? = loaded ? Set(model.entries.map(\.id)) : nil
        keeper.attach(account: model.account, today: HubModel.today(), rotation: (try? HubData.bundled())?.rotation ?? [], boxIds: boxIds)
        workspace?.attach(account: model.account, boxIds: boxIds)
    }
}

extension View {
    /// Keeps `keeper` in step with the selected account's saved squads.
    func keepsSquads(_ keeper: SquadKeeper, _ workspace: SquadWorkspace? = nil) -> some View { modifier(SquadAttach(keeper: keeper, workspace: workspace)) }
}

// MARK: Current, Available and Best (pass 2-5, rule 27)

/// What one squad screen holds while the player is on it and drops when they leave: the tab each squad is on and the drafts (edits of Available and Best), never stored
/// (`SquadDrafts`). Each squad screen owns one (`@StateObject`) next to its keeper.
@MainActor
final class SquadWorkspace: ObservableObject {
    @Published private(set) var state = SquadDrafts()

    /// The screen is showing `account`'s squads over a box of `boxIds` (nil while the box is not loaded): another account's drafts are dropped (H1), and a draft pick whose copy left
    /// the box is emptied, as the store's are (H2; the screen then keeps the refill in the draft).
    func attach(account: String?, boxIds: Set<String>?) {
        update { d in
            d.switchAccount(account)
            if let boxIds { d = d.reconciled(boxIds: boxIds) }
        }
    }

    func update(_ change: (inout SquadDrafts) -> Void) {
        var s = state
        change(&s)
        if s != state { state = s }
    }

    /// The squad as the screen draws and edits it right now.
    func surface(_ ref: SquadRef, store: SquadStore, defaults: [SquadSlot]) -> SquadSurface {
        let current = store.current(ref)
        let tab = state.tab(ref.key, hasCurrent: current != nil, mode: store.mode(for: ref.screen))
        return SquadSurface(ref: ref, account: state.account, tab: tab, current: current, draft: tab == .current ? nil : state.draft(ref.key, tab), defaults: defaults, justSaved: tab != .current && state.justSaved(ref.key, tab, current: current))
    }

    /// The player chose a tab. Available and Best are remembered for the screen (the tab a squad with no Current opens on), as before.
    func select(_ tab: SquadTab, ref: SquadRef, keeper: SquadKeeper) {
        update { $0.select(tab, for: ref.key) }
        if tab != .current { keeper.update { $0.setMode(tab.mode, for: ref.screen) } }
    }

    /// A change to the squad on the tab it is on: Current is stored at once, a draft is held here. It never changes the tab.
    func edit(_ s: SquadSurface, keeper: SquadKeeper, _ change: (inout SquadStore.Saved) -> Void) {
        if s.tab == .current {
            keeper.update { store in
                var q = store.current(s.ref) ?? SquadStore.Saved(slots: s.defaults)
                change(&q)
                store.setCurrent(q, s.ref)
            }
        } else {
            update { d in
                var q = d.draft(s.key, s.tab) ?? SquadStore.Saved(slots: s.defaults)
                change(&q)
                d.setDraft(q, s.key, s.tab)
            }
        }
    }

    /// Save to Current (and, from "Set this squad", the mark): the squad as shown on Available or Best becomes the squad's Current. The player stays on the tab.
    func saveToCurrent(_ s: SquadSurface, keeper: SquadKeeper, filled: [FilledSlot], setMark: Bool) {
        // A draft is never written into another account's store: the surface was drawn for the account the keeper and the drafts are on now.
        guard s.account == keeper.account, s.account == state.account else { return }
        var shown = s.squad
        shown.fixing(filled)
        shown.isSet = false
        var current = shown
        current.isSet = setMark
        keeper.update { $0.setCurrent(current, s.ref) }
        update { $0.didSave(shown, s.key, s.tab) }
        // Said on every save, including "Set this squad" from an unedited tab (H11).
        AccessibilityNotification.Announcement("Saved to Current").post()
    }

    func reset(_ s: SquadSurface) { update { $0.reset(s.key, s.tab) } }

    /// Delete current squad: the squad shows Available (or the remembered tab) again; the drafts are left as they are.
    func deleteCurrent(_ s: SquadSurface, keeper: SquadKeeper) {
        keeper.update { $0.deleteCurrent(s.ref) }
        update { $0.clearTab(for: s.key); $0.clearSaved(s.key) }
    }
}

/// One squad on its tab: what is drawn (`squad`), where an edit goes, and what the controls under the slots show.
struct SquadSurface {
    let ref: SquadRef
    /// The account the surface was drawn for.
    let account: String?
    let tab: SquadTab
    /// The stored Current squad; nil when the player has kept nothing.
    let current: SquadStore.Saved?
    /// The edited Available or Best squad; nil while it is unedited.
    let draft: SquadStore.Saved?
    /// The suggestion's slots: the roles an unedited Available or Best squad is made of.
    let defaults: [SquadSlot]
    /// The draft was just saved to Current and the stored Current is still that squad.
    let justSaved: Bool
    /// The squad as drawn differs from the suggestion as drawn (rule 27.3, H6): set by `with(edited:)` once the screen has drawn both.
    private(set) var edited = false

    func with(edited: Bool) -> SquadSurface { var s = self; s.edited = edited; return s }

    /// Whether an Available or Best draft, drawn as `filled`, differs from the suggestion `suggested` draws. Nothing is worked out while there is no draft.
    func isEdited(filled: [FilledSlot], suggested: () -> [FilledSlot]) -> Bool {
        tab != .current && draft != nil && !HubSquads.sameSquad(filled, suggested())
    }

    /// Saving the squad drawn as `filled` would replace a Current that is a different squad (the set mark is not part of it): only then is the question asked (H12).
    func replaces(filled: [FilledSlot]) -> Bool {
        guard let current else { return false }
        var shown = squad
        shown.fixing(filled)
        return !shown.sameSquad(as: current)
    }

    var key: String { ref.key }
    var hasCurrent: Bool { current != nil }
    /// The squad to draw: the stored Current, the draft, or the unedited suggestion.
    var squad: SquadStore.Saved { tab == .current ? (current ?? SquadStore.Saved(slots: defaults)) : (draft ?? SquadStore.Saved(slots: defaults)) }
    var mode: SquadMode { tab.mode }
    /// Current is drawn as kept: no mode placement rule hides a kept pick.
    var kept: Bool { tab == .current }
    var differs: Bool { edited }
    /// The unedited Best tab, which is the squad strength's reference and reads 100%.
    var isBestSuggestion: Bool { tab == .best && !edited }
}
