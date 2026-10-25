import Foundation
import PogoBox

/// What a filtered pass says about itself, in the words the scan flow uses instead of the usual Full / Add and update ones. Kept apart from the views so the wording can be tested.
enum PassWording {
    /// "Dynamax pass: 14 marked, 1 new, 1 to check". Marked: Pokémon already in the box that the pass marked; new: Pokémon it added (marked); to check: the rows the scan flagged and
    /// the hand values it kept (`pass-conflict`). Parts that are zero are left out, except the marked count.
    static func line(_ pass: ScanPass, _ tally: BoxMerge.PassTally, toCheck: Int) -> String {
        var parts = ["\(tally.marked.formatted()) marked"]
        if tally.new > 0 { parts.append("\(tally.new.formatted()) new") }
        let check = toCheck + tally.conflicts
        if check > 0 { parts.append("\(check.formatted()) to check") }
        return "\(pass.passName): " + parts.joined(separator: ", ")
    }

    /// Step 1 of the Scan screen's steps and the guide's first page.
    static func searchInstruction(_ pass: ScanPass) -> String { "In Pokémon Go, type \(pass.searchWord) in the storage search." }
    static let openFirst = "Then open the appraisal of the first Pokémon it shows."
    static func lastStep(_ pass: ScanPass) -> String { "When the scan ends, come back to Pogo Assist: every Pokémon it read is marked \(pass.title)." }
    static func optionsLine(_ pass: ScanPass) -> String { "Marks every Pokémon the game\u{2019}s \(pass.searchWord) search shows. Nothing is removed from your box." }
    static func summary(_ pass: ScanPass) -> String { "\(pass.passName) · search: \(pass.searchWord)" }
    static func searchQuestion(_ pass: ScanPass) -> String { "Was this a \(pass.searchWord) search?" }
}
