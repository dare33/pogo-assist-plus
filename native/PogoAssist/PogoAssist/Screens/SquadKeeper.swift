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
    /// The box's names by entry id (`squadPickNames`), so a write remembers the names of the copies a squad holds while they are still in the box (`SquadStore.remember`).
    private var boxNames: [String: String] = [:]
    /// The box's entry ids at the last attach (nil while the box was not loaded): what a restored or undone squad is reconciled against (H8).
    private var boxIds: Set<String>?

    /// The defaults key of an account's squads. `AppModel.moveAccountKeys` moves it with a rename.
    nonisolated static let keyPrefix = "squads."

    nonisolated static func key(_ account: String) -> String { keyPrefix + account }

    /// Reads the account's store and applies the keeping rules (`SquadStore.refreshed`) for today's date, the rotation and the box's ids. `boxIds` is nil while the
    /// box is not loaded yet: the picks are then left alone. A loaded box with no copies is an empty set, and every pick is dropped (the last copy was deleted).
    func attach(account: String?, today: String, rotation: [HubData.RotationRow], boxIds: Set<String>?, names: [String: String]? = nil) {
        let changedAccount = account != self.account
        self.account = account
        guard let account else { store = SquadStore(); boxNames = [:]; self.boxIds = nil; return }
        self.boxIds = boxIds
        var s = changedAccount || store == SquadStore() ? Self.load(account) : store
        if let names, boxIds != nil { boxNames = names }
        // Names are remembered before the rules run: a copy that left the box is emptied from the squads, but a history row still names it.
        if boxIds != nil { s.remember(names: boxNames) }
        if let boxIds { s = s.refreshed(today: today, rotation: rotation, boxIds: boxIds) }
        if s != store { store = s }
        if boxIds != nil { Self.save(s, for: account) }
    }

    /// Changes the store and writes it. `reconciling` runs the rule attach applies after the change (a copy not in the box is emptied from the squads; species picks stay), for a change that
    /// brings back a squad kept in the history, which is never reconciled while it is there (H8).
    func update(reconciling: Bool = false, _ change: (inout SquadStore) -> Void) {
        var s = store
        change(&s)
        if reconciling, let boxIds { s = s.reconciled(boxIds: boxIds) }
        if !boxNames.isEmpty { s.remember(names: boxNames) }
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

extension SquadScreen {
    /// The `BoxAdvice.Build.areas` labels whose builds a screen's slots are made of (Rocket also takes Raids builds, as `HubSquads.isRocketArea` does).
    var buildAreas: [String] {
        switch self {
        case .raids: return ["Raids"]
        case .max: return ["Max"]
        case .gym: return ["Gym"]
        case .rocket: return ["Rocket", "Raids"]
        case .pvp: return ["GL", "UL", "ML"]
        }
    }
}

/// The name a squad screen gives a copy: the target of the first build of the screen's OWN area (as a slot card names it), else the box title; nil when the copy is not in the box.
func squadPickName(_ id: String, entries: [BoxEntry], builds: [BoxAdvice.Build], screen: SquadScreen) -> String? {
    guard let e = entries.first(where: { $0.id == id }) else { return nil }
    let areas = Set(screen.buildAreas)
    let name = builds.first { $0.entryId == id && !areas.isDisjoint(with: $0.areas) }?.targetName ?? e.row.title
    return SquadWords.boxName(name)
}

/// The name a squad screen gives each copy of the box, by entry id (`squadPickName`). A history row keeps naming a copy after it leaves.
func squadPickNames(entries: [BoxEntry], builds: [BoxAdvice.Build], screen: SquadScreen) -> [String: String] {
    var firstBuild = [String: String]()
    let areas = Set(screen.buildAreas)
    for b in builds where !areas.isDisjoint(with: b.areas) && firstBuild[b.entryId] == nil { firstBuild[b.entryId] = b.targetName }
    var out = [String: String]()
    for e in entries { out[e.id] = SquadWords.boxName(firstBuild[e.id] ?? e.row.title) }
    return out
}

/// Loads the keeper's squads when a squad screen appears and applies the keeping rules again when the account, the box or the advice changes (a re-scan saved, a
/// switch of account). The box is waited for: until it is loaded the box ids the rules need are not known.
struct SquadAttach: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissToast) private var dismissToast
    @ObservedObject var keeper: SquadKeeper
    /// The screen's tab choices, which follow the same account (nil on a screen with none).
    var workspace: SquadWorkspace? = nil
    /// The screen the keeper serves: the names it remembers are those a slot card of this screen shows.
    let screen: SquadScreen

    func body(content: Content) -> some View {
        content
            .onAppear(perform: attach)
            // The screen's toast (its Undo acts on this keeper) goes with the screen (H10).
            .onDisappear { dismissToast(ObjectIdentifier(keeper)) }
            .onChange(of: model.account) { _, _ in attach() }
            .onChange(of: model.snapshot?.seq) { _, _ in attach() }
            .onChange(of: model.boxLoaded) { _, _ in attach() }
            .onChange(of: model.hubAdvice != nil) { _, _ in attach() }
    }

    private func attach() {
        let loaded = model.boxLoaded && model.boxProblem == nil
        let boxIds: Set<String>? = loaded ? Set(model.entries.map(\.id)) : nil
        keeper.attach(account: model.account, today: HubModel.today(), rotation: (try? HubData.bundled())?.rotation ?? [], boxIds: boxIds,
                      names: loaded ? squadPickNames(entries: model.entries, builds: model.hubAdvice?.builds ?? [], screen: screen) : nil)
        workspace?.attach(account: model.account, boxIds: boxIds)
    }
}

