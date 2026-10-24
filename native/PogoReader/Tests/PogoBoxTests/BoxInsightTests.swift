import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The list's per-copy tags and per-species tiles (`BoxInsight`): the slot agrees with the pick card, the tile is the species' best copy, and a chip
/// keeps the copies that are Strong or OK.
final class BoxInsightTests: XCTestCase {
    typealias R = BoxAdvice.LeagueRating
    typealias O = R.Option

    private func option(_ id: String, score: Double? = nil, pct: Double? = nil, rankPct: Double = 90, over: Bool = false) -> O {
        O(speciesId: id, name: id.capitalized, isSelf: false, genderLocked: nil, strength: score.map { .init(score: $0, rank: 10, of: 1152) }, moves: nil, needs: nil,
          iv: pct.map { .init(rank: 100, pct: $0, rankPct: rankPct, level: 20, cp: 1490) }, overCap: over, cost: nil)
    }
    private var date: Date { Date(timeIntervalSince1970: 1_790_000_000) }
    private func entry(_ id: String, _ title: String) -> BoxEntry {
        let row = ScanRow(index: 1, name: title, display: title, form: "", speciesId: title.lowercased(), dex: nil, cp: 1400, hp: 100, ivs: nil, ivsRead: nil, ivsGuess: nil,
                          level: 20, levelMax: nil, dust: nil, solveStatus: "exact", flags: [], frames: [])
        return BoxEntry(id: id, row: row, firstSeen: date, lastSeen: date)
    }
    private func advice(_ leagues: [String: [String: R]], fit: [String: [String: BoxAdvice.Fit]] = [:]) -> BoxAdvice {
        var a = BoxAdvice(builds: [], gaps: [], duplicates: [], unresolved: [])
        a.leagues = leagues; a.fit = fit
        return a
    }

    func testSlotAgreesWithTheCardForEveryStatus() {
        let fits = R(options: [option("flareon", score: 93, pct: 97.2, rankPct: 95)])
        let notRead = R(options: [option("flareon", score: 93)])
        let over = R(options: [option("corviknight", score: 86, pct: 90, over: true)])
        let fallback = R(options: [option("corviknight", score: 86, pct: 90, over: true), option("corvisquire", pct: 91, rankPct: 85)], pick: 0, experimental: 0)
        for r in [fits, notRead, over, fallback] {
            let s = LeaguePanel.slot(r, shown: 0, key: "gl"), c = LeaguePanel.card(r, shown: 0, key: "gl", level: 20)
            XCTAssertEqual(s?.worth, c.worth)
            XCTAssertEqual(s?.pct, c.ivPct)
            XCTAssertEqual(s?.member, c.option.name)
            XCTAssertEqual(s?.status == .overCap, c.status == .noViable)
            XCTAssertEqual(s?.status == .ivsNotRead, c.status == .ivsNotRead)
        }
        XCTAssertEqual(LeaguePanel.slot(fits, shown: 0, key: "gl")?.worth, .strong, "S tier, top-fifth roll")
        XCTAssertEqual(LeaguePanel.slot(fallback, shown: 0, key: "gl")?.member, "Corvisquire", "the member that fits headlines")
    }

