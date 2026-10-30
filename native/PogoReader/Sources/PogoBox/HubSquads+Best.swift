import Foundation
import PogoReader

/// Phone feedback items 8 and 9 (30 Oct 2026): what Best lists, and how a slot and a whole squad are rated. Rule numbers are CONCEPTS.md's.
///
/// **Available** (the existing candidate lists, `raidCandidates` and the like, under `.available`) is the player's own Pokémon as they are, best first for the slot.
/// **Best** is the ranked list below: the best Pokémon in the game for the slot, from the research tier tables, whether or not the player has it and whether or
/// not it can be got now. Each row carries the player's best copy or build of that Pokémon when there is one, and when there is not, a line that says when it
/// might be had: the rotation when the species is a raid or Max boss now or coming, else the table's own obtain text (the only "last available" information
/// the app has; there is no history of past dates).
extension HubSquads {
    // MARK: rule 6: Best rows

    /// One row of a Best list: a Pokémon the table lists for the slot, with the player's best copy or build of it when they have one.
    public struct BestRow: SquadCandidate, Equatable {
        /// The species key a species pick stores (`SquadSlot.species`): the table's species id, `_shadow` added for a Shadow listed under a plain id.
        public var key: String
        /// The table's name for it ("Mega Delphox", "Shadow Reshiram").
        public var name: String
        public var speciesId: String
        /// The table's tier for it in this area, S, A or B.
        public var tier: String
        /// The roles it may take on this screen (`RaidRole`, `MaxRole`, `PvpRole` names; the Gym's "Defender"; none on Rocket).
        public var roles: [String]
        public var types: [String]
        /// The player's best build of it (raids, Max, Gym, Rocket); nil when the box has none.
        public var build: BoxAdvice.Build?
        /// The player's best copy of it in the league (PvP); nil when the box has none.
        public var pvp: PvpCandidate?
        /// Not in the box: when it might be had. Empty for a Pokémon the box has.
        public var availability: String
        /// Rocket: how many of the slot's options its types hit for more than normal damage, the types with that, and the slot line ("beats 2 of 3").
        public var hits: Int = 0
        public var typeFlags: [TypeFlag] = []
        public var slotLine: String? = nil

        public init(key: String, name: String, speciesId: String, tier: String, roles: [String], types: [String], build: BoxAdvice.Build? = nil, pvp: PvpCandidate? = nil, availability: String) {
            self.key = key; self.name = name; self.speciesId = speciesId; self.tier = tier; self.roles = roles; self.types = types
            self.build = build; self.pvp = pvp; self.availability = availability
        }

        /// The id a pick or a slot holds: the copy's entry id when the box has it, else `squadSpeciesPrefix` + the key.
        public var entryId: String { ownedEntryId ?? squadSpeciesPrefix + key }
        public var ownedEntryId: String? { build?.entryId ?? pvp?.entryId }
        public var inBox: Bool { ownedEntryId != nil }
        public var roleNames: [String] { roles }
    }

    private static func speciesTypes(_ id: String, ctx: HubContext) -> [String] {
        ctx.gm.byId[id]?.types ?? ctx.gm.byId[id.replacingOccurrences(of: "_shadow", with: "")]?.types ?? []
    }

    /// The key of a table entry: its species id, with `_shadow` for a Shadow the table lists under the plain id ("Shadow Pheromosa"), so two Pokémon never share one.
    static func bestKey(_ e: TierTable.Entry) -> String { e.flags.shadow && !e.speciesId.hasSuffix("_shadow") ? e.speciesId + "_shadow" : e.speciesId }

