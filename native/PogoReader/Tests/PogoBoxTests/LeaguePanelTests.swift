import XCTest
@testable import PogoBox

/// The derivations behind the Pokémon page's Leagues panel: which card state, best available, past best level, short dust.
final class LeaguePanelTests: XCTestCase {
    typealias R = BoxAdvice.LeagueRating
    typealias O = R.Option

    private func option(_ id: String, score: Double? = nil, rank: Int = 100, iv: R.IV? = nil, over: Bool = false, cost: R.Cost? = nil,
                        isSelf: Bool = false, moves: R.Moves? = nil, needs: [String]? = nil, locked: String? = nil) -> O {
        O(speciesId: id, name: id.capitalized, isSelf: isSelf, genderLocked: locked, strength: score.map { .init(score: $0, rank: rank, of: 1152) }, moves: moves,
          needs: needs, iv: iv, overCap: over, cost: cost)
    }
    private let iv = R.IV(rank: 216, pct: 97.24, rankPct: 97, level: 18.5, cp: 1500)
    private let cost = R.Cost(dust: 6600, candy: 25, xl: 0, evolveCandy: 6, toLevel: 18.5)

    func testShownIndexFollowsTheRanking() {
        let r = R(options: [option("a"), option("b")], pick: 1, experimental: 0)
        XCTAssertEqual(LeaguePanel.shownIndex(r, pogoAssist: false), 1)
        XCTAssertEqual(LeaguePanel.shownIndex(r, pogoAssist: true), 0)
        XCTAssertEqual(LeaguePanel.chipText(pogoAssist: false), "Pick")
        XCTAssertEqual(LeaguePanel.chipText(pogoAssist: true), "Pogo Assist pick")
    }

    func testFittingCardFigures() {
        let moves = R.Moves(fast: "Ember", charged: ["Overheat", "Flamethrower"])
        let r = R(options: [option("flareon", score: 68.9, rank: 710, iv: iv, cost: cost, isSelf: false, moves: moves)])
        let c = LeaguePanel.card(r, shown: 0, key: "gl", level: 17)
        XCTAssertEqual(c.status, .fits)
        XCTAssertEqual(c.scoreText, "68.9"); XCTAssertEqual(c.rankText, "#710 of 1,152"); XCTAssertFalse(c.scoreStrong)
        XCTAssertEqual(c.ivText, "97.2%"); XCTAssertEqual(c.ivRankText, "IV #216"); XCTAssertTrue(c.ivStrong)
        XCTAssertEqual(c.costItems.map { $0.label + $0.value }, ["Target level: 18.5", "Target CP: 1,500", "6,600 dust", "31 candy"])
        XCTAssertNil(c.costNote); XCTAssertNil(c.bestAvailableNote)
        XCTAssertEqual(c.ivPct, 97.24)
        XCTAssertEqual(c.moves.map(\.text), ["Ember", "Overheat", "Flamethrower"])
        XCTAssertEqual(LeaguePanel.spoken(c, key: "gl", chip: "Pick"),
                       "Great League, under 1,500 CP. Pick: Flareon. Weak for Great League. Species 68.9, rank 710 of 1,152. This copy 97.2 percent, IV rank 216. Target level 18.5, target CP 1,500, 6,600 dust, 31 candy. Moves Ember, Overheat, Flamethrower.")
    }

    func testXLIsAppendedToTheCandyAndMissingMovesAreChips() {
        let xlCost = R.Cost(dust: 488_800, candy: 25, xl: 296, evolveCandy: 0, toLevel: 50)
        let moves = R.Moves(fast: "Dragon Tail", charged: ["Aeroblast", "Sky Attack"])
        let r = R(options: [option("lugia", score: 88.6, iv: iv, cost: xlCost, isSelf: true, moves: moves, needs: ["Aeroblast"])])
        let c = LeaguePanel.card(r, shown: 0, key: "ml", level: 25)
        XCTAssertEqual(c.costItems.last?.value, "25 candy, 296 XL")
        XCTAssertEqual(c.moves, [.init(text: "Dragon Tail", missing: false), .init(text: "Needs Aeroblast", missing: true), .init(text: "Sky Attack", missing: false)])
        // Evolving re-rolls moves: a member that is not the Pokémon itself never shows "Needs".
        var other = r.options[0]; other.isSelf = false
        XCTAssertEqual(LeaguePanel.moveChips(other).filter(\.missing).count, 0)
    }

