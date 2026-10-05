import Foundation
import PogoBox
import PogoReader

/// What the Box screen needs from a saved box, worked out once per box load or save (never per keystroke or per row):
/// the species groups, best IV, top CP, counts and the lowercase search keys. 15,000 entries is the storage cap, so
/// nothing in here walks the box more than once per call, and a search only runs the one predicate over the items.
struct BoxIndex {
    struct Item {
        var id: String
        /// Name with form in brackets, as the rows show it ("Zamazenta (Hero)").
        var title: String
        /// The lowercase name the game's search takes ("staraptor"); the form is not part of it.
        var name: String
        /// Lowercase text a typed search is matched against: the title and the display name with its form ("Mega Charizard X", "Alolan Raichu"), so "mega" or "alola" find them.
        var key: String
        /// 0 when the CP is not known (a Mega-when-scanned entry).
        var cp: Int
        /// What the game search needs besides the name and CP (see `GameSearch.part(name:cp:hp:noLevelFits:)`).
        var hp: Int?
        var noLevelFits: Bool
        var ivs: String?
        var ivSum: Int?
        var pct: Int? { ivSum.map { Int((Double($0) / 45 * 100).rounded()) } }
        var needsCheck: Bool
        var fixed: Bool
        /// The entry has a Mega form with a known CP. It is still one Pokémon, and every figure here (CP, best IV, top CP) is its normal form's.
        var hasMega = false
    }

    struct Group {
        var title: String
        var letter: String
        /// Positions in `items`, best IVs first.
        var members: [Int]
        var stats: Stats
    }

    struct Stats: Equatable {
        var count = 0
        var bestPct: Int?
        var topCP: Int?
        var toCheck = 0
    }

    var items: [Item] = []
    /// By species title, A to Z.
    var groups: [Group] = []
    /// Item positions by the game-search name, to count what a name and CP search would also show.
    var byName: [String: [Int]] = [:]
    var toCheckCount = 0
    var fixedCount = 0
    var count: Int { items.count }
    /// Distinct species (by Pokédex number, so a regional form or a Mega is the same species as its base), not the species-and-form rows the list shows.
    private(set) var speciesCount = 0

    static let empty = BoxIndex()

    init() {}

    init(entries: [BoxEntry]) {
        items.reserveCapacity(entries.count)
        var byTitle = [String: [Int]]()
        var species = Set<String>()
        for e in entries {
            let r = e.row, title = r.title
            let sum = r.ivs.map { $0.atk + $0.def + $0.hp }
            let mega = e.shownMegaForm
            let key = title.lowercased() + "|" + r.display.lowercased() + (mega.map { "|" + $0.title.lowercased() + "|" + $0.display.lowercased() } ?? "")
            var item = Item(id: e.id, title: title, name: r.name.lowercased(), key: key, cp: r.cp, hp: r.hp, noLevelFits: GameSearch.noLevelFits(r.flags), ivs: r.ivs.map { "\($0.atk)/\($0.def)/\($0.hp)" }, ivSum: sum,
                            needsCheck: e.needsCheck, fixed: e.isHandCorrected)
            item.hasMega = mega != nil
            if item.needsCheck { toCheckCount += 1 }
            if item.fixed { fixedCount += 1 }
            species.insert(r.dex.map { "dex\($0)" } ?? r.name.lowercased())
            byTitle[title, default: []].append(items.count)
            byName[item.name, default: []].append(items.count)
            items.append(item)
        }
        let all = items
        let order = { (a: Int, b: Int) -> Bool in
            let x = all[a], y = all[b]
            if x.ivSum != y.ivSum { return (x.ivSum ?? -1) > (y.ivSum ?? -1) }
            if x.cp != y.cp { return x.cp > y.cp }
            return x.id < y.id
        }
        var built = [Group]()
        built.reserveCapacity(byTitle.count)
        for (title, members) in byTitle {
            let sorted = members.sorted(by: order)
            built.append(Group(title: title, letter: Self.letter(of: title), members: sorted, stats: Self.stats(of: sorted, in: all)))
        }
        groups = built
        speciesCount = species.count
        groups.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func letter(of title: String) -> String {
        guard let c = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased().first, c.isASCII, c.isLetter else { return "#" }
        return String(c)
    }

    func stats(of members: [Int]) -> Stats { Self.stats(of: members, in: items) }

    static func stats(of members: [Int], in items: [Item]) -> Stats {
        var s = Stats(count: members.count)
        for i in members {
            let it = items[i]
            if let p = it.pct, p > (s.bestPct ?? -1) { s.bestPct = p }
            if it.cp > 0, it.cp > (s.topCP ?? 0) { s.topCP = it.cp }
            if it.needsCheck { s.toCheck += 1 }
        }
        return s
    }

    // MARK: filtering

    enum Chip: Hashable { case all, toCheck, fixed }

    enum Query: Hashable {
        case none
        case text(String)
        case cp(ClosedRange<Int>)

        /// "staraptor", "2819" (an exact CP), "cp2819" or "cp1500-2500". Anything else is a piece of a name.
        init(_ raw: String) {
            let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if q.isEmpty { self = .none; return }
            if let n = Int(q) { self = .cp(n...n); return }
            if q.hasPrefix("cp") {
                let rest = q.dropFirst(2).replacingOccurrences(of: "–", with: "-")
                if let n = Int(rest) { self = .cp(n...n); return }
                let parts = rest.split(separator: "-", omittingEmptySubsequences: false)
                if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) { self = .cp(min(a, b)...max(a, b)); return }
            }
            self = .text(q)
        }
        var isEmpty: Bool { self == .none }
    }

