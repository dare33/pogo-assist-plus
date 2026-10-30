import Foundation
import PogoReader

/// Design pass 2: the per-screen squad rules (Raids, Max, Gym, Rocket, PvP). See `HubSquads.swift` for the shared ones. Rule numbers are CONCEPTS.md's.
extension HubSquads {
    // MARK: Raids (rules 8 to 10)

    public struct RaidCandidate: SquadCandidate, Equatable {
        public var build: BoxAdvice.Build
        public var role: PogoRules.RaidRole
        /// The best tier the Raids table gives the target under one of the boss's bring types ("" when none).
        public var tier: String
        /// How many of the bring types the target counts for.
        public var covers: Int
        public var built: Bool
        public var entryId: String { build.entryId }
        public var roleNames: [String] { [role.rawValue] }
    }

    /// Rule 9: Raids builds whose target counts for one of the boss's bring types (`HubRaidsModel.typesCounted`), ordered by the best tier the Raids
    /// table gives the target under a bring type, then built first, then how many bring types it covers, then the advisor's order; one entry per copy.
    /// Under Available only builds usable as they are, and no Mega (rule 3).
    public static func raidCandidates(row: HubData.RotationRow, mode: SquadMode, ctx: HubContext) -> [RaidCandidate] {
        let bring = Set(HubRaidsModel.bring(row: row, hub: ctx.hub))
        var out: [(c: RaidCandidate, offset: Int)] = []
        for (i, b) in ctx.advice.builds.enumerated() where b.areas.contains("Raids") && isUsable(b, mode: mode) {
            let shadow = HubRaidsModel.isShadow(b, entries: ctx.entries)
            let counted = HubRaidsModel.typesCounted(by: b, screen: .raids, table: ctx.table, gm: ctx.gm, shadow: shadow).intersection(bring)
            guard !counted.isEmpty else { continue }
            // The same entries and the same reading of a section as `typesCounted`: a typed section stands for that type, one that is not a type for the
            // species' own types. The tier is the best of the entries that stand for a counted type.
            let entries = HubRaidsModel.raidEntries(targetId: b.targetId, viaMega: b.viaMega, table: ctx.table, shadow: shadow)
            let own = ctx.gm.byId[b.targetId]?.types ?? []
            let best = entries.filter { !Set(HubRaidsModel.entryTypes($0, in: entries, speciesTypes: own)).isDisjoint(with: counted) }.map { PogoRules.tierRank($0.tier) }.min() ?? 3
            let role = PogoRules.raidRole(targetId: b.targetId, viaMega: b.viaMega, shadow: shadow, gm: ctx.gm)
            out.append((RaidCandidate(build: b, role: role, tier: ["S", "A", "B"].indices.contains(best) ? ["S", "A", "B"][best] : "", covers: counted.count,
                                      built: isFullStrength(b, screen: .raids, ctx: ctx)), i))
        }
        out.sort { l, r in
            let (a, b) = (l.c, r.c)
            if PogoRules.tierRank(a.tier) != PogoRules.tierRank(b.tier) { return PogoRules.tierRank(a.tier) < PogoRules.tierRank(b.tier) }
            if a.built != b.built { return a.built }
            if a.covers != b.covers { return a.covers > b.covers }
            return l.offset < r.offset
        }
        var seen = Set<String>()
        return out.map(\.c).filter { seen.insert($0.entryId).inserted }
    }

    /// The suggested raid squad's slots: Mega, Heavy hitter ×3, Bulky hitter ×2. Under Available the Mega slot stays empty (rule 3), which the empty Mega pool gives.
    public static func defaultRaidSlots() -> [SquadSlot] { PogoRules.RaidRole.suggested.map { SquadSlot(role: $0.rawValue) } }

    /// Rule 10: each slot takes the first unused candidate of its role (role "All": any candidate).
    public static func raidSquad(slots: [SquadSlot] = defaultRaidSlots(), candidates: [RaidCandidate], placeable: (String, String) -> Bool) -> [FilledSlot] {
        fill(slots: slots, pool: { _, role in Pool(preferred: pool(role: role, in: candidates)) }, placeable: placeable)
    }

    // MARK: Max (rule 12)

