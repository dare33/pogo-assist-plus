import Foundation
import PogoReader

/// Design pass 3: how one copy fits each activity, for the activity tabs on the Pokémon page (CONCEPTS rules 10 to 16). The tabs look at the copy's
/// species and the evolutions below it (`PogoRules.reach`). Pure: the box, advice, rotation and "today" come in through `HubContext`.
/// Bulk, "a type hits X", the Max and raid roles and reach are `PogoRules`' (shared with pass 2); the Gym yardstick is pass 2's Gym order.
public enum PokemonActivities {
    public enum Tab: String, CaseIterable {
        case summary, pvp, raids, gym, rocket, max
        /// Rule 19: the tabs read Summary, PvP, Raids, Gym, Rocket, Max.
        public var title: String { ["summary": "Summary", "pvp": "PvP", "raids": "Raids", "gym": "Gym", "rocket": "Rocket", "max": "Max"][rawValue] ?? rawValue }
    }

    /// The five activities of the Summary tab, in the order its rows come: PvP leagues first (D8).
    public enum Activity: String, CaseIterable { case pvp, raids, gym, rocket, max }

    // MARK: the member of reach

    public struct Member: Equatable {
        public var id: String
        public var name: String
        public var types: [String]
    }

    /// Rule 10: the copy's species and the evolutions below it, breadth first.
    public static func members(of copy: BoxEntry, ctx: HubContext) -> [Member] {
        PogoRules.reach(of: copy.row.speciesId, gm: ctx.gm).map { Member(id: $0, name: ctx.gm.byId[$0]?.name ?? $0, types: ctx.gm.byId[$0]?.types ?? []) }
    }

    /// The copy's own build of an area that targets a reachable member (the "plan"), nil when it has none.
    private static func ownBuild(_ copy: BoxEntry, area: String, member: String, ctx: HubContext) -> BoxAdvice.Build? {
        ctx.advice.builds.first { $0.entryId == copy.id && $0.areas.contains(area) && $0.targetId == member }
    }

    /// A plan on a card: this copy's build for the member, and whether it is at full strength.
    public struct Plan: Equatable {
        public var build: BoxAdvice.Build
        public var built: Bool
    }

    // MARK: rule 11: the Raids tab

    public enum RaidPlan: Equatable {
        /// This copy's own Raids build for the member.
        case mine(Plan)
        /// The box's best Raids build for the type (tier, then built): another copy, or this copy under another member.
        case best(Plan, tier: String)
        case none
    }

    /// A raid or Max battle a card counters, with the name the Summary line uses.
    public struct BossRow: Equatable {
        public var entry: HubRaidsModel.Entry
        public var isNow: Bool { entry.isNow }
        /// "now" or "in 3 d".
        public var when: String { HubRaidsModel.dateColumn(entry).when }
    }

    public struct RaidCard: Equatable {
        public var member: Member
        /// The attacking type the Raids table lists the member under (lowercase).
        public var type: String
        public var tier: String
        public var role: PogoRules.RaidRole
        public var plan: RaidPlan
        /// The raids on now and coming whose bring types include the type, now first, up to six.
        public var counters: [BossRow]
        /// How many raids that is before the cap of six.
        public var counterCount: Int
    }

    /// The box's best Raids build for each attacking type: tier first, then built, then the advisor's order.
    static func bestRaidBuilds(ctx: HubContext) -> [String: (build: BoxAdvice.Build, tier: String)] {
        var best = [String: (build: BoxAdvice.Build, tier: String)]()
        for b in ctx.advice.builds where b.areas.contains("Raids") {
            let shadow = HubRaidsModel.isShadow(b, entries: ctx.entries)
            let built = HubSquads.isFullStrength(b, screen: .raids, ctx: ctx)
            let own = ctx.gm.byId[b.targetId]?.types ?? []
            let entries = HubRaidsModel.raidEntries(targetId: b.targetId, viaMega: b.viaMega, table: ctx.table, shadow: shadow)
            for e in entries {
                for type in HubRaidsModel.entryTypes(e, in: entries, speciesTypes: own) {
                    if let cur = best[type] {
                        let curBuilt = HubSquads.isFullStrength(cur.build, screen: .raids, ctx: ctx)
                        let better = PogoRules.tierRank(e.tier) < PogoRules.tierRank(cur.tier) || (PogoRules.tierRank(e.tier) == PogoRules.tierRank(cur.tier) && built && !curBuilt)
                        if !better { continue }
                    }
                    best[type] = (b, e.tier)
                }
            }
        }
        return best
    }