    func testBestAvailableHeadlinesTheMemberThatFitsAndNamesTheStrongerOne() {
        let r = R(options: [option("corviknight", score: 86.3, rank: 88, iv: iv, over: true),
                            option("corvisquire", iv: iv, cost: .init(dust: 0, candy: 0, xl: 0, evolveCandy: 50, toLevel: 35), isSelf: false)], pick: 1, experimental: 1)
        let c = LeaguePanel.card(r, shown: 1, key: "gl", level: 35)
        XCTAssertEqual(c.option.speciesId, "corvisquire")
        XCTAssertEqual(c.bestAvailableNote, "Corviknight is the stronger species, but this copy is already over 1,500 CP as Corviknight.")
        XCTAssertEqual(c.overCapCount, 1)
        XCTAssertEqual(c.scoreText, "—"); XCTAssertEqual(c.rankText, "")
        XCTAssertEqual(c.costNote, "Already at level 35; 50 candy")
        XCTAssertTrue(c.costItems.isEmpty)
        // A shown pick that is itself over the cap gives way to the first member that fits.
        let shownOver = LeaguePanel.card(r, shown: 0, key: "gl", level: 35)
        XCTAssertEqual(shownOver.option.speciesId, "corvisquire")
        XCTAssertEqual(shownOver.strongerOverCap?.speciesId, "corviknight")
    }

    func testNoNoteWhenNothingStrongerIsOverTheCap() {
        // The shown member is the strongest: nothing to name.
        let top = R(options: [option("a", score: 90, iv: iv, cost: cost), option("b", score: 80, over: true)])
        XCTAssertNil(LeaguePanel.card(top, shown: 0, key: "gl", level: 17).bestAvailableNote)
        // A weaker member is over the cap but the shown one outscores it: still nothing stronger.
        let weakerOver = R(options: [option("a", score: 90, iv: iv, cost: cost), option("b", score: 60, over: true)])
        XCTAssertNil(LeaguePanel.card(weakerOver, shown: 0, key: "gl", level: 17).bestAvailableNote)
        // Unranked members over the cap listed AFTER the shown one are earlier evolutions, never the stronger species.
        let earlier = R(options: [option("final", iv: iv, cost: cost), option("middle", over: true)])
        XCTAssertNil(LeaguePanel.card(earlier, shown: 0, key: "gl", level: 17).bestAvailableNote)
        // Nothing over the cap at all.
        XCTAssertNil(LeaguePanel.card(R(options: [option("a", score: 90, iv: iv, cost: cost), option("b", score: 80, iv: iv, cost: cost)]), shown: 0, key: "gl", level: 17).bestAvailableNote)
    }

    func testGenderLockedStrongerSpeciesIsNamedWithItsCondition() {
        // Unknown-sex Kirlia: Gallade (male only) is the stronger species and is over the cap; Kirlia is shown.
        let r = R(options: [option("gallade", score: 85, over: true, locked: "male"), option("kirlia", score: 60, iv: iv, cost: cost, isSelf: true)], pick: 1, experimental: 1)
        let c = LeaguePanel.card(r, shown: 1, key: "gl", level: 35)
        XCTAssertEqual(c.bestAvailableNote, "Gallade (if it is male) is the stronger species, but this copy is already over 1,500 CP as Gallade.")
        let female = R(options: [option("froslass", score: 85, over: true, locked: "female"), option("snorunt", score: 60, iv: iv, cost: cost, isSelf: true)], pick: 1, experimental: 1)
        XCTAssertEqual(LeaguePanel.card(female, shown: 1, key: "ul", level: 35).bestAvailableNote, "Froslass (if it is female) is the stronger species, but this copy is already over 2,500 CP as Froslass.")
    }

    /// Constructed data for the second branch only: the shown member is unranked and the unranked final evolution is over the cap. (In real
    /// data PvPoke ranks Corviknight, so a real Rookidee takes the first branch, a ranked stronger member.)
    func testUnrankedOverCapFinalEvolutionIsNamedWhenTheShownMemberIsUnranked() {
        // Corviknight (the final evolution) is over the cap and unranked here ("fallback"); Corvisquire is shown.
        let r = R(options: [option("corviknight", over: true), option("corvisquire", iv: iv, cost: cost), option("rookidee", over: true)], pick: 1, experimental: 1, source: "fallback")
        let c = LeaguePanel.card(r, shown: 1, key: "gl", level: 35)
        XCTAssertEqual(c.bestAvailableNote, "Corviknight is the stronger species, but this copy is already over 1,500 CP as Corviknight.")
        XCTAssertEqual(c.strongerOverCap?.speciesId, "corviknight")
        XCTAssertEqual(c.overCapCount, 2)
    }

