import SwiftUI
import PogoBox
import PogoReader

struct PokemonDetailView: View {
    @EnvironmentObject var model: AppModel
    let id: String
    @State private var fixing = false

    var body: some View {
        if let e = model.entry(id) {
            let r = e.row
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.title2.bold())
                        Text(verbatim: "CP \(r.cp)").font(.title3).monospacedDigit()
                    }
                }
                Section("Stats") {
                    line("HP", r.hp.map(String.init) ?? "not read")
                    line("Level", Fmt.level(r) ?? "not known")
                    line("IVs", r.ivs.map { "\(Fmt.ivs($0)) (\(Fmt.ivPercent($0) ?? ""))" } ?? "not read")
                    line("Power-up dust", r.dust.map(String.init) ?? "not known")
                    line("First seen", Fmt.day(e.firstSeen))
                    line("Last seen", Fmt.day(e.lastSeen))
                }
                if !r.flags.isEmpty {
                    Section("To check in the game") {
                        ForEach(r.flags, id: \.self) { Text(FlagInfo.explain($0)).font(.callout) }
                        Button("These values are right") { Task { await model.markChecked(id) } }
                    }
                }
                if e.isHandCorrected {
                    Section { Label("Corrected by hand: \(corrected(e)). A later scan will not undo it unless the Pokémon has changed.", systemImage: "pencil").font(.footnote).foregroundStyle(.secondary) }
                }
                adviceSection(e)
                Section { Button { fixing = true } label: { Label("Fix a value", systemImage: "pencil") } }
            }
            .navigationTitle(r.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $fixing) { FixValueView(entry: e).environmentObject(model) }
        } else {
            Text("This Pokémon is no longer in the box.").foregroundStyle(.secondary)
        }
    }

    private func corrected(_ e: BoxEntry) -> String {
        var parts = [String]()
        if e.corrections.species != nil { parts.append("name") }
        if e.corrections.cp != nil { parts.append("CP") }
        if e.corrections.hp != nil { parts.append("HP") }
        if e.corrections.ivs != nil { parts.append("IVs") }
        return parts.joined(separator: ", ")
    }

    private func line(_ t: String, _ v: String) -> some View {
        HStack { Text(t); Spacer(); Text(v).foregroundStyle(.secondary).monospacedDigit() }
    }

    @ViewBuilder private func adviceSection(_ e: BoxEntry) -> some View {
        switch model.advice {
        case .none: EmptyView()
        case .computing: Section("Advice") { HStack { ProgressView(); Text("Working out advice") } }
        case .failed(let m): Section("Advice") { Text("Advice could not be worked out: \(m)").font(.footnote).foregroundStyle(.secondary) }
        case .ready(let advice):
            let a = advice.entries(for: e.id)
            Section("Advice") {
                if a.isEmpty { Text("The advisor has nothing for this Pokémon.").foregroundStyle(.secondary) }
                ForEach(a.builds) { BuildRow(build: $0, showName: false) }
                ForEach(a.spareFor) { b in Text("A spare copy: a better one is already planned for \(b.targetName).").font(.footnote).foregroundStyle(.secondary) }
                if let d = a.duplicateOf {
                    Text(a.keep ? "One of \(d.count) \(d.name) in your box. Keep this one." : "One of \(d.count) \(d.name) in your box. The advisor would transfer this one.")
                        .font(.callout)
                }
            }
        }
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
    private var costLine: String {
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
        name = r.title; cp = String(r.cp); hp = r.hp.map(String.init) ?? ""
        atk = r.ivs.map { String($0.atk) } ?? ""; def = r.ivs.map { String($0.def) } ?? ""; sta = r.ivs.map { String($0.hp) } ?? ""
    }

    private func save() {
        var edit = BoxMerge.Edit()
        func int(_ s: String) -> Int? { Int(s.trimmingCharacters(in: .whitespaces)) }
        if cp.trimmingCharacters(in: .whitespaces) != String(entry.row.cp) {
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