extension View {
    /// Keeps `keeper` in step with the selected account's saved squads.
    func keepsSquads(_ keeper: SquadKeeper, _ workspace: SquadWorkspace? = nil, screen: SquadScreen) -> some View { modifier(SquadAttach(keeper: keeper, workspace: workspace, screen: screen)) }
}

// MARK: Available, Best and Current (pass 2-6, rule 27)

/// What one squad screen holds while the player is on it and drops when they leave: the tab each squad is on. The player's edits of Available and Best are kept in the store
/// (`SquadStore.edits`), per account, squad, tab and (on Raids) style. Each squad screen owns one (`@StateObject`) next to its keeper.
@MainActor
final class SquadWorkspace: ObservableObject {
    @Published private(set) var state = SquadTabChoices()
    /// The box the screen last attached to (nil while it is not loaded): what a refill may be adopted from.
    private var boxIds: Set<String>?

    /// The screen is showing `account`'s squads over a box of `boxIds` (nil while the box is not loaded): another account's tab choices are dropped (H1). The kept edits follow the box in
    /// the store (`SquadKeeper.attach`); the screen keeps a slot's refill in the edit (`adopt`).
    func attach(account: String?, boxIds: Set<String>?) {
        self.boxIds = boxIds
        update { $0.switchAccount(account) }
    }

    func update(_ change: (inout SquadTabChoices) -> Void) {
        var s = state
        change(&s)
        if s != state { state = s }
    }

    /// The squad as the screen draws and edits it right now.
    func surface(_ ref: SquadRef, store: SquadStore, defaults: [SquadSlot]) -> SquadSurface {
        let current = store.current(ref)
        let tab = state.tab(ref.key, hasCurrent: current != nil, mode: store.mode(for: ref.screen))
        let style = store.raidStyle
        return SquadSurface(ref: ref, account: state.account, tab: tab, current: current, edit: tab == .current ? nil : store.edit(ref, tab, style: style), style: style, defaults: defaults)
    }

    /// The player chose a tab. Available and Best are remembered for the screen (the tab a squad with no Current opens on), as before.
    func select(_ tab: SquadTab, ref: SquadRef, keeper: SquadKeeper) {
        update { $0.select(tab, for: ref.key) }
        if tab != .current { keeper.update { $0.setMode(tab.mode, for: ref.screen) } }
    }

    /// A change the player made to the squad on the tab it is on, stored at once: the Current, or the kept edit of Available or Best. It never changes the tab. On Current it marks the
    /// squad edited and clears its figure (the figure it was set with no longer describes it); the strength task writes the new one back (`record`).
    func edit(_ s: SquadSurface, keeper: SquadKeeper, _ change: (inout SquadStore.Saved) -> Void) { write(s, keeper: keeper, playerEdit: true, change) }