    func testTheTileIsTheSpeciesBestCopyUnderEachRanking() {
        // Two copies of Eevee: A fits Flareon at a lower rank percentile, B fits it higher. A third has IVs not read, a fourth is over the cap.
        let es = [entry("a", "Eevee"), entry("b", "Eevee"), entry("c", "Eevee"), entry("d", "Pidgey"), entry("e", "Pidgey")]
        func two(_ classic: O, _ assist: O) -> R { R(options: [classic, assist], pick: 0, experimental: 1) }
        let adv = advice([
            "a": ["gl": two(option("flareon", score: 70, pct: 96, rankPct: 80), option("vaporeon", score: 80, pct: 94, rankPct: 70))],
            "b": ["gl": two(option("flareon", score: 70, pct: 95, rankPct: 90), option("vaporeon", score: 80, pct: 93, rankPct: 60))],
            "c": ["gl": two(option("flareon", score: 70), option("vaporeon", score: 80))],
            "d": ["gl": R(options: [option("pidgeot", over: true)])],
            "e": ["gl": R(options: [option("pidgeot", over: true)]), "ul": R(options: [option("pidgeot", pct: 99)])],
        ])
        let insight = BoxInsight.make(advice: adv, entries: es)
        let classic = insight.tile(title: "Eevee", league: "gl", pogoAssist: false)
        XCTAssertEqual(classic, .init(status: .fits, member: "Flareon", pct: 95, copyId: "b"), "highest roll percentile, not highest IV %")
        let assist = insight.tile(title: "Eevee", league: "gl", pogoAssist: true)
        XCTAssertEqual(assist, .init(status: .fits, member: "Vaporeon", pct: 94, copyId: "a"))
        XCTAssertEqual(insight.tile(title: "Eevee", league: "ul", pogoAssist: false)?.status, .noData)
        XCTAssertEqual(insight.tile(title: "Pidgey", league: "gl", pogoAssist: false)?.status, .overCap)
        XCTAssertEqual(insight.tile(title: "Pidgey", league: "ul", pogoAssist: false), .init(status: .fits, member: "Pidgeot", pct: 99, copyId: "e"))
        // Nothing but unread IVs: "IVs not read". An over-cap copy beside an unread one is also "IVs not read" (a copy fits, its IVs are not known).
        let unread = BoxInsight.make(advice: advice(["c": ["gl": R(options: [option("flareon", score: 70)])], "x": ["gl": R(options: [option("eevee", over: true)])]]), entries: [entry("x", "Eevee"), entry("c", "Eevee")])
        XCTAssertEqual(unread.tile(title: "Eevee", league: "gl", pogoAssist: false)?.status, .ivsNotRead)
    }

    /// Eevee-shaped: copy "flare" has the better IV rank percentile but a Weak Flareon rating; copy "umbre" is Strong as Umbreon at a lower percentile. The tile (and
    /// so the species list's league tag) names the Strong copy, and among equals the rank percentile, then IV %, then the box order decide.
    func testTheTilePrefersStrongThenOkThenWeakBeforeTheIVRank() {
        let es = [entry("flare", "Eevee"), entry("umbre", "Eevee"), entry("ok1", "Eevee"), entry("ok2", "Eevee"), entry("t1", "Vulpix"), entry("t2", "Vulpix"), entry("t3", "Vulpix")]
        let adv = advice([
            "flare": ["gl": R(options: [option("flareon", score: 70, pct: 99, rankPct: 99)])],
            "umbre": ["gl": R(options: [option("umbreon", score: 93, pct: 90, rankPct: 85)])],
            "ok1": ["gl": R(options: [option("espeon", score: 90, pct: 92, rankPct: 88)])],
            "ok2": ["gl": R(options: [option("espeon", score: 90, pct: 92, rankPct: 97)])],
            "t1": ["gl": R(options: [option("ninetales", score: 93, pct: 90, rankPct: 90)])],
            "t2": ["gl": R(options: [option("ninetales", score: 93, pct: 95, rankPct: 90)])],
            "t3": ["gl": R(options: [option("ninetales", score: 93, pct: 95, rankPct: 90)])],
        ])
        let insight = BoxInsight.make(advice: adv, entries: es)
        XCTAssertEqual(insight.copies["flare"]?.slot("gl", pogoAssist: false)?.worth, .weak)
        XCTAssertEqual(insight.copies["umbre"]?.slot("gl", pogoAssist: false)?.worth, .strong)
        XCTAssertEqual(insight.tile(title: "Eevee", league: "gl", pogoAssist: false)?.copyId, "umbre", "Strong beats a Weak copy with the higher IV rank")
        XCTAssertEqual(insight.tile(title: "Eevee", league: "gl", pogoAssist: false)?.member, "Umbreon")
        // Without the Strong copy, the OK copy with the better percentile beats the Weak one.
        let noStrong = BoxInsight.make(advice: adv, entries: es.filter { $0.id != "umbre" })
        XCTAssertEqual(noStrong.tile(title: "Eevee", league: "gl", pogoAssist: false)?.copyId, "ok2")
        // Equal worth and percentile: IV %, then the first in the box.
        XCTAssertEqual(insight.tile(title: "Vulpix", league: "gl", pogoAssist: false)?.copyId, "t2")
    }

