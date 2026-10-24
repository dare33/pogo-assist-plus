import Foundation

/// The suggested teams of the Gym, Team Rocket and PvP screens, worked out from the advice report, the game master's types and the Hub's type
/// chart. The teams are read-only suggestions (slot pickers and saved assignments are not built yet). Pure, so the fixture pins them (`HubTeamsModelTests`).
public enum HubTeams {
    // MARK: shared

    /// A build is built when nothing is left to do but the Dynamax requirement, which is set on the Pokémon's page. A report read without
    /// `steps` counts as built here (the Hub's "needs something" rule in `HubModel` reads it the other way, for a different question).
    public static func isBuilt(_ b: BoxAdvice.Build) -> Bool {
        guard let steps = b.steps else { return true }
        return steps.allSatisfy { $0.kind == "needsDynamaxCopy" }
    }

    /// 0 for S, 1 for A, 2 for B, then the rest.
    static func tierRank(_ b: BoxAdvice.Build) -> Int { ["S": 0, "A": 1, "B": 2][b.tier] ?? 3 }

    /// The build target's types (empty when the game master does not know the species).
    public static func types(of b: BoxAdvice.Build, gm: GameMaster) -> [String] { gm.byId[b.targetId]?.types ?? [] }

    /// What a build still needs, in a few words and no arrow: "evolve Pupitar", "power up Lapras", "mega evolve Lucario".
    public static func todo(_ b: BoxAdvice.Build) -> String {
        let h = HubModel.headline(for: b)
        let short = h.components(separatedBy: " → ").first ?? h
        return short.prefix(1).lowercased() + short.dropFirst()
    }

    /// Builds in the order the screens prefer them: tier S, A, B, then the higher score; the advisor's order breaks the rest.
    private static func byTierThenScore(_ builds: [BoxAdvice.Build]) -> [BoxAdvice.Build] {
        builds.enumerated().sorted { l, r in
            let (a, b) = (l.element, r.element)
            if tierRank(a) != tierRank(b) { return tierRank(a) < tierRank(b) }
            if a.score != b.score { return a.score > b.score }
            return l.offset < r.offset
        }.map(\.element)
    }

    // MARK: Gym

    /// The six best built defenders: builds with the Gym area that are built, S before A before B, then by score, one per target species.
    public static func topDefenders(builds: [BoxAdvice.Build]) -> [BoxAdvice.Build] {
        var seen = Set<String>(), out = [BoxAdvice.Build]()
        for b in byTierThenScore(builds.filter { $0.areas.contains("Gym") && isBuilt($0) }) where seen.insert(b.targetId).inserted {
            out.append(b)
            if out.count == 6 { break }
        }
        return out
    }

    /// Every build with the Gym area, in the advisor's order (the TOP AVAILABLE list).
    public static func gymAvailable(builds: [BoxAdvice.Build]) -> [BoxAdvice.Build] { builds.filter { $0.areas.contains("Gym") } }

    /// What each empty slot would take: the Gym builds that are not built yet, in the advisor's order, as "Power up Lapras". The first empty
    /// slot names the first, the second the next, so two empty slots never name the same build; nil when there are no more.
    public static func gymEmptyHints(builds: [BoxAdvice.Build], slots: Int) -> [String?] {
        let open = gymAvailable(builds: builds).filter { !isBuilt($0) }
        return (0..<max(0, slots)).map { open.indices.contains($0) ? HubModel.headline(for: open[$0]) : nil }
    }

    // MARK: Team Rocket

    /// The answer to one slot or one grunt.
    public enum Counter: Equatable {
        /// The best build that is done.
        case built(BoxAdvice.Build)
        /// The best build that is not done yet: `todo(_:)` says what is left.
        case toBuild(BoxAdvice.Build)
        /// Nothing in the box can become a counter; the top-tier Pokémon that would be one.
        case gap(BoxAdvice.Gap)
        case none
        /// A typeless grunt (Mixed team, Decoy): any strong attacker will do.
        case anyAttacker

