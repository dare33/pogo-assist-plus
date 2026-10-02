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
    /// The app group container exists (false when signing / the group is not set up).
    @Published var groupAvailable = SharedStore.containerAvailable
    private var timer: Timer?

    /// What the Darwin notification callback holds. The callback cannot capture, so something must
    /// travel as the observer pointer; it must never be the model itself, because a notification can
    /// arrive after the model has gone (Diagnostics is a sheet that closes) and would then call into
    /// freed memory. The box is retained for the life of the process (a few bytes per model) and only
    /// holds the model weakly.
    private final class ObserverBox { weak var model: StateModel? }
    private let box = ObserverBox()

    init() {
        reload()
        box.model = self
        let pointer = Unmanaged.passRetained(box).toOpaque()   // never released: see ObserverBox
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), pointer, { _, observer, _, _, _ in
            guard let observer = observer else { return }
            let box = Unmanaged<ObserverBox>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { box.model?.reload() } }
        }, SharedStore.notificationName as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(box).toOpaque(), CFNotificationName(SharedStore.notificationName as CFString), nil)
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
        groupAvailable = SharedStore.containerAvailable
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
    /// the rows, write them to the app group, and only then delete the crops. Not while a broadcast is
    /// writing them: there is no way to force it past that.
    func readSavedCrops() {
        guard !reading, !live, let dir = SharedStore.cropsURL, let out = SharedStore.deferredURL else { return }
        let archive = CropArchive(directory: dir)
        guard archive.frameCount > 0 else { return }
        reading = true
        deferredNote = "Reading \(archive.frameCount) saved frames..."
        Task.detached(priority: .userInitiated) {
            let table = try? SpeciesTable.bundled()
            let probe = MemoryProbe()
            probe.resetPeak()
            let reader = FrameReader(text: VisionTextReader(), names: table.map(displayNames) ?? [])
            let t0 = Date()
            let result = DeferredRun.readAndGroup(archive: archive, reader: reader, species: table, removeWhenDone: false)
            probe.sample()
            let secs = Date().timeIntervalSince(t0)
            // The crops are the only copy of what was read: delete them only once the result is on disk.
            var saved = false
            if let data = try? JSONEncoder().encode(DeferredResult(rows: result.rows, frames: result.readings.count, seconds: secs, peakFootprintMB: MemoryProbe.megabytes(probe.peakBytes))) {
                do { try data.write(to: out, options: .atomic); saved = true } catch { saved = false }
            }
            if saved { archive.remove(frames: result.consumed) }   // only the frames that were read
            await MainActor.run {
                self.deferredRows = result.rows
                let kept = result.unreadable > 0 ? " Kept \(result.unreadable) unreadable frames." : ""
                self.deferredNote = saved
                    ? "Read \(result.readings.count) saved frames in \(String(format: "%.1f", secs)) s; the crops that were read were deleted.\(kept)"
                    : "Read \(result.readings.count) saved frames but could not write the result: the crops were kept.\(kept)"
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
