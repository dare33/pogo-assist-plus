import Foundation
import PogoReader

/// Design pass 2: the Collection screen's numbers (rules 25 and 26). Pure: the box, the game master and the advice come in as arguments.
public enum HubCollection {
    // MARK: rule 25: species and regions

    /// A species released in Pokémon GO: one per dex number (`released`; Mega, Shadow and `duplicate` entries are not separate species).
    public struct ReleasedSpecies: Equatable {
        public var dex: Int
        public var id: String
        public var name: String
        public var tags: [String]
    }

    /// One per dex number, the plain species rather than a form when the file lists both (`pikachu` before `pikachu_libre`: a form has a bracket in
    /// its game master name, so ids such as `mr_mime` and `ho_oh` are plain); in dex order. A dex number in `owned` always counts, even where PvPoke
    /// flags it unreleased (Ditto, Shedinja, ...): a box that holds a species has it, so owned never exceeds the total.
    public static func releasedSpecies(gm: GameMaster, owned: Set<Int> = []) -> [ReleasedSpecies] {
        func isPlain(_ s: GameMaster.Species) -> Bool { GameMaster.nameAndForm(s.name).form.isEmpty }
        func skipped(_ s: GameMaster.Species) -> Bool { s.tags.contains("shadow") || s.tags.contains("mega") || s.tags.contains("duplicate") }
        var byDex = [Int: ReleasedSpecies]()
        for s in gm.ordered where s.released && !skipped(s) {
            if byDex[s.dex] == nil || isPlain(s) { byDex[s.dex] = ReleasedSpecies(dex: s.dex, id: s.id, name: s.name, tags: s.tags) }
        }
        var extra = [Int: ReleasedSpecies]()
        for s in gm.ordered where owned.contains(s.dex) && byDex[s.dex] == nil && !skipped(s) {
            if extra[s.dex] == nil || isPlain(s) { extra[s.dex] = ReleasedSpecies(dex: s.dex, id: s.id, name: s.name, tags: s.tags) }
        }
        return byDex.merging(extra) { a, _ in a }.values.sorted { $0.dex < $1.dex }
    }

    public static let regions: [(name: String, dex: ClosedRange<Int>)] = [
        ("Kanto", 1...151), ("Johto", 152...251), ("Hoenn", 252...386), ("Sinnoh", 387...493), ("Unova", 494...649),
        ("Kalos", 650...721), ("Alola", 722...809), ("Galar", 810...905), ("Paldea", 906...1025),
    ]

    public static func region(ofDex dex: Int) -> String? { regions.first { $0.dex.contains(dex) }?.name }

    /// The dex numbers of the box: a copy owns its species whatever its form (a Shadow or Mega copy of a species counts).
    public static func ownedDex(entries: [BoxEntry], gm: GameMaster) -> Set<Int> {
        Set(entries.compactMap { gm.byId[$0.row.speciesId]?.dex })
    }

    public struct RegionRow: Equatable { public var name: String; public var owned: Int; public var total: Int }

    public struct Overview: Equatable {
        public var owned: Int
        public var released: Int
        public var regions: [RegionRow]
        /// Missing species with an earlier family member in the box.
        public var canEvolve: Int
        public var percent: Int { released == 0 ? 0 : Int((Double(owned) / Double(released) * 100).rounded()) }
    }

    public static func overview(entries: [BoxEntry], gm: GameMaster) -> Overview {
        let owned = ownedDex(entries: entries, gm: gm), released = releasedSpecies(gm: gm, owned: owned)
        let rows = regions.map { r -> RegionRow in
            let all = released.filter { r.dex.contains($0.dex) }
            return RegionRow(name: r.name, owned: all.filter { owned.contains($0.dex) }.count, total: all.count)
        }
        let missing = missingSpecies(entries: entries, advice: BoxAdvice(), gm: gm)
        return Overview(owned: released.filter { owned.contains($0.dex) }.count, released: released.count, regions: rows, canEvolve: missing.filter { $0.evolvesFrom != nil }.count)
    }

    // MARK: Missing

    public struct MissingSpecies: Equatable {
        public var dex: Int
        public var name: String
        public var region: String
        /// "you can evolve": the name of the nearest earlier family member in the box; nil when none is.
        public var evolvesFrom: String?
        /// How to get it, when known: the research's obtain text for the species' gap, else Mythical or Legendary; "" otherwise.
        public var how: String
    }

