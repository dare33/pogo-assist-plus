import XCTest
@testable import PogoAssist
@testable import PogoBox

/// What VoiceOver says for a build mark is the cost the mark draws: the dust of all the builds with work left, in total (review of My Pokémon, round 1, M3).
final class BuildMarkWordsTests: XCTestCase {
    private func build(_ target: String, dust: Int, candy: Int = 0, entry: String = "e", steps: [BoxAdvice.Build.Step]) -> BoxAdvice.Build {
        BoxAdvice.Build(entryId: entry, title: "Eevee", cp: 300, level: 20, ivs: nil, targetId: target.lowercased(), targetName: target, powerUp: true, formChange: false,
                        viaMega: false, needsDynamax: false, spares: 0, areas: ["Raids"], tier: "B", targetLevel: nil, dust: dust, candy: candy, xl: 0, pvp: nil, score: 1, steps: steps)
    }
    private let work = [BoxAdvice.Build.Step(kind: "powerUp", toLevel: 30)]

    func testACopyWithTwoUnfinishedBuildsSpeaksTheTotalItsMarkShows() {
        let builds = [build("Umbreon", dust: 6_600, steps: work), build("Vaporeon", dust: 5_400, steps: work), build("Flareon", dust: 90_000, steps: [])]
        guard case .upgrade(let cost, let n) = MyPokemon.copyMark(builds: builds) else { return XCTFail("an upgrade mark") }
        XCTAssertEqual(n, 2)
        XCTAssertEqual(cost?.words, "12k dust", "the mark's cost: the unfinished builds' dust in total, not the built one's")
        let words = BuildMarkWords.copy(builds)
        XCTAssertTrue(words?.hasSuffix(", " + (cost?.words ?? "?")) == true, "spoken cost = drawn cost: \(words ?? "nil")")
        XCTAssertTrue(words?.hasPrefix("Upgrade available: power up Eevee") == true, words ?? "nil")
    }

    func testCandyWhenNoDustAndFullStrengthAndNone() {
        XCTAssertEqual(BuildMarkWords.copy([build("A", dust: 0, candy: 25, steps: work), build("B", dust: 0, candy: 100, steps: work)]), "Upgrade available: power up Eevee, 125 candy")
        XCTAssertEqual(BuildMarkWords.copy([build("A", dust: 5, steps: [])]), "Full strength")
        XCTAssertNil(BuildMarkWords.copy([]))
        // Two copies: each adds its one build. One copy with two builds adds only its top one (F3, 31 Oct 2026).
        XCTAssertEqual(BuildMarkWords.species(MyPokemon.speciesMark(builds: [build("A", dust: 5_000, steps: work), build("B", dust: 7_000, entry: "f", steps: work)])), "Upgrade available: 2 builds to do, 12k dust for each copy's top build")
        XCTAssertEqual(BuildMarkWords.species(MyPokemon.speciesMark(builds: [build("A", dust: 5_000, steps: work), build("B", dust: 7_000, steps: work)])), "Upgrade available: 2 builds to do, 5,000 dust for each copy's top build")
    }
}
