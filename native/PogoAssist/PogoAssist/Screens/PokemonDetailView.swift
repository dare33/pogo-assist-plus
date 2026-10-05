import SwiftUI
import PogoBox
import PogoReader

/// One Pokémon: name and CP as the heading, what to check, IV bars, the advice, a few facts and its own game search
/// (design handoff v2 section 1h and the prototype's detail). The tab bar is hidden here, as in the prototype.
struct PokemonDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    let id: String
    @State private var fixing = false
    @State private var deleting: DeleteTarget?
    @AppStorage(PrefKey.megaDefault) private var megaDefault = MegaDefault.normal.rawValue
    /// The switch's position once the person has moved it; until then the Settings choice.
    @State private var chosenMega: Bool?

    /// The Mega form the page shows now: only for an entry whose Mega form has a CP, and only while the switch is on Mega.
    private func megaShown(_ e: BoxEntry) -> MegaForm? {
        guard let mf = e.shownMegaForm, chosenMega ?? (megaDefault == MegaDefault.mega.rawValue) else { return nil }
        return mf
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                IconButton(systemImage: "chevron.left", kind: .floating, label: "Back") { dismiss() }
                Spacer()
                if let e = model.entry(id) {
                    // "Fix a value" changes the normal values only, so it waits while the page shows the Mega form.
                    let onMega = megaShown(e) != nil
                    IconButton(systemImage: "pencil", kind: .floating, label: "Fix a value") { fixing = true }
                        .disabled(onMega).opacity(onMega ? 0.4 : 1)
                        .accessibilityHint(onMega ? "Fixing changes the normal values. Switch to Normal first." : "")
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .frame(minHeight: 52)
            if let e = model.entry(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.panelGap) {
                        heading(e, mega: megaShown(e))
                        if !e.row.checkFlags.isEmpty { checkPanel(e) }
                        ivPanel(e.row)
                        advicePanel(e)
                        factsPanel(e, mega: megaShown(e))
                        notesPanel(e, mega: megaShown(e))
                        // The search is always the normal form's: the game shows a Mega CP only while the Pokémon is Mega evolved, so a search on it would find nothing the rest of the time.
                        if let search = GameSearch.text([GameSearch.part(row: e.row)]) {
                            SearchStrip(text: search, prominent: true)
                            if megaShown(e) != nil {
                                Text("The game shows the Mega CP only while it is Mega evolved, so this search uses the normal CP.")
                                    .font(.figtree(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("mega-search-note")
                            }
                        }
                        Button { deleting = DeleteTarget(id: e.id, title: e.row.title, cp: e.row.cp) } label: {
                            Text("Delete from box").font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.red)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .accessibilityHint("Removes it from the box only, not from the game")
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
    }

    // MARK: heading

    /// The entry's own values, or its Mega form's while the switch is on Mega.
    private func heading(_ e: BoxEntry, mega: MegaForm?) -> some View {
        let r = e.row
        let title = mega?.title ?? r.title, cp = mega?.cp ?? r.cp
        let level = mega != nil ? Fmt.level(mega?.level, mega?.levelMax) : Fmt.level(r), hp = mega != nil ? mega?.hp : r.hp
        let meta = [level.map { "Level \($0)" } ?? "Level not known", hp.map { "HP \($0)" } ?? "HP not read"]
        return VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.figtree(34, .heavy, relativeTo: .largeTitle)).tracking(-0.025 * 34).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: Fmt.cp(cp)).font(.figtree(cp > 0 ? 22 : 17, .heavy, relativeTo: .title2)).monospacedDigit().foregroundStyle(Theme.ink)
                Text(meta.joined(separator: " · ")).font(.figtree(15, .semibold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            if e.shownMegaForm != nil { formSwitch(on: mega != nil).padding(.top, 12) }
        }
        .padding(.horizontal, 8).padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: IVs

    private func ivPanel(_ r: ScanRow) -> some View {
        Panel {
            HStack(alignment: .firstTextBaseline) {
                Text("IVs").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                Spacer()
                if let p = Fmt.ivPercent(r.ivs) { Text(p).font(.figtree(26, .heavy, relativeTo: .title)).monospacedDigit().foregroundStyle(Theme.greenInk) }
            }
            if let i = r.ivs { BarsView(i.atk, i.def, i.hp) } else { Text("IVs not read").paText(.secondary).foregroundStyle(Theme.muted) }
        }
    }

    // MARK: advice

    private func tag(_ text: String) -> some View {
        Text(text).font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }

    @ViewBuilder private func advicePanel(_ e: BoxEntry) -> some View {
        switch model.advice {
        case .none: EmptyView()
        case .computing:
            Panel(tint: .accent, padding: 18, spacing: 8) {
                adviceLabel
                HStack(spacing: 10) { ProgressView(); Text("Working out advice").font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.ink) }
            }
        case .failed(let m):
            Panel(tint: .accent, padding: 18, spacing: 8) {
                adviceLabel
                Text("Advice could not be worked out: \(m)").font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.ink)
            }
        case .ready(let advice):
            let a = advice.entries(for: e.id)
            Panel(tint: .accent, padding: 18, spacing: 8) {
                adviceLabel
                if a.isEmpty { Text("The advisor has nothing for this Pokémon.").font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.ink) }
                ForEach(Array(a.builds.enumerated()), id: \.element.id) { n, b in
                    if n > 0 { Rectangle().fill(accent.ink.opacity(0.18)).frame(height: 1).padding(.vertical, 4) }
                    Text(b.action + (b.needsDynamax ? " (Max needs a Dynamax copy)" : "") + (b.pvp.map { " (\($0))" } ?? "")).font(.figtree(20, .heavy, relativeTo: .title3)).foregroundStyle(Theme.ink)
                    HStack(spacing: 6) {
                        ForEach(b.areas, id: \.self) { tag($0) }
                        if !b.tier.isEmpty { tag("Tier \(b.tier)") }
                    }
                    Text(BuildRow(build: b, showName: false).costLine).font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineSpacing(3)
                }
                ForEach(a.spareFor) { b in Text("A spare copy: a better one is already planned for \(b.targetName).").font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.ink) }
                if let d = a.duplicateOf {
                    Text(a.keep ? "One of \(d.count) \(d.name) in your box. **Keep this one.**" : "One of \(d.count) \(d.name) in your box. **The advisor would transfer this one.**")
                        .font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineSpacing(3)
                }
            }
        }
    }

    private var adviceLabel: some View {
        Text("ADVICE").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(accent.ink).accessibilityAddTraits(.isHeader)
    }

    // MARK: facts

    private func factsPanel(_ e: BoxEntry, mega: MegaForm?) -> some View {
        var facts = [(String, String)]()
        facts.append(("Power-up dust", (mega != nil ? mega?.dust : e.row.dust).map { $0.formatted() } ?? "not known"))
        if case .ready(let advice) = model.advice, let spares = advice.entries(for: e.id).builds.map(\.spares).max(), spares > 0 { facts.append(("Spare copies", spares.formatted())) }
        facts.append(("First seen · last seen", "\(Self.short(mega?.firstSeen ?? e.firstSeen)) · \(Self.short(mega?.lastSeen ?? e.lastSeen))"))
        return Panel(padding: 0, spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { n, f in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(f.0).font(.figtree(15, .regular, relativeTo: .subheadline)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    Text(f.1).font(.figtree(15, .bold, relativeTo: .subheadline)).monospacedDigit().foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .overlay(alignment: .bottom) { if n < facts.count - 1 { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 16) } }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: how it was read

    @ViewBuilder private func notesPanel(_ e: BoxEntry, mega: MegaForm?) -> some View {
        let r = e.row
        if !r.noteFlags.isEmpty || e.megaWhenScanned == true || mega != nil || e.isHandCorrected {
            Panel(padding: 16, spacing: 10) {
                if !r.noteFlags.isEmpty {
                    Text("How it was read").font(.figtree(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    ForEach(r.noteFlags, id: \.self) { Text(FlagInfo.explainNote($0)).paText(.secondary).foregroundStyle(Theme.muted) }
                }
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
            Text(build.action + (build.needsDynamax ? " (Max needs a Dynamax copy)" : "") + (build.pvp.map { " (\($0))" } ?? "")).font(showName ? .callout : .callout.weight(.medium))
            if showName {
                Text("CP \(build.cp)" + (build.ivs.map { ", IVs \($0)" } ?? "") + (build.level.map { ", level \(Fmt.number($0))" } ?? "")).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            Text("\(build.areas.joined(separator: ", ")) · tier \(build.tier)").font(.footnote).foregroundStyle(.secondary)
            Text(costLine).font(.footnote).foregroundStyle(.secondary)
            if build.spares > 0 { Text("\(build.spares) spare \(build.spares == 1 ? "copy" : "copies")").font(.footnote).foregroundStyle(.secondary) }
        }
    }
    var costLine: String {
        let from = build.level.map { "Level \(Fmt.number($0))" } ?? ""
        let to = build.targetLevel.map { $0 > (build.level ?? 0) ? " to \(Fmt.number($0))" : "" } ?? ""
        let cost = build.dust == 0 && build.candy == 0 && build.xl == 0 && build.eliteTMs == 0 ? "nothing to spend" : build.costText
        return (from.isEmpty ? "" : from + to + ": ") + cost
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