    private func write(_ s: SquadSurface, keeper: SquadKeeper, playerEdit: Bool, _ change: (inout SquadStore.Saved) -> Void) {
        // Like every write: only a surface drawn for the account the keeper and the tab choices are on now.
        guard s.account == keeper.account, s.account == state.account else { return }
        if s.tab == .current {
            keeper.update { store in
                var q = store.current(s.ref) ?? SquadStore.Saved(slots: s.defaults)
                change(&q)
                // A player's edit: edited since it was set, and the figure it was set with no longer describes it. An automatic refill (`adopt`) is neither.
                if playerEdit { q.edited = true; q.strength = nil }
                store.setCurrent(q, s.ref)
            }
        } else {
            keeper.update { store in
                var q = store.edit(s.ref, s.tab, style: s.style) ?? SquadStore.Saved(slots: s.defaults)
                change(&q)
                store.setEdit(q, s.ref, s.tab, style: s.style)
            }
        }
    }

    /// Keeps what a changed squad shows in a slot that refilled (rule 27.6). Run later from a task, so it reads the live account and box, not the ones the surface was drawn under:
    /// another account's surface writes nothing, and only a copy in the box now is adopted (a species pick is not a copy and is adopted as shown). An automatic refill is not the
    /// player's edit: it does not mark a Current edited or clear its figure.
    func adopt(_ s: SquadSurface, keeper: SquadKeeper, filled: [FilledSlot]) {
        guard s.account == keeper.account, s.account == state.account else { return }
        let inBox = filled.map { f -> FilledSlot in
            var f = f
            if let e = f.entryId, let ids = boxIds, !ids.contains(e) { f.entryId = nil }
            return f
        }
        write(s, keeper: keeper, playerEdit: false) { $0.adoptRefills(inBox) }
    }

    /// The strength task worked out the Current's figure: it is written back to the stored Current (edited stays as it is), so the figure is never lost for good and a history row
    /// records it. Nothing is written on another tab, for another account, or when the figure is already there.
    func record(_ s: SquadSurface, keeper: SquadKeeper, strength: Int?) {
        guard s.tab == .current, let strength, s.account == keeper.account, s.account == state.account,
              var q = keeper.store.current(s.ref), q.strength != strength else { return }
        q.strength = strength
        keeper.update { $0.setCurrent(q, s.ref) }
    }

    /// An edit of Available or Best that is drawn the same as the suggestion is not an edit (rule 27.2): the stored edit is dropped, so a later power-up or re-scan changes what
    /// the tab shows. Run from a task when `SquadSurface.editIsStale`.
    func dropUneditedEdit(_ s: SquadSurface, keeper: SquadKeeper) {
        guard s.tab != .current, s.account == keeper.account, s.account == state.account else { return }
        keeper.update { $0.resetEdit(s.ref, s.tab, style: s.style) }
    }

    /// "Reset to suggestion": the tab's kept edit is dropped at once.
    func reset(_ s: SquadSurface, keeper: SquadKeeper) {
        guard s.account == keeper.account, s.account == state.account else { return }
        keeper.update { $0.resetEdit(s.ref, s.tab, style: s.style) }
    }

    /// "Set this squad": the squad as shown on Available or Best becomes the squad's Current, with no question. The player stays on the tab. Returns whether a different Current was
    /// replaced (the screen then offers Undo); that Current is in the history.
    @discardableResult
    func setCurrent(_ s: SquadSurface, keeper: SquadKeeper, filled: [FilledSlot], strength: Int?, date: Date = Date()) -> Bool {
        // The squad is never written into another account's store: the surface was drawn for the account the keeper and the tab choices are on now.
        guard s.account == keeper.account, s.account == state.account else { return false }
        var shown = s.squad
        shown.fixing(filled)
        let old = keeper.store.current(s.ref)
        let replaced = old.map { $0.slots != shown.slots } ?? false
        keeper.update { $0.replaceCurrent(with: shown, s.ref, source: s.tab, edited: s.edited, strength: strength, date: date) }
        update { $0.select(s.tab, for: s.key) }
        return replaced
    }

    /// "✓ Squad set" tapped, or Delete current squad: the Current moves to the history, with the figure it holds, and the squad shows Available (or the remembered tab) again.
    func unsetCurrent(_ s: SquadSurface, keeper: SquadKeeper, date: Date = Date()) {
        guard s.account == keeper.account, s.account == state.account else { return }
        keeper.update { $0.unsetCurrent(s.ref, date: date) }
        if s.tab == .current { update { $0.clearTab(for: s.key) } }
    }

