import Foundation
import PogoReader

/// Design pass 2 (Pogo Hub squads): the rules the Raids, Max, Gym, Rocket and PvP squad screens share. Rule numbers are those of
/// `design_handoff_pass-2-hub/CONCEPTS.md`. The per-screen rules are in `HubSquads+Areas.swift`; where squads are kept is `SquadStore.swift`.
/// Everything is pure: the box, the advice, the rotation and "today" come in as arguments.
public enum SquadMode: String, Codable, CaseIterable {
    /// The player's own Pokémon as they are now, best first for the slot (the default, D29).
    case available
    /// The best Pokémon in the game for the slot from the research tables, owned or not (`HubSquads.BestRow`); the box's candidate lists with `.best` remain for the
    /// lists that still read the box alone (the Rocket grunt counters, Next best).
    case best
}

public enum SquadScreen: String, Codable, CaseIterable {
    case raids, max, gym, rocket, pvp
}

/// The role that allows any Pokémon (D16).
public let squadRoleAll = "All"

/// The prefix of a pick id that names a species rather than a copy: a Best squad may hold a Pokémon the box does not have (`SquadSlot.species`).
public let squadSpeciesPrefix = "species:"

/// One slot of a squad as the player left it: its role and the Pokémon they chose (an entry id), nil when the slot shows the suggestion. Under Best the player may
/// instead choose a species they do not own: `species` is its key (`HubSquads.BestRow.key`). A slot holds one or the other. A file written before species picks
/// existed has no `species` and reads as it did.
public struct SquadSlot: Codable, Equatable {
    public var role: String
    public var pick: String?
    public var species: String?
    public init(role: String, pick: String? = nil, species: String? = nil) { self.role = role; self.pick = pick; self.species = species }

    /// The pick as one id: the copy's entry id, else `squadSpeciesPrefix` + the species key.
    public var pickId: String? { pick ?? species.map { squadSpeciesPrefix + $0 } }
}

/// A slot with its Pokémon worked out: the player's pick, else the suggestion, else nothing.
public struct FilledSlot: Equatable {
    public var role: String
    public var entryId: String?
    /// The species key of a Pokémon the box does not have (Best only); `entryId` is nil then.
    public var species: String? = nil
    /// True when the player chose it; false for a suggestion.
    public var chosen: Bool
    /// True when no Pokémon is listed for the role and the slot took the best unused one of another role (PvP, rule 23).
    public var fallback: Bool
    /// The slot's Pokémon as one id (the copy's entry id, else `squadSpeciesPrefix` + the species key); nil when the slot is empty.
    public var pickId: String? { entryId ?? species.map { squadSpeciesPrefix + $0 } }
    /// Every id the slot's Pokémon goes by: its copy and its species (a species pick that reads as a copy has both).
    public var ids: Set<String> { Set([entryId, species.map { squadSpeciesPrefix + $0 }].compactMap { $0 }) }
}

/// A Pokémon a slot may take, with the roles it is listed for. Each screen's candidate type conforms.
public protocol SquadCandidate {
    var entryId: String { get }
    /// Role names (`RaidRole.rawValue`, ...). A candidate may have several or none.
    var roleNames: [String] { get }
}

public enum HubSquads {
    // MARK: rule 1: full strength

    /// Raids and Max use `HubRaidsModel.isBuilt` (the covering Max build is finished and the copy marked Dynamax), so the badge and the readiness bar agree
    /// (read-back note on rule 1); Gym, Rocket and PvP use `HubTeams.isBuilt`.
    public static func isFullStrength(_ b: BoxAdvice.Build, screen: SquadScreen, ctx: HubContext) -> Bool {
        guard b.steps != nil else { return false }   // one reading of an unknown build everywhere: never Full strength (see `isBuilt`)
        switch screen {
        case .raids: return HubRaidsModel.isBuilt(b, advice: ctx.advice, entries: ctx.entries, screen: .raids)
        case .max:
            // THIS copy must be marked Dynamax: another copy of the species being marked does not make this one ready (the readiness bar's rule is looser).
            return b.areas.contains("Max") && HubRaidsModel.isFinished(b) && ctx.entry(b.entryId)?.row.dynamax == true
        case .gym, .rocket, .pvp: return isBuilt(b)
        }
    }

    /// `HubTeams.isBuilt` for a build whose steps are known: a build read without `steps` is not known to be finished, so no list or slot badges it
    /// (`HubTeams.isBuilt` itself reads nil as built, for its other callers).
    public static func isBuilt(_ b: BoxAdvice.Build) -> Bool { b.steps != nil && HubTeams.isBuilt(b) }

    // MARK: rule 2: cost, value and currency

    public enum Currency: String, Equatable { case dust, candy, free }

