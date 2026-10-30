import Foundation
@testable import PogoBox
import PogoReader

/// Hand-made boxes, builds, tier tables and rotation rows for the pass 2 and pass 3 rule tests. The game master and the type chart are the bundled ones;
/// everything else is built per test, so a rule is pinned on exactly the data it reads.
enum P23 {
    static let anyone: (String, String) -> Bool = { _, _ in true }
    static let gm = try! GameMaster.bundled()
    static let hub = try! HubData.bundled()

    static func build(_ entry: String, _ target: String, areas: [String], tier: String = "A", score: Double = 50, built: Bool = true, powerUp: Bool = true,
                      formChange: Bool = false, viaMega: Bool = false, dust: Int = 0, candy: Int = 0, level: Double? = 30, targetLevel: Double? = nil,
                      title: String? = nil, pvp: String? = nil, steps: [BoxAdvice.Build.Step]? = nil) -> BoxAdvice.Build {
        let name = gm.byId[target]?.name ?? target
        let todo: [BoxAdvice.Build.Step] = steps ?? (built ? [] : [.init(kind: "powerUp", toLevel: targetLevel ?? 40, areas: areas.map { $0.lowercased() })])
        return BoxAdvice.Build(entryId: entry, title: title ?? name, cp: 1000, level: level, ivs: nil, targetId: target, targetName: name, powerUp: powerUp,
                               formChange: formChange, viaMega: viaMega, needsDynamax: false, spares: 0, areas: areas, tier: tier, targetLevel: targetLevel,
                               dust: dust, candy: candy, xl: 0, pvp: pvp, score: score, steps: todo)
    }

    static func entry(_ id: String, _ species: String, ivs: IVs? = IVs(atk: 10, def: 10, hp: 10), level: Double? = 30, cp: Int = 1000, dynamax: Bool? = nil,
                      shadow: Int? = nil) -> BoxEntry {
        let s = gm.byId[species]!
        let nf = GameMaster.nameAndForm(s.name)
        let row = ScanRow(index: 1, name: nf.name, display: nf.name, form: nf.form, speciesId: species, dex: s.dex, cp: cp, hp: 100, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                          level: level, levelMax: level, dust: nil, solveStatus: "exact", flags: [], frames: [], shadow: shadow, dynamax: dynamax)
        let d = Date(timeIntervalSince1970: 1_790_000_000)
        return BoxEntry(id: id, row: row, firstSeen: d, lastSeen: d)
    }

    static func tierEntry(_ area: String, _ section: String, _ tier: String, _ species: String, role: String? = nil, shadow: Bool = false, mega: Bool = false,
                          max: Bool = false, name: String? = nil, rank: Double? = nil, obtain: String? = nil) -> TierTable.Entry {
        TierTable.Entry(area: area, kind: "x", section: section, tier: tier, rank: rank, name: name ?? gm.byId[species]?.name ?? species, speciesId: species,
                        flags: .init(shadow: shadow, mega: mega, max: max), role: role, obtain: obtain)
    }

    static func table(_ e: [TierTable.Entry]) -> TierTable { TierTable(entries: e) }

    static func boss(_ id: String, types: [String]) -> HubData.Boss { HubData.Boss(name: gm.byId[id]?.name ?? id, speciesId: id, types: types, shadow: nil) }

    static func row(_ from: String, _ to: String, _ kind: HubData.Kind = .fiveStar, title: String = "Test raid", bosses: [HubData.Boss]) -> HubData.RotationRow {
        HubData.RotationRow(from: from, to: to, kind: kind, title: title, bosses: bosses, note: "", source: "", tba: nil)
    }

    static func ctx(builds: [BoxAdvice.Build] = [], gaps: [BoxAdvice.Gap] = [], entries: [BoxEntry] = [], table t: TierTable = table([]), today: String = "2026-10-25",
                    rotation: [HubData.RotationRow]? = nil, leagues: [String: [String: BoxAdvice.LeagueRating]] = [:], edit: ((inout HubData) -> Void)? = nil) -> HubContext {
        var a = BoxAdvice(builds: builds, gaps: gaps)
        a.leagues = leagues
        var h = hub
        if let rotation { h.rotation = rotation }
        edit?(&h)
        return HubContext(advice: a, entries: entries, gm: gm, hub: h, table: t, today: today)
    }

    static func gap(_ area: String, _ name: String, _ species: String, tier: String = "S", section: String? = nil, obtain: String? = nil) -> BoxAdvice.Gap {
        BoxAdvice.Gap(area: area, section: section, tier: tier, name: name, obtain: obtain, haveBase: false, speciesId: species)
    }

    /// One league option with the figures a candidate needs.
    static func option(_ species: String, isSelf: Bool = true, score: Double, ivRank: Int = 50, overCap: Bool = false, dust: Int = 0, candy: Int = 0) -> BoxAdvice.LeagueRating.Option {
        .init(speciesId: species, name: gm.byId[species]?.name ?? species, isSelf: isSelf, strength: .init(score: score, rank: 10, of: 100), moves: nil, needs: nil,
              iv: .init(rank: ivRank, pct: 95, rankPct: 99, level: 20, cp: 1490), overCap: overCap, cost: .init(dust: dust, candy: candy, xl: 0, evolveCandy: 0, toLevel: 20))
    }

    static func rating(_ options: [BoxAdvice.LeagueRating.Option]) -> BoxAdvice.LeagueRating { BoxAdvice.LeagueRating(options: options, pick: 0) }
}
