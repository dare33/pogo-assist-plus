import Foundation

/// The advisor's report for one saved box, in the shape the screens use. `CoreEngine.advise` passes the JavaScript's own
/// JSON through (`builds`, `gaps`, `hygiene`); this reads the fields `scripts/advise.mjs` prints and ties each Pokémon in
/// them back to a `BoxEntry` id. The advisor is given the entries as a Poke Genie CSV whose Index column is the entry's
/// position plus one, which is how a build finds its Pokémon again.
public struct BoxAdvice: Codable, Equatable {
    public struct Build: Codable, Equatable, Identifiable {
        public var id: String { "\(entryId)|\(targetId)" }
        public var entryId: String
        public var title: String
        public var cp: Int
        public var level: Double?
        public var ivs: String?
        public var targetId: String
        public var targetName: String
        /// True when the build is a power-up of the Pokémon as it is.
        public var powerUp: Bool
        public var formChange: Bool
        public var viaMega: Bool
        public var needsDynamax: Bool
        public var spares: Int
        public var areas: [String]
        public var tier: String
        public var targetLevel: Double?
        public var dust: Int
        public var candy: Int
        public var xl: Int
        /// "GL rank 12" when the build is a league one.
        public var pvp: String?
        /// The league build's league key ("gl", "ul", "ml") and this copy's IV rank percentile there (`pvpCost.rankPct`, 100 the best spread); nil on a
        /// build with no league cost. A report cached before these fields existed decodes them as nil, which reads as an IV percentage.
        public var pvpLeague: String? = nil
        public var pvpRankPct: Double? = nil
        public var score: Double
        /// One thing still to do, as `steps` in `src/advise.js` lists them. `kind` is evolve (to, candy), formChange (to), megaEvolve,
        /// powerUp (toLevel, areas: the area keys that share that level), secondMove (certain: false when the copy's moves are unknown),
        /// eliteTM (count), cdMove or needsDynamaxCopy.
        public struct Step: Codable, Equatable {
            public var kind: String
            public var to: String?
            public var candy: Int?
            public var toLevel: Double?
            public var areas: [String]?
            public var certain: Bool?
            public var count: Int?
            public init(kind: String, to: String? = nil, candy: Int? = nil, toLevel: Double? = nil, areas: [String]? = nil, certain: Bool? = nil, count: Int? = nil) {
                self.kind = kind; self.to = to; self.candy = candy; self.toLevel = toLevel; self.areas = areas; self.certain = certain; self.count = count
            }
            /// Reads one step from the engine's JSON. A step without a kind is kept as kind "unknown" (never dropped: dropping it could turn
            /// a build with something left to do into "Already built").
            init(json v: JSONValue) {
                if case .string(let k)? = v["kind"] { kind = k } else { kind = "unknown" }
                if case .string(let t)? = v["to"] { to = t }
                if case .number(let c)? = v["candy"], let n = LeagueRating.whole(c) { candy = n }
                if case .number(let l)? = v["toLevel"] { toLevel = l }
                if let arr = v["areas"]?.arrayValue { areas = arr.compactMap { if case .string(let a) = $0 { return a } else { return nil } } }
                if case .bool(let c)? = v["certain"] { certain = c }
                if case .number(let c)? = v["count"], let n = LeagueRating.whole(c) { count = n }
            }
        }
        /// What is left to do, in order. nil only for a build read without the engine's `steps` (then `action` falls back to the plain
        /// "Power up" / "Evolve to"); an EMPTY list means the copy is already built.
        public var steps: [Step]? = nil
        /// A league the climb goes past (`leavesLeague` in `src/advise.js`): going past `bestLevel` leaves `league` (a label such as "UL").
        public struct LeaguePast: Codable, Equatable {
            public var league: String
            public var bestLevel: Double
            public init(league: String, bestLevel: Double) { self.league = league; self.bestLevel = bestLevel }
        }
        public var leavesLeague: [LeaguePast] = []
        /// "going past 27 leaves UL, going past 16 leaves GL", or nil when the climb leaves no league.
        public var leavesLeagueText: String? {
            leavesLeague.isEmpty ? nil : leavesLeague.map { "going past \(levelText($0.bestLevel)) leaves \($0.league)" }.joined(separator: ", ")
        }
        /// The level the power-up step climbs to, if there is one.
        public var climbLevel: Double? { steps?.first { $0.kind == "powerUp" }?.toLevel }

        private func areaText(_ keys: [String]?) -> String { (keys ?? []).map { BoxAdvice.areaLabel[$0] ?? $0 }.joined(separator: "/") }
        private func levelText(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(d) }