    public struct MaxCandidate: SquadCandidate, Equatable {
        public var build: BoxAdvice.Build
        public var roles: [PogoRules.MaxRole]
        /// The best tier among the target's usable Max entries.
        public var tier: String
        /// One of the target's types hits the boss for more than normal damage.
        public var hitsBoss: Bool
        public var built: Bool
        public var entryId: String { build.entryId }
        public var roleNames: [String] { roles.map(\.rawValue) }
    }

    /// Max builds whose target has a usable Max entry (Gigantamax entries never), ordered by Max tier, then a type that hits the boss, then the advisor's
    /// order; one entry per copy.
    public static func maxCandidates(row: HubData.RotationRow, mode: SquadMode, ctx: HubContext) -> [MaxCandidate] {
        var out: [(c: MaxCandidate, offset: Int)] = []
        for (i, b) in ctx.advice.builds.enumerated() where b.areas.contains("Max") && isUsable(b, mode: mode) {
            let entries = HubRaidsModel.maxEntries(b.targetId, ctx.table)
            guard let best = entries.map({ PogoRules.tierRank($0.tier) }).min() else { continue }
            let hits = PogoRules.hitsAnyBoss(ctx.gm.byId[b.targetId]?.types ?? [], row: row, hub: ctx.hub)
            out.append((MaxCandidate(build: b, roles: PogoRules.maxRoles(of: b.targetId, table: ctx.table), tier: ["S", "A", "B"].indices.contains(best) ? ["S", "A", "B"][best] : "",
                                     hitsBoss: hits, built: isFullStrength(b, screen: .max, ctx: ctx)), i))
        }
        out.sort { l, r in
            if PogoRules.tierRank(l.c.tier) != PogoRules.tierRank(r.c.tier) { return PogoRules.tierRank(l.c.tier) < PogoRules.tierRank(r.c.tier) }
            if l.c.hitsBoss != r.c.hitsBoss { return l.c.hitsBoss }
            return l.offset < r.offset
        }
        var seen = Set<String>()
        return out.map(\.c).filter { seen.insert($0.entryId).inserted }
    }

    public static func defaultMaxSlots() -> [SquadSlot] { PogoRules.MaxRole.suggested.map { SquadSlot(role: $0.rawValue) } }

    /// Suggested Max squad: the first Tank, the first Healer, the first Attacker that hits the boss (else the first Attacker). Until a copy is marked
    /// Dynamax every Max pick reads Upgrade available (`isFullStrength` on .max), as the read-back's Q7 says.
    public static func maxSquad(slots: [SquadSlot] = defaultMaxSlots(), candidates: [MaxCandidate], placeable: (String, String) -> Bool) -> [FilledSlot] {
        fill(slots: slots, pool: { _, role in
            let listed = candidates.filter { role == squadRoleAll || $0.roleNames.contains(role) }
            let ordered = role == PogoRules.MaxRole.attacker.rawValue ? listed.filter(\.hitsBoss) + listed.filter { !$0.hitsBoss } : listed
            return Pool(preferred: ordered.map(\.entryId))
        }, placeable: placeable)
    }

    // MARK: Gym (rules 13 and 14)

    public struct GymRow: Equatable {
        public var build: BoxAdvice.Build
        /// The best tier the Gym table gives the target (the build's own tier when the table does not list it).
        public var tier: String
        /// Rule 14, at the build's target level, or the copy's level when built. Never assumed: see `PogoRules.Bulk`.
        public var bulk: PogoRules.Bulk
        /// The level the bulk was worked at; nil when it was not read.
        public var level: Double?
        public var built: Bool
        /// Shown in place of the bulk figure ("level not read"); `ivsNotRead` has its own wording.
        public var levelNotRead: Bool { bulk == .levelNotRead }
        public var ivsNotRead: Bool { bulk == .ivsNotRead }
    }

    /// One Gym build as a row: its Gym table tier, whether it is at full strength, and its bulk (rule 14).
    public static func gymRow(_ b: BoxAdvice.Build, ctx: HubContext) -> GymRow {
        let tiers = ctx.table.entries(for: b.targetId, area: "gym").map(\.tier)
        let tier = tiers.min { PogoRules.tierRank($0) < PogoRules.tierRank($1) } ?? b.tier
        let built = isFullStrength(b, screen: .gym, ctx: ctx)
        // Read or not is the copy's own level: the engine fills a missing one with 20 in the build (`p.level ?? 20`), which must never stand in for it.
        let copy = ctx.entry(b.entryId)
        let level: Double? = copy?.row.level.map { current in built ? current : (b.targetLevel ?? current) }
        let bulk = PogoRules.bulk(target: b.targetId, ivs: copy?.row.ivs, level: level, gm: ctx.gm)
        return GymRow(build: b, tier: tier, bulk: bulk, level: level, built: built)
    }

