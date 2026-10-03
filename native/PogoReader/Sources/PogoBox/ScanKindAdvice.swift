import Foundation
import PogoReader

/// Whether a scan may be a FULL scan (every saved Pokémon it did not see is proposed as gone). The automatic end cannot tell the end of the list
/// from the command running out, or from a stop that came too early, so a full scan is only the default when everything agrees. One function, so
/// the app and the tests decide the same way.
public enum ScanKindAdvice {
    public struct Decision: Equatable {
        /// True: a full scan is sound. False: the review defaults to Add and update (the person can still change it, after confirming), with `reason`.
        public var fullIsSound: Bool
        public var reason: String?
        /// What the person typed, when it was usable, and the tolerance used.
        public var typedCount: Int?
    }

    /// How far the Pokémon read may differ from the typed count: 1% of it, at least 3 (the count error seen on the device runs is under 1%). The typed count is what the game
    /// shows, which includes eggs, so the read total may also be up to `StorageCountRules.maxEggSlots` below it.
    public static func tolerance(_ typed: Int) -> Int { StorageCountRules.tolerance(typed) }

    /// FULL only when ALL hold:
    /// - the automatic end fired (`endedAtListEnd`);
    /// - the replay log is neither truncated nor failed;
    /// - a count was typed and is at most the largest command size;
    /// - typed - eggs (the number typed, else 12 egg slots) - tol <= Pokémon read <= min(typed + tol, reach - 1), where reach is what the named command pages (`covers` + 1).
    /// `commandPeriod` is what the extension recorded for the scan (its pace picks the sizing; nil: paged by hand).
    public static func decide(endedAtListEnd: Bool, pokemonRead: Int, typedCount: Int?, logTruncated: Bool, logFailed: Bool, commandPeriod: Double?, eggCount: Int? = nil) -> Decision {
        func no(_ why: String) -> Decision { Decision(fullIsSound: false, reason: why, typedCount: typedCount) }
        let largest = VoiceCommandFile.setSizes.last ?? 0
        guard let typed = typedCount else {
            return no("No storage count was entered, so the scan cannot be checked against your Pokémon. Add and update is chosen.")
        }
        if typed > largest {
            return no("Your storage is above \(largest.formatted()) Pokémon, so one command cannot reach the end. Add and update is chosen; scan the rest with another command.")
        }
        if logTruncated || logFailed {
            return no("The scan's log is incomplete (it \(logFailed ? "could not be written" : "filled up")), so the end of the scan may be missing. Add and update is chosen.")
        }
        if !endedAtListEnd {
            return no("The scan was stopped by hand, not by reaching the end of the list, so it cannot say which Pokémon are gone. Add and update is chosen.")
        }
        let tol = tolerance(typed)
        if pokemonRead < StorageCountRules.lowestRead(typed, eggs: eggCount) {
            let why = StorageCountRules.validEggs(eggCount).map { "eggs are not scanned and you typed \($0), so about \($0) fewer is expected" } ?? "eggs are not scanned, so up to \(StorageCountRules.maxEggSlots) fewer is expected"
            return no("The scan stopped short of your count: \(pokemonRead.formatted()) Pokémon were read and the game showed \(typed.formatted()) (\(why)). Add and update is chosen.")
        }
        let size = VoiceCommandFile.setSize(covering: typed) ?? largest
        let kind: VoiceCommandFile.SetKind = (commandPeriod ?? 0) > 1.4 ? .swipe : .tap
        let reach = VoiceCommandFile.setSizing(size: size, kind: kind).covers + 1   // the command pages `covers` times from the first Pokémon
        if pokemonRead > typed + tol || pokemonRead >= reach {
            return no("The scan read more Pokémon than your count (\(pokemonRead.formatted()) against \(typed.formatted())), so the count may be out of date and the command (Pogo scan \(size)) may have run out. Add and update is chosen.")
        }
        return Decision(fullIsSound: true, reason: nil, typedCount: typed)
    }

    /// The line on the result for a scan the extension ended itself. It never claims completeness: it says how many were read, and only
    /// when a full scan is sound that this matches the count.
    /// Only when a full scan is sound: how the Pokémon read compare with the typed count. Never "matches".
    public static func matchSentence(pokemonRead: Int, decision: Decision, eggCount: Int? = nil) -> String? {
        guard decision.fullIsSound, let typed = decision.typedCount else { return nil }
        return "\(pokemonRead.formatted()) Pokémon read against the \(typed.formatted()) the game shows (that count includes \(eggsClause(eggCount)), which are not scanned)."
    }

    public static func endedLabel(pokemonRead: Int, decision: Decision, eggCount: Int? = nil) -> String {
        guard decision.fullIsSound, let typed = decision.typedCount else { return "The scan ended by itself after \(pokemonRead.formatted()) Pokémon." }
        return "The scan ended by itself: \(pokemonRead.formatted()) Pokémon read against the \(typed.formatted()) the game shows (that count includes \(eggsClause(eggCount)), which are not scanned)."
    }

    /// "the 8 eggs you typed" with a usable egg count, else "any eggs" (the flat allowance applies).
    private static func eggsClause(_ eggs: Int?) -> String {
        guard let e = StorageCountRules.validEggs(eggs) else { return "any eggs" }
        return e == 1 ? "the 1 egg you typed" : "the \(e) eggs you typed"
    }

    /// What the extension is told when the scan starts: the command's period when the person chose to page with the voice command AND the
    /// command set was made on this phone, else nil (no automatic end). Without the commands there is nothing to page by.
    public static func autoEndPeriod(wantsCommand: Bool, commandSetMade: Bool, pace: VoiceCommandFile.Pace) -> Double? {
        wantsCommand && commandSetMade ? pace.every : nil
    }

    /// The paging choice before the person has made one: by hand until the commands exist.
    public static func defaultsToHand(commandSetMade: Bool) -> Bool { !commandSetMade }
}