        /// What is left to do, worded as `actionText` in `src/advise.js` does: the steps joined with " + ". The Dynamax requirement is Max's
        /// alone: it goes inside the Max power-up bracket, or after the rest in brackets; a Max-only build that lacks nothing else reads
        /// "Needs a Dynamax copy", and a build with other areas and nothing left "Already built (Max needs a Dynamax copy)".
        public var action: String {
            guard let steps else { return powerUp ? "Power up" : "\(formChange ? "Form change to" : "Evolve to") \(targetName)" }
            let dynamax = steps.contains { $0.kind == "needsDynamaxCopy" }
            var inlined = false
            var parts = [String]()
            for st in steps {
                switch st.kind {
                case "evolve": parts.append("Evolve to \(st.to ?? targetName)")
                case "formChange": parts.append("Form change to \(st.to ?? targetName)")
                case "megaEvolve": parts.append("Mega evolve")
                case "powerUp":
                    let say = dynamax && (st.areas ?? []).contains("max")
                    inlined = inlined || say
                    let areas = areaText(st.areas) + (say ? "; needs a Dynamax copy" : "")
                    if let level = st.toLevel { parts.append("Power up to level \(levelText(level))" + (areas.isEmpty ? "" : " (\(areas))")) } else { parts.append("Power up") }
                case "secondMove": parts.append(st.certain == false ? "Second move (if it doesn't have it)" : "Second move")
                case "eliteTM": parts.append((st.count ?? 1) == 1 ? "1 Elite TM" : "\(st.count ?? 1) Elite TMs")
                case "cdMove": parts.append("Community Day move")
                case "needsDynamaxCopy": break
                default: parts.append("More to do") // a step this version does not know: still something left, never "Already built"
                }
            }
            if parts.isEmpty { return dynamax ? (areas == ["Max"] ? "Needs a Dynamax copy" : "Already built (Max needs a Dynamax copy)") : "Already built" }
            let base = parts.joined(separator: " + ")
            return dynamax && !inlined ? base + " (Max needs a Dynamax copy)" : base
        }
        /// This copy's IV percentage from `ivs` ("17/9/13" is 86.7); nil when the IVs are not known.
        public var ivPercent: Double? {
            let p = (ivs ?? "").split(separator: "/").compactMap { Double($0) }
            return p.count == 3 ? p.reduce(0, +) / 45 * 100 : nil
        }
        /// The roll in the Next list's words. A league build's roll is the copy's IV rank percentile for that league ("GL rank top 5%", N = 100 minus
        /// the percentile rounded up, at least 1: the figure the league card's sentence uses); an activity build's roll is the IV percentage ("IVs 24.4%").
        /// A build that covers both shows both, the league first.
        public var rollText: String {
            let ivText = ivPercent.map { "IVs " + String(format: "%.1f", $0) + "%" } ?? "IVs not read"
            guard let league = pvpLeague, let rankPct = pvpRankPct else { return ivText }
            let rank = "\(BoxAdvice.areaLabel[league] ?? league.uppercased()) rank top \(max(1, Int((100 - rankPct).rounded(.up))))%"
            let leagueLabels = ["gl", "ul", "ml"].compactMap { BoxAdvice.areaLabel[$0] }
            return areas.allSatisfy(leagueLabels.contains) ? rank : rank + " · " + ivText
        }
        /// The Next list's WORTH: the build target's tier and this copy's roll ("S-tier · IVs 17.8%", "S-tier · GL rank top 5%", "S-tier · IVs not read"), so species worth and the copy are both shown.
        public var worthText: String { "\(tier)-tier · " + rollText }
        /// The Next list's EFFORT: the cost figures only ("120k dust, 150 candy, 8 XL candy"); "No dust or candy" when all are zero. The steps themselves
        /// (a form change, a Mega, an Elite TM, a second move, a Dynamax copy) are the action line above, so they are not repeated here.
        public var effortText: String { dust != 0 || candy != 0 || xl != 0 ? costText : "No dust or candy" }
        /// "120k dust, 150 candy, 8 XL". Elite TMs and the Community Day move are steps of `action`, not repeated here.
        public var costText: String {
            var parts = [String]()
            parts.append(dust >= 1000 ? "\(Int((Double(dust) / 1000).rounded()))k dust" : "\(dust) dust")
            if candy > 0 { parts.append("\(candy) candy") }
            if xl > 0 { parts.append("\(xl) XL candy") }
            return parts.joined(separator: ", ")
        }
    }

