import ReplayKit
import CoreMedia
import CoreVideo
import os
import PogoReader

/// The broadcast upload extension. It receives the screen as sample buffers, keeps at most five
/// frames a second by presentation timestamp, and handles one frame at a time. A frame that arrives
/// while the previous one is still being handled is dropped: the callback only bumps a counter and
/// returns, so the sample buffer is never captured by a closure and never queued (a queue of sample
/// buffers is how extensions get killed). Results go to the app through a small JSON file in the app group.
///
/// Three reader modes (chosen in the app, read at `broadcastStarted`):
/// - accurate / fast: Vision runs here. Before each frame the extension asks iOS how much memory is
///   left; below `Tuning.lowMemoryAvailableBytes` it skips the frame (counted) rather than risk being killed.
/// - saveCrops: no Vision request exists in this mode. Only the pixel work runs; a few small crops per
///   card are written to the app group and the app reads them when it comes to the foreground.
///
/// The state file is written whenever rows change and at least once a second (a timer), so if the
/// extension is killed the app still has the last state, and finds no finish marker in it. The extension
/// logs with os_log (subsystem = its bundle id) at start, on the mode chosen, on finish and on any state
/// write that fails; read it in Console.app (device selected) or `log stream`.
///
/// Swipes are seen separately from reading: every kept frame (5 fps), including those dropped because Vision is
/// busy, gets a cheap luma signature straight from its buffer (`SwipeDetector`, the JS reference's signature
/// over the CP and name bands). Three frames in a row that differ sharply from their predecessors are a swipe;
/// its time (the confirming frame's) goes into a small lock-guarded list. The reader drains the list right after
/// Vision returns, immediately before it adds that frame's reading (and before a skipped frame, and at finish), so
/// a swipe confirmed while Vision was busy is seen by the grouper before the reading that followed it. Without
/// this, a busy extension drops the very frames (no CP, no HP) that show a swipe, and two identical Pokémon in a
/// row would merge. It cannot see every swipe (see the README's swipe table); a swipe it misses is not recovered.
///
/// Allocations are kept small on purpose: the frame goes straight to FrameProcessor (vImage into one
/// reused buffer), no UIKit images, no CIContext, and nothing large is logged.
class SampleHandler: RPBroadcastSampleHandler {
    /// Frames per second kept, by presentation timestamp.
    private let readsPerSecond = 5.0

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.dare33.pogoassist.broadcast", category: "broadcast")
    // `.workItem`: every work item gets its own autorelease pool; the user-initiated class because a
    // frame must be read before the next one arrives.
    private let queue = DispatchQueue(label: "pogo.read", qos: .userInitiated, autoreleaseFrequency: .workItem)
    private let lock = NSLock()
    // Guarded by `lock`: the callback's whole decision is made under it.
    private var busy = false
    private var lastKept = -Double.infinity   // presentation time of the last frame accepted
    private var seen = 0                      // frames offered at the 5 fps rate
    private var dropped = 0                   // of those, dropped because the previous one was still being handled
    private var ticks = [Double]()            // swipe times seen by the signature, drained by the reader
    private var droppedTimes = [Double]()     // times of frames dropped because the reader was busy, drained likewise (bounded)
    private var replay: ReplayWriter?         // the replay log; touched on `queue` only
    private var finished = false              // broadcastFinished has run: later frames are ignored
    private var detector = SwipeDetector()    // guarded by `lock` (the callback and broadcastStarted)
    private var ticker = SwipeTicker()        // likewise