        public var build: BoxAdvice.Build? {
            switch self { case .built(let b), .toBuild(let b): return b; default: return nil }
        }
        public var isBuilt: Bool { if case .built = self { return true } else { return false } }
        /// The name a tile shows, "—" when there is none. An unbuilt counter shows its target's name.
        public var name: String { build?.targetName ?? (self == .anyAttacker ? "Any attacker" : "—") }
        /// "gap: evolve Pupitar" for a build still to do, "gap: Rhyperior" for a Pokémon the box cannot make; nil otherwise.
        public var gapText: String? {
            switch self {
            case .toBuild(let b): return "gap: \(HubTeams.todo(b))"
            case .gap(let g): return "gap: \(g.name)"
            default: return nil
            }
        }
    }

    private static func isRocketCounterArea(_ b: BoxAdvice.Build) -> Bool { b.areas.contains("Rocket") || b.areas.contains("Raids") }

    /// The Rocket-area build first, then tier, then score, then the advisor's order.
    private static func rocketOrder(_ builds: [BoxAdvice.Build]) -> [BoxAdvice.Build] {
        builds.enumerated().sorted { l, r in
            let (a, b) = (l.element, r.element)
            let (ra, rb) = (a.areas.contains("Rocket"), b.areas.contains("Rocket"))
            if ra != rb { return ra }
            if tierRank(a) != tierRank(b) { return tierRank(a) < tierRank(b) }
            if a.score != b.score { return a.score > b.score }
            return l.offset < r.offset
        }.map(\.element)
    }

    /// How many of the slot's options one of the build's types hits for more than normal damage.
    static func hits(_ b: BoxAdvice.Build, options: [HubData.Boss], gm: GameMaster, hub: HubData) -> Int {
        let mine = types(of: b, gm: gm)
        return options.filter { o in mine.contains { hub.effectiveness($0, against: o.types) > 1.0001 } }.count
    }

    /// The best build for a slot: among the builds that have the Rocket or Raids area, the one whose target has a type super-effective
    /// against the most of the slot's options (ties: Rocket area, tier, score). A built one wins; failing that the best build still to do.
    /// `excluding` are target species another slot already uses; one is passed over only when an alternative exists.
    public static func counter(for options: [HubData.Boss], builds: [BoxAdvice.Build], gm: GameMaster, hub: HubData, excluding used: Set<String> = []) -> Counter {
        let scored = builds.filter(isRocketCounterArea).map { ($0, hits($0, options: options, gm: gm, hub: hub)) }.filter { $0.1 > 0 }
        // Most options hit first; rocketOrder is stable, so sorting by hits afterwards would lose it: group instead.
        let ordered = Dictionary(grouping: scored, by: { $0.1 }).sorted { $0.key > $1.key }.flatMap { rocketOrder($0.value.map(\.0)) }
        func first(built: Bool, fresh: Bool) -> BoxAdvice.Build? { ordered.first { isBuilt($0) == built && used.contains($0.targetId) != fresh } }
        if let b = first(built: true, fresh: true) { return .built(b) }
        if let b = first(built: false, fresh: true) { return .toBuild(b) }
        if let b = first(built: true, fresh: false) { return .built(b) }
        if let b = first(built: false, fresh: false) { return .toBuild(b) }
        return .none
    }

    /// One counter per slot (three). A species used in one slot is not used in another when an alternative exists.
    public static func leaderTeam(leader: HubData.Leader, builds: [BoxAdvice.Build], gm: GameMaster, hub: HubData) -> [Counter] {
        var used = Set<String>()
        return leader.slots.map { options in
            let c = counter(for: options, builds: builds, gm: gm, hub: hub, excluding: used)
            if let b = c.build { used.insert(b.targetId) }
            return c
        }
    }