    public struct Gap: Codable, Equatable, Identifiable {
        public var id: String { "\(area)|\(name)" }
        public var area: String
        public var section: String?
        public var tier: String
        public var name: String
        public var obtain: String?
        public var haveBase: Bool
        /// The game master id of the species the table names (Megas and forms included); nil in an advice cached before the engine sent it.
        public var speciesId: String? = nil
    }

    public struct Duplicate: Codable, Equatable, Identifiable {
        public var id: String { name }
        public var name: String
        public var count: Int
        public var keep: [String]
        public var transfer: [String]
        public var keepIds: [String]
        public var transferIds: [String]
        /// How many of the last `keep` entries are kept only because the person marked them as caught as a Dynamax (nil: none).
        public var dynamaxExtras: Int?
    }

    /// One league's ratings of one Pokémon, as `src/leagues.js` `leaguesFor` returns them (null becomes nil).
    ///
    /// `options` lists every allowed member of the Pokémon's family (strongest PvPoke score first, then the members PvPoke does not
    /// rank), each rated for this exact copy. `moves` is filled on every option PvPoke ranks (nil on an unranked one). `pick` (JSON "pick") is the index of the member to show, which copies Poke Genie;
    /// `experimental` is the index of the CLOSE_SCORE rule's member, shown under the Pogo Assist ranking. The accessors below (`pick`, `strength`,
    /// `moves`, `needs`, `iv`, `overCap`, `cost`) read the SHOWN member, so a screen written for one rating per league keeps working.
    public struct LeagueRating: Codable, Equatable {
        public struct Pick: Codable, Equatable {
            public var speciesId: String; public var name: String
            /// The Pokémon itself is the pick.
            public var isSelf: Bool
            /// "male" or "female" when the pick is an evolution only one sex can make and the entry's sex is not known (scans carry none).
            public var genderLocked: String?
        }
        public struct Strength: Codable, Equatable { public var score: Double; public var rank: Int; public var of: Int }
        public struct Moves: Codable, Equatable { public var fast: String; public var charged: [String] }
        public struct IV: Codable, Equatable { public var rank: Int; public var pct: Double; public var rankPct: Double; public var level: Double; public var cp: Int }
        public struct Cost: Codable, Equatable { public var dust: Int; public var candy: Int; public var xl: Int; public var evolveCandy: Int; public var toLevel: Double }

        /// One family member rated for this league. `strength` is nil when PvPoke does not rank it in this league (then `moves` is nil too).
        public struct Option: Codable, Equatable {
            public var speciesId: String; public var name: String
            /// JSON key "self", which Swift cannot use as a property name.
            public var isSelf: Bool
            public var genderLocked: String?
            public var strength: Strength?
            public var moves: Moves?
            public var needs: [String]?
            public var iv: IV?
            public var overCap: Bool
            public var cost: Cost?
            private enum CodingKeys: String, CodingKey { case speciesId, name, isSelf = "self", genderLocked, strength, moves, needs, iv, overCap, cost }

