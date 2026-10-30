import SwiftUI
import PogoBox

/// What a Special sets card opens: a sheet with the player's Pokémon in that set, laid out as My Pokémon is (species rows by letter, each opening in place, a copy opens
/// its Pokémon page). The set's members are `HubCollection.Membership`'s, the definition the card's count reads, asked of the index as the matching search word.
/// A copy set lists only its copies; a species set lists the owned species with all their copies.
struct CollectionSetSheet: View {
    let kind: HubCollection.SetKind
    /// The card the sheet opened from: the count it showed.
    let set: HubCollection.SpecialSet
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = BoxIndexStore()
    @State private var sections: [BoxIndex.Section] = []
    @State private var sectionsFor: String?
    @State private var openTitle: String?
    @State private var buildsByEntry: [String: [BoxAdvice.Build]] = [:]
    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue

    private var indexKey: String { "\(model.account ?? "")|\(model.snapshot?.seq ?? -1)" }
    private var pogoAssist: Bool { rankingRaw == Ranking.pogoAssist.rawValue }
    private var readyAdvice: BoxAdvice? { if case .ready(let a) = model.advice { return a } else { return nil } }
    private var insightKey: InsightKey { InsightKey(account: model.account, seq: model.snapshot?.seq, state: InsightKey.State(model.advice)) }
    private var query: BoxIndex.Query { .keyword(BoxIndex.SearchWord(kind)) }

    /// "14 of 52 species", "6 copies"; the card's note while a set has nothing yet.
    private var figure: String {
        if let note = set.note { return note }
        let n = set.owned ?? 0
        if let total = set.total { return "\(n.formatted()) of \(total.formatted()) \(set.unit)" }
        return "\(n.formatted()) \(n == 1 ? "copy" : "copies")"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(set.name).font(.figtree(22, .heavy, relativeTo: .title2)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                        Text(figure).font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted).monospacedDigit()
                            .accessibilityIdentifier("collection-set-sheet-count")
                    }
                    .padding(.horizontal, 6)
                    if sectionsFor == indexKey && sections.isEmpty {
                        Text(set.note ?? "No Pokémon in this set yet.").paText(.secondary).foregroundStyle(Theme.muted).padding(.horizontal, 6).padding(.vertical, 20)
                            .accessibilityIdentifier("collection-set-sheet-empty")
                    } else if sectionsFor != indexKey {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    ForEach(sections) { s in
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
        let result: [BoxIndex.Section]
        if idx.count < 2000 { result = idx.sections(query: q, chip: .all, sort: .name) }
        else { result = await Task.detached(priority: .userInitiated) { idx.sections(query: q, chip: .all, sort: .name) }.value }
        if Task.isCancelled || built != store.indexKey { return }
        sections = result; sectionsFor = built
    }
}
