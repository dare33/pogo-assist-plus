import Foundation

/// The name a squad screen shows for a Pokémon whose name comes from the game master (pass 2-6, H3; READBACK 1.14 and 3.7, D69). The game master writes a Mega or Primal form as a
/// bracket after the species ("Rayquaza (Mega)", "Charizard (Mega X)", "Groudon (Primal)"); the game and the app's tables write it in front. A Shadow stays a bracket ("Palkia (Shadow)").
/// Every other name, and a name already written in front, is returned as it is.
public enum SquadNames {
    /// "Rayquaza (Mega)" is "Mega Rayquaza", "Charizard (Mega X)" is "Mega Charizard X", "Groudon (Primal)" is "Primal Groudon".
    public static func display(_ name: String) -> String {
        guard name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) else { return name }
        let base = String(name[..<open.lowerBound]), form = String(name[open.upperBound...].dropLast())
        for prefix in ["Mega", "Primal"] {
            if form == prefix { return prefix + " " + base }
            if form.hasPrefix(prefix + " ") {
                let rest = form.dropFirst(prefix.count + 1)
                if !rest.isEmpty { return prefix + " " + base + " " + rest }
            }
        }
        return name
    }
}
