import XCTest
@testable import PogoBox

/// The My Pokémon tab's rules (design pass 3, `CONCEPTS.md` rules 2 to 5 and 9): grades, the species build mark, TOP PVP and TOP IVS.
final class MyPokemonTests: XCTestCase {
    typealias R = BoxAdvice.LeagueRating
    typealias O = R.Option

    // MARK: builders

    private func build(_ entry: String, _ target: String = "Umbreon", dust: Int = 0, candy: Int = 0, steps: [BoxAdvice.Build.Step]? = []) -> BoxAdvice.Build {
        BoxAdvice.Build(entryId: entry, title: "Eevee", cp: 300, level: 20, ivs: nil, targetId: target.lowercased(), targetName: target, powerUp: false, formChange: false,
                        viaMega: false, needsDynamax: false, spares: 0, areas: ["Raids"], tier: "B", targetLevel: nil, dust: dust, candy: candy, xl: 0, pvp: nil, score: 1, steps: steps)
    }
    private let todo = [BoxAdvice.Build.Step(kind: "powerUp", toLevel: 30)]

    private func option(_ name: String, score: Double?, ivRank: Int?, over: Bool = false) -> O {
        O(speciesId: name.lowercased(), name: name, strength: score.map { .init(score: $0, rank: 100, of: 1152) },
          iv: ivRank.map { .init(rank: $0, pct: 95, rankPct: 90, level: 20, cp: 1490) }, overCap: over)
    }
    /// A league whose only member is the pick.
    private func league(_ name: String, score: Double?, ivRank: Int?, over: Bool = false) -> R { R(options: [option(name, score: score, ivRank: ivRank, over: over)]) }

    // MARK: number grades (rule 9, rule 3)

    func testScoreGradeBands() {
        XCTAssertEqual(MyPokemon.scoreGrade(92), .top); XCTAssertEqual(MyPokemon.scoreGrade(97.4), .top)
        XCTAssertEqual(MyPokemon.scoreGrade(91.99), .good); XCTAssertEqual(MyPokemon.scoreGrade(90), .good)
        XCTAssertEqual(MyPokemon.scoreGrade(89.99), .plain); XCTAssertEqual(MyPokemon.scoreGrade(80), .plain)
        XCTAssertEqual(MyPokemon.scoreGrade(nil), .plain)
    }

    func testRankGradeBands() {
        XCTAssertEqual(MyPokemon.rankGrade(1), .top); XCTAssertEqual(MyPokemon.rankGrade(100), .top)
        XCTAssertEqual(MyPokemon.rankGrade(101), .good); XCTAssertEqual(MyPokemon.rankGrade(500), .good)
        XCTAssertEqual(MyPokemon.rankGrade(501), .plain); XCTAssertEqual(MyPokemon.rankGrade(4096), .plain)
        XCTAssertEqual(MyPokemon.rankGrade(nil), .plain); XCTAssertEqual(MyPokemon.rankGrade(0), .plain, "rank 0 is not a rank")
    }

    func testIVGradeIsTopAt45AndGoodAt42() {
        XCTAssertEqual(MyPokemon.ivGrade(sum: 45), .top)
        XCTAssertEqual(MyPokemon.ivGrade(sum: 44), .good); XCTAssertEqual(MyPokemon.ivGrade(sum: 42), .good)
        XCTAssertEqual(MyPokemon.ivGrade(sum: 41), .plain, "41 of 45 is 91%")
        XCTAssertEqual(MyPokemon.ivGrade(sum: 0), .plain); XCTAssertEqual(MyPokemon.ivGrade(sum: nil), .plain)
    }

    // MARK: the species build mark (rule 2)

    func testNoBuildHasNoMark() {
        XCTAssertEqual(MyPokemon.speciesMark(builds: []), .none)
    }

    func testAllBuiltIsFullStrength() {
        // Built = no steps, or only the Dynamax requirement; a report read without steps counts as built.
        let builds = [build("a", steps: []), build("b", steps: [.init(kind: "needsDynamaxCopy")]), build("c", steps: nil)]
        XCTAssertEqual(MyPokemon.speciesMark(builds: builds), .fullStrength)
    }

    func testWorkLeftIsUpgradeWithTheDustOfThoseBuildsInTotal() {
        // The built build's dust is not counted: only the builds with work left.
        let builds = [build("a", dust: 6_600, candy: 25, steps: todo), build("b", dust: 5_400, steps: todo), build("c", dust: 99_000, steps: [])]
        XCTAssertEqual(MyPokemon.speciesMark(builds: builds), .upgrade(cost: .init(value: "12k", currency: .dust), builds: 2))
        XCTAssertEqual(MyPokemon.Cost(value: "12k", currency: .dust).words, "12k dust")
    }