    private var mode = ReaderMode.accurate
    private var processor: FrameProcessor?    // touched on `queue` only, below
    private var archive: CropArchive?
    private var saver = CropSaver()
    private var grouper = LiveGrouper(species: nil)
    private var state = BroadcastState()
    private var memory = MemoryProbe()
    private var msTotal = 0.0                 // time spent on frames that were read (skipped frames excluded)
    private var lastWrite = Date.distantPast
    private var heartbeat: DispatchSourceTimer?
    private var writeFailures = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        queue.sync {
            mode = ReaderSettings.mode
            log.notice("broadcast started, mode \(self.mode.rawValue, privacy: .public), app group \(SharedStore.groupID, privacy: .public)")
            if !SharedStore.containerAvailable {
                log.error("app group container unavailable: no state can be shared; check Signing & Capabilities on both targets")
            }
            lock.lock(); finished = false; ticks.removeAll(); droppedTimes.removeAll(); detector = SwipeDetector(); ticker = SwipeTicker(); lock.unlock()
            memory = MemoryProbe()
            let table = try? SpeciesTable.bundled()
            if table == nil { log.error("species table could not be loaded") }
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
                } else {
                    log.error("crops folder unavailable (no app group): nothing will be saved")
                }
                saver = CropSaver()
            }
            state = BroadcastState()
            state.mode = mode.rawValue
            msTotal = 0
            replay = nil
            if mode != .saveCrops, let url = SharedStore.replayURL {
                replay = ReplayWriter(url: url)      // truncates; nil if it cannot be opened
                if replay == nil { log.error("replay log could not be opened") }
            }
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
        guard sampleBufferType == .video else { return }
        let stamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        // A timestamp that is not a number (an invalid CMTime) drops the frame: nothing downstream may be stamped
        // with a made-up time.
        guard stamp.isFinite else { return }
        // The whole decision, under one lock. A frame that is not kept, or that arrives while busy, captures
        // nothing: only the counters change, and nothing is enqueued.
        lock.lock()
        if finished { lock.unlock(); return }
        let pts = stamp
        guard pts - lastKept >= 1.0 / readsPerSecond - 0.005 else { lock.unlock(); return }
        lastKept = pts
        seen += 1
        let wasBusy = busy
        if !wasBusy { busy = true }
        if wasBusy {
            dropped += 1
            if droppedTimes.count >= 256 { droppedTimes.removeFirst() }   // bounded: the oldest goes
            droppedTimes.append(pts)
        }
        lock.unlock()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            if !wasBusy { lock.lock(); busy = false; lock.unlock() }
            return
        }
        // The swipe signature of every kept frame, read or not (see the class comment): cheap, and under the lock so
        // a restart of the detector (broadcastStarted) cannot race it.
        lock.lock()
        if let confirmed = ticker.feed(diff: detector.feed(pixelBuffer), time: pts) {
            if ticks.count >= Tuning.maxPendingTicks { ticks.removeFirst() }   // the oldest goes
            ticks.append(confirmed)
        }
        lock.unlock()
        if wasBusy { return }     // nothing captured, nothing queued
        queue.async { [self] in
            autoreleasepool { handle(pixelBuffer, time: pts) }
            lock.lock(); busy = false; lock.unlock()
        }
    }

    override func broadcastFinished() {
        lock.lock(); finished = true; lock.unlock()
        queue.sync {
            heartbeat?.cancel()
            heartbeat = nil
            drainTicks()
            grouper.finish()
            state.rows = grouper.rows
            state.finished = true
            replay?.close()
            write(force: true)
            log.notice("broadcast finished: \(self.state.framesRead) read, \(self.state.framesDropped) dropped, \(self.state.skippedLowMemory) skipped for memory, peak \(self.state.peakFootprintMB, format: .fixed(precision: 1)) MB")
        }
    }

    /// On `queue`. One accepted frame, in whichever mode.
    private func handle(_ pixelBuffer: CVPixelBuffer, time: Double) {
        guard let processor = processor else { return }
        lock.lock(); let over = finished; lock.unlock()
        if over { return }
        memory.sample()
        if mode == .saveCrops {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var (analysis, crops) = processor.analyse(pixelBuffer, time: time)
            drainTicks()          // after the frame is analysed, before it is judged: a swipe confirmed meanwhile counts
            var changed = false
            if saver.shouldSave(&analysis), let crops = crops, let archive = archive, archive.save(analysis, crops) {
                state.savedFrames = archive.frameCount; state.savedFiles = archive.fileCount
                state.savedMB = MemoryProbe.megabytes(archive.byteCount)
                changed = true
            }
            msTotal += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            state.framesRead += 1
            write(force: changed)
        } else if ReadGuard.shouldSkipVision(availableBytes: MemoryProbe.availableBytes()) {
            // Little memory left: skip Vision for this frame and say so, instead of being killed. The
            // skip is not a read: it is not counted in the frames read or the mean time per frame.
            drainTicks()
            record(.drop(time))
            state.skippedLowMemory += 1
            if state.skippedLowMemory == 1 { log.error("low memory: skipping Vision for frames (available below \(Tuning.lowMemoryAvailableBytes / 1_048_576) MB)") }
            write(force: false)
        } else {
            let t0 = DispatchTime.now().uptimeNanoseconds
            let reading = processor.process(pixelBuffer, time: time)
            msTotal += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
            drainTicks()          // right after Vision returns, immediately before the reading is added
            record(.reading(ReplayReading(reading, time: time, ms: Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)))
            state.framesRead += 1
            let changed = grouper.add(reading)
            if changed { state.rows = grouper.rows }
            write(force: changed)
        }
    }

    /// On `queue`. Hand the swipes the signature saw to whoever groups (the grouper, or the crop saver), and put them, with
    /// the frames dropped meanwhile, in the replay log in the order the grouper receives them.
    private func drainTicks() {
        lock.lock()
        let seenTicks = ticks; ticks.removeAll(keepingCapacity: true)
        let seenDrops = droppedTimes; droppedTimes.removeAll(keepingCapacity: true)
        lock.unlock()
        for t in seenDrops { record(.drop(t)) }
        for t in seenTicks {
            record(.tick(t))
            if mode == .saveCrops { saver.noteSwipe(at: t) } else { grouper.swipe(at: t) }
        }
    }

    /// On `queue`. One line of the replay log. A failure switches the log off and is logged once; reading is never affected.
    private func record(_ line: ReplayLine) {
        guard let writer = replay else { return }
        switch writer.append(line) {
        case .written: state.replayLines = writer.lineCount
        case .truncatedNow: state.replayLogTruncated = true; log.notice("replay log reached its size cap and stopped")
        case .failedNow: state.replayLogFailed = true; log.error("replay log write failed: the log is switched off, reading continues")
        case .disabled: break
        }
    }

    /// On `queue`. Rows (or saved crops) changed: write now. Otherwise at most about once a second.
    private func write(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastWrite) >= 0.9 else { return }
        lastWrite = now
        lock.lock(); state.framesSeen = seen; state.framesDropped = dropped; lock.unlock()
        state.meanMsPerFrame = state.framesRead > 0 ? msTotal / Double(state.framesRead) : 0
        state.footprintMB = MemoryProbe.megabytes(memory.sample())
        state.peakFootprintMB = MemoryProbe.megabytes(memory.peakBytes)
        state.lowestAvailableMB = memory.lowestAvailableBytes.map(MemoryProbe.megabytes)
        state.updated = now
        if !SharedStore.write(state) {
            writeFailures += 1
            if writeFailures == 1 || writeFailures % 60 == 0 { log.error("state write failed (\(self.writeFailures) times): app group container unavailable or disk full") }
        }
    }
}
