import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The species page's places (`BoxInsight.top` / `place`): which copies rank for a use, in what order, capped at three, never a Weak one.
final class BoxTopTests: XCTestCase {
    typealias R = BoxAdvice.LeagueRating
    typealias O = R.Option

    private func option(_ id: String, score: Double? = 93, pct: Double? = 90, rankPct: Double = 90, over: Bool = false) -> O {
        O(speciesId: id, name: id.capitalized, isSelf: false, genderLocked: nil, strength: score.map { .init(score: $0, rank: 10, of: 1152) }, moves: nil, needs: nil,
          iv: pct.map { .init(rank: 100, pct: $0, rankPct: rankPct, level: 20, cp: 1490) }, overCap: over, cost: nil)
    }
    private var date: Date { Date(timeIntervalSince1970: 1_790_000_000) }
    private func entry(_ id: String, _ title: String = "Eevee", cp: Int = 1400, shadow: Bool = false) -> BoxEntry {
        var row = ScanRow(index: 1, name: title, display: title, form: "", speciesId: title.lowercased(), dex: nil, cp: cp, hp: 100, ivs: nil, ivsRead: nil, ivsGuess: nil,
                          level: 20, levelMax: nil, dust: nil, solveStatus: "exact", flags: [], frames: [])
        if shadow { row.shadow = 1 }
        return BoxEntry(id: id, row: row, firstSeen: date, lastSeen: date)
    }
    private func fit(_ area: String, _ tag: BoxAdvice.Fit.Tag, tier: String? = nil, iv: Double = 90, as name: String? = "Tyranitar") -> BoxAdvice.Fit {
        BoxAdvice.Fit(area: area, tag: tag, asName: tag == .weak ? nil : name, tier: tier, reason: tag == .weak ? .iv : nil, species: nil, ivPercent: iv)
    }
    private func advice(_ leagues: [String: [String: R]] = [:], fit: [String: [String: BoxAdvice.Fit]] = [:]) -> BoxAdvice {
        var a = BoxAdvice(builds: [], gaps: [], duplicates: [], unresolved: [])
        a.leagues = leagues; a.fit = fit
        return a
    }
    private func ids(_ i: BoxInsight, _ a: BoxInsight.Activity, assist: Bool = false, title: String = "Eevee") -> [String] { i.top(title: title, a, pogoAssist: assist) }

    func testALeagueRanksTopBeforeGoodThenRollThenIVPercentThenBoxOrder() {
        // Scores: 93 is S (Top with a top-fifth roll), 89 is B (Good with one). rankPct under 80 is Weak for any tier.
        let es = ["a", "b", "c", "d", "e", "f"].map { entry($0) }
        let adv = advice(["a": ["gl": R(options: [option("flareon", score: 89, pct: 99, rankPct: 99)])],  // Good, best roll
                          "b": ["gl": R(options: [option("flareon", score: 93, pct: 90, rankPct: 85)])],  // Top, lower roll
                          "c": ["gl": R(options: [option("flareon", score: 93, pct: 91, rankPct: 85)])],  // Top, same roll, higher IV %
                          "d": ["gl": R(options: [option("flareon", score: 93, pct: 91, rankPct: 85)])],  // ties c: box order
                          "e": ["gl": R(options: [option("flareon", score: 93, pct: 60, rankPct: 10)])],  // Weak
                          "f": ["gl": R(options: [option("flareon", score: 93, pct: 99, rankPct: 99)])]]) // Top, best roll: first
        let i = BoxInsight.make(advice: adv, entries: es)
        XCTAssertEqual(i.copies["e"]?.slot("gl", pogoAssist: false)?.worth, .weak)
        XCTAssertEqual(ids(i, .gl), ["f", "c", "d"], "Top by roll, then IV %, then box order; capped at three; Good a is past the cap")
        XCTAssertFalse(ids(i, .gl).contains("e"), "a Weak copy is never ranked")
        XCTAssertEqual(i.place(of: "f", title: "Eevee", .gl, pogoAssist: false), 1)
        XCTAssertNil(i.place(of: "a", title: "Eevee", .gl, pogoAssist: false))
        XCTAssertNil(i.place(of: "e", title: "Eevee", .gl, pogoAssist: false))
    }

    func testGoodCopiesFillTheEmptyPlacesBehindTop() {
        let es = ["a", "b"].map { entry($0) }
        let adv = advice(["a": ["ul": R(options: [option("flareon", score: 89, pct: 99, rankPct: 99)])],
                          "b": ["ul": R(options: [option("flareon", score: 93, pct: 80, rankPct: 81)])]])
        let i = BoxInsight.make(advice: adv, entries: es)
        XCTAssertEqual(ids(i, .ul), ["b", "a"], "Top first although the Good copy has the better roll")
        XCTAssertEqual(i.place(of: "a", title: "Eevee", .ul, pogoAssist: false), 2)
    }