    func testNoViableOption() {
        let moves = R.Moves(fast: "Dragon Tail", charged: ["Aeroblast"])
        let one = R(options: [option("lugia", score: 88, over: true, isSelf: true, moves: moves)])
        let c = LeaguePanel.card(one, shown: 0, key: "gl", level: 25)
        XCTAssertEqual(c.status, .noViable)
        XCTAssertEqual(c.blockedText, "This copy is already above 1,500 CP as Lugia.")
        XCTAssertEqual(c.overCapCount, 1); XCTAssertNil(c.ivPct)
        XCTAssertEqual(c.moves.map(\.text), ["Dragon Tail", "Aeroblast"], "moves still shown")
        let many = R(options: [option("a", over: true), option("b", over: true)])
        XCTAssertEqual(LeaguePanel.card(many, shown: 0, key: "ul", level: 40).blockedText, "This copy is already above 2,500 CP as every member of the family.")
    }

    func testIVsNotReadAndLevelNotKnown() {
        let blind = R(options: [option("eevee", score: 70, isSelf: true)])
        let c = LeaguePanel.card(blind, shown: 0, key: "gl", level: 17)
        XCTAssertEqual(c.status, .ivsNotRead)
        XCTAssertEqual(c.ivText, "—"); XCTAssertEqual(c.ivRankText, "not read")
        XCTAssertTrue(c.costItems.isEmpty); XCTAssertNil(c.costNote)
        let noLevel = R(options: [option("eevee", score: 70, iv: iv, isSelf: true)])
        XCTAssertEqual(LeaguePanel.card(noLevel, shown: 0, key: "gl", level: nil).costNote, "Level not known, so no cost")
        XCTAssertEqual(LeaguePanel.row(noLevel.options[0], key: "gl", level: nil).candy, "level not known")
    }

    func testPastBestLevelAndAtLevel() {
        let o = option("corviknight", score: 86.3, iv: iv, cost: .init(dust: 0, candy: 0, xl: 0, evolveCandy: 100, toLevel: 31))
        XCTAssertEqual(LeaguePanel.costNote(o, key: "ul", level: 51), "Past its best Ultra League level; 100 candy")
        XCTAssertEqual(LeaguePanel.costNote(o, key: "ul", level: 31), "Already at level 31; 100 candy")
        let none = option("x", iv: iv, cost: .init(dust: 0, candy: 0, xl: 0, evolveCandy: 0, toLevel: 50))
        XCTAssertEqual(LeaguePanel.costNote(none, key: "ml", level: 51), "Past its best Master League level")
        XCTAssertEqual(LeaguePanel.costNote(none, key: "ml", level: 50), "Already at level 50")
        XCTAssertNil(LeaguePanel.costNote(option("y", iv: iv, cost: cost), key: "gl", level: 17))
    }

    func testDustShort() {
        XCTAssertEqual(LeaguePanel.dustShort(0), "0")
        XCTAssertEqual(LeaguePanel.dustShort(4400), "4,400")
        XCTAssertEqual(LeaguePanel.dustShort(9999), "9,999")
        XCTAssertEqual(LeaguePanel.dustShort(14_000), "14k")
        XCTAssertEqual(LeaguePanel.dustShort(56_800), "56.8k")
        XCTAssertEqual(LeaguePanel.dustShort(488_800), "489k")
    }

