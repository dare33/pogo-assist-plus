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
    @State private var choosingExport = false
    @State private var confirmDiscardWaiting = false
    @State private var applied = BoxIndex.Query.none
    @State private var chip = BoxIndex.Chip.all
    @State private var sort = BoxIndex.Sort.name
    @State private var sections: [BoxIndex.Section] = []
    /// The index key `sections` were computed for; they show only while it is the current account's and box version's.
    @State private var sectionsFor: String?
    @State private var jumped: String?
    @State private var rankingInfo = false
    @State private var headerContentHeight: CGFloat = 0
    @State private var listAreaHeight: CGFloat = 0
    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue
    @FocusState private var searching: Bool
    #if DEBUG
    @State private var benchText: String?
    private var synthetic: Bool { CommandLine.arguments.contains("-box-synthetic") }
    #else
    private var synthetic: Bool { false }
    #endif

    private var indexKey: String { "\(model.account ?? "")|\(model.snapshot?.seq ?? -1)" }
    /// What the store's index and the sections must be built for to be shown (the synthetic box installs its own).
    private var wantedKey: String { synthetic ? "synthetic" : indexKey }
    /// The sections are the current account's and box version's. A big box builds its index away from the main thread, so after a switch of account the previous
    /// account's sections can still be in `sections`: they are never shown, the progress view stands in until the new ones are computed.
    private var sectionsCurrent: Bool { Self.showsSections(computedFor: sectionsFor, current: wantedKey) }
    /// Keys read "account|seq". Sections of the same account stay up while a newer box version is indexed (a hand fix keeps the rows and the scroll position); another account's never show.
    static func showsSections(computedFor: String?, current: String) -> Bool {
        guard let computedFor else { return false }
        func account(_ k: String) -> Substring { k.lastIndex(of: "|").map { k[..<$0] } ?? k[...] }
        return account(computedFor) == account(current)
    }
    private var index: BoxIndex { store.index }

    private var pogoAssist: Bool { rankingRaw == Ranking.pogoAssist.rawValue }
    /// The advice, once it is ready for this box version (the tags, tiles and activity chips read it).
    private var readyAdvice: BoxAdvice? { if case .ready(let a) = model.advice { return a } else { return nil } }
    private var adviceState: InsightKey.State { InsightKey.State(model.advice) }
    private var insightKey: InsightKey { InsightKey(account: model.account, seq: model.snapshot?.seq, state: adviceState) }
    /// The insight read for this account (never another account's).
    private var insight: BoxInsight? { store.insight(forAccount: model.account) }
    /// The advice is still being worked out, or it is ready but the insight is not yet built for this box version (cached advice at launch or after a switch of
    /// account): "…" and "Working out…", not "—". A failed advice is not waiting: it never arrives.
    private var insightWaiting: Bool { insightKey.isWaiting(builtFor: store.insightBuiltFor) }

    private struct SectionKey: Equatable { var query: String; var chip: BoxIndex.Chip; var sort: BoxIndex.Sort; var version: Int; var insightVersion: Int; var pogoAssist: Bool }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if let problem = model.boxProblem { problemState(problem) }
                else if !model.boxLoaded && model.entries.isEmpty && !synthetic { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if model.entries.isEmpty && !synthetic { emptyState }
                else if !sectionsCurrent { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
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
        .confirmationDialog("Discard the waiting scan?", isPresented: $confirmDiscardWaiting, titleVisibility: .visible) {
            Button("Discard scan", role: .destructive) { model.discardWaitingScan() }
        } message: { Text(model.waitingScan.map { $0.damaged ? "It is thrown away without being added to any box." : "The scan for \($0.account) is thrown away without being added to its box." } ?? "") }
        .sheet(isPresented: Binding(get: { model.exportURL != nil }, set: { if !$0 { model.exportURL = nil } })) {
            if let url = model.exportURL {
                ShareSheet(url: url).presentationDetents([.medium, .large])
                    // The share sheet shortens the file name in its preview; this says it whole (and lets a UI test check the file's kind).
                    .overlay(alignment: .topLeading) { Color.clear.frame(width: 1, height: 1).accessibilityElement().accessibilityIdentifier("export-file").accessibilityLabel(url.lastPathComponent) }
            }
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
        .task(id: insightKey) {
            if synthetic { return }
            await store.refreshInsight(key: insightKey, advice: readyAdvice, entries: model.entries)
        }
        .task(id: SectionKey(query: query, chip: chip, sort: sort, version: store.version, insightVersion: store.insightVersion, pogoAssist: pogoAssist)) { await recompute() }
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
                IconButton(systemImage: "square.and.arrow.up", kind: .floating, label: "Export") { choosingExport = true }
                    .exportChoice(isPresented: $choosingExport) { format in Task { await model.export(format) } }
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
                Text(model.boxNeedsNewerApp ? "This box needs a newer version of the app" : model.storageMissing ? "There is nowhere to keep your box" : model.recoveryProblem != nil ? "A rename is unfinished" : "This box could not be read").paText(.questionTitle).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                Text(text).paText(.secondary).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                if !model.boxNeedsNewerApp && !model.storageMissing && model.recoveryProblem == nil {
                    PillButton("Restore the latest readable version", style: .filled) { Task { await model.restoreLatestReadable() } }
                }
                Text("Scanning is paused until this is resolved.").font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                if model.waitingScan != nil {
                    // A scan waiting for this box would block scanning for good; it can be thrown away without the box being readable.
                    Text(model.waitingScan.map { $0.damaged ? "A scan left from earlier is also kept on this phone." : "A scan for \($0.account) is also waiting to be reviewed." } ?? "")
                        .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    PillButton("Discard the waiting scan", style: .plain, isDestructive: true) { confirmDiscardWaiting = true }.accessibilityIdentifier("discard-waiting-scan")
                }
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

    /// The count line, search, chips and sort line (with the ranking switch and its explainer) stay fixed while the species list scrolls under them (Greg, 25 Oct 2026).
    /// The saved-scan panel is not part of that block; it stays at the top of the scrolling list. An open ranking explainer sits inside the fixed block and pushes the list down.
    private var list: some View {
        VStack(spacing: 0) {
            frozenHeader
            listScroll
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listAreaHeight = $0 }
    }

    /// The fixed block is as tall as its content up to `headerShare` of the list's area; beyond that (an open ranking explainer at the largest text sizes would
    /// otherwise fill the screen and cut itself off) it scrolls inside itself and the list keeps the rest. Below that share nothing scrolls.
    private static let headerShare: CGFloat = 0.55

    private var frozenHeader: some View {
        ScrollViewReader { headerProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                countLine
                searchField
                chips
                if chip == .toCheck { rescanButton }
                sortLine
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerContentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        // An opened explainer is brought into view inside the capped block.
        .onChange(of: rankingInfo) { _, open in
            // After the explainer's first layout, or the scroll runs to where its end was.
            if open { Task { try? await Task.sleep(nanoseconds: 250_000_000); withAnimation { headerProxy.scrollTo("ranking-explainer", anchor: .bottom) } } }
        }
        .frame(height: headerContentHeight > 0 && listAreaHeight > 0 ? min(headerContentHeight, listAreaHeight * Self.headerShare) : nil)
        .background(Theme.bg)
        .zIndex(1)
        }
    }

    private var listScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                    if let s = savedSummary { savedPanel(s) }
                    if sections.isEmpty {
                        // An activity chip waits for the advice: until then nothing can be Strong or OK, which is not the same as no match. A failed advice says so.
                        let isActivity: Bool = { if case .activity = chip { return true } else { return false } }()
                        Text(isActivity && insight == nil ? (adviceState == .failed ? "Advice could not be worked out" : "Working out advice…") : "No Pokémon match.").paText(.secondary).foregroundStyle(Theme.muted).padding(.horizontal, 6).padding(.vertical, 20)
                    }
                    ForEach(sections) { sectionView($0) }
                }
                .padding(.leading, Theme.Space.screen)
                .padding(.trailing, Theme.Space.screen + (showsIndex ? 18 : 0))
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .trailing) { if showsIndex { jumpIndex(proxy) } }
        }
    }

    /// "2,115 Pokémon · 349 species" with the to-check badge at its trailing end (it wraps under the count where the two no longer fit).
    private var countLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) { countText; Spacer(minLength: 8); toCheckBadge }
            VStack(alignment: .leading, spacing: 2) { countText; toCheckBadge }
        }
        .padding(.horizontal, 6)
    }

    private var countText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(index.count.formatted()).paText(.screenTitle).foregroundStyle(Theme.ink)
            Text("Pokémon · \(index.speciesCount.formatted()) species").font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .combine)
    }

    /// The flag and the number of Pokémon to check: tapping filters the list to them (what the To check chip did), tapping again clears it. Hidden at 0.
    @ViewBuilder private var toCheckBadge: some View {
        if index.toCheckCount > 0 {
            let on = chip == .toCheck
            Button { chip = on ? .all : .toCheck; searching = false } label: {
                HStack(spacing: 4) {
                    Image(systemName: on ? "flag.fill" : "flag").font(.figtree(11, .heavy)).accessibilityHidden(true)
                    Text(index.toCheckCount.formatted()).font(.figtree(12, .heavy, relativeTo: .caption)).monospacedDigit()
                }
                .foregroundStyle(on ? Theme.bg : Theme.orangeInk)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(on ? Theme.orangeInk : Theme.orangeTint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.vertical, 8).padding(.horizontal, 2).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .padding(.vertical, -8)
            .accessibilityLabel("To check \(index.toCheckCount.formatted())")
            .accessibilityHint(on ? "Shows every Pokémon again" : "Shows only the Pokémon to check")
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("to-check-badge")
        }
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
        guard sectionsCurrent, applied == BoxIndex.Query(query) else { return nil }
        return sections.reduce(0) { $0 + $1.rows.reduce(0) { $0 + $1.stats.count } }
    }

    // MARK: chips and sort

    /// The activity filter: All, then Raids, Gym, Rocket, Great, Ultra, Master and Max (each in its colours), and Fixed by hand after them while the box has any hand
    /// corrections. "To check" moved to the badge in the count line. There is no "Not seen" chip: the saved box does not record which entries a Full scan saw but could
    /// not read ("On screen but not read", "Stationed"), so an old last-seen date cannot say "not seen".
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip("All", .all)
                ForEach(BoxInsight.Activity.allCases, id: \.self) { filterChip($0.title, .activity($0)) }
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
            let search = toCheckSearch
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if let text = search.text {
                        PillButton("Copy search", systemImage: "doc.on.doc", style: .tint) { UIPasteboard.general.string = text; showToast("Copied") }
                            .accessibilityIdentifier("copy-check-search").accessibilityValue(text)
                    }
                    PillButton("Re-scan \(index.toCheckCount.formatted())", systemImage: "arrow.clockwise", style: .tint) { model.startRescan(count: index.toCheckCount, shown: search.text == nil ? index.toCheckCount : search.covered + search.extra) }
                        .accessibilityIdentifier("rescan-button")
                }
                if let line = Self.searchLine(search) {
                    Text(line).font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("check-search-line")
                }
            }
        }
    }

    /// What the copied search really shows: the to-check Pokémon it covers plus the others in the box with the same name and CP (or HP). The game can show more than the box knows of.
    static func searchLine(_ s: BoxIndex.PickedSearch) -> String? {
        guard s.text != nil else { return nil }
        let covered = s.covered.formatted()
        var line = s.extra > 0
            ? "The search shows at least \((s.covered + s.extra).formatted()) in the game: \(covered) to check and \(s.extra.formatted()) \(s.extra == 1 ? "other" : "others") with the same name and CP or HP."
            : "The search finds the \(covered) to check and no others in your box."
        if s.notCovered > 0 { line += " \(s.notCovered.formatted()) of them \(s.notCovered == 1 ? "is" : "are") not in the search." }
        return line
    }

    private var toCheckSearch: BoxIndex.PickedSearch {
        index.gameSearch(picked: index.items.indices.filter { index.items[$0].needsCheck })
    }

    /// A selected chip is filled with its colour, the others are soft: an activity or league tint with its ink, All and Fixed by hand on the surface.
    private func filterChip(_ title: String, _ value: BoxIndex.Chip) -> some View {
        let on = chip == value
        var ink = Theme.ink, tint = Theme.surface
        var identifier = "chip-all", soft = false
        if case .activity(let a) = value { ink = a.ink(accent); tint = a.tint(accent); identifier = "chip-\(a.rawValue)"; soft = true }
        if value == .fixed { identifier = "chip-fixed" }
        return Button { chip = value; searching = false } label: {
            Text(title).font(.figtree(14, on || soft ? .bold : .semibold, relativeTo: .subheadline))
                .foregroundStyle(on ? Theme.bg : ink)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().fill(on ? ink : tint))
                .modifier(ChipShadow(on: !on && !soft))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// Left the sort menu (Name or Top CP), right the ranking switch (Classic | Pogo Assist) and its "i"; the explainer opens under the line. The switch is the
    /// app-wide preference the Leagues panel and the species list share.
    private var sortLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { sortMenu; Spacer(minLength: 8); RankingSwitch(infoOpen: $rankingInfo, identifier: "list-scoring") }
                VStack(alignment: .leading, spacing: 0) { sortMenu; RankingSwitch(infoOpen: $rankingInfo, identifier: "list-scoring") }
            }
            if rankingInfo { RankingExplainer(identifier: "list-scoring-explainer").id("ranking-explainer").transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.15), value: rankingInfo)
        .padding(.horizontal, 4)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                Text("Name").tag(BoxIndex.Sort.name)
                Text("Top CP").tag(BoxIndex.Sort.topCP)
            }
        } label: {
            Label(sort == .name ? "Name" : "Top CP", systemImage: "arrow.up.arrow.down")
                .font(.figtree(13, .bold, relativeTo: .footnote)).labelStyle(.titleAndIcon)
                .foregroundStyle(accent.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Sort, \(sort == .name ? "Name" : "Top CP")")
        .accessibilityIdentifier("sort-menu")
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
        let activity: BoxInsight.Activity? = { if case .activity(let a) = chip { return a } else { return nil } }()
        let check = r.stats.toCheck > 0 ? "\(r.stats.toCheck) to check" : nil
        var label = "\(r.title), \(r.stats.count) Pokémon"
        if let activity, let lead = r.lead { label += ", \(lead.label) for \(activity.title)" }
        label += ". " + LeagueTiles.spoken(title: r.title, insight: insight, waiting: insightWaiting, pogoAssist: pogoAssist)
        if let check { label += ". " + check }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    FlowLayout(spacing: 8) {
                        Text(r.title).font(.figtree(16, .bold, relativeTo: .body)).foregroundStyle(Theme.ink)
                        // With a chip chosen, the species' best copy's tag for it: the list reads as a ranking.
                        if let activity, let lead = r.lead { WorthTag(activity: activity, worth: lead) }
                    }
                    if let check { Text(check).font(.figtree(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.orangeInk) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(r.stats.count.formatted()).font(.figtree(13, .heavy, relativeTo: .footnote)).monospacedDigit().foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).frame(minWidth: 34, minHeight: 26)
                    .background(Theme.surface2, in: Capsule())
                Image(systemName: "chevron.right").font(.figtree(13, .bold)).foregroundStyle(Theme.faint).accessibilityHidden(true)
            }
            LeagueTiles(title: r.title, insight: insight, waiting: insightWaiting, pogoAssist: pogoAssist)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 16) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
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
        let idx = index, built = store.indexKey, chip = chip, sort = sort
        let scoring = BoxIndex.Scoring(insight: insight, pogoAssist: pogoAssist)
        let result: [BoxIndex.Section]
        if idx.count < 2000 { result = idx.sections(query: q, chip: chip, sort: sort, scoring: scoring) }
        else { result = await Task.detached(priority: .userInitiated) { idx.sections(query: q, chip: chip, sort: sort, scoring: scoring) }.value }
        // Only for the index still on the store: a detached pass for the previous account or box version must not land on this one.
        if Task.isCancelled || built != store.indexKey { return }
        applied = q; sections = result; sectionsFor = built
    }
}

private struct ChipShadow: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { if on { content.panelShadow() } else { content } }
}