    func testDustIsFormattedLikeTheHubsCost() {
        // The words are HubModel.costShort's, split into value and currency.
        let b = build("a", dust: 489_000, steps: todo)
        XCTAssertEqual(MyPokemon.speciesMark(builds: [b]), .upgrade(cost: .init(value: "489k", currency: .dust), builds: 1))
        XCTAssertEqual(MyPokemon.Cost(value: "489k", currency: .dust).words, HubModel.costShort(b))
        let small = build("a", dust: 6_600, steps: todo)
        XCTAssertEqual(MyPokemon.Cost(value: "6,600", currency: .dust).words, HubModel.costShort(small))
        XCTAssertEqual(MyPokemon.speciesMark(builds: [small]), .upgrade(cost: .init(value: "6,600", currency: .dust), builds: 1))
    }

    func testNoDustFallsBackToTheCandyTotal() {
        let builds = [build("a", candy: 25, steps: todo), build("b", candy: 100, steps: todo)]
        XCTAssertEqual(MyPokemon.speciesMark(builds: builds), .upgrade(cost: .init(value: "125", currency: .candy), builds: 2))
        XCTAssertEqual(MyPokemon.Cost(value: "125", currency: .candy).words, HubModel.costShort(build("a", candy: 125)))
    }

    func testWorkLeftWithNoDustOrCandyIsUpgradeWithoutACost() {
        XCTAssertEqual(MyPokemon.speciesMark(builds: [build("a", steps: [.init(kind: "secondMove")])]), .upgrade(cost: nil, builds: 1))
    }

    func testOneUnbuiltBuildAmongBuiltOnesIsStillUpgrade() {
        let builds = [build("a", steps: []), build("b", dust: 3_000, steps: todo)]
        XCTAssertEqual(MyPokemon.speciesMark(builds: builds), .upgrade(cost: .init(value: "3,000", currency: .dust), builds: 1))
        XCTAssertEqual(MyPokemon.copyMark(builds: [builds[0]]), .fullStrength)
    }

    func testSpeciesCostCountsOneBuildPerCopy() {
        // Copy "a" has a raid build (tier S, 10k) and a PvP build (tier B, 5k): only the top one counts. Copy "b" has one build (3k).
        func tiered(_ entry: String, tier: String, dust: Int, score: Double) -> BoxAdvice.Build {
            var b = build(entry, dust: dust, steps: todo); b.tier = tier; b.score = score; return b
        }
        let builds = [tiered("a", tier: "B", dust: 5_000, score: 9), tiered("a", tier: "S", dust: 10_000, score: 5), tiered("b", tier: "A", dust: 3_000, score: 1)]
        XCTAssertEqual(MyPokemon.speciesMark(builds: builds), .upgrade(cost: .init(value: "13k", currency: .dust), builds: 3))
        // The copy's own mark still lists all of its builds.
        XCTAssertEqual(MyPokemon.copyMark(builds: Array(builds[0..<2])), .upgrade(cost: .init(value: "15k", currency: .dust), builds: 2))
        // Same tier: the higher score is the top build; a built build is never the top.
        let same = [tiered("a", tier: "A", dust: 4_000, score: 2), tiered("a", tier: "A", dust: 6_000, score: 8)]
        XCTAssertEqual(MyPokemon.speciesMark(builds: same), .upgrade(cost: .init(value: "6,000", currency: .dust), builds: 2))
        var built = tiered("a", tier: "S", dust: 99_000, score: 99); built.steps = []
        XCTAssertEqual(MyPokemon.speciesMark(builds: [built, tiered("a", tier: "B", dust: 2_000, score: 1)]), .upgrade(cost: .init(value: "2,000", currency: .dust), builds: 1))
    }

    // MARK: TOP PVP (rule 4)

    func testStandingTakesTheBetterScoreOfGreatAndUltra() {
        let s = MyPokemon.pvpStanding(ratings: ["gl": league("Umbreon", score: 90.2, ivRank: 99), "ul": league("Vaporeon", score: 93.1, ivRank: 400)], pogoAssist: false)
        XCTAssertEqual(s, .init(league: "ul", pick: "Vaporeon", score: 93.1, ivRank: 400))
        XCTAssertEqual(s?.scoreGrade, .top); XCTAssertEqual(s?.rankGrade, .good)
    }

    func testStandingTieOnScoreGoesToTheBetterIVRankThenGreatLeague() {
        let a = MyPokemon.pvpStanding(ratings: ["gl": league("Umbreon", score: 90, ivRank: 300), "ul": league("Umbreon", score: 90, ivRank: 20)], pogoAssist: false)
        XCTAssertEqual(a?.league, "ul")
        let b = MyPokemon.pvpStanding(ratings: ["gl": league("Umbreon", score: 90, ivRank: 20), "ul": league("Umbreon", score: 90, ivRank: 20)], pogoAssist: false)
        XCTAssertEqual(b?.league, "gl")
    }

