import SwiftUI
import PogoBox

/// What a Special sets card opens: a sheet with the player's Pokémon in that set, laid out as My Pokémon is (species rows by letter, each opening in place, a copy opens
/// its Pokémon page). The set's members are `HubCollection.Membership`'s, the definition the card's count reads, asked of the index as the matching search word.
/// A copy set lists only its copies; Legendary, Mythical and Ultra Beasts list each owned species with all its copies, and Mega-capable only the copies that can Mega Evolve.
struct CollectionSetSheet: View {
    let kind: HubCollection.SetKind
    /// The card the sheet opened from: its count until the sheet has worked out its own (an edit on a copy page opened from here changes the set).
    let set: HubCollection.SpecialSet
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = BoxIndexStore()
    @State private var sections: [BoxIndex.Section] = []
    @State private var sectionsFor: String?
    /// The set's count for the box version the sections were built for.
    @State private var current: HubCollection.SpecialSet?
    @State private var openTitle: String?
    @State private var buildsByEntry: [String: [BoxAdvice.Build]] = [:]
    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue

    private var indexKey: String { "\(model.account ?? "")|\(model.snapshot?.seq ?? -1)" }
    private var pogoAssist: Bool { rankingRaw == Ranking.pogoAssist.rawValue }
    private var readyAdvice: BoxAdvice? { if case .ready(let a) = model.advice { return a } else { return nil } }
    private var insightKey: InsightKey { InsightKey(account: model.account, seq: model.snapshot?.seq, state: InsightKey.State(model.advice)) }
    /// A set that is coming soon has no search word and is never opened (its strip has no "All"); the empty text is a placeholder.
    private var query: BoxIndex.Query { BoxIndex.SearchWord(kind).map { .keyword($0) } ?? .text("") }

    /// The sections show only with the index they were built for: a row holds positions in that index, so with another one they would be the wrong rows (or none).
    /// They also wait for the box version the model is on: while a newer one is being indexed, the old rows are not shown.
    static func showsSections(computedFor: String?, storeKey: String?, modelKey: String) -> Bool { computedFor != nil && computedFor == storeKey && storeKey == modelKey }
    private var ready: Bool { Self.showsSections(computedFor: sectionsFor, storeKey: store.indexKey, modelKey: indexKey) }
    private var shown: HubCollection.SpecialSet { current ?? set }

    /// "14 of 52 species", "6 copies"; the card's note while a set has nothing yet.
    private var figure: String {
        if let note = shown.note { return note }
        let n = shown.owned ?? 0
        if let total = shown.total { return "\(n.formatted()) of \(total.formatted()) \(shown.unitWord)" }
        return "\(n.formatted()) \(shown.unitWord)"
    }

    /// A species set lists a species' forms as rows of their own (Giratina Altered and Origin), so it can have more rows than the count has species.
    private var formsListedSeparately: Bool { kind.isSpeciesSet && sections.reduce(0) { $0 + $1.rows.count } > (shown.owned ?? 0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shown.name).font(.figtree(22, .heavy, relativeTo: .title2)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                        Text(figure).font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted).monospacedDigit()
                            .accessibilityIdentifier("collection-set-sheet-count")
                    }
                    .padding(.horizontal, 6)
                    if !ready {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else if sections.isEmpty {
                        // A set with a note (Lucky before any mark) says it once, under the title.
                        if shown.note == nil {
                            Text("No Pokémon in this set yet.").paText(.secondary).foregroundStyle(Theme.muted).padding(.horizontal, 6).padding(.vertical, 20)
                                .accessibilityIdentifier("collection-set-sheet-empty")
                        }
                    } else if formsListedSeparately {
                        Text("Forms are listed separately.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).padding(.horizontal, 6)
                            .accessibilityIdentifier("collection-set-sheet-forms")
                    }
                    ForEach(ready ? sections : []) { s in
                        SpeciesSectionView(section: s, index: store.index, query: query, chip: .all, advice: readyAdvice, adviceState: insightKey.state, pogoAssist: pogoAssist,
                                           buildsByEntry: buildsByEntry, openTitle: $openTitle)
                    }
                }
                .padding(.horizontal, Theme.Space.listGutter)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("collection-set-sheet-done") }
            }
            .navigationDestination(for: String.self) { PokemonDetailView(id: $0) }
            .navigationDestination(for: CopyRoute.self) { PokemonDetailView(id: $0.id, initialLeague: $0.league) }
            .navigationDestination(for: SpeciesRoute.self) { SpeciesListView(route: $0, store: store) }
        }
        // The app's alert shows over this sheet, so the player is still in the set when it is dismissed (the root view's alert waits while a sheet hosts it).
        .alert("Pogo Assist+", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .onAppear { model.alertHosts += 1 }
        .onDisappear { model.alertHosts -= 1 }
        .accessibilityIdentifier("collection-set-sheet")
        .task(id: indexKey) { await store.refresh(key: indexKey, entries: model.entries) }
        .task(id: insightKey) { await store.refreshInsight(key: insightKey, advice: readyAdvice, entries: model.entries) }
        .task(id: insightKey) { buildsByEntry = readyAdvice.map { Dictionary(grouping: $0.builds, by: \.entryId) } ?? [:] }
        .task(id: store.version) { await recompute() }
    }

    /// The sections for the box version the index was built for; they show once they are for the current one.
    private func recompute() async {
        guard let built = store.indexKey else { return }
        let idx = store.index, q = query
        let entries = model.entries, name = kind.name
        func work() -> ([BoxIndex.Section], HubCollection.SpecialSet?) {
            let count = (try? GameMaster.bundled()).flatMap { gm in HubCollection.specialSets(entries: entries, gm: gm).first { $0.name == name } }
            return (idx.sections(query: q, chip: .all, sort: .name), count)
        }
        let result: ([BoxIndex.Section], HubCollection.SpecialSet?)
        if idx.count < 2000 { result = work() }
        else { result = await Task.detached(priority: .userInitiated) { work() }.value }
        if Task.isCancelled || built != store.indexKey { return }
        sections = result.0; current = result.1; sectionsFor = built
    }
}