    /// "Set squad" on a history row. Returns whether a different Current was replaced. The squad comes back reconciled with the box: a copy that left it is emptied and its slot refills.
    @discardableResult
    func restore(_ s: SquadSurface, keeper: SquadKeeper, index: Int, date: Date = Date()) -> Bool {
        guard s.account == keeper.account, s.account == state.account else { return false }
        let old = keeper.store.current(s.ref), entry = keeper.store.history[s.ref.key]?[safe: index]
        let replaced = old != nil && entry != nil && old!.slots != entry!.slots
        keeper.update(reconciling: true) { _ = $0.restoreFromHistory(s.ref, index: index, date: date) }
        return replaced
    }

    /// Undo of the last Set this squad, Set squad or Delete (the toast's action): the Current and the history go back exactly as they were, reconciled with the box. false, and nothing
    /// changed, when there is nothing to undo.
    @discardableResult
    func undo(_ s: SquadSurface, keeper: SquadKeeper) -> Bool {
        guard s.account == keeper.account, s.account == state.account, keeper.store.canUndo(s.ref) else { return false }
        // The squad comes back on the Current tab or not at all; the tab choice stays what the player made.
        keeper.update(reconciling: true) { _ = $0.undoReplace(s.ref) }
        return true
    }

    /// The toast's action for the change just made: Undo, or nil when it left nothing to undo (a skipped duplicate push), so the toast then carries no Undo.
    func undoAction(_ s: SquadSurface, keeper: SquadKeeper) -> ToastAction? {
        guard keeper.store.canUndo(s.ref) else { return nil }
        return ToastAction(label: "Undo", perform: { [weak self, weak keeper] in
            guard let self, let keeper else { return }
            self.undo(s, keeper: keeper)
        }, owner: ObjectIdentifier(keeper))
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// One squad on its tab: what is drawn (`squad`), where an edit goes, and what the controls under the slots show.
struct SquadSurface {
    let ref: SquadRef
    /// The account the surface was drawn for.
    let account: String?
    let tab: SquadTab
    /// The stored Current squad; nil when the player has kept nothing.
    let current: SquadStore.Saved?
    /// The kept edit of the Available or Best squad; nil while it is unedited.
    let edit: SquadStore.Saved?
    /// The Raids style the edit is kept under (the other screens ignore it).
    let style: RaidStyle
    /// The suggestion's slots: the roles an unedited Available or Best squad is made of.
    let defaults: [SquadSlot]
    /// The squad as drawn differs from the suggestion as drawn (rule 27.3): set by `with(edited:)` once the screen has drawn both.
    private(set) var edited = false

    func with(edited: Bool) -> SquadSurface { var s = self; s.edited = edited; return s }

    /// Whether an Available or Best edit, drawn as `filled`, differs from the suggestion `suggested` draws. Nothing is worked out while there is no edit.
    func isEdited(filled: [FilledSlot], suggested: () -> [FilledSlot]) -> Bool {
        tab != .current && edit != nil && !HubSquads.sameSquad(filled, suggested())
    }

    /// An edit is stored but the squad is drawn as the suggestion (rule 27.2: that is not an edit): `SquadWorkspace.dropUneditedEdit` removes it. Needs `edited` set by `with(edited:)`.
    var editIsStale: Bool { tab != .current && edit != nil && !edited }

    /// The tab's squad as drawn is the Current as drawn (rule 27.3, the comparison `isEdited` makes): every slot holds the same Pokémon (copy or species) in the same role. The pill reads
    /// "✓ Squad set" exactly then. `currentFilled` draws the stored Current (as the Current tab does), worked out only when there is one.
    func isCurrent(filled: [FilledSlot], currentFilled: () -> [FilledSlot]) -> Bool {
        current != nil && HubSquads.sameSquad(filled, currentFilled())
    }

    var key: String { ref.key }
    var hasCurrent: Bool { current != nil }
    /// The squad to draw: the stored Current, the kept edit, or the unedited suggestion.
    var squad: SquadStore.Saved { tab == .current ? (current ?? SquadStore.Saved(slots: defaults)) : (edit ?? SquadStore.Saved(slots: defaults)) }
    var mode: SquadMode { tab.mode }
    /// Current, and an edit of Available or Best, are drawn as kept: no mode placement rule hides a kept pick (rule 27.4).
    var kept: Bool { tab == .current || edit != nil }
    var differs: Bool { edited }
    /// The unedited Best tab, which is the squad strength's reference and reads 100%.
    var isBestSuggestion: Bool { tab == .best && !edited }
}