    func matches(_ it: Item, _ query: Query, _ chip: Chip) -> Bool {
        switch chip {
        case .all: break
        case .toCheck: if !it.needsCheck { return false }
        case .fixed: if !it.fixed { return false }
        }
        switch query {
        case .none: return true
        case .text(let t): return it.key.contains(t)
        case .cp(let r): return it.cp > 0 && r.contains(it.cp)
        }
    }

    /// The members of a species that pass the chip and the search, still best IVs first.
    func members(of title: String, query: Query, chip: Chip) -> [Int] {
        guard let g = groups.first(where: { $0.title == title }) else { return [] }
        if query.isEmpty, chip == .all { return g.members }
        return g.members.filter { matches(items[$0], query, chip) }
    }

    // MARK: rows and sections

    enum Sort: String, CaseIterable { case name, topCP }

    struct Row: Identifiable {
        var id: String { title }
        var title: String
        var stats: Stats
    }
    struct Section: Identifiable {
        var id: String
        /// The jump index's short label ("S", "2k").
        var short: String
        /// The heading above the rows.
        var heading: String
        var rows: [Row]
    }

    /// Species rows grouped under A to Z (or CP bands). With a search or a chip, a row shows the figures of the Pokémon that pass it.
    func sections(query: Query, chip: Chip, sort: Sort) -> [Section] {
        let filtered = !query.isEmpty || chip != .all
        var rows = [Row]()
        rows.reserveCapacity(groups.count)
        for g in groups {
            if !filtered { rows.append(Row(title: g.title, stats: g.stats)); continue }
            let m = g.members.filter { matches(items[$0], query, chip) }
            if !m.isEmpty { rows.append(Row(title: g.title, stats: stats(of: m))) }
        }
        switch sort {
        case .name:
            var out = [Section]()
            for r in rows {
                let l = Self.letter(of: r.title)
                if out.last?.id == l { out[out.count - 1].rows.append(r) } else { out.append(Section(id: l, short: l, heading: l, rows: [r])) }
            }
            return out
        case .topCP:
            rows.sort { a, b in
                let x = a.stats.topCP ?? 0, y = b.stats.topCP ?? 0
                return x != y ? x > y : a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
            var out = [Section]()
            for r in rows {
                let b = Self.band(r.stats.topCP)
                if out.last?.id == b.id { out[out.count - 1].rows.append(r) } else { out.append(Section(id: b.id, short: b.short, heading: b.heading, rows: [r])) }
            }
            return out
        }
    }

    /// CP bands for the CP sort: by a species' top CP.
    static func band(_ cp: Int?) -> (id: String, short: String, heading: String) {
        guard let cp, cp > 0 else { return ("none", "–", "CP not known") }
        let lows = [4000, 3000, 2500, 2000, 1500, 1000, 500, 0]
        let low = lows.first { cp >= $0 } ?? 0
        let ceiling = [4000: "4,000 and up", 3000: "3,000 to 3,999", 2500: "2,500 to 2,999", 2000: "2,000 to 2,499", 1500: "1,500 to 1,999", 1000: "1,000 to 1,499", 500: "500 to 999", 0: "Under 500"]
        let short = [4000: "4k+", 3000: "3k", 2500: "2.5k", 2000: "2k", 1500: "1.5k", 1000: "1k", 500: "500", 0: "0"]
        return ("cp\(low)", short[low] ?? "", "CP " + (ceiling[low] ?? ""))
    }

    // MARK: the game search for picked Pokémon

    struct PickedSearch: Equatable {
        /// The search, built by `GameSearch` like every other one in the app. nil when none of the picked can be searched for.
        var text: String?
        /// How many of the picked it covers.
        var covered: Int
        /// Other Pokémon in this box that the search also matches: the same name and one of the CPs (or HPs) in it, and not picked. Counted from the saved box.
        var extra: Int
        /// Picked Pokémon with no CP or HP to search for (no CP, or a CP that fits no level and no HP), which the search leaves out.
        var notCovered: Int
    }

    /// `picked` are item positions in the order the list shows them.
    func gameSearch(picked: [Int]) -> PickedSearch {
        let parts = picked.map { i -> GameSearch.Part in let it = items[i]; return GameSearch.part(name: it.name, cp: it.cp, hp: it.hp, noLevelFits: it.noLevelFits) }
        let covered = GameSearch.covered(parts)
        var names = [String](), cps = Set<Int>(), hps = Set<Int>()
        for (n, p) in parts.enumerated() where p.covered {
            let it = items[picked[n]]
            if !names.contains(it.name) { names.append(it.name) }
            if it.noLevelFits { if let h = it.hp { hps.insert(h) } } else { cps.insert(it.cp) }
        }
        var shown = 0
        for n in names { for i in byName[n] ?? [] where cps.contains(items[i].cp) || items[i].hp.map(hps.contains) == true { shown += 1 } }
        return PickedSearch(text: GameSearch.text(parts), covered: covered, extra: max(0, shown - covered), notCovered: picked.count - covered)
    }
}

/// Owns the current `BoxIndex`: rebuilt when the box is loaded or saved (a new version), away from the main thread for a large box.
@MainActor
final class BoxIndexStore: ObservableObject {
    @Published private(set) var index = BoxIndex.empty
    /// Bumped on each rebuild, so a view can recompute what it derived from the index.
    @Published private(set) var version = 0
    private var builtFor: String?

