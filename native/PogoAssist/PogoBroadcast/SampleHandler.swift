import ReplayKit
import CoreMedia
import CoreVideo
import AudioToolbox
import os
import PogoReader
import UserNotifications

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
    private var stalls = StalledCardNormaliser()   // the live grouper sees a stalled card's CP misreads as the card's own CP; the replay log keeps the raw readings
    private var state = BroadcastState()
    private var memory = MemoryProbe()
    private var msTotal = 0.0                 // time spent on frames that were read (skipped frames excluded)
    private var lastWrite = Date.distantPast
    private var heartbeat: DispatchSourceTimer?
    private var writeFailures = 0
    private var covered = CoveredCpDetector()      // touched on `queue`: a banner over the CP makes the phone vibrate (see `handleCovered`)
    private let buzzLock = NSLock()
    private var buzzGeneration = 0                  // a burst of vibration pulses plays only while its generation is the current one: bumped when the CP clears and when the scan finishes
    private var endController: ScanEndController?   // only for a scan paged by a command; touched on `queue`
    private var lastReadingTime = 0.0, lastReadingUptime = 0.0
    private var finishedWork = false              // the finish work (state, log) has been done, by a user stop or by the end of the list

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        queue.sync {
            mode = ReaderSettings.mode
            log.notice("broadcast started, mode \(self.mode.rawValue, privacy: .public), app group \(SharedStore.groupID, privacy: .public)")
            if !SharedStore.containerAvailable {
                log.error("app group container unavailable: no state can be shared; check Signing & Capabilities on both targets")
            }
            lock.lock(); finished = false; ticks.removeAll(); droppedTimes.removeAll(); detector = SwipeDetector(); ticker = SwipeTicker(); lock.unlock()
            memory = MemoryProbe()
            finishedWork = false
            covered = CoveredCpDetector()
            cancelBuzz()
            let period = ReaderSettings.autoEndPeriod
            ReaderSettings.clearFinishRequest()
            ScanNotifier.removePauseNotifications()   // a new scan: no earlier scan's pause notification (or its "End scan" button) stays
            // The scan kind, the count and the eggs are captured here, like the period: only a Full scan may pause, and an Add-and-update scan neither uses nor remembers the count.
            // A Full scan started with no valid count (from Control Centre, past the Scan screen) runs as Add and update: no pause, never judged Full.
            let isFull = ScanEndDecision.pausesAllowed(isFull: ReaderSettings.scanIsFull, storageCount: ReaderSettings.storageCount)
            endController = ScanEndController(period: period, storageCount: ReaderSettings.storageCount, eggCount: ReaderSettings.eggCount, pausesAllowed: isFull)
            let table = try? SpeciesTable.bundled()
            if table == nil { log.error("species table could not be loaded") }
            let names = table.map(displayNames) ?? []
            grouper = LiveGrouper(species: table)
            stalls = StalledCardNormaliser()
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
            state.pausesAllowed = isFull
            state.storageCount = isFull ? ReaderSettings.storageCount : nil
            state.eggCount = isFull ? ReaderSettings.eggCount : nil
            state.scanId = Int(state.started.timeIntervalSince1970)
            state.commandPeriod = period   // what this scan was started with: the app judges it by this, not by a setting changed since
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
            timer.setEventHandler { [weak self] in self?.beat() }
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
        queue.sync { finishWork() }
    }

    /// On `queue`. The state and log as a user stop leaves them; once only, whether the user stopped or the list ended.
    private func finishWork() {
        guard !finishedWork else { return }
        finishedWork = true
        heartbeat?.cancel()
        heartbeat = nil
        cancelBuzz()
        drainTicks()
        grouper.finish()
        state.rows = grouper.rows
        state.finished = true
        state.paused = false; state.pausedAt = nil   // a stop from the red bar while paused must not leave the scan looking paused (the app's fallback would post a stale "paused")
        replay?.close()
        write(force: true)
        log.notice("broadcast finished: \(self.state.framesRead) read, \(self.state.framesDropped) dropped, \(self.state.skippedLowMemory) skipped for memory, peak \(self.state.peakFootprintMB, format: .fixed(precision: 1)) MB")
    }

    /// On `queue`, once a second: the state write, and the person's "Finish now" (the app sets a flag in the app group).
    private func beat() {
        guard !finishedWork else { return }
        if let asked = ReaderSettings.finishRequestedScan {
            // Scoped to THIS scan. Not paused at this moment: the request waits up to `finishRequestGraceSeconds` for the scan to pause again (a false resume and a second pause on the same
            // stall must not swallow the tap); another scan's request, or an old one, is dropped, so an old notification never ends a later pause.
            let age = Date().timeIntervalSince1970 - (ReaderSettings.finishRequestedAt ?? 0)
            switch ScanNotification.finishRequestVerdict(asked: asked, runningScan: state.scanId, paused: state.paused, ageSeconds: age) {
            case .keep: break
            case .drop: ReaderSettings.clearFinishRequest()
            case .honour:
                ReaderSettings.clearFinishRequest()
                if var c = endController {
                    let event = c.finishNow(at: lastReadingTime)
                    endController = c
                    if case .finish(let at, let last) = event { endAtListEnd(at: at, last: last, byPerson: true); return }
                }
            }
        }
        // The pause timeout is also checked here, so a paused broadcast with no frames (or with Vision skipped under memory pressure) still finishes.
        if var c = endController, c.paused != nil {
            let now = lastReadingTime + (ProcessInfo.processInfo.systemUptime - lastReadingUptime)
            let event = c.tick(now: now)
            endController = c
            if case .finish(let at, let last) = event { endAtListEnd(at: at, last: last, byPerson: false, timeout: endController?.timedOut ?? false); return }
        }
        write(force: false)
    }

    /// On `queue`. The controller's verdict on one reading: nothing, a PAUSE (the quiet time was reached on a card that is not clearly the end: keep reading, tell the person),
    /// a RESUME (a new card was read) or a FINISH (the list ended, or a pause timed out).
    private func handleEnd(_ reading: FrameReading, time: Double) {
        guard var c = endController else { return }
        lastReadingTime = time; lastReadingUptime = ProcessInfo.processInfo.systemUptime
        let event = c.feed(reading, time: time, read: state.rows.count)
        endController = c
        switch event {
        case .none: break
        case .pause(let p):
            log.notice("paused at \(p.name ?? "?", privacy: .public) CP \(p.cp ?? 0): \(p.read) read")
            record(.pause(at: p.at, last: p.last, read: p.read, closed: p.closed))
            state.paused = true; state.pauseCount += 1; state.pausedAt = Date(); state.eventSeq += 1
            state.pauseLimitSeconds = c.remainingPauseSeconds(now: time)
            state.pausedCard = [p.name, p.cp.map { "CP \($0)" }].compactMap { $0 }.joined(separator: " ")
            write(force: true)
            ScanNotifier.post(ScanNotification.paused(scan: state.scanId, event: state.eventSeq, read: p.read, storageCount: state.storageCount, eggCount: state.eggCount, lastName: p.name, lastCP: p.cp, sizes: ReaderSettings.commandSizes, limitSeconds: state.pauseLimitSeconds)) { [log] error in
                if let error { log.error("notification could not be posted: \(error.localizedDescription, privacy: .public)") }
            }
        case .resume(let at):
            log.notice("resumed: a new card was read")
            record(.resume(at: at))
            state.paused = false; state.pausedAt = nil
            write(force: true)
            ScanNotifier.removePauseNotifications(scan: state.scanId)
        case .windowRestarted:
            log.notice("appraisal reopened on the paused card: the \(Int(ScanEndDecision.pauseTimeoutSeconds)) s window starts over")
            state.pausedAt = Date()
            write(force: true)
        case .finish(let at, let last):
            endAtListEnd(at: at, last: last, byPerson: false, timeout: endController?.timedOut ?? false)
        }
    }

    /// A burst of vibration: `buzzPulses` pulses `buzzGap` seconds apart, about 3.5 s. The vibrate sound is one fixed short pulse, so back to back pulses are the only way to make it longer and feel stronger.
    /// Each pulse schedules the next on a global queue and checks the generation first, so `cancelBuzz` stops a burst at once and nothing is left scheduled once the scan finishes.
    private static let buzzPulses = 7, buzzGap = 0.5

    private func startBuzz() {
        buzzLock.lock(); buzzGeneration += 1; let generation = buzzGeneration; buzzLock.unlock()   // a burst still playing gives way to the new one
        pulse(1, generation: generation)
    }

    private func pulse(_ n: Int, generation: Int) {
        buzzLock.lock(); let current = buzzGeneration == generation; buzzLock.unlock()
        guard current else { return }
        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        guard n < Self.buzzPulses else { return }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.buzzGap) { [weak self] in self?.pulse(n + 1, generation: generation) }
    }

    private func cancelBuzz() { buzzLock.lock(); buzzGeneration += 1; buzzLock.unlock() }

    /// On `queue`. Something covers the CP (`CoveredCpDetector`): a burst of vibration of about 3.5 s, repeated every five more cards with no CP until the CP is shown again; the firing is
    /// also noted in the replay log and the shared state. No sound and no notification (a notification banner would itself cover the CP). The scan goes on reading.
    private func handleCovered(_ reading: FrameReading, time: Double) {
        guard let event = covered.feed(reading) else { return }
        switch event {
        case .covered(let c):
            log.notice("CP covered from \(c.firstName, privacy: .public): last card with a CP was \(c.lastGoodName ?? "?", privacy: .public) \(c.lastGoodCp ?? 0)")
            startBuzz()
            if let writer = replay {
                switch writer.append(CpCoveredNote(t: c.startedAt ?? time, first: c.firstName, lastGood: c.lastGoodName, lastGoodCp: c.lastGoodCp)) {
                case .written: state.replayLines = writer.lineCount
                case .truncatedNow: state.replayLogTruncated = true; log.notice("replay log reached its size cap and stopped")
                case .failedNow: state.replayLogFailed = true; log.error("replay log write failed: the log is switched off, reading continues")
                case .disabled: break
                }
            }
            state.cpCovered = true; state.cpCoveredStretches += 1; state.cpCoveredSince = Date()
            state.cpCoveredFirstName = c.firstName; state.cpCoveredLastGoodName = c.lastGoodName; state.cpCoveredLastGoodCp = c.lastGoodCp
            write(force: true)
        case .stillCovered(let cards):
            // Not noted in the replay log: no note type fits and the log's firing note already says where the stretch began.
            log.notice("CP still covered after \(cards) more cards: another burst")
            startBuzz()
        case .cleared:
            log.notice("CP shown again")
            cancelBuzz()
            state.cpCovered = false
            write(force: true)
        }
    }

    /// On `queue`. The end of the list was seen: write the end marker (so the app can cut the tail), finish exactly as a user stop does,
    /// then end the broadcast. `finishBroadcastWithError` is the only way an extension can end one; the message reads as a result.
    private func endAtListEnd(at: Double, last: Double, byPerson: Bool, timeout: Bool = false) {
        log.notice("end of the list reached: last new Pokémon at \(last, format: .fixed(precision: 1)), ending at \(at, format: .fixed(precision: 1))")
        ScanNotifier.removePauseNotifications(scan: state.scanId)
        if byPerson { record(.stoppedByPerson(at: at)) }
        if timeout { record(.pauseTimedOut(at: at)) }
        record(.end(at: at, last: last))
        // A scan the person finished is judged like a stop from the red bar (never a Full scan), so it does not claim the end of the list was reached.
        state.endedAtListEnd = !byPerson && !timeout; state.stoppedByPerson = byPerson; state.stoppedByTimeout = timeout; state.paused = false; state.eventSeq += 1
        lock.lock(); finished = true; lock.unlock()
        finishWork()
        // The notification is posted FIRST and the broadcast is ended from its completion handler, so the extension cannot be torn down before the request is handed to the
        // system; a 0.5 s timer ends it whether or not the completion fired, so a slow or refused notification cannot hang the finish. Whichever comes first ends it, once.
        // Both run off the queue: if ReplayKit answers with broadcastFinished synchronously, its `queue.sync` must not wait on this block. The state and the log are written.
        let last = state.rows.last
        let note = ScanNotification.stopped(scan: state.scanId, event: state.eventSeq, read: state.rows.count, lastName: last?.name, lastCP: last?.cp)
        let once = OnceGate()
        let finish: () -> Void = { [weak self] in
            guard once.pass() else { return }
            self?.finishBroadcastWithError(NSError(domain: "com.dare33.pogoassist.broadcast", code: 0, userInfo: [NSLocalizedDescriptionKey: "The Pogo Assist scan has ended. OK stays in Pokémon GO; Go to Application opens Pogo Assist."]))
        }
        DispatchQueue.global(qos: .userInitiated).async { [log] in
            ScanNotifier.post(note) { error in
                if let error { log.error("notification could not be posted: \(error.localizedDescription, privacy: .public)") }
                finish()
            }
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5, execute: finish)
    }

    /// Lets the first caller through and no other.
    private final class OnceGate {
        private let lock = NSLock()
        private var passed = false
        func pass() -> Bool { lock.lock(); defer { lock.unlock() }; if passed { return false }; passed = true; return true }
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
            let changed = grouper.add(stalls.feed(reading))
            if changed { state.rows = grouper.rows }
            write(force: changed)
            state.readCount = state.rows.count
            handleCovered(reading, time: time)
            handleEnd(reading, time: time)
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
            covered.swipe()
            if mode == .saveCrops { saver.noteSwipe(at: t) } else { grouper.swipe(at: t) }
            if var c = endController { c.noteSwipe(at: t); endController = c }
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
