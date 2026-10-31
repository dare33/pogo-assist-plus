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
        /// The game master's tags for the species ("legendary", "mythical", "ultrabeast", ...), for the Missing summary's breakdown.
        public var tags: [String] = []
    }

    /// The Missing section's summary card (Greg, 31 Oct 2026: "a bit of a summary card"): how many species are missing and a short breakdown. The breakdown
    /// counts overlap by design (a Legendary can also be one you can evolve), so each reads as "of the missing, this many are ...".
    public struct MissingSummary: Equatable {
        public var count: Int
        /// An earlier family member is in the box.
        public var canEvolve: Int
        public var legendary: Int
        public var mythical: Int
        /// The region with the most species missing (the earlier region on a tie); nil when none is missing.
        public var topRegion: (name: String, count: Int)?

        public static func == (a: MissingSummary, b: MissingSummary) -> Bool {
            a.count == b.count && a.canEvolve == b.canEvolve && a.legendary == b.legendary && a.mythical == b.mythical && a.topRegion?.name == b.topRegion?.name && a.topRegion?.count == b.topRegion?.count
        }

        /// The short breakdown, parts with a count of zero left out: "12 you can evolve now", "9 Legendary", "3 Mythical", "most in Paldea (40)".
        public var parts: [String] {
            var out = [String]()
            if canEvolve > 0 { out.append("\(canEvolve) you can evolve now") }
            if legendary > 0 { out.append("\(legendary) Legendary") }
            if mythical > 0 { out.append("\(mythical) Mythical") }
            if let t = topRegion { out.append("most in \(t.name) (\(t.count))") }
            return out
        }
    }

    public static func missingSummary(_ missing: [MissingSpecies]) -> MissingSummary {
        var byRegion = [String: Int]()
        for m in missing { byRegion[m.region, default: 0] += 1 }
        let top = regions.compactMap { r in byRegion[r.name].map { (name: r.name, count: $0) } }.reduce(nil as (name: String, count: Int)?) { best, r in
            if let b = best, b.count >= r.count { return b } else { return r }
        }
        return MissingSummary(count: missing.count, canEvolve: missing.filter { $0.evolvesFrom != nil }.count,
                              legendary: missing.filter { $0.tags.contains("legendary") }.count, mythical: missing.filter { $0.tags.contains("mythical") }.count, topRegion: top)
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
            return MissingSpecies(dex: s.dex, name: s.name, region: region(ofDex: s.dex) ?? "", evolvesFrom: from, how: how, tags: s.tags)
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
        /// The unit as it reads after the count: "1 copy", "6 copies", "3 of 52 species".
        public var unitWord: String { unit == "copies" && owned == 1 ? "copy" : unit }
    }

    /// The eleven groups, in the order the Collection shows them. Shiny and Background are placeholders until a scan reads them (`isComingSoon`).
    public enum SetKind: String, CaseIterable, Hashable, Identifiable {
        case hundo = "Hundo", legendary = "Legendary", mythical = "Mythical", ultraBeasts = "Ultra Beasts", megaCapable = "Mega-capable", lucky = "Lucky", shadow = "Shadow",
             dynamax = "Dynamax", gigantamax = "Gigantamax", shiny = "Shiny", background = "Background"
        public var name: String { rawValue }
        public var id: String { rawValue }
        /// Legendary, Mythical, Ultra Beasts and Mega-capable are species sets: the card counts owned species of released, and the list shows each owned species'
        /// copies (all of them for the first three; for Mega-capable only the copies that can Mega Evolve). The others count copies.
        public var isSpeciesSet: Bool {
            switch self {
            case .legendary, .mythical, .ultraBeasts, .megaCapable: return true
            case .hundo, .lucky, .shadow, .dynamax, .gigantamax, .shiny, .background: return false
            }
        }
        /// The box holds no data for the set yet, so its card says "Coming soon" and it has no list (Greg, 31 Oct 2026).
        public var isComingSoon: Bool { self == .shiny || self == .background }
    }

    /// The note a set carries while the box holds no data for it.
    public static let comingSoon = "Coming soon"

    /// A copy's Lucky mark: the one definition the set, its list and the My Pokémon search read.
    public static func isLuckyMarked(_ e: BoxEntry) -> Bool { e.row.lucky == true }

    /// A copy's Shadow state: the hand mark wins when it is set (1 Shadow, 2 Purified, 0 neither); only a copy with no mark is a Shadow by its `_shadow` species id.
    /// The one definition the Shadow set, Mega-capable and the search read.
    public static func isShadow(_ row: ScanRow) -> Bool {
        switch row.shadow {
        case 1?: return true
        case .some: return false
        case nil: return row.speciesId.hasSuffix("_shadow")
        }
    }

    /// Which sets a copy belongs to: the single definition behind a card's count, the list that opens from it and the My Pokémon search words. Legendary, Mythical and
    /// Ultra Beasts hold a copy of any form of the species (the dex number is the species, as everywhere on the Collection); `released` includes an owned species PvPoke
    /// flags unreleased, so the sets and the species totals agree. Mega-capable is the copy's own: its species-form has a Mega Evolution in the game master and it is not
    /// a Shadow (a Shadow Pokémon cannot Mega Evolve), so Galarian Slowbro, Armored Mewtwo, Alolan Raichu and any Shadow copy are out.
    public struct Membership {
        let tagDex: [SetKind: Set<Int>]
        /// Species ids that have a Mega Evolution (or Primal Reversion): `charizard` for `charizard_mega_x`.
        let megaIds: Set<String>
        let megaTotal: Int
        let gm: GameMaster
        let isLucky: (BoxEntry) -> Bool

        public init(entries: [BoxEntry], gm: GameMaster, isLucky: @escaping (BoxEntry) -> Bool = HubCollection.isLuckyMarked) {
            self.gm = gm; self.isLucky = isLucky
            let released = HubCollection.releasedSpecies(gm: gm, owned: HubCollection.ownedDex(entries: entries, gm: gm))
            func dex(_ tag: String) -> Set<Int> { Set(released.filter { $0.tags.contains(tag) }.map(\.dex)) }
            var megaDex = Set<Int>(), ids = Set<String>()
            for s in gm.ordered where s.released && s.tags.contains("mega") {
                megaDex.insert(s.dex)
                for suffix in ["_mega_x", "_mega_y", "_mega", "_primal"] where s.id.hasSuffix(suffix) { ids.insert(String(s.id.dropLast(suffix.count))); break }
            }
            megaIds = ids; megaTotal = megaDex.count
            tagDex = [.legendary: dex("legendary"), .mythical: dex("mythical"), .ultraBeasts: dex("ultrabeast")]
        }

        /// The species total of a species set (nil for a set of copies).
        public func total(_ kind: SetKind) -> Int? { kind == .megaCapable ? megaTotal : (kind.isSpeciesSet ? tagDex[kind]?.count ?? 0 : nil) }

        public func kinds(of e: BoxEntry) -> Set<SetKind> {
            var out = Set<SetKind>()
            if let v = e.row.ivs, v.atk == 15, v.def == 15, v.hp == 15 { out.insert(.hundo) }
            if let dex = gm.byId[e.row.speciesId]?.dex {
                for (k, set) in tagDex where set.contains(dex) { out.insert(k) }
            }
            let shadow = HubCollection.isShadow(e.row)
            // A Purified copy of a `_shadow` species is the plain species again, so its Mega is looked up by the id without the suffix.
            let id = e.row.speciesId.hasSuffix("_shadow") ? String(e.row.speciesId.dropLast("_shadow".count)) : e.row.speciesId
            if shadow { out.insert(.shadow) } else if megaIds.contains(id) { out.insert(.megaCapable) }
            if isLucky(e) { out.insert(.lucky) }
            // The Dynamax and Gigantamax sets read the marks the box already has: the hand marks and the Dynamax and Gigantamax passes both set `row.dynamax` / `row.gigantamax`.
            if e.row.dynamax == true { out.insert(.dynamax) }
            if e.row.gigantamax == true { out.insert(.gigantamax) }
            return out
        }
    }

    /// The copies in a set, in box order: what the Collection's card counts and what its list shows.
    public static func members(of kind: SetKind, entries: [BoxEntry], gm: GameMaster, isLucky: @escaping (BoxEntry) -> Bool = isLuckyMarked) -> [BoxEntry] {
        let m = Membership(entries: entries, gm: gm, isLucky: isLucky)
        return entries.filter { m.kinds(of: $0).contains(kind) }
    }

    /// Counts for the named groups, read from `Membership`. Hundo (15/15/15, once called 100% IVs), Lucky and Shadow count copies (a Shadow follows `isShadow`: the hand mark when there is one, else a `_shadow` species); Legendary, Mythical, Ultra Beasts and Mega-capable count species (owned of
    /// released). `isLucky` reads the copy's Lucky mark (the data model adds it); while no copy is marked the Lucky tile has no count.
    public static func specialSets(entries: [BoxEntry], gm: GameMaster, isLucky: @escaping (BoxEntry) -> Bool = isLuckyMarked) -> [SpecialSet] {
        let m = Membership(entries: entries, gm: gm, isLucky: isLucky)
        var copies = [SetKind: Int](), dexes = [SetKind: Set<Int>]()
        for e in entries {
            let dex = gm.byId[e.row.speciesId]?.dex
            for k in m.kinds(of: e) {
                copies[k, default: 0] += 1
                if let dex { dexes[k, default: []].insert(dex) }
            }
        }
        return SetKind.allCases.map { k in
            if k.isComingSoon { return SpecialSet(name: k.name, owned: nil, total: nil, unit: "copies", note: comingSoon) }
            if k.isSpeciesSet { return SpecialSet(name: k.name, owned: dexes[k]?.count ?? 0, total: m.total(k), unit: "species", note: nil) }
            let n = copies[k] ?? 0
            if k == .lucky && n == 0 { return SpecialSet(name: k.name, owned: nil, total: nil, unit: "copies", note: "Not in your scans yet") }
            return SpecialSet(name: k.name, owned: n, total: nil, unit: "copies", note: nil)
        }
    }
}

