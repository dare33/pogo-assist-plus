import SwiftUI

struct RootView: View {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView {
            NavigationStack { BoxView() }
                .tabItem { Label("Box", systemImage: "square.grid.2x2") }
            NavigationStack { NextView() }
                .tabItem { Label("Next", systemImage: "list.number") }
        }
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
        .background { Color.clear.fullScreenCover(isPresented: Binding(get: { model.isReviewing }, set: { _ in })) { ReviewView().environmentObject(model) } }
        .sheet(isPresented: Binding(get: { !model.shareURLs.isEmpty }, set: { if !$0 { model.shareURLs = [] } })) {
            ShareSheet(urls: model.shareURLs).presentationDetents([.medium, .large])
        }
        .alert("Pogo Assist+", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .overlay { if let work = model.busy { BusyOverlay(text: work) } }
        .onAppear { model.refreshBroadcast(); model.startTimer() }
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
    @EnvironmentObject var model: AppModel
    @State private var asking = false
    @State private var newName = ""

    var body: some View {
        Menu {
            ForEach(model.accounts, id: \.self) { name in
                Button { model.select(name) } label: {
                    if name == model.account { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Divider()
            Button { newName = ""; asking = true } label: { Label("New account", systemImage: "plus") }
        } label: {
            HStack(spacing: 4) {
                Text(model.account ?? "Account").font(.headline).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.bold())
            }
        }
        .alert("New account", isPresented: $asking) {
            TextField("Trainer name", text: $newName).accountNameField()
            Button("Create") { model.createAccount(newName) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Each account has its own box.") }
    }
}

/// Settings and Diagnostics, in a menu at the top right.
struct MoreMenu: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Menu {
            Button { model.sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
            Button { model.sheet = .diagnostics } label: { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        } label: { Image(systemName: "ellipsis.circle") }
        .accessibilityLabel("More")
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    init(url: URL) { urls = [url] }
    init(urls: [URL]) { self.urls = urls }
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
