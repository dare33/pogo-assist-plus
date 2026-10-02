import Foundation

/// Whether a scan may be a FULL scan (every saved Pokémon it did not see is proposed as gone). The automatic end cannot tell the end of the list
/// from the command running out, so a full scan is only offered when the list can be known to have ended. One function, so the app and the
/// tests decide the same way.
public enum ScanKindAdvice {
    public struct Decision: Equatable {
        /// True: a full scan is sound. False: the review defaults to Add and update (the person can still change it), with `reason`.
        public var fullIsSound: Bool
        public var reason: String?
    }

    /// - endedAtListEnd: the extension ended the scan itself because the list ended (`EndOfListDetector`).
    /// - pokemonRead: Pokémon in the scan result.
    /// - typedCount: the storage count typed for a full scan (nil when none).
    /// - logTruncated: the replay log hit its size cap, so its end may be missing.
    public static func decide(endedAtListEnd: Bool, pokemonRead: Int, typedCount: Int?, logTruncated: Bool, pace: VoiceCommandFile.Pace) -> Decision {
        let largest = VoiceCommandFile.setSizes.last ?? 0
        guard let typedCount else {
            return Decision(fullIsSound: false, reason: "No storage count was entered, so the command and how far it reaches are not known. Add and update is chosen.")
        }
        if typedCount > largest {
            return Decision(fullIsSound: false, reason: "Your storage is above \(largest.formatted()) Pokémon, so one command cannot reach the end. Add and update is chosen; scan the rest with another command.")
        }
        if logTruncated {
            return Decision(fullIsSound: false, reason: "The scan's log filled up, so the end of the scan may be missing. Add and update is chosen.")
        }
        if !endedAtListEnd {
            return Decision(fullIsSound: false, reason: "The scan was stopped by hand, not by reaching the end of the list, so it cannot say which Pokémon are gone. Add and update is chosen.")
        }
        if let size = VoiceCommandFile.setSize(covering: typedCount) {
            let reach = VoiceCommandFile.sizing(storageCount: size, pace: pace).covers + 1   // the command pages `covers` times from the first Pokémon
            if pokemonRead >= reach {
                return Decision(fullIsSound: false, reason: "The command (Pogo scan \(size)) ran out before the end of the list was seen. Add and update is chosen.")
            }
        }
        return Decision(fullIsSound: true, reason: nil)
    }
}
