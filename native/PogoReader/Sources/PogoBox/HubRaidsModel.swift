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
        case .battleDay: return "RAID DAY"
        case .raidHour: return "RAID HOUR"
        case .maxMonday: return "MAX MON"
        case .maxEvent: return "EVENT"
        case .other: return ""
        }
    }

    /// What a row is called: its bosses joined with " · "; a row still "to be announced" reads its title and says so; a row with no boss
    /// (a Raid Hour, Dynamax Trails) reads its title.
    public static func name(_ row: HubData.RotationRow) -> String {
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

    private static func types(of b: BoxAdvice.Build, _ gm: GameMaster) -> [String] { gm.byId[b.targetId]?.types ?? [] }

    /// A build is built for a screen when it counts there and nothing is left but the Dynamax requirement. On the Max screen the copy must
    /// also be marked Dynamax: the requirement is the person's to set, so an unmarked copy is not ready. A build read without steps counts
    /// as built, as the brief for this screen words it.
    static func isBuilt(_ b: BoxAdvice.Build, entries: [BoxEntry], screen: Screen) -> Bool {
        guard b.areas.contains(screen.area) else { return false }
        if let steps = b.steps, steps.contains(where: { $0.kind != "needsDynamaxCopy" }) { return false }
        if screen == .max { return entries.first { $0.id == b.entryId }?.row.dynamax == true }
        return true
    }

    /// How many of the row's bring types the box has a built counter for, how many it needs, and the types it lacks (in bring order).
    public static func readiness(row: HubData.RotationRow, builds: [BoxAdvice.Build], entries: [BoxEntry], gm: GameMaster, hub: HubData, screen: Screen)
        -> (built: Int, needed: Int, missing: [String]) {
        let need = bring(row: row, hub: hub)
        let have = Set(builds.filter { isBuilt($0, entries: entries, screen: screen) }.flatMap { types(of: $0, gm) })
        let missing = need.filter { !have.contains($0) }
        return (need.count - missing.count, need.count, missing)
    }

    /// "Tyranitar" for "tyranitar", "Fighting" for "fighting".
    public static func typeName(_ t: String) -> String { t.prefix(1).uppercased() + t.dropFirst() }

    // MARK: to do

    /// A build's action with the Pokémon named: "Evolve Pupitar to Tyranitar", "Power up Moltres to level 30 (Raids)", "Mega evolve Lucario".
    static func sentence(for b: BoxAdvice.Build) -> String {
        for prefix in ["Evolve to ", "Form change to "] where b.action.hasPrefix(prefix) {
            let verb = prefix.dropLast(4)   // drops " to ": "Evolve", "Form change"
            return "\(verb) \(b.title) to \(b.action.dropFirst(prefix.count))"
        }
        for verb in ["Power up", "Mega evolve", "Second move", "Elite TM"] where b.action.hasPrefix(verb) {
            return "\(verb) \(b.title)\(b.action.dropFirst(verb.count))"
        }
        return "\(b.title): \(b.action)"
    }

    /// The sentence under the readiness bar: "Ready." when nothing is missing; else the first unbuilt build, in the advisor's order, that
    /// brings a missing type ("Evolve Pupitar to Tyranitar (100 candy)."); else the first missing type with no build for it.
    public static func toDo(row: HubData.RotationRow, builds: [BoxAdvice.Build], entries: [BoxEntry], gm: GameMaster, hub: HubData, screen: Screen) -> String {
        if row.bosses.isEmpty { return row.tba == true ? "Boss not announced yet." : row.note }
        let r = readiness(row: row, builds: builds, entries: entries, gm: gm, hub: hub, screen: screen)
        guard let first = r.missing.first else { return "Ready." }
        if let b = builds.first(where: { $0.areas.contains(screen.area) && !isBuilt($0, entries: entries, screen: screen) && !Set(types(of: $0, gm)).isDisjoint(with: r.missing) }) {
            if screen == .max, !HubModel.needsSomething(b) { return "Mark \(b.title) as Dynamax on its page." }
            return "\(sentence(for: b)) (\(HubModel.costShort(b)))."
        }
        return "No \(typeName(first)) counter in your box."
    }

    /// The unbuilt builds for this screen that bring a type the shown rows ask for, in the advisor's order.
    public static func gapClosers(rows: [HubData.RotationRow], builds: [BoxAdvice.Build], entries: [BoxEntry], gm: GameMaster, hub: HubData, screen: Screen) -> [BoxAdvice.Build] {
        let wanted = Set(rows.flatMap { bring(row: $0, hub: hub) })
        return builds.filter { $0.areas.contains(screen.area) && !isBuilt($0, entries: entries, screen: screen) && !Set(types(of: $0, gm)).isDisjoint(with: wanted) }
    }

    // MARK: Max roster

    /// One Dynamax-Yes copy on the Max screen: its name, CP and the best Max build for it ("S · Already built") or "No Max use in the tables".
    public struct RosterTile: Equatable {
        public var entryId: String
        public var name: String
        public var cp: Int
        public var line: String
        public var hasUse: Bool
    }

    /// The copies marked Dynamax, those with a Max use first (the advisor's order), then by CP. `unsetCount` is how many copies not yet
    /// marked either way carry a Max build, which marking would put in the roster.
    public static func maxRoster(entries: [BoxEntry], builds: [BoxAdvice.Build]) -> (tiles: [RosterTile], unsetCount: Int) {
        func best(_ e: BoxEntry) -> (Int, BoxAdvice.Build)? {
            builds.enumerated().first { $0.element.entryId == e.id && $0.element.areas.contains("Max") }.map { ($0.offset, $0.element) }
        }
        let tiles = entries.filter { $0.row.dynamax == true }.map { e -> (Int, RosterTile) in
            let b = best(e)
            return (b?.0 ?? Int.max, RosterTile(entryId: e.id, name: e.row.title, cp: e.row.cp,
                                                line: b.map { "\($0.1.tier) · \($0.1.action)" } ?? "No Max use in the tables", hasUse: b != nil))
        }
        .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.cp > $1.1.cp }.map(\.1)
        return (tiles, entries.filter { $0.row.dynamax == nil && best($0) != nil }.count)
    }
}