// MARK: rule 26: the Special sets strips

extension HubCollection {
    /// How well a copy does one activity, comparable: the advisor's tag (Strong, OK, Weak) first, then the tier of its table entry (S before A before B).
    /// `level` 0 is "not in that activity's tables".
    public struct ActivityRank: Equatable, Comparable {
        public var level: Int
        public var tier: Int
        public var words: String
        public static let none = ActivityRank(level: 0, tier: 9, words: "")
        /// Equal ranks tie whatever they are called ("Raids S" and "Max S"), so the order they give is consistent.
        public static func == (a: ActivityRank, b: ActivityRank) -> Bool { a.level == b.level && a.tier == b.tier }
        public static func < (a: ActivityRank, b: ActivityRank) -> Bool { a.level != b.level ? a.level < b.level : a.tier > b.tier }
    }

    /// The activities a set's strip can be ranked by. Raids and Max read the advisor's fit for the area; PvP reads the best Great or Ultra League card's worth.
    public enum Activity: String { case raids, gym, rocket, max, pvp
        var label: String { self == .pvp ? "PvP" : rawValue.capitalized }
    }

    public static func rank(_ e: BoxEntry, in activity: Activity, advice: BoxAdvice, pogoAssist: Bool = false) -> ActivityRank {
        if activity == .pvp {
            var best = ActivityRank.none
            for key in MyPokemon.pvpLeagues {
                guard let r = advice.leagues[e.id]?[key],
                      let w = LeaguePanel.card(r, shown: LeaguePanel.shownIndex(r, pogoAssist: pogoAssist), key: key, level: e.row.level).worth else { continue }
                let level = w == .strong ? 3 : w == .ok ? 2 : 1
                let cand = ActivityRank(level: level, tier: 9, words: "PvP \(w.label)")
                if cand > best { best = cand }
            }
            return best
        }
        guard let f = advice.fit[e.id]?[activity.rawValue] else { return .none }
        let level = f.tag == .strong ? 3 : f.tag == .ok ? 2 : 1
        let tier = f.tier.flatMap { ["S": 0, "A": 1, "B": 2][$0] } ?? 9
        let words = f.tag == .weak ? "\(activity.label) weak" : "\(activity.label) \(f.tier ?? "")"
        return ActivityRank(level: level, tier: tier, words: words.trimmingCharacters(in: .whitespaces))
    }

