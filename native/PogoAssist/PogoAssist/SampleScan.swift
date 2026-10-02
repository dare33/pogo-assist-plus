import Foundation
import PogoReader

/// "Load sample scan": copy the bundled device log into the app group as if a broadcast had just finished, so the whole flow
/// (review, save, box, advice) can be driven where the broadcast extension cannot run, such as the simulator.
enum SampleScan {
    enum Failure: Error, LocalizedError {
        case missing, noContainer
        var errorDescription: String? {
            switch self {
            case .missing: return "The sample scan is not in the app."
            case .noContainer: return "The app group is not available, so there is nowhere to put the sample. Check Signing and Capabilities."
            }
        }
    }

    /// `partialRead` loads a tiny log whose one Pokémon has a part-read CP (182 for a saved 1982): the merge asks about it.
    static func install(partialRead: Bool = false) throws {
        guard let source = Bundle.main.url(forResource: partialRead ? "sample-partial-cp.replay" : "sample-scan.replay", withExtension: "jsonl") else { throw Failure.missing }
        guard let dest = SharedStore.replayURL else { throw Failure.noContainer }
        let data = try Data(contentsOf: source)
        try data.write(to: dest, options: .atomic)
        var state = BroadcastState()
        let lines = data.split(separator: UInt8(ascii: "\n")).count
        let readings = ReplayLog.lines(in: dest).reduce(0) { n, l in if case .reading = l { return n + 1 } else { return n } }
        state.finished = true
        state.framesRead = readings
        state.framesSeen = readings
        state.replayLines = lines
        state.started = Date().addingTimeInterval(-110)
        state.updated = Date()
        guard SharedStore.write(state) else { throw Failure.noContainer }
    }
}
