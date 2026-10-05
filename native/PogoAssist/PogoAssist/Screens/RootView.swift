import SwiftUI

struct RootView: View {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    @State private var tab: AppTab = .box
    @State private var scanOpen = false
    @State private var barHidden = false
    /// A scan that has just ended opened the Scan screen's Done state; the Scan screen closes again when its review ends.
    @State private var doneRun = false

    /// The scan screen is pushed on the current tab's stack only, so it is built once.
    private func scanBinding(for t: AppTab) -> Binding<Bool> {
        Binding(get: { scanOpen && tab == t }, set: { if !$0 { scanOpen = false } })
    }

    var body: some View {
        // The shell: the current tab's screen full-bleed on the background, the floating tab bar over it. Both
        // tabs stay alive (their scroll position and pushed screens survive a switch); the other is hidden.
        ZStack {
            Theme.bg.ignoresSafeArea()
            NavigationStack { BoxView().navigationDestination(isPresented: scanBinding(for: .box)) { ScanView().hidesTabBar() } }
                .opacity(tab == .box ? 1 : 0).allowsHitTesting(tab == .box).accessibilityHidden(tab != .box)
            NavigationStack { NextView().navigationDestination(isPresented: scanBinding(for: .next)) { ScanView().hidesTabBar() } }
                .opacity(tab == .next ? 1 : 0).allowsHitTesting(tab == .next).accessibilityHidden(tab != .next)
        }
        .onPreferenceChange(HidesTabBarKey.self) { barHidden = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !barHidden { Color.clear.frame(height: FloatingTabBar.clearance) }
        }
        .overlay(alignment: .bottom) {
            if !barHidden { FloatingTabBar(selection: $tab, scanDisabled: model.boxProblem != nil) { scanOpen = true } }
        }
        .overlay(alignment: .bottom) {
            if model.scanDonePending && !scanOpen { ScanDonePill { scanOpen = true }.padding(.bottom, FloatingTabBar.clearance) }
        }
        .themeRoot()
        .environmentObject(model)
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .settings: SettingsView().environmentObject(model)
            case .diagnostics:
                ContentView(onLoadSample: { partial in
                    do {
                        try SampleScan.install(partialRead: partial)
                        if partial { model.scanKind = .partial }
                        model.sheet = nil
                    } catch { model.message = "The sample scan could not be loaded: \(error.localizedDescription)" }
                }, showsDone: true)
            }
        }
        .background { Color.clear.fullScreenCover(isPresented: .constant(model.accounts.isEmpty)) { WelcomeView().environmentObject(model) } }
        .background { Color.clear.fullScreenCover(isPresented: Binding(get: { model.reviewCoverShown }, set: { _ in })) { ReviewView().environmentObject(model) } }
        .sheet(isPresented: Binding(get: { !model.shareURLs.isEmpty }, set: { if !$0 { model.shareURLs = [] } })) {
            ShareSheet(urls: model.shareURLs).presentationDetents([.medium, .large])
        }
        .alert("Pogo Assist+", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .overlay { if let work = model.busy { BusyOverlay(text: work) } }
        .onAppear {
            model.refreshBroadcast(); model.startTimer()
            #if DEBUG
            if let variant = UserDefaults.standard.string(forKey: "uitest-seed-review") { model.seedReview(variant: variant) }
            #endif
        }
        // A scan has ended: bring the person to its Done screen (the Scan screen), and back out of it when the review is over.
        // "Re-scan N" in the Box: open the Scan screen; closing it ends the suggestion.
        .onChange(of: model.rescanCount) { _, n in if n != nil { scanOpen = true } }
        .onChange(of: scanOpen) { _, open in if !open { model.rescanCount = nil } }
        .onChange(of: model.scanDonePending) { _, pending in if pending { doneRun = true; scanOpen = true } }
        .onChange(of: model.isReviewing) { _, reviewing in if !reviewing && doneRun { doneRun = false; scanOpen = false } }
        .onChange(of: phase) { _, p in
            if p == .active { model.refreshBroadcast(); model.startTimer() } else { model.stopTimer() }
        }
    }
}