    /// What each set's strip is ranked by (Greg, 31 Oct 2026, "Per set"): Dynamax and Gigantamax by Max battle rank; Shadow, Legendary, Mythical, Ultra Beasts and
    /// Mega-capable by raid rank; Hundo, Lucky, Shiny and Background by the best rank in any activity. nil is "any activity".
    public static func rankingActivity(_ kind: SetKind) -> Activity? {
        switch kind {
        case .dynamax, .gigantamax: return .max
        case .shadow, .legendary, .mythical, .ultraBeasts, .megaCapable: return .raids
        case .hundo, .lucky, .shiny, .background: return nil
        }
    }

    /// A copy's rank for a set: that activity's, or the best of Raids, Gym, Rocket, Max and PvP.
    public static func rank(_ e: BoxEntry, for kind: SetKind, advice: BoxAdvice, pogoAssist: Bool = false) -> ActivityRank {
        if let a = rankingActivity(kind) { return rank(e, in: a, advice: advice, pogoAssist: pogoAssist) }
        var best = ActivityRank.none
        for a in [Activity.raids, .gym, .rocket, .max, .pvp] {
            let r = rank(e, in: a, advice: advice, pogoAssist: pogoAssist)
            if r > best { best = r }
        }
        return best
    }

    /// One card of a set's strip.
    public struct StripPick: Equatable {
        public var entry: BoxEntry
        public var rank: ActivityRank
    }

