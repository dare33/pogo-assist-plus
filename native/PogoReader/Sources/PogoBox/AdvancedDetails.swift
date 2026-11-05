import Foundation

/// Design pass 3, rules 17 and 18: what the Pokémon page's advanced details offer. Option lists and defaults only; what the player chose is stored with
/// the copy (the data model's `details`). The export carries no moves, so nothing here comes from a scan.
public enum AdvancedDetails {
    public struct MoveOption: Equatable {
        public var id: String
        public var name: String
        /// Lowercase type of the move.
        public var type: String
        /// Only an Elite TM or an event gives it (the game master's `eliteMoves`).
        public var elite: Bool
    }

    private static func options(_ ids: [String], elite: Set<String>, gm: GameMaster) -> [MoveOption] {
        ids.map { id in MoveOption(id: id, name: gm.moves[id]?.name ?? id, type: gm.moves[id]?.type ?? "normal", elite: elite.contains(id)) }
    }

    /// Rule 17: only the fast moves in the species' `fastMoves`, in the game master's order, with their Elite flags.
    public static func fastMoves(of speciesId: String, gm: GameMaster) -> [MoveOption] {
        guard let s = gm.byId[speciesId] else { return [] }
        return options(s.fastMoves, elite: Set(s.eliteMoves), gm: gm)
    }

    /// Only the charged moves in `chargedMoves`.
    public static func chargedMoves(of speciesId: String, gm: GameMaster) -> [MoveOption] {
        guard let s = gm.byId[speciesId] else { return [] }
        return options(s.chargedMoves, elite: Set(s.eliteMoves), gm: gm)
    }

    /// The first charged move's choices: every charged move except the one chosen as the second.
    public static func firstChargedOptions(of speciesId: String, second: String?, gm: GameMaster) -> [MoveOption] {
        chargedMoves(of: speciesId, gm: gm).filter { $0.id != second }
    }

    /// The second charged move's choices (it starts "Not unlocked", which is `nil`): every charged move except the first, so the two are never equal.
    public static func secondChargedOptions(of speciesId: String, first: String?, gm: GameMaster) -> [MoveOption] {
        chargedMoves(of: speciesId, gm: gm).filter { $0.id != first }
    }

    /// Rule 18: the first fast move and the first non-Elite charged move (the first charged move when every one is Elite); the second charged move is
    /// not unlocked. Nil where the species has none.
    public struct Defaults: Equatable {
        public var fast: String?
        public var charged1: String?
        public var charged2: String?
    }

    public static func defaults(of speciesId: String, gm: GameMaster) -> Defaults {
        let charged = chargedMoves(of: speciesId, gm: gm)
        return Defaults(fast: fastMoves(of: speciesId, gm: gm).first?.id, charged1: (charged.first { !$0.elite } ?? charged.first)?.id, charged2: nil)
    }

    /// A stored choice made valid for the species: a move the species cannot learn becomes the default, and a second charged move equal to the first, or
    /// to nothing the species can learn, becomes "Not unlocked". Use it when a copy's species changes (an evolution) or the stored value is stale.
    public static func normalised(_ choice: Defaults, speciesId: String, gm: GameMaster) -> Defaults {
        let d = defaults(of: speciesId, gm: gm)
        let fast = Set(fastMoves(of: speciesId, gm: gm).map(\.id)), charged = Set(chargedMoves(of: speciesId, gm: gm).map(\.id))
        let f = choice.fast.flatMap { fast.contains($0) ? $0 : nil } ?? d.fast
        let c1 = choice.charged1.flatMap { charged.contains($0) ? $0 : nil } ?? d.charged1
        let c2 = choice.charged2.flatMap { charged.contains($0) && $0 != c1 ? $0 : nil }
        return Defaults(fast: f, charged1: c1, charged2: c2)
    }

    // MARK: Max moves

    /// Max Attack's name by the fast move's type: the game's names for the eighteen types. Taken from the design file; they are the Sword and Shield
    /// Max Move names and were not re-checked against the live game.
    public static let maxAttackNames: [String: String] = [
        "normal": "Max Strike", "fire": "Max Flare", "water": "Max Geyser", "grass": "Max Overgrowth", "electric": "Max Lightning", "ice": "Max Hailstorm",
        "fighting": "Max Knuckle", "poison": "Max Ooze", "ground": "Max Quake", "flying": "Max Airstream", "psychic": "Max Mindstorm", "bug": "Max Flutterby",
        "rock": "Max Rockfall", "ghost": "Max Phantasm", "dragon": "Max Wyrmwind", "dark": "Max Darkness", "steel": "Max Steelspike", "fairy": "Max Starfall",
    ]

    /// Max Attack's name follows the chosen fast move's type; with no fast move chosen, the species' first type; otherwise Normal's.
    public static func maxAttackName(fastMove: String?, speciesId: String, gm: GameMaster) -> String {
        let type = fastMove.flatMap { gm.moves[$0]?.type } ?? gm.byId[speciesId]?.types.first ?? "normal"
        return maxAttackNames[type] ?? "Max Strike"
    }

    /// Max Attack runs 1 to 3; Max Guard and Max Spirit run "–" (not unlocked, 0) and 1 to 3.
    public static let maxAttackLevels = [1, 2, 3], maxGuardLevels = [0, 1, 2, 3], maxSpiritLevels = [0, 1, 2, 3]

    /// Max moves show only while the Dynamax mark is on (`dynamax == true`; off and not set both hide them).
    public static func showsMaxMoves(dynamax: Bool?) -> Bool { dynamax == true }

    // MARK: Mega level

    /// The Mega forms of a species (`_mega`, `_mega_x`, `_mega_y`, `_primal`), by name, in id order; empty for a species without one.
    public static func megaForms(of speciesId: String, gm: GameMaster) -> [String] {
        gm.byId.keys.filter { $0 == speciesId + "_mega" || $0.hasPrefix(speciesId + "_mega_") || $0 == speciesId + "_primal" }.sorted().compactMap { gm.byId[$0]?.name }
    }

    /// The Mega level shows only for a species with a Mega form.
    public static func showsMegaLevel(speciesId: String, gm: GameMaster) -> Bool { !megaForms(of: speciesId, gm: gm).isEmpty }

    /// How far a copy's Mega form has levelled. The words are the design's; CONCEPTS word check 9 asks to check them against the game's own Mega Level names.
    public enum MegaLevel: Int, CaseIterable, Codable {
        case notYet = 0, base, high, max
        public var title: String { ["Not yet", "Base", "High", "Max"][rawValue] }
    }

    /// The player's own marks beside the moves.
    public static let marks = ["Lucky", "Purified", "Best Buddy", "Weather-boosted"]
}