            /// Reads one option from the engine's parsed JSON; nil when a required field is missing or any present field is the wrong
            /// type (the same cases the Codable decoding rejects). Absent and null optional fields are nil.
            init?(json o: JSONValue) {
                func str(_ v: JSONValue?) -> String? { if case .string(let s)? = v { return s } else { return nil } }
                func dbl(_ v: JSONValue?) -> Double? { if case .number(let n)? = v { return n } else { return nil } }
                func int(_ v: JSONValue?) -> Int? { dbl(v).flatMap(LeagueRating.whole) }
                func isNull(_ v: JSONValue?) -> Bool { if v == nil { return true }; if case .null? = v { return true }; return false }
                guard let id = str(o["speciesId"]), let name = str(o["name"]), case .bool(let overCap)? = o["overCap"] else { return nil }
                self.speciesId = id; self.name = name; self.overCap = overCap
                if case .bool(let b)? = o["self"] { self.isSelf = b } else { return nil }
                if isNull(o["genderLocked"]) { self.genderLocked = nil } else if let g = str(o["genderLocked"]) { self.genderLocked = g } else { return nil }
                if isNull(o["strength"]) { self.strength = nil }
                else if let s = o["strength"], let score = dbl(s["score"]), let rank = int(s["rank"]), let of = int(s["of"]) { self.strength = Strength(score: score, rank: rank, of: of) }
                else { return nil }
                if isNull(o["moves"]) { self.moves = nil }
                else if let m = o["moves"], let fast = str(m["fast"]), let charged = m["charged"]?.arrayValue {
                    let names = charged.compactMap(str)
                    guard names.count == charged.count else { return nil }
                    self.moves = Moves(fast: fast, charged: names)
                } else { return nil }
                if isNull(o["needs"]) { self.needs = nil }
                else if let arr = o["needs"]?.arrayValue {
                    let names = arr.compactMap(str)
                    guard names.count == arr.count else { return nil }
                    self.needs = names
                } else { return nil }
                if isNull(o["iv"]) { self.iv = nil }
                else if let v = o["iv"], let rank = int(v["rank"]), let pct = dbl(v["pct"]), let rankPct = dbl(v["rankPct"]), let level = dbl(v["level"]), let cp = int(v["cp"]) {
                    self.iv = IV(rank: rank, pct: pct, rankPct: rankPct, level: level, cp: cp)
                } else { return nil }
                if isNull(o["cost"]) { self.cost = nil }
                else if let c = o["cost"], let dust = int(c["dust"]), let candy = int(c["candy"]), let xl = int(c["xl"]), let evo = int(c["evolveCandy"]), let to = dbl(c["toLevel"]) {
                    self.cost = Cost(dust: dust, candy: candy, xl: xl, evolveCandy: evo, toLevel: to)
                } else { return nil }
            }
            public init(speciesId: String, name: String, isSelf: Bool = false, genderLocked: String? = nil, strength: Strength? = nil, moves: Moves? = nil,
                        needs: [String]? = nil, iv: IV? = nil, overCap: Bool = false, cost: Cost? = nil) {
                self.speciesId = speciesId; self.name = name; self.isSelf = isSelf; self.genderLocked = genderLocked; self.strength = strength
                self.moves = moves; self.needs = needs; self.iv = iv; self.overCap = overCap; self.cost = cost
            }
        }

        public var options: [Option]
        /// Index into `options` of the member to show.
        public var pickIndex: Int
        /// Index into `options` of the experimental member (may equal `pickIndex`).
        public var experimentalIndex: Int
        /// How the shown member was chosen: "export" (Poke Genie's own pick), "emulated" (its rule applied here), "ranked" (the highest PvPoke score: Master League, or IVs unknown), "fallback" (the PvPoke-score rule ran (Master League, or unknown IVs) but none of the members it may show is ranked here: either nothing in the family is ranked, or every ranked member is past the cap. The shown member is then the final evolution if it fits, else the first option that fits, which is an unranked one (a level-50 Bulbasaur with unknown IVs shows Ivysaur in Ultra League). If no member fits and nothing is ranked, the final evolution is shown even though it is over the cap. A copy with known IVs in Great or Ultra League and nothing ranked is still "emulated").
        public var source: String

        private enum CodingKeys: String, CodingKey { case options, pickIndex = "pick", experimentalIndex = "experimental", source }

        /// The indexes are clamped into range, so the accessors never trap. `options` must not be empty.
        public init(options: [Option], pick: Int = 0, experimental: Int? = nil, source: String = "ranked") {
            precondition(!options.isEmpty, "a league rating has at least one option")
            self.options = options
            self.pickIndex = min(max(pick, 0), options.count - 1)
            self.experimentalIndex = min(max(experimental ?? pick, 0), options.count - 1)
            self.source = source
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let options = try c.decode([Option].self, forKey: .options)
            let pick = try c.decode(Int.self, forKey: .pickIndex)
            guard options.indices.contains(pick) else { throw DecodingError.dataCorruptedError(forKey: .pickIndex, in: c, debugDescription: "pick is not an index of options") }
            // Odd experimental or source values are not fatal, exactly as in `decode(_:)`: an experimental index that is missing, not a whole
            // number or out of range is the shown pick, and a source that is missing or not a string is "ranked".
            let experimental = (try? c.decodeIfPresent(Int.self, forKey: .experimentalIndex)).flatMap { $0 }.flatMap { options.indices.contains($0) ? $0 : nil }
            let source = (try? c.decodeIfPresent(String.self, forKey: .source)).flatMap { $0 } ?? "ranked"
            self.init(options: options, pick: pick, experimental: experimental, source: source)
        }

        /// A whole number that fits an Int, or nil (NaN, infinite, fractional or huge values: `Int(_:)` would trap on them).
        static func whole(_ x: Double) -> Int? {
            guard x.isFinite, x == x.rounded(), abs(x) < 9e15 else { return nil }
            return Int(x)
        }

