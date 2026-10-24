import Foundation

/// What the Pokémon list and the species list read for every copy, worked out once per box version and once per ranking (never per row render or
/// per keystroke): the copy's tag in each league under both rankings and in each activity, and per species the tile of each league (the species'
/// best copy and the member it is rated as). The tag rules are the ones the Pokémon page uses: a league's is `LeaguePanel.slot` (the pick card's
/// headline member, tier and roll), an activity's is the advice's `fit` tag. Both rankings are built together so that switching is instant.
public struct BoxInsight {
    /// The seven things a list chip can filter by, in the order the chips run.
    public enum Activity: String, CaseIterable, Hashable {
        case raids, gym, rocket, gl, ul, ml, max

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

    public init() {}

    public func tile(title: String, league: String, pogoAssist: Bool) -> Tile? {
        guard let l = LeaguePanel.keys.firstIndex(of: league), let t = species[title] else { return nil }
        return t[(pogoAssist ? 3 : 0) + l]
    }

    /// The tag of a copy for a chip, nil when unknown.
    public func worth(of id: String, _ a: Activity, pogoAssist: Bool) -> LeaguePanel.Worth? { copies[id]?.worth(a, pogoAssist: pogoAssist) }

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
        for e in entries {
            let ratings = advice.leagues(for: e.id)
            var slots = [LeaguePanel.Slot?](repeating: nil, count: 6)
            for (l, key) in LeaguePanel.keys.enumerated() {
                guard let r = ratings[key] else { continue }
                slots[l] = LeaguePanel.slot(r, shown: LeaguePanel.shownIndex(r, pogoAssist: false), key: key)
                slots[3 + l] = LeaguePanel.slot(r, shown: LeaguePanel.shownIndex(r, pogoAssist: true), key: key)
            }
            let fits = advice.fit(for: e.id)
            let fit: [LeaguePanel.Worth?] = areas.map { area in
                guard let f = fits[area] else { return nil }
                return f.tag == .strong ? .strong : f.tag == .ok ? .ok : .weak
            }
            out.copies[e.id] = Copy(slots: slots, fit: fit)

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
        return out
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
