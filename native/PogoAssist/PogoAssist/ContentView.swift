import SwiftUI
import ReplayKit
import PogoReader

/// The broadcast picker button, preset to the extension (microphone off).
struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        picker.preferredExtension = Bundle.main.object(forInfoDictionaryKey: "BroadcastExtensionID") as? String
        picker.showsMicrophoneButton = false
        return picker
    }
    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var model = StateModel()
    @Environment(\.scenePhase) private var phase

    /// The extension's memory limit is about 50 MB; the peak turns red from here.
    private let peakWarnMB = 45.0

    var body: some View {
        NavigationStack {
            List {
                Section("Before you start") {
                    Label("Voice Control: Show Confirmation and Show Hints off", systemImage: "1.circle")
                    Label("Tap the button below and start the broadcast", systemImage: "2.circle")
                    Label("Open Pokémon GO on the first Pokémon, appraisal open", systemImage: "3.circle")
                    Label("Say the command (or swipe by hand)", systemImage: "4.circle")
                    HStack {
                        Text("Start broadcast")
                        Spacer()
                        BroadcastPicker().frame(width: 64, height: 64)
                    }
                }
                Section("Reader (applies when the broadcast starts)") {
                    Picker("Reader", selection: $model.mode) {
                        ForEach(ReaderMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Section("Run") { statusView }
                if model.mode == .saveCrops || model.state.savedFrames > 0 || !model.deferredRows.isEmpty || model.savedCropFrames > 0 {
                    Section("Saved crops") {
                        Text("Saved \(model.state.savedFrames) frames (\(model.state.savedFiles) files, \(String(format: "%.1f", model.state.savedMB)) MB)").font(.footnote)
                        Button(model.reading ? "Reading..." : "Read saved crops now") { model.readSavedCrops(force: true) }.disabled(model.reading)
                        if let n = model.deferredNote { Text(n).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                if !model.deferredRows.isEmpty {
                    Section("Pokémon read from saved crops (\(model.deferredRows.count))") {
                        ForEach(model.deferredRows, id: \.index) { RowView(row: $0) }
                    }
                }
                Section("Pokémon read live (\(model.state.rows.count))") {
                    if model.state.rows.isEmpty { Text(model.hasState ? "Nothing read yet." : "No broadcast yet.").foregroundStyle(.secondary) }
                    ForEach(model.state.rows, id: \.index) { RowView(row: $0) }
                }
            }
            .navigationTitle("Pogo Assist+")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if model.hasState, let url = SharedStore.stateURL {
                        ShareLink(items: [url] + (SharedStore.deferredURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? [$0] : [] } ?? [])) { Image(systemName: "square.and.arrow.up") }
                    }
                    Button("Clear", role: .destructive) { model.clear() }
                }
            }
        }
        .onAppear { model.reload(); model.startTimer(); model.readSavedCrops() }
        .onDisappear { model.stopTimer() }
        // Coming to the foreground: refresh, and read any crops a finished or dead broadcast left.
        .onChange(of: phase) { _, p in
            if p == .active { model.reload(); model.startTimer(); model.readSavedCrops() } else { model.stopTimer() }
        }
    }

    private var statusView: some View {
        let s = model.state
        return VStack(alignment: .leading, spacing: 4) {
            Text("Frames read \(s.framesRead), dropped \(s.framesDropped), \(String(format: "%.0f", s.meanMsPerFrame)) ms each")
            HStack(spacing: 12) {
                Text("Extension memory \(mb(s.footprintMB))")
                Text("peak \(mb(s.peakFootprintMB))").foregroundStyle(s.peakFootprintMB >= peakWarnMB ? Color.red : Color.primary)
                Text("lowest free \(s.lowestAvailableMB.map(mb) ?? "n/a")")
            }
            .font(.footnote)
            if s.skippedLowMemory > 0 { Text("Skipped for low memory: \(s.skippedLowMemory) frames").font(.footnote).foregroundStyle(.orange) }
            if s.finished {
                Text("Broadcast finished (\(s.mode))").font(.footnote).foregroundStyle(.secondary)
            } else if model.endedWithoutFinish {
                Text("The broadcast ended without a finish marker: no update for \(Int(model.secondsSinceUpdate)) s (\(s.mode) mode). The extension may have been killed; this is its last state.")
                    .font(.footnote).foregroundStyle(.red)
            } else if model.hasState {
                Text("Broadcasting (\(s.mode))").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func mb(_ v: Double) -> String { String(format: "%.1f MB", v) }
}

struct RowView: View {
    let row: LiveRow
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(row.index). \(row.name)").font(.headline)
                Spacer()
                Text(row.cp.map { "CP \($0)" } ?? "CP ?").monospacedDigit()
            }
            Text("HP \(row.hp.map(String.init) ?? "?")   IVs \(row.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "?")   frames \(row.frames)")
                .font(.footnote).foregroundStyle(.secondary)
            if !row.flags.isEmpty { Text(row.flags.joined(separator: " ")).font(.caption2).foregroundStyle(.orange) }
        }
    }
}
