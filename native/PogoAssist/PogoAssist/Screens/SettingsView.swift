import SwiftUI
import PogoBox

struct SettingsView: View {
    @State private var shareURLs: [URL] = []
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmPrevious = false
    @State private var restoring: BoxSnapshot.Header?
    @State private var renaming = false
    @State private var newName = ""
    @State private var renameProblem: String?

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

    private func scanRow(_ scan: BoxStore.Summary) -> some View {
        let kind: String = scan.kind == .full ? "Full scan" : "Add and update"
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.date(scan.scanDate)).font(.callout)
                Text("\(kind), \(scan.rows) Pokémon read").font(.footnote).foregroundStyle(.secondary)
                if let sent = scan.reportSentAt { Text("Sent \(Fmt.day(sent))").font(.footnote).foregroundStyle(.secondary) }
                if let again = scan.lastReread { Text("Read again \(Fmt.date(again))").font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
            Menu {
                Button { model.rereadScan(scan) } label: { Label("Read again with the latest rules", systemImage: "arrow.triangle.2.circlepath") }
                if model.reportsEnabled { Button { model.reportTarget = .saved(scan.id) } label: { Label("Make scans better", systemImage: "paperplane") } }
                Button { shareURLs = model.shareFiles(for: scan) } label: { Label("Share scan files", systemImage: "square.and.arrow.up") }
            } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Scan actions")
        }
    }

    @ViewBuilder private func historyRow(_ h: BoxSnapshot.Header) -> some View {
        let isCurrent: Bool = h.seq == model.history.first?.seq
        VStack(alignment: .leading, spacing: 2) {
            Text("Version \(h.seq): \(h.note)").font(.callout)
            Text(Fmt.date(h.createdAt)).font(.footnote).foregroundStyle(.secondary)
        }
        .swipeActions {
            if !isCurrent && !model.boxNeedsNewerApp { Button("Restore") { restoring = h }.tint(.blue) }
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
                    Button("Rename account") { newName = model.account ?? ""; renaming = true }.disabled(model.account == nil)
                } footer: { if let p = renameProblem { Text(p).foregroundStyle(.red) } }
                Section {
                    Button("Restore previous box") { confirmPrevious = true }.disabled(model.previous == nil || model.boxNeedsNewerApp)
                } header: { Text("Box for \(model.account ?? "this account")") } footer: {
                    Text(previousFooter)
                }
                Section {
                    if model.history.isEmpty { Text("No saved versions yet.").foregroundStyle(.secondary) }
                    ForEach(model.history, id: \.seq) { h in historyRow(h) }
                } header: { Text("History") } footer: { Text("Every scan and every correction is kept as a version. Swipe a version to restore it; the current box stays in the history.") }
                Section {
                    if model.scans.isEmpty { Text("No saved scans yet.").foregroundStyle(.secondary) }
                    ForEach(model.scans, id: \.id) { scan in scanRow(scan) }
                } header: { Text("Scans") } footer: { Text("Share a scan's replay log and result to send them for diagnosis.") }
                Section("About") {
                    Text("Reader mode is set to accurate. The mode picker is in Diagnostics.").font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            // Presented from here, not from the root: Settings is itself a sheet, and the root cannot
            // put a second sheet over it.
            .sheet(item: $model.reportTarget) { MakeScansBetterSheet(target: $0).environmentObject(model) }
            .sheet(isPresented: Binding(get: { !shareURLs.isEmpty }, set: { if !$0 { shareURLs = [] } })) {
                ShareSheet(urls: shareURLs).presentationDetents([.medium, .large])
            }
            .alert("Rename account", isPresented: $renaming) {
                TextField("Trainer name", text: $newName).accountNameField()
                Button("Rename") {
                    let old = model.account ?? ""
                    Task { renameProblem = await model.renameAccount(old, to: newName) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The box, its history and its saved scans move to the new name.") }
            .onAppear { model.loadScans(); renameProblem = nil }
            .confirmationDialog("Restore the previous box?", isPresented: $confirmPrevious, titleVisibility: .visible) {
                Button("Restore previous box") { Task { await model.restorePrevious() } }
            } message: { Text("The box as it is now stays in the history, so you can come back to it.") }
            .confirmationDialog("Restore version \(restoring?.seq ?? 0)?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible) {
                Button("Restore this version") { if let r = restoring { Task { await model.restore(seq: r.seq) } } }
            } message: { Text("The box as it is now stays in the history.") }
        }
    }
}
