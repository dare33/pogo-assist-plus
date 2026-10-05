import SwiftUI
import PogoBox
import PogoReader

/// Where a species row goes: the species list, with the search and chip that were on when it was tapped (the row's
/// figures count only the Pokémon that pass them, so the list must show the same ones).
struct SpeciesRoute: Hashable {
    var title: String
    var query: BoxIndex.Query
    var chip: BoxIndex.Chip
}

/// The Box tab: the box grouped by species, A to Z, with search and filter chips (design handoff v2 section 1g and the prototype's Box).
struct BoxView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.showToast) private var showToast
    @Environment(\.accent) private var accent
    @StateObject private var store = BoxIndexStore()

    @State private var query = ""
    @State private var applied = BoxIndex.Query.none
    @State private var chip = BoxIndex.Chip.all
    @State private var sort = BoxIndex.Sort.name
    @State private var sections: [BoxIndex.Section] = []
    @State private var sectionsReady = false
    @State private var jumped: String?
    @FocusState private var searching: Bool
    #if DEBUG
    @State private var benchText: String?
    private var synthetic: Bool { CommandLine.arguments.contains("-box-synthetic") }
    #else
    private var synthetic: Bool { false }
    #endif

    private var indexKey: String { "\(model.account ?? "")|\(model.snapshot?.seq ?? -1)" }
    private var index: BoxIndex { store.index }

    private struct SectionKey: Equatable { var query: String; var chip: BoxIndex.Chip; var sort: BoxIndex.Sort; var version: Int }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if let problem = model.boxProblem { problemState(problem) }
                else if model.entries.isEmpty && !synthetic { emptyState }
                else { list }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // The floating bar would ride up on the keyboard and cover the results while typing.
        .hidesTabBar(searching)
        // Leaving for a species list or a Pokémon ends the typing, so coming back does not bring the keyboard up over the list (iOS 27 gives the field its focus back).
        .onDisappear { searching = false }
        .navigationDestination(for: String.self) { PokemonDetailView(id: $0) }
        .navigationDestination(for: SpeciesRoute.self) { SpeciesListView(route: $0, store: store) }
        .sheet(isPresented: Binding(get: { model.exportURL != nil }, set: { if !$0 { model.exportURL = nil } })) {
            if let url = model.exportURL { ShareSheet(url: url).presentationDetents([.medium, .large]) }
        }
        .task(id: indexKey) {
            if synthetic { return }
            await store.refresh(key: indexKey, entries: model.entries)
        }
        #if DEBUG
        .task {
            if synthetic {
                let (built, line) = BoxIndex.bench()
                store.install(built, key: "synthetic")
                benchText = line
            }
        }
        #endif
        .task(id: SectionKey(query: query, chip: chip, sort: sort, version: store.version)) { await recompute() }
        .onChange(of: store.version) { _, _ in
            // A chip whose Pokémon are all gone (the last check cleared, say) would show an empty list with no way to know why.
            if (chip == .toCheck && index.toCheckCount == 0) || (chip == .fixed && index.fixedCount == 0) { chip = .all }
        }
        #if DEBUG
        .overlay(alignment: .bottom) {
            if let benchText { Text(benchText).font(.system(size: 8)).padding(4).background(.thinMaterial).accessibilityIdentifier("bench-result").accessibilityLabel(benchText).allowsHitTesting(false) }
        }
        #endif
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 4) {
            AccountPill()
            Spacer(minLength: 8)
            if !model.entries.isEmpty {
                IconButton(systemImage: "square.and.arrow.up", kind: .floating, label: "Export CSV") { Task { await model.exportCSV() } }
            }
            MoreButton()
        }
        .padding(.horizontal, Theme.Space.screen)
        .frame(minHeight: 52)
    }

    // MARK: states

    /// The newest box version cannot be read: not an empty box, and nothing is saved until a readable version is restored.
    private func problemState(_ text: String) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle").font(.figtree(44, .regular, relativeTo: .largeTitle)).foregroundStyle(Theme.orange).accessibilityHidden(true)
                Text(model.boxNeedsNewerApp ? "This box needs a newer version of the app" : "This box could not be read").paText(.questionTitle).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                Text(text).paText(.secondary).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                if !model.boxNeedsNewerApp {
                    PillButton("Restore the latest readable version", style: .filled) { Task { await model.restoreLatestReadable() } }
                }
                Text("Scanning is paused until this is resolved.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2").font(.figtree(44, .regular, relativeTo: .largeTitle)).foregroundStyle(Theme.faint).accessibilityHidden(true)
                Text("No Pokémon in this box yet").paText(.questionTitle).foregroundStyle(Theme.ink)
                Text("Scan your Pokémon GO storage and they will appear here, with their IVs and what to do with each.")
                    .paText(.secondary).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: the box

    private var showsIndex: Bool { sections.count >= 3 && query.isEmpty }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                    if let s = savedSummary { savedPanel(s) }
                    countLine
                    searchField
                    chips
                    if chip == .toCheck { rescanButton }
                    sortLine
                    if sectionsReady && sections.isEmpty { Text("No Pokémon match.").paText(.secondary).foregroundStyle(Theme.muted).padding(.horizontal, 6).padding(.vertical, 20) }
                    ForEach(sections) { sectionView($0) }
                }
                .padding(.leading, Theme.Space.screen)
                .padding(.trailing, Theme.Space.screen + (showsIndex ? 18 : 0))
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .trailing) { if showsIndex { jumpIndex(proxy) } }
        }
    }

    private var countLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(index.count.formatted()).paText(.screenTitle).foregroundStyle(Theme.ink)
                Text("Pokémon · \(index.speciesCount.formatted()) species").font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
            if let d = model.snapshot?.scanDate { Text("Last scan \(Fmt.date(d))").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.figtree(16, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
            TextField("", text: $query, prompt: Text("Name, CP, or cp1500-2500").foregroundStyle(Theme.faint))
                .font(.figtree(16, .regular, relativeTo: .body))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searching)
                .accessibilityLabel("Search")
                .accessibilityIdentifier("box-search")
            if !query.isEmpty {
                if let n = matchCount { Text("\(n.formatted()) of \(index.count.formatted())").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted) }
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.figtree(17, .regular)).foregroundStyle(Theme.faint).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 16).padding(.trailing, query.isEmpty ? 16 : 0)
        .frame(minHeight: 46)
        .background(Capsule().fill(Theme.surface))
        .panelShadow()
    }

    /// How many Pokémon pass the search and chip, once the debounced search has run.
    private var matchCount: Int? {
        guard sectionsReady, applied == BoxIndex.Query(query) else { return nil }
        return sections.reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.stats.count } }
    }

    // MARK: chips and sort

    /// A chip only when the box has something for it: To check from the entries' checks, Fixed by hand from the hand corrections. There is no "Not seen" chip: the
    /// saved box does not record which entries a Full scan saw but could not read ("On screen but not read", "Stationed"), so an old last-seen date cannot say "not seen".
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip("All", .all)
                if index.toCheckCount > 0 { filterChip("To check \(index.toCheckCount.formatted())", .toCheck) }
                if index.fixedCount > 0 { filterChip("Fixed by hand", .fixed) }
            }
            .padding(.horizontal, 1).padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    /// The to-check flow in the Box: one game search for every Pokémon to check (Greg, 6 Oct 2026), beside "Re-scan N", the Scan screen with Add and update chosen
    /// (`AppModel.startRescan`). The search leaves out entries with no CP or HP to look for, as the Review's does.
    @ViewBuilder private var rescanButton: some View {
        if !model.live {
            HStack(spacing: 10) {
                if let search = toCheckSearch {
                    PillButton("Copy search", systemImage: "doc.on.doc", style: .tint) { UIPasteboard.general.string = search; showToast("Copied") }
                        .accessibilityIdentifier("copy-check-search").accessibilityValue(search)
                }
                PillButton("Re-scan \(index.toCheckCount.formatted())", systemImage: "arrow.clockwise", style: .tint) { model.startRescan(count: index.toCheckCount) }
                    .accessibilityIdentifier("rescan-button")
            }
        }
    }

    private var toCheckSearch: String? {
        GameSearch.text(index.items.filter(\.needsCheck).map { GameSearch.part(name: $0.name, cp: $0.cp, hp: $0.hp, noLevelFits: $0.noLevelFits) })
    }

    private func filterChip(_ title: String, _ value: BoxIndex.Chip) -> some View {
        let on = chip == value
        let orange = value == .toCheck
        return Button { chip = value; searching = false } label: {
            Text(title).font(.figtree(14, orange || on ? .bold : .semibold, relativeTo: .subheadline))
                .foregroundStyle(on ? Theme.bg : (orange ? Theme.orangeInk : Theme.ink))
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().fill(on ? Theme.ink : (orange ? Theme.orangeTint : Theme.surface)))
                .modifier(ChipShadow(on: !on && !orange))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var sortLine: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                Text("Name").tag(BoxIndex.Sort.name)
                Text("Top CP").tag(BoxIndex.Sort.topCP)
            }
        } label: {
            HStack(spacing: 8) {
                Label(sort == .name ? "Name" : "Top CP", systemImage: "arrow.up.arrow.down")
                Text("·").foregroundStyle(Theme.faint)
                Label("By species", systemImage: "square.stack")
            }
            .font(.figtree(14, .bold, relativeTo: .subheadline)).labelStyle(.titleAndIcon)
            .foregroundStyle(accent.ink)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 4)
        .accessibilityLabel("Sort, \(sort == .name ? "Name" : "Top CP"), by species")
    }

    // MARK: sections

    private func sectionView(_ s: BoxIndex.Section) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(s.heading).font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            .padding(.horizontal, 6)
            VStack(spacing: 0) {
                ForEach(Array(s.rows.enumerated()), id: \.element.id) { i, r in
                    NavigationLink(value: SpeciesRoute(title: r.title, query: applied, chip: chip)) { speciesRow(r, last: i == s.rows.count - 1) }
                        .buttonStyle(PressStyle())
                        .simultaneousGesture(TapGesture().onEnded { searching = false })   // opening a species ends the typing
                        .accessibilityIdentifier("species-row")
                }
            }
            .background(Theme.surface, in: shape)
            .clipShape(shape)
            .panelShadow()
        }
        .id(s.id)
    }

    private func speciesRow(_ r: BoxIndex.Row, last: Bool) -> some View {
        var parts = [r.stats.bestPct.map { "best \($0)%" } ?? "IVs not read"]
        if let cp = r.stats.topCP { parts.append("top \(cp)") }
        let sub = parts.joined(separator: " · ")
        let check = r.stats.toCheck > 0 ? " · \(r.stats.toCheck) to check" : ""
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title).paText(.rowTitle).foregroundStyle(Theme.ink)
                Text("\(sub)\(Text(check).fontWeight(.bold).foregroundStyle(Theme.orangeInk))")
                    .font(.figtree(13, .regular, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(r.stats.count.formatted()).font(.figtree(13, .heavy, relativeTo: .footnote)).monospacedDigit().foregroundStyle(Theme.ink)
                .padding(.horizontal, 6).frame(minWidth: 34, minHeight: 26)
                .background(Theme.surface2, in: Capsule())
            Image(systemName: "chevron.right").font(.figtree(13, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 16) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.title), \(r.stats.count) Pokémon, \(sub)\(check)")
    }

    // MARK: A-Z index

    private func jumpIndex(_ proxy: ScrollViewProxy) -> some View {
        let labels: [String] = sort == .name ? ((65...90).map { String(UnicodeScalar($0)!) } + (sections.contains { $0.id == "#" } ? ["#"] : [])) : sections.map(\.short)
        let present = Dictionary(sections.map { ($0.short, $0.id) }, uniquingKeysWith: { a, _ in a })
        func jump(to label: String) {
            // A letter with nothing under it goes to the next letter that has something.
            guard let at = labels.firstIndex(of: label), let hit = labels[at...].first(where: { present[$0] != nil }) ?? labels.last(where: { present[$0] != nil }), let id = present[hit] else { return }
            if jumped != id { jumped = id; proxy.scrollTo(id, anchor: .top) }
        }
        let row: CGFloat = 14
        return VStack(spacing: 0) {
            ForEach(labels, id: \.self) { l in
                let on = present[l] != nil && present[l] == jumped
                Text(l).font(.figtree(10, .heavy, relativeTo: .caption2)).dynamicTypeSize(.large)
                    .foregroundStyle(on ? accent.onSolid : (present[l] != nil ? accent.ink : Theme.faint.opacity(0.6)))
                    .frame(width: 16, height: row)
                    .background { if on { Capsule().fill(accent.solid) } }
            }
        }
        .frame(width: 28)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            jump(to: labels[min(max(Int(v.location.y / row), 0), labels.count - 1)])
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jump index")
        .accessibilityValue(jumped.flatMap { id in sections.first { $0.id == id }?.heading } ?? "")
        .accessibilityAdjustableAction { direction in
            let ids = sections.map(\.id)
            let at = jumped.flatMap { ids.firstIndex(of: $0) } ?? -1
            let to = direction == .increment ? min(at + 1, ids.count - 1) : max(at - 1, 0)
            if ids.indices.contains(to) { jumped = ids[to]; proxy.scrollTo(ids[to], anchor: .top) }
        }
    }

    // MARK: saved panel

    /// The last save's summary while its box version is still the current one: after Undo, a later edit or a switch of account it goes.
    private var savedSummary: SaveSummary? {
        guard let s = model.lastSave, s.account == model.account, s.seq == model.snapshot?.seq else { return nil }
        return s
    }

    private func savedPanel(_ s: SaveSummary) -> some View {
        Panel(tint: .green, padding: 18, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark").font(.figtree(18, .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Circle().fill(Theme.green)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved to \(s.account)").font(.figtree(18, .heavy, relativeTo: .headline)).foregroundStyle(Theme.greenInk)
                    TimelineView(.periodic(from: .now, by: 20)) { ctx in
                        Text(Self.ago(s.date, ctx.date)).font(.figtree(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.greenInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.previous != nil {
                    Button { Task { await model.restorePrevious() } } label: {
                        Text("Undo").font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.greenInk).padding(.horizontal, 6).frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityHint("Goes back to the box as it was before this save")
                }
            }
            if s.showsCounts {
                HStack(spacing: 6) {
                    stat(s.added, "new"); stat(s.updated, "updated"); stat(s.removed, "removed")
                }
            }
            if index.toCheckCount > 0 {
                Button { chip = .toCheck } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.figtree(16, .bold)).foregroundStyle(Theme.orangeInk).accessibilityHidden(true)
                        Text("\(index.toCheckCount.formatted()) still to check").font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.figtree(13, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.insetRow, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                // With the To check chip on, the button sits under the chips instead.
                if chip != .toCheck { rescanButton }
            }
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n.formatted()).font(.figtree(22, .heavy, relativeTo: .title2)).monospacedDigit().foregroundStyle(Theme.ink)
            Text(label).font(.figtree(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.insetRow, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private static func ago(_ date: Date, _ now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }

    // MARK: search

    /// Waits 150 ms after the last keystroke, then builds the rows: a chip, a sort or a new box version builds them at once.
    private func recompute() async {
        let q = BoxIndex.Query(query)
        if q != applied { try? await Task.sleep(nanoseconds: 150_000_000) }
        if Task.isCancelled { return }
        let idx = index, chip = chip, sort = sort
        let result: [BoxIndex.Section]
        if idx.count < 2000 { result = idx.sections(query: q, chip: chip, sort: sort) }
        else { result = await Task.detached(priority: .userInitiated) { idx.sections(query: q, chip: chip, sort: sort) }.value }
        if Task.isCancelled { return }
        applied = q; sections = result; sectionsReady = true
    }
}

private struct ChipShadow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { if on { content.panelShadow() } else { content } }
}
