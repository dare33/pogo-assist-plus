import Foundation

/// What the Pokémon list and the species list read for every copy, worked out once per box version and once per ranking (never per row render or
/// per keystroke): the copy's tag in each league under both rankings and in each activity, and per species the tile of each league (the species'
/// best copy and the member it is rated as). The tag rules are the ones the Pokémon page uses: a league's is `LeaguePanel.slot` (the pick card's
/// headline member, tier and roll), an activity's is the advice's `fit` tag. Both rankings are built together so that switching is instant.
public struct BoxInsight {
    /// The seven things a list chip can filter by, in the order the chips run: the three PvP leagues, then Raids, Gym, Rocket, Max (Greg, 25 Oct 2026). Nothing keys on this order: the cases are String-backed, and the insight indexes by `areas` and `LeaguePanel.keys`.
    public enum Activity: String, CaseIterable, Hashable {
        case gl, ul, ml, raids, gym, rocket, max

        public var title: String {
            switch self {
            case .raids: return "Raids"
            case .gym: return "Gym"
            case .rocket: return "Rocket"
            case .gl: return "Great"
            case .ul: return "Ultra"
            case .ml: return "Master"
            case .max: return "Max"
            }
        }
        /// `gl`, `ul` or `ml` for a league chip.
        public var league: String? { [Activity.gl, .ul, .ml].contains(self) ? rawValue : nil }
        /// The area key of `BoxAdvice.fit` for an activity chip.
        public var area: String? { league == nil ? rawValue : nil }
    }

    /// The four non-league areas, in the order the Activities row shows them.
    public static let areas = ["raids", "gym", "rocket", "max"]

    public struct Copy: Equatable {
        /// Six slots: Classic's Great, Ultra, Master, then Pogo Assist's; nil where the copy has no rating for the league.
        public var slots: [LeaguePanel.Slot?]
        /// The fit tag in `areas` order; nil where the advice has none.
        public var fit: [LeaguePanel.Worth?]
        /// The areas the advice calls this copy the best of its species for, each with the table entry it is rated as (a Shadow copy's name says so; nil for Max).
        public var best: [BestTag] = []
        /// The sentence a tap on the copy's tag opens, kept here with the tags so that a list rebuilt from this insight never needs the advice: in `areas` order,
        /// and in the order of `slots`.
        public var areaLines: [String?] = []
        public var leagueLines: [String?] = []
        /// What the species page's ranking reads (the engine's own best-of key, src/advise.js): per area in `areas` order the table tier as 3 for S, 2 for A, 1 for B, 0 for
        /// none or Weak; the engine's IV % for the area (0 where unknown); the table entry the copy is rated as (Shadow-suffixed); and the copy's CP.
        public var fitTier: [Int] = []
        public var fitIVPct: [Double] = []
        public var asNames: [String?] = []
        public var cp: Int = 0

        public struct BestTag: Equatable {
            public var area: String
            public var asName: String?
            public init(area: String, asName: String?) { self.area = area; self.asName = asName }
        }

        /// The line a tag for the chip opens: the activity's `fit` line, or the league card's tier-and-roll sentence; nil where the copy has no tag.
        public func line(_ a: Activity, pogoAssist: Bool) -> String? {
            if let league = a.league, let l = LeaguePanel.keys.firstIndex(of: league) {
                let i = (pogoAssist ? 3 : 0) + l
                return leagueLines.indices.contains(i) ? leagueLines[i] : nil
            }
            guard let i = a.area.flatMap({ BoxInsight.areas.firstIndex(of: $0) }) else { return nil }
            return areaLines.indices.contains(i) ? areaLines[i] : nil
        }

        public func slot(_ league: String, pogoAssist: Bool) -> LeaguePanel.Slot? {
            guard let l = LeaguePanel.keys.firstIndex(of: league) else { return nil }
            return slots[(pogoAssist ? 3 : 0) + l]
        }
        /// The tag for a chip: nil when the copy has none for it (a league it has no rating for, no advice).
        public func worth(_ a: Activity, pogoAssist: Bool) -> LeaguePanel.Worth? {
            if let league = a.league { return slot(league, pogoAssist: pogoAssist)?.worth }
            return a.area.flatMap { BoxInsight.areas.firstIndex(of: $0) }.flatMap { fit[$0] }
        }
        /// Strong or OK: what a chip keeps.
        public func suits(_ a: Activity, pogoAssist: Bool) -> Bool {
            let w = worth(a, pogoAssist: pogoAssist)
            return w == .strong || w == .ok
        }
    }

    /// One species' tile for one league under one ranking: its best copy's member and IV %.
    public struct Tile: Equatable {
        public enum Status: Equatable { case fits, ivsNotRead, overCap, noData }
        public var status: Status
        public var member: String
        public var pct: Double?
        /// The copy the tile is read from (the species' best for the league); nil unless `.fits`.
        public var copyId: String?
    }

