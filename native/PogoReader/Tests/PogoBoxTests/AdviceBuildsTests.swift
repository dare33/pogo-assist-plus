import XCTest
@testable import PogoBox

/// The Pokémon page's Advice panel lists `BoxAdvice.entries(for:).builds`: every build the copy carries, in the advisor's order
/// (best score first), and only that copy's.
final class AdviceBuildsTests: XCTestCase {
    private func build(_ entry: String, _ target: String, areas: [String], score: Double) -> BoxAdvice.Build {
        BoxAdvice.Build(entryId: entry, title: "Eevee", cp: 300, level: 20, ivs: nil, targetId: target, targetName: target.capitalized, powerUp: false,
                        formChange: false, viaMega: false, needsDynamax: false, spares: 0, areas: areas, tier: "B", targetLevel: nil, dust: 0, candy: 0, xl: 0,
                        pvp: nil, score: score, steps: [])
    }

    func testACopyListsEveryBuildItCarriesBestFirstAndNoOthers() {
        // The advisor hands them over sorted by score; entries(for:) must keep that order and drop other copies' builds.
        let advice = BoxAdvice(builds: [
            build("a", "vaporeon", areas: ["Max"], score: 0.69),
            build("b", "jolteon", areas: ["Raids"], score: 0.68),
            build("a", "glaceon", areas: ["Raids", "GL"], score: 0.66),
            build("a", "umbreon", areas: ["Gym"], score: 0.31),
        ])
        let mine = advice.entries(for: "a").builds
        XCTAssertEqual(mine.map(\.targetId), ["vaporeon", "glaceon", "umbreon"])
        XCTAssertEqual(mine.map(\.score), mine.map(\.score).sorted(by: >))
        XCTAssertEqual(mine[1].areas, ["Raids", "GL"], "each build keeps its own area chips")
        XCTAssertEqual(advice.entries(for: "b").builds.map(\.targetId), ["jolteon"])
        XCTAssertEqual(Set(mine.map(\.id)).count, mine.count, "one block per (copy, target)")
    }
}
