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
    private var account: String?

    /// The defaults key of an account's squads. `AppModel.moveAccountKeys` moves it with a rename.
    nonisolated static let keyPrefix = "squads."

    nonisolated static func key(_ account: String) -> String { keyPrefix + account }

    /// Reads the account's store and applies the two rules for `ctx` (today's date, the rotation and the box's ids). A box that is not loaded (no entries) leaves
    /// the picks alone: an empty id set would read as "every copy left" and wipe them.
    func attach(account: String?, ctx: HubContext?) {
        let changedAccount = account != self.account
        self.account = account
        guard let account else { store = SquadStore(); return }
        var s = changedAccount || store == SquadStore() ? Self.load(account) : store
        if let ctx, !ctx.entries.isEmpty {
            s = s.refreshed(today: ctx.today, rotation: ctx.hub.rotation, boxIds: Set(ctx.entries.map(\.id)))
        }
        if s != store { store = s }
        if let ctx, !ctx.entries.isEmpty { Self.save(s, for: account) }
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
/// switch of account). The advice is waited for: until then the box ids the rules need are not known.
struct SquadAttach: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var keeper: SquadKeeper

    func body(content: Content) -> some View {
        content
            .onAppear(perform: attach)
            .onChange(of: model.account) { _, _ in attach() }
            .onChange(of: model.snapshot?.seq) { _, _ in attach() }
            .onChange(of: model.hubAdvice != nil) { _, _ in attach() }
    }

    private func attach() { keeper.attach(account: model.account, ctx: model.squadContext()) }
}

extension View {
    /// Keeps `keeper` in step with the selected account's saved squads.
    func keepsSquads(_ keeper: SquadKeeper) -> some View { modifier(SquadAttach(keeper: keeper)) }
}
