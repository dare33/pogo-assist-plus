import SwiftUI
import PogoBox

/// One species' Pokémon, best IVs first, with Select mode: pick some and the bottom bar builds one game search for them
/// (design handoff v2 section 1g and the prototype's species screen).
struct SpeciesListView: View {
    let route: SpeciesRoute
    @ObservedObject var store: BoxIndexStore
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.showToast) private var showToast
    @State private var selecting = false
    @State private var picked = Set<String>()
    @State private var deleting: DeleteTarget?

    private var index: BoxIndex { store.index }
    private var members: [Int] { index.members(of: route.title, query: route.query, chip: route.chip) }

    var body: some View {
        let ms = members
        let ids = ms.map { index.items[$0].id }
        VStack(spacing: 0) {
            header(count: ms.count, ids: ids)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                    Label("Best IVs first", systemImage: "arrow.down").labelStyle(.titleAndIcon)
                        .font(.figtree(14, .bold, relativeTo: .subheadline)).foregroundStyle(accent.ink)
                        .padding(.horizontal, 6)
                    rows(ms)
                }
                .padding(.horizontal, Theme.Space.screen)
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .animation(nil, value: selecting)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if selecting, !picked.isEmpty { selectBar(ms) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .confirmDelete($deleting)
        .onChange(of: ms.isEmpty) { _, empty in if empty { dismiss() } }
    }

    // MARK: header

    @ViewBuilder private func header(count: Int, ids: [String]) -> some View {
        HStack(spacing: 8) {
            if selecting {
                HeaderTextButton(title: "Cancel") { selecting = false; picked = [] }
                Text("\(picked.count) selected").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                HeaderTextButton(title: picked.count == count ? "None" : "All \(count.formatted())") { picked = picked.count == count ? [] : Set(ids) }
            } else {
                IconButton(systemImage: "chevron.left", kind: .floating, label: "Back") { dismiss() }
                Text("\(route.title) · \(count.formatted())").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                    .lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                HeaderTextButton(title: "Select") { selecting = true }
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .frame(minHeight: 52)
    }

    // MARK: rows

    private func rows(_ ms: [Int]) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(Array(ms.enumerated()), id: \.element) { n, i in
                let it = index.items[i]
                Group {
                    if selecting {
                        Button { toggle(it.id) } label: { row(it, last: n == ms.count - 1) }.buttonStyle(PressStyle())
                            .accessibilityAddTraits(picked.contains(it.id) ? .isSelected : [])
                    } else {
                        NavigationLink(value: it.id) { row(it, last: n == ms.count - 1) }.buttonStyle(PressStyle())
                            .contextMenu { Button(role: .destructive) { deleting = DeleteTarget(id: it.id, title: it.title, cp: it.cp) } label: { Label("Delete from box", systemImage: "trash") } }
                    }
                }
                .accessibilityIdentifier("pokemon-row")
            }
        }
        .background(Theme.surface, in: shape)
        .clipShape(shape)
        .panelShadow()
    }

    private func toggle(_ id: String) { if picked.contains(id) { picked.remove(id) } else { picked.insert(id) } }

    private func row(_ it: BoxIndex.Item, last: Bool) -> some View {
        let on = selecting && picked.contains(it.id)
        let ivs = it.ivs.map { "\($0) · \(it.pct ?? 0)%" } ?? "IVs not read"
        return HStack(spacing: 12) {
            if selecting {
                Image(systemName: "checkmark").font(.figtree(13, .bold)).foregroundStyle(on ? accent.onSolid : .clear)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(on ? accent.solid : .clear))
                    .overlay(Circle().strokeBorder(on ? .clear : Theme.line, lineWidth: 2))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(it.title).paText(.rowTitle).foregroundStyle(Theme.ink)
                Text("\(ivs)\(Text(it.needsCheck ? " · To check" : "").fontWeight(.bold).foregroundStyle(Theme.orangeInk))\(it.fixed ? " · Fixed by hand" : "")")
                    .font(.figtree(13, .regular, relativeTo: .footnote)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CPFigure(cp: it.cp)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(on ? accent.tint : .clear)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, selecting ? 54 : 16) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(it.title), \(it.cp > 0 ? "CP \(it.cp)" : "CP not known"), \(ivs)\(it.needsCheck ? ", to check" : "")\(it.fixed ? ", fixed by hand" : "")")
    }

    // MARK: select bar

    private func selectBar(_ ms: [Int]) -> some View {
        let order = ms.filter { picked.contains(index.items[$0].id) }
        let search = index.gameSearch(picked: order)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.figtree(16, .bold)).foregroundStyle(Theme.orangeInk).accessibilityHidden(true)
                Text(search.text).font(.figtree(14, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.orangeInk)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
            .background(Theme.orangeTint, in: RoundedRectangle(cornerRadius: Theme.Radius.insetRow, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Search to paste into the game")
            .accessibilityValue(search.text)
            if search.extra > 0 {
                Text("In the game this search will also show \(search.extra.formatted()) more: \(search.extra == 1 ? "a Pokémon" : "Pokémon") with the same name and one of these CPs that you did not pick.")
                    .font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.orangeInk)
            }
            if search.withoutCP > 0 {
                Text("\(search.withoutCP.formatted()) of the picked \(search.withoutCP == 1 ? "has" : "have") no CP known, so this search cannot find \(search.withoutCP == 1 ? "it" : "them").")
                    .font(.figtree(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.orangeInk)
            }
            HStack(spacing: 8) {
                PillButton("Copy search (\(order.count.formatted()))", systemImage: "doc.on.doc", style: .filled, height: 52) {
                    UIPasteboard.general.string = search.text
                    showToast("Copied")
                }
                PillButton("Export", systemImage: "square.and.arrow.up", style: .tint, height: 52, fullWidth: false) {
                    let ids = Set(order.map { index.items[$0].id })
                    Task { await model.exportCSV(only: ids) }
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255).opacity(0.14), radius: 12, x: 0, y: -4)
        .padding(.horizontal, 8).padding(.bottom, 8)
    }
}
