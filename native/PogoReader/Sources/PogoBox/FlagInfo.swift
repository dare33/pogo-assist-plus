import Foundation

/// What each flag the reader and the solver put on a Pokémon means in plain words, and which hand-corrected value
/// answers it. A flag is a prefix up to the first ":" or "-from"/"-over" detail; `cp-chosen-1960-over-60` is the flag
/// `cp-chosen` with detail.
public enum FlagInfo {
    public enum Field { case cp, hp, ivs, species }

    struct Entry { var prefix: String; var field: Field?; var text: (String) -> String }

    static let table: [Entry] = [
        Entry(prefix: "cp-computed", field: .cp) { _ in "The CP was not on screen, so it was worked out from the HP and the bars. Check it in the game." },
        Entry(prefix: "cp-recovered", field: .cp) { _ in "The CP was partly hidden on screen and was worked out from the HP and the bars. Check it in the game." },
        Entry(prefix: "cp-chosen", field: .cp) { _ in "The CP was read two different ways. The one that fits the stats was chosen. Check it in the game." },
        Entry(prefix: "same-as-previous", field: nil) { _ in "An identical copy of the Pokémon before it, found by the swipe between them. Check that you own two." },
        Entry(prefix: "ivs-unread", field: .ivs) { _ in "The appraisal bars could not be read, so the IVs are unknown. Open the appraisal and check." },
        Entry(prefix: "ambiguous-ivs", field: .ivs) { _ in "More than one set of IVs fits what was read, so none is saved. Check the appraisal." },
        Entry(prefix: "ivs-corrected", field: .ivs) { _ in "The bars read as IVs that cannot happen at this CP, so they were adjusted to ones that can. Check the appraisal." },
        Entry(prefix: "bars-unsettled", field: .ivs) { _ in "The appraisal bars were still moving when they were read. Check the IVs in the game." },
        Entry(prefix: "no-level-fits", field: .ivs) { _ in "No level and IVs fit this CP and HP, so a value was misread. Check the CP, HP and IVs." },
        Entry(prefix: "name-low-confidence", field: .species) { _ in "The name was hard to read and may be a longer name cut short. Check the name." },
        Entry(prefix: "level-ambiguous", field: nil) { _ in "More than one level fits, so the level is shown as a range." },
        Entry(prefix: "form-ambiguous", field: .species) { _ in "The screen does not show which form this is. Check the form in the game." },
        Entry(prefix: "hp-computed", field: .hp) { _ in "The HP was not read, so it was worked out from the stats. Check it in the game." },
        Entry(prefix: "hp-unread", field: .hp) { _ in "The HP could not be read or worked out. Check it in the game." },
        Entry(prefix: "sex-from-stats", field: .species) { _ in "Nidoran male and female look the same on screen. The one whose stats fit was chosen." },
        Entry(prefix: "mega-when-scanned", field: .cp) { _ in "This Pokémon was Mega evolved when it was scanned, so its CP, HP and level were not saved (the Mega values are temporary). Scan it again when it is not Mega evolved." },
        Entry(prefix: "ivs-disagree", field: .ivs) { _ in "The appraisal bars read differently on different frames. Check the IVs in the game." },
    ]

    private static func split(_ flag: String) -> (key: String, detail: String) {
        for e in table where flag == e.prefix || flag.hasPrefix(e.prefix + ":") || flag.hasPrefix(e.prefix + "-") {
            return (e.prefix, String(flag.dropFirst(e.prefix.count).drop { $0 == ":" || $0 == "-" }))
        }
        return (flag, "")
    }

    /// One plain sentence for a flag, with a generic one for a flag this table does not know.
    public static func explain(_ flag: String) -> String {
        let (key, detail) = split(flag)
        if let e = table.first(where: { $0.prefix == key }) { return e.text(detail) }
        return "The reader marked this Pokémon for a check (\(flag)). Check it in the game."
    }

    /// The value a hand correction of which would answer this flag, or nil for a flag no correction answers.
    public static func field(of flag: String) -> Field? {
        let (key, _) = split(flag)
        return table.first { $0.prefix == key }?.field
    }

    /// The flags left after the given values were corrected by hand.
    public static func remaining(_ flags: [String], corrected: Corrections) -> [String] {
        flags.filter { flag in
            switch field(of: flag) {
            case .cp?: return corrected.cp == nil
            case .hp?: return corrected.hp == nil
            case .ivs?: return corrected.ivs == nil
            case .species?: return corrected.species == nil
            case nil: return true
            }
        }
    }
}
