import Foundation

/// One species of the game master, reduced to what the reader needs.
public struct Species: Equatable {
    public var id: String
    public var name: String
    public var dex: Int
    public var baseStats: BaseStats
    public init(id: String, name: String, dex: Int, baseStats: BaseStats) { self.id = id; self.name = name; self.dex = dex; self.baseStats = baseStats }
}

/// The species table, loaded from `species.json` (written by native/tools/build-species.mjs from
/// data/gamemaster.json, shadow ids already skipped). Order is the game master's: the name matcher
/// breaks ties by order.
public struct SpeciesTable {
    public let species: [Species]
    public let byId: [String: Species]

    public init(species: [Species]) {
        self.species = species
        var m = [String: Species]()
        for s in species where m[s.id] == nil { m[s.id] = s }
        self.byId = m
    }

    private struct File: Decodable {
        var species: [Row]
    }
    private struct Row: Decodable {
        var s: Species
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            let id = try c.decode(String.self), name = try c.decode(String.self), dex = try c.decode(Int.self)
            let atk = try c.decode(Int.self), def = try c.decode(Int.self), hp = try c.decode(Int.self)
            s = Species(id: id, name: name, dex: dex, baseStats: BaseStats(atk: atk, def: def, hp: hp))
        }
    }

    public init(json: Data) throws {
        let f = try JSONDecoder().decode(File.self, from: json)
        self.init(species: f.species.map(\.s))
    }

    /// The table bundled with the package.
    public static func bundled() throws -> SpeciesTable {
        guard let url = Bundle.module.url(forResource: "species", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try SpeciesTable(json: Data(contentsOf: url))
    }

    /// Species for the ids a matched name could be.
    public func species(for ids: [String]) -> [Species] { ids.compactMap { byId[$0] } }
}
