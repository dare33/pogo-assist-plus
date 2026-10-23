import SwiftUI
import PogoBox

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmPrevious = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var renameProblem: String?
    @AppStorage(PrefKey.megaDefault) private var megaDefault = MegaDefault.normal.rawValue

    private func accountLabel(_ name: String) -> some View {
        let selected: Bool = name == model.account
        return HStack {
            Text(name).foregroundStyle(Color.primary)
            Spacer()
            if selected { Image(systemName: "checkmark") }
        }
    }

    private var previousFooter: String {
        if model.boxNeedsNewerApp { return "This box needs a newer version of the app, so it cannot be restored or changed here. Update the app." }
        guard let p = model.previous else { return "There is no earlier box to go back to yet." }
        return "Goes back to version \(p.seq), \(p.note.lowercased()), \(Fmt.date(p.createdAt)). The box as it is now stays in the history."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Appearance") { AppearanceView() }.accessibilityIdentifier("settings-appearance")
                    NavigationLink { SetupChecklistView() } label: {
                        HStack {
                            Text("Get ready to scan")
                            Spacer()
                            Text(model.setup.isDone ? "Done" : "\(model.setup.doneCount) of \(SetupProgress.count) done").foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings-get-ready")
                }
                Section {
                    Picker("Mega Pokémon", selection: $megaDefault) {
                        ForEach(MegaDefault.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .accessibilityIdentifier("settings-mega")
                } footer: { Text("Which form a Pokémon's page shows first when it has a Mega form. You can switch on the page.") }
                Section("Accounts") {
                    ForEach(model.accounts, id: \.self) { name in
                        Button { model.select(name) } label: { accountLabel(name) }
                    }
                }
                Section {
                    Button("Rename account") { newName = model.account ?? ""; renaming = true }.disabled(model.account == nil || model.isReviewing)
                } footer: {
                    if let p = renameProblem { Text(p).foregroundStyle(.red) }
                    else if model.isReviewing { Text("A scan is open. Save or discard it before renaming the account.") }
                }
                Section {
                    Button("Restore previous box") { confirmPrevious = true }.disabled(model.previous == nil || model.boxNeedsNewerApp)
                    NavigationLink("History and scans") { HistoryScansView() }.accessibilityIdentifier("settings-history-row")
                } header: { Text("Box for \(model.account ?? "this account")") } footer: {
                    Text(previousFooter)
                }
                Section("About") {
                    Text("Reader mode is set to accurate. The mode picker is in Diagnostics.").font(.footnote)
                    // Trademark notice, needed by Apple's review and fair to the owners of the names: the app reads a player's own screen and is nobody's partner.
                    Text("Pogo Assist+ is not affiliated with, endorsed by or connected to Niantic, Nintendo or The Pokémon Company. Pokémon and Pokémon GO are trademarks of their owners.").font(.footnote)
                        .accessibilityIdentifier("about-affiliation")
                    Text("League ratings and recommended moves come from PvPoke (pvpoke.com), used under its MIT licence.").font(.footnote)
                        .accessibilityIdentifier("about-pvpoke")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
        }
    }
}