/// Asks for the first account's name. Nothing is seeded: an account is a name the person makes up.
struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Pogo Assist+ keeps one box of Pokémon for each Pokémon GO account you scan. Give the first one a name, such as your trainer name.")
                }
                Section("Account name") {
                    TextField("Trainer name", text: $name)
                        .accountNameField()
                        .submitLabel(.done)
                        .onSubmit(create)
                }
                Section {
                    Button("Create account", action: create).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Welcome")
        }
    }
    private func create() { model.createAccount(name) }
}

extension View {
    /// An account name is a name the person chose: no autocorrection, no spell checking, no automatic capitals.
    func accountNameField() -> some View {
        self.autocorrectionDisabled(true).textInputAutocapitalization(.never).textContentType(.none)
    }
}

struct BusyOverlay: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) { ProgressView(); Text(text).font(.callout) }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// The account switcher in the navigation bar, with "New account".
struct AccountMenu: View {
    /// The UI v1 header look: monogram, name and chevron on a surface pill (see `AccountPill`).
    var pill = false
    /// Display only (no menu, no chevron): a finished scan waiting for review belongs to the account named, so the account cannot be switched under it.
    var locked = false
    @EnvironmentObject var model: AppModel
    @State private var asking = false
    @State private var newName = ""

    var body: some View {
        if locked { pillLabel(chevron: false).accessibilityElement(children: .ignore).accessibilityLabel("Account, \(model.account ?? "none")") }
        else { menu }
    }

    private func pillLabel(chevron: Bool) -> some View {
        HStack(spacing: 8) {
            AccountMonogram(name: model.account ?? "?", size: 28)
            Text(model.account ?? "Account").font(.figtree(15, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.ink).lineLimit(1)
            if chevron { Image(systemName: "chevron.down").font(.figtree(12, .bold)).foregroundStyle(Theme.muted) }
        }
        .padding(.leading, 4).padding(.trailing, 12)
        .frame(minHeight: 36)
        .background(Capsule().fill(Theme.surface))
        .panelShadow()
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var menu: some View {
        Menu {
            ForEach(model.accounts, id: \.self) { name in
                Button { model.select(name) } label: {
                    if name == model.account { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Divider()
            Button { newName = ""; asking = true } label: { Label("New account", systemImage: "plus") }
        } label: {
            if pill {
                pillLabel(chevron: true)
            } else {
                HStack(spacing: 4) {
                    Text(model.account ?? "Account").font(.headline).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.bold())
                }
            }
        }
        .accessibilityLabel(pill ? "Account, \(model.account ?? "none")" : (model.account ?? "Account"))
        .alert("New account", isPresented: $asking) {
            TextField("Trainer name", text: $newName).accountNameField()
            Button("Create") { model.createAccount(newName) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Each account has its own box.") }
    }
}

/// Settings and Diagnostics, in a menu at the top right.
struct MoreMenu: View {
    /// The UI v1 header look: a 40 pt circle with an ellipsis (see `MoreButton`).
    var circle = false
    @EnvironmentObject var model: AppModel
    var body: some View {
        Menu {
            Button { model.sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
            Button { model.sheet = .diagnostics } label: { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        } label: {
            if circle { IconButton(systemImage: "ellipsis", kind: .floating, label: "More", action: {}).face } else { Image(systemName: "ellipsis.circle") }
        }
        .accessibilityLabel("More")
    }
}

/// The Box header's account pill: opens the account menu (switch account, New account).
struct AccountPill: View {
    @EnvironmentObject var model: AppModel
    /// The Scan screen's pill is display only while a scan is waiting for review or being read (`isReviewing`): its Done headline is about this account.
    var locksWhileReviewing = false
    var body: some View { AccountMenu(pill: true, locked: locksWhileReviewing && model.isReviewing) }
}

/// The Box header's 40 pt circular "..." button: opens the Settings / Diagnostics menu.
struct MoreButton: View {
    var body: some View { MoreMenu(circle: true) }
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    init(url: URL) { urls = [url] }
    init(urls: [URL]) { self.urls = urls }
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