    func refresh(key: String, entries: [BoxEntry]) async {
        guard builtFor != key else { return }
        let built: BoxIndex
        if entries.count < 2000 {
            built = BoxIndex(entries: entries)
        } else {
            built = await Task.detached(priority: .userInitiated) { BoxIndex(entries: entries) }.value
        }
        guard !Task.isCancelled else { return }
        index = built; builtFor = key; version += 1
    }

    #if DEBUG
    /// DEBUG only: put a ready-made index in place (the synthetic 15,000 box).
    func install(_ built: BoxIndex, key: String) { index = built; builtFor = key; version += 1 }
    #endif
}

/// What the last Save changed, from numbers the app really has when it saves: the box before and the box after.
struct SaveSummary: Equatable {
    var account: String
    var seq: Int
    var date: Date
    var added: Int
    var updated: Int
    var removed: Int
    /// False for a scan read again: its box is the one from before that scan, so counts against it would not describe what the person's box did.
    var showsCounts: Bool

    init(base: [BoxEntry], saved: BoxSnapshot, showsCounts: Bool = true) {
        self.showsCounts = showsCounts
        account = saved.account; seq = saved.seq; date = saved.createdAt
        var before = [String: BoxEntry](minimumCapacity: base.count)
        for e in base { before[e.id] = e }
        var kept = Set<String>(), a = 0, u = 0
        for e in saved.entries {
            kept.insert(e.id)
            guard let o = before[e.id] else { a += 1; continue }
            // Position, frames and when it was last seen change on every scan: only what the box shows counts as an update.
            let (x, y) = (e.row, o.row)
            if x.cp != y.cp || x.hp != y.hp || x.ivs != y.ivs || x.level != y.level || x.speciesId != y.speciesId || x.name != y.name || x.form != y.form
                || x.flags != y.flags || e.corrections != o.corrections || e.megaWhenScanned != o.megaWhenScanned { u += 1 }
        }
        added = a; updated = u; removed = base.reduce(0) { kept.contains($1.id) ? $0 : $0 + 1 }
    }
}

#if DEBUG
extension BoxIndex {
    /// A synthetic 15,000-entry box of 412 species for the performance check (`-box-synthetic`): 36 or so of each, with a
    /// few to check, a few fixed by hand and some not seen.
    static func syntheticEntries(_ n: Int = 15_000, species: Int = 412) -> [BoxEntry] {
        let syl = ["ra", "ki", "so", "mu", "ta", "ne", "lo", "pi", "zu", "ba", "chi", "ven", "dra", "fo", "gla", "hy"]
        var names = [String]()
        for i in 0..<species { names.append((syl[i % 16] + syl[(i / 16) % 16] + syl[(i / 7 + i) % 16]).capitalized) }
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        return (0..<n).map { i in
            let name = names[next() % species]
            let iv = IVs(atk: next() % 16, def: next() % 16, hp: next() % 16)
            var flags = [String]()
            if next() % 38 == 0 { flags.append("single-read") }
            let row = ScanRow(index: i + 1, name: name, display: name, form: "Normal", speciesId: name.lowercased(), dex: nil, cp: 10 + next() % 4500, hp: 50 + next() % 150,
                              ivs: iv, ivsRead: iv, ivsGuess: nil, level: Double(1 + next() % 50), levelMax: nil, dust: 1000, solveStatus: "exact", flags: flags, frames: [])
            let corrected = next() % 90 == 0
            return BoxEntry(id: "syn-\(i)", row: row, firstSeen: base, lastSeen: next() % 40 == 0 ? base.addingTimeInterval(-86_400) : base,
                            corrections: corrected ? Corrections(cp: Fix(was: nil)) : Corrections())
        }
    }

    /// Builds the synthetic index and times the pieces; the result line goes to the log and to the Box screen's `bench-result` label.
    static func bench() -> (BoxIndex, String) {
        func ms(_ since: Date) -> String { String(format: "%.1f", Date().timeIntervalSince(since) * 1000) }
        let entries = syntheticEntries()
        var t = Date()
        let index = BoxIndex(entries: entries)
        let build = ms(t)
        t = Date()
        let all = index.sections(query: .none, chip: .all, sort: .name)
        let sectionsAll = ms(t)
        t = Date()
        let name = index.sections(query: Query("ra"), chip: .all, sort: .name)
        let searchName = ms(t)
        t = Date()
        let range = index.sections(query: Query("cp1500-2500"), chip: .all, sort: .topCP)
        let searchRange = ms(t)
        let line = "BoxIndex 15,000 entries: build \(build) ms (\(index.speciesCount) species), sections \(sectionsAll) ms (\(all.count) letters), search \"ra\" \(searchName) ms (\(name.reduce(0) { $0 + $1.rows.count }) species), search cp1500-2500 by CP \(searchRange) ms (\(range.reduce(0) { $0 + $1.rows.count }) species)"
        NSLog("%@", line)
        return (index, line)
    }
}
#endif