    func testAShadowCopysBestOfTagNamesTheShadow() {
        var f = BoxAdvice.Fit(area: "raids", tag: .strong, asName: "Tyranitar", tier: "S", reason: nil, species: nil, ivPercent: 90)
        XCTAssertEqual(f.asNameLabel(shadow: true), "Tyranitar (Shadow)")
        XCTAssertEqual(f.asNameLabel(shadow: false), "Tyranitar")
        f.asName = "Tyranitar (Shadow)"
        XCTAssertEqual(f.asNameLabel(shadow: true), "Tyranitar (Shadow)", "not doubled")
        f.asName = nil
        XCTAssertNil(f.asNameLabel(shadow: true))
    }

    func testAChipKeepsStrongAndOkCopies() {
        let es = [entry("a", "Eevee"), entry("b", "Eevee")]
        let strong = BoxAdvice.Fit(area: "raids", tag: .strong, asName: "Tyranitar", tier: "S", reason: nil, species: nil, ivPercent: 90)
        let weak = BoxAdvice.Fit(area: "raids", tag: .weak, asName: nil, tier: nil, reason: BoxAdvice.Fit.Reason.iv, species: nil, ivPercent: 50)
        let okMax = BoxAdvice.Fit(area: "max", tag: .ok, asName: "Blissey", tier: "A", reason: nil, species: nil, ivPercent: 90)
        let adv = advice(["a": ["gl": R(options: [option("flareon", score: 93, pct: 97, rankPct: 95)])]],
                         fit: ["a": ["raids": strong, "max": okMax], "b": ["raids": weak]])
        let insight = BoxInsight.make(advice: adv, entries: es)
        XCTAssertEqual(insight.worth(of: "a", .raids, pogoAssist: false), .strong)
        XCTAssertEqual(insight.worth(of: "b", .raids, pogoAssist: false), .weak)
        XCTAssertNil(insight.worth(of: "b", .gym, pogoAssist: false), "no fit for the area: no tag")
        XCTAssertTrue(insight.copies["a"]!.suits(.raids, pogoAssist: false))
        XCTAssertTrue(insight.copies["a"]!.suits(.max, pogoAssist: false), "OK counts")
        XCTAssertFalse(insight.copies["b"]!.suits(.raids, pogoAssist: false))
        XCTAssertTrue(insight.copies["a"]!.suits(.gl, pogoAssist: true))
        XCTAssertFalse(insight.copies["b"]!.suits(.gl, pogoAssist: true), "no league rating")
    }

    func testTheBuildChipNamesTheTargetWhenItIsNotTheCopy() {
        var f = BoxAdvice.Fit(area: "raids", tag: .ok, asName: "Blastoise", tier: "A", reason: nil, species: nil, ivPercent: 90)
        XCTAssertNil(f.buildsChipText(ownNames: ["Wartortle"]))
        f.build = true; f.buildAs = "Blastoise"
        XCTAssertEqual(f.buildsChipText(ownNames: ["Wartortle"]), "ADVICE BUILDS BLASTOISE")
        XCTAssertEqual(f.buildsChipText(ownNames: ["Blastoise"]), "ADVICE BUILDS IT")
        f.buildAs = "Blastoise (Shadow)"
        XCTAssertEqual(f.buildsChipText(ownNames: ["blastoise"]), "ADVICE BUILDS IT")
    }

