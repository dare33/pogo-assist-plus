import Foundation
import PogoReader

/// Advice worked out for one evolution family after an edit to one of its copies, so the Pokémon page can answer at once while the whole box's advice is worked out.
///
/// Why this is the same answer as the whole box's: `analyseBox` (`src/advise.js`) works out everything a Pokémon's page reads (its hits and builds, its league
/// ratings, its fit and best-copy tags, its duplicate group and the spares) from that copy and the other copies of the SAME species. The one box-wide result is the
/// gap list, which no edit of a mark touches and the page does not read. A family holds every copy of the edited species (and of its pre-evolutions, its
/// evolutions and its other forms), so the advice of just those rows, merged over the last whole-box advice, equals what the whole box would give for every
/// entry of the family. `FamilyAdviceTests` checks that on the fixture box, field by field.
public extension BoxAdvice {
    /// The root of an evolution chain: the species with no parent (itself when the game master does not know it).
    private static func root(of id: String, gm: GameMaster) -> String {
        var cur = id, seen: Set<String> = [id]
        while let p = gm.byId[cur]?.parent, gm.byId[p] != nil, !seen.contains(p) { seen.insert(p); cur = p }
        return cur
    }

    /// The entries of the edited copy's family: every copy whose species shares its evolution root, and every copy of the same Pokédex number (its other forms), in the
    /// box's order. Includes the copy itself.
    static func family(of copy: BoxEntry, in entries: [BoxEntry], gm: GameMaster) -> [BoxEntry] {
        let top = root(of: copy.row.speciesId, gm: gm), dex = copy.row.dex
        return entries.filter { e in
            e.id == copy.id || (dex != nil && e.row.dex == dex) || root(of: e.row.speciesId, gm: gm) == top
        }
    }

    /// `self` (the advice for the box before the edit, or an earlier family result over it) with the family's part replaced by `family` (the advice of the family's
    /// entries alone). `entries` is the whole box after the edit: it gives the order the advisor's lists keep (builds by score then box position, duplicates by their
    /// number to transfer then their first copy's position). The gaps stay as they were: they are box-wide, and the page does not read them.
    func replacingFamily(ids: Set<String>, with family: BoxAdvice, entries: [BoxEntry]) -> BoxAdvice {
        var pos = [String: Int]()
        for (i, e) in entries.enumerated() { pos[e.id] = i }
        func at(_ id: String) -> Int { pos[id] ?? Int.max }
        var out = self
        // Builds: the advisor sorts by score, ties in box order (a stable sort); a copy's own builds keep the order of the list they came from.
        let all = builds.filter { !ids.contains($0.entryId) } + family.builds.filter { ids.contains($0.entryId) }
        out.builds = all.enumerated().sorted { a, b in
            if a.element.score != b.element.score { return a.element.score > b.element.score }
            let (pa, pb) = (at(a.element.entryId), at(b.element.entryId))
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map(\.element)
        // Duplicate groups are one species: all of it is in the family or none of it.
        func inFamily(_ d: Duplicate) -> Bool { (d.keepIds + d.transferIds).contains { ids.contains($0) } }
        func first(_ d: Duplicate) -> Int { (d.keepIds + d.transferIds).map(at).min() ?? Int.max }
        out.duplicates = (duplicates.filter { !inFamily($0) } + family.duplicates.filter(inFamily)).enumerated().sorted { a, b in
            if a.element.transfer.count != b.element.transfer.count { return a.element.transfer.count > b.element.transfer.count }
            let (fa, fb) = (first(a.element), first(b.element))
            return fa != fb ? fa < fb : a.offset < b.offset
        }.map(\.element)
        out.unresolved = (unresolved.filter { !ids.contains($0) } + family.unresolved.filter { ids.contains($0) }).sorted { at($0) < at($1) }
        func swap<T>(_ mine: [String: T], _ theirs: [String: T]) -> [String: T] {
            var m = mine.filter { !ids.contains($0.key) }
            for (k, v) in theirs where ids.contains(k) { m[k] = v }
            return m
        }
        out.spareBuilds = swap(spareBuilds, family.spareBuilds)
        out.leagues = swap(leagues, family.leagues)
        out.fit = swap(fit, family.fit)
        out.bestOf = swap(bestOf, family.bestOf)
        return out
    }

    /// The advice after an edit of copy `id`, for the page of that copy: `base` with the copy's family worked out again from `entries` (the box after the edit). nil when
    /// the copy is not in the box. Runs the engine on the family's rows only, so it belongs on the engine's worker; the result is for the page and is never saved as the
    /// box version's advice.
    static func afterEdit(of id: String, base: BoxAdvice, entries: [BoxEntry], scanDate: Date, engine: CoreEngine, gm: GameMaster) throws -> BoxAdvice? {
        guard let copy = entries.first(where: { $0.id == id }) else { return nil }
        let members = family(of: copy, in: entries, gm: gm)
        let rows = members.enumerated().map { i, e in var r = e.row; r.index = i + 1; return r }
        let report = try engine.advise(rows: rows, scanDate: scanDate)
        let part = BoxAdvice.make(from: report, entries: members)
        return base.replacingFamily(ids: Set(members.map(\.id)), with: part, entries: entries)
    }
}
