import Foundation

/// The bundled tier tables (`Resources/tiers.json`, built by `npm run build:tiers` from `data/source`): which Pokémon the tables list for
/// each area, under which section and tier, with the Max table's role. The Hub reads it to say which attacking type a Pokémon counts for
/// (the Raids table is sectioned by attacking type, which is not always the species' own type: Kartana is a Grass/Steel Pokémon listed
/// under Fighting too) and what role a Max battler has. The advisor itself reads the same file in the JavaScript engine.
public struct TierTable {
    public struct Entry: Decodable, Equatable {
        public struct Flags: Decodable, Equatable { public var shadow: Bool; public var mega: Bool; public var max: Bool }
        /// `raids`, `gym`, `rocket`, `gl`, `ul`, `ml` or `max`.
        public var area: String
        /// `pve-by-type` (Raids), `defence` (Gym), `attacker` (Rocket), `pvp` or `max`.
        public var kind: String
        /// The Raids table's attacking type ("Fighting"), or the section heading of the other tables ("Tanks and healers").
        public var section: String
        /// S, A or B.
        public var tier: String
        public var rank: Double?
        public var name: String
        public var speciesId: String
        public var flags: Flags
        /// The Max table's role ("Tank and healer"); nil elsewhere and for Max attackers.
        public var role: String?
    }

    public let entries: [Entry]
    private let bySpecies: [String: [Entry]]

    init(entries: [Entry]) {   // internal so a test can build a table by hand
        self.entries = entries
        bySpecies = Dictionary(grouping: entries, by: \.speciesId)
    }

    /// The entries of one area for one species id, in table order.
    public func entries(for speciesId: String, area: String) -> [Entry] { (bySpecies[speciesId] ?? []).filter { $0.area == area } }

    public enum Failure: Error, LocalizedError {
        case unreadable(String)
        public var errorDescription: String? { if case .unreadable(let m) = self { return "tier tables unreadable: \(m)" } else { return nil } }
    }

    /// The bundled tables. Loaded once per process (a static initialiser is thread-safe).
    public static func bundled() throws -> TierTable { try loaded.get() }
    private static let loaded = Result<TierTable, Error> {
        struct File: Decodable { var entries: [Entry] }
        guard let url = Bundle.module.url(forResource: "tiers", withExtension: "json") else { throw Failure.unreadable("tiers.json is missing from the app") }
        do { return TierTable(entries: try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).entries) } catch { throw Failure.unreadable("\(error)") }
    }
}