    func testRowFigures() {
        let xl = option("eevee", iv: .init(rank: 1778, pct: 95.2, rankPct: 95, level: 50, cp: 1200), cost: .init(dust: 488_800, candy: 25, xl: 296, evolveCandy: 0, toLevel: 50), isSelf: true)
        let r = LeaguePanel.row(xl, key: "ml", level: 17)
        XCTAssertEqual(r.sub, "itself, no evolving"); XCTAssertEqual(r.dust, "489k"); XCTAssertEqual(r.candy, "296 XL"); XCTAssertTrue(r.dustMuted)
        XCTAssertEqual(r.score, "—"); XCTAssertEqual(r.ivRank, "IV #1,778")
        let umb = option("umbreon", score: 90.2, rank: 24, iv: .init(rank: 1879, pct: 94.75, rankPct: 94, level: 26.5, cp: 1481), cost: .init(dust: 56_800, candy: 60, xl: 0, evolveCandy: 15, toLevel: 26.5))
        let u = LeaguePanel.row(umb, key: "gl", level: 17)
        XCTAssertEqual(u.sub, "L26.5 · CP 1,481"); XCTAssertEqual(u.dust, "56.8k"); XCTAssertEqual(u.candy, "75 candy"); XCTAssertEqual(u.rank, "#24"); XCTAssertTrue(u.scoreStrong)
        XCTAssertEqual(u.detailLevel, "Best level 26.5 under the cap, CP 1,481. IVs rank #1,879 of 4,096, 94.75% of best.")
        XCTAssertEqual(u.detailCost, "To level 26.5: 56,800 dust, 75 candy · CP 1,481")
        XCTAssertNil(u.detailMoves, "an unranked or move-less member has no moves line")
        let ml = LeaguePanel.row(umb, key: "ml", level: 17)
        XCTAssertEqual(ml.detailLevel, "Best level 26.5, CP 1,481. IVs rank #1,879 of 4,096, 94.75% of best.", "Master League has no cap to be under")
        var ranked = umb; ranked.moves = .init(fast: "Snarl", charged: ["Foul Play", "Last Resort"])
        XCTAssertEqual(LeaguePanel.row(ranked, key: "gl", level: 17).detailMoves, "Moves: Snarl, Foul Play, Last Resort")
        let over = LeaguePanel.row(option("corviknight", score: 86, over: true), key: "gl", level: 35)
        XCTAssertEqual(over.blockedText, "Over 1,500 CP as Corviknight"); XCTAssertEqual(over.sub, "too high already")
        XCTAssertEqual(LeaguePanel.row(option("gallade", locked: "male"), key: "gl", level: 17).sub, "if it is male")
        XCTAssertEqual(LeaguePanel.title(option("gallade", locked: "male")), "Gallade, if it is male")
    }

    func testIVFiguresPerLeague() {
        let gl = R(options: [option("a", score: 70, iv: iv, cost: cost)])
        let ul = R(options: [option("a", over: true)])
        let f = LeaguePanel.ivFigures(["gl": gl, "ul": ul], pogoAssist: false, level: 17)
        XCTAssertEqual(f.map(\.key), ["gl", "ul", "ml"])
        XCTAssertEqual(f[0].pct, 97.24); XCTAssertNil(f[1].pct); XCTAssertNil(f[2].pct)
    }

    func testListedLeavesOutTheHeadline() {
        let r = R(options: [option("a"), option("b"), option("c")])
        XCTAssertEqual(LeaguePanel.listed(r, headline: 1).map(\.speciesId), ["a", "c"])
        XCTAssertEqual(LeaguePanel.listed(r, headline: nil).count, 3)
    }

    func testCapText() {
        XCTAssertEqual(LeaguePanel.capText("gl"), "Under 1,500 CP"); XCTAssertEqual(LeaguePanel.capText("ul"), "Under 2,500 CP"); XCTAssertEqual(LeaguePanel.capText("ml"), "No CP cap")
    }

    // MARK: the worth tag

    private func build(areas: [String]) -> BoxAdvice.Build {
        BoxAdvice.Build(entryId: "e", title: "X", cp: 300, level: 20, ivs: nil, targetId: "t", targetName: "T", powerUp: false, formChange: false, viaMega: false,
                        needsDynamax: false, spares: 0, areas: areas, tier: "B", targetLevel: nil, dust: 0, candy: 0, xl: 0, pvp: nil, score: 1, steps: [])
    }
    private func rolled(_ pct: Double) -> R.IV { R.IV(rank: 216, pct: 97.24, rankPct: pct, level: 18.5, cp: 1500) }
    private func worth(_ o: O, builds: [BoxAdvice.Build] = []) -> LeaguePanel.Worth? { LeaguePanel.card(R(options: [o]), shown: 0, key: "gl", level: 17, builds: builds).worth }

