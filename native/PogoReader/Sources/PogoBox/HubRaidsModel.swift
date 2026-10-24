import Foundation

/// The Raids and Max battles screens' derivations: the dated timeline, what to bring against each boss, how many of those counters the
/// box already has built, the sentence that says what to do next, and the Max roster. Pure, so the fixture report and `hub.json` pin
/// them (`HubRaidsModelTests`). Builds are read from the advice report as they are; nothing here touches the game.
public enum HubRaidsModel {
    /// The two screens that show a timeline.
    public enum Screen {
        case raids, max
        /// The kinds of rotation row this screen lists, in the order rows of the same day sort. Super Mega Raid Days are raids; Dynamax
        /// Trails and Max Mondays are Max battles.
        var kinds: [HubData.Kind] {
            switch self {
            case .raids: return [.fiveStar, .mega, .shadow, .battleDay, .raidHour]
            case .max: return [.maxMonday, .maxEvent]
            }
        }
        /// The `BoxAdvice.Build.areas` label that puts a build on this screen.
        var area: String { self == .raids ? "Raids" : "Max" }
    }

    /// One listed row with where it stands today.
    public struct Entry: Equatable {
        public var row: HubData.RotationRow
        /// Today is within `from…to`, both days included.
        public var isNow: Bool
        /// Local calendar days from today to `from`; 0 or less once it has begun.
        public var daysUntil: Int
    }

    // MARK: timeline

    /// The screen's rows from today on (a row whose last day has passed is dropped), by first day then kind. `now` is the rows under way,
    /// `comingUp` the rest.
    public static func timeline(rows: [HubData.RotationRow], screen: Screen, today: String) -> (now: [Entry], comingUp: [Entry]) {
        let kinds = screen.kinds
        let listed = rows.enumerated().compactMap { i, r -> (Int, Int, Entry)? in
            guard let k = kinds.firstIndex(of: r.kind), r.to >= today else { return nil }
            return (k, i, Entry(row: r, isNow: r.from <= today, daysUntil: days(from: today, to: r.from)))
        }
        .sorted { ($0.2.row.from, $0.0, $0.1) < ($1.2.row.from, $1.0, $1.1) }
        .map(\.2)
        return (listed.filter(\.isNow), listed.filter { !$0.isNow })
    }