    public private(set) var copies: [String: Copy] = [:]
    /// By species title (the row title the list groups by), six tiles in the order of `Copy.slots`.
    public private(set) var species: [String: [Tile]] = [:]
    /// By species title, the copy ids that rank for each use, best first, at most `topCount`: 14 lists, the seven activities in `Activity.allCases` order under Classic, then under
    /// Pogo Assist (the area lists are the same under both). Built once with the rest, so the species page never ranks per render.
    private var tops: [String: [[String]]] = [:]
    /// How many copies of a species take a place for one use.
    public static let topCount = 3

    public init() {}

    public func tile(title: String, league: String, pogoAssist: Bool) -> Tile? {
        guard let l = LeaguePanel.keys.firstIndex(of: league), let t = species[title] else { return nil }
        return t[(pogoAssist ? 3 : 0) + l]
    }

    /// The tag of a copy for a chip, nil when unknown.
    public func worth(of id: String, _ a: Activity, pogoAssist: Bool) -> LeaguePanel.Worth? { copies[id]?.worth(a, pogoAssist: pogoAssist) }

    /// What a chip's merged tag adds once the copy is also its species' best for the same area: "best as Tyranitar (Shadow)" for an activity (the engine's own `as`
    /// text, Shadow-suffixed), "best: Flareon 97.2%" for a league (the tile's member and roll). It carries no count: the engine ranks per resolved species, so a plain
    /// and a Shadow copy of one title are each their own best. nil where the copy is not the best for it.
    public func bestText(of id: String, title: String, _ a: Activity, pogoAssist: Bool) -> String? {
        if let key = a.league {
            guard tile(title: title, league: key, pogoAssist: pogoAssist)?.copyId == id, let slot = copies[id]?.slot(key, pogoAssist: pogoAssist), slot.status == .fits else { return nil }
            return "best: \(slot.member)" + (slot.pct.map { " " + LeaguePanel.percent($0) } ?? "")
        }
        guard let b = copies[id]?.best.first(where: { $0.area == a.rawValue }) else { return nil }
        if a == .max { return "best (needs a Dynamax copy)" }
        return "best" + (b.asName.map { " as " + $0 } ?? "")
    }

    /// The copies of a species title that rank for a use, best first (0 to `topCount` ids). Only Top and Good copies take part; the whole title is ranked, so a plain and a Shadow
    /// copy of one species are placed together, and neither the search nor a chip changes it. A league: Top before Good, then the IV rank percentile, then IV % of best, then box
    /// order, the tile's own rule, so place 1 is always the copy on the league tile. Raids, Gym, Rocket and Max: the table tier (S, A, B), then IV %, then CP, then box order.
    public func top(title: String, _ a: Activity, pogoAssist: Bool) -> [String] {
        guard let all = tops[title], let i = Activity.allCases.firstIndex(of: a) else { return [] }
        return all[(pogoAssist ? 7 : 0) + i]
    }

    /// 1 to `topCount` for a copy in its species' top places for a use, else nil.
    public func place(of id: String, title: String, _ a: Activity, pogoAssist: Bool) -> Int? {
        top(title: title, a, pogoAssist: pogoAssist).firstIndex(of: id).map { $0 + 1 }
    }

    /// 0 for Strong, 1 for OK, 2 for Weak or no tag: lower is better.
    static func worthRank(_ w: LeaguePanel.Worth?) -> Int { w == .strong ? 0 : w == .ok ? 1 : 2 }

