#if DEBUG
import Foundation
import PogoReader

/// UI tests only: `-fake-scan` or `-fake-scan-paused` writes a running broadcast's shared state (as SampleScan writes a finished one) and keeps its
/// heartbeat fresh, so the Scan screen's scanning state can be looked at where no broadcast can run. Nothing else is faked: the screen reads it the
/// way it reads the real one.
enum ScanDebug {
    private static var timer: Timer?

    /// `-fake-ending list-end | pause | person` marks the sample scan the way the extension marks a scan that ended at the end of the list, after a pause
    /// that ran out, or by the person; `-fake-storage-count N` is the count the scan was started with (a Full scan is only judged sound with one). Only the
    /// shared state is faked: the rows, the merge and the advice are the real ones.
    static func applyEnding(to s: inout BroadcastState) {
        let d = UserDefaults.standard
        switch d.string(forKey: "fake-ending") {
        case "list-end": s.endedAtListEnd = true
        case "pause": s.stoppedByTimeout = true
        case "person": s.stoppedByPerson = true
        default: break
        }
        if d.object(forKey: "fake-storage-count") != nil { s.storageCount = d.integer(forKey: "fake-storage-count"); s.eggCount = 0 }
    }

    static func installIfAsked() {
        let args = CommandLine.arguments
        let paused = args.contains("-fake-scan-paused")
        guard paused || args.contains("-fake-scan"), timer == nil else { return }
        // `-fake-scan-after N`: the broadcast goes live N seconds after launch and is fresh (started just now), as a broadcast the Scan screen started would be.
        let after = UserDefaults.standard.double(forKey: "fake-scan-after")
        let launched = Date()
        let started = after > 0 ? launched.addingTimeInterval(after) : Date().addingTimeInterval(-300)
        func write() {
            if after > 0, Date() < launched.addingTimeInterval(after) { return }
            var s = BroadcastState()
            s.started = started
            s.updated = Date()
            s.framesRead = 3700; s.framesSeen = 3720
            s.readCount = 742
            s.storageCount = 1698; s.eggCount = 12
            s.pausesAllowed = true
            s.scanId = Int(started.timeIntervalSince1970)
            s.commandPeriod = 0.5
            // `-fake-cp covered | cleared` (and `-fake-cp-stretches N`): the extension's covered-CP fields, as it publishes them.
            if let cp = UserDefaults.standard.string(forKey: "fake-cp") {
                s.cpCovered = cp == "covered"
                s.cpCoveredStretches = max(1, UserDefaults.standard.integer(forKey: "fake-cp-stretches"))
                s.cpCoveredSince = Date().addingTimeInterval(-40)
                s.cpCoveredFirstName = "Pidgey"; s.cpCoveredLastGoodName = "Rattata"; s.cpCoveredLastGoodCp = 412
            }
            if paused { s.paused = true; s.pausedAt = Date().addingTimeInterval(-20); s.pausedCard = "Pidgey CP 312"; s.pauseLimitSeconds = 70 }
            _ = SharedStore.write(s)
        }
        write()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in write() }
    }
}
#endif
