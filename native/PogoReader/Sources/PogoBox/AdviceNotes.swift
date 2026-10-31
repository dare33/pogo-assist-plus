import Foundation

/// The Advice panel's wording around the builds: one message about being a spare, and one duplicate verdict that agrees with it.
/// The verdict comes from the hygiene rule in `src/advise.js` (sort by IV %, unknown IVs count as 0, ties by CP; keep one copy, or two of a
/// legendary, mythical or ultra beast; transfer the rest), which ignores the builds. So the verdict is only shown for a copy with no build of
/// its own: under a build it would contradict it (a copy built into Blastoise can still be the one hygiene would transfer).
public extension BoxAdvice {
    struct AdviceNotes: Equatable {
        /// "No build for this copy: you already have a better Eevee planned for Umbreon, Vaporeon and Glaceon." or, under its own builds,
        /// "Also a spare for Umbreon: a better copy is already planned."; nil when the copy is not a spare for anything.
        public var spare: String?
        /// "One of 65 Eevee in your box. **Keep it:** it has your best IVs of the 65." (Markdown bold); nil when the copy has a build of its own
        /// or is not one of several.
        public var verdict: String?
    }

    static func adviceNotes(_ a: ForEntry, name: String) -> AdviceNotes {
        // A target that is the Pokémon itself (a power-up) reads "another Moltres", not "another Moltres planned for Moltres".
        var targets = [String]()
        for b in a.spareFor where b.targetName != name && !targets.contains(b.targetName) { targets.append(b.targetName) }
        let joined = targets.count <= 1 ? (targets.first ?? "") : targets.dropLast().joined(separator: ", ") + " and " + targets[targets.count - 1]
        var spare: String?
        if !a.spareFor.isEmpty {
            if a.builds.isEmpty {
                spare = targets.isEmpty ? "No build for this copy: you already have another \(name) planned."
                                        : "No build for this copy: you already have another \(name) planned for \(joined)."
            } else {
                spare = targets.isEmpty ? "Also a spare: a better copy is already planned."
                                        : targets.count == 1 ? "Also a spare for \(joined): a better copy is already planned."
                                                             : "Also a spare for \(joined): better copies are already planned."
            }
        }
        guard a.builds.isEmpty, let d = a.duplicateOf else { return AdviceNotes(spare: spare, verdict: nil) }
        let count = "One of \(d.count) \(d.name) in your box."
        guard a.keep else { return AdviceNotes(spare: spare, verdict: "\(count) **The advisor would transfer this one.**") }
        return AdviceNotes(spare: spare, verdict: "\(count) **Keep it:** \(keepReason(d, copy: a.keepIndex ?? 0)).")
    }

    /// Why hygiene kept this copy: it has the best IVs (known, and at least every copy it did not keep: a tie goes to CP, but a transferred copy may
    /// have the higher CP, so a tie still reads "best IVs"), or it is the strongest because its IVs are unknown.
    /// A copy kept beyond the IV-ranked keeps (the trailing `dynamaxExtras`) is kept because it is marked as caught as a Dynamax; the IV wording counts only the IV-ranked keeps.
    internal static func keepReason(_ d: Duplicate, copy: Int) -> String {
        let ranked = max(0, d.keep.count - (d.dynamaxExtras ?? 0))
        if copy >= ranked { return "it is marked as caught as a Dynamax" }
        func pct(_ line: String) -> Double {
            // "CP 1960, 13/15/14" or "CP 1960, IVs unknown"
            guard let ivs = line.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) else { return 0 }
            let p = ivs.split(separator: "/").compactMap { Double($0) }
            return p.count == 3 ? (p[0] + p[1] + p[2]) / 45 * 100 : 0
        }
        let mine = d.keep.indices.contains(copy) ? pct(d.keep[copy]) : 0
        let bestOther = d.transfer.map(pct).max() ?? -1
        let wonOnIVs = mine > 0 && mine >= bestOther
        let two = ranked >= 2
        switch (two, wonOnIVs) {
        case (false, true): return "it has your best IVs of the \(d.count)"
        case (true, true): return "it has one of your two best IV sets of the \(d.count)"
        case (false, false): return "it is your strongest of the \(d.count)"
        case (true, false): return "it is one of your two strongest of the \(d.count)"
        }
    }
}
