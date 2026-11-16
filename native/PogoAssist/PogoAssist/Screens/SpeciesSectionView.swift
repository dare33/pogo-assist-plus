import SwiftUI
import PogoBox
import PogoReader

/// One section of My Pokémon's list (a letter or a CP band): its heading and the species rows, each opening in place to `OpenSpeciesView`. Shared by the My Pokémon
/// tab and the Collection's Special sets list, so the two read the same.
struct SpeciesSectionView: View {
    let section: BoxIndex.Section
    let index: BoxIndex
    /// The search that built the section: a row's figures and its opened copies count only the Pokémon that pass it.
    let query: BoxIndex.Query
    let chip: BoxIndex.Chip
    let advice: BoxAdvice?
    let adviceState: InsightKey.State
    let pogoAssist: Bool
    /// The advice's builds by the copy they are for, so a row's build mark does not walk the report.
    let buildsByEntry: [String: [BoxAdvice.Build]]
    /// The species opened in place (one at a time; another tap on its row closes it).
    @Binding var openTitle: String?
    /// Called when a row is tapped, before it opens or closes (My Pokémon ends the typing).
    var onOpen: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The game master, read once: the type icons of every row come from it.
    private static let gameMaster = try? GameMaster.bundled()

    var body: some View {
        let s = section
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(s.heading).font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            .padding(.horizontal, 6)
            VStack(spacing: 0) {
                ForEach(Array(s.rows.enumerated()), id: \.element.id) { i, r in
                    let open = openTitle == r.title
                    Button {
                        onOpen()
                        if reduceMotion { openTitle = open ? nil : r.title } else { withAnimation(.easeOut(duration: 0.18)) { openTitle = open ? nil : r.title } }
                    } label: { speciesRow(r, last: i == s.rows.count - 1, open: open) }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("species-row")
                    if open {
                        OpenSpeciesView(route: SpeciesRoute(title: r.title, query: query, chip: chip), copies: index.members(of: r.title, query: query, chip: chip).map { index.items[$0] },
                                        advice: advice, adviceState: adviceState, pogoAssist: pogoAssist, buildsByEntry: buildsByEntry)
                            .transition(.opacity)
                    }
                }
            }
            .background(Theme.surface, in: shape)
            .clipShape(shape)
            .panelShadow()
        }
        .id(s.id)
    }

    private func speciesRow(_ r: BoxIndex.Row, last: Bool, open: Bool) -> some View {
        let activity: BoxInsight.Activity? = { if case .activity(let a) = chip { return a } else { return nil } }()
        let check = r.stats.toCheck > 0 ? "\(r.stats.toCheck) to check" : nil
        let types = (Self.gameMaster?.byId[r.speciesId]?.types ?? [])
        let mark = MyPokemon.speciesMark(builds: r.members.flatMap { buildsByEntry[index.items[$0].id] ?? [] })
        // The count and the lead tag come first, so a label still starts "Moltres, 6 Pokémon" (the UI tests and the list's readers rely on it).
        var label = "\(r.title), \(r.stats.count) Pokémon"
        if let activity, let lead = r.lead { label += ", \(lead.label) for \(activity.title)" }
        if !types.isEmpty { label += ", " + types.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " and ") }
        if let best = r.stats.bestPct {
            label += ", best \(best) percent"
        } else { label += ", IVs not read" }
        if let top = r.stats.topCP { label += ", top CP \(top)" }
        if let words = BuildMarkWords.species(mark) { label += ", " + words }
        if let check { label += ". " + check }
        label += open ? ". Open" : ". Opens in place"
        let bestSum = r.members.compactMap { index.items[$0].ivSum }.max()
        let trailing = HStack(spacing: 10) {
            BuildMarkView(mark: mark, upgradeLabel: BuildMarkWords.species(mark) ?? "Upgrade available")
            Text(r.stats.count.formatted()).font(.figtree(13, .heavy, relativeTo: .footnote)).monospacedDigit().foregroundStyle(Theme.ink)
                .padding(.horizontal, 6).frame(minWidth: 34, minHeight: 26)
                .background(Theme.surface2, in: Capsule())
            Image(systemName: "chevron.right").font(.figtree(13, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
                .rotationEffect(.degrees(open ? 90 : 0))
        }
        let main = VStack(alignment: .leading, spacing: 1) {
            FlowLayout(spacing: 6) {
                Text(r.title).font(.figtree(16, .bold, relativeTo: .body)).foregroundStyle(Theme.ink)
                if !types.isEmpty { TypeIcons(types: types, size: 18) }
                // With a chip chosen, the species' best copy's tag for it: the list reads as a ranking.
                if let activity, let lead = r.lead { WorthTag(activity: activity, worth: lead) }
            }
            FlowLayout(spacing: 4) {
                if let best = r.stats.bestPct {
                    Text("best")
                    GradedNumber("\(best)%", MyPokemon.ivGrade(sum: bestSum), size: 13, plain: .regular)
                } else { Text("IVs not read") }
                if let top = r.stats.topCP { Text("· top \(top)") }
            }
            .font(.figtree(13, .regular, relativeTo: .footnote)).foregroundStyle(Theme.muted).monospacedDigit()
            if let check { Text(check).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.orangeInk) }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { main.frame(maxWidth: .infinity, alignment: .leading); trailing }
            VStack(alignment: .leading, spacing: 8) { main.frame(maxWidth: .infinity, alignment: .leading); trailing.frame(maxWidth: .infinity, alignment: .trailing) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last && !open { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 16) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(open ? .isSelected : [])
    }
}
