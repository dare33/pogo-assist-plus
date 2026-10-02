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

    private enum CodingKeys: String, CodingKey { case builds, gaps, duplicates, unresolved, spareBuilds }

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
        return out
    }
}