        /// Decodes the engine's JSON for one league, tolerating a bad option: an option that does not decode is dropped and the
        /// indexes are re-pointed, so one odd member never loses the league. Returns nil only when there is no usable shown option.
        /// A bad experimental option falls back to the shown one. Each option is read straight from the parsed `JSONValue`
        /// (`Option.init?(json:)`), with no re-encode and re-decode per option: a 2,000-Pokémon box has ~13,000 of them.
        public static func decode(_ v: JSONValue) -> LeagueRating? {
            guard case .number(let p)? = v["pick"], let pickAt = whole(p), let raw = v["options"]?.arrayValue else { return nil }
            var kept = [Option](), newIndex = [Int: Int]()
            for (i, o) in raw.enumerated() {
                guard let option = Option(json: o) else { continue }
                newIndex[i] = kept.count; kept.append(option)
            }
            guard let pick = newIndex[pickAt] else { return nil }
            var experimental = pick
            if case .number(let x)? = v["experimental"], let at = whole(x), let j = newIndex[at] { experimental = j }
            var source = "ranked"
            if case .string(let s)? = v["source"] { source = s }
            return LeagueRating(options: kept, pick: pick, experimental: experimental, source: source)
        }

        /// The member to show.
        public var shown: Option { options[pickIndex] }
        /// The experimental member (shown under the Pogo Assist ranking).
        public var experimental: Option { options[experimentalIndex] }

        public var pick: Pick { Pick(speciesId: shown.speciesId, name: shown.name, isSelf: shown.isSelf, genderLocked: shown.genderLocked) }
        public var strength: Strength? { shown.strength }
        public var moves: Moves? { shown.moves }
        public var needs: [String]? { shown.needs }
        public var iv: IV? { shown.iv }
        public var overCap: Bool { shown.overCap }
        public var cost: Cost? { shown.cost }
    }

    /// 2 since the Leagues section: an advice cached by build 2 or earlier has no leagues, so `BoxLibrary.loadAdvice` drops it and it is recomputed.
    /// 3 since the league options; 4 since their shape became { options, pick, experimental, source } and the shown pick copies Poke Genie.
    /// 5 since `overCap` became "CP at the current level exceeds the cap" (0/0/0 when the IVs are unknown) and the shown pick avoids over-cap members.
    /// 6 since a build carried `powerUpNeeded` and `secondMoveDue`; 7 since those became the list of `steps` (evolve, Mega, power up, second move,
    /// Elite TM, Community Day move, Dynamax copy), which the action is worded from; 8 since the power-up step is the climb the cost covers, builds carry
    /// `leavesLeague`, the second move follows the unlocked charged slot, and `eliteTMs` / `communityDayMove` are gone; 9 since every option PvPoke ranks carries its
    /// `moves` (before, only the shown and experimental ones did). Advice cached at 2 to 8 has the old shape or the old rules, so it is dropped and recomputed too.
    /// Versions 10 and 11 were written by dev builds of a branch that carried interim payload fields (since removed), so they are taken: the next real
    /// bump must be 12 or higher, or such a cache would pass for the new shape (`loadAdvice` keeps any version at or above this one).
    /// 12 since each Pokémon carries `fit` (a Strong / OK / Weak tag per Raids, Gym, Rocket and Max, in the compact form the bridge sends) and `bestOf` (the areas it is its species' best copy for).
    /// 14 since the Gigantamax Max rows kept their prefix (a Dynamax copy is no longer credited with a Gigantamax entry); 13 is reserved by
    /// the open design stack, so any later merge must go above 14.
    public static let currentVersion = 14
    public var version: Int = BoxAdvice.currentVersion
    public var builds: [Build]
    public var gaps: [Gap]
    public var duplicates: [Duplicate]
    /// Entry ids the advisor could not place in any species (their species is not in its data).
    public var unresolved: [String]

    public init(builds: [Build] = [], gaps: [Gap] = [], duplicates: [Duplicate] = [], unresolved: [String] = []) {
        self.builds = builds; self.gaps = gaps; self.duplicates = duplicates; self.unresolved = unresolved
    }

    public static let areaLabel = ["raids": "Raids", "rocket": "Rocket", "gym": "Gym", "gl": "GL", "ul": "UL", "ml": "ML", "max": "Max"]

    /// What the advisor said about one Pokémon: the builds it is part of (as the best copy or a spare), and whether it is a
    /// duplicate to keep or to transfer.
    public struct ForEntry: Equatable {
        public var builds: [Build]
        public var spareFor: [Build]
        public var duplicateOf: Duplicate?
        public var keep: Bool
        public var isEmpty: Bool { builds.isEmpty && spareFor.isEmpty && duplicateOf == nil }
        /// This copy's position in the duplicate's kept list (nil when it is not kept).
        public var keepIndex: Int?
        /// No build of its own, and the hygiene rule would transfer it.
        public var transfersWithNoBuild: Bool { builds.isEmpty && duplicateOf != nil && !keep }
    }