    // The rule is worth alone (the species' PvPoke tier and this copy's roll); the advisor's builds do not enter it. What changed from the earlier
    // tests: Strong used to mean "an Advice build covers the league" and OK was "score >= 80"; Strong is now score >= 92 with a roll in the top fifth,
    // OK score >= 88 (A from 90, B from the engine's 88 floor) with the same roll, and the build is the separate `buildsIt` marker.
    func testTheTagIsTheSpeciesTierAndTheRollNotTheBuild() {
        XCTAssertEqual(worth(option("a", score: 92, iv: iv, cost: cost)), .strong, "92 is the S line, inclusive")
        XCTAssertEqual(worth(option("a", score: 96.4, iv: iv, cost: cost)), .strong)
        XCTAssertEqual(worth(option("a", score: 91.9, iv: iv, cost: cost)), .ok)
        XCTAssertEqual(worth(option("a", score: 90, iv: iv, cost: cost)), .ok, "90 is the A line")
        XCTAssertEqual(worth(option("a", score: 88, iv: iv, cost: cost)), .ok, "88 is the engine's PvP-relevant floor, inclusive")
        XCTAssertEqual(worth(option("a", score: 87.9, iv: iv, cost: cost)), .weak)
        XCTAssertEqual(worth(option("a", iv: iv, cost: cost)), .weak, "unranked")
        // A build covering the league changes nothing about the tag: neither up for a weak species, nor down for a strong one.
        XCTAssertEqual(worth(option("a", score: 60, iv: iv, cost: cost), builds: [build(areas: ["GL"])]), .weak)
        XCTAssertEqual(worth(option("a", score: 95, iv: iv, cost: cost), builds: [build(areas: ["UL", "ML"])]), .strong)
        XCTAssertEqual([LeaguePanel.sScore, LeaguePanel.aScore, LeaguePanel.bScore, LeaguePanel.decentRollPercentile], [92, 90, 88, 80])
        XCTAssertEqual(LeaguePanel.tier(score: 92), "S"); XCTAssertEqual(LeaguePanel.tier(score: 90), "A"); XCTAssertEqual(LeaguePanel.tier(score: 88), "B")
        XCTAssertNil(LeaguePanel.tier(score: 87.9)); XCTAssertNil(LeaguePanel.tier(score: nil))
    }

    func testADecentRollIsTheTopFifthOfTheLeaguesSpreads() {
        XCTAssertEqual(worth(option("a", score: 95, iv: rolled(80), cost: cost)), .strong, "80 is the bar, inclusive")
        XCTAssertEqual(worth(option("a", score: 95, iv: rolled(79.9), cost: cost)), .weak)
        XCTAssertEqual(worth(option("a", score: 89, iv: rolled(80), cost: cost)), .ok)
        XCTAssertEqual(worth(option("a", score: 89, iv: rolled(79), cost: cost)), .weak)
        XCTAssertEqual(worth(option("a", score: 95, iv: nil, cost: cost)), .weak, "IVs not read")
        XCTAssertEqual(LeaguePanel.card(R(options: [option("a", score: 95, iv: nil, cost: cost)]), shown: 0, key: "gl", level: 17).status, .ivsNotRead)
    }

    func testTheCardCarriesTierRollAndTheBuildMarkerSeparately() {
        let r = R(options: [option("wartortle", score: 86.2, rank: 90, iv: iv, cost: cost)])
        // Squirtle: the shown member (Wartortle, 86.2: below the B line, so Weak) differs from the build's target (Blastoise); the build covers GL and UL.
        let b = build(areas: ["Max", "GL", "UL", "Raids"])
        let gl = LeaguePanel.card(r, shown: 0, key: "gl", level: 17, builds: [b])
        XCTAssertEqual(gl.worth, .weak); XCTAssertTrue(gl.buildsIt); XCTAssertNil(gl.tier); XCTAssertEqual(gl.roll, 97)
        XCTAssertTrue(LeaguePanel.card(r, shown: 0, key: "ul", level: 17, builds: [b]).buildsIt)
        let ml = LeaguePanel.card(r, shown: 0, key: "ml", level: 17, builds: [b])
        XCTAssertFalse(ml.buildsIt, "no build covers Master League"); XCTAssertNil(ml.buildTarget)
        XCTAssertFalse(LeaguePanel.card(r, shown: 0, key: "gl", level: 17).buildsIt)
        let strong = LeaguePanel.card(R(options: [option("sylveon", score: 93, rank: 4, iv: iv, cost: cost)]), shown: 0, key: "gl", level: 17)
        XCTAssertEqual(strong.worth, .strong); XCTAssertEqual(strong.tier, "S"); XCTAssertFalse(strong.buildsIt)
    }

