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
                       "Great League, under 1,500 CP. Pick: Flareon. Species 68.9, rank 710 of 1,152. This copy 97.2 percent, IV rank 216. target level 18.5, target CP 1,500, 6,600 dust, 31 candy. Moves Ember, Overheat, Flamethrower.")
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
}
