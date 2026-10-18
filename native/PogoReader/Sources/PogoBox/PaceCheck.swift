import Foundation

/// Compares how fast a scan went with the Voice Control command the person chose: when it ran at the pace of a different mode, the
/// wrong command was probably heard. The measured pace is `ScanPace.medianPeriod`.
public enum PaceCheck {
    /// The mode whose nominal pace is nearest to a measured one, or nil when no mode is within `tolerance` seconds (a scan paged by
    /// hand, or by something else). Every mode the generator makes counts, so a 2.1 s run is named too (an older command ran at that pace).
    public static func nearestMode(to seconds: Double, tolerance: Double = 0.3) -> VoiceCommandFile.Pace? {
        let best = VoiceCommandFile.Pace.allCases.min { abs($0.every - seconds) < abs($1.every - seconds) }
        return best.flatMap { abs($0.every - seconds) <= tolerance ? $0 : nil }
    }

    /// One plain sentence when the scan ran at the pace of a different mode than the one chosen, else nil. A pace within 0.15 s of the
    /// chosen mode's counts as that mode; a pace near none of them says nothing.
    public static func check(measured seconds: Double, chosen: VoiceCommandFile.Pace) -> String? {
        if abs(chosen.every - seconds) <= 0.15 { return nil }
        guard let ran = nearestMode(to: seconds), ran != chosen else { return nil }
        return "This scan ran at about \(String(format: "%.1f", seconds)) s per Pokémon, which is the \(ran.title) pace; you had chosen \(chosen.title). Voice Control may have heard a different command."
    }
}