    func testMasterLeagueIsLeftOut() {
        XCTAssertNil(MyPokemon.pvpStanding(ratings: ["ml": league("Lugia", score: 99, ivRank: 1)], pogoAssist: false))
        let s = MyPokemon.pvpStanding(ratings: ["gl": league("Umbreon", score: 70, ivRank: 900), "ml": league("Lugia", score: 99, ivRank: 1)], pogoAssist: false)
        XCTAssertEqual(s?.league, "gl")
    }

    func testAnOverCapCardDoesNotCount() {
        // Only member, over the cap: no card fits.
        XCTAssertNil(MyPokemon.pvpStanding(ratings: ["gl": league("Umbreon", score: 95, ivRank: 1, over: true)], pogoAssist: false))
        // The shown pick is over the cap, so the card is the best-ranked member that fits (the league panel's headline).
        let r = R(options: [option("Vaporeon", score: 95, ivRank: 5, over: true), option("Eevee", score: 60, ivRank: 7)], pick: 0)
        let s = MyPokemon.pvpStanding(ratings: ["gl": r], pogoAssist: false)
        XCTAssertEqual(s, .init(league: "gl", pick: "Eevee", score: 60, ivRank: 7))
        // An over-cap Great League card does not stop the Ultra League one counting.
        let both = MyPokemon.pvpStanding(ratings: ["gl": league("Umbreon", score: 95, ivRank: 1, over: true), "ul": league("Umbreon", score: 88, ivRank: 30)], pogoAssist: false)
        XCTAssertEqual(both?.league, "ul")
    }

    func testAnUnrankedPickOrUnreadIVsGiveNoStanding() {
        XCTAssertNil(MyPokemon.pvpStanding(ratings: ["gl": league("Umbreon", score: nil, ivRank: 10)], pogoAssist: false), "PvPoke does not rank the pick")
        XCTAssertNil(MyPokemon.pvpStanding(ratings: ["gl": league("Umbreon", score: 91, ivRank: nil)], pogoAssist: false), "IVs not read: no IV rank")
        XCTAssertNil(MyPokemon.pvpStanding(ratings: [:], pogoAssist: false), "no league card")
    }

    func testTheStandingFollowsTheRanking() {
        let r = R(options: [option("Vaporeon", score: 92, ivRank: 400), option("Umbreon", score: 90, ivRank: 20)], pick: 0, experimental: 1)
        XCTAssertEqual(MyPokemon.pvpStanding(ratings: ["gl": r], pogoAssist: false)?.pick, "Vaporeon")
        XCTAssertEqual(MyPokemon.pvpStanding(ratings: ["gl": r], pogoAssist: true)?.pick, "Umbreon")
    }

    func testTopPvPTakesTheTwoBestCopiesByScoreThenIVRank() {
        let copies: [(id: String, ratings: [String: R])] = [
            ("a", ["gl": league("Umbreon", score: 90.2, ivRank: 99)]),
            ("b", ["gl": league("Umbreon", score: 90.2, ivRank: 351)]),
            ("c", ["ul": league("Vaporeon", score: 93, ivRank: 800)]),
            ("d", ["gl": league("Umbreon", score: 90.2, ivRank: 12)]),
            ("e", [:]),
        ]
        let top = MyPokemon.topPvP(copies: copies, pogoAssist: false)
        XCTAssertEqual(top.map(\.copyId), ["c", "d"], "the higher score first, then the tie by IV rank")
        XCTAssertEqual(top[0].standing.league, "ul")
        XCTAssertEqual(MyPokemon.topPvP(copies: copies, pogoAssist: false, limit: 3).map(\.copyId), ["c", "d", "a"])
    }

    func testEqualStandingsKeepTheListsOrder() {
        let copies: [(id: String, ratings: [String: R])] = [("x", ["gl": league("Umbreon", score: 90, ivRank: 50)]), ("y", ["gl": league("Umbreon", score: 90, ivRank: 50)]),
                                                            ("z", ["gl": league("Umbreon", score: 90, ivRank: 50)])]
        XCTAssertEqual(MyPokemon.topPvP(copies: copies, pogoAssist: false).map(\.copyId), ["x", "y"])
    }

    func testASpeciesWithOneCopyOrNoLeagueCard() {
        XCTAssertEqual(MyPokemon.topPvP(copies: [("only", ["gl": league("Umbreon", score: 90, ivRank: 5)])], pogoAssist: false).map(\.copyId), ["only"])
        XCTAssertEqual(MyPokemon.topPvP(copies: [("only", [:])], pogoAssist: false), [])
        XCTAssertEqual(MyPokemon.topPvP(copies: [], pogoAssist: false), [])
    }

    // MARK: TOP IVS (rule 5)