    public func entries(for id: String) -> ForEntry {
        let dup = duplicates.first { $0.keepIds.contains(id) || $0.transferIds.contains(id) }
        return ForEntry(builds: builds.filter { $0.entryId == id }, spareFor: spareBuilds[id] ?? [], duplicateOf: dup, keep: dup?.keepIds.contains(id) ?? false,
                        keepIndex: dup?.keepIds.firstIndex(of: id))
    }
    /// entry id -> builds it is a spare copy for (built when decoding is not needed: filled by `make`).
    var spareBuilds: [String: [Build]] = [:]
    /// entry id -> "gl" | "ul" | "ml" -> that league's rating.
    public var leagues: [String: [String: LeagueRating]] = [:]

    public func leagues(for id: String) -> [String: LeagueRating] { leagues[id] ?? [:] }

    /// IV % (the average of the three IVs) at or above which a copy with a table entry in reach is OK or Strong rather than Weak. Mirror of `FIT_IV_PCT` in
    /// `src/advise.js` (which decides the tag; this only words the Weak reason), so change the pair together.
    public static let fitIVPercent = 80.0

    /// How well one copy suits one non-league activity area, as `src/advise.js` `fit` says it. The bridge carries a compact array (see
    /// `native/tools/pogo-core-facade.js`) and the app composes the sentence (`line`) from it as the engine words it.
    public struct Fit: Codable, Equatable {
        /// The tag is worth alone, free of cost: "strong" (a reachable S-tier use, IVs at `fitIVPercent` or more), "ok" (an A or B one, same IVs) or "weak".
        public enum Tag: String, Codable { case strong, ok, weak }
        /// Why a Weak copy is weak: no table entry in reach, IVs below the threshold, IVs unknown, or a Shadow copy whose only entries are Mega ones.
        public enum Reason: String, Codable { case none, iv, ivUnknown, shadowNoMega }
        /// What the advisor's build for the area costs, the figures the Advice panel shows.
        public struct BuildCost: Codable, Equatable {
            public var dust: Int
            public var candy: Int
            public var xl: Int
            public init(dust: Int, candy: Int, xl: Int) { self.dust = dust; self.candy = candy; self.xl = xl }
        }
        public var area: String
        public var tag: Tag
        /// The table entry the copy is rated as ("Mega Delphox"); nil for weak.
        public var asName: String?
        public var tier: String?
        public var reason: Reason?
        /// The engine's display name for a Weak "none" line (it composes the form itself); nil for any other reason.
        public var species: String?
        public var ivPercent: Double?
        /// True on the copy that carries the advisor's primary build for the area (a separate marker: it says nothing about the tag, which is worth alone).
        public var build: Bool = false
        /// That build's target name and cost; nil unless `build`.
        public var buildAs: String?
        public var buildCost: BuildCost?

        public var line: String {
            let label = BoxAdvice.areaLabel[area] ?? area
            switch tag {
            case .strong, .ok:
                let tierPart = tier.map { " \($0)" } ?? ""
                let asPart = asName.map { " as \($0)" } ?? ""
                return "\(label)\(tierPart)\(asPart)\(area == "max" ? " (needs a Dynamax copy)" : "")"
            case .weak:
                // A reason code this build does not know must not read as "no table entry": say only that the copy is weak here.
                guard let reason else { return "Weak for \(label)" }
                switch reason {
                case .none: return species.map { "No table entry for \($0) in \(label)" } ?? "No table entry in \(label)"
                case .ivUnknown: return "IVs not known"
                case .shadowNoMega: return "A Shadow copy cannot Mega evolve"
                case .iv:
                    // One decimal, a whole number without it ("80%", "66.7%"), as the engine's Number(toFixed(1)) prints it.
                    let pct = ((ivPercent ?? 0) * 10).rounded() / 10
                    let text = pct == pct.rounded() ? String(Int(pct)) : String(format: "%.1f", pct)
                    return "IVs \(text)%, below \(Int(BoxAdvice.fitIVPercent))%"
                }
            }
        }