    func testNoTagOnANoViableCardAndTheSentencesAndSpeech() {
        let none = R(options: [option("moltres", score: 70, over: true, isSelf: true)])
        let c = LeaguePanel.card(none, shown: 0, key: "gl", level: 20, builds: [build(areas: ["GL"])])
        XCTAssertEqual(c.status, .noViable); XCTAssertNil(c.worth)
        XCTAssertNil(LeaguePanel.worthSentence(c, key: "gl"))
        XCTAssertFalse(LeaguePanel.spoken(c, key: "gl", chip: "Pick").contains("for Great League"))
        func card(_ score: Double?, _ iv: R.IV?, key: String = "gl") -> LeaguePanel.Card {
            LeaguePanel.card(R(options: [option("a", score: score, iv: iv, cost: iv == nil ? nil : cost)]), shown: 0, key: key, level: 17)
        }
        XCTAssertEqual(LeaguePanel.worthSentence(card(95, rolled(97)), key: "gl"), "S-tier species, IVs in the top 3% for Great League")
        XCTAssertEqual(LeaguePanel.worthSentence(card(95, rolled(80)), key: "gl"), "S-tier species, IVs in the top 20% for Great League")
        XCTAssertEqual(LeaguePanel.worthSentence(card(90.5, rolled(88.4)), key: "ul"), "A-tier species, IVs in the top 12% for Ultra League")
        XCTAssertEqual(LeaguePanel.worthSentence(card(88.5, rolled(99)), key: "ml"), "B-tier species, IVs in the top 1% for Master League")
        XCTAssertEqual(LeaguePanel.worthSentence(card(95, rolled(55)), key: "gl"), "S-tier species, but IVs only in the top 45% for Great League; a good roll is the top 20%")
        XCTAssertEqual(LeaguePanel.worthSentence(card(80, rolled(99)), key: "gl"), "Species below the B-tier line for Great League")
        XCTAssertEqual(LeaguePanel.worthSentence(card(nil, rolled(99)), key: "gl"), "Species not ranked for Great League")
        XCTAssertEqual(LeaguePanel.worthSentence(card(95, nil), key: "gl"), "IVs not read, so no roll to judge for Great League")
        XCTAssertEqual(LeaguePanel.worthSentence(card(80, rolled(99)), key: "ml", transfers: true), "Species below the B-tier line for Master League. Better kept for trading or transferring")
        XCTAssertEqual(LeaguePanel.worthSentence(card(95, rolled(97)), key: "gl", transfers: true), "S-tier species, IVs in the top 3% for Great League", "transferring is only said of a Weak tag")
        let fit = card(89, rolled(97), key: "ml")
        XCTAssertTrue(LeaguePanel.spoken(fit, key: "ml", chip: "Pick").contains("Pick: A. Good for Master League. Species 89.0"), LeaguePanel.spoken(fit, key: "ml", chip: "Pick"))
    }

    func testASpareCopyDoesNotGetTheBuildMarkerFromAnotherCopysBuild() {
        // The build covers GL, but another copy carries it (this copy is only a spare for it): the card is handed the copy's OWN builds, which is none.
        var advice = BoxAdvice(builds: [build(areas: ["GL"])])
        advice.spareBuilds["spare"] = advice.builds
        let own = advice.entries(for: "spare").builds
        XCTAssertTrue(own.isEmpty)
        let r = R(options: [option("cursola", score: 60, rank: 700, iv: iv, cost: cost)])
        XCTAssertFalse(LeaguePanel.card(r, shown: 0, key: "gl", level: 17, builds: own).buildsIt)
        XCTAssertTrue(LeaguePanel.card(r, shown: 0, key: "gl", level: 17, builds: advice.entries(for: "e").builds).buildsIt, "the copy that carries the build has the marker")
    }

    func testTheBuildMarkerNamesTheBuildTargetWhenItIsNotTheShownMember() {
        func b(_ name: String, areas: [String]) -> BoxAdvice.Build { var x = build(areas: areas); x.targetName = name; return x }
        // Wartortle card, Blastoise build.
        let squirtle = R(options: [option("wartortle", score: 86.2, rank: 90, iv: iv, cost: cost)])
        let c = LeaguePanel.card(squirtle, shown: 0, key: "gl", level: 17, builds: [b("Blastoise", areas: ["GL"])])
        XCTAssertTrue(c.buildsIt); XCTAssertEqual(c.buildTarget, "Blastoise")
        XCTAssertTrue(LeaguePanel.spoken(c, key: "gl", chip: "Pick").contains("Advice builds it as Blastoise"))
        // The shown member is the build's target (also with a Shadow suffix): no "as".
        let same = LeaguePanel.card(R(options: [option("blastoise", score: 89, rank: 40, iv: iv, cost: cost)]), shown: 0, key: "gl", level: 17, builds: [b("Blastoise", areas: ["GL"])])
        XCTAssertTrue(same.buildsIt); XCTAssertNil(same.buildTarget)
        XCTAssertTrue(LeaguePanel.spoken(same, key: "gl", chip: "Pick").contains("Advice builds it."), "no target named")
        XCTAssertNil(LeaguePanel.card(R(options: [option("blastoise", score: 89, rank: 40, iv: iv, cost: cost)]), shown: 0, key: "gl", level: 17, builds: [b("Blastoise (Shadow)", areas: ["GL"])]).buildTarget)
        // Any covering build for the shown member is enough; a build for another league names nothing.
        XCTAssertNil(LeaguePanel.card(squirtle, shown: 0, key: "gl", level: 17, builds: [b("Blastoise", areas: ["GL"]), b("Wartortle", areas: ["GL"])]).buildTarget)
        let other = LeaguePanel.card(squirtle, shown: 0, key: "ul", level: 17, builds: [b("Blastoise", areas: ["GL"])])
        XCTAssertNil(other.buildTarget); XCTAssertFalse(other.buildsIt)
    }

