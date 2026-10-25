import SwiftUI
import PogoBox
import PogoReader

/// One Pokémon (design pass 3, Option A): the details card with its marks and advanced details, the activity tabs (Summary, PvP, Raids, Gym, Rocket, Max), the
/// facts and Delete under every tab. The tab bar is hidden here, as in the prototype. All rules come from PogoBox (`PokemonActivities`, `PokemonPage`,
/// `AdvancedDetails`, `LeaguePanel`); this file and its neighbours only lay them out.
struct PokemonDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    let id: String
    @State private var tab: PokemonActivities.Tab
    /// The league tile chosen on the PvP tab (a league key). Per screen, not stored.
    @State private var league: String
    @State private var fixing = false
    @State private var deleting: DeleteTarget?
    @State private var advancedOpen = false
    /// An edit is being saved: the marks and chips wait for it (two quick taps would save twice).
    @State private var saving = false
    @AppStorage(PrefKey.megaDefault) private var megaDefault = MegaDefault.normal.rawValue
    @AppStorage(PrefKey.ranking) private var rankingRaw = Ranking.default.rawValue
    @Environment(\.showToast) private var showToast
    /// The switch's position once the person has moved it; until then the Settings choice.
    @State private var chosenMega: Bool?
    /// "How it was read" is one line that opens its notes beneath it.
    @State private var notesOpen = false
    /// What the page works out from the advice, kept until the advice or the box changes.
    @State private var cache = PageCache()
    /// Bumped each time the advice changes, so the cache is rebuilt.
    @State private var adviceGen = 0

    /// `initialLeague` (a league key) opens the page on the PvP tab with that league's tile chosen (a tap on a TOP PVP copy, rule 6); otherwise it opens on Summary (rule 19).
    init(id: String, initialLeague: String? = nil) {
        self.id = id
        let league = initialLeague ?? Self.testLeague
        _tab = State(initialValue: league == nil ? .summary : .pvp)
        _league = State(initialValue: league ?? "gl")
    }

    /// A DEBUG build honours `-uitest-initial-league gl|ul|ml`, so a UI test can open the page as a TOP PVP copy does without the list's route.
    private static var testLeague: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-uitest-initial-league"), i + 1 < args.count, LeaguePanel.keys.contains(args[i + 1]) { return args[i + 1] }
        #endif
        return nil
    }

    /// The Mega form the page shows now: only for an entry whose Mega form has a CP, and only while the switch is on Mega.
    private func megaShown(_ e: BoxEntry) -> MegaForm? {
        guard let mf = e.shownMegaForm, chosenMega ?? (megaDefault == MegaDefault.mega.rawValue) else { return nil }
        return mf
    }

    private var pogoAssist: Bool { rankingRaw == Ranking.pogoAssist.rawValue }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let e = model.entry(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                        if !e.row.checkFlags.isEmpty { checkPanel(e) }
                        PokemonDetailsCard(entry: e, mega: megaShown(e), advancedOpen: $advancedOpen, apply: apply)
                        if e.shownMegaForm != nil { formSwitch(on: megaShown(e) != nil).frame(maxWidth: .infinity, alignment: .leading) }
                        if megaShown(e) != nil { megaSearchNote }
                        ActivityTabBar(selection: $tab)
                        tabContent(e)
                        factsPanel(e, mega: megaShown(e))
                        notesPanel(e, mega: megaShown(e))
                        deleteButton(e)
                    }
                    .padding(.horizontal, Theme.Space.screen)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                }
                .sheet(isPresented: $fixing) { FixValueView(entry: e).environmentObject(model) }
            } else {
                Text("This Pokémon is no longer in the box.").paText(.secondary).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .confirmDelete($deleting) { dismiss() }
        .onChange(of: model.advice) { _, _ in adviceGen += 1 }
    }

    // MARK: header

    /// Back, the orange search circle (copies the game search) and the pencil (Fix a value, unchanged).
    private var header: some View {
        HStack {
            IconButton(systemImage: "chevron.left", kind: .floating, label: "Back") { dismiss() }
            Spacer()
            if let e = model.entry(id) {
                // The search is always the normal form's: the game shows a Mega CP only while the Pokémon is Mega evolved, so a search on it would find nothing the rest of the time.
                if let search = GameSearch.text([GameSearch.part(row: e.row)]) {
                    Button {
                        UIPasteboard.general.string = search
                        showToast("Copied")
                    } label: {
                        IconButton(systemImage: "magnifyingglass", kind: .floating, label: "Copy search", inkOverride: Theme.orangeInk) {}.face
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Copy search")
                    .accessibilityValue(search)
                    .accessibilityIdentifier("search-chip")
                }
                // "Fix a value" changes the normal values only, so it waits while the page shows the Mega form.
                let onMega = megaShown(e) != nil
                IconButton(systemImage: "pencil", kind: .floating, label: "Fix a value") { fixing = true }
                    .disabled(onMega).opacity(onMega ? 0.4 : 1)
                    .accessibilityHint(onMega ? "Fixing changes the normal values. Switch to Normal first." : "")
            }
        }
        .padding(.horizontal, Theme.Space.screen)
        .frame(minHeight: 52)
        // The circles hold a glyph that would outgrow them at the accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Every mark and chip saves through the data model's edit as a box version; the advice is worked out again (AppModel.correct).
    private func apply(_ edit: BoxMerge.Edit) {
        guard !saving else { return }
        saving = true
        Task {
            let result = await model.correct(id, edit)
            saving = false
            if let error = result.error { model.message = error }
        }
    }

    // MARK: Normal / Mega

    /// Two parts, as Settings > Appearance's mode switch: the page shows the normal form or the Mega form of this one Pokémon. IVs, advice, checks and Delete are the same for both.
    private func formSwitch(on mega: Bool) -> some View {
        HStack(spacing: 0) {
            formButton("Normal", selected: !mega, to: false)
            formButton("Mega", selected: mega, to: true)
        }
        .padding(4).background(Theme.off, in: Capsule())
        .frame(maxWidth: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Form")
    }

    private func formButton(_ title: String, selected: Bool, to mega: Bool) -> some View {
        Button { chosenMega = mega } label: {
            Text(title).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(selected ? Theme.surface : Color.clear, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("form-\(title.lowercased())")
    }

    private var megaSearchNote: some View {
        Text("The game shows the Mega CP only while it is Mega evolved, so this search uses the normal CP.")
            .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .accessibilityIdentifier("mega-search-note")
    }

    // MARK: a check

    private func checkPanel(_ e: BoxEntry) -> some View {
        Panel(tint: .orange, padding: 16, spacing: 10) {
            ForEach(e.row.checkFlags, id: \.self) { Text(FlagInfo.explain($0)).font(.figtree(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.orangeInk).fixedSize(horizontal: false, vertical: true) }
            Button { Task { await model.markChecked(id) } } label: {
                Text("These values are right").font(.figtree(15, .heavy, relativeTo: .subheadline)).foregroundStyle(Theme.orangeInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(Theme.surface))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
        }
    }

    // MARK: the tabs

    /// What the advice gives the page: the last ready advice stays on show while a new one is worked out (an edit recomputes it), so the page does not jump.
    private var readyAdvice: BoxAdvice? {
        if case .ready(let a) = model.advice { cache.lastReady = a; return a }
        return cache.lastReady
    }

    private func context(_ advice: BoxAdvice) -> HubContext? {
        cache.context(key: "\(adviceGen)|\(model.snapshot?.seq ?? -1)") {
            guard let gm = try? GameMaster.bundled(), let hub = try? HubData.bundled(), let table = try? TierTable.bundled() else { return nil }
            return HubContext(advice: advice, entries: model.entries, gm: gm, hub: hub, table: table, today: HubModel.today())
        }
    }

    @ViewBuilder private func tabContent(_ e: BoxEntry) -> some View {
        if let advice = readyAdvice, let ctx = context(advice) {
            switch tab {
            case .summary:
                let rows = cache.value("summary|\(pogoAssist)") { PokemonActivities.summary(copy: e, ctx: ctx, pogoAssist: pogoAssist) }
                SummaryRowsPanel(rows: rows) { tab = $0 }
                AdvicePanel(entry: e, advice: advice)
            case .pvp: leaguesPanel(e, advice: advice)
            case .raids:
                let cards = cache.value("raids") { PokemonActivities.raidCards(copy: e, ctx: ctx) }
                RaidsTab(copy: e, family: familyName(e, ctx), cards: cards)
            case .gym:
                let top = cache.value("top") { PokemonActivities.topDefender(ctx: ctx) }
                let cards = cache.value("gym") { PokemonActivities.gymCards(copy: e, ctx: ctx, top: top) }
                GymTab(copy: e, family: familyName(e, ctx), cards: cards, top: top)
            case .rocket:
                RocketTab(cards: cache.value("rocket") { PokemonActivities.rocketCards(copy: e, ctx: ctx) })
            case .max:
                let max = cache.value("max") { PokemonActivities.maxCards(copy: e, ctx: ctx) }
                MaxTab(copy: e, family: familyName(e, ctx), cards: max.cards, battles: max.battles)
            }
        } else {
            switch model.advice {
            case .computing:
                Panel(tint: .accent, padding: 18, spacing: 8) {
                    HStack(spacing: 10) { ProgressView(); Text("Working out advice").font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.ink) }
                }
            case .failed(let m):
                Panel(tint: .accent, padding: 18, spacing: 8) {
                    Text("Advice could not be worked out: \(m)").font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
                }
            default: EmptyView()
            }
        }
    }

    private func familyName(_ e: BoxEntry, _ ctx: HubContext) -> String { PokemonActivities.members(of: e, ctx: ctx).first?.name ?? e.row.title }

    // MARK: leagues

    /// Great, Ultra and Master League for this Pokémon, all read from the cached advice: nothing is worked out here.
    @ViewBuilder private func leaguesPanel(_ e: BoxEntry, advice: BoxAdvice) -> some View {
        let ratings = advice.leagues(for: e.id)
        if megaShown(e) != nil {
            // Megas are not allowed in GO Battle League, so the tab says so while the page shows the Mega form.
            Panel(padding: 16, spacing: 8) {
                Text("PVP LEAGUES").font(.figtree(13, .heavy, relativeTo: .footnote)).tracking(0.5).foregroundStyle(ContentType.pvp.ink(accent))
                Text("Mega Pokémon cannot battle in GO Battle League. Switch to Normal to see the leagues.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
        } else if !ratings.isEmpty {
            let a = advice.entries(for: e.id)
            LeaguesPanel(ratings: ratings, level: e.row.level, showsShadowNote: e.row.shadow == nil, builds: a.builds, transfers: a.transfersWithNoBuild, selected: $league)
        } else {
            Panel(padding: 16, spacing: 8) { Text("No league ratings for this Pokémon.").font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.muted) }
        }
    }

    // MARK: under every tab

    private func factsPanel(_ e: BoxEntry, mega: MegaForm?) -> some View {
        var spares = 0
        if case .ready(let advice) = model.advice { spares = advice.entries(for: e.id).builds.map(\.spares).max() ?? 0 }
        else if let advice = cache.lastReady { spares = advice.entries(for: e.id).builds.map(\.spares).max() ?? 0 }
        let first = Self.short(mega?.firstSeen ?? e.firstSeen), last = Self.short(mega?.lastSeen ?? e.lastSeen)
        return PageFacts(dust: mega != nil ? mega?.dust : e.row.dust, spares: spares, seen: first == last ? first : "\(first) · \(last)")
    }

    private func deleteButton(_ e: BoxEntry) -> some View {
        VStack(spacing: 2) {
            Button { deleting = DeleteTarget(id: e.id, title: e.row.title, cp: e.row.cp) } label: {
                Text("Delete from box").font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityHint("Removes it from the box only, not from the game")
            Text("Removes this copy from the app's box only, not from the game.").font(.figtree(12, .regular, relativeTo: .caption)).foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: how it was read

    @ViewBuilder private func notesPanel(_ e: BoxEntry, mega: MegaForm?) -> some View {
        let r = e.row
        // Only the read notes fold away behind the one line; the Mega and hand-corrected notes stay in view as they were, and with no read
        // notes there is no line.
        if !r.noteFlags.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.easeOut(duration: 0.15)) { notesOpen.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text("How it was read").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        Image(systemName: "chevron.right").font(.figtree(11, .bold)).foregroundStyle(Theme.muted).rotationEffect(.degrees(notesOpen ? 90 : 0)).accessibilityHidden(true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(notesOpen ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("how-it-was-read")
                if notesOpen { ForEach(r.noteFlags, id: \.self) { Text(FlagInfo.explainNote($0)).paText(.secondary).foregroundStyle(Theme.muted) } }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if e.megaWhenScanned == true || mega != nil || e.isHandCorrected {
            Panel(padding: 16, spacing: 10) {
                if mega != nil {
                    Label("The Mega CP is temporary: these are the Mega values from the last scan that saw it Mega evolved. The IVs and the advice are the same for both forms. To fix a value, switch to Normal.", systemImage: "sparkles").paText(.secondary).foregroundStyle(Theme.muted)
                } else if e.megaWhenScanned == true {
                    Label("Mega evolved when scanned. The Mega CP is temporary, so the values above are from an earlier scan.", systemImage: "sparkles").paText(.secondary).foregroundStyle(Theme.muted)
                }
                if e.isHandCorrected {
                    Label("Corrected by hand: \(corrected(e)). A later scan will not undo it unless the Pokémon has changed.", systemImage: "pencil").paText(.secondary).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    /// "4 Oct": the year is left out, as in the design.
    private static func short(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }

    private func corrected(_ e: BoxEntry) -> String {
        var parts = [String]()
        if e.corrections.species != nil { parts.append("name") }
        if e.corrections.cp != nil { parts.append("CP") }
        if e.corrections.hp != nil { parts.append("HP") }
        if e.corrections.ivs != nil { parts.append("IVs") }
        return parts.joined(separator: ", ")
    }
}

struct BuildRow: View {
    let build: BoxAdvice.Build
    var showName = true
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if showName { Text(build.title).font(.callout.weight(.medium)) }
            Text(build.action + (build.pvp.map { " (\($0))" } ?? "")).font(showName ? .callout : .callout.weight(.medium))
            if showName {
                Text("CP \(build.cp)" + (build.ivs.map { ", IVs \($0)" } ?? "") + (build.level.map { ", level \(Fmt.number($0))" } ?? "")).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            if showName {
                // The Next list: the advisor's order mixes worth with ease, so the two are shown apart. Worth is the build's best tier among its areas;
                // effort is the dust, candy and XL it costs ("No dust or candy" when none; the steps are the action line above).
                Text(build.areas.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 24) {
                    // The tag on the Box list is per copy (its roll included); this tier is the build target's, so the copy's roll (league rank or IV %) is shown beside it.
                    labelled("Worth", build.worthText)
                    labelled("Effort", build.effortText)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("\(build.areas.joined(separator: ", ")) · tier \(build.tier)").font(.footnote).foregroundStyle(.secondary)
            }
            // The Next list already shows the cost as EFFORT, so its line keeps the level climb and what it leaves; the Advice panel's line carries the cost.
            let line = showName ? climbLine : costLine
            if !line.isEmpty { Text(line).font(.footnote).foregroundStyle(.secondary) }
            if build.spares > 0 { Text("\(build.spares) spare \(build.spares == 1 ? "copy" : "copies")").font(.footnote).foregroundStyle(.secondary) }
        }
    }
    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit()
        }
    }
    private var climb: String {
        let from = build.level.map { "Level \(Fmt.number($0))" } ?? ""
        let to = build.climbLevel.map { $0 > (build.level ?? 0) ? " to \(Fmt.number($0))" : "" } ?? ""
        return from.isEmpty ? "" : from + to
    }
    /// "Level 20 to 35; going past 27 leaves UL": the climb without its cost (the Next list shows the cost as EFFORT). Empty when there is neither.
    var climbLine: String {
        [climb, build.leavesLeagueText ?? ""].filter { !$0.isEmpty }.joined(separator: "; ")
    }
    var costLine: String {
        let cost = build.dust == 0 && build.candy == 0 && build.xl == 0 ? "no dust or candy to spend" : build.costText
        let line = (climb.isEmpty ? "" : climb + ": ") + cost
        return build.leavesLeagueText.map { line + "; " + $0 } ?? line
    }
}

/// "Fix a value": CP, HP, IVs or the species name, by hand.
struct FixValueView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: BoxEntry
    @State private var name = ""
    @State private var cp = ""
    @State private var hp = ""
    @State private var atk = ""
    @State private var def = ""
    @State private var sta = ""
    @State private var error: String?
    @State private var saving = false

    private var suggestions: [String] {
        let all = (try? GameMaster.bundled().names(matching: name)) ?? []
        return name == entry.row.title || name.isEmpty ? [] : all.filter { $0.lowercased() != name.lowercased() }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Species name", text: $name).autocorrectionDisabled().textInputAutocapitalization(.words)
                    ForEach(suggestions, id: \.self) { s in Button(s) { name = s }.foregroundStyle(.primary) }
                }
                Section("Values") {
                    field("CP", $cp)
                    field("HP", $hp)
                }
                Section("IVs") {
                    field("Attack", $atk)
                    field("Defence", $def)
                    field("Stamina", $sta)
                }
                Section {
                    Text("A value you change is marked as corrected by hand, and the check for it is cleared. The level and dust are worked out again from the new values. A later scan will not overwrite it unless the Pokémon has really changed.").font(.footnote).foregroundStyle(.secondary)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Fix a value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saving) }
            }
            .onAppear(perform: load)
        }
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        HStack { Text(title); Spacer(); TextField("not read", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 120) }
    }

    private func load() {
        let r = entry.row
        name = r.title; cp = r.cp > 0 ? String(r.cp) : ""; hp = r.hp.map(String.init) ?? ""
        atk = r.ivs.map { String($0.atk) } ?? ""; def = r.ivs.map { String($0.def) } ?? ""; sta = r.ivs.map { String($0.hp) } ?? ""
    }

    private func save() {
        var edit = BoxMerge.Edit()
        func int(_ s: String) -> Int? { Int(s.trimmingCharacters(in: .whitespaces)) }
        if cp.trimmingCharacters(in: .whitespaces) != (entry.row.cp > 0 ? String(entry.row.cp) : "") {
            guard let v = int(cp) else { error = "CP must be a whole number."; return }
            edit.cp = v
        }
        if hp.trimmingCharacters(in: .whitespaces) != (entry.row.hp.map(String.init) ?? "") {
            guard let v = int(hp) else { error = "HP must be a whole number."; return }
            edit.hp = v
        }
        let oldIVs = entry.row.ivs
        let typed = [atk, def, sta].map { $0.trimmingCharacters(in: .whitespaces) }
        if typed != [oldIVs.map { String($0.atk) } ?? "", oldIVs.map { String($0.def) } ?? "", oldIVs.map { String($0.hp) } ?? ""] {
            guard let a = int(typed[0]), let d = int(typed[1]), let s = int(typed[2]) else { error = "Fill in all three IVs, each a whole number from 0 to 15."; return }
            edit.ivs = IVs(atk: a, def: d, hp: s)
        }
        if name != entry.row.title { edit.speciesName = name }
        guard edit != BoxMerge.Edit() else { dismiss(); return }
        saving = true
        Task {
            let result = await model.correct(entry.id, edit)
            if let problem = result.error { error = problem; saving = false; return }
            if let notice = result.notice { model.message = notice }
            dismiss()
        }
    }
}

/// What the Pokémon page keeps between renders: the last ready advice and the rules' results for the current advice and box. A reference type held in `@State`,
/// so a render can read it without a change to it asking for another render.
final class PageCache {
    var lastReady: BoxAdvice?
    private var key = ""
    private var ctx: HubContext?
    private var memo = [String: Any]()

    func context(key: String, make: () -> HubContext?) -> HubContext? {
        if key != self.key || ctx == nil { self.key = key; ctx = make(); memo = [:] }
        return ctx
    }

    func value<T>(_ name: String, _ make: () -> T) -> T {
        if let v = memo[name] as? T { return v }
        let v = make()
        memo[name] = v
        return v
    }
}
