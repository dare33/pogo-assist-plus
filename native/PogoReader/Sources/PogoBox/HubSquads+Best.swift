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

    /// A Best row's one status (S1, 31 Oct 2026). `inBox`: the player has it (`needsUpgrade` when its build still needs work, or no build serves it). `canGetNow`: the
    /// box lacks it and a raid, Max or Rocket boss now has it, or the research's obtain line says it can be got (`detail` is that line). `notAvailableNow`: neither;
    /// `detail` says when it is next on, when the schedule knows. No history of past dates is kept.
    public struct BestStatus: Equatable {
        public enum Kind: String, Equatable { case inBox, canGetNow, notAvailableNow }
        public var kind: Kind
        public var needsUpgrade: Bool
        public var detail: String?

        /// The reason a Pokémon the schedule does not list is not available now: no date is invented.
        public static let notOnSchedule = "not on the schedule"
        /// A status for a Pokémon no Best row describes (a stored species pick the lists no longer hold).
        public static let unlisted = BestStatus(kind: .notAvailableNow, needsUpgrade: false, detail: notOnSchedule)

        /// "In your box", "In your box · needs upgrade", "In your box · needs upgrade · no build for this", "Can get now · Raid boss now", "Not available now · Raids from
        /// 9 Nov", "Not available now · not on the schedule". Every status but a plain "In your box" carries its reason.
        public var text: String {
            let why = detail.flatMap { $0.isEmpty ? nil : " · " + $0 } ?? ""
            switch kind {
            case .inBox: return (needsUpgrade ? "In your box · needs upgrade" : "In your box") + why
            case .canGetNow: return "Can get now" + why
            case .notAvailableNow: return "Not available now" + why
            }
        }
    }

    /// One row of a Best list: a Pokémon the table lists for the slot, with what the box has of it. There are three cases: a build or league candidate for the slot
    /// (`build` or `pvp`: the player's best copy or build, with its mark); a copy in the box that no build of this area serves (`copy`: "In your box · no build for
    /// this"); and nothing (`availability` says when it might be had).
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
        /// A copy of the species in the box that no build or candidate of this area and slot serves.
        public var copy: BoxEntry?
        /// The name of a higher row that already shows this row's copy; the copy then reads "same copy as <it>", and a pick of this row is a species pick.
        public var sharedWith: String?
        /// Not in the box: when it might be had (the rotation line, else the table's obtain text). Empty for a Pokémon the box has.
        public var availability: String
        /// The rotation part of `availability` alone ("Raids from 9 Nov"), for a card; nil when the line comes from the obtain text.
        public var rotationLine: String?
        /// Max: one of its types hits the boss for more than normal damage (the suggested Attacker is the first that does).
        public var hitsBoss = false
        /// Rocket: how many of the slot's options its types hit for more than normal damage, the types with that, and the slot line ("beats 2 of 3").
        public var hits: Int = 0
        public var typeFlags: [TypeFlag] = []
        public var slotLine: String? = nil
        /// Its one status (S1): in the box, can be got now, or not available now.
        public var status = BestStatus.unlisted

        public init(key: String, name: String, speciesId: String, tier: String, roles: [String], types: [String], build: BoxAdvice.Build? = nil, pvp: PvpCandidate? = nil,
                    copy: BoxEntry? = nil, sharedWith: String? = nil, availability: String, rotationLine: String? = nil) {
            self.key = key; self.name = name; self.speciesId = speciesId; self.tier = tier; self.roles = roles; self.types = types
            self.build = build; self.pvp = pvp; self.copy = copy; self.sharedWith = sharedWith; self.availability = availability; self.rotationLine = rotationLine
        }

        /// The copy the row shows, whichever way the box has it.
        public var ownedEntryId: String? { build?.entryId ?? pvp?.entryId ?? copy?.id }
        /// A build or candidate serves it (it has a mark); false for a bare copy.
        public var hasBuild: Bool { build != nil || pvp != nil }
        /// The id a pick or a slot holds: the copy's entry id when the box has it and no higher row shows it too, else `squadSpeciesPrefix` + the key (a species pick,
        /// which reads as a copy of the species whenever the box has one).
        public var entryId: String { sharedWith == nil ? (ownedEntryId ?? squadSpeciesPrefix + key) : squadSpeciesPrefix + key }
        public var inBox: Bool { ownedEntryId != nil }
        public var roleNames: [String] { roles }
        /// Every id that stands for this Pokémon in a slot: choosing it clears the others from the squad's other slots.
        public var ids: [String] { var out = [entryId, squadSpeciesPrefix + key] + (ownedEntryId.map { [$0] } ?? []); var seen = Set<String>(); out.removeAll { !seen.insert($0).inserted }; return out }
    }

    private static func speciesTypes(_ id: String, ctx: HubContext) -> [String] {
        ctx.gm.byId[id]?.types ?? ctx.gm.byId[id.replacingOccurrences(of: "_shadow", with: "")]?.types ?? []
    }

    /// The key of a table entry: its species id, with `_shadow` for a Shadow the table lists under the plain id ("Shadow Pheromosa"), so two Pokémon never share one.
    static func bestKey(_ e: TierTable.Entry) -> String { e.flags.shadow && !e.speciesId.hasSuffix("_shadow") ? e.speciesId + "_shadow" : e.speciesId }

    /// The keys a build fills. A Shadow copy fills its Shadow row, and where Shadows may serve (`shadowServesPlain`: Raids and Rocket) the plain row too, as `raidEntries`
    /// does; on the Gym and in Max a Shadow copy fills nothing (a Shadow cannot defend a gym or go Dynamax).
    static func buildKeys(_ b: BoxAdvice.Build, shadowServesPlain: Bool, ctx: HubContext) -> [String] {
        let plain = b.targetId.hasSuffix("_shadow") ? String(b.targetId.dropLast("_shadow".count)) : b.targetId
        // A Purified copy (mark 2) is not a Shadow even when its target ends `_shadow`: it fills the plain row only.
        guard HubRaidsModel.isShadow(b, entries: ctx.entries) else { return [plain] }
        return shadowServesPlain ? [plain + "_shadow", plain] : []
    }

    private static func keyedBuilds(_ builds: [BoxAdvice.Build], shadowServesPlain: Bool, ctx: HubContext) -> [String: [BoxAdvice.Build]] {
        var out = [String: [BoxAdvice.Build]]()
        for b in builds { for k in buildKeys(b, shadowServesPlain: shadowServesPlain, ctx: ctx) { out[k, default: []].append(b) } }
        return out
    }

    /// The box's copies by species key (Shadow copies under `x_shadow`, and under the plain key too when `shadowServesPlain`), best CP first.
    private static func copyIndex(shadowServesPlain: Bool = false, ctx: HubContext) -> [String: [BoxEntry]] {
        var out = [String: [BoxEntry]]()
        for e in ctx.entries {
            let base = e.row.speciesId.replacingOccurrences(of: "_shadow", with: "")
            if HubRaidsModel.isShadow(e) { out[base + "_shadow", default: []].append(e); if shadowServesPlain { out[base, default: []].append(e) } } else { out[base, default: []].append(e) }
        }
        return out.mapValues { $0.sorted { $0.row.cp > $1.row.cp } }
    }

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

    /// What the box has for one table row: a build, else a copy no build of the area serves. A copy shows against one row at a time: when the only one a row has is
    /// already shown by a higher row, the row still lists it, with that row's name in `sharedWith`. Rows are asked in rank order, so `claims` (entry id to the name of the
    /// row showing it) is built as they go.
    private struct Owner {
        var build: BoxAdvice.Build?
        var copy: BoxEntry?
        var sharedWith: String?
    }

    private static func owner(_ e: TierTable.Entry, builds: [BoxAdvice.Build], screen: SquadScreen, copies: [String: [BoxEntry]], claims: inout [String: String], ctx: HubContext) -> Owner {
        let name = displayName(e)
        if !builds.isEmpty {
            if let b = bestBuild(builds.filter { claims[$0.entryId] == nil }, screen: screen, ctx: ctx) { claims[b.entryId] = name; return Owner(build: b) }
            let b = bestBuild(builds, screen: screen, ctx: ctx)!
            return Owner(build: b, sharedWith: claims[b.entryId])
        }
        let mine = copies[bestKey(e)] ?? []
        if let c = mine.first(where: { claims[$0.id] == nil }) { claims[c.id] = name; return Owner(copy: c) }
        if let c = mine.first { return Owner(copy: c, sharedWith: claims[c.id]) }
        return Owner()
    }

    private static func displayName(_ e: TierTable.Entry) -> String { e.name.hasPrefix("Dynamax ") ? String(e.name.dropFirst("Dynamax ".count)) : e.name }

    private static func bestRow(_ e: TierTable.Entry, roles: [String], owner o: Owner = Owner(), pvp: PvpCandidate? = nil, kinds: [HubData.Kind]? = nil, screen: SquadScreen, ctx: HubContext) -> BestRow {
        let owned = o.build != nil || o.copy != nil || pvp != nil
        let parts = availabilityParts(of: e, kinds: kinds, ctx: ctx)
        var row = BestRow(key: bestKey(e), name: displayName(e), speciesId: e.speciesId, tier: e.tier, roles: roles, types: speciesTypes(e.speciesId, ctx: ctx), build: o.build, pvp: pvp,
                          copy: o.copy, sharedWith: o.sharedWith, availability: owned ? "" : parts.text, rotationLine: owned ? nil : parts.rotation)
        // Rule 6, S1: exactly one status per row. A copy with a build needs an upgrade unless that build is at Full strength; a copy no build serves always does.
        if owned {
            let needs = o.build.map { !isFullStrength($0, screen: screen, ctx: ctx) } ?? pvp.map { !$0.candidate.built } ?? true
            row.status = BestStatus(kind: .inBox, needsUpgrade: needs, detail: o.build == nil && pvp == nil ? "no build for this" : nil)
        } else if parts.canGetNow {
            row.status = BestStatus(kind: .canGetNow, needsUpgrade: false, detail: parts.text)
        } else {
            row.status = BestStatus(kind: .notAvailableNow, needsUpgrade: false, detail: parts.rotation ?? BestStatus.notOnSchedule)
        }
        return row
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

    /// The rotation's line for a Pokémon, nil when it is no boss now or later. A boss is the entry's Pokémon only when the Shadow state agrees (Shadow Giratina is not
    /// the plain Giratina raid). Kinds that carry no boss (Raid Hour, other) are never read. Under way: "Raid boss now" / "Max battle now", and for a one-day event
    /// "<title> today" ("Max Monday today"). Coming: "Raids from 9 Nov", "Max battles from 16 Nov", and for a one-day event "<title> <day>" ("Max Monday 2 Nov").
    /// `now` is true for a line under way.
    static func rotationInfo(of e: TierTable.Entry, kinds: [HubData.Kind]? = nil, ctx: HubContext) -> (line: String, now: Bool)? {
        let wantShadow = e.flags.shadow || e.speciesId.hasSuffix("_shadow")
        let base = e.speciesId.replacingOccurrences(of: "_shadow", with: "")
        func isBoss(_ b: HubData.Boss) -> Bool {
            (b.speciesId.hasSuffix("_shadow") || b.shadow == true) == wantShadow && b.speciesId.replacingOccurrences(of: "_shadow", with: "") == base
        }
        let rows = ctx.hub.rotation.filter { $0.to >= ctx.today && (kinds ?? raidKinds + maxKinds).contains($0.kind) && $0.bosses.contains(where: isBoss) }
        func line(_ r: HubData.RotationRow, now: Bool) -> String {
            let raid = raidKinds.contains(r.kind)
            if r.from == r.to { return now ? "\(r.title) today" : "\(r.title) \(dayMonth(r.from))" }
            if now { return raid ? "Raid boss now" : "Max battle now" }
            return (raid ? "Raids from " : "Max battles from ") + dayMonth(r.from)
        }
        let under = rows.filter { $0.from <= ctx.today }
        if let r = under.first(where: { raidKinds.contains($0.kind) }) ?? under.first { return (line(r, now: true), true) }
        if let r = rows.filter({ $0.from > ctx.today }).min(by: { ($0.from, $0.to) < ($1.from, $1.to) }) { return (line(r, now: false), false) }
        return nil
    }

    static func rotationLine(of e: TierTable.Entry, kinds: [HubData.Kind]? = nil, ctx: HubContext) -> String? { rotationInfo(of: e, kinds: kinds, ctx: ctx)?.line }

    /// A Rocket entry whose Pokémon a leader brings now, with the Shadow state agreeing as for a raid boss. Only the slot the player can catch counts (manager call,
    /// 31 Oct 2026: `data/hub.json` does not mark it, so the rule is here): Giovanni's third slot, the first slot of every other leader.
    static func isRocketBossNow(_ e: TierTable.Entry, ctx: HubContext) -> Bool {
        let wantShadow = e.flags.shadow || e.speciesId.hasSuffix("_shadow")
        let base = e.speciesId.replacingOccurrences(of: "_shadow", with: "")
        return ctx.hub.leaders.contains { leader in
            let at = leader.name == "Giovanni" ? 2 : 0
            return leader.slots.indices.contains(at) && leader.slots[at].contains { ($0.speciesId.hasSuffix("_shadow") || $0.shadow == true) == wantShadow && $0.speciesId.replacingOccurrences(of: "_shadow", with: "") == base }
        }
    }

    /// Whether the research's obtain line says a Pokémon the schedule does not list can be got now (S1, manager call 31 Oct 2026). All of: the difficulty word (up to the
    /// first full stop) is Easy or Medium, with no range to Hard and no slash; the row is not a Mega, Primal, Legendary, Mythical or Ultra Beast (those come through
    /// events, so the schedule decides); the line names no month or year (it is about a past or future run). The line has no dates of its own, so this reads it, it does not know.
    static func obtainableNow(_ obtain: String, entry e: TierTable.Entry, ctx: HubContext) -> Bool {
        let head = obtain.split(separator: ".", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
        guard head.contains("easy") || head.contains("medium"), !head.contains("hard"), !head.contains("locked"), !head.contains("/") else { return false }
        guard obtain.range(of: #"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec|January|February|March|April|June|July|August|September|October|November|December)\b|\b20[0-9]{2}\b"#, options: .regularExpression) == nil else { return false }
        if e.flags.mega || e.speciesId.contains("_mega") || e.speciesId.contains("_primal") { return false }
        let base = e.speciesId.replacingOccurrences(of: "_shadow", with: "")
        let tags = (ctx.gm.byId[e.speciesId] ?? ctx.gm.byId[base]).map(\.tags) ?? []
        return !tags.contains { ["mega", "legendary", "mythical", "ultrabeast"].contains($0) }
    }

    /// When a Pokémon the box lacks can be had. `rotation` is the schedule's line (a boss now or coming, or "Rocket boss now"); `text` the line a plain list shows (the
    /// rotation line, else the table's obtain text, else empty); `canGetNow`: the schedule has it under way, a Rocket leader brings it now, or, when the schedule never lists
    /// it, the obtain line reads as obtainable now. A schedule that lists it only later wins over the obtain line: a legend that is a boss next week is not got now.
    static func availabilityParts(of e: TierTable.Entry, kinds: [HubData.Kind]? = nil, ctx: HubContext) -> (rotation: String?, text: String, canGetNow: Bool) {
        let info = rotationInfo(of: e, kinds: kinds, ctx: ctx)
        if let info, info.now { return (info.line, info.line, true) }
        if e.area == "rocket", isRocketBossNow(e, ctx: ctx) { return ("Rocket boss now", "Rocket boss now", true) }
        let obtain = (e.obtain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let info { return (info.line, info.line, false) }
        return (nil, obtain, obtainableNow(obtain, entry: e, ctx: ctx))
    }

    /// When a Pokémon the box lacks might be had: the rotation line when it is a boss now or coming, else the table's obtain text ("Medium. T5 raids"); empty when the
    /// table has none either.
    public static func availability(of e: TierTable.Entry, ctx: HubContext) -> String { availabilityParts(of: e, ctx: ctx).text }

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
        let copies = copyIndex(shadowServesPlain: true, ctx: ctx)
        var claims = [String: String]()
        return ranked(items, secondary: { bring.firstIndex(of: $0.section.lowercased()) ?? bring.count }).map { r in
            bestRow(r.e, roles: r.roles, owner: owner(r.e, builds: fills[bestKey(r.e)] ?? [], screen: .raids, copies: copies, claims: &claims, ctx: ctx), screen: .raids, ctx: ctx)
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
        let copies = copyIndex(ctx: ctx)
        var claims = [String: String]()
        let byKey = keyedBuilds(plainBuilds(ctx.advice.builds).filter { $0.areas.contains("Max") }, shadowServesPlain: false, ctx: ctx)
        return ranked(items, secondary: { PogoRules.hitsAnyBoss(speciesTypes($0.speciesId, ctx: ctx), row: row, hub: ctx.hub) ? 0 : 1 }).map { r in
            // A Max entry's rotation is the Max battles' only (a raid boss of the same species is no Max battle).
            var out = bestRow(r.e, roles: r.roles, owner: owner(r.e, builds: byKey[bestKey(r.e)] ?? [], screen: .max, copies: copies, claims: &claims, ctx: ctx), kinds: maxKinds, screen: .max, ctx: ctx)
            out.hitsBoss = PogoRules.hitsAnyBoss(out.types, row: row, hub: ctx.hub)
            return out
        }
    }

    // MARK: Gym

    /// Best for the Gym: the Gym table's entries, best tier first, then the table's order. The box's build for an entry is a Gym build whose target is that species.
    public static func bestGymRows(ctx: HubContext) -> [BestRow] {
        let items = ctx.table.entries.enumerated().compactMap { i, e -> (e: TierTable.Entry, index: Int, roles: [String])? in e.area == "gym" ? (e, i, [gymSlotRole]) : nil }
        let copies = copyIndex(ctx: ctx)
        var claims = [String: String]()
        let byKey = keyedBuilds(HubTeams.gymAvailable(builds: plainBuilds(ctx.advice.builds)), shadowServesPlain: false, ctx: ctx)
        return ranked(items).map { r in
            bestRow(r.e, roles: r.roles, owner: owner(r.e, builds: byKey[bestKey(r.e)] ?? [], screen: .gym, copies: copies, claims: &claims, ctx: ctx), screen: .gym, ctx: ctx)
        }
    }

    /// The Gym table's tier for a build's target (S, A or B); "" when the table does not list it (rule 29 reads that as needing work).
    public static func gymTableTier(_ b: BoxAdvice.Build, ctx: HubContext) -> String {
        ctx.table.entries(for: b.targetId, area: "gym").map(\.tier).min { PogoRules.tierRank($0) < PogoRules.tierRank($1) } ?? ""
    }

    // MARK: Team Rocket

    /// Best for one slot of a leader's lineup: the Rocket table's entries whose types hit at least one of the slot's options for more than normal damage, best tier
    /// first, then the table's order. The box's build for an entry is a Rocket or Raids build whose target is that species (a Shadow copy serves the Shadow row too).
    public static func bestRocketRows(options: [HubData.Boss], ctx: HubContext) -> [BestRow] {
        let items = ctx.table.entries.enumerated().compactMap { i, e -> (e: TierTable.Entry, index: Int, roles: [String])? in
            guard e.area == "rocket", options.contains(where: { ctx.hub.beats(speciesTypes(e.speciesId, ctx: ctx), $0.types) }) else { return nil }
            return (e, i, [])
        }
        let copies = copyIndex(shadowServesPlain: true, ctx: ctx)
        var claims = [String: String]()
        let byKey = keyedBuilds(plainBuilds(ctx.advice.builds).filter(isRocketArea), shadowServesPlain: true, ctx: ctx)
        return ranked(items).map { r in
            var out = bestRow(r.e, roles: r.roles, owner: owner(r.e, builds: byKey[bestKey(r.e)] ?? [], screen: .rocket, copies: copies, claims: &claims, ctx: ctx), screen: .rocket, ctx: ctx)
            out.hits = options.filter { ctx.hub.beats(out.types, $0.types) }.count
            out.typeFlags = out.types.map { t in TypeFlag(type: t, hits: options.contains { ctx.hub.beats([t], $0.types) }) }
            out.slotLine = slotLine(hits: out.hits, of: options.count)
            return out
        }
    }

    /// The Rocket table's tier for a build's target (a Shadow copy reads the Shadow entry first); "" when the table does not list it.
    public static func rocketTableTier(_ b: BoxAdvice.Build, ctx: HubContext) -> String {
        let shadow = HubRaidsModel.isShadow(b, entries: ctx.entries)
        let es = (ctx.table.entries(for: b.targetId, area: "rocket") + (shadow ? ctx.table.entries(for: b.targetId + "_shadow", area: "rocket") : [])).filter { shadow || !$0.flags.shadow }
        return es.map(\.tier).min { PogoRules.tierRank($0) < PogoRules.tierRank($1) } ?? ""
    }

    // MARK: PvP

    /// Best for a league: its table's entries, best tier first, then the table's # (its rank), with the roles the table's role text gives. The box's copy of an entry
    /// is the league candidate of that species (`pvpCandidates`, which needs a score of `HubTeams.candidateFloor` or more and is not past the cap); a copy of the species
    /// that is not a candidate reads "In your box · needs upgrade · no build for this".
    public static func bestPvpRows(league: String, pogoAssist: Bool = false, ctx: HubContext) -> [BestRow] {
        let items = ctx.table.entries.enumerated().compactMap { i, e -> (e: TierTable.Entry, index: Int, roles: [String])? in
            e.area == league ? (e, i, PvpRole.allCases.filter(pvpRoles(e.role ?? "").contains).map(\.rawValue)) : nil
        }
        var owned = [String: PvpCandidate]()
        var claims = [String: String]()
        for c in pvpCandidates(league: league, mode: .best, pogoAssist: pogoAssist, ctx: ctx) {
            if owned[c.candidate.speciesId] == nil { owned[c.candidate.speciesId] = c }
            claims[c.entryId] = c.candidate.name
        }
        let copies = copyIndex(ctx: ctx)
        return ranked(items).map { r in
            if let c = owned[r.e.speciesId] { return bestRow(r.e, roles: r.roles, pvp: c, screen: .pvp, ctx: ctx) }
            return bestRow(r.e, roles: r.roles, owner: owner(r.e, builds: [], screen: .pvp, copies: copies, claims: &claims, ctx: ctx), screen: .pvp, ctx: ctx)
        }
    }

    /// The league tier the screens show for a member: the table's, else the 88-score band (`LeaguePanel.tier(speciesId:key:score:)`). "" when neither.
    public static func pvpTier(speciesId: String, league: String, score: Double?) -> String { LeaguePanel.tier(speciesId: speciesId, key: league, score: score) ?? "" }

    // MARK: rule 6: a Best pick that the box now has

    /// A species pick for a Pokémon the box has since got is read as a copy of it, whichever row shows that copy: the slot then shows the copy, not "Not in your box".
    /// The stored pick is left alone (it is the player's choice of the species).
    public static func resolvingSpecies(_ slots: [SquadSlot], rows: [BestRow]) -> [SquadSlot] {
        slots.map { s in
            guard s.pick == nil, let key = s.species, let own = rows.first(where: { $0.key == key })?.ownedEntryId else { return s }
            return SquadSlot(role: s.role, pick: own)
        }
    }

    /// A slot filled from a species pick keeps the species too (`FilledSlot.species`), so the screen can show the row the player chose, not the row that happens to
    /// show the same copy.
    private static func keepingSpecies(_ filled: [FilledSlot], _ slots: [SquadSlot], rows: [BestRow]) -> [FilledSlot] {
        var out = filled
        for i in out.indices where i < slots.count && slots[i].pick == nil && out[i].entryId != nil && out[i].chosen {
            if let key = slots[i].species, rows.contains(where: { $0.key == key }) { out[i].species = key }
        }
        return out
    }

    /// The ids that stand for the Pokémon with this pick id in the Best lists: every id of every row that shows the same copy (Primal Kyogre and Kyogre are two rows of
    /// one copy), its species ids included. Choosing it clears all of them from the squad's other slots. Pass the rows of every list the squad draws on (all of a
    /// Rocket leader's slots).
    public static func equivalents(of id: String, rows: [BestRow]) -> [String] {
        let seeds = rows.filter { $0.ids.contains(id) }
        let copies = Set(seeds.compactMap(\.ownedEntryId) + [id])
        var out = [id]
        for r in rows where !copies.isDisjoint(with: r.ids) || (r.ownedEntryId.map(copies.contains) ?? false) { for x in r.ids where !out.contains(x) { out.append(x) } }
        return out
    }

    /// The copy an id stands for in these rows: a copy's own id is itself, a species id the box has a copy of resolves to that copy, any other species id to nil.
    public static func copyResolver(rows: [BestRow]) -> (String) -> String? {
        var map = [String: String]()
        for r in rows { if let c = r.ownedEntryId { map[r.entryId] = c; map[squadSpeciesPrefix + r.key] = c; map[c] = c } }
        return { id in map[id] ?? (id.hasPrefix(squadSpeciesPrefix) ? nil : id) }
    }

    /// The ids a slot's row is ticked under: only the row the player picked (a species pick that reads as a copy ticks its own row, not a higher row that shows the same copy).
    public static func tickIds(_ f: FilledSlot, rows: [BestRow]) -> Set<String> {
        if let key = f.species { return [rows.first { $0.key == key }?.entryId ?? squadSpeciesPrefix + key] }
        return f.entryId.map { [$0] } ?? []
    }

    /// A leader's Best squad: each slot takes the player's pick, else the first unused row of the Rocket table that beats that slot (`bestRocketRows`).
    public static func bestRocketSquad(leader: HubData.Leader, slots: [SquadSlot] = defaultRocketSlots(), ctx: HubContext) -> [FilledSlot] {
        let rows = leader.slots.map { bestRocketRows(options: $0, ctx: ctx) }
        let all = rows.flatMap { $0 }
        return keepingSpecies(fill(slots: resolvingSpecies(slots, rows: all), pool: { i, _ in Pool(preferred: rows.indices.contains(i) ? rows[i].map(\.entryId) : []) },
                                   copyOf: copyResolver(rows: all)), slots, rows: all)
    }

    /// The Best squad's slots: each takes the player's pick, else the first unused row of the ranked list for its role. A Max Attacker slot takes the first row that
    /// hits the boss when there is one, even over a higher tier that does not (rule 12).
    /// With `oneMega` (raids) a squad holds one Mega: once a slot holds a Mega row, no later slot takes one (the fill skips it).
    public static func bestSquad(slots: [SquadSlot], rows: [BestRow], fallback: Bool = false, oneMega: Bool = false) -> [FilledSlot] {
        let megaIds = oneMega ? megaRowIds(rows) : []
        return keepingSpecies(fill(slots: resolvingSpecies(slots, rows: rows), pool: { _, role in
            var listed = pool(role: role, in: rows)
            if role == PogoRules.MaxRole.attacker.rawValue {
                let hits = Set(rows.filter(\.hitsBoss).map(\.entryId))
                listed = listed.filter(hits.contains) + listed.filter { !hits.contains($0) }
            }
            return Pool(preferred: listed, fallback: fallback ? rows.map(\.entryId) : [])
        }, copyOf: copyResolver(rows: rows), allows: { id, _, out in megaIds.isEmpty || !megaIds.contains(id) || !out.contains { $0.pickId.map(megaIds.contains) ?? false } }), slots, rows: rows)
    }

    /// Every id of a Mega row of a raid Best list (the row's own id and its species id).
    public static func megaRowIds(_ rows: [BestRow]) -> Set<String> {
        Set(rows.filter { $0.roles.contains(PogoRules.RaidRole.mega.rawValue) }.flatMap(\.ids))
    }

    /// The Mega rows another slot's Pokémon rules out of the edited slot's picker: once any other slot holds a Mega, no Mega row is offered (the edited slot's own stays, ticked).
    public static func megaExcluded(by filled: [FilledSlot], editing: Int, rows: [BestRow]) -> Set<String> {
        let megas = megaRowIds(rows)
        let held = filled.enumerated().contains { $0.offset != editing && $0.element.ids.contains(where: megas.contains) }
        return held ? megas : []
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