    func testBothRankingsAreRankedAndOnlyTheLeaguesDifferByRanking() {
        func two(_ classic: O, _ assist: O) -> R { R(options: [classic, assist], pick: 0, experimental: 1) }
        let es = [entry("a"), entry("b")]
        let strong = fit("raids", .strong, tier: "S")
        let adv = advice(["a": ["gl": two(option("flareon", score: 93, pct: 90, rankPct: 95), option("vaporeon", score: 93, pct: 90, rankPct: 85))],
                          "b": ["gl": two(option("flareon", score: 93, pct: 90, rankPct: 90), option("vaporeon", score: 93, pct: 90, rankPct: 92))]],
                         fit: ["a": ["raids": strong], "b": ["raids": strong]])
        let i = BoxInsight.make(advice: adv, entries: es)
        XCTAssertEqual(ids(i, .gl, assist: false), ["a", "b"])
        XCTAssertEqual(ids(i, .gl, assist: true), ["b", "a"])
        XCTAssertEqual(ids(i, .raids, assist: false), ids(i, .raids, assist: true))
    }

    func testTheFirstPlaceIsTheLeagueTileCopyUnderBothRankings() {
        func two(_ classic: O, _ assist: O) -> R { R(options: [classic, assist], pick: 0, experimental: 1) }
        let es = (0..<5).map { entry("c\($0)") }
        let scores: [(Double, Double, Double, Double)] = [(93, 70, 96, 70), (89, 95, 99, 99), (93, 85, 91, 60), (93, 85, 97, 92), (70, 99, 99, 99)]
        var leagues = [String: [String: R]]()
        for (n, s) in scores.enumerated() {
            leagues["c\(n)"] = ["gl": two(option("flareon", score: s.0, pct: 90 + Double(n), rankPct: s.1), option("vaporeon", score: s.2, pct: 91 - Double(n), rankPct: s.3))]
        }
        let i = BoxInsight.make(advice: advice(leagues), entries: es)
        for assist in [false, true] {
            let tile = i.tile(title: "Eevee", league: "gl", pogoAssist: assist)
            XCTAssertEqual(ids(i, .gl, assist: assist).first, tile?.copyId, "assist \(assist)")
        }
    }

    func testAnAreaRanksTierThenIVPercentThenCPThenBoxOrderAndSkipsWeak() {
        let es = [entry("a", cp: 2000), entry("b", cp: 1000), entry("c", cp: 1500), entry("d", cp: 1500), entry("e", cp: 3000), entry("f", cp: 900)]
        let adv = advice(fit: [
            "a": ["gym": fit("gym", .ok, tier: "A", iv: 99)],        // A beats nothing above S
            "b": ["gym": fit("gym", .strong, tier: "S", iv: 85)],
            "c": ["gym": fit("gym", .strong, tier: "S", iv: 85)],    // same tier and IV %: higher CP than b
            "d": ["gym": fit("gym", .strong, tier: "S", iv: 85)],    // ties c on everything: box order
            "e": ["gym": fit("gym", .weak)],
            "f": ["gym": fit("gym", .ok, tier: "B", iv: 100)],
        ])
        let i = BoxInsight.make(advice: adv, entries: es)
        XCTAssertEqual(ids(i, .gym), ["c", "d", "b"], "S over A over B, then IV %, then CP, then box order; cap of three")
        XCTAssertEqual(ids(i, .gym, assist: true), ids(i, .gym))
        XCTAssertNil(i.place(of: "e", title: "Eevee", .gym, pogoAssist: false), "Weak is never numbered")
        XCTAssertEqual(ids(i, .rocket), [], "no fit for the area: no places")
        // The IV % outranks tier only within a tier: an S at 80 beats an A at 100.
        let j = BoxInsight.make(advice: advice(fit: ["a": ["max": fit("max", .ok, tier: "A", iv: 100)], "b": ["max": fit("max", .strong, tier: "S", iv: 80)]]), entries: [entry("a"), entry("b")])
        XCTAssertEqual(ids(j, .max), ["b", "a"])
    }

    func testAPlainAndAShadowCopyOfOneTitleAreRankedTogether() {
        let es = [entry("plain"), entry("shadow", shadow: true)]
        let adv = advice(fit: ["plain": ["raids": fit("raids", .strong, tier: "S", iv: 90)], "shadow": ["raids": fit("raids", .strong, tier: "S", iv: 95)]])
        let i = BoxInsight.make(advice: adv, entries: es)
        XCTAssertEqual(ids(i, .raids), ["shadow", "plain"], "one list across both, not one best each")
        XCTAssertEqual(i.copies["shadow"]?.asNames[0], "Tyranitar (Shadow)")
        XCTAssertEqual(i.copies["plain"]?.asNames[0], "Tyranitar")
    }

    func testPlaceAgreesWithTopAndOtherSpeciesDoNotMix() {
        let es = [entry("a"), entry("b"), entry("x", "Pidgey")]
        let strong = fit("raids", .strong, tier: "S")
        let i = BoxInsight.make(advice: advice(fit: ["a": ["raids": strong], "b": ["raids": strong], "x": ["raids": strong]]), entries: es)
        for a in BoxInsight.Activity.allCases {
            for title in ["Eevee", "Pidgey", "Nobody"] {
                let list = i.top(title: title, a, pogoAssist: false)
                XCTAssertLessThanOrEqual(list.count, BoxInsight.topCount)
                for (n, id) in list.enumerated() { XCTAssertEqual(i.place(of: id, title: title, a, pogoAssist: false), n + 1) }
            }
        }
        XCTAssertEqual(ids(i, .raids), ["a", "b"])
        XCTAssertEqual(ids(i, .raids, title: "Pidgey"), ["x"])
        XCTAssertNil(i.place(of: "x", title: "Eevee", .raids, pogoAssist: false))
    }
}