    // MARK: the tier is the engine's (fold of slice 1b)

    func testTheTierIsTheTierTablesLetterWhenTheTableNamesTheSpeciesElseTheScoreBand() {
        func card(_ id: String, _ score: Double?, key: String = "gl") -> LeaguePanel.Card {
            LeaguePanel.card(R(options: [option(id, score: score, iv: rolled(97), cost: cost)]), shown: 0, key: key, level: 17)
        }
        // Tinkaton in Great League: tiers.json says S, the score 91.7 alone would say A. The table wins, as in the Next list and the Advice panel.
        let tinkaton = card("tinkaton", 91.7)
        XCTAssertEqual(tinkaton.tier, "S"); XCTAssertEqual(tinkaton.worth, .strong)
        XCTAssertEqual(LeaguePanel.worthSentence(tinkaton, key: "gl"), "S-tier species, IVs in the top 3% for Great League")
        XCTAssertEqual(LeaguePanel.tier(score: 91.7), "A", "the band alone")
        // The table is per league: an id the Great League table names is judged by its score in a league whose table does not.
        XCTAssertEqual(LeaguePanel.tableTiers["gl/altaria"], "S"); XCTAssertNil(LeaguePanel.tableTiers["ul/altaria"])
        XCTAssertNil(LeaguePanel.tier(speciesId: "altaria", key: "ul", score: 80.5), "no Ultra entry and below the B line")
        XCTAssertEqual(LeaguePanel.tier(speciesId: "altaria", key: "ul", score: 90.5), "A", "no Ultra entry: the score band")
        XCTAssertEqual(LeaguePanel.tier(speciesId: "tinkaton", key: "ml", score: 80), LeaguePanel.tableTiers["ml/tinkaton"] ?? nil)
        // No table entry: the score band applies (S >= 92, A >= 90, B >= 88, below none).
        XCTAssertNil(LeaguePanel.tableTiers["gl/notaspecies"])
        XCTAssertEqual(card("notaspecies", 90.4).tier, "A"); XCTAssertEqual(card("notaspecies", 88).tier, "B")
        XCTAssertNil(card("notaspecies", 87.9).tier)
        // Wartortle (Great League 86.2) and Scyther (Ultra League 71.8) are in no table and below the B line: no tier, Weak, however good the roll.
        XCTAssertNil(LeaguePanel.tableTiers["gl/wartortle"]); XCTAssertNil(LeaguePanel.tableTiers["ul/scyther"])
        let wartortle = card("wartortle", 86.2), scyther = card("scyther", 71.8, key: "ul")
        XCTAssertNil(wartortle.tier); XCTAssertEqual(wartortle.worth, .weak)
        XCTAssertNil(scyther.tier); XCTAssertEqual(scyther.worth, .weak)
    }

    func testTierAndRollComeFromTheHeadlineOptionWhenTheShownOneIsOverTheCap() {
        let r = R(options: [option("tinkaton", score: 95, rank: 1, iv: rolled(99), over: true),
                            option("scyther", score: 71.8, rank: 700, iv: rolled(50), cost: cost)], pick: 0, experimental: 0)
        let c = LeaguePanel.card(r, shown: 0, key: "gl", level: 17)
        XCTAssertEqual(c.option.speciesId, "scyther")
        XCTAssertNil(c.tier); XCTAssertEqual(c.roll, 50); XCTAssertEqual(c.worth, .weak)
    }

