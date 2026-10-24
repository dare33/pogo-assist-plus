import Foundation

/// The Pogo Hub's reference data (`Resources/hub.json`, built by `npm run build:hub` from `data/source/10-12`):
/// the raid, Max and event rotation, the Team GO Rocket lineups and grunt quotes, and the type chart. The Hub
/// derives its screens from this and the advice report; nothing here is read from the game.
public struct HubData: Codable, Equatable {
    public struct Boss: Codable, Equatable {
        public var name: String
        public var speciesId: String
        /// One or two lowercase type names, as the game master spells them.
        public var types: [String]
    }

    public enum Kind: String, Codable, Equatable {
        case fiveStar = "5star", mega, shadow, maxMonday = "maxmon", battleDay = "battleday", event, raidHour = "raidhour"
    }

    /// One dated row of the rotation. `from` and `to` are local calendar days, `yyyy-mm-dd`. `bosses` is empty
    /// for a row with no species (a Raid Hour, a Max Monday still "to be announced").
    public struct RotationRow: Codable, Equatable {
        public var from: String
        public var to: String
        public var kind: Kind
        public var title: String
        public var bosses: [Boss]
        public var note: String
        public var source: String
    }

    /// One card of the events strip. `tie` is the Hub screen it opens ("everything", "raids", "gym", "rocket",
    /// "pvp", "max") or empty.
    public struct Event: Codable, Equatable {
        public var from: String
        public var to: String
        public var title: String
        public var line: String
        public var tie: String
        public var source: String
    }

    /// A Rocket leader. `slots` holds three slots; each is the options the leader may bring in that slot.
    /// `since` is `yyyy-mm-dd`, or `yyyy-mm` when only the month is published.
    public struct Leader: Codable, Equatable {
        public var name: String
        public var since: String
        public var slots: [[Boss]]
        public var source: String
    }

    /// A grunt's opening quote and the type of its team; the Decoy grunt has an empty type.
    public struct Grunt: Codable, Equatable {
        public var type: String
        public var quote: String
    }

    public var generated: String
    public var rotation: [RotationRow]
    public var events: [Event]
    public var leaders: [Leader]
    public var grunts: [Grunt]
    /// `typeChart[attacking][defending]`: 1.6 super effective, 0.625 not very effective, 0.390625 immune-class.
    public var typeChart: [String: [String: Double]]

    /// The 18 types in the order the chart and the game list them. A dictionary has no order, so ties sort by this.
    public static let typeOrder = ["normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
                                   "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]

    public enum Failure: Error, LocalizedError {
        case unreadable(String)
        public var errorDescription: String? { if case .unreadable(let m) = self { return "hub data unreadable: \(m)" } else { return nil } }
    }

    /// The bundled hub data. Loaded once per process (a static initialiser is thread-safe).
    public static func bundled() throws -> HubData { try loaded.get() }
    private static let loaded = Result<HubData, Error> {
        guard let url = Bundle.module.url(forResource: "hub", withExtension: "json") else { throw Failure.unreadable("hub.json is missing from the app") }
        do { return try JSONDecoder().decode(HubData.self, from: Data(contentsOf: url)) } catch { throw Failure.unreadable("\(error)") }
    }

    /// How much damage an attack of type `attacking` does to a Pokémon with `types`: the product over its types.
    /// An unknown type counts as neutral (1).
    public func effectiveness(_ attacking: String, against types: [String]) -> Double {
        types.reduce(1.0) { $0 * (typeChart[attacking]?[$1] ?? 1) }
    }

    /// The types that hit a Pokémon with `types` for more than normal damage, strongest first, ties in the chart's
    /// type order. A double weakness is one entry at 2.56.
    public func weaknesses(of types: [String]) -> [(type: String, multiplier: Double)] {
        Self.typeOrder.enumerated().compactMap { i, t -> (Int, String, Double)? in
            let m = effectiveness(t, against: types)
            return m > 1.0001 ? (i, t, m) : nil
        }
        .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
        .map { (type: $0.1, multiplier: $0.2) }
    }
}
