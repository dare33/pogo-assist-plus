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
                Text(unsure.kind == .partialRead
                     ? "Only part of the CP was read, so this may be a Pokémon already in your box."
                     : "It could be more than one Pokémon already in your box.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(unsure.candidates, id: \.self) { id in
                if let e = saved[id] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("In your box").font(.caption).foregroundStyle(.secondary)
                        Text(Fmt.candidate(e.row)).font(.callout)
                        answer("It is this one", selected: choice == .existing(id)) { model.resolve(unsure.scanned, .existing(id)) }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack {
                answer("It is new", selected: choice == .new) { model.resolve(unsure.scanned, .new) }
                answer("Leave it out of the box", selected: choice == .leaveOut) { model.resolve(unsure.scanned, .leaveOut) }
            }
        }
        .padding(.vertical, 4)
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
