import ReplayKit
import CoreMedia
import CoreVideo
import PogoReader

/// The broadcast upload extension. It receives the screen as sample buffers, keeps at most five
/// frames a second by presentation timestamp, and handles one frame at a time: a frame that arrives
/// while the previous one is still being handled is dropped, never queued (a queue of sample buffers
/// is how extensions get killed). Results go to the app through a small JSON file in the app group.
///
/// Three reader modes (chosen in the app, read at `broadcastStarted`):
/// - accurate / fast: Vision runs here. Before each frame the extension asks iOS how much memory is
///   left; below `Tuning.lowMemoryAvailableBytes` it skips the frame (counted) rather than risk being killed.
/// - saveCrops: no Vision request exists in this mode. Only the pixel work runs; a few small crops per
///   card are written to the app group and the app reads them when it comes to the foreground.
///
/// The state file is written whenever rows change and at least once a second (a timer), so if the
/// extension is killed the app still has the last state, and finds no finish marker in it.
///
/// Allocations are kept small on purpose: the frame goes straight to FrameProcessor (vImage into one
/// reused buffer), no UIKit images, no CIContext, and nothing large is logged.
class SampleHandler: RPBroadcastSampleHandler {
    /// Frames per second kept, by presentation timestamp.
    private let readsPerSecond = 5.0

    private let queue = DispatchQueue(label: "pogo.read", qos: .utility)
    private let lock = NSLock()
    private var busy = false                  // guarded by lock
    private var lastKept = -Double.infinity   // presentation time of the last frame accepted
    private var mode = ReaderMode.accurate
    private var processor: FrameProcessor?    // touched on `queue` only
    private var archive: CropArchive?
    private var saver = CropSaver()
    private var grouper = LiveGrouper(species: nil)
    private var state = BroadcastState()
    private var memory = MemoryProbe()
    private var msTotal = 0.0
    private var lastWrite = Date.distantPast
    private var heartbeat: DispatchSourceTimer?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        queue.sync {
            mode = ReaderSettings.mode
            memory = MemoryProbe()
            let table = try? SpeciesTable.bundled()
            let names = table.map(displayNames) ?? []
            grouper = LiveGrouper(species: table)
            switch mode {
            case .accurate, .fast:
                var options = VisionOptions()
                options.fast = mode == .fast
                processor = FrameProcessor(textReader: VisionTextReader(options: options), names: names, targetWidth: 750, memory: memory)
            case .saveCrops:
                // No Vision request is created in this mode.
                processor = FrameProcessor.cropsOnly(names: names, targetWidth: 750, memory: memory)
                if let dir = SharedStore.cropsURL {
                    let a = CropArchive(directory: dir)
                    a.removeAll()     // a new broadcast starts a new set of crops
                    archive = a
                }
                saver = CropSaver()
            }
            state = BroadcastState()
            state.mode = mode.rawValue
            msTotal = 0
            write(force: true)
            // At least one state write a second, whatever the frames are doing.
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in self?.write(force: false) }
            timer.resume()
            heartbeat = timer
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Video only; audio and microphone are ignored.
        guard sampleBufferType == .video, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard pts - lastKept >= 1.0 / readsPerSecond - 0.005 else { return }
        lastKept = pts
        lock.lock()
        let wasBusy = busy
        if !wasBusy { busy = true }
        lock.unlock()
        // Dropped frames only bump a counter; nothing is queued behind a busy frame.
        queue.async { [self] in
            state.framesSeen += 1
            if wasBusy { state.framesDropped += 1; return }
            handle(pixelBuffer, time: pts)
            lock.lock(); busy = false; lock.unlock()
        }
    }

    override func broadcastFinished() {
        queue.sync {
            heartbeat?.cancel()
            heartbeat = nil
            grouper.finish()
            state.rows = grouper.rows
            state.finished = true
            write(force: true)
        }
    }

    /// On `queue`. One accepted frame, in whichever mode.
    private func handle(_ pixelBuffer: CVPixelBuffer, time: Double) {
        guard let processor = processor else { return }
        memory.sample()
        let t0 = DispatchTime.now().uptimeNanoseconds
        var changed = false
        if mode == .saveCrops {
            var (analysis, crops) = processor.analyse(pixelBuffer, time: time)
            if saver.shouldSave(&analysis), let crops = crops, let archive = archive, archive.save(analysis, crops) {
                state.savedFrames = archive.frameCount; state.savedFiles = archive.fileCount
                state.savedMB = MemoryProbe.megabytes(archive.byteCount)
                changed = true
            }
        } else if ReadGuard.shouldSkipVision(availableBytes: MemoryProbe.availableBytes()) {
            // Little memory left: skip Vision for this frame and say so, instead of being killed.
            state.skippedLowMemory += 1
            msTotal += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            write(force: false)
            return
        } else {
            let reading = processor.process(pixelBuffer, time: time)
            changed = grouper.add(reading)
            if changed { state.rows = grouper.rows }
        }
        msTotal += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        state.framesRead += 1
        write(force: changed)
    }

    /// On `queue`. Rows (or saved crops) changed: write now. Otherwise at most about once a second.
    private func write(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastWrite) >= 0.9 else { return }
        lastWrite = now
        state.meanMsPerFrame = state.framesRead > 0 ? msTotal / Double(state.framesRead) : 0
        state.footprintMB = MemoryProbe.megabytes(memory.sample())
        state.peakFootprintMB = MemoryProbe.megabytes(memory.peakBytes)
        state.lowestAvailableMB = memory.lowestAvailableBytes.map(MemoryProbe.megabytes)
        state.updated = now
        SharedStore.write(state)
    }
}
