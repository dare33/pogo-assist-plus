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
        public var eliteTMs: Int
        public var communityDayMove: Bool
        /// "GL rank 12" when the build is a league one.
        public var pvp: String?
        public var score: Double

        /// What to do, as `scripts/advise.mjs` words it.
        public var action: String {
            (powerUp ? "Power up" : "\(formChange ? "Form change to" : "Evolve to") \(targetName)") + (viaMega ? " and Mega evolve" : "")
        }
        /// "120k dust, 150 candy, 8 XL, 1 Elite TM".
        public var costText: String {
            var parts = [String]()
            parts.append(dust >= 1000 ? "\(Int((Double(dust) / 1000).rounded()))k dust" : "\(dust) dust")
            if candy > 0 { parts.append("\(candy) candy") }
            if xl > 0 { parts.append("\(xl) XL candy") }
            if eliteTMs > 0 { parts.append(eliteTMs == 1 ? "1 Elite TM" : "\(eliteTMs) Elite TMs") }
            if communityDayMove { parts.append("Community Day move") }
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
    }

    public struct Duplicate: Codable, Equatable, Identifiable {
        public var id: String { name }
        public var name: String
        public var count: Int
        public var keep: [String]
        public var transfer: [String]
        public var keepIds: [String]
        public var transferIds: [String]
    }

    /// One league's ratings of one Pokémon, as `src/leagues.js` `leaguesFor` returns them (null becomes nil).
    ///
    /// `options` lists every allowed member of the Pokémon's family (strongest PvPoke score first, then the members PvPoke does not
    /// rank), each rated for this exact copy. `moves` is filled only on the shown and experimental options (nil on the rest). `pick` (JSON "pick") is the index of the member to show, which copies Poke Genie;
    /// `experimental` is the index of the CLOSE_SCORE rule's member, carried but not shown. The accessors below (`pick`, `strength`,
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
        /// How the shown member was chosen: "export" (Poke Genie's own pick), "emulated" (its rule applied here), "ranked" (the highest PvPoke score: Master League, or IVs unknown), "fallback" (the PvPoke-score rule ran (Master League, or unknown IVs) but none of the members it may show is ranked here: either nothing in the family is ranked, or every ranked member is past the cap. The shown member is then the final evolution if it fits, else the first option that fits, which is an unranked one (a level-50 Bulbasaur with unknown IVs shows Ivysaur in Ultra League). A copy with known IVs in Great or Ultra League and nothing ranked is still "emulated").
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
        /// The experimental member (not shown).
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
    /// Advice cached at 2, 3 or 4 has the old shape or the old rules, so it is dropped and recomputed too.
    public static let currentVersion = 5
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
    }

    public func entries(for id: String) -> ForEntry {
        let dup = duplicates.first { $0.keepIds.contains(id) || $0.transferIds.contains(id) }
        return ForEntry(builds: builds.filter { $0.entryId == id }, spareFor: spareBuilds[id] ?? [], duplicateOf: dup, keep: dup?.keepIds.contains(id) ?? false)
    }
    /// entry id -> builds it is a spare copy for (built when decoding is not needed: filled by `make`).
    var spareBuilds: [String: [Build]] = [:]
    /// entry id -> "gl" | "ul" | "ml" -> that league's rating.
    public var leagues: [String: [String: LeagueRating]] = [:]

    public func leagues(for id: String) -> [String: LeagueRating] { leagues[id] ?? [:] }

    private enum CodingKeys: String, CodingKey { case version, builds, gaps, duplicates, unresolved, spareBuilds, leagues }

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
            let cost = b["cost"], flags = b["moveFlags"]
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
                              eliteTMs: int(flags?["elite"]), communityDayMove: bool(flags?["cd"]), pvp: pvp, score: num(b["score"]) ?? 0)
            out.builds.append(build)
            for s in spares { out.spareBuilds[s, default: []].append(build) }
        }
        for g in report["gaps"]?.arrayValue ?? [] {
            out.gaps.append(Gap(area: areaLabel[str(g["area"]) ?? ""] ?? str(g["area"]) ?? "", section: str(g["section"]), tier: str(g["tier"]) ?? "", name: str(g["name"]) ?? "?",
                                obtain: str(g["obtain"]), haveBase: bool(g["haveBase"])))
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
                                            keepIds: keep.compactMap { id($0) }, transferIds: transfer.compactMap { id($0) }))
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
        return out
    }
}
