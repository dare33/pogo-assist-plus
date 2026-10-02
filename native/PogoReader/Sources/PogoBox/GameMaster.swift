import Foundation

/// The parts of the game master (`Resources/gamemaster.json`, PvPoke's) the app needs in Swift: which species
/// evolves from which (for the box merge) and the species names (for a hand correction). Everything else in
/// that file is read by the JavaScript, not here. Decoding skips the 1.6 MB of moves and stats it does not name.
public struct GameMaster {
    public struct Species: Equatable {
        public var id: String
        public var name: String
        public var dex: Int
        public var parent: String?
        public var evolutions: [String]
    }

    public enum Failure: Error, LocalizedError {
        case unreadable(String)
        public var errorDescription: String? { if case .unreadable(let m) = self { return "game data unreadable: \(m)" } else { return nil } }
    }

    public let byId: [String: Species]
    private let byLowerName: [String: String]

    public init(data: Data) throws {
        struct Family: Decodable { var parent: String?; var evolutions: [String]? }
        struct Entry: Decodable { var dex: Int; var speciesId: String; var speciesName: String; var family: Family? }
        struct File: Decodable { var pokemon: [Entry] }
        let file: File
        do { file = try JSONDecoder().decode(File.self, from: data) } catch { throw Failure.unreadable("\(error)") }
        var map = [String: Species](), names = [String: String]()
        for e in file.pokemon {
            map[e.speciesId] = Species(id: e.speciesId, name: e.speciesName, dex: e.dex, parent: e.family?.parent, evolutions: e.family?.evolutions ?? [])
            // First entry wins, so "Vulpix" is the plain species and not a later duplicate of the name.
            if names[e.speciesName.lowercased()] == nil { names[e.speciesName.lowercased()] = e.speciesId }
        }
        byId = map; byLowerName = names
    }

    /// The bundled game master. Loaded once per process (a static initialiser is thread-safe).
    public static func bundled() throws -> GameMaster { try loaded.get() }
    private static let loaded = Result<GameMaster, Error> {
        guard let url = Bundle.module.url(forResource: "gamemaster", withExtension: "json") else { throw Failure.unreadable("gamemaster.json is missing from the app") }
        return try GameMaster(data: Data(contentsOf: url))
    }

    /// True when `species` is a later stage of `ancestor`: `ancestor` is on its chain of parents. A species is not
    /// its own descendant. Unknown ids are nobody's descendant.
    public func isDescendant(_ species: String, of ancestor: String) -> Bool {
        var seen = Set<String>()
        var cur = byId[species]?.parent
        while let c = cur, seen.insert(c).inserted {
            if c == ancestor { return true }
            cur = byId[c]?.parent
        }
        // The family data lists children on the parent too; cover a parent link that is missing on the child.
        return reaches(ancestor, species, depth: 0)
    }

    private func reaches(_ from: String, _ target: String, depth: Int) -> Bool {
        guard depth < 6, let s = byId[from] else { return false }
        for e in s.evolutions { if e == target || reaches(e, target, depth: depth + 1) { return true } }
        return false
    }

    /// The species id for a name as the game master writes it ("Vulpix (Alolan)"), ignoring case. nil when unknown.
    public func speciesId(forName name: String) -> String? {
        byLowerName[name.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// Names that contain `text`, for a suggestion list; shortest first.
    public func names(matching text: String, limit: Int = 6) -> [String] {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return [] }
        return byLowerName.keys.filter { $0.contains(t) }.sorted { ($0.count, $0) < ($1.count, $1) }.prefix(limit).compactMap { byId[byLowerName[$0]!]?.name }
    }

    /// Name and form as the roster writes them: "Zamazenta (Hero)" is name "Zamazenta", form "Hero".
    public static func nameAndForm(_ speciesName: String) -> (name: String, form: String) {
        guard speciesName.hasSuffix(")"), let open = speciesName.lastIndex(of: "(") else { return (speciesName, "") }
        let name = speciesName[..<open].trimmingCharacters(in: .whitespaces)
        let form = speciesName[speciesName.index(after: open)..<speciesName.index(before: speciesName.endIndex)]
        return (name, String(form))
    }
}
