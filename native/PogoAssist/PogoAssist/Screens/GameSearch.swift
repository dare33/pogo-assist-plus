import Foundation
import PogoBox
import PogoReader

/// The text to paste into the game's storage search: lower-case species names joined by ",", then "&", then the terms joined by ",".
/// "staraptor,moltres,charizard&hp140,hp129,hp118" finds the three names that also have one of the three HPs (a 4 Oct 2026 device check
/// confirmed that in the game "," binds before "&"). A CP term is used only for a CP that can be trusted; for a part-read CP (the CP is what is
/// in doubt) the HP term is used instead. A Pokémon with no usable term (no CP, or an untrusted CP and no HP) is left out of the search altogether
/// and counted as not covered: its name alone would only widen what the search shows. Every game search in the app (Review, Box select mode, the
/// detail page) is built here.
enum GameSearch {
    /// One question's or one row's contribution: the names and the terms it adds to a shared search.
    struct Part: Equatable {
        var names: [String]
        var terms: [String]
        /// The search can point at this one: it has a name and at least one term.
        var covered: Bool { !terms.isEmpty && names.contains { !$0.isEmpty } }
    }

    /// The search for these parts: names, then terms, each without repeats and in first-seen order. Parts that are not covered are left out.
    /// nil when no part is covered.
    static func text(_ parts: [Part]) -> String? {
        var names = [String](), terms = [String]()
        for p in parts where p.covered {
            for n in p.names where !n.isEmpty && !names.contains(n) { names.append(n) }
            for t in p.terms where !terms.contains(t) { terms.append(t) }
        }
        guard !names.isEmpty else { return nil }
        let head = names.joined(separator: ",")
        return terms.isEmpty ? head : head + "&" + terms.joined(separator: ",")
    }

    /// How many of these parts the search covers (the others are left out of `text`).
    static func covered(_ parts: [Part]) -> Int { parts.filter(\.covered).count }

    static func name(_ r: ScanRow) -> String { r.name.lowercased() }
    static func cp(_ v: Int) -> [String] { v > 0 ? ["cp\(v)"] : [] }
    static func hp(_ v: Int?) -> [String] { v.map { $0 > 0 ? ["hp\($0)"] : [] } ?? [] }

    /// The row's own CP cannot be trusted: it fits no level, or the merge found it to be a fragment of a saved CP (`partialRead`).
    static func untrusted(_ r: ScanRow, partRead: Bool = false) -> Bool { partRead || noLevelFits(r.flags) }

    static func noLevelFits(_ flags: [String]) -> Bool { flags.contains { $0 == "no-level-fits" || $0.hasPrefix("no-level-fits:") } }

    /// The one rule for a Pokémon on its own: its CP, or its HP when the CP cannot be trusted (it fits no level). An untrusted CP is never
    /// searched for, so with no HP there is no term and the part is not covered.
    static func part(name: String, cp v: Int, hp h: Int?, noLevelFits bad: Bool) -> Part {
        Part(names: [name.lowercased()], terms: bad ? hp(h) : cp(v))
    }

    /// A scanned row on its own (To check), or a saved entry's row (Box detail).
    static func part(row r: ScanRow) -> Part { part(name: r.name, cp: r.cp, hp: r.hp, noLevelFits: untrusted(r)) }

    /// A saved Pokémon (Not seen, Box): its name and CP, or its HP when its CP was flagged as fitting no level.
    static func part(saved e: BoxEntry) -> Part { part(row: e.row) }

    /// An open question: what to look for in the game to answer it.
    /// - evolved and powered up: both CPs (the saved one and the one read now), and both names for an evolution;
    /// - a Mega pair: the CPs of the two saved entries;
    /// - a part read (or a row whose CP fits no level): the HP, because the CP is what is in doubt;
    /// - anything else: the CP read.
    static func part(for u: BoxMerge.Unsure, row r: ScanRow, saved: [String: BoxEntry]) -> Part {
        let candidates = u.candidates.compactMap { saved[$0] }
        let own = untrusted(r, partRead: u.kind == .partialRead)
        // The row's own terms: never its CP when that CP is in doubt (no HP then means no term).
        let readTerms = own ? hp(r.hp) : cp(r.cp)
        switch u.kind {
        case .megaPair:
            guard let base = candidates.first else { return Part(names: [name(r)], terms: readTerms) }
            return Part(names: [name(base.row)], terms: candidates.flatMap { cp($0.row.cp) })
        case .evolved, .poweredUp:
            return Part(names: candidates.map { name($0.row) } + [name(r)], terms: candidates.flatMap { cp($0.row.cp) } + readTerms)
        default:
            return Part(names: [name(r)], terms: readTerms)
        }
    }
}
