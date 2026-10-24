import SwiftUI
import PogoBox

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmPrevious = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var renameProblem: String?
    @State private var megaInfoOpen = false
    @State private var restoreInfoOpen = false
    @AppStorage(PrefKey.megaDefault) private var megaDefault = MegaDefault.normal.rawValue

    @Environment(\.accent) private var accent

    private func accountLabel(_ name: String) -> some View {
        let selected: Bool = name == model.account
        return HStack(spacing: 12) {
            Text(name).font(.figtree(16, .semibold, relativeTo: .body)).foregroundStyle(Theme.ink)
            Spacer()
            if selected { Image(systemName: "checkmark").font(.figtree(16, .heavy, relativeTo: .body)).foregroundStyle(accent.ink).accessibilityHidden(true) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    // MARK: pieces (the same card, header and inset-row shapes as Appearance and the setup checklist)

    private func panelTitle(_ text: String) -> some View {
        Text(text).font(.figtree(17, .heavy, relativeTo: .headline)).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
    }

    private func note(_ text: String, tint: Color = Theme.muted) -> some View {
        Text(text).font(.figtree(13, .regular, relativeTo: .footnote)).foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var separator: some View { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 16) }

    private func rowLabel(_ title: String, value: String? = nil, chevron showsChevron: Bool = false, action: Bool = false) -> some View {
        SettingsRowLabel(title: title, value: value, chevron: showsChevron, action: action)
    }

    private var previousFooter: String {
        if model.boxNeedsNewerApp { return "This box needs a newer version of the app, so it cannot be restored or changed here. Update the app." }
        guard let p = model.previous else { return "There is no earlier box to go back to yet." }
        return "Goes back to version \(p.seq), \(p.note.lowercased()), \(Fmt.date(p.createdAt)). The box as it is now stays in the history."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.panelGap) {
                    Panel(padding: 0, spacing: 0) {
                        NavigationLink { AppearanceView() } label: { rowLabel("Appearance", chevron: true) }
                            .buttonStyle(PressStyle()).accessibilityIdentifier("settings-appearance")
                        separator
                        NavigationLink { SetupChecklistView() } label: {
                            rowLabel("Get ready to scan", value: model.setup.isDone ? "Done" : "\(model.setup.doneCount) of \(SetupProgress.count) done", chevron: true)
                        }
                        .buttonStyle(PressStyle()).accessibilityIdentifier("settings-get-ready")
                    }
                    Panel(padding: 0, spacing: 0) {
                        // The whole row is the menu's label, so a tap anywhere on it opens the menu; the identifier sits on that one element, whose label starts "Mega Pokémon".
                        // The "i" sits beside the Menu, not inside its label, so a tap on it never opens the menu.
                        HStack(spacing: 0) {
                            Menu {
                                Picker("Mega Pokémon", selection: $megaDefault) {
                                    ForEach(MegaDefault.allCases) { Text($0.title).tag($0.rawValue) }
                                }
                                .pickerStyle(.inline)
                            } label: {
                                SettingsRowLabel(title: "Mega Pokémon", value: MegaDefault(rawValue: megaDefault)?.title, chevron: true, chevronName: "chevron.up.chevron.down")
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityIdentifier("settings-mega")
                            InfoButton(isOpen: $megaInfoOpen, size: 24, label: "About Mega Pokémon", identifier: "settings-mega-info")
                                .padding(.trailing, 4)
                        }
                        if megaInfoOpen {
                            ExplainerCard(text: "Which form a Pokémon's page shows first when it has a Mega form. You can switch on the page.", identifier: "settings-mega-explainer")
                                .padding(.horizontal, 16).padding(.bottom, 12)
                        }
                    }
                    Panel(padding: 0, spacing: 0) {
                        panelTitle("Accounts")
                        ForEach(Array(model.accounts.enumerated()), id: \.element) { i, name in
                            Button { model.select(name) } label: { accountLabel(name) }.buttonStyle(PressStyle())
                                .accessibilityAddTraits(name == model.account ? .isSelected : [])
                            if i < model.accounts.count - 1 { separator }
                        }
                    }
                    Panel(padding: 0, spacing: 0) {
                        Button { newName = model.account ?? ""; renaming = true } label: { rowLabel("Rename account", action: true) }
                            .buttonStyle(PressStyle()).disabled(model.account == nil || model.isReviewing)
                        if let p = renameProblem { note(p, tint: Theme.red) }
                        else if model.isReviewing { note("A scan is open. Save or discard it before renaming the account.") }
                    }
                    Panel(padding: 0, spacing: 0) {
                        panelTitle("Box for \(model.account ?? "this account")")
                        HStack(spacing: 0) {
                            Button { confirmPrevious = true } label: { rowLabel("Restore previous box", action: true) }
                                .buttonStyle(PressStyle()).disabled(model.previous == nil || model.boxNeedsNewerApp)
                            InfoButton(isOpen: $restoreInfoOpen, size: 24, label: "About restoring", identifier: "settings-restore-info")
                                .padding(.trailing, 4)
                        }
                        if restoreInfoOpen {
                            ExplainerCard(text: previousFooter, identifier: "settings-restore-explainer")
                                .padding(.horizontal, 16).padding(.bottom, 12)
                        }
                        separator
                        NavigationLink { HistoryScansView() } label: { rowLabel("History and scans", chevron: true) }
                            .buttonStyle(PressStyle()).accessibilityIdentifier("settings-history-row")
                    }
                    Panel(padding: 0, spacing: 0) {
                        panelTitle("About")
                        note("Reader mode is set to accurate. The mode picker is in Diagnostics.")
                        // Trademark notice, needed by Apple's review and fair to the owners of the names: the app reads a player's own screen and is nobody's partner.
                        note("Pogo Assist+ is not affiliated with, endorsed by or connected to Niantic, Nintendo or The Pokémon Company. Pokémon and Pokémon GO are trademarks of their owners.")
                            .accessibilityIdentifier("about-affiliation")
                        note("League ratings and recommended moves come from PvPoke (pvpoke.com), used under its MIT licence.")
                            .accessibilityIdentifier("about-pvpoke")
                    }
                }
                .padding(.horizontal, Theme.Space.screen).padding(.top, 6).padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
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
            .onAppear { renameProblem = nil }
            .confirmationDialog("Restore the previous box?", isPresented: $confirmPrevious, titleVisibility: .visible) {
                Button("Restore previous box") { Task { await model.restorePrevious() } }
            } message: { Text("The box as it is now stays in the history, so you can come back to it.") }
        }
    }
}

/// A row's label. It reads isEnabled itself because the environment value is set on the Button, below the screen that builds the row.
private struct SettingsRowLabel: View {
    let title: String
    var value: String?
    var chevron = false
    var chevronName = "chevron.right"
    /// An action row (Rename, Restore) is drawn in the accent ink; a navigation row in the plain ink.
    var action = false
    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.figtree(16, .semibold, relativeTo: .body)).foregroundStyle(ink).multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if let value { Text(value).font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(enabled ? Theme.muted : Theme.faint) }
            if chevron { Image(systemName: chevronName).font(.figtree(14, .bold, relativeTo: .body)).foregroundStyle(enabled ? accent.ink : Theme.faint).accessibilityHidden(true) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var ink: Color { !enabled ? Theme.faint : (action ? accent.ink : Theme.ink) }
}