        /// Decodes one area's compact array; nil when the tag is not one the app knows. `ivPercent` is the fallback for a reason "iv" that carries no
        /// figure of its own; the engine's one-decimal figure at index 4 wins when present (it prefers the row's imported %). A build tail
        /// `[true, buildAs, dust, candy, xl]` follows index 2 for s / o and index 4 for w (index 4 is then the extra or null).
        static func decode(area: String, _ v: JSONValue, ivPercent: Double?) -> Fit? {
            guard let a = v.arrayValue, case .string(let t)? = a.first else { return nil }
            func str(_ i: Int) -> String? { if i < a.count, case .string(let s) = a[i] { return s } else { return nil } }
            // The same range-checked whole-number reading as the league decoder: `Int(_:)` traps on NaN, infinity and huge values.
            func num(_ i: Int) -> Int? { if i < a.count, case .number(let n) = a[i] { return LeagueRating.whole(n) } else { return nil } }
            let tag: Tag
            switch t { case "s": tag = .strong; case "o": tag = .ok; case "w": tag = .weak; default: return nil }
            // A strong or ok fit always names the build species and the tier; one without them is not a Strong the app can word, so it is skipped.
            if tag != .weak, str(1) == nil || str(2) == nil { return nil }
            var pct = ivPercent
            var species: String?
            let reason = str(3).flatMap(Reason.init(rawValue:))
            if tag == .weak {
                if 4 < a.count, case .number(let n) = a[4] { pct = n }
                if reason == Reason.none { species = str(4) }  // not `.none`: that would be Optional.none
            }
            var f = Fit(area: area, tag: tag, asName: str(1), tier: str(2), reason: reason, species: species, ivPercent: pct)
            let tail = tag == .weak ? 5 : 3
            if tail < a.count, case .bool(true) = a[tail], let name = str(tail + 1), let d = num(tail + 2), let c = num(tail + 3), let x = num(tail + 4) {
                f.build = true; f.buildAs = name; f.buildCost = BuildCost(dust: d, candy: c, xl: x)
            }
            return f
        }
    }
    /// entry id -> "raids" | "gym" | "rocket" | "max" -> that area's fit. Empty for an advice the JavaScript wrote without `fit`.
    public var fit: [String: [String: Fit]] = [:]
    /// entry id -> the areas this copy is the best of its species for (at most one copy per species per area).
    public var bestOf: [String: [String]] = [:]

    public func fit(for id: String) -> [String: Fit] { fit[id] ?? [:] }
    public func bestOf(for id: String) -> [String] { bestOf[id] ?? [] }

    private enum CodingKeys: String, CodingKey { case version, builds, gaps, duplicates, unresolved, spareBuilds, leagues, fit, bestOf }

    // MARK: - from the JavaScript's JSON

