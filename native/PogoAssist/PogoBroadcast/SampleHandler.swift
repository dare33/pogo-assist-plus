import ReplayKit
import CoreMedia
import CoreVideo
import PogoReader

/// The broadcast upload extension. It receives the screen as sample buffers, keeps at most five
/// frames a second by presentation timestamp, and reads one frame at a time: a frame that arrives
/// while the previous one is still being read is dropped, never queued (a queue of sample buffers is
/// how extensions get killed). Results go to the app through a small JSON file in the app group.
///
/// Allocations are kept small on purpose: the frame goes straight to FrameProcessor (vImage into one
/// reused buffer), no UIKit images, no CIContext, and nothing large is logged.
class SampleHandler: RPBroadcastSampleHandler {
    /// Frames per second kept, by presentation timestamp.
    private let readsPerSecond = 5.0
    /// Stats-only writes (no row change) are spaced at least this far apart, seconds.
    private let statsInterval = 1.0

    private let queue = DispatchQueue(label: "pogo.read", qos: .utility)
    private let lock = NSLock()
    private var busy = false                  // guarded by lock
    private var lastKept = -Double.infinity   // presentation time of the last frame offered to the reader
    private var processor: FrameProcessor?    // touched on `queue` only
    private var grouper = LiveGrouper(species: nil)
    private var state = BroadcastState()
    private var memory = MemoryProbe()
    private var msTotal = 0.0
    private var lastWrite = Date.distantPast

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        queue.sync {
            memory = MemoryProbe()
            let table = try? SpeciesTable.bundled()
            grouper = LiveGrouper(species: table)
            processor = FrameProcessor(names: table.map(displayNames) ?? [], targetWidth: 750, memory: memory)
            state = BroadcastState()
            msTotal = 0
            write(force: true)
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
        // Dropped frames only bump a counter; nothing is queued behind a busy read.
        queue.async { [self] in
            state.framesSeen += 1
            if wasBusy { state.framesDropped += 1; return }
            read(pixelBuffer, time: pts)
            lock.lock(); busy = false; lock.unlock()
        }
    }

    override func broadcastFinished() {
        queue.sync {
            grouper.finish()
            state.rows = grouper.rows
            state.finished = true
            write(force: true)
        }
    }

    /// On `queue`. Reads one frame, folds it into the rows, writes the state when something changed.
    private func read(_ pixelBuffer: CVPixelBuffer, time: Double) {
        guard let processor = processor else { return }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let reading = processor.process(pixelBuffer, time: time)
        msTotal += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        state.framesRead += 1
        let changed = grouper.add(reading)
        if changed { state.rows = grouper.rows }
        write(force: changed)
    }

    /// On `queue`. Rows changed: write now. Otherwise at most once per `statsInterval`.
    private func write(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastWrite) >= statsInterval else { return }
        lastWrite = now
        state.meanMsPerFrame = state.framesRead > 0 ? msTotal / Double(state.framesRead) : 0
        state.footprintMB = MemoryProbe.megabytes(memory.sample())
        state.peakFootprintMB = MemoryProbe.megabytes(memory.peakBytes)
        state.lowestAvailableMB = memory.lowestAvailableBytes.map(MemoryProbe.megabytes)
        state.updated = now
        SharedStore.write(state)
    }
}
