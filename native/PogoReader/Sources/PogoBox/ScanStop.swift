import Foundation
import PogoReader

/// What the review says when a command scan ended by itself: where it stopped and what to do. It does not claim to know why: the log only tells whether the
/// appraisal had closed at the end (a tap past the end of the list closes it; a command that merely stopped leaves it open), and the count says whether the scan
/// is the size of the command that was said.
public enum ScanStop {
    /// Whether the appraisal was closed on the last card: of the last `window` card readings (a CP or a name read) in the log, at least `need` had no bars
    /// (closed) or at least `need` had them (open); nil when there are too few readings or no clear majority.
    public static func appraisalClosed(lines: [ReplayLine], window: Int = 8, need: Int = 6) -> Bool? {
        let card = lines.compactMap { l -> ReplayReading? in
            if case .reading(let r) = l, r.cp != nil || r.name != nil { return r } else { return nil }
        }.suffix(window)
        guard card.count >= window else { return nil }
        let noBars = card.filter { $0.ivs == nil }.count
        if noBars >= need { return true }
        if card.count - noBars >= need { return false }
        return nil
    }

    /// How far the Pokémon read may be from a command's reach for the scan to count as "the size of the command": 1% of the reach, at least 3 (the same
    /// tolerance as `ScanKindAdvice`; the run that ran a 1500 command out read 1,552 against a reach of 1,551).
    public static func tolerance(reach: Int) -> Int { max(3, Int((Double(reach) * 0.01).rounded(.up))) }

    /// Whether `read` is the size of the command that was said: for a full scan with a typed count, the smallest command covering it; otherwise (a part scan, or no
    /// count) any size in the set. `commandPeriod` picks the tap or swipe sizing.
    public static func ranOut(read: Int, typedCount: Int?, full: Bool, commandPeriod: Double?) -> Bool {
        let kind: VoiceCommandFile.SetKind = (commandPeriod ?? 0) > 1.4 ? .swipe : .tap
        func reach(_ size: Int) -> Int { VoiceCommandFile.setSizing(size: size, kind: kind).covers + 1 }
        let sizes: [Int]
        if full, let typed = typedCount, let size = VoiceCommandFile.setSize(covering: typed) ?? VoiceCommandFile.setSizes.last { sizes = [size] } else { sizes = VoiceCommandFile.setSizes }
        return sizes.contains { abs(read - reach($0)) <= tolerance(reach: reach($0)) }
    }

    /// The one place at the top of the review for a scan the extension ended itself.
    /// Where the scan paused (a card that was not the end of the list), by the row whose card was on screen when each pause began: "Stunfisk (CP 902)".
    public static func pauseNames(_ pauses: [ScanPipeline.Pause], rows: [ScanRow]) -> [String] {
        pauses.compactMap { p in
            let starts: [(ScanRow, Double)] = rows.compactMap { r in r.frames.compactMap(\.time).min().map { (r, $0) } }
            guard let hit = starts.filter({ $0.1 <= p.last + 1 }).max(by: { $0.1 < $1.1 }) else { return nil }
            return "\(hit.0.display) (CP \(hit.0.cp))"
        }
    }

    public static func summary(lastName: String?, lastCP: Int?, read: Int, appraisalClosed: Bool?, ranOut: Bool, matchSentence: String? = nil, paused: [String] = []) -> String {
        let last = lastName.map { name in "the last one read was \(name)" + (lastCP.map { " (CP \($0))" } ?? "") } ?? "no Pokémon were named"
        let opened = lastName ?? "the last Pokémon"
        var s = "The scan ended by itself after \(read.formatted()) Pokémon; \(last)."
        if !paused.isEmpty { s += paused.count == 1 ? " It paused once, at \(paused[0]), and carried on." : " It paused \(paused.count) times, at \(paused.dropLast().joined(separator: ", ")) and \(paused.last!), and carried on." }
        if let c = appraisalClosed { s += c ? " The appraisal had closed." : " The appraisal was still open." }
        if ranOut {
            s += " This is the size of the command you said: it ran out. To scan the rest, open \(opened) in Pokémon GO with the appraisal showing and say a command for what is left (Add and update)."
        } else {
            s += " It stopped after \(read.formatted()), short of the command's size. If that was not the end of your list, open \(opened) in Pokémon GO with the appraisal showing and scan again from there (Add and update)."
        }
        if let m = matchSentence { s += " " + m }
        return s
    }
}