    /// Whole calendar days from one `yyyy-mm-dd` to another (negative when `to` is earlier); 0 when either does not parse.
    static func days(from a: String, to b: String) -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        func date(_ s: String) -> Date? {
            let p = s.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 ? cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) : nil
        }
        guard let x = date(a), let y = date(b) else { return 0 }
        return cal.dateComponents([.day], from: x, to: y).day ?? 0
    }

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    private static func short(_ key: String) -> (d: Int, m: String)? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return nil }
        return (p[2], months[p[1] - 1])
    }

    /// The timeline's date column: the dates ("28 OCT – 3 NOV", "9 – 24 NOV" inside a month, "26 OCT" for one day) over "now" or "in 6 d".
    public static func dateColumn(_ e: Entry) -> (dates: String, when: String) {
        let when = e.isNow ? "now" : "in \(e.daysUntil) d"
        guard let f = short(e.row.from), let t = short(e.row.to) else { return ("", when) }
        if e.row.from == e.row.to { return ("\(f.d) \(f.m)", when) }
        if f.m == t.m { return ("\(f.d) – \(t.d) \(t.m)", when) }
        return ("\(f.d) \(f.m) – \(t.d) \(t.m)", when)
    }

    /// The small chip beside a row's name; empty for a kind this app does not know.
    public static func kindChip(_ kind: HubData.Kind) -> String {
        switch kind {
        case .fiveStar: return "5★"
        case .mega: return "MEGA"
        case .shadow: return "SHADOW"
        case .battleDay: return "BATTLE DAY"
        case .raidHour: return "RAID HOUR"
        case .maxMonday: return "MAX MON"
        case .maxEvent: return "EVENT"
        case .other: return ""
        }
    }

    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    /// The date column for VoiceOver: "28 October to 3 November, in 3 days"; "26 October, in 1 day"; "21 October to 27 October, now".
    public static func spokenDates(_ e: Entry) -> String {
        func long(_ key: String) -> String? {
            let p = key.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 && (1...12).contains(p[1]) ? "\(p[2]) \(monthNames[p[1] - 1])" : nil
        }
        let when = e.isNow ? "now" : "in \(e.daysUntil) \(e.daysUntil == 1 ? "day" : "days")"
        guard let f = long(e.row.from), let t = long(e.row.to) else { return when }
        return (e.row.from == e.row.to ? f : "\(f) to \(t)") + ", " + when
    }

    /// The last day any row of the screen runs to, as "1 Dec"; nil when there are no rows. The screens' sub line reads "Bosses to 1 Dec".
    public static func lastDay(rows: [HubData.RotationRow], screen: Screen) -> String? {
        guard let last = rows.filter({ screen.kinds.contains($0.kind) }).map(\.to).max(), let d = short(last) else { return nil }
        return "\(d.d) \(d.m.prefix(1))\(d.m.dropFirst().lowercased())"
    }

    /// What a row is called: its bosses joined with " · "; a row still "to be announced" reads its title and says so; a row with no boss
    /// (a Raid Hour, Dynamax Trails) reads its title.
    public static func name(_ row: HubData.RotationRow) -> String {
        // Four forms of one species ("Deoxys", "Deoxys (Speed)", ...) read as one name.
        let bases = Set(row.bosses.map { $0.name.components(separatedBy: " (").first ?? $0.name })
        if row.bosses.count > 2, bases.count == 1, let base = bases.first { return "\(base) (\(row.bosses.count) formes)" }
        if !row.bosses.isEmpty { return row.bosses.map(\.name).joined(separator: " · ") }
        return row.tba == true ? "\(row.title) to be announced" : row.title
    }

    // MARK: bring

    /// At most four attacking types that hit any boss of the row super-effectively: the best multiplier across the bosses first, ties in
    /// the chart's order. Empty for a row with no boss.
    public static func bring(row: HubData.RotationRow, hub: HubData) -> [String] {
        var best = [String: Double]()
        for boss in row.bosses {
            for w in hub.weaknesses(of: boss.types) { best[w.type] = max(best[w.type] ?? 0, w.multiplier) }
        }
        return HubData.typeOrder.enumerated().compactMap { i, t in best[t].map { (i, t, $0) } }
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
            .prefix(4).map(\.1)
    }

    // MARK: built

    /// The tier tables list a build's target under an attacking type; this is the rule the Hub uses for what a counter counts for.
    ///
    /// **Raids.** A counter of type T is a built build (Raids area, nothing left but the Dynamax requirement; a build read without `steps`
    /// is not built, as in `HubModel.needsSomething`) whose TARGET species has a Raids `pve-by-type` entry (tier S, A or B) in the section T.
    /// A build that mega evolves also reads the target's Mega entries (`lucario` counts under Fighting through `lucario_mega`). A target with
    /// Raids entries but none sectioned by a type (a high-tier table) counts for its own species' types; a target the Raids table does not
    /// list counts for nothing. The section, not the species' types, decides: Kartana is Grass/Steel and is listed under Grass and Fighting.
    ///
    /// **Max.** The Max table has no type sections, so a Dynamax-Yes COPY counts for the types of the species of its Max entry. The copy
    /// reaches an entry through its own species (a Blissey), or through a build whose target has one and which covers the copy as its carrier or
    /// as a spare (the advisor emits one build per species and target, so a spare copy has none of its own); then it counts once that build
    /// has nothing left to do. A copy marked No or not set counts for nothing.
    static func typesCounted(by b: BoxAdvice.Build, screen: Screen, table: TierTable, gm: GameMaster) -> Set<String> {
        switch screen {
        case .raids:
            var entries = table.entries(for: b.targetId, area: "raids")
            if b.viaMega {
                entries += table.entries.filter { $0.area == "raids" && $0.flags.mega && ($0.speciesId.hasPrefix(b.targetId + "_mega") || $0.speciesId.hasPrefix(b.targetId + "_primal")) }
            }
            let typed = Set(entries.map { $0.section.lowercased() }).intersection(HubData.typeOrder)
            if !typed.isEmpty { return typed }
            return entries.isEmpty ? [] : Set(gm.byId[b.targetId]?.types ?? [])
        case .max:
            return maxTypes(of: b.targetId, table: table, gm: gm)
        }
    }

    private static func maxTypes(of speciesId: String, table: TierTable, gm: GameMaster) -> Set<String> {
        table.entries(for: speciesId, area: "max").isEmpty ? [] : Set(gm.byId[speciesId]?.types ?? [])
    }

    /// Nothing left to do but the Dynamax requirement.
    static func isFinished(_ b: BoxAdvice.Build) -> Bool { !HubModel.needsSomething(b) }

    /// The copies a build serves: its carrier and the spares the advisor names.
    static func copies(of b: BoxAdvice.Build, advice: BoxAdvice) -> [String] {
        [b.entryId] + advice.spareBuilds.filter { $0.value.contains { $0.id == b.id } }.map(\.key).sorted()
    }

    /// A build is built for a screen when it counts there and is finished; on the Max screen a copy it serves must also be marked Dynamax.
    static func isBuilt(_ b: BoxAdvice.Build, advice: BoxAdvice, entries: [BoxEntry], screen: Screen) -> Bool {
        guard b.areas.contains(screen.area), isFinished(b) else { return false }
        if screen == .raids { return true }
        let yes = Set(entries.filter { $0.row.dynamax == true }.map(\.id))
        if copies(of: b, advice: advice).contains(where: { yes.contains($0) }) { return true }
        // Another copy of the carrier's species marked Yes serves too, so the to-do never asks for a mark that is already there.
        guard let species = entries.first(where: { $0.id == b.entryId })?.row.speciesId else { return false }
        return entries.contains { $0.row.dynamax == true && $0.row.speciesId == species }
    }

    /// The Max table entry a copy takes part under, with whether the copy already is what the entry names. Own species first; else the builds
    /// that cover the copy (carrier or spare) in the advisor's order, built once finished. Of several entries of one species the best tier wins.
    struct MaxUse: Equatable {
        var entry: TierTable.Entry
        var built: Bool
        var build: BoxAdvice.Build?
    }
    static func maxUse(of copy: BoxEntry, advice: BoxAdvice, table: TierTable) -> MaxUse? {
        func best(_ id: String) -> TierTable.Entry? { table.entries(for: id, area: "max").min { $0.tier < $1.tier } }
        if let e = best(copy.row.speciesId) { return MaxUse(entry: e, built: true, build: nil) }
        for b in advice.builds where b.areas.contains("Max") && (b.entryId == copy.id || (advice.spareBuilds[copy.id] ?? []).contains { $0.id == b.id }) {
            if let e = best(b.targetId) { return MaxUse(entry: e, built: isFinished(b), build: b) }
        }
        return nil
    }

    /// The types the box has a counter for on this screen.
    static func covered(advice: BoxAdvice, entries: [BoxEntry], gm: GameMaster, screen: Screen) -> Set<String> {
        guard let table = try? TierTable.bundled() else { return [] }
        switch screen {
        case .raids:
            return advice.builds.filter { isBuilt($0, advice: advice, entries: entries, screen: .raids) }
                .reduce(into: Set<String>()) { $0.formUnion(typesCounted(by: $1, screen: .raids, table: table, gm: gm)) }
        case .max:
            return entries.filter { $0.row.dynamax == true }.reduce(into: Set<String>()) { acc, e in
                if let u = maxUse(of: e, advice: advice, table: table), u.built { acc.formUnion(maxTypes(of: u.entry.speciesId, table: table, gm: gm)) }
            }
        }
    }

    /// How many of the row's bring types the box has a counter for, how many it needs, and the types it lacks (in bring order).
    public static func readiness(row: HubData.RotationRow, advice: BoxAdvice, entries: [BoxEntry], gm: GameMaster, hub: HubData, screen: Screen)
        -> (built: Int, needed: Int, missing: [String]) {
        let need = bring(row: row, hub: hub)
        let have = covered(advice: advice, entries: entries, gm: gm, screen: screen)
        let missing = need.filter { !have.contains($0) }
        return (need.count - missing.count, need.count, missing)
    }

    /// "Tyranitar" for "tyranitar", "Fighting" for "fighting".
    public static func typeName(_ t: String) -> String { t.prefix(1).uppercased() + t.dropFirst() }

    // MARK: to do

    /// A build's action with the Pokémon named: "Evolve Pupitar to Tyranitar", "Power up Moltres to level 30", "Mega evolve Lucario".
    static func sentence(for b: BoxAdvice.Build) -> String {
        // The cost follows in brackets, so the power-up's own area bracket ("to level 35 (Raids)") is dropped.
        let action = b.action.replacingOccurrences(of: #"(to level [0-9.]+) \([^)]*\)"#, with: "$1", options: .regularExpression)
        for prefix in ["Evolve to ", "Form change to "] where action.hasPrefix(prefix) {
            let verb = prefix.dropLast(4)   // drops " to ": "Evolve", "Form change"
            return "\(verb) \(b.title) to \(action.dropFirst(prefix.count))"
        }
        for verb in ["Power up", "Mega evolve", "Second move", "Elite TM"] where action.hasPrefix(verb) {
            return "\(verb) \(b.title)\(action.dropFirst(verb.count))"
        }
        return "\(b.title): \(action)"
    }

    /// The sentence under the readiness bar: "Ready." when nothing is missing; else, for the FIRST missing type, the first unbuilt build of the
    /// area in the advisor's order that counts for that type ("Evolve Pupitar to Tyranitar (100 candy)."); only when no build counts for it, the
    /// same for the next missing type; else "No <first missing type> counter in your box."
    public static func toDo(row: HubData.RotationRow, advice: BoxAdvice, entries: [BoxEntry], gm: GameMaster, hub: HubData, screen: Screen) -> String {
        if row.bosses.isEmpty { return row.tba == true ? "Boss not announced yet." : row.note }
        let r = readiness(row: row, advice: advice, entries: entries, gm: gm, hub: hub, screen: screen)
        guard let first = r.missing.first else { return "Ready." }
        if let table = try? TierTable.bundled() {
            for type in r.missing {
                if let b = advice.builds.first(where: { $0.areas.contains(screen.area) && !isBuilt($0, advice: advice, entries: entries, screen: screen)
                                                        && typesCounted(by: $0, screen: screen, table: table, gm: gm).contains(type) }) {
                    if screen == .max, isFinished(b) { return "Mark \(b.title) as Dynamax on its page." }
                    return "\(sentence(for: b)) (\(HubModel.costShort(b)))."
                }
            }
        }
        return screen == .max ? "No \(typeName(first)) Max attacker marked Dynamax." : "No \(typeName(first)) counter in your box."
    }

    /// The unbuilt builds for this screen that count for a type the shown rows ask for, in the advisor's order.
    public static func gapClosers(rows: [HubData.RotationRow], advice: BoxAdvice, entries: [BoxEntry], gm: GameMaster, hub: HubData, screen: Screen) -> [BoxAdvice.Build] {
        guard let table = try? TierTable.bundled() else { return [] }
        let wanted = Set(rows.flatMap { bring(row: $0, hub: hub) })
        return advice.builds.filter { $0.areas.contains(screen.area) && !isBuilt($0, advice: advice, entries: entries, screen: screen)
                                      && !typesCounted(by: $0, screen: screen, table: table, gm: gm).isDisjoint(with: wanted) }
    }

    // MARK: Max roster

    /// One Dynamax-Yes copy on the Max screen: its name, CP, the Max entry's tier and role ("S · Tank and healer"; "S · Attackers" for an entry
    /// with no role), and whether the species' build is done ("Built", "To build"); "No Max use in the tables" with no state when it has no entry.
    public struct RosterTile: Equatable {
        public var entryId: String
        public var name: String
        public var cp: Int
        public var line: String
        public var state: String
        public var hasUse: Bool
    }

    /// The copies marked Dynamax, those with a Max entry first (best tier, then CP). `unsetCount` is how many copies not yet marked either way
    /// have a Max entry, which marking would put in the roster.
    public static func maxRoster(entries: [BoxEntry], advice: BoxAdvice) -> (tiles: [RosterTile], unsetCount: Int) {
        guard let table = try? TierTable.bundled() else { return ([], 0) }
        let tiles = entries.filter { $0.row.dynamax == true }.map { e -> (String, RosterTile) in
            guard let u = maxUse(of: e, advice: advice, table: table) else {
                return ("Z", RosterTile(entryId: e.id, name: e.row.title, cp: e.row.cp, line: "No Max use in the tables", state: "", hasUse: false))
            }
            return (u.entry.tier, RosterTile(entryId: e.id, name: e.row.title, cp: e.row.cp, line: "\(u.entry.tier) · \(u.entry.role ?? u.entry.section)",
                                             state: u.built ? "Built" : "To build", hasUse: true))
        }
        .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.cp > $1.1.cp }.map(\.1)
        return (tiles, entries.filter { $0.row.dynamax == nil && maxUse(of: $0, advice: advice, table: table) != nil }.count)
    }
}

// MARK: today

extension HubModel {
    /// The local calendar day the Hub's timelines count from. A debug build honours `-uitest-today yyyy-mm-dd` so the UI tests do not depend on
    /// the date they run on; a release build always reads the clock.
    public static func today(now: Date = Date(), arguments: [String] = ProcessInfo.processInfo.arguments) -> String {
        #if DEBUG
        if let i = arguments.firstIndex(of: "-uitest-today"), i + 1 < arguments.count, arguments[i + 1].range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return arguments[i + 1]
        }
        #endif
        // Always the Gregorian calendar: a device set to the Buddhist or Japanese calendar numbers its years differently.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
