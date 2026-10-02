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
    /// Set when this is the Diagnostics screen of the app: adds "Load sample scan" and a Done button.
    var onLoadSample: ((_ partialRead: Bool) -> Void)?
    var showsDone = false

    @StateObject private var model = StateModel()
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss

    /// The extension's memory limit is about 50 MB; the peak turns red from here.
    private let peakWarnMB = 45.0

    var body: some View {
        NavigationStack {
            List {
                if !model.groupAvailable {
                    Section {
                        Text("App group not available: check Signing & Capabilities on both targets")
                            .font(.callout.bold()).foregroundStyle(.red)
                    }
                }
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
                if let onLoadSample {
                    Section {
                        Button("Load sample scan") { onLoadSample(false) }.disabled(model.live)
                        Button("Load partial-read sample") { onLoadSample(true) }.disabled(model.live)
                    } footer: { Text("Copies a bundled device log into the app group as if a broadcast had just finished, then opens the scan result. For use where the broadcast cannot run. The partial-read sample is one Staraptor whose CP was read as 182; scan the full sample first and save it, then load this as an add-and-update scan.") }
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
                        Button(model.reading ? "Reading..." : "Read saved crops now") { model.readSavedCrops() }.disabled(model.reading || model.live)
                        if model.live { Text("Available when the broadcast has stopped.").font(.footnote).foregroundStyle(.secondary) }
                        if let n = model.deferredNote { Text(n).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                if !model.deferredRows.isEmpty {
                    Section("Pokémon read from saved crops (\(model.deferredRows.count))") {
                        ForEach(model.deferredRows, id: \.index) { RowView(row: $0) }
                    }
                }
                Section("Pokémon read live (\(model.state.rows.count))") {
                    if model.state.rows.isEmpty { Text(!model.groupAvailable ? "No shared storage (see the red line above)." : model.hasState ? "Nothing read yet." : "No broadcast yet.").foregroundStyle(.secondary) }
                    ForEach(model.state.rows, id: \.index) { RowView(row: $0) }
                }
            }
            .navigationTitle(showsDone ? "Diagnostics" : "Pogo Assist+")
            .toolbar {
                if showsDone { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if model.hasState, let url = SharedStore.stateURL {
                        ShareLink(items: [url] + [SharedStore.deferredURL, SharedStore.replayURL].compactMap { $0 }.filter { FileManager.default.fileExists(atPath: $0.path) }) { Image(systemName: "square.and.arrow.up") }
                    }
                    // Not while a broadcast is live: Clear would delete the replay log the extension is still writing.
                    Button("Clear", role: .destructive) { model.clear() }.disabled(model.live)
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
            if s.replayLines > 0 || s.replayLogFailed {
                Text("Replay log: \(s.replayLines) lines" + (s.replayLogTruncated ? " (stopped at its size cap)" : "") + (s.replayLogFailed ? " (a write failed; logging stopped)" : ""))
                    .font(.footnote).foregroundStyle(s.replayLogFailed || s.replayLogTruncated ? Color.orange : Color.secondary)
            }
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