    /// Rule 11: one card per reachable member and attacking type the Raids table lists (a Shadow entry only for a Shadow copy), best tier first, then the
    /// type with more raids to counter, then the order of reach and the table.
    public static func raidCards(copy: BoxEntry, ctx: HubContext) -> [RaidCard] {
        let timeline = HubRaidsModel.timeline(rows: ctx.hub.rotation, screen: .raids, today: ctx.today)
        let rows = (timeline.now + timeline.comingUp).filter { !$0.row.bosses.isEmpty }
        let best = bestRaidBuilds(ctx: ctx)
        let shadow = HubRaidsModel.isShadow(copy)
        var cards: [RaidCard] = []
        for m in members(of: copy, ctx: ctx) {
            // A member is a species, not a build: no Mega route here (a Mega-route build is credited in `bestRaidBuilds`).
            let entries = HubRaidsModel.raidEntries(targetId: m.id, viaMega: false, table: ctx.table, shadow: shadow)
            for (e, type) in entries.flatMap({ e in HubRaidsModel.entryTypes(e, in: entries, speciesTypes: m.types).map { (e, $0) } }) {
                let plan: RaidPlan
                if let mine = ownBuild(copy, area: "Raids", member: m.id, ctx: ctx) {
                    plan = .mine(Plan(build: mine, built: HubSquads.isFullStrength(mine, screen: .raids, ctx: ctx)))
                } else if let b = best[type] {
                    plan = .best(Plan(build: b.build, built: HubSquads.isFullStrength(b.build, screen: .raids, ctx: ctx)), tier: b.tier)
                } else {
                    plan = .none
                }
                let all = rows.filter { HubRaidsModel.bring(row: $0.row, hub: ctx.hub).contains(type) }
                cards.append(RaidCard(member: m, type: type, tier: e.tier,
                                      role: PogoRules.raidRole(targetId: m.id, viaMega: false, shadow: shadow, gm: ctx.gm), plan: plan,
                                      counters: all.prefix(6).map(BossRow.init), counterCount: all.count))
            }
        }
        return cards.enumerated().sorted { l, r in
            let (a, b) = (l.element, r.element)
            if PogoRules.tierRank(a.tier) != PogoRules.tierRank(b.tier) { return PogoRules.tierRank(a.tier) < PogoRules.tierRank(b.tier) }
            if a.counterCount != b.counterCount { return a.counterCount > b.counterCount }
            return l.offset < r.offset
        }.map(\.element)
    }

    // MARK: rule 12: the Gym tab

    /// The Gym yardstick: the first of the Gym screen's six suggested defenders (pass 2's order) whose bulk is worked out. When the first has no level
    /// read, the next with a figure stands in, because a share needs a number.
    public struct TopDefender: Equatable {
        public var build: BoxAdvice.Build
        /// The copy's bulk as the build's target at the copy's CURRENT level (pass 3's Bulk term; pass 2's Gym screen works rule 14 at the target level).
        public var bulk: Double
        public var entryId: String { build.entryId }
        public var name: String { build.targetName }
    }

    public static func topDefender(mode: SquadMode = .available, ctx: HubContext) -> TopDefender? {
        HubSquads.gymRows(mode: mode, ctx: ctx).prefix(6).lazy.compactMap { r -> TopDefender? in
            guard let copy = ctx.entry(r.build.entryId),
                  let bulk = PogoRules.bulk(target: r.build.targetId, ivs: copy.row.ivs, level: copy.row.level, gm: ctx.gm).value else { return nil }
            return TopDefender(build: r.build, bulk: bulk)
        }.first
    }