    func testTopIVsTakeTheNextTwoInListOrderNotAlreadyInTopPvP() {
        let listed = [("a", 45), ("b", 44), ("c", 43), ("d", 42), ("e", 10)].map { MyPokemon.ListedCopy(id: $0.0, ivSum: $0.1) }
        XCTAssertEqual(MyPokemon.topIVs(listed: listed, excluding: []), ["a", "b"])
        XCTAssertEqual(MyPokemon.topIVs(listed: listed, excluding: ["a", "c"]), ["b", "d"], "skips the copies already shown")
        XCTAssertEqual(MyPokemon.topIVs(listed: listed, excluding: ["a", "b", "c", "d"]), ["e"], "fewer than two left: what exists")
        XCTAssertEqual(MyPokemon.topIVs(listed: listed, excluding: Set(listed.map(\.id))), [])
    }

    func testTopIVsSkipCopiesWhoseIVsAreNotRead() {
        let listed = [MyPokemon.ListedCopy(id: "a", ivSum: 30), MyPokemon.ListedCopy(id: "b", ivSum: nil), MyPokemon.ListedCopy(id: "c", ivSum: nil)]
        XCTAssertEqual(MyPokemon.topIVs(listed: listed, excluding: []), ["a"])
        XCTAssertEqual(MyPokemon.topIVs(listed: [MyPokemon.ListedCopy(id: "only", ivSum: 12)], excluding: []), ["only"], "a species with one copy")
        XCTAssertEqual(MyPokemon.topIVs(listed: [], excluding: []), [])
    }

    func testTopIVsLimit() {
        let listed = (1...5).map { MyPokemon.ListedCopy(id: "c\($0)", ivSum: 50 - $0) }
        XCTAssertEqual(MyPokemon.topIVs(listed: listed, excluding: [], limit: 3), ["c1", "c2", "c3"])
    }

    // MARK: the keep or transfer tag

    private func entry(_ d: BoxAdvice.Duplicate?, id: String, builds: [BoxAdvice.Build] = []) -> BoxAdvice.ForEntry {
        BoxAdvice.ForEntry(builds: builds, spareFor: [], duplicateOf: d, keep: d?.keepIds.contains(id) ?? false, keepIndex: d?.keepIds.firstIndex(of: id))
    }

    func testKeepAndTransferTagsAreTheAdviceWordsShortened() {
        let one = BoxAdvice.Duplicate(name: "Eevee", count: 65, keep: ["CP 1960, 13/15/14"], transfer: ["CP 2500, 10/10/10"], keepIds: ["me"], transferIds: ["you"])
        XCTAssertEqual(MyPokemon.keepTag(entry(one, id: "me"))?.text, "Keep · best IVs of 65")
        XCTAssertEqual(MyPokemon.keepTag(entry(one, id: "you"))?.text, "Transfer · one of 65")
        XCTAssertEqual(MyPokemon.keepTag(entry(one, id: "you"))?.keep, false)
        let two = BoxAdvice.Duplicate(name: "Eevee", count: 6, keep: ["CP 1, 15/15/15", "CP 2, 14/15/15"], transfer: ["CP 3, 1/1/1"], keepIds: ["a", "b"], transferIds: ["t"])
        XCTAssertEqual(MyPokemon.keepTag(entry(two, id: "a"))?.text, "Keep · two best IV sets of 6")
        var dyn = BoxAdvice.Duplicate(name: "Eevee", count: 2, keep: ["CP 200, 15/15/15", "CP 100, 0/0/0"], transfer: ["CP 3, 1/1/1"], keepIds: ["best", "yes"], transferIds: ["t"])
        dyn.dynamaxExtras = 1
        XCTAssertEqual(MyPokemon.keepTag(entry(dyn, id: "yes"))?.text, "Keep · marked as caught as a Dynamax")
    }

    func testACopyWithABuildStillCarriesItsTag() {
        // CONCEPTS rule 5 / D1: a TOP IVS row keeps its keep or transfer tag, and a copy with a build also shows its upgrade mark.
        let d = BoxAdvice.Duplicate(name: "Eevee", count: 3, keep: ["CP 1, 15/15/15"], transfer: ["CP 3, 1/1/1"], keepIds: ["me"], transferIds: ["you"])
        XCTAssertEqual(MyPokemon.keepTag(entry(d, id: "me", builds: [build("me")]))?.text, "Keep · best IVs of 3")
        XCTAssertEqual(MyPokemon.keepTag(entry(d, id: "you", builds: [build("you")]))?.text, "Transfer · one of 3")
    }

    func testNoTagForACopyThatIsNotOneOfSeveral() {
        XCTAssertNil(MyPokemon.keepTag(entry(nil, id: "solo")))
        XCTAssertNil(MyPokemon.keepTag(entry(nil, id: "solo", builds: [build("solo")])))
    }
}