    func testCardHighlightsUseTheTagsThresholds() {
        func card(_ score: Double, _ pct: Double) -> LeaguePanel.Card {
            LeaguePanel.card(R(options: [option("a", score: score, iv: rolled(pct), cost: cost)]), shown: 0, key: "gl", level: 17)
        }
        XCTAssertTrue(card(88, 80).scoreStrong); XCTAssertFalse(card(87.9, 80).scoreStrong); XCTAssertTrue(card(88, 80).ivStrong); XCTAssertFalse(card(88, 79.9).ivStrong)
        let row = LeaguePanel.row(option("a", score: 88, iv: rolled(80), cost: cost), key: "gl", level: 17)
        XCTAssertTrue(row.scoreStrong); XCTAssertTrue(row.ivStrong)
        let low = LeaguePanel.row(option("a", score: 85, iv: rolled(79), cost: cost), key: "gl", level: 17)
        XCTAssertFalse(low.scoreStrong); XCTAssertFalse(low.ivStrong)
    }

    func testTheBuildChipNamesTheTargetOnlyWhenItDiffersAndTheSentenceChecksTheTierFirst() {
        var b = build(areas: ["GL"]); b.targetName = "Blastoise"
        let wart = LeaguePanel.card(R(options: [option("wartortle", score: 86.2, iv: iv, cost: cost)]), shown: 0, key: "gl", level: 17, builds: [b])
        XCTAssertEqual(LeaguePanel.buildsChipText(wart), "ADVICE BUILDS BLASTOISE")
        let same = LeaguePanel.card(R(options: [option("blastoise", score: 89, iv: iv, cost: cost)]), shown: 0, key: "gl", level: 17, builds: [b])
        XCTAssertEqual(LeaguePanel.buildsChipText(same), "ADVICE BUILDS IT")
        XCTAssertTrue(LeaguePanel.spoken(wart, key: "gl", chip: "Pick").contains("Advice builds it as Blastoise"))
        // Unranked and IVs not read: the species is what is wrong first.
        let unranked = LeaguePanel.card(R(options: [option("a", iv: nil)]), shown: 0, key: "gl", level: 17)
        XCTAssertEqual(LeaguePanel.worthSentence(unranked, key: "gl"), "Species not ranked for Great League")
        // A roll just under the bar is "top 21%" against the "top 20%" bar.
        let near = LeaguePanel.card(R(options: [option("a", score: 95, iv: rolled(79.9), cost: cost)]), shown: 0, key: "gl", level: 17)
        XCTAssertEqual(LeaguePanel.worthSentence(near, key: "gl"), "S-tier species, but IVs only in the top 21% for Great League; a good roll is the top 20%")
    }

    func testTheNextListShowsTheCopysRollBesideTheTierAndWordsTheStepsLeft() {
        var b = build(areas: ["GL"])
        b.tier = "S"; b.ivs = "8/15/0"
        XCTAssertEqual(b.worthText, "S-tier · IVs 51.1%")
        b.ivs = "15/15/15"; XCTAssertEqual(b.worthText, "S-tier · IVs 100.0%")
        b.ivs = nil; XCTAssertEqual(b.worthText, "S-tier · IVs not read")
        // A league build's roll is the league IV rank percentile; a league build that also covers an activity shows both; the IV % never stands in for it.
        b.ivs = "11/0/0"; b.pvpLeague = "gl"; b.pvpRankPct = 95
        XCTAssertEqual(b.worthText, "S-tier · GL rank top 5%")
        b.areas = ["GL", "Raids"]; XCTAssertEqual(b.worthText, "S-tier · GL rank top 5% · IVs 24.4%")
        b.ivs = nil; XCTAssertEqual(b.worthText, "S-tier · GL rank top 5% · IVs not read")
        b.areas = ["UL"]; b.pvpLeague = "ul"; b.pvpRankPct = 100; XCTAssertEqual(b.worthText, "S-tier · UL rank top 1%", "never top 0%")
        b.pvpRankPct = 82.9; XCTAssertEqual(b.worthText, "S-tier · UL rank top 18%")
        // EFFORT is the cost figures only; the steps are the action line.
        b.steps = [.init(kind: "formChange", to: "X"), .init(kind: "eliteTM", count: 2)]
        XCTAssertEqual(b.effortText, "No dust or candy")
        b.steps = []; XCTAssertEqual(b.effortText, "No dust or candy")
        b.dust = 56_800; b.candy = 10
        XCTAssertEqual(b.effortText, b.costText, "a cost is shown as the cost")
    }
}
