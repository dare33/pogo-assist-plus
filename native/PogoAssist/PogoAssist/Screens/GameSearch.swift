import Foundation
import PogoBox
import PogoReader

/// The text to paste into the game's storage search: lower-case species names joined by ",", then "&", then the terms joined by ",".
/// "staraptor,moltres,charizard&hp140,hp129,hp118" finds the three names that also have one of the three HPs (a 4 Oct 2026 device check
/// confirmed that in the game "," binds before "&"). A CP term is used only for a CP that can be trusted; for a part-read CP (the CP is what is
/// in doubt) the HP term is used instead.
enum GameSearch {
    /// One question's or one row's contribution: the names and the terms it adds to a shared search.
    struct Part: Equatable {
        var names: [String]
        var terms: [String]
    }

    /// The search for these parts: names, then terms, each without repeats and in first-seen order. nil when there is no name to search for.
    static func text(_ parts: [Part]) -> String? {
        var names = [String](), terms = [String]()
        for p in parts {
            for n in p.names where !n.isEmpty && !names.contains(n) { names.append(n) }
            for t in p.terms where !terms.contains(t) { terms.append(t) }
        }
        guard !names.isEmpty else { return nil }
        let head = names.joined(separator: ",")
        return terms.isEmpty ? head : head + "&" + terms.joined(separator: ",")
    }

    static func name(_ r: ScanRow) -> String { r.name.lowercased() }
    static func cp(_ v: Int) -> [String] { v > 0 ? ["cp\(v)"] : [] }
    static func hp(_ v: Int?) -> [String] { v.map { $0 > 0 ? ["hp\($0)"] : [] } ?? [] }

    /// The row's own CP cannot be trusted: it fits no level, or the merge found it to be a fragment of a saved CP (`partialRead`).
    static func untrusted(_ r: ScanRow, partRead: Bool = false) -> Bool {
        partRead || r.flags.contains { $0 == "no-level-fits" || $0.hasPrefix("no-level-fits:") }
    }

    /// A scanned row on its own (To check): its CP, or its HP when the CP does not fit any level.
    static func part(row r: ScanRow) -> Part {
        Part(names: [name(r)], terms: untrusted(r) && r.hp != nil ? hp(r.hp) : cp(r.cp))
    }

    /// A saved Pokémon (Not seen): its name and CP.
    static func part(saved e: BoxEntry) -> Part { Part(names: [name(e.row)], terms: cp(e.row.cp)) }

    /// An open question: what to look for in the game to answer it.
    /// - evolved and powered up: both CPs (the saved one and the one read now), and both names for an evolution;
    /// - a Mega pair: the CPs of the two saved entries;
    /// - a part read (or a row whose CP fits no level): the HP, because the CP is what is in doubt;
    /// - anything else: the CP read.
    static func part(for u: BoxMerge.Unsure, row r: ScanRow, saved: [String: BoxEntry]) -> Part {
        let candidates = u.candidates.compactMap { saved[$0] }
        let own = untrusted(r, partRead: u.kind == .partialRead)
        switch u.kind {
        case .megaPair:
            guard let base = candidates.first else { return Part(names: [name(r)], terms: cp(r.cp)) }
            return Part(names: [name(base.row)], terms: candidates.flatMap { cp($0.row.cp) })
        case .evolved, .poweredUp:
            let readTerms = own ? hp(r.hp) : cp(r.cp)
            return Part(names: candidates.map { name($0.row) } + [name(r)], terms: candidates.flatMap { cp($0.row.cp) } + readTerms)
        default:
            return Part(names: [name(r)], terms: own ? hp(r.hp) : cp(r.cp))
        }
    }
}