    func testTheRealEnginesCopiesGetTilesAndTags() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let csv = try String(contentsOf: root.appendingPathComponent("fixtures/greg-2026-09-25.pokegenie.csv"), encoding: .utf8)
        let box = try sharedEngine.importPokeGenie(csv: csv)
        let report = try CoreEngine().advise(box: box)
        let es = (try XCTUnwrap(box.arrayValue)).enumerated().map { i, rec -> BoxEntry in
            var name = "?"; if case .string(let n)? = rec["name"] { name = n }
            let row = ScanRow(index: i + 1, name: name, display: name, form: "", speciesId: "", dex: nil, cp: 0, hp: nil, ivs: nil, ivsRead: nil, ivsGuess: nil,
                              level: nil, levelMax: nil, dust: nil, solveStatus: "exact", flags: [], frames: [])
            return BoxEntry(id: "e\(i)", row: row, firstSeen: date, lastSeen: date)
        }
        let advice = BoxAdvice.make(from: report, entries: es)
        let insight = BoxInsight.make(advice: advice, entries: es)
        XCTAssertEqual(insight.copies.count, 311)
        // Every copy's slot is the pick card's, under both rankings.
        for e in es {
            let ratings = advice.leagues(for: e.id)
            for (l, key) in LeaguePanel.keys.enumerated() {
                guard let r = ratings[key] else { XCTAssertNil(insight.copies[e.id]?.slots[l]); continue }
                for assist in [false, true] {
                    let c = LeaguePanel.card(r, shown: LeaguePanel.shownIndex(r, pogoAssist: assist), key: key, level: nil)
                    let s = try XCTUnwrap(insight.copies[e.id]?.slot(key, pogoAssist: assist))
                    XCTAssertEqual(s.worth, c.worth, e.id); XCTAssertEqual(s.pct, c.ivPct, e.id)
                }
            }
        }
        // Each tile reads from a copy of the species, and no copy of the species beats it.
        for (title, tiles) in insight.species {
            for (i, t) in tiles.enumerated() where t.status == .fits {
                let mine = es.filter { $0.row.title == title }
                // The best is Strong before OK before Weak, then the higher rank percentile.
                func key(_ s: LeaguePanel.Slot) -> [Double] { [Double(-BoxInsight.worthRank(s.worth)), s.rankPct ?? 0] }
                let fitting = mine.compactMap { insight.copies[$0.id]?.slots[i] }.filter { $0.status == .fits }
                let tile = try XCTUnwrap(insight.copies[try XCTUnwrap(t.copyId)]?.slots[i])
                XCTAssertTrue(fitting.allSatisfy { !key(tile).lexicographicallyPrecedes(key($0)) }, title)
            }
        }
        XCTAssertTrue(insight.species.values.contains { $0.contains { $0.status == .fits } }, "some tile has a value")
        XCTAssertTrue(es.contains { insight.copies[$0.id]?.suits(.raids, pogoAssist: false) == true })
    }

    // MARK: the lines and the best-of text live in the insight

    private func shadowEntry(_ id: String, _ title: String, shadow: Bool) -> BoxEntry {
        var e = entry(id, title)
        e.row.shadow = shadow ? 1 : 0
        return e
    }

    /// A species list rebuilt from the insight alone (the advice is being recalculated) still has every tag's line and every best-of area.
    func testTheInsightCarriesTheLinesAndTheBestOfAreas() {
        let es = [entry("a", "Tyranitar")]
        let fit = BoxAdvice.Fit(area: "raids", tag: .ok, asName: "Tyranitar", tier: "A", reason: nil, species: nil, ivPercent: 98)
        var adv = advice(["a": ["gl": R(options: [option("flareon", score: 93, pct: 97.2, rankPct: 95)])]], fit: ["a": ["raids": fit]])
        adv.bestOf = ["a": ["raids"]]
        let insight = BoxInsight.make(advice: adv, entries: es)
        XCTAssertEqual(insight.copies["a"]?.line(.raids, pogoAssist: false), fit.line)
        XCTAssertNil(insight.copies["a"]?.line(.gym, pogoAssist: false), "no tag, no line")
        let r = adv.leagues(for: "a")["gl"]!
        let c = LeaguePanel.card(r, shown: LeaguePanel.shownIndex(r, pogoAssist: false), key: "gl", level: nil)
        XCTAssertEqual(insight.copies["a"]?.line(.gl, pogoAssist: false), LeaguePanel.worthSentence(c, key: "gl") ?? c.blockedText)
        XCTAssertNotNil(insight.copies["a"]?.line(.gl, pogoAssist: true))
        XCTAssertEqual(insight.copies["a"]?.best, [.init(area: "raids", asName: "Tyranitar")])
    }

    /// The merged chip names what the copy is best as, not a count: a plain and a Shadow copy of one title are each their own best, and their chips differ by the suffix.
    func testTheMergedChipTextNamesTheBestAsAndTellsPlainFromShadow() {
        let es = [shadowEntry("p", "Tyranitar", shadow: false), shadowEntry("s", "Tyranitar", shadow: true)]
        func fit() -> BoxAdvice.Fit { BoxAdvice.Fit(area: "raids", tag: .ok, asName: "Tyranitar", tier: "A", reason: nil, species: nil, ivPercent: 98) }
        var adv = advice(["p": ["gl": R(options: [option("flareon", score: 93, pct: 97.2, rankPct: 95)])]], fit: ["p": ["raids": fit()], "s": ["raids": fit()]])
        adv.bestOf = ["p": ["raids"], "s": ["raids"]]
        let insight = BoxInsight.make(advice: adv, entries: es)
        XCTAssertEqual(insight.bestText(of: "p", title: "Tyranitar", .raids, pogoAssist: false), "best as Tyranitar")
        XCTAssertEqual(insight.bestText(of: "s", title: "Tyranitar", .raids, pogoAssist: false), "best as Tyranitar (Shadow)")
        XCTAssertNil(insight.bestText(of: "p", title: "Tyranitar", .gym, pogoAssist: false), "not best for Gym")
        // An engine name that already says Shadow gets no second suffix.
        var named = fit(); named.asName = "Tyranitar (Shadow)"
        adv.fit["s"] = ["raids": named]
        XCTAssertEqual(BoxInsight.make(advice: adv, entries: es).bestText(of: "s", title: "Tyranitar", .raids, pogoAssist: false), "best as Tyranitar (Shadow)")
        // A league chip keeps the member and the roll.
        XCTAssertEqual(insight.bestText(of: "p", title: "Tyranitar", .gl, pogoAssist: false), "best: Flareon 97.2%")
        XCTAssertNil(insight.bestText(of: "s", title: "Tyranitar", .gl, pogoAssist: false), "the tile is another copy's")
    }

    /// Max has no "as" name; its merged chip keeps the caveat that the copy must be Dynamaxed.
    func testTheMaxMergedChipKeepsTheDynamaxCaveat() {
        let es = [shadowEntry("m", "Charizard", shadow: false)]
        let fit = BoxAdvice.Fit(area: "max", tag: .ok, asName: nil, tier: "A", reason: nil, species: nil, ivPercent: 98)
        var adv = advice(["m": ["gl": R(options: [option("flareon", score: 93, pct: 97.2, rankPct: 95)])]], fit: ["m": ["max": fit]])
        adv.bestOf = ["m": ["max"]]
        XCTAssertEqual(BoxInsight.make(advice: adv, entries: es).bestText(of: "m", title: "Charizard", .max, pogoAssist: false), "best (needs a Dynamax copy)")
    }
}
