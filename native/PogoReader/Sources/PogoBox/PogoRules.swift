import Foundation
import PogoReader

/// What pass 2 (the Hub's squads) and pass 3 (the Pokémon page's activity tabs) both compute, written once so the two cannot disagree: bulk,
/// "a type hits X for more than normal damage", the Max and raid roles, and reach. Pure; nothing here reads the clock or the disk.
/// The rules are the numbered rules of `design_handoff_pass-2-hub/CONCEPTS.md` and `design_handoff_pass-3-pokemon/CONCEPTS.md`.

/// Everything a rule needs besides the arguments it is asked about. `today` is the local calendar day `yyyy-mm-dd` (`HubModel.today()`), passed in
/// so no rule reads the clock.
public struct HubContext {
    public var advice: BoxAdvice
    public var entries: [BoxEntry]
    public var gm: GameMaster
    public var hub: HubData
    public var table: TierTable
    public var today: String
    private let byId: [String: BoxEntry]

    public init(advice: BoxAdvice, entries: [BoxEntry], gm: GameMaster, hub: HubData, table: TierTable, today: String) {
        self.advice = advice; self.entries = entries; self.gm = gm; self.hub = hub; self.table = table; self.today = today
        byId = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The box entry with this id (the stable id the app keeps through re-scans); nil when the copy has left the box.
    public func entry(_ id: String) -> BoxEntry? { byId[id] }
}

extension HubData {
    /// "A type hits X for more than normal damage" (the rule both passes use): one of the `attacking` types is super-effective against a Pokémon of
    /// the `defending` types. `HubTeams.hits` and the grunt lists use the same 1.0001 threshold.
    public func beats(_ attacking: [String], _ defending: [String]) -> Bool {
        attacking.contains { effectiveness($0, against: defending) > 1.0001 }
    }
}

public enum PogoRules {
    // MARK: bulk (pass 2 rule 14, pass 3 Terms)

    /// The CP multiplier for a level of the game's table (1 to 51 in half steps); nil for any other number. `PogoReader.cpm` traps on those.
    public static func cpm(_ level: Double) -> Double? {
        guard level >= 1, level <= 51, abs(level * 2 - (level * 2).rounded()) < 1e-9 else { return nil }
        return PogoReader.cpm(level)
    }

    /// Why a bulk figure is there or not. Nothing is assumed: an unread level or unread IVs give no figure (read-back Q5; the design helper's
    /// level-20 and 0.6 CPM fallbacks are not carried over).
    public enum Bulk: Equatable {
        case known(Double)
        case levelNotRead
        case ivsNotRead
        case unknownSpecies

        public var value: Double? { if case .known(let v) = self { return v } else { return nil } }
        public var isKnown: Bool { value != nil }
    }

    /// (target base Defence + the copy's Defence IV) × CPM × floor((target base HP + the copy's HP IV) × CPM). Not rounded: the screens round for display.
    public static func bulk(target speciesId: String, ivs: IVs?, level: Double?, gm: GameMaster) -> Bulk {
        guard let base = gm.byId[speciesId]?.baseStats else { return .unknownSpecies }
        guard let level, let m = cpm(level) else { return .levelNotRead }
        guard let ivs else { return .ivsNotRead }
        return .known(Double(base.def + ivs.def) * m * (Double(base.hp + ivs.hp) * m).rounded(.down))
    }

    // MARK: reach (pass 3 rule 10)

    /// The copy's species and the evolutions below it, breadth first, never back up the family. Ids the game master does not know are dropped
    /// (the species itself is kept when unknown, so a copy always reaches itself).
    public static func reach(of speciesId: String, gm: GameMaster) -> [String] {
        var out = [speciesId], i = 0
        while i < out.count {
            for e in gm.byId[out[i]]?.evolutions ?? [] where gm.byId[e] != nil && !out.contains(e) { out.append(e) }
            i += 1
        }
        return out
    }

    // MARK: roles

    /// Raid roles (pass 2 rules 8 and 10).
    public enum RaidRole: String, Codable, CaseIterable {
        case mega = "Mega", heavy = "Heavy hitter", bulky = "Bulky hitter"
        /// The suggested squad's slots: one Mega, three Heavy, two Bulky.
        public static let suggested: [RaidRole] = [.mega, .heavy, .heavy, .heavy, .bulky, .bulky]
    }

    /// An attacker is a Heavy hitter when its base Attack is at least this many times its base Defence.
    public static let heavyRatio = 1.3

    /// Rule 8: Mega when the build mega evolves or targets a Mega or Primal; Heavy hitter when the copy is Shadow or the target's base Attack ≥ 1.3 ×
    /// base Defence; Bulky hitter otherwise. `shadow` is the copy's own state (`HubRaidsModel.isShadow`).
    public static func raidRole(targetId: String, viaMega: Bool, shadow: Bool, gm: GameMaster) -> RaidRole {
        if viaMega || targetId.contains("_mega") || targetId.contains("_primal") { return .mega }
        if shadow || targetId.hasSuffix("_shadow") { return .heavy }
        if let s = gm.byId[targetId]?.baseStats, Double(s.atk) >= heavyRatio * Double(s.def) { return .heavy }
        return .bulky
    }

    /// Max roles (pass 2 rule 12).
    public enum MaxRole: String, Codable, CaseIterable {
        case tank = "Tank", healer = "Healer", attacker = "Attacker"
        /// The suggested squad's slots.
        public static let suggested: [MaxRole] = [.tank, .healer, .attacker]
    }

    /// The roles one Max table entry gives: section Attackers = Attacker; role text containing "tank" = Tank, "healer" = Healer (Blissey both).
    public static func maxRoles(_ e: TierTable.Entry) -> [MaxRole] {
        if e.section == "Attackers" { return [.attacker] }
        let r = (e.role ?? "").lowercased()
        return [r.contains("tank") ? MaxRole.tank : nil, r.contains("healer") ? MaxRole.healer : nil].compactMap { $0 }
    }

    /// The roles of a species over its usable Max entries (Gigantamax entries never), in Tank, Healer, Attacker order.
    public static func maxRoles(of speciesId: String, table: TierTable) -> [MaxRole] {
        let all = HubRaidsModel.maxEntries(speciesId, table).flatMap(maxRoles)
        return MaxRole.allCases.filter(all.contains)
    }

    /// True when any of the species' types hits any boss of the row for more than normal damage (the Max "attacker that hits the boss").
    public static func hitsAnyBoss(_ speciesTypes: [String], row: HubData.RotationRow, hub: HubData) -> Bool {
        row.bosses.contains { hub.beats(speciesTypes, $0.types) }
    }

    /// A tier letter as a sort key: S, A, B, then the rest.
    public static func tierRank(_ tier: String) -> Int { HubRaidsModel.tierRank(tier) }
}
