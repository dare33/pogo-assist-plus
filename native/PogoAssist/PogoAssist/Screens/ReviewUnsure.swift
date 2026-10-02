import SwiftUI
import PogoBox

/// One Pokémon the merge would not guess about: what was read, the saved candidates with their values, and the answers.
struct UnsureCard: View {
    @EnvironmentObject var model: AppModel
    let unsure: BoxMerge.Unsure
    let row: ScanRow
    let saved: [String: BoxEntry]

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
            ForEach(unsure.kind == .extraTwin ? [] : unsure.candidates, id: \.self) { id in
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
            if unsure.kind == .extraTwin {
                HStack {
                    answer("Add a second one", selected: choice == .new) { model.resolve(unsure.scanned, .new) }
                    answer("Leave it out", selected: choice == .leaveOut) { model.resolve(unsure.scanned, .leaveOut) }
                }
            } else {
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
        case .keepsIVsAndFlags: return "The scan read other IVs for the same CP and HP. IVs never change, so one read is wrong: choosing this keeps the saved IVs and marks it to check."
        }
    }

    private var explanation: String {
        switch unsure.kind {
        case .partialRead: return "Only part of the CP was read, so this may be a Pokémon already in your box."
        case .misreadSaved: return "A Pokémon in your box was read badly earlier (no IVs). This may be the same Pokémon read properly. The line under each choice says what it does."
        case .extraTwin: return "The scan saw two identical Pokémon in a row and the box has one. Add a second?"
        case .ambiguous: return unsure.candidates.count == 1 ? "It could be this Pokémon already in your box." : "It could be more than one Pokémon already in your box."
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
