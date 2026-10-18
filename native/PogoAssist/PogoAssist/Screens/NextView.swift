import SwiftUI
import PogoBox

/// What to do next, from the advisor: builds best first, then the gaps and the duplicates, as `scripts/advise.mjs` prints them.
struct NextView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAllBuilds = false

    private static let buildLimit = 40

    var body: some View {
        Group {
            switch model.advice {
            case .none: placeholder("Nothing to advise on yet", "Scan your Pokémon and the advisor will list what to power up, evolve or transfer.")
            case .computing: VStack(spacing: 12) { ProgressView().controlSize(.large); Text("Working out advice").font(.headline) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let m): placeholder("Advice could not be worked out", m)
            case .ready(let advice): list(advice)
            }
        }
        .navigationTitle("Next")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { AccountMenu() }
            ToolbarItem(placement: .topBarTrailing) { MoreMenu() }
        }
        .navigationDestination(for: String.self) { PokemonDetailView(id: $0) }
    }

    private func placeholder(_ title: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "list.number").font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ a: BoxAdvice) -> some View {
        let shown = showAllBuilds ? a.builds : Array(a.builds.prefix(Self.buildLimit))
        let sGaps = a.gaps.filter { $0.tier == "S" }, aGaps = a.gaps.filter { $0.tier == "A" }.count
        return List {
            Section("Builds, best first (\(a.builds.count))") {
                if a.builds.isEmpty { Text("The advisor found nothing worth building in this box.").foregroundStyle(.secondary) }
                ForEach(shown) { b in NavigationLink(value: b.entryId) { BuildRow(build: b) } }
                if a.builds.count > Self.buildLimit {
                    Button(showAllBuilds ? "Show fewer" : "Show all \(a.builds.count)") { showAllBuilds.toggle() }
                }
            }
            Section {
                ForEach(sGaps) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name).font(.callout.weight(.medium))
                        Text("\(g.area)\(g.section.map { ", \($0)" } ?? "")" + (g.obtain.map { ": \($0)" } ?? "")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if aGaps > 0 { Text("Plus \(aGaps) A-tier gaps.").font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Gaps (\(sGaps.count) S tier)") } footer: { Text("Top-tier Pokémon that nothing in the box can become.") }
            Section("Duplicates (\(a.duplicates.count) species)") {
                ForEach(a.duplicates.prefix(15)) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(d.name), \(d.count) copies").font(.callout.weight(.medium))
                        Text("Keep: \(d.keep.joined(separator: "; "))").font(.footnote).foregroundStyle(.secondary)
                        Text("Transfer \(d.transfer.count)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if a.duplicates.count > 15 { Text("Plus \(a.duplicates.count - 15) more species.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}