    public struct GymCard: Equatable {
        public var member: Member
        public var tier: String
        /// This copy's bulk as the member, at its current level (rule 12; no level is assumed).
        public var bulk: PogoRules.Bulk
        /// The bulk over the top defender's, in whole per cent ("45% of the top"); nil when either is not known.
        public var share: Int?
        /// The bar's length, 0 to 1.
        public var barFraction: Double? { share.map { min(1, Double($0) / 100) } }
        /// This copy IS the top defender (its entry id, as the member the top defender's build targets): the card reads "Your top defender".
        public var isTop: Bool
        public var plan: Plan?
    }

    /// Rule 12: one card per reachable member the Gym table lists, best tier then bulk (a bulk not worked out after those that are).
    public static func gymCards(copy: BoxEntry, ctx: HubContext, top: TopDefender?) -> [GymCard] {
        var cards: [GymCard] = []
        for m in members(of: copy, ctx: ctx) {
            for e in ctx.table.entries(for: m.id, area: "gym") {
                let bulk = PogoRules.bulk(target: m.id, ivs: copy.row.ivs, level: copy.row.level, gm: ctx.gm)
                let share: Int? = bulk.value.flatMap { v in top.map { Int((v / $0.bulk * 100).rounded()) } }
                let mine = ownBuild(copy, area: "Gym", member: m.id, ctx: ctx).map { Plan(build: $0, built: HubSquads.isFullStrength($0, screen: .gym, ctx: ctx)) }
                cards.append(GymCard(member: m, tier: e.tier, bulk: bulk, share: share, isTop: top?.entryId == copy.id && top?.build.targetId == m.id, plan: mine))
            }
        }
        return cards.enumerated().sorted { l, r in
            let (a, b) = (l.element, r.element)
            if PogoRules.tierRank(a.tier) != PogoRules.tierRank(b.tier) { return PogoRules.tierRank(a.tier) < PogoRules.tierRank(b.tier) }
            switch (a.bulk.value, b.bulk.value) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return l.offset < r.offset
            }
        }.map(\.element)
    }

    // MARK: rule 13: the Rocket tab

    public struct LeaderSlotBeat: Equatable {
        public var leader: String
        /// 1 to 3.
        public var slot: Int
        /// The slot's options the member's types hit for more than normal damage, without "Shadow ".
        public var beats: [String]
        public var of: Int
    }

    public struct RocketCard: Equatable {
        public var member: Member
        public var gruntTypes: [String]
        public var leaderSlots: [LeaderSlotBeat]
        public var plan: Plan?
        public var tier: String?
    }

    /// Rule 13: a member beats a grunt type or a leader option when one of its own types hits it for more than normal damage (moves are not checked: the
    /// export has none). A member that beats a leader option but no grunt type is still listed. Up to four: most grunt types first, then most leader
    /// options beaten, then the later evolution.
    static func rocketCard(_ m: Member, copy: BoxEntry, ctx: HubContext) -> RocketCard {
            var seen = Set<String>()
            let grunts = ctx.hub.grunts.map(\.type).filter { !$0.isEmpty && ctx.hub.beats(m.types, [$0]) && seen.insert($0).inserted }
            var slots: [LeaderSlotBeat] = []
            for l in ctx.hub.leaders {
                for (i, options) in l.slots.enumerated() {
                    let beaten = options.filter { ctx.hub.beats(m.types, $0.types) }.map { HubTeams.plain($0.name) }
                    if !beaten.isEmpty { slots.append(LeaderSlotBeat(leader: l.name, slot: i + 1, beats: beaten, of: options.count)) }
                }
            }
            let mine = ownBuild(copy, area: "Rocket", member: m.id, ctx: ctx).map { Plan(build: $0, built: HubSquads.isFullStrength($0, screen: .rocket, ctx: ctx)) }
            return RocketCard(member: m, gruntTypes: grunts, leaderSlots: slots, plan: mine, tier: ctx.table.entries(for: m.id, area: "rocket").map(\.tier).min { PogoRules.tierRank($0) < PogoRules.tierRank($1) })
    }

    public static func rocketCards(copy: BoxEntry, ctx: HubContext) -> [RocketCard] {
        let cards = members(of: copy, ctx: ctx).map { rocketCard($0, copy: copy, ctx: ctx) }.filter { !$0.gruntTypes.isEmpty || !$0.leaderSlots.isEmpty }
        func options(_ c: RocketCard) -> Int { c.leaderSlots.reduce(0) { $0 + $1.beats.count } }
        return Array(cards.enumerated().sorted { l, r in
            let (a, b) = (l.element, r.element)
            if a.gruntTypes.count != b.gruntTypes.count { return a.gruntTypes.count > b.gruntTypes.count }
            if options(a) != options(b) { return options(a) > options(b) }
            return l.offset > r.offset
        }.map(\.element).prefix(4))
    }

    // MARK: rule 14: the Max tab

    public struct MaxCard: Equatable {
        public var member: Member
        public var tier: String
        public var roles: [PogoRules.MaxRole]
        /// The table's role text ("Tank and healer"), else its section ("Attackers").
        public var roleText: String
        public var plan: Plan?
        /// True until the copy carries the Dynamax mark (`row.dynamax == true`).
        public var needsDynamax: Bool
    }

    /// A Max battle on now or coming that some reachable member's types hit, with the members that do.
    public struct MaxBattle: Equatable {
        public var row: BossRow
        public var by: [String]
    }

    /// Rule 14: the reachable members the Max table lists (Gigantamax entries are not used here), and the Max battles on now and coming that a member's
    /// types hit, now first.
    public static func maxCards(copy: BoxEntry, ctx: HubContext) -> (cards: [MaxCard], battles: [MaxBattle]) {
        let timeline = HubRaidsModel.timeline(rows: ctx.hub.rotation, screen: .max, today: ctx.today)
        let rows = (timeline.now + timeline.comingUp).filter { !$0.row.bosses.isEmpty }
        var cards: [MaxCard] = []
        var by = [[String]](repeating: [], count: rows.count)
        for m in members(of: copy, ctx: ctx) {
            // One card per member: several usable table entries merge (best tier, the roles of all of them).
            let entries = HubRaidsModel.maxEntries(m.id, ctx.table)
            if let best = entries.map(\.tier).min(by: { PogoRules.tierRank($0) < PogoRules.tierRank($1) }) {
                let roles = Set(entries.flatMap(PogoRules.maxRoles))
                let ordered = PogoRules.MaxRole.allCases.filter(roles.contains)
                // The tables' own wording for each entry ("Tank", "Tanks and healers"), once each, in table order.
                var words = [String]()
                for e in entries { let w = e.role ?? e.section; if !words.contains(w) { words.append(w) } }
                let text = words.joined(separator: " · ")
                let mine = ownBuild(copy, area: "Max", member: m.id, ctx: ctx).map { Plan(build: $0, built: HubSquads.isFullStrength($0, screen: .max, ctx: ctx)) }
                cards.append(MaxCard(member: m, tier: best, roles: ordered, roleText: text, plan: mine, needsDynamax: copy.row.dynamax != true))
            }
            for (i, r) in rows.enumerated() where PogoRules.hitsAnyBoss(m.types, row: r.row, hub: ctx.hub) { by[i].append(m.name) }
        }
        let battles = rows.enumerated().filter { !by[$0.offset].isEmpty }.map { MaxBattle(row: BossRow(entry: $0.element), by: by[$0.offset]) }
        return (cards, battles)
    }

    // MARK: rule 15: Summary verdicts

    public enum Verdict: Equatable {
        case fullStrength, planned, spare, option, notPicked
        /// Rocket: the member shown beats this many grunt types.
        case beatsGrunts(Int)
        case needsDynamax
        /// PvP: the best league's worth tag.
        case pvp(LeaguePanel.Worth)
        case notUsed

        /// The row's word. The PvP words are the app's own worth words (Top, Good, Weak: `LeaguePanel.Worth.label`), which replaced the design's
        /// Strong / OK / Weak.
        public var text: String {
            switch self {
            case .fullStrength: return "FULL STRENGTH"
            case .planned: return "PLANNED"
            case .spare: return "SPARE"
            case .option: return "OPTION"
            case .notPicked: return "NOT PICKED"
            case .beatsGrunts(let n): return "BEATS \(n) GRUNT\(n == 1 ? "" : "S")"
            case .needsDynamax: return "NEEDS DYNAMAX"
            case .pvp(let w): return w.label.uppercased()
            case .notUsed: return "NOT USED"
            }
        }

        public enum Tone: Equatable { case positive, neutral, action }
        public var tone: Tone {
            switch self {
            case .fullStrength, .beatsGrunts: return .positive
            case .planned, .needsDynamax: return .action
            case .pvp(let w): return w == .strong ? .positive : .neutral
            default: return .neutral
            }
        }
    }

    /// The Summary row's mark: Upgrade available (the first build still to do, with its cost), Full strength (every build done) or nothing (no build).
    public enum Mark: Equatable {
        case none, fullStrength
        case upgrade(BoxAdvice.Build, cost: HubSquads.Cost, label: String)
    }

    static func mark(_ builds: [BoxAdvice.Build], built: (BoxAdvice.Build) -> Bool) -> Mark {
        // Only a build with work left is an upgrade; one that waits on the Dynamax mark alone is said by the NEEDS DYNAMAX verdict, with no mark.
        if let open = builds.first(where: { !built($0) && HubModel.needsSomething($0) }), let label = HubSquads.upgradeLabel(open) {
            return .upgrade(open, cost: HubSquads.cost(of: open), label: label)
        }
        return !builds.isEmpty && builds.allSatisfy(built) ? .fullStrength : .none
    }

    // MARK: rule 16: Summary lines

    /// One fact on one line. A PvP line carries its league in `lead` and its score apart, for the grades.
    public struct Line: Equatable {
        public var lead: String?
        public var text: String
        public var score: String?
        /// Type icons that follow the text (Rocket: the grunt types).
        public var icons: [String]
        public var plain: String { [lead, text, score].compactMap { $0 }.joined(separator: " ") }
    }

    private static func line(_ text: String, icons: [String] = []) -> Line { Line(lead: nil, text: text, score: nil, icons: icons) }

    /// A boss row's name for a line: each boss's bracketed form is dropped ("Giratina (Origin)" is "Giratina") unless another boss shares its base name, in
    /// the same row (the four Deoxys formes) or in any other row of `rows`.
    public static func shortName(_ row: HubData.RotationRow, among rows: [HubData.RotationRow]) -> String {
        guard !row.bosses.isEmpty else { return HubRaidsModel.name(row) }
        func base(_ n: String) -> String { n.range(of: #" \(.*\)$"#, options: .regularExpression).map { String(n[..<$0.lowerBound]) } ?? n }
        let others = rows.filter { $0 != row }.flatMap(\.bosses)
        var names = [String]()
        for (i, b) in row.bosses.enumerated() {
            let shared = row.bosses.enumerated().contains { $0.offset != i && base($0.element.name) == base(b.name) } || others.contains { base($0.name) == base(b.name) }
            let n = shared ? b.name : base(b.name)
            if !names.contains(n) { names.append(n) }
        }
        return names.joined(separator: " · ")
    }

    /// "Palkia now", "Giratina in 3 d".
    static func bossText(_ b: BossRow, among rows: [HubData.RotationRow]) -> String {
        let name = shortName(b.entry.row, among: rows)
        return b.isNow ? "\(name) now" : "\(name) \(b.when)"
    }

    /// "Beats Giovanni slot 2", "Beats Giovanni slots 1, 3 · Sierra slot 2": the leader slots a member's types beat.
    static func leaderText(_ c: RocketCard) -> String {
        var order = [String](), slots = [String: [Int]]()
        for s in c.leaderSlots { if slots[s.leader] == nil { order.append(s.leader) }; slots[s.leader, default: []].append(s.slot) }
        return "Beats " + order.map { l in "\(l) slot\(slots[l]!.count > 1 ? "s" : "") " + slots[l]!.map(String.init).joined(separator: ", ") }.joined(separator: " · ")
    }

    /// "bulk 48k", or why there is no figure: "level not read", "IVs not read" (each its own wording), "bulk not known" for a species without stats.
    public static func bulkWording(_ bulk: PogoRules.Bulk) -> String {
        switch bulk {
        case .known(let v): return "bulk " + bulkText(v)
        case .levelNotRead: return "level not read"
        case .ivsNotRead: return "IVs not read"
        case .unknownSpecies: return "bulk not known"
        }
    }

    /// "48k" for a bulk figure (the Pogo Hub's short numbers).
    public static func bulkText(_ bulk: Double) -> String { HubModel.dustShort(Int(bulk.rounded())) }

    // MARK: the Summary tab

    public struct SummaryRow: Equatable {
        public var activity: Activity
        public var verdict: Verdict
        public var lines: [Line]
        public var mark: Mark
    }

    private static func planVerdict(_ builds: [BoxAdvice.Build], built: (BoxAdvice.Build) -> Bool) -> Verdict? {
        builds.isEmpty ? nil : (builds.allSatisfy(built) ? .fullStrength : .planned)
    }

    private static func capital(_ t: String) -> String { t.prefix(1).uppercased() + t.dropFirst() }

    /// Rules 15 and 16: one row per activity, PvP leagues first.
    public static func summary(copy: BoxEntry, ctx: HubContext, pogoAssist: Bool = false) -> [SummaryRow] {
        let mine = ctx.advice.builds.filter { $0.entryId == copy.id }
        func area(_ a: String) -> [BoxAdvice.Build] { mine.filter { $0.areas.contains(a) } }
        func built(_ screen: SquadScreen) -> (BoxAdvice.Build) -> Bool { { HubSquads.isFullStrength($0, screen: screen, ctx: ctx) } }
        var rows: [SummaryRow] = []

        // PvP
        var leagueLines: [Line] = [], worths: [(w: LeaguePanel.Worth, score: Double)] = []
        for key in LeaguePanel.keys {
            guard let r = ctx.advice.leagues[copy.id]?[key] else { continue }
            let c = LeaguePanel.card(r, shown: LeaguePanel.shownIndex(r, pogoAssist: pogoAssist), key: key, level: copy.row.level)
            let lead = BoxAdvice.areaLabel[key] ?? key.uppercased()
            if c.status == .noViable { leagueLines.append(Line(lead: lead, text: "over the cap", score: nil, icons: [])) }
            else { leagueLines.append(Line(lead: lead, text: c.title, score: c.scoreText, icons: [])) }
            if let w = c.worth { worths.append((w, c.option.strength?.score ?? 0)) }
        }
        let pvpBuilds = HubModel.builds(mine, for: .pvp)
        let bestWorth = worths.enumerated().sorted { l, r in
            let rank: (LeaguePanel.Worth) -> Int = { $0 == .strong ? 0 : $0 == .ok ? 1 : 2 }
            if rank(l.element.w) != rank(r.element.w) { return rank(l.element.w) < rank(r.element.w) }
            if l.element.score != r.element.score { return l.element.score > r.element.score }
            return l.offset < r.offset
        }.first?.element.w
        rows.append(SummaryRow(activity: .pvp, verdict: planVerdict(pvpBuilds, built: built(.pvp)) ?? bestWorth.map(Verdict.pvp) ?? .notUsed, lines: leagueLines,
                               mark: mark(pvpBuilds, built: built(.pvp))))

        // Raids
        let raid = raidCards(copy: copy, ctx: ctx)
        var raidVerdict: Verdict = .notUsed, raidLines = [line("Not in our raid tables")]
        if let top = raid.first {
            if case .best = top.plan { raidVerdict = .spare } else { raidVerdict = .option }
            raidLines = [line("\(top.member.name), \(top.tier) \(capital(top.type)) attacker")]
            if let first = top.counters.first {
                raidLines.append(line("Counters " + bossText(first, among: top.counters.map(\.entry.row)) + (top.counterCount > 1 ? " +\(top.counterCount - 1) more" : "")))
            } else { raidLines.append(line("No raid on or coming needs it")) }
        }
        rows.append(SummaryRow(activity: .raids, verdict: planVerdict(area("Raids"), built: built(.raids)) ?? raidVerdict, lines: raidLines, mark: mark(area("Raids"), built: built(.raids))))

        // Gym
        let top = topDefender(ctx: ctx)
        let gym = gymCards(copy: copy, ctx: ctx, top: top)
        var gymLines = [line("Not in our gym table")]
        if let g = gym.first {
            gymLines = [line("As \(g.member.name), " + bulkWording(g.bulk))]
            if g.isTop { gymLines.append(line("Your top defender")) }
            else if let share = g.share, let top { gymLines.append(line("\(share)% of your top defender, \(top.name)")) }
        }
        rows.append(SummaryRow(activity: .gym, verdict: planVerdict(area("Gym"), built: built(.gym)) ?? (gym.isEmpty ? .notUsed : .notPicked), lines: gymLines,
                               mark: mark(area("Gym"), built: built(.gym))))

        // Rocket: the member shown has a Rocket build, else beats the most grunt types, ties to the later evolution.
        // A planned member is shown even when it beats no grunt type (its line then says what it does beat); else the member beating the most grunt types;
        // only when none beats a grunt type, a member that beats leader options.
        let all = members(of: copy, ctx: ctx).enumerated().map { (index: $0.offset, card: rocketCard($0.element, copy: copy, ctx: ctx)) }
        func best(_ pool: [(index: Int, card: RocketCard)], by key: (RocketCard) -> Int) -> RocketCard? {
            pool.sorted { l, r in key(l.card) != key(r.card) ? key(l.card) > key(r.card) : l.index > r.index }.first?.card
        }
        let planned = best(all.filter { $0.card.plan != nil }) { $0.gruntTypes.count }
        let gruntMember = best(all.filter { !$0.card.gruntTypes.isEmpty }) { $0.gruntTypes.count }
        let leaderMember = best(all.filter { !$0.card.leaderSlots.isEmpty }) { $0.leaderSlots.reduce(0) { $0 + $1.beats.count } }
        let shown = planned ?? gruntMember ?? leaderMember
        var rocketLines = [line("No type advantage on any grunt")]
        if let c = shown {
            if !c.gruntTypes.isEmpty { rocketLines = [line("As \(c.member.name)", icons: c.gruntTypes)] }
            else if !c.leaderSlots.isEmpty { rocketLines = [line(leaderText(c))] }
            else { rocketLines = [line("As \(c.member.name), no type advantage")] }
        }
        let rocketVerdict = planVerdict(area("Rocket"), built: built(.rocket)) ?? gruntMember.map { Verdict.beatsGrunts($0.gruntTypes.count) } ?? .notUsed
        rows.append(SummaryRow(activity: .rocket, verdict: rocketVerdict, lines: rocketLines, mark: mark(area("Rocket"), built: built(.rocket))))

        // Max
        let m = maxCards(copy: copy, ctx: ctx)
        var maxLines = [line("Not in our Max table")]
        var maxVerdict: Verdict = .notUsed
        if let t = m.cards.first {
            maxVerdict = copy.row.dynamax != true ? .needsDynamax : (planVerdict(area("Max"), built: built(.max)) ?? .option)
            maxLines = [line("\(t.member.name), \(t.tier) tier"), line(t.roleText)]
            if let b = m.battles.first(where: { $0.by.contains(t.member.name) }) { maxLines.append(line("Hits " + bossText(b.row, among: m.battles.map(\.row.entry.row)))) }
        } else if let b = m.battles.first {
            maxLines.append(line("Its types hit " + bossText(b.row, among: m.battles.map(\.row.entry.row))))
        }
        rows.append(SummaryRow(activity: .max, verdict: maxVerdict, lines: maxLines, mark: mark(area("Max"), built: built(.max))))
        return rows
    }
}
