import Foundation

/// What the My Pokémon tab says that is not a layout choice (design pass 3, `CONCEPTS.md` rules 2 to 5 and 9): the number grades, the species build mark (its cost counts one build per copy, the copy's top one with work left),
/// and the two groups a species shows when it opens in place. Pure functions over what the advisor already worked out, so `swift test` pins them and pass 2's
/// screens can use the same grades and marks.
public enum MyPokemon {
    // MARK: number grades (rule 9, and rule 3 for IV %)

    /// How a number reads: bold green on a tint (top), bold green (good), or plain.
    public enum Grade: Equatable { case plain, good, top }

    /// A PvPoke score: 92 and over is top, 90 and over is good. The same cut-offs as the S and A tiers (`LeaguePanel.sScore`, `aScore`).
    public static func scoreGrade(_ score: Double?) -> Grade {
        guard let score else { return .plain }
        return score >= LeaguePanel.sScore ? .top : score >= LeaguePanel.aScore ? .good : .plain
    }

    /// An IV rank within the league's 4,096 spreads: 1 to 100 is top, 101 to 500 good. A rank below 1 is not a rank.
    public static func rankGrade(_ rank: Int?) -> Grade {
        guard let rank, rank >= 1 else { return .plain }
        return rank <= 100 ? .top : rank <= 500 ? .good : .plain
    }

    /// An IV % on a row (rule 3, a proposal): top at 100% (45 of 45), good at 42 of 45 or more (93%). Graded on the IV sum, not the rounded percentage,
    /// so the line is the same one however the percentage is rounded for display.
    public static func ivGrade(sum: Int?) -> Grade {
        guard let sum else { return .plain }
        return sum >= 45 ? .top : sum >= 42 ? .good : .plain
    }

    // MARK: the species build mark (rule 2)

    /// The currency a cost is in.
    public enum Currency: Equatable { case dust, candy }

    /// A cost as the value the screen draws beside the currency's icon: "12k" and `.dust`, "25" and `.candy`.
    public struct Cost: Equatable {
        public var value: String
        public var currency: Currency
        public init(value: String, currency: Currency) { self.value = value; self.currency = currency }
        /// The same words `HubModel.costShort` gives a build: "12k dust", "25 candy".
        public var words: String { "\(value) \(currency == .dust ? "dust" : "candy")" }
    }

    public enum BuildMark: Equatable {
        /// Some copy has a build with work left. `cost` is the dust (else candy) of each copy's top build with work left, one per copy, not of every build; `builds` counts every build with work left. `cost` is nil when that work costs no dust and no candy (a second move, an Elite TM).
        case upgrade(cost: Cost?, builds: Int)
        case fullStrength
        case none
    }

    /// The mark on a species row, from the builds of the species' copies (the caller keeps only the builds whose `entryId` is one of them): the upgrade
    /// arrow when any build has work left; Full strength when there are builds and all are built (`HubTeams.isBuilt`); nothing without a build. Its cost
    /// counts ONE build per copy, that copy's top build with work left (tier S, A, B, then the higher score, then the advisor's order), so a copy with
    /// a raid build and a PvP build adds one of them, not both (Greg, 31 Oct 2026). `builds` is still the number of builds with work left.
    public static func speciesMark(builds: [BoxAdvice.Build]) -> BuildMark {
        guard !builds.isEmpty else { return .none }
        let open = builds.filter { !HubTeams.isBuilt($0) }
        guard !open.isEmpty else { return .fullStrength }
        var top = [String: BoxAdvice.Build](), order = [String]()
        for b in open {
            if let cur = top[b.entryId] {
                let better = HubTeams.tierRank(b) != HubTeams.tierRank(cur) ? HubTeams.tierRank(b) < HubTeams.tierRank(cur) : b.score > cur.score
                if better { top[b.entryId] = b }
            } else { top[b.entryId] = b; order.append(b.entryId) }
        }
        return .upgrade(cost: cost(of: order.compactMap { top[$0] }), builds: open.count)
    }

    /// The mark on one copy: the same rule over its own builds, all of which count (the copy's page lists each build's own work).
    public static func copyMark(builds: [BoxAdvice.Build]) -> BuildMark {
        guard !builds.isEmpty else { return .none }
        let open = builds.filter { !HubTeams.isBuilt($0) }
        guard !open.isEmpty else { return .fullStrength }
        return .upgrade(cost: cost(of: open), builds: open.count)
    }

    /// The dust of the builds in total, else their candy in total (formatted as `HubModel.costShort`); nil when neither is due.
    static func cost(of builds: [BoxAdvice.Build]) -> Cost? {
        let dust = builds.reduce(0) { $0 + $1.dust }
        if dust > 0 { return Cost(value: HubModel.dustShort(dust), currency: .dust) }
        let candy = builds.reduce(0) { $0 + $1.candy }
        return candy > 0 ? Cost(value: String(candy), currency: .candy) : nil
    }

    // MARK: TOP PVP (rule 4)

