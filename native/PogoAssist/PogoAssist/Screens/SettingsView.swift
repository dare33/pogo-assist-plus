import SwiftUI
import PogoBox

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmPrevious = false
    @State private var restoring: BoxSnapshot.Header?

    private func accountLabel(_ name: String) -> some View {
        let selected: Bool = name == model.account
        return HStack {
            Text(name).foregroundStyle(Color.primary)
            Spacer()
            if selected { Image(systemName: "checkmark") }
        }
    }

    private var previousFooter: String {
        guard let p = model.previous else { return "There is no earlier box to go back to yet." }
        return "Goes back to version \(p.seq), \(p.note.lowercased()), \(Fmt.date(p.createdAt)). The box as it is now stays in the history."
    }

    @ViewBuilder private func historyRow(_ h: BoxSnapshot.Header) -> some View {
        let isCurrent: Bool = h.seq == model.history.first?.seq
        VStack(alignment: .leading, spacing: 2) {
            Text("Version \(h.seq): \(h.note)").font(.callout)
            Text(Fmt.date(h.createdAt)).font(.footnote).foregroundStyle(.secondary)
        }
        .swipeActions {
            if !isCurrent { Button("Restore") { restoring = h }.tint(.blue) }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Accounts") {
                    ForEach(model.accounts, id: \.self) { name in
                        Button { model.select(name) } label: { accountLabel(name) }
                    }
                }
                Section {
                    Button("Restore previous box") { confirmPrevious = true }.disabled(model.previous == nil)
                } header: { Text("Box for \(model.account ?? "this account")") } footer: {
                    Text(previousFooter)
                }
                Section {
                    if model.history.isEmpty { Text("No saved versions yet.").foregroundStyle(.secondary) }
                    ForEach(model.history, id: \.seq) { h in historyRow(h) }
                } header: { Text("History") } footer: { Text("Every scan and every correction is kept as a version. Swipe a version to restore it; the current box stays in the history.") }
                Section("About") {
                    Text("Reader mode is set to accurate. The mode picker is in Diagnostics.").font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Restore the previous box?", isPresented: $confirmPrevious, titleVisibility: .visible) {
                Button("Restore previous box") { Task { await model.restorePrevious() } }
            } message: { Text("The box as it is now stays in the history, so you can come back to it.") }
            .confirmationDialog("Restore version \(restoring?.seq ?? 0)?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible) {
                Button("Restore this version") { if let r = restoring { Task { await model.restore(seq: r.seq) } } }
            } message: { Text("The box as it is now stays in the history.") }
        }
    }
}
