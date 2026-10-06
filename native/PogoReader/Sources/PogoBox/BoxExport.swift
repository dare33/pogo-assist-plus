import Foundation
import PogoReader

/// The box as one plain-text Markdown file for a chat model (Claude, ChatGPT): a header that defines every column and term, then one
/// table row per Pokémon with the advice the Next tab gives it. A table, not a line each: 2,000 rows with the column names written
/// once cost far fewer words than 2,000 lines that repeat them, and a model reads a Markdown table well.
public enum BoxExport {
    public static func fileName(account: String, date: Date) -> String {
        let safe = account.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "pogo-box-\(safe.isEmpty ? "box" : safe)-\(day(date)).md"
    }

    /// `advice` nil means the advisor's report was not available; the header says so and the Advice column is left out.
    public static func markdown(entries: [BoxEntry], advice: BoxAdvice?, account: String, date: Date) -> String {
        var out = [String]()
        out.append("# Pokémon GO box, exported from Pogo Assist+")
        out.append("")
        out.append("- Account: \(account)")
        out.append("- Box date (the scan this box was last saved from): \(day(date))")
        out.append("- Pokémon in this file: \(entries.count)")
        out.append(advice == nil
            ? "- Advice: NOT included. The advisor's report was not ready when this file was made, so the table has no Advice column."
            : "- Advice: included, the same advice the app's Next tab shows for each Pokémon.")
        out.append("")
        out.append("This is one player's Pokémon GO storage, read from the game's screen by the Pogo Assist+ app. One table row is one Pokémon. These are the columns and terms:")
        out.append("")
        out.append("- Pokémon: the species, with the form in brackets when it has one (for example Zamazenta (Hero)). \"(Shadow)\" or \"(Purified)\" is added when the box knows that.")
        out.append("- CP: combat power, as the game shows it. 0 means the CP is not known.")
        out.append("- Level: the Pokémon's level (1 to 50, in halves). \"30 to 31\" means the scan could not tell which of the two it is.")
        out.append("- HP: the Pokémon's hit points.")
        out.append("- IVs: the hidden stats as attack/defence/HP, each out of 15. \"not read\" means the scan could not read them.")
        out.append("- IV %: the three IVs added up, out of 45, as a percentage (15/15/15 is 100%).")
        out.append("- Dust: the stardust the game asks for the next power-up of this Pokémon, as shown on its card.")
        out.append("- Candy and XL: in the Advice column, the candy and XL candy a build costs. XL candy is the candy needed to power up beyond level 40.")
        out.append("- Flags: Shadow or Purified (only when the box knows it), and \"Hand-corrected\" when the owner typed over a value the scan had read. Shiny, lucky, favourite, gender, moves and the Pokémon's own nickname are NOT in this file.")
        out.append("- First seen, Last seen: the dates of the first and latest scan that found this Pokémon.")
        out.append("- To check: \"yes\" means the scan could not read at least one value for sure, so the CP, HP, IVs or level may be wrong until the owner checks it in the game. \"no\" means the values were read cleanly or were confirmed.")
        out.append("- Mega CP: when the scan has seen this Pokémon Mega evolved, the CP it had then (the Mega CP is temporary). The other columns are the Pokémon's own, un-evolved form, and its IVs are the same in both forms. Blank when never seen as a Mega.")
        if advice != nil {
            out.append("- Advice: what the app suggests for this Pokémon. Each build reads \"Power up to level 40\" or \"Evolve to X\" (\"and Mega evolve\" when that is part of it), then in brackets the tier, the areas it is for and the cost. Tier is the best rank this build's target has in the app's tier lists for those areas (S is the best, then A, then B). Areas are where the build is useful: Raids, Rocket, Gym, GL (Great League), UL (Ultra League), ML (Master League), Max (Max battles). The cost is dust, candy, XL candy and Elite TMs. \"spare for\" means this Pokémon is an extra copy of a build better served by another one, and \"duplicate\" says whether the app would keep it or transfer it. A blank Advice cell means the app suggests nothing for that Pokémon.")
        }
        out.append("")
        let head = ["#", "Pokémon", "CP", "Level", "HP", "IVs", "IV %", "Dust", "Flags", "First seen", "Last seen", "To check", "Mega CP"] + (advice == nil ? [] : ["Advice"])
        out.append("| " + head.joined(separator: " | ") + " |")
        out.append("|" + head.map { _ in " --- " }.joined(separator: "|") + "|")
        for (i, e) in entries.enumerated() {
            let r = e.row
            let ivs: String = r.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "not read"
            let megaCp: String = (e.megaForm?.cp).flatMap { $0 > 0 ? String($0) : nil } ?? ""
            var cells: [String] = [String(i + 1), name(r), r.cp > 0 ? String(r.cp) : "unknown", level(r.level, r.levelMax) ?? "unknown", r.hp.map(String.init) ?? "unknown"]
            cells += [ivs, percent(r.ivs) ?? "", r.dust.map(String.init) ?? "", flags(e), day(e.firstSeen), day(e.lastSeen), e.needsCheck ? "yes" : "no", megaCp]
            if let advice { cells.append(adviceText(advice.entries(for: e.id))) }
            out.append("| " + cells.map(cell).joined(separator: " | ") + " |")
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: - cells

    /// A pipe or a line break would break the table.
    private static func cell(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ") }

    private static func name(_ r: ScanRow) -> String { r.title + (r.shadow == 1 ? " (Shadow)" : r.shadow == 2 ? " (Purified)" : "") }

    private static func flags(_ e: BoxEntry) -> String {
        var f = [String]()
        if e.row.shadow == 1 { f.append("Shadow") } else if e.row.shadow == 2 { f.append("Purified") }
        if e.isHandCorrected { f.append("Hand-corrected") }
        return f.joined(separator: ", ")
    }

    private static func percent(_ i: IVs?) -> String? { i.map { "\(Int((Double($0.atk + $0.def + $0.hp) / 45 * 100).rounded()))%" } }

    private static func level(_ level: Double?, _ levelMax: Double?) -> String? {
        guard let l = level else { return nil }
        func n(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
        if let m = levelMax, m != l { return "\(n(l)) to \(n(m))" }
        return n(l)
    }

    private static func adviceText(_ a: BoxAdvice.ForEntry) -> String {
        var parts = [String]()
        for b in a.builds {
            var what = b.action
            if let l = b.targetLevel { what += " to level \(l == l.rounded() ? String(Int(l)) : String(l))" }
            var detail = [String]()
            if !b.tier.isEmpty { detail.append("tier \(b.tier)") }
            if !b.areas.isEmpty { detail.append(b.areas.joined(separator: ", ")) }
            if let p = b.pvp { detail.append(p) }
            detail.append(b.dust == 0 && b.candy == 0 && b.xl == 0 && b.eliteTMs == 0 ? "nothing to spend" : b.costText)
            if b.needsDynamax { detail.append("needs Dynamax") }
            if b.spares > 0 { detail.append("\(b.spares) spare \(b.spares == 1 ? "copy" : "copies")") }
            parts.append("\(what) [\(detail.joined(separator: "; "))]")
        }
        for b in a.spareFor { parts.append("spare for \(b.action) (\(b.title))") }
        if let d = a.duplicateOf { parts.append("duplicate of \(d.name), \(a.keep ? "keep" : "transfer")") }
        return parts.joined(separator: " / ")
    }

    private static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}