    /// The entries in ranking order, one per Pokémon: best tier first, then `secondary`, then the table's own order (its # in the PvP tables, else its position).
    /// A Pokémon listed more than once (a raid attacker under two types) keeps its best entry and the union of the roles the entries give.
    private static func ranked(_ items: [(e: TierTable.Entry, index: Int, roles: [String])], secondary: (TierTable.Entry) -> Int = { _ in 0 }) -> [(e: TierTable.Entry, roles: [String])] {
        let sorted = items.sorted { l, r in
            let (a, b) = (PogoRules.tierRank(l.e.tier), PogoRules.tierRank(r.e.tier))
            if a != b { return a < b }
            let (x, y) = (secondary(l.e), secondary(r.e))
            if x != y { return x < y }
            let (p, q) = (l.e.rank ?? Double.greatestFiniteMagnitude, r.e.rank ?? Double.greatestFiniteMagnitude)
            if p != q { return p < q }
            return l.index < r.index
        }
        var out: [(e: TierTable.Entry, roles: [String])] = []
        var at = [String: Int]()
        for item in sorted {
            let key = bestKey(item.e)
            if let i = at[key] { out[i].roles += item.roles.filter { !out[i].roles.contains($0) } } else { at[key] = out.count; out.append((item.e, item.roles)) }
        }
        return out
    }

    /// The build to show for a Pokémon the box can make: at full strength first, then the least dust, then the least candy, then the advisor's order.
    private static func bestBuild(_ builds: [BoxAdvice.Build], screen: SquadScreen, ctx: HubContext) -> BoxAdvice.Build? {
        builds.enumerated().min { l, r in
            let (a, b) = (l.element, r.element)
            let (fa, fb) = (isFullStrength(a, screen: screen, ctx: ctx), isFullStrength(b, screen: screen, ctx: ctx))
            if fa != fb { return fa }
            if a.dust != b.dust { return a.dust < b.dust }
            if a.candy != b.candy { return a.candy < b.candy }
            return l.offset < r.offset
        }?.element
    }

    /// A copy is shown against one table row at a time, so a copy that serves a higher-ranked row is not repeated further down (a Swampert that mega evolves
    /// is listed as Mega Swampert, not again as Swampert). `nil` means "skip this row": the box has a build, but every one is already shown above.
    private static func claim(_ builds: [BoxAdvice.Build], screen: SquadScreen, claimed: inout Set<String>, ctx: HubContext) -> (skip: Bool, build: BoxAdvice.Build?) {
        guard !builds.isEmpty else { return (false, nil) }
        guard let b = bestBuild(builds.filter { !claimed.contains($0.entryId) }, screen: screen, ctx: ctx) else { return (true, nil) }
        claimed.insert(b.entryId)
        return (false, b)
    }

    private static func bestRow(_ e: TierTable.Entry, roles: [String], build: BoxAdvice.Build? = nil, pvp: PvpCandidate? = nil, ctx: HubContext) -> BestRow {
        let owned = build != nil || pvp != nil
        return BestRow(key: bestKey(e), name: e.name, speciesId: e.speciesId, tier: e.tier, roles: roles, types: speciesTypes(e.speciesId, ctx: ctx), build: build, pvp: pvp,
                       availability: owned ? "" : availability(of: e, ctx: ctx))
    }

    // MARK: availability

    private static let raidKinds: [HubData.Kind] = [.fiveStar, .mega, .shadow, .battleDay]
    private static let maxKinds: [HubData.Kind] = [.maxMonday, .maxEvent]
    private static let monthWords = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "9 Nov" for `2026-11-09`; the key itself when it does not parse.
    static func dayMonth(_ key: String) -> String {
        let p = key.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 && (1...12).contains(p[1]) ? "\(p[2]) \(monthWords[p[1] - 1])" : key
    }