    /// The set's strip: its best Pokémon for the set's activity first. Order: the rank (tag, then tier), then IV % (a copy with no read IVs last), then CP, then entry id
    /// so the order is stable. A species set shows each species once (its best copy), as its card counts species; a set of copies shows copies. The first `limit`.
    /// `members` are the set's copies (`members(of:)`); a set that is coming soon has none.
    public static func strip(kind: SetKind, members: [BoxEntry], gm: GameMaster, advice: BoxAdvice, pogoAssist: Bool = false, limit: Int = 10) -> [StripPick] {
        let picks = members.map { StripPick(entry: $0, rank: rank($0, for: kind, advice: advice, pogoAssist: pogoAssist)) }
        func better(_ a: StripPick, _ b: StripPick) -> Bool {
            if a.rank != b.rank { return a.rank > b.rank }
            let (x, y) = (ivPercent(a.entry) ?? -1, ivPercent(b.entry) ?? -1)
            if x != y { return x > y }
            if a.entry.row.cp != b.entry.row.cp { return a.entry.row.cp > b.entry.row.cp }
            return a.entry.id < b.entry.id
        }
        var chosen = picks
        if kind.isSpeciesSet {
            var best = [String: StripPick]()
            for p in picks {
                let key = gm.byId[p.entry.row.speciesId].map { "dex \($0.dex)" } ?? "id \(p.entry.row.speciesId)"
                if let cur = best[key], !better(p, cur) { continue }
                best[key] = p
            }
            chosen = Array(best.values)
        }
        return Array(chosen.sorted(by: better).prefix(limit))
    }
}
