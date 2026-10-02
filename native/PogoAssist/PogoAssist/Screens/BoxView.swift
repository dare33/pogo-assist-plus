import SwiftUI
import PogoBox
import PogoReader

struct BoxView: View {
    @EnvironmentObject var model: AppModel
    @State private var showToCheck = false
    @State private var search = ""
    @State private var scanning = false

    private var toCheckCount: Int { model.entries.filter(\.needsCheck).count }

    private var visible: [BoxEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return model.entries
            .filter { !showToCheck || $0.needsCheck }
            .filter { q.isEmpty || $0.row.title.lowercased().contains(q) || $0.row.display.lowercased().contains(q) || String($0.row.cp).contains(q) }
            .sorted { ($0.row.cp, $1.id) > ($1.row.cp, $0.id) }
    }

    var body: some View {
        Group {
            if model.entries.isEmpty { emptyState } else { list }
        }
        .navigationTitle("Box")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { AccountMenu() }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !model.entries.isEmpty {
                    Button { Task { await model.exportCSV() } } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Export CSV")
                }
                MoreMenu()
            }
        }
        .navigationDestination(isPresented: $scanning) { ScanView() }
        .navigationDestination(for: String.self) { PokemonDetailView(id: $0) }
        .sheet(isPresented: Binding(get: { model.exportURL != nil }, set: { if !$0 { model.exportURL = nil } })) {
            if let url = model.exportURL { ShareSheet(url: url).presentationDetents([.medium, .large]) }
        }
        .safeAreaInset(edge: .bottom) { scanButton }
    }

    private var scanButton: some View {
        Button { scanning = true } label: {
            Label("Scan Pokémon", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("No Pokémon in this box yet").font(.title3.bold())
            Text("Scan your Pokémon GO storage and they will appear here, with their IVs and what to do with each.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.entries.count) Pokémon").font(.title2.bold())
                    if let d = model.snapshot?.scanDate { Text("Last scan \(Fmt.date(d))").font(.footnote).foregroundStyle(.secondary) }
                }
                Picker("Show", selection: $showToCheck) {
                    Text("All").tag(false)
                    Text("To check \(toCheckCount)").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Section {
                ForEach(visible) { e in
                    NavigationLink(value: e.id) { EntryRow(entry: e) }
                }
                if visible.isEmpty { Text(showToCheck && search.isEmpty ? "Nothing needs a check." : "No Pokémon match.").foregroundStyle(.secondary) }
            }
        }
        .searchable(text: $search, prompt: "Search by name or CP")
        .listStyle(.insetGrouped)
    }
}

struct EntryRow: View {
    let entry: BoxEntry
    var body: some View {
        let r = entry.row
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(.body)
                Text(Fmt.ivLine(r.ivs)).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 8)
            if entry.isHandCorrected { Image(systemName: "pencil").font(.footnote).foregroundStyle(.secondary).accessibilityLabel("Corrected by hand") }
            if entry.needsCheck { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Needs a check") }
            Text(verbatim: "CP \(r.cp)").monospacedDigit().font(.body.weight(.medium))
        }
    }
}