    /// The answer to a grunt of type `type` (empty for a typeless grunt). Built counters first: a build with the Rocket or Raids area whose
    /// target type is super-effective against `type` (Rocket area, tier, score). Else the best one still to do. Else the first S or A gap
    /// (Rocket or Raids area) whose species has such a type. Else none.
    public static func gruntCounter(type: String, builds: [BoxAdvice.Build], gaps: [BoxAdvice.Gap] = [], gm: GameMaster, hub: HubData) -> Counter {
        guard !type.isEmpty else { return .anyAttacker }
        func beats(_ types: [String]) -> Bool { types.contains { hub.effectiveness($0, against: [type]) > 1.0001 } }
        let fit = rocketOrder(builds.filter { isRocketCounterArea($0) && beats(types(of: $0, gm: gm)) })
        if let b = fit.first(where: isBuilt) { return .built(b) }
        if let b = fit.first { return .toBuild(b) }
        // The Rocket area's gaps first, then the Raids area's; S before A within each.
        let gap = gaps.enumerated().filter { _, g in
            guard (g.tier == "S" || g.tier == "A"), g.area == "Rocket" || g.area == "Raids" else { return false }
            // The tier tables write a Shadow as "Shadow Ninetales"; a Mega's types differ from its species', so it is left out.
            let plain = g.name.hasPrefix("Shadow ") ? String(g.name.dropFirst(7)) : g.name
            guard let id = gm.speciesId(forName: plain) else { return false }
            return beats(gm.byId[id]?.types ?? [])
        }.sorted { l, r in
            let (a, b) = (l.element, r.element)
            if (a.area == "Rocket") != (b.area == "Rocket") { return a.area == "Rocket" }
            if a.tier != b.tier { return a.tier == "S" }
            return l.offset < r.offset
        }.first?.element
        return gap.map(Counter.gap) ?? .none
    }

    // MARK: PvP

    /// The lowest PvPoke score a candidate may have: the B band.
    public static let bFloor = 88.0, aFloor = 90.0, sFloor = 92.0

    /// S at 92 or more, A at 90, B at 88; "" below.
    public static func tier(score: Double) -> String { score >= sFloor ? "S" : score >= aFloor ? "A" : score >= bFloor ? "B" : "" }

    /// One copy's shown option in a league.
    public struct Candidate: Equatable, Identifiable {
        public var id: String { entryId }
        public var entryId: String
        public var option: BoxAdvice.LeagueRating.Option
        /// The copy's own species name, which is where the option comes from when it is an evolution.
        public var copyTitle: String
        public var score: Double
        public var ivRank: Int?
        public var ivPct: Double?
        public var speciesId: String { option.speciesId }
        public var name: String { option.name }
        public var tier: String { HubTeams.tier(score: score) }
        /// "From Eevee" when the option is not the copy itself.
        public var fromText: String? { option.isSelf || copyTitle.isEmpty ? nil : "From \(copyTitle)" }
        /// "#12 · 98.7%" (IV rank and IV percent); "IVs not read" when the copy's IVs are not.
        public var subText: String {
            guard let r = ivRank, let p = ivPct else { return "IVs not read" }
            return "#\(LeaguePanel.grouped(r)) · \(LeaguePanel.oneDecimal(p))%"
        }
    }