    /// The leagues that count for a copy's PvP standing: Great and Ultra. Master League is left out, where the IVs decide and TOP IVS shows them (Greg, 25 Oct 2026).
    public static let pvpLeagues = ["gl", "ul"]

    /// One copy's PvP standing: its best Great or Ultra League card that fits under the cap.
    public struct PvPStanding: Equatable {
        public var league: String
        /// The card's pick (the headline member), as the league card names it.
        public var pick: String
        /// The pick's PvPoke score.
        public var score: Double
        /// This copy's IV rank as the pick (1 is the best of the 4,096 spreads).
        public var ivRank: Int
        public init(league: String, pick: String, score: Double, ivRank: Int) { self.league = league; self.pick = pick; self.score = score; self.ivRank = ivRank }
        public var scoreGrade: Grade { MyPokemon.scoreGrade(score) }
        public var rankGrade: Grade { MyPokemon.rankGrade(ivRank) }
    }

    /// The copy's standing, or nil when it has no Great or Ultra League card that fits under the cap with a ranked pick and a read IV rank. A card is the one the
    /// league panel shows (`LeaguePanel.headlineIndex`): the shown pick when it fits, else the best-ranked member that does. Of the leagues, the higher score wins;
    /// a tie goes to the better IV rank, then to Great League.
    public static func pvpStanding(ratings: [String: BoxAdvice.LeagueRating], pogoAssist: Bool) -> PvPStanding? {
        var best: PvPStanding?
        for key in pvpLeagues {
            guard let r = ratings[key], let at = LeaguePanel.headlineIndex(r, shown: LeaguePanel.shownIndex(r, pogoAssist: pogoAssist)) else { continue }
            let o = r.options[at]
            guard !o.overCap, let score = o.strength?.score, let rank = o.iv?.rank else { continue }
            let cand = PvPStanding(league: key, pick: o.name, score: score, ivRank: rank)
            if let cur = best, !(cand.score > cur.score || (cand.score == cur.score && cand.ivRank < cur.ivRank)) { continue }
            best = cand
        }
        return best
    }

    public struct TopPvPCopy: Equatable {
        public var copyId: String
        public var standing: PvPStanding
    }

    /// The best copies of a species by PvP standing: the higher score first, ties by the lower IV rank, then by the order given (the species list's order, best
    /// IVs first). `copies` are the species title's copies with their league ratings.
    public static func topPvP(copies: [(id: String, ratings: [String: BoxAdvice.LeagueRating])], pogoAssist: Bool, limit: Int = 2) -> [TopPvPCopy] {
        let ranked = copies.enumerated().compactMap { n, c in pvpStanding(ratings: c.ratings, pogoAssist: pogoAssist).map { (n, TopPvPCopy(copyId: c.id, standing: $0)) } }
        return ranked.sorted { l, r in
            let (a, b) = (l.1.standing, r.1.standing)
            if a.score != b.score { return a.score > b.score }
            if a.ivRank != b.ivRank { return a.ivRank < b.ivRank }
            return l.0 < r.0
        }.prefix(limit).map(\.1)
    }

    // MARK: TOP IVS (rule 5)

    /// A copy as the species list orders it, for the IV groups.
    public struct ListedCopy: Equatable {
        public var id: String
        /// The sum of the three IVs; nil when they are not read.
        public var ivSum: Int?
        public init(id: String, ivSum: Int?) { self.id = id; self.ivSum = ivSum }
    }

    /// The next copies in the species list's order (best IVs first) that are not already in TOP PVP. A copy whose IVs are not read is never "top by IVs", so it is skipped.
    public static func topIVs(listed: [ListedCopy], excluding shown: Set<String>, limit: Int = 2) -> [String] {
        Array(listed.lazy.filter { $0.ivSum != nil && !shown.contains($0.id) }.prefix(limit).map(\.id))
    }

    /// The keep or transfer tag a copy carries, as the Advice panel words it: only for a copy that is one of several. A TOP IVS row keeps it whether or not the copy
    /// has a build (D1: "a copy with a build still shows its upgrade mark"). "Keep · best IVs of the 65", "Keep · marked as caught as a Dynamax", "Transfer · one of 65".
    public struct KeepTag: Equatable {
        public var keep: Bool
        public var detail: String
        public var text: String { (keep ? "Keep" : "Transfer") + " · " + detail }
    }

    public static func keepTag(_ a: BoxAdvice.ForEntry) -> KeepTag? {
        guard let d = a.duplicateOf else { return nil }
        guard a.keep else { return KeepTag(keep: false, detail: "one of \(d.count)") }
        var reason = BoxAdvice.keepReason(d, copy: a.keepIndex ?? 0)
        // "it has your best IVs of the 65" reads "best IVs of 65"; "it is marked as caught as a Dynamax" reads "marked as caught as a Dynamax".
        for prefix in ["it has one of your ", "it has your ", "it is one of your ", "it is your ", "it is "] where reason.hasPrefix(prefix) {
            reason = String(reason.dropFirst(prefix.count)); break
        }
        return KeepTag(keep: true, detail: reason.replacingOccurrences(of: "of the ", with: "of "))
    }
}