    /// When a Pokémon the box lacks might be had. The rotation first: "Raid boss now" or "Max battle now" when it is a boss today; else its next appearance, "Raids
    /// from 9 Nov", "Max Monday 2 Nov" or "Max battles from 16 Nov". Otherwise the table's obtain text ("Medium. T5 raids"); "Last available not known" only
    /// when the table has none either (nothing in the data says when it was last available).
    public static func availability(of e: TierTable.Entry, ctx: HubContext) -> String {
        func isBoss(_ b: HubData.Boss) -> Bool { b.speciesId == e.speciesId || (b.shadow == true && b.speciesId + "_shadow" == e.speciesId) }
        let rows = ctx.hub.rotation.filter { $0.to >= ctx.today && $0.bosses.contains(where: isBoss) }
        if rows.contains(where: { $0.from <= ctx.today && raidKinds.contains($0.kind) }) { return "Raid boss now" }
        if rows.contains(where: { $0.from <= ctx.today && maxKinds.contains($0.kind) }) { return "Max battle now" }
        if let next = rows.filter({ $0.from > ctx.today }).min(by: { ($0.from, $0.to) < ($1.from, $1.to) }) {
            if raidKinds.contains(next.kind) { return "Raids from \(dayMonth(next.from))" }
            return next.kind == .maxMonday ? "Max Monday \(dayMonth(next.from))" : "Max battles from \(dayMonth(next.from))"
        }
        let obtain = (e.obtain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return obtain.isEmpty ? "Last available not known" : obtain
    }

    // MARK: Raids

    /// Best for a raid: the Raids table's entries listed under one of the boss's bring types, best tier first, then the bring type that hits hardest, then the table's
    /// order. The role is the one `raidRole` gives the entry (a Mega or Primal is a Mega). The box's build for an entry is any Raids build whose target fills it
    /// (`HubRaidsModel.raidEntries`: the species itself, or the Mega it evolves to).
    public static func bestRaidRows(row: HubData.RotationRow, ctx: HubContext) -> [BestRow] {
        let bring = HubRaidsModel.bring(row: row, hub: ctx.hub)
        let items = ctx.table.entries.enumerated().compactMap { i, e -> (e: TierTable.Entry, index: Int, roles: [String])? in
            guard e.area == "raids", bring.contains(e.section.lowercased()) else { return nil }
            return (e, i, [PogoRules.raidRole(targetId: e.speciesId, viaMega: e.flags.mega, shadow: e.flags.shadow, gm: ctx.gm).rawValue])
        }
        // Which Raids builds fill which entry, found once per build.
        var fills = [String: [BoxAdvice.Build]]()
        for b in ctx.advice.builds where b.areas.contains("Raids") {
            let shadow = HubRaidsModel.isShadow(b, entries: ctx.entries)
            for e in HubRaidsModel.raidEntries(targetId: b.targetId, viaMega: b.viaMega, table: ctx.table, shadow: shadow) { fills[bestKey(e), default: []].append(b) }
        }
        var claimed = Set<String>()
        return ranked(items, secondary: { bring.firstIndex(of: $0.section.lowercased()) ?? bring.count }).compactMap { r in
            let c = claim(fills[bestKey(r.e)] ?? [], screen: .raids, claimed: &claimed, ctx: ctx)
            return c.skip ? nil : bestRow(r.e, roles: r.roles, build: c.build, ctx: ctx)
        }
    }

    // MARK: Max

    /// Best for a Max battle: the Max table's entries (Gigantamax entries never, as in rule 12), best tier first, then a type that hits the boss, then the table's
    /// order. Roles from the table (rule 12). The box's build for an entry is a Max build whose target is that species.
    public static func bestMaxRows(row: HubData.RotationRow, ctx: HubContext) -> [BestRow] {
        let items = ctx.table.entries.enumerated().compactMap { i, e -> (e: TierTable.Entry, index: Int, roles: [String])? in
            guard e.area == "max", e.name.range(of: "gigantamax|g-max", options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
            let roles = PogoRules.maxRoles(e).map(\.rawValue)
            return roles.isEmpty ? nil : (e, i, roles)
        }
        var claimed = Set<String>()
        let byTarget = Dictionary(grouping: ctx.advice.builds.filter { $0.areas.contains("Max") }, by: \.targetId)
        return ranked(items, secondary: { PogoRules.hitsAnyBoss(speciesTypes($0.speciesId, ctx: ctx), row: row, hub: ctx.hub) ? 0 : 1 }).compactMap { r in
            let c = claim(byTarget[r.e.speciesId] ?? [], screen: .max, claimed: &claimed, ctx: ctx)
            return c.skip ? nil : bestRow(r.e, roles: r.roles, build: c.build, ctx: ctx)
        }
    }

    // MARK: Gym

    /// Best for the Gym: the Gym table's entries, best tier first, then the table's order. The box's build for an entry is a Gym build whose target is that species.
    public static func bestGymRows(ctx: HubContext) -> [BestRow] {
        let items = ctx.table.entries.enumerated().compactMap { i, e -> (e: TierTable.Entry, index: Int, roles: [String])? in e.area == "gym" ? (e, i, [gymSlotRole]) : nil }
        var claimed = Set<String>()
        let byTarget = Dictionary(grouping: HubTeams.gymAvailable(builds: ctx.advice.builds), by: \.targetId)
        return ranked(items).compactMap { r in
            let c = claim(byTarget[r.e.speciesId] ?? [], screen: .gym, claimed: &claimed, ctx: ctx)
            return c.skip ? nil : bestRow(r.e, roles: r.roles, build: c.build, ctx: ctx)
        }
    }

    // MARK: Team Rocket

    /// Best for one slot of a leader's lineup: the Rocket table's entries whose types hit at least one of the slot's options for more than normal damage, best tier
    /// first, then the table's order. The box's build for an entry is a Rocket or Raids build whose target is that species.
    public static func bestRocketRows(options: [HubData.Boss], ctx: HubContext) -> [BestRow] {
        let items = ctx.table.entries.enumerated().compactMap { i, e -> (e: TierTable.Entry, index: Int, roles: [String])? in
            guard e.area == "rocket", options.contains(where: { ctx.hub.beats(speciesTypes(e.speciesId, ctx: ctx), $0.types) }) else { return nil }
            return (e, i, [])
        }
        var claimed = Set<String>()
        let byTarget = Dictionary(grouping: ctx.advice.builds.filter(isRocketArea), by: \.targetId)
        return ranked(items).compactMap { r in
            let c = claim(byTarget[r.e.speciesId] ?? [], screen: .rocket, claimed: &claimed, ctx: ctx)
            if c.skip { return nil }
            var out = bestRow(r.e, roles: r.roles, build: c.build, ctx: ctx)
            out.hits = options.filter { ctx.hub.beats(out.types, $0.types) }.count
            out.typeFlags = out.types.map { t in TypeFlag(type: t, hits: options.contains { ctx.hub.beats([t], $0.types) }) }
            out.slotLine = slotLine(hits: out.hits, of: options.count)
            return out
        }
    }

    // MARK: PvP

    /// Best for a league: its table's entries, best tier first, then the table's # (its rank), with the roles the table's role text gives. The box's copy of an entry
    /// is the league candidate of that species (`pvpCandidates`, which needs a score of `HubTeams.candidateFloor` or more).
    public static func bestPvpRows(league: String, pogoAssist: Bool = false, ctx: HubContext) -> [BestRow] {
        let items = ctx.table.entries.enumerated().compactMap { i, e -> (e: TierTable.Entry, index: Int, roles: [String])? in
            e.area == league ? (e, i, PvpRole.allCases.filter(pvpRoles(e.role ?? "").contains).map(\.rawValue)) : nil
        }
        var owned = [String: PvpCandidate]()
        for c in pvpCandidates(league: league, mode: .best, pogoAssist: pogoAssist, ctx: ctx) where owned[c.candidate.speciesId] == nil { owned[c.candidate.speciesId] = c }
        return ranked(items).map { r in bestRow(r.e, roles: r.roles, pvp: owned[r.e.speciesId], ctx: ctx) }
    }

    // MARK: rule 6: a Best pick that the box now has

    /// A species pick for a Pokémon the box has since got is read as the best copy of it: the slot then shows the copy, not "Not in your box". The stored pick is
    /// left alone (it is the player's choice of the species).
    public static func resolvingSpecies(_ slots: [SquadSlot], rows: [BestRow]) -> [SquadSlot] {
        slots.map { s in
            guard s.pick == nil, let key = s.species, let own = rows.first(where: { $0.key == key })?.ownedEntryId else { return s }
            return SquadSlot(role: s.role, pick: own)
        }
    }

    /// A leader's Best squad: each slot takes the player's pick, else the first unused row of the Rocket table that beats that slot (`bestRocketRows`).
    public static func bestRocketSquad(leader: HubData.Leader, slots: [SquadSlot] = defaultRocketSlots(), ctx: HubContext) -> [FilledSlot] {
        let rows = leader.slots.map { bestRocketRows(options: $0, ctx: ctx) }
        return fill(slots: resolvingSpecies(slots, rows: rows.flatMap { $0 }), pool: { i, _ in Pool(preferred: rows.indices.contains(i) ? rows[i].map(\.entryId) : []) })
    }

    /// The Best squad's slots: each takes the player's pick, else the first unused row of the ranked list for its role.
    public static func bestSquad(slots: [SquadSlot], rows: [BestRow], fallback: Bool = false) -> [FilledSlot] {
        fill(slots: resolvingSpecies(slots, rows: rows), pool: { _, role in
            Pool(preferred: pool(role: role, in: rows), fallback: fallback ? rows.map(\.entryId) : [])
        })
    }

    // MARK: rules 29 and 30: how ready a slot and a squad are

    /// One slot's state (CONCEPTS rule 29).
    public enum SlotStatus: String, Equatable {
        /// A Pokémon the player has, at Full strength, rated S or A for the area and slot.
        case ready
        /// A Pokémon the player has that still needs work, or is rated B or lower or is not in the table.
        case needsWork
        /// Best only: the Pokémon in the slot is not in the box.
        case toGet
        /// Nothing in the slot.
        case empty

        /// The word a VoiceOver label ends with.
        public var spoken: String {
            switch self {
            case .ready: return "ready"
            case .needsWork: return "needs work"
            case .toGet: return "not in your box, to get"
            case .empty: return "empty"
            }
        }
    }

    /// Rule 29 for a slot holding a Pokémon: green only when the player has it, it is at Full strength and the tier is S or A. `tier` is the one the screen shows for it.
    public static func slotStatus(inBox: Bool, fullStrength: Bool, tier: String) -> SlotStatus {
        guard inBox else { return .toGet }
        return fullStrength && (tier == "S" || tier == "A") ? .ready : .needsWork
    }

    public struct TeamStatus: Equatable {
        public enum Level: String, Equatable { case green, amber, red }
        public var level: Level
        public var text: String
    }

    /// Rule 30: the line over a squad. "Ready" when every slot is ready; "Nearly ready: 2 need work" when none is empty or to get and some need work; else "Not ready:"
    /// with what is missing, "2 to get, 1 empty" (a Best squad can hold Pokémon the box lacks). nil for a squad with no slots.
    public static func teamStatus(_ slots: [SlotStatus]) -> TeamStatus? {
        guard !slots.isEmpty else { return nil }
        let count = { (s: SlotStatus) in slots.filter { $0 == s }.count }
        let toGet = count(.toGet), empty = count(.empty), work = count(.needsWork)
        if toGet + empty > 0 {
            let parts = [toGet > 0 ? "\(toGet) to get" : nil, empty > 0 ? "\(empty) empty" : nil].compactMap { $0 }
            return TeamStatus(level: .red, text: "Not ready: " + parts.joined(separator: ", "))
        }
        if work > 0 { return TeamStatus(level: .amber, text: "Nearly ready: \(work) \(work == 1 ? "needs" : "need") work") }
        return TeamStatus(level: .green, text: "Ready")
    }
}
