import SwiftUI
import PogoBox

/// One Pokémon the merge would not guess about: what was read, the saved candidates with their values, and the answers.
struct UnsureCard: View {
    @EnvironmentObject var model: AppModel
    let unsure: BoxMerge.Unsure
    let row: ScanRow
    let saved: [String: BoxEntry]

    @State private var showAll = false
    /// A row that cannot be identified by its CP has its same-species, same-HP entries ranked first (`Plan.rankedCounts`): the card shows the best three, with "Show all (N)" for the rest
    /// of the list (the other ranked entries, then the family). Any other question shows its whole list.
    private var rankedCount: Int { if case .review(let r) = model.flow { return r.plan.rankedCounts[unsure.scanned] ?? 0 } else { return 0 } }
    private var shownCandidates: [String] {
        let all = unsure.kind == .extraTwin ? Array(unsure.candidates.dropFirst()) : unsure.candidates
        guard rankedCount > 0, !showAll else { return all }
        return Array(all.prefix(min(3, rankedCount)))
    }
    private var choice: BoxMerge.Resolution? {
        if case .review(let r) = model.flow { return r.resolutions[unsure.scanned] }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Read in the scan").font(.caption).foregroundStyle(.secondary)
                Text(readLine).font(.callout.weight(.medium))
                Text(explanation).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(shownCandidates, id: \.self) { id in
                if unsure.kind == .megaPair {
                    if let e = saved[id] {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(id == unsure.candidates.first ? "Saved as the normal form" : "Saved as Mega").font(.caption).foregroundStyle(.secondary)
                            Text(Fmt.candidate(e.row)).font(.callout)
                        }
                        .padding(10)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    }
                } else

                if let e = saved[id] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("In your box").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.candidate(e.row)).font(.callout)
                        if let text = effectText(for: e) { Text(text).font(.footnote).foregroundStyle(.secondary) }
                        answer("It is this one", selected: choice == .existing(id)) { model.resolve(unsure.scanned, .existing(id)) }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if unsure.kind == .megaPair {
                HStack {
                    answer("Join them", selected: choice == .existing(unsure.candidates.first ?? "")) { if let id = unsure.candidates.first { model.resolve(unsure.scanned, .existing(id)) } }
                    answer("Keep both", selected: choice == .leaveOut) { model.resolve(unsure.scanned, .leaveOut) }
                }
            } else if unsure.kind == .extraTwin {
                HStack {
                    answer("Add a second one", selected: choice == .new) { model.resolve(unsure.scanned, .new) }
                    answer("Leave it out", selected: choice == .leaveOut) { model.resolve(unsure.scanned, .leaveOut) }
                }
            } else {
            if rankedCount > 0, !showAll, unsure.candidates.count > shownCandidates.count {
                Button("Show all (\(unsure.candidates.count))") { showAll = true }.font(.footnote)
            }
            HStack {
                answer("It is new", selected: choice == .new) { model.resolve(unsure.scanned, .new) }
                answer("Leave it out of the box", selected: choice == .leaveOut) { model.resolve(unsure.scanned, .leaveOut) }
            }
            }
        }
        .padding(.vertical, 4)
    }

    /// What "It is this one" will do for this candidate: the same `BoxMerge.effect` that `apply` follows, so the card cannot disagree with the result.
    private func effectText(for e: BoxEntry) -> String? {
        guard case .review(let r) = model.flow else { return nil }
        switch BoxMerge.effect(r.plan, unsure, candidate: e, gameMaster: try? GameMaster.bundled()) {
        case .seenOnly: return "Choosing this only marks it as seen. Nothing is changed."
        case .seenAsMega: return "Choosing this marks it as seen and as Mega evolved when scanned. The Mega values are not copied."
        case .replacesValues: return "Choosing this updates the saved Pokémon with the values read in the scan."
        case .replacesIVs: return "The saved IVs were not an exact read, so choosing this replaces them with the IVs read now."
        case .joinsMegaPair: return "Joining keeps this entry exactly as saved (values and hand corrections unchanged), marks it Mega when scanned if the scan read the Mega form, and removes the other entry with whatever was saved for it."
        case .keepsIVsAndFlags: return "The scan read other IVs for the same CP and HP. IVs never change, so one read is wrong: choosing this keeps the saved IVs and marks it to check."
        }
    }

    private var explanation: String {
        // "Same IVs" is only true when the saved entry's current IVs equal the read ones; a match through a hand correction's old IVs says so.
        var ivsPhrase = "Same IVs as this saved one."
        if unsure.candidates.count == 1, let e = saved[unsure.candidates[0]], let ivs = row.ivs, e.row.ivs != ivs, e.corrections.ivs?.was == ivs {
            ivsPhrase = "These IVs match this saved one's IVs from before you corrected them."
        }
        switch unsure.kind {
        case .partialRead: return "Only part of the CP was read, so this may be a Pokémon already in your box."
        case .misreadSaved: return "A Pokémon in your box was read badly earlier (no IVs). This may be the same Pokémon read properly. The line under each choice says what it does."
        case .extraTwin: return unsure.candidates.count > 1 ? "The scan saw two identical Pokémon in a row and the box has one like it. A saved Pokémon with the same CP and HP but other IVs is shown below: it may be this one, read with the wrong IVs. Otherwise add a second?" : "The scan saw two identical Pokémon in a row and the box has one. Add a second?"
        case .poweredUp: return "\(ivsPhrase) It may be that Pokémon powered up, or a different one with the same IVs."
        case .evolved: return "\(ivsPhrase) It may be that Pokémon evolved, or a different one with the same IVs."
        case .megaPair:
            let names = unsure.candidates.compactMap { saved[$0] }
            if names.count == 2 { return "Your \(names[0].row.name) is saved twice, once as a Mega (CP \(names[1].row.cp)) and once not (CP \(names[0].row.cp)), with the same IVs and HP. Join them? Joining keeps the normal entry exactly as saved (its values and hand corrections do not change) and removes the Mega one with whatever was saved for it. Keeping both changes nothing." }
            return "This Pokémon is saved twice, once as a Mega and once not. Join them?"
        case .megaToBase: return "This is the normal form; the saved one was scanned in its Mega form. \(ivsPhrase) It may be that same Pokémon, or a different one with the same IVs."
        case .ambiguous:
            if unsure.candidates.count == 1, let e = saved[unsure.candidates[0]], let ivs = row.ivs, e.row.cp < row.cp {
                if e.row.ivs == ivs || e.corrections.ivs?.was == ivs { return "\(ivsPhrase) It may be that Pokémon powered up, or a different one with the same IVs." }
            }
            return unsure.candidates.count == 1 ? "It could be this Pokémon already in your box." : "It could be more than one Pokémon already in your box."
        }
    }

    private var readLine: String {
        var parts = [row.title, "CP \(row.cp)", "HP \(row.hp.map(String.init) ?? "not read")", "IVs \(Fmt.ivs(row.ivs))"]
        if row.flags.contains(where: { $0.hasPrefix("no-level-fits") }) { parts.append("no level fits") }
        return parts.joined(separator: ", ")
    }

    /// Drawn by hand with the plain style: bordered buttons inside a List row are tappable as a whole row and crashed
    /// SwiftUI's accessibility pass in the simulator.
    private func answer(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark") }
                Text(title).multilineTextAlignment(.center).font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.horizontal, 8)
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .background(selected ? Color.accentColor : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