    /// "19k" + dust, "100" + candy, nothing + free: `HubModel.costShort` split for the icon beside the arrow.
    public struct Cost: Equatable {
        public var value: String?
        public var currency: Currency
    }

    public static func cost(of b: BoxAdvice.Build) -> Cost { cost(dust: b.dust, candy: b.candy) }

    public static func cost(dust: Int, candy: Int) -> Cost {
        if dust > 0 { return Cost(value: HubModel.dustShort(dust), currency: .dust) }
        if candy > 0 { return Cost(value: "\(candy)", currency: .candy) }
        return Cost(value: nil, currency: .free)
    }

    /// The upgrade icon's accessibility label: "Upgrade available: power up to level 30". It names the work that remains (the build's steps), without the
    /// Dynamax-copy clause, which the Dynamax state shows. nil when nothing but the Dynamax requirement is left: that build is not upgrade work.
    public static func upgradeLabel(_ b: BoxAdvice.Build) -> String? {
        guard HubModel.needsSomething(b) else { return nil }
        var action = b.action.replacingOccurrences(of: " (Max needs a Dynamax copy)", with: "").replacingOccurrences(of: "; needs a Dynamax copy", with: "")
        action = action.replacingOccurrences(of: #"(to level [0-9.]+) \([^)]*\)"#, with: "$1", options: .regularExpression)
        // Mid-sentence the steps after the first start in lower case ("... + second move"); "Community Day move" keeps its capitals.
        let steps = action.components(separatedBy: " + ").enumerated().map { i, part -> String in
            i > 0 && !part.hasPrefix("Community") ? part.prefix(1).lowercased() + part.dropFirst() : part
        }
        action = steps.joined(separator: " + ")
        return "Upgrade available: " + action.prefix(1).lowercased() + action.dropFirst()
    }

    // MARK: rule 3: Available vs Best

    /// Available: a raid, Max, Gym or Rocket pick keeps the copy's own species (power up only: not a form change, not via a Mega). Best: any.
    public static func isUsable(_ b: BoxAdvice.Build, mode: SquadMode) -> Bool {
        mode == .best || (b.powerUp && !b.formChange && !b.viaMega)
    }

    /// A PvP pick under Available is the copy itself.
    public static func isUsable(_ option: BoxAdvice.LeagueRating.Option, mode: SquadMode) -> Bool { mode == .best || option.isSelf }

    /// The `placeable` test of a screen under a mode (see `fill`). Best places any pick. Available places a pick only when the copy has a build of the
    /// screen's area that is usable as it is (a raid Mega slot never; a PvP pick whose shown option is the copy itself).
    public static func placeable(screen: SquadScreen, mode: SquadMode, league: String? = nil, ctx: HubContext) -> (String, String) -> Bool {
        guard mode == .available else { return { _, _ in true } }
        func hasUsable(_ id: String, _ areas: [String]) -> Bool {
            ctx.advice.builds.contains { $0.entryId == id && $0.areas.contains { areas.contains($0) } && isUsable($0, mode: .available) }
        }
        switch screen {
        case .raids: return { id, role in role != PogoRules.RaidRole.mega.rawValue && hasUsable(id, ["Raids"]) }
        case .max: return { id, _ in hasUsable(id, ["Max"]) }
        case .gym: return { id, _ in hasUsable(id, ["Gym"]) }
        case .rocket: return { id, _ in hasUsable(id, ["Rocket", "Raids"]) }
        case .pvp: return { id, _ in league.flatMap { ctx.advice.leagues[id]?[$0] }?.shown.isSelf ?? false }
        }
    }

    // MARK: rules 4 and 5: slots, pickers, role changes

    /// The squad as shown. The player's picks are placed first (a copy sits in one slot at a time: the first slot holding it keeps it), then each empty
    /// slot in order takes the first unused entry of `pool(slotIndex, role)`; `fallback` entries are used only when `preferred` has no unused one.
    public struct Pool {
        public var preferred: [String]
        public var fallback: [String]
        public init(preferred: [String], fallback: [String] = []) { self.preferred = preferred; self.fallback = fallback }
    }

    /// `placeable(entryId, role)` says whether a saved pick may be placed now. Under Available a pick that is not usable as it is (any Mega, an evolution)
    /// is not placed and the slot shows the suggestion; the pick stays in the store and returns under Best (`placeable(screen:mode:league:ctx:)`).
    /// `copyOf` names the copy an id stands for (a species id the box has a copy of resolves to it): a copy sits in one slot at a time however many ids it goes by
    /// (Primal Kyogre and Kyogre are two rows of one copy), so taking an id takes its copy too.
    public static func fill(slots: [SquadSlot], pool: (Int, String) -> Pool, placeable: (String, String) -> Bool = { _, _ in true },
                            copyOf: (String) -> String? = { _ in nil }) -> [FilledSlot] {
        var used = Set<String>()
        var out = slots.map { FilledSlot(role: $0.role, entryId: nil, chosen: false, fallback: false) }
        func put(_ id: String, at i: Int) {
            if id.hasPrefix(squadSpeciesPrefix) { out[i].species = String(id.dropFirst(squadSpeciesPrefix.count)) } else { out[i].entryId = id }
        }
        func free(_ id: String) -> Bool { !used.contains(id) && !(copyOf(id).map(used.contains) ?? false) }
        func take(_ id: String) { used.insert(id); if let c = copyOf(id) { used.insert(c) } }
        for (i, s) in slots.enumerated() {
            if let p = s.pickId, placeable(p, s.role), free(p) { take(p); put(p, at: i); out[i].chosen = true }
        }
        for (i, s) in slots.enumerated() where out[i].pickId == nil {
            let p = pool(i, s.role)
            if let id = p.preferred.first(where: free) { take(id); put(id, at: i) }
            else if let id = p.fallback.first(where: free) { take(id); put(id, at: i); out[i].fallback = true }
        }
        return out
    }

    /// The candidates listed for a role, in their order; role "All" allows any.
    public static func pool<C: SquadCandidate>(role: String, in candidates: [C]) -> [String] {
        candidates.filter { role == squadRoleAll || $0.roleNames.contains(role) }.map(\.entryId)
    }

    /// Whether the Pokémon fits the role (rule 5: a pick that does not fit a new role is dropped).
    public static func fits<C: SquadCandidate>(_ entryId: String, role: String, in candidates: [C]) -> Bool {
        pool(role: role, in: candidates).contains(entryId)
    }

    /// The Pokémon the picker of `editing` must not offer: those in the squad's other slots (rule 4). On Rocket only Pokémon the player chose leave
    /// the list (D28), so `onlyChosen` is true there.
    /// `copyOf` adds the copy each of them stands for, so `picker` can hide a row that shows the same copy under another id.
    public static func excluded(by filled: [FilledSlot], editing: Int, onlyChosen: Bool, copyOf: (String) -> String? = { _ in nil }) -> Set<String> {
        var out = Set<String>()
        for (i, s) in filled.enumerated() where i != editing && (!onlyChosen || s.chosen) {
            for id in s.ids { out.insert(id); if let c = copyOf(id) { out.insert(c) } }
        }
        return out
    }

    public struct PickerRow: Equatable {
        public var entryId: String
        /// The edited slot's own Pokémon is listed, ticked.
        public var ticked: Bool
    }

    /// The picker's rows: `candidates` (best first) without the excluded ones; the edited slot's own Pokémon stays and is ticked.
    /// The same with every id the edited slot's Pokémon goes by (`FilledSlot.ids`): the row of its copy, or of its species, is ticked.
    /// A row is hidden when its id, or the copy it stands for (`copyOf`), is in `excluded`.
    public static func picker(candidates: [String], excluded: Set<String>, ownIds: Set<String>, copyOf: (String) -> String? = { _ in nil }) -> [PickerRow] {
        candidates.filter { ownIds.contains($0) || !(excluded.contains($0) || (copyOf($0).map(excluded.contains) ?? false)) }.map { PickerRow(entryId: $0, ticked: ownIds.contains($0)) }
    }

    public static func picker(candidates: [String], excluded: Set<String>, own: String?) -> [PickerRow] {
        candidates.filter { !excluded.contains($0) || $0 == own }.map { PickerRow(entryId: $0, ticked: $0 == own) }
    }

    /// Rule 5: relabel the slot; keep the player's pick when it fits the new role, else drop it so the slot refills with the best unused one.
    public static func changeRole(_ slots: inout [SquadSlot], at index: Int, to role: String, fits: (String) -> Bool) {
        guard slots.indices.contains(index) else { return }
        slots[index].role = role
        if let p = slots[index].pickId, !fits(p) { slots[index].pick = nil; slots[index].species = nil }
    }

    // MARK: rule 15: built rows on build lists

    public struct BuildRow: Equatable {
        public var build: BoxAdvice.Build
        public var built: Bool
        /// Shown beside the arrow when not built; a built row shows the Full strength badge in its place.
        public var cost: Cost
        /// The sub line: "Gym, Max · 10k dust"; a built row drops " · Free" ("Gym, Max").
        public var subLine: String
        public var showsFullStrength: Bool { built }
    }

    public static func buildRow(_ b: BoxAdvice.Build) -> BuildRow {
        // A build read without `steps` is not known to be finished (HubTeams.isBuilt reads it as built; a list must not badge it), so it keeps its cost.
        let built = isBuilt(b)
        return BuildRow(build: b, built: built, cost: built ? Cost(value: nil, currency: .free) : cost(of: b),
                        subLine: built ? HubModel.areaWords(b) : HubModel.areaLabel(for: b))
    }
}