    /// The candidates for a league (`gl`, `ul` or `ml`): per copy in the box its shown option (the Pogo Assist pick when `pogoAssist`), when it
    /// is not past the cap and PvPoke ranks it at the B floor or better. Best score first, then the better IV rank; one entry per species
    /// (the best copy).
    public static func candidates(league: String, advice: BoxAdvice, pogoAssist: Bool = false) -> [Candidate] {
        var all = [Candidate]()
        for (id, ratings) in advice.leagues {
            guard let r = ratings[league] else { continue }
            let o = r.options[LeaguePanel.shownIndex(r, pogoAssist: pogoAssist)]
            guard !o.overCap, let s = o.strength, s.score >= bFloor else { continue }
            all.append(Candidate(entryId: id, option: o, copyTitle: r.options.first(where: \.isSelf)?.name ?? "", score: s.score, ivRank: o.iv?.rank, ivPct: o.iv?.pct))
        }
        all.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if ($0.ivRank ?? Int.max) != ($1.ivRank ?? Int.max) { return ($0.ivRank ?? Int.max) < ($1.ivRank ?? Int.max) }
            return $0.entryId < $1.entryId
        }
        var seen = Set<String>()
        return all.filter { seen.insert($0.speciesId).inserted }
    }

    private static func types(of c: Candidate, gm: GameMaster) -> [String] { gm.byId[c.speciesId]?.types ?? [] }

    /// The types a team hits for more than normal damage: a type is covered when one member's type is super-effective against it.
    static func covered(_ team: [Candidate], gm: GameMaster, hub: HubData) -> Set<String> {
        let mine = Set(team.flatMap { types(of: $0, gm: gm) })
        return Set(HubData.typeOrder.filter { defender in mine.contains { hub.effectiveness($0, against: [defender]) > 1.0001 } })
    }

    /// The top candidate, then each time the candidate that covers the most types not yet covered (ties: the better score, as the list is sorted).
    public static func suggestedTeam(candidates: [Candidate], gm: GameMaster, hub: HubData) -> [Candidate] {
        guard let lead = candidates.first else { return [] }
        var team = [lead]
        while team.count < 3 {
            let have = covered(team, gm: gm, hub: hub)
            let rest = candidates.filter { c in !team.contains { $0.speciesId == c.speciesId } }
            guard let next = rest.enumerated().max(by: { l, r in
                let (a, b) = (covered(team + [l.element], gm: gm, hub: hub).subtracting(have).count, covered(team + [r.element], gm: gm, hub: hub).subtracting(have).count)
                return a != b ? a < b : l.offset > r.offset
            })?.element else { break }
            team.append(next)
        }
        return team
    }

    /// How many of the 18 types the team covers.
    public static func coverage(team: [Candidate], gm: GameMaster, hub: HubData) -> Int { covered(team, gm: gm, hub: hub).count }

    private static func list(_ words: [String]) -> String {
        let w = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return w.count < 2 ? (w.first ?? "") : w.dropLast().joined(separator: ", ") + " and " + w[w.count - 1]
    }

    /// "Weak to Fairy and Rock." (the types that hit at least two members for more than normal damage), or "No shared weakness.". When a
    /// candidate outside the team would raise the coverage by taking the place of a member other than the lead, a second sentence names the
    /// first such swap: "Swapping X for Y covers Z.", where Z is what the swap newly covers.
    public static func weaknessNote(team: [Candidate], candidates: [Candidate] = [], gm: GameMaster, hub: HubData) -> String {
        let shared = HubData.typeOrder.filter { attacker in team.filter { hub.effectiveness(attacker, against: types(of: $0, gm: gm)) > 1.0001 }.count >= 2 }
        var note = shared.isEmpty ? "No shared weakness." : "Weak to \(list(shared))."
        if let swap = swapSuggestion(team: team, candidates: candidates, gm: gm, hub: hub) { note += " " + swap }
        return note
    }

    private static func swapSuggestion(team: [Candidate], candidates: [Candidate], gm: GameMaster, hub: HubData) -> String? {
        guard team.count > 1 else { return nil }
        let have = covered(team, gm: gm, hub: hub)
        for c in candidates where !team.contains(where: { $0.speciesId == c.speciesId }) {
            // The member whose replacement covers the most; the lowest-scored one on a tie. The lead stays.
            var best: (out: Candidate, gained: [String], total: Int)?
            for out in team.dropFirst().reversed() {
                let after = covered(team.filter { $0.speciesId != out.speciesId } + [c], gm: gm, hub: hub)
                guard after.count > have.count else { continue }
                let gained = HubData.typeOrder.filter { after.contains($0) && !have.contains($0) }
                if best == nil || after.count > best!.total { best = (out, gained, after.count) }
            }
            if let best { return "Swapping \(best.out.name) for \(c.name) covers \(list(best.gained))." }
        }
        return nil
    }

    /// The candidates not in the team, in their order.
    public static func others(candidates: [Candidate], team: [Candidate]) -> [Candidate] {
        candidates.filter { c in !team.contains { $0.entryId == c.entryId } }
    }
}
