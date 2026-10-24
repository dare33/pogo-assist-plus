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
                        // The "i" sits in the row beside the title (as the prototype does for this row only; the Restore row's "i" is at the trailing edge), outside the Menu's label: the label leaves a gap there and the "i" is drawn over it, so a tap on it never opens the menu.
                        Menu {
                            Picker("Mega Pokémon", selection: $megaDefault) {
                                ForEach(MegaDefault.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            SettingsRowLabel(title: "Mega Pokémon", value: MegaDefault(rawValue: megaDefault)?.title, chevron: true, chevronName: "chevron.up.chevron.down", infoSlot: true)
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityIdentifier("settings-mega")
                        .infoOverlay(title: "Mega Pokémon", value: MegaDefault(rawValue: megaDefault)?.title, chevron: true, chevronName: "chevron.up.chevron.down", isOpen: $megaInfoOpen, label: "About Mega Pokémon", identifier: "settings-mega-info")
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
                        // The Restore "i" is at the trailing edge (the prototype groups an "i" with its title only on the Mega row). The "i" is outside the Button, so it works while the row is disabled.
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
    /// Leaves a gap after the title for the "i" that `infoOverlay` draws over it (outside this label, so it is not part of the control).
    var infoSlot = false
    /// Set only on the overlay's copy of the row: the same layout with every piece hidden and the real "i" in the gap.
    var mirror: InfoMirror?
    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var enabled
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var circle: CGFloat = 24

    private var titleText: some View {
        Text(title).font(.figtree(16, .semibold, relativeTo: .body)).foregroundStyle(ink).multilineTextAlignment(.leading).hiddenIfMirror(mirror != nil)
    }
    private var trailing: some View {
        HStack(spacing: 12) {
            if let value { Text(value).font(.figtree(14, .medium, relativeTo: .subheadline)).foregroundStyle(enabled ? Theme.muted : Theme.faint) }
            if chevron { Image(systemName: chevronName).font(.figtree(14, .bold, relativeTo: .body)).foregroundStyle(enabled ? accent.ink : Theme.faint).accessibilityHidden(true) }
        }
        .hiddenIfMirror(mirror != nil)
    }
    /// The gap after the title: empty in the row, the real "i" in the overlay's copy (so it is exactly where the row left room).
    private func slot(height: CGFloat) -> some View {
        Color.clear.frame(width: InfoOverlay.reserve(circle), height: height)
            .overlay(alignment: .leading) {
                if let mirror {
                    InfoButton(isOpen: mirror.isOpen, size: 24, label: mirror.label, identifier: mirror.identifier)
                        .frame(width: InfoOverlay.slot, height: InfoOverlay.slot)
                        .padding(.leading, InfoOverlay.spacing(circle))
                }
            }
    }

    var body: some View {
        Group {
            if infoSlot && typeSize.isAccessibilitySize {
                // Large text: the title and the "i" on the first line, the value and chevron on the second.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) { titleText; slot(height: InfoOverlay.slot) }
                    HStack(spacing: 0) { Spacer(minLength: 0); trailing }
                }
            } else {
                HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        titleText
                        if infoSlot { slot(height: 24) }
                    }
                    Spacer(minLength: 8)
                    trailing
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 52)
        .modifier(RowShape(solid: mirror == nil))
    }

    private var ink: Color { !enabled ? Theme.faint : (action ? accent.ink : Theme.ink) }
}

struct InfoMirror {
    var isOpen: Binding<Bool>
    var label: String
    var identifier: String
}

private extension View {
    @ViewBuilder func hiddenIfMirror(_ on: Bool) -> some View {
        if on { hidden().accessibilityHidden(true) } else { self }
    }
}

/// The "i" over the gap `SettingsRowLabel(infoSlot:)` leaves after the title.
/// The overlay is a second copy of the whole row (title, value and chevron hidden, the real "i" in the gap) rather than a hidden title alone:
/// the title wraps against the value and chevron and the row's padding, so only a copy with every one of them in the same layout is
/// certain to break on the same words and to put the "i" 8 pt after the visible title at any text size.
private struct InfoOverlay: ViewModifier {
    /// The "i" button's hit frame (44 pt; its circle is 24 at the default text size).
    static let slot: CGFloat = 44
    /// The circle is `circle` pt (to at most 44) in the middle of the frame, so it sits (slot - circle) / 2 in from the frame's edge.
    /// The title-to-circle gap is 8, so the frame starts `8 - inset` after the title (negative while the circle is small); the label reserves frame plus that.
    static func inset(_ circle: CGFloat) -> CGFloat { (slot - min(circle, slot)) / 2 }
    static func spacing(_ circle: CGFloat) -> CGFloat { 8 - inset(circle) }
    static func reserve(_ circle: CGFloat) -> CGFloat { slot + spacing(circle) }
    let row: SettingsRowLabel

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) { row }
    }
}

private extension View {
    func infoOverlay(title: String, value: String? = nil, chevron: Bool = false, chevronName: String = "chevron.right", action: Bool = false,
                     isOpen: Binding<Bool>, label: String, identifier: String) -> some View {
        modifier(InfoOverlay(row: SettingsRowLabel(title: title, value: value, chevron: chevron, chevronName: chevronName, action: action, infoSlot: true,
                                                   mirror: InfoMirror(isOpen: isOpen, label: label, identifier: identifier))))
    }
}

/// The row's whole area takes the tap, except in the overlay's copy, where only the "i" does.
private struct RowShape: ViewModifier {
    let solid: Bool
    func body(content: Content) -> some View {
        if solid { content.contentShape(Rectangle()) } else { content }
    }
}
