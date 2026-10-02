import Foundation
import PogoBox
import PogoReader

/// How the screens write a Pokémon's values.
enum Fmt {
    static func ivs(_ i: IVs?) -> String { i.map { "\($0.atk)/\($0.def)/\($0.hp)" } ?? "not read" }

    static func ivPercent(_ i: IVs?) -> String? { i.map { "\(Int((Double($0.atk + $0.def + $0.hp) / 45 * 100).rounded()))%" } }

    /// "IVs 15/14/13 (96%)" or "IVs not read".
    static func ivLine(_ i: IVs?) -> String { i.map { "IVs \(ivs($0)) (\(ivPercent($0) ?? ""))" } ?? "IVs not read" }

    static func level(_ r: ScanRow) -> String? {
        guard let l = r.level else { return nil }
        func n(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
        if let m = r.levelMax, m != l { return "\(n(l)) to \(n(m))" }
        return n(l)
    }

    static func date(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .shortened) }
    static func day(_ d: Date) -> String { d.formatted(date: .abbreviated, time: .omitted) }

    static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t >= 60 ? "\(t / 60) min \(t % 60) s" : "\(t) s"
    }

    /// "Pidgey (CP 300, IVs 10/11/12)" for a scanned or saved row, to tell two apart.
    static func brief(_ r: ScanRow) -> String { "\(r.title), \(cp(r.cp)), IVs \(ivs(r.ivs))" }

    /// "CP 1982", or "CP not known" for the 0 a Mega-when-scanned entry has.
    static func cp(_ v: Int) -> String { v > 0 ? "CP \(v)" : "CP not known" }

    /// One line for an entry in the "on screen but not read" list.
    static func unmatched(_ u: Unmatched) -> String {
        var known = [String]()
        if let n = u.name ?? (u.nameText?.isEmpty == false ? u.nameText : nil) { known.append(n) }
        if let cp = u.cp { known.append("CP \(cp)") }
        if let hp = u.hp { known.append("HP \(hp)") }
        if let i = u.ivs { known.append("IVs \(ivs(i))") }
        let what = known.isEmpty ? "A Pokémon" : known.joined(separator: ", ")
        switch u.reason {
        case "name-not-read": return "\(what): the name could not be read."
        case "cp-not-read":
            let opts = (u.cpOptions ?? []).map(String.init).joined(separator: " or ")
            return "\(what): the CP could not be read" + (opts.isEmpty ? "." : "; it could be \(opts).")
        case "absorbed": return "\(what): seen on one frame only and joined to the Pokémon next to it" + (u.into.map { " (CP \($0))." } ?? ".")
        default: return "\(what): not read (\(u.reason))."
        }
    }
}

extension Fmt {
    static func number(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }
}

extension Fmt {
    /// A saved Pokémon for a choice list: "Staraptor, CP 1982, HP 142, IVs 13/12/15".
    static func candidate(_ r: ScanRow) -> String { "\(r.title), \(cp(r.cp)), HP \(r.hp.map(String.init) ?? "not read"), IVs \(ivs(r.ivs))" }
}