    /// Rule 13: Gym builds ordered by Gym table tier, then bulk (CP is not a key). Within a tier, a copy whose level is not read (or whose bulk cannot be
    /// worked out) comes after those with a known bulk, in the advisor's order. One row per copy (its first build in the order).
    public static func gymRows(mode: SquadMode, ctx: HubContext) -> [GymRow] {
        var rows: [(r: GymRow, offset: Int)] = []
        for (i, b) in HubTeams.gymAvailable(builds: ctx.advice.builds).enumerated() where isUsable(b, mode: mode) { rows.append((gymRow(b, ctx: ctx), i)) }
        rows.sort { l, r in
            let (a, b) = (l.r, r.r)
            if PogoRules.tierRank(a.tier) != PogoRules.tierRank(b.tier) { return PogoRules.tierRank(a.tier) < PogoRules.tierRank(b.tier) }
            switch (a.bulk.value, b.bulk.value) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return l.offset < r.offset
            }
        }
        var seen = Set<String>()
        return rows.map(\.r).filter { seen.insert($0.build.entryId).inserted }
    }

    public static let gymSlotRole = "Defender"

    /// Six defender slots, each replaceable through the picker.
    public static func defaultGymSlots() -> [SquadSlot] { Array(repeating: SquadSlot(role: gymSlotRole), count: 6) }

    /// The six suggested defenders: the first rows of the order not already chosen elsewhere in the squad.
    public static func gymSquad(slots: [SquadSlot] = defaultGymSlots(), rows: [GymRow], placeable: (String, String) -> Bool) -> [FilledSlot] {
        fill(slots: slots, pool: { _, _ in Pool(preferred: rows.map { $0.build.entryId }) }, placeable: placeable)
    }

    // MARK: Team Rocket (rules 16 to 21)

    static func isRocketArea(_ b: BoxAdvice.Build) -> Bool { b.areas.contains("Rocket") || b.areas.contains("Raids") }

    /// One of a build's types, in colour when it hits one of the slot's options for more than normal damage, grey otherwise (rule 17).
    public struct TypeFlag: Equatable {
        public var type: String
        public var hits: Bool
    }

    public struct RocketRow: SquadCandidate, Equatable {
        public var build: BoxAdvice.Build
        /// How many of the slot's options the build's types hit for more than normal damage.
        public var hits: Int
        public var built: Bool
        public var typeFlags: [TypeFlag]
        /// Rule 21: nil for a slot with one option, else "beats all 3" or "beats 2 of 3".
        public var slotLine: String?
        public var entryId: String { build.entryId }
        public var roleNames: [String] { [] }
    }

    public static let rocketSlotRole = "Counter"

    static func typeFlags(_ b: BoxAdvice.Build, options: [HubData.Boss], ctx: HubContext) -> [TypeFlag] {
        HubTeams.types(of: b, gm: ctx.gm).map { t in TypeFlag(type: t, hits: options.contains { ctx.hub.beats([t], $0.types) }) }
    }

    /// Rule 21: one option: no line; several: "beats all n" or "beats k of n" (none when it beats none).
    public static func slotLine(hits: Int, of n: Int) -> String? {
        guard n > 1, hits > 0 else { return nil }
        return hits == n ? "beats all \(n)" : "beats \(hits) of \(n)"
    }

    private static func rocketOrder(_ l: (b: BoxAdvice.Build, off: Int, built: Bool), _ r: (b: BoxAdvice.Build, off: Int, built: Bool)) -> Bool? {
        if l.built != r.built { return l.built }
        let (lr, rr) = (l.b.areas.contains("Rocket"), r.b.areas.contains("Rocket"))
        if lr != rr { return lr }
        if HubTeams.tierRank(l.b) != HubTeams.tierRank(r.b) { return HubTeams.tierRank(l.b) < HubTeams.tierRank(r.b) }
        if l.b.score != r.b.score { return l.b.score > r.b.score }
        return nil
    }

    /// Rule 16: builds with the Rocket or Raids area that hit at least one of the slot's options for more than normal damage; most options hit first, then
    /// built first, then Rocket area, then tier, score, advisor order. One row per copy.
    public static func rocketPicker(options: [HubData.Boss], mode: SquadMode, ctx: HubContext) -> [RocketRow] {
        var rows: [(row: RocketRow, off: Int)] = []
        for (i, b) in ctx.advice.builds.enumerated() where isRocketArea(b) && isUsable(b, mode: mode) {
            let hits = HubTeams.hits(b, options: options, gm: ctx.gm, hub: ctx.hub)
            guard hits > 0 else { continue }
            rows.append((RocketRow(build: b, hits: hits, built: HubSquads.isBuilt(b), typeFlags: typeFlags(b, options: options, ctx: ctx), slotLine: slotLine(hits: hits, of: options.count)), i))
        }
        rows.sort { l, r in
            if l.row.hits != r.row.hits { return l.row.hits > r.row.hits }
            return rocketOrder((l.row.build, l.off, l.row.built), (r.row.build, r.off, r.row.built)) ?? (l.off < r.off)
        }
        var seen = Set<String>()
        return rows.map(\.row).filter { seen.insert($0.entryId).inserted }
    }

    /// Rule 18, one choice when nothing in the box beats the slot.
    public struct NextBest: Equatable {
        public var build: BoxAdvice.Build
        public var built: Bool
        /// How many of the slot's options hit the build for more than normal damage.
        public var weakTo: Int
        /// "Not weak to this slot".
        public var notWeak: Bool { weakTo == 0 }
    }

    /// Rule 18: when no build hits any option (under the mode), the Rocket and Raids builds ordered by fewest of the slot's options that hit them for more
    /// than normal damage, then built first, Rocket area, tier, score; one per species; up to three. Empty when the slot has a picker row.
    public static func rocketNextBest(options: [HubData.Boss], mode: SquadMode, ctx: HubContext) -> [NextBest] {
        guard rocketPicker(options: options, mode: mode, ctx: ctx).isEmpty else { return [] }
        var rows: [(nb: NextBest, off: Int)] = []
        for (i, b) in ctx.advice.builds.enumerated() where isRocketArea(b) && isUsable(b, mode: mode) {
            let mine = HubTeams.types(of: b, gm: ctx.gm)
            let takes = options.filter { ctx.hub.beats($0.types, mine) }.count
            rows.append((NextBest(build: b, built: HubSquads.isBuilt(b), weakTo: takes), i))
        }
        rows.sort { l, r in
            if l.nb.weakTo != r.nb.weakTo { return l.nb.weakTo < r.nb.weakTo }
            return rocketOrder((l.nb.build, l.off, l.nb.built), (r.nb.build, r.off, r.nb.built)) ?? (l.off < r.off)
        }
        var seen = Set<String>()
        return Array(rows.map(\.nb).filter { seen.insert($0.build.targetId).inserted }.prefix(3))
    }

    /// The three slots of a leader's squad. A slot takes the player's pick, else the first picker row not used above it; a slot nothing in the box beats
    /// stays empty (its Next best list is for the player to choose from). Only chosen picks leave another slot's picker (`excluded(..., onlyChosen: true)`).
    public static func defaultRocketSlots() -> [SquadSlot] { Array(repeating: SquadSlot(role: rocketSlotRole), count: 3) }

    public static func rocketSquad(leader: HubData.Leader, slots: [SquadSlot] = defaultRocketSlots(), mode: SquadMode, ctx: HubContext) -> [FilledSlot] {
        let pickers = leader.slots.map { rocketPicker(options: $0, mode: mode, ctx: ctx).map(\.entryId) }
        return fill(slots: slots, pool: { i, _ in Pool(preferred: pickers.indices.contains(i) ? pickers[i] : []) }, placeable: placeable(screen: .rocket, mode: mode, ctx: ctx))
    }

    /// Rule 19: the box's counters for a grunt type: up to eight, one per species, built first, then `HubTeams.gruntCounter`'s order (Rocket area, tier,
    /// score, advisor order); the first is the app's own pick. A typeless grunt (Mixed team, Decoy) reads "Any strong attacker" and lists none.
    public struct GruntCounters: Equatable {
        public var anyAttacker: Bool
        public var builds: [BoxAdvice.Build]
        public var best: BoxAdvice.Build? { builds.first }
    }

    public static func gruntCounters(type: String, mode: SquadMode, ctx: HubContext) -> GruntCounters {
        guard !type.isEmpty else { return GruntCounters(anyAttacker: true, builds: []) }
        // `HubTeams.gruntFit` is the order `gruntCounter` picks from (Rocket area, tier, score, advisor order); the list shows the built ones first.
        let fit = HubTeams.gruntFit(type: type, builds: ctx.advice.builds.filter { isUsable($0, mode: mode) }, gm: ctx.gm, hub: ctx.hub)
        let ordered = fit.filter(HubSquads.isBuilt) + fit.filter { !HubSquads.isBuilt($0) }
        var seen = Set<String>()
        return GruntCounters(anyAttacker: false, builds: Array(ordered.filter { seen.insert($0.targetId).inserted }.prefix(8)))
    }

    /// Rule 20: the types that hit a grunt of this type for more than normal damage, strongest first (the "beaten by" icons).
    public static func beatenBy(gruntType: String, hub: HubData) -> [String] {
        gruntType.isEmpty ? [] : hub.weaknesses(of: [gruntType]).map(\.type)
    }

    // MARK: PvP (rules 22 and 23)

    public enum PvpRole: String, Codable, CaseIterable {
        case lead = "Lead", safeSwap = "Safe swap", closer = "Closer"
    }

    /// Rule 22: from the league table's role text: "lead" = Lead; "safe swap" or "switch" = Safe swap; "closer" = Closer; any number or none.
    public static func pvpRoles(_ text: String) -> [PvpRole] {
        let t = text.lowercased()
        return [t.contains("lead") ? PvpRole.lead : nil, t.contains("safe swap") || t.contains("switch") ? .safeSwap : nil, t.contains("closer") ? .closer : nil].compactMap { $0 }
    }

    public struct PvpCandidate: SquadCandidate, Equatable {
        public var candidate: HubTeams.Candidate
        public var roles: [PvpRole]
        public var entryId: String { candidate.entryId }
        public var roleNames: [String] { roles.map(\.rawValue) }
    }

    /// The league's candidates (`HubTeams.candidates`: best score first, then the better IV rank, one per species) with their roles from the league table.
    /// Under Available only a candidate whose option is the copy itself (rule 3).
    public static func pvpCandidates(league: String, mode: SquadMode, pogoAssist: Bool = false, ctx: HubContext) -> [PvpCandidate] {
        HubTeams.candidates(league: league, advice: ctx.advice, pogoAssist: pogoAssist, allowed: { isUsable($0.option, mode: mode) }).map { c in
            let all = ctx.table.entries(for: c.speciesId, area: league).flatMap { pvpRoles($0.role ?? "") }
            return PvpCandidate(candidate: c, roles: PvpRole.allCases.filter(all.contains))
        }
    }

    public static func defaultPvpSlots() -> [SquadSlot] { PvpRole.allCases.map { SquadSlot(role: $0.rawValue) } }

    /// Rule 23: slots Lead, Safe swap, Closer, each taking the best-scoring unused candidate listed for that role, else (`fallback`) the best-scoring unused
    /// one. Role "All": the best-scoring unused. Coverage is not used to pick.
    public static func pvpSquad(slots: [SquadSlot] = defaultPvpSlots(), candidates: [PvpCandidate], placeable: (String, String) -> Bool) -> [FilledSlot] {
        fill(slots: slots, pool: { _, role in
            let listed = pool(role: role, in: candidates)
            return Pool(preferred: listed, fallback: candidates.map(\.entryId))
        }, placeable: placeable)
    }

    /// The squad's coverage, for display only (D57): how many of the 18 types its members hit for more than normal damage, and which.
    public static func pvpCoverage(of filled: [FilledSlot], candidates: [PvpCandidate], ctx: HubContext) -> (count: Int, types: Set<String>) {
        let team = filled.compactMap { s in candidates.first { $0.entryId == s.entryId }?.candidate }
        let types = HubTeams.covered(team, gm: ctx.gm, hub: ctx.hub)
        return (types.count, types)
    }

}