    /// Released species with no copy in the box, in dex order.
    public static func missingSpecies(entries: [BoxEntry], advice: BoxAdvice, gm: GameMaster) -> [MissingSpecies] {
        let owned = ownedDex(entries: entries, gm: gm)
        func ancestorOwned(_ id: String) -> String? {
            var cur = gm.byId[id]?.parent, steps = 0
            while let c = cur, steps < 4 {
                if let s = gm.byId[c], owned.contains(s.dex) { return s.name }
                cur = gm.byId[c]?.parent; steps += 1
            }
            return nil
        }
        return releasedSpecies(gm: gm, owned: owned).filter { !owned.contains($0.dex) }.map { s in
            let from = ancestorOwned(s.id)
            let how: String
            if let from { how = "Evolve from \(from) (you have one)" }
            else if let o = advice.gaps.first(where: { $0.speciesId == s.id && !($0.obtain ?? "").isEmpty })?.obtain { how = o }
            else if s.tags.contains("mythical") { how = "Mythical" }
            else if s.tags.contains("legendary") { how = "Legendary" }
            else { how = "" }
            return MissingSpecies(dex: s.dex, name: s.name, region: region(ofDex: s.dex) ?? "", evolvesFrom: from, how: how)
        }
    }

    // MARK: rule 26: Showcase

    /// A copy's IV % (the three IVs over 45); nil when its IVs are not read.
    static func ivPercent(_ e: BoxEntry) -> Double? { e.row.ivs.map { Double($0.atk + $0.def + $0.hp) / 45 * 100 } }

    /// Each species' best copy by IV %, ties by CP, the first twelve. A species is one dex number (the Collection term: a Shadow, Mega or form copy
    /// competes with the rest of its dex number). A copy whose IVs are not read cannot be ranked and is left out. A remaining tie is broken by entry id so the
    /// order is stable.
    public static func showcase(entries: [BoxEntry], gm: GameMaster, limit: Int = 12) -> [BoxEntry] {
        func better(_ a: BoxEntry, _ b: BoxEntry) -> Bool {
            let (x, y) = (ivPercent(a) ?? -1, ivPercent(b) ?? -1)
            if x != y { return x > y }
            if a.row.cp != b.row.cp { return a.row.cp > b.row.cp }
            return a.id < b.id
        }
        func key(_ e: BoxEntry) -> String { gm.byId[e.row.speciesId].map { "dex \($0.dex)" } ?? "id \(e.row.speciesId)" }
        var best = [String: BoxEntry]()
        for e in entries where ivPercent(e) != nil {
            if let cur = best[key(e)], !better(e, cur) { continue }
            best[key(e)] = e
        }
        return Array(best.values.sorted(by: better).prefix(limit))
    }

    // MARK: Special sets

    public struct SpecialSet: Equatable {
        public var name: String
        public var owned: Int?
        /// nil for a count of copies with no species total.
        public var total: Int?
        /// "copies" or "species".
        public var unit: String
        /// "Not in your scans yet" for Lucky while no copy carries the mark; nil otherwise.
        public var note: String?
    }

    /// Counts for the named groups. 100% IVs, Lucky and Shadow count copies; Legendary, Mythical, Ultra Beasts and Mega-capable count species (owned of
    /// released). `isLucky` reads the copy's Lucky mark (the data model adds it); while no copy is marked the Lucky tile has no count.
    public static func specialSets(entries: [BoxEntry], gm: GameMaster, isLucky: (BoxEntry) -> Bool = { _ in false }) -> [SpecialSet] {
        let ownedDex = ownedDex(entries: entries, gm: gm)
        let released = releasedSpecies(gm: gm, owned: ownedDex)
        func species(_ tag: String) -> SpecialSet {
            let ids = released.filter { $0.tags.contains(tag) }
            return SpecialSet(name: "", owned: ids.filter { ownedDex.contains($0.dex) }.count, total: ids.count, unit: "species", note: nil)
        }
        var megaDex = Set<Int>()
        for s in gm.ordered where s.released && s.tags.contains("mega") { megaDex.insert(s.dex) }
        func named(_ n: String, _ s: SpecialSet) -> SpecialSet { var s = s; s.name = n; return s }
        let hundos = entries.filter { $0.row.ivs.map { $0.atk == 15 && $0.def == 15 && $0.hp == 15 } ?? false }.count
        let lucky = entries.filter(isLucky).count
        return [
            SpecialSet(name: "100% IVs", owned: hundos, total: nil, unit: "copies", note: nil),
            named("Legendary", species("legendary")), named("Mythical", species("mythical")), named("Ultra Beasts", species("ultrabeast")),
            SpecialSet(name: "Mega-capable", owned: ownedDex.intersection(megaDex).count, total: megaDex.count, unit: "species", note: nil),
            lucky == 0 ? SpecialSet(name: "Lucky", owned: nil, total: nil, unit: "copies", note: "Not in your scans yet") : SpecialSet(name: "Lucky", owned: lucky, total: nil, unit: "copies", note: nil),
            SpecialSet(name: "Shadow", owned: entries.filter { $0.row.shadow == 1 }.count, total: nil, unit: "copies", note: nil),
        ]
    }
}