    public static func make(advice: BoxAdvice, entries: [BoxEntry]) -> BoxInsight {
        var out = BoxInsight()
        out.copies.reserveCapacity(entries.count)
        // Per species and slot: the best copy so far. Best = the copy the row calls best for the league: Strong before OK before Weak (the tag the copy itself
        // carries, so a tile never names a Weak copy while another copy of the species is Strong), then the higher IV rank percentile, then IV %, then the
        // first in the box. The IV rank alone put a Weak Flareon copy on Eevee's Great League tile above its Strong Umbreon copy.
        struct Best { var worth: Int; var rankPct: Double; var pct: Double; var tile: Tile }
        var best = [String: [Best?]]()
        var weakest = [String: [Tile]]()
        // Per species title, the copies in box order with what the ranking reads of them.
        var seen = [String: [String]]()
        for e in entries {
            let ratings = advice.leagues(for: e.id)
            var slots = [LeaguePanel.Slot?](repeating: nil, count: 6)
            var leagueLines = [String?](repeating: nil, count: 6)
            for (l, key) in LeaguePanel.keys.enumerated() {
                guard let r = ratings[key] else { continue }
                for (i, assist) in [(l, false), (3 + l, true)] {
                    let shown = LeaguePanel.shownIndex(r, pogoAssist: assist)
                    slots[i] = LeaguePanel.slot(r, shown: shown, key: key)
                    let c = LeaguePanel.card(r, shown: shown, key: key, level: nil)
                    leagueLines[i] = LeaguePanel.worthSentence(c, key: key) ?? c.blockedText
                }
            }
            let fits = advice.fit(for: e.id)
            let fit: [LeaguePanel.Worth?] = areas.map { area in
                guard let f = fits[area] else { return nil }
                return f.tag == .strong ? .strong : f.tag == .ok ? .ok : .weak
            }
            let bestTags = advice.bestOf(for: e.id).map { area in
                Copy.BestTag(area: area, asName: area == "max" ? nil : fits[area]?.asNameLabel(shadow: e.row.shadow == 1))
            }
            let tierWeight = ["S": 3, "A": 2, "B": 1]
            out.copies[e.id] = Copy(slots: slots, fit: fit, best: bestTags, areaLines: areas.map { fits[$0]?.line }, leagueLines: leagueLines,
                                    fitTier: areas.map { a in fits[a].flatMap { $0.tag == .weak ? nil : $0.tier.flatMap { tierWeight[$0] } } ?? 0 },
                                    fitIVPct: areas.map { fits[$0]?.ivPercent ?? 0 },
                                    asNames: areas.map { fits[$0]?.asNameLabel(shadow: e.row.shadow == 1) },
                                    cp: e.row.cp)
            seen[e.row.title, default: []].append(e.id)

            let title = e.row.title
            var b = best[title] ?? [Best?](repeating: nil, count: 6)
            var w = weakest[title] ?? [Tile](repeating: Tile(status: .noData, member: "", pct: nil, copyId: nil), count: 6)
            for i in 0..<6 {
                guard let s = slots[i] else { continue }
                switch s.status {
                case .fits:
                    let rp = s.rankPct ?? 0, p = s.pct ?? 0, wr = Self.worthRank(s.worth)
                    if let cur = b[i], (-wr, rp, p) <= (-cur.worth, cur.rankPct, cur.pct) { continue }
                    b[i] = Best(worth: wr, rankPct: rp, pct: p, tile: Tile(status: .fits, member: s.member, pct: s.pct, copyId: e.id))
                case .ivsNotRead:
                    if w[i].status == .noData || w[i].status == .overCap { w[i] = Tile(status: .ivsNotRead, member: s.member, pct: nil, copyId: nil) }
                case .overCap:
                    if w[i].status == .noData { w[i] = Tile(status: .overCap, member: s.member, pct: nil, copyId: nil) }
                }
            }
            best[title] = b; weakest[title] = w
        }
        for (title, w) in weakest {
            let b = best[title] ?? []
            out.species[title] = (0..<6).map { i in b.indices.contains(i) ? (b[i]?.tile ?? w[i]) : w[i] }
        }
        for (title, ids) in seen { out.tops[title] = out.rankings(ids) }
        return out
    }

    /// The 14 top lists of one species' copies (given in box order). `sorted(by:)` is not stable, so the box position is part of every key.
    private func rankings(_ ids: [String]) -> [[String]] {
        func cap(_ keyed: [(String, [Double])]) -> [String] {
            let order = keyed.enumerated().sorted { a, b in
                for (x, y) in zip(a.element.1, b.element.1) where x != y { return x > y }
                return a.offset < b.offset
            }
            return order.prefix(Self.topCount).map { $0.element.0 }
        }
        var lists = [[String]](repeating: [], count: 14)
        for (n, a) in Activity.allCases.enumerated() {
            if let key = a.league, let l = LeaguePanel.keys.firstIndex(of: key) {
                for assist in 0...1 {
                    lists[assist * 7 + n] = cap(ids.compactMap { id in
                        guard let s = copies[id]?.slots[assist * 3 + l], s.status == .fits, let w = s.worth, w != .weak else { return nil }
                        return (id, [Double(-Self.worthRank(w)), s.rankPct ?? 0, s.pct ?? 0])
                    })
                }
            } else if let i = a.area.flatMap({ BoxInsight.areas.firstIndex(of: $0) }) {
                let list = cap(ids.compactMap { id in
                    guard let c = copies[id], c.fitTier.indices.contains(i), c.fitTier[i] > 0 else { return nil }
                    return (id, [Double(c.fitTier[i]), c.fitIVPct[i], Double(c.cp)])
                })
                lists[n] = list; lists[7 + n] = list
            }
        }
        return lists
    }
}

extension BoxAdvice.Fit {
    /// The table entry the copy is rated as, for a "best for" tag: a Shadow copy's name says so ("Tyranitar (Shadow)"), because the engine's best-of is per resolved
    /// species and a plain and a Shadow copy of one species are each their own best. Nothing is added where the engine's name already says Shadow.
    public func asNameLabel(shadow: Bool) -> String? {
        asName.map { shadow && !$0.contains("(Shadow)") ? $0 + " (Shadow)" : $0 }
    }

    /// "ADVICE BUILDS IT" on the copy that carries the advisor's primary build for the area, "ADVICE BUILDS MEGA CHARIZARD X" when the build's target is
    /// not the copy itself (compared without a "(Shadow)" suffix and without regard to case against `ownNames`, the copy's name and title); nil without a build.
    /// The same marker as the league cards' (`LeaguePanel.buildsChipText`).
    public func buildsChipText(ownNames: [String]) -> String? {
        guard build else { return nil }
        func plain(_ s: String) -> String { s.replacingOccurrences(of: " (Shadow)", with: "").lowercased() }
        guard let target = buildAs, !ownNames.contains(where: { plain($0) == plain(target) }) else { return "ADVICE BUILDS IT" }
        return "ADVICE BUILDS " + target.uppercased()
    }
}
