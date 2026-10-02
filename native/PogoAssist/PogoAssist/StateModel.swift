import SwiftUI
import PogoReader

/// Re-reads the extension's state file on its Darwin notification and on a 1 s timer while the app
/// is in the foreground, and runs the deferred read of saved crops ("save crops" mode).
@MainActor
final class StateModel: ObservableObject {
    @Published var state = BroadcastState()
    @Published var hasState = false
    @Published var mode = ReaderSettings.mode { didSet { ReaderSettings.mode = mode } }
    @Published var deferredRows: [LiveRow] = []
    @Published var deferredNote: String?
    @Published var reading = false
    @Published var now = Date()
    private var timer: Timer?

    init() {
        reload()
        // The extension posts this after each write; the callback must not capture, so the model
        // travels as the observer pointer.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
            guard let observer = observer else { return }
            let model = Unmanaged<StateModel>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { model.reload() }
        }, SharedStore.notificationName as CFString, nil, .deliverImmediately)
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func stopTimer() { timer?.invalidate(); timer = nil }

    func reload() {
        now = Date()
        if let s = SharedStore.read() { state = s; hasState = true } else { state = BroadcastState(); hasState = false }
    }

    func clear() {
        SharedStore.clear()
        deferredRows = []
        deferredNote = nil
        if let u = SharedStore.deferredURL { try? FileManager.default.removeItem(at: u) }
        reload()
    }

    // MARK: - broadcast health

    /// Seconds since the extension last wrote its state.
    var secondsSinceUpdate: Double { max(0, now.timeIntervalSince(state.updated)) }

    /// The extension writes at least once a second; no update for a few seconds and no finish marker
    /// means the broadcast stopped without finishing (the extension may have been killed).
    var endedWithoutFinish: Bool { hasState && !state.finished && secondsSinceUpdate >= Tuning.staleStateSeconds }

    /// A broadcast is running (a recent write, no finish marker).
    var live: Bool { hasState && !state.finished && !endedWithoutFinish }

    // MARK: - saved crops

    var savedCropFrames: Int {
        guard let dir = SharedStore.cropsURL else { return 0 }
        return CropArchive(directory: dir).frameCount
    }

    /// Read the saved crops with Vision (the same PogoReader code as the live path), group them, show
    /// the rows, write them to the app group, and delete the crops. Not while a broadcast is writing them.
    func readSavedCrops(force: Bool = false) {
        guard !reading, force || !live, let dir = SharedStore.cropsURL else { return }
        let archive = CropArchive(directory: dir)
        guard archive.frameCount > 0 else { return }
        reading = true
        deferredNote = "Reading \(archive.frameCount) saved frames..."
        let out = SharedStore.deferredURL
        Task.detached(priority: .userInitiated) {
            let table = try? SpeciesTable.bundled()
            let probe = MemoryProbe()
            probe.resetPeak()
            let reader = FrameReader(text: VisionTextReader(), names: table.map(displayNames) ?? [])
            let t0 = Date()
            let result = DeferredRun.readAndGroup(archive: archive, reader: reader, species: table)
            probe.sample()
            let secs = Date().timeIntervalSince(t0)
            if let out = out, let data = try? JSONEncoder().encode(DeferredResult(rows: result.rows, frames: result.readings.count, seconds: secs, peakFootprintMB: MemoryProbe.megabytes(probe.peakBytes))) {
                try? data.write(to: out, options: .atomic)
            }
            await MainActor.run {
                self.deferredRows = result.rows
                self.deferredNote = "Read \(result.readings.count) saved frames in \(String(format: "%.1f", secs)) s; the crops were deleted."
                self.reading = false
            }
        }
    }
}

/// What the app writes after reading saved crops (shared with the run's numbers).
struct DeferredResult: Codable {
    var rows: [LiveRow]
    var frames: Int
    var seconds: Double
    var peakFootprintMB: Double
}