    /// `report` is `CoreEngine.advise(rows:)`'s result; `entries[i]` is the Pokémon with CSV Index `i + 1`.
    public static func make(from report: JSONValue, entries: [BoxEntry]) -> BoxAdvice {
        func id(_ p: JSONValue?) -> String? {
            guard case .number(let n)? = p?["index"], Int(n) >= 1, Int(n) <= entries.count else { return nil }
            return entries[Int(n) - 1].id
        }
        func str(_ v: JSONValue?) -> String? { if case .string(let s)? = v { return s } else { return nil } }
        func num(_ v: JSONValue?) -> Double? { if case .number(let n)? = v { return n } else { return nil } }
        func int(_ v: JSONValue?) -> Int { Int(num(v) ?? 0) }
        func bool(_ v: JSONValue?) -> Bool { if case .bool(let b)? = v { return b } else { return false } }
        func title(_ p: JSONValue?) -> String {
            let name = str(p?["name"]) ?? "?", form = str(p?["form"]) ?? ""
            return (form.isEmpty || form == "Normal" ? name : "\(name) (\(form))") + (bool(p?["shadow"]) ? " (Shadow)" : "")
        }
        var out = BoxAdvice()
        for b in report["builds"]?.arrayValue ?? [] {
            guard let p = b["pokemon"], let eid = id(p) else { continue }
            let cost = b["cost"]
            var ivs: String?
            if let i = p["ivs"], case .number(let a)? = i["atk"], case .number(let d)? = i["def"], case .number(let h)? = i["hp"] { ivs = "\(Int(a))/\(Int(d))/\(Int(h))" }
            var pvp: String?
            if let pc = b["pvpCost"], let league = str(pc["league"]) { pvp = "\(league.uppercased()) rank \(int(pc["rank"]))" }
            let spares = (b["spares"]?.arrayValue ?? []).compactMap { id($0) }
            let build = Build(entryId: eid, title: title(p), cp: int(p["cp"]), level: num(b["level"]) ?? num(p["level"]), ivs: ivs,
                              targetId: str(b["targetId"]) ?? "", targetName: str(b["targetName"]) ?? "?", powerUp: str(b["targetId"]) == str(b["speciesId"]),
                              formChange: bool(b["formChange"]), viaMega: bool(b["viaMega"]), needsDynamax: bool(b["needsDynamax"]), spares: spares.count,
                              areas: (b["areas"]?.arrayValue ?? []).compactMap { str($0) }.map { areaLabel[$0] ?? $0 },
                              tier: str(b["bestTier"]) ?? "", targetLevel: num(b["targetLevel"]), dust: int(cost?["dust"]), candy: int(cost?["candy"]), xl: int(cost?["xl"]),
                              pvp: pvp, pvpLeague: str(b["pvpCost"]?["league"]), pvpRankPct: num(b["pvpCost"]?["rankPct"]), score: num(b["score"]) ?? 0,
                              steps: b["steps"]?.arrayValue.map { $0.map(Build.Step.init(json:)) },
                              leavesLeague: (b["leavesLeague"]?.arrayValue ?? []).compactMap { v in
                                  guard case .string(let l)? = v["league"], case .number(let at)? = v["bestLevel"] else { return nil }
                                  return Build.LeaguePast(league: areaLabel[l] ?? l, bestLevel: at)
                              })
            out.builds.append(build)
            for s in spares { out.spareBuilds[s, default: []].append(build) }
        }
        for g in report["gaps"]?.arrayValue ?? [] {
            out.gaps.append(Gap(area: areaLabel[str(g["area"]) ?? ""] ?? str(g["area"]) ?? "", section: str(g["section"]), tier: str(g["tier"]) ?? "", name: str(g["name"]) ?? "?",
                                obtain: str(g["obtain"]), haveBase: bool(g["haveBase"]), speciesId: str(g["speciesId"])))
        }
        for h in report["hygiene"]?.arrayValue ?? [] {
            func line(_ p: JSONValue) -> String {
                let ivs: String = {
                    if let i = p["ivs"], case .number(let a)? = i["atk"], case .number(let d)? = i["def"], case .number(let hh)? = i["hp"] { return "\(Int(a))/\(Int(d))/\(Int(hh))" }
                    return "IVs unknown"
                }()
                return "CP \(int(p["cp"])), \(ivs)"
            }
            let keep = h["keep"]?.arrayValue ?? [], transfer = h["transfer"]?.arrayValue ?? []
            out.duplicates.append(Duplicate(name: str(h["name"]) ?? "?", count: int(h["count"]), keep: keep.map(line), transfer: transfer.map(line),
                                            keepIds: keep.compactMap { id($0) }, transferIds: transfer.compactMap { id($0) },
                                            dynamaxExtras: h["dynamaxExtras"].flatMap { if case .number(let n) = $0 { return Int(n) } else { return nil } }))
        }
        for e in report["pokemon"]?.arrayValue ?? [] where bool(e["unresolved"]) { if let eid = id(e["p"]) { out.unresolved.append(eid) } }
        for e in report["pokemon"]?.arrayValue ?? [] {
            guard let eid = id(e["p"]), let l = e["leagues"] else { continue }
            var byLeague = [String: LeagueRating]()
            for key in ["gl", "ul", "ml"] {
                // Per option, so one member the decoder cannot read does not take the league (and the shown pick) with it.
                guard let v = l[key], let rating = LeagueRating.decode(v) else { continue }
                byLeague[key] = rating
            }
            if !byLeague.isEmpty { out.leagues[eid] = byLeague }
        }
        // Optional: a report without `fit` / `bestOf` (older JavaScript) still decodes, with no tags.
        for e in report["pokemon"]?.arrayValue ?? [] {
            guard let eid = id(e["p"]), case .number(let n)? = e["p"]?["index"] else { continue }
            let row = entries[Int(n) - 1].row
            let ivPercent = row.ivs.map { Double($0.atk + $0.def + $0.hp) / 45 * 100 }
            var fits = [String: Fit]()
            if case .object(let areas)? = e["fit"] {
                for (area, v) in areas {
                    if let f = Fit.decode(area: area, v, ivPercent: ivPercent) { fits[area] = f }
                }
            }
            if !fits.isEmpty { out.fit[eid] = fits }
            let best = (e["bestOf"]?.arrayValue ?? []).compactMap { str($0) }
            if !best.isEmpty { out.bestOf[eid] = best }
        }
        return out
    }
}
