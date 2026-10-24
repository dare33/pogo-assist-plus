import XCTest
import SwiftUI
@testable import PogoAssist
@testable import PogoBox
import PogoReader

/// The Pokémon list's insight store, key and filter, which have no screen of their own to drive: the three advice states, what an account switch and a box edit do
/// to the tags on show, the ranking side of the activity chips, and the tile wording.
@MainActor
final class BoxInsightStoreTests: XCTestCase {
    typealias R = BoxAdvice.LeagueRating
    typealias O = R.Option

    private func option(_ id: String, score: Double? = nil, pct: Double? = nil, rankPct: Double = 90, over: Bool = false) -> O {
        O(speciesId: id, name: id.capitalized, isSelf: false, genderLocked: nil, strength: score.map { .init(score: $0, rank: 10, of: 1152) }, moves: nil, needs: nil,
          iv: pct.map { .init(rank: 100, pct: $0, rankPct: rankPct, level: 20, cp: 1490) }, overCap: over, cost: nil)
    }
    private var date: Date { Date(timeIntervalSince1970: 1_790_000_000) }
    private func entry(_ id: String, _ title: String, ivs: IVs? = IVs(atk: 15, def: 15, hp: 15)) -> BoxEntry {
        let row = ScanRow(index: 1, name: title, display: title, form: "", speciesId: title.lowercased(), dex: nil, cp: 1400, hp: 100, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                          level: 20, levelMax: nil, dust: nil, solveStatus: "exact", flags: [], frames: [])
        return BoxEntry(id: id, row: row, firstSeen: date, lastSeen: date)
    }
    private func advice(_ leagues: [String: [String: R]]) -> BoxAdvice {
        var a = BoxAdvice(builds: [], gaps: [], duplicates: [], unresolved: [])
        a.leagues = leagues
        return a
    }
    private func oneCopy() -> (BoxAdvice, [BoxEntry]) {
        (advice(["a": ["gl": R(options: [option("flareon", score: 93, pct: 97, rankPct: 95)])]]), [entry("a", "Eevee")])
    }

    // MARK: the key

    func testTheKeyHasThreeAdviceStates() {
        XCTAssertEqual(InsightKey.State(.none), .waiting)
        XCTAssertEqual(InsightKey.State(.computing), .waiting)
        XCTAssertEqual(InsightKey.State(.failed("no")), .failed)
        XCTAssertEqual(InsightKey.State(.ready(advice([:]))), .ready)
        let waiting = InsightKey(account: "Greg", seq: 3, state: .waiting)
        XCTAssertNotEqual(waiting, InsightKey(account: "Greg", seq: 3, state: .failed), "failed is not waiting: the list must not say \"Working out advice…\" for ever")
        XCTAssertNotEqual(waiting, InsightKey(account: "Greg", seq: 3, state: .ready))
        XCTAssertNotEqual(waiting, InsightKey(account: "Greg", seq: 4, state: .waiting))
        XCTAssertNotEqual(waiting, InsightKey(account: "Other", seq: 3, state: .waiting))
        XCTAssertEqual(InsightKey(account: nil, seq: nil, state: .waiting), InsightKey(account: "", seq: -1, state: .waiting))
    }

    // MARK: the store

    func testAFailedAdviceDropsTheInsightAndAWaitingOneDoesNot() async {
        let store = BoxIndexStore(), (adv, es) = oneCopy()
        await store.refreshInsight(key: InsightKey(account: "A", seq: 1, state: .ready), advice: adv, entries: es)
        XCTAssertNotNil(store.insight)
        await store.refreshInsight(key: InsightKey(account: "A", seq: 2, state: .waiting), advice: nil, entries: es)
        XCTAssertNotNil(store.insight, "a hand fix or a saved scan: the previous insight stays while the new one is built")
        await store.refreshInsight(key: InsightKey(account: "A", seq: 2, state: .failed), advice: nil, entries: es)
        XCTAssertNil(store.insight, "nothing can be said about a box version whose advice failed")
        await store.refreshInsight(key: InsightKey(account: "A", seq: 3, state: .ready), advice: adv, entries: es)
        XCTAssertNotNil(store.insight, "and a later advice builds again")
    }

    func testAnotherAccountsInsightNeverShows() async {
        let store = BoxIndexStore(), (adv, es) = oneCopy()
        await store.refreshInsight(key: InsightKey(account: "A", seq: 1, state: .ready), advice: adv, entries: es)
        let before = store.insightVersion
        await store.refreshInsight(key: InsightKey(account: "B", seq: 1, state: .waiting), advice: nil, entries: es)
        XCTAssertNil(store.insight, "the account part of the key changed: B's list must not carry A's tags or tiles")
        XCTAssertGreaterThan(store.insightVersion, before, "and the list recomputes")
        // Back to A while its advice is still being worked out: B's (nothing here) is not carried over either, and a ready advice builds.
        await store.refreshInsight(key: InsightKey(account: "A", seq: 1, state: .ready), advice: adv, entries: es)
        XCTAssertNotNil(store.insight)
        await store.refreshInsight(key: InsightKey(account: "B", seq: 1, state: .ready), advice: advice([:]), entries: [])
        XCTAssertNil(store.insight?.copies["a"], "B's own insight replaces A's")
    }

    func testABoxEditKeepsTheInsightOnShowUntilTheNewOneIsBuilt() async {
        let store = BoxIndexStore(), (adv, es) = oneCopy()
        await store.refreshInsight(key: InsightKey(account: "A", seq: 1, state: .ready), advice: adv, entries: es)
        let before = store.insightVersion
        await store.refreshInsight(key: InsightKey(account: "A", seq: 2, state: .waiting), advice: nil, entries: es)
        XCTAssertEqual(store.insight?.copies["a"]?.slot("gl", pogoAssist: false)?.worth, .strong)
        XCTAssertEqual(store.insightVersion, before, "nothing to redraw while the old insight stays")
        let edited = advice(["a": ["gl": R(options: [option("flareon", score: 70, pct: 97, rankPct: 95)])]])
        await store.refreshInsight(key: InsightKey(account: "A", seq: 2, state: .ready), advice: edited, entries: es)
        XCTAssertEqual(store.insight?.copies["a"]?.slot("gl", pogoAssist: false)?.worth, .weak, "the new one replaces it")
    }

    // MARK: the ranking side of the filter

    /// "x" is Strong for Great League only under the Pogo Assist ranking, "y" only under Classic.
    func testTheActivityChipFollowsTheRanking() {
        func two(classic: O, assist: O) -> R { R(options: [classic, assist], pick: 0, experimental: 1) }
        let adv = advice([
            "x": ["gl": two(classic: option("flareon", score: 70, pct: 90, rankPct: 90), assist: option("umbreon", score: 93, pct: 90, rankPct: 90))],
            "y": ["gl": two(classic: option("flareon", score: 93, pct: 90, rankPct: 90), assist: option("umbreon", score: 70, pct: 90, rankPct: 90))],
        ])
        let entries = [entry("x", "Xatu"), entry("y", "Yanma")]
        let index = BoxIndex(entries: entries)
        let insight = BoxInsight.make(advice: adv, entries: entries)
        func titles(_ assist: Bool) -> [String] {
            index.sections(query: .none, chip: .activity(.gl), sort: .name, scoring: .init(insight: insight, pogoAssist: assist)).flatMap(\.rows).map(\.title)
        }
        XCTAssertEqual(titles(false), ["Yanma"])
        XCTAssertEqual(titles(true), ["Xatu"])
        XCTAssertTrue(index.matches(index.items[0], .none, .activity(.gl), .init(insight: insight, pogoAssist: true)))
        XCTAssertFalse(index.matches(index.items[0], .none, .activity(.gl), .init(insight: insight, pogoAssist: false)))
        XCTAssertTrue(titles(false).count == 1 && index.sections(query: .none, chip: .activity(.gl), sort: .name, scoring: .init(insight: insight, pogoAssist: false)).flatMap(\.rows).first?.lead == .strong)
        XCTAssertTrue(index.sections(query: .none, chip: .activity(.gl), sort: .name, scoring: .none).isEmpty, "no insight: nothing is Strong or OK yet")
    }

    // MARK: the tiles

    func testTheTileWordsForEveryStatus() {
        let fits = BoxInsight.Tile(status: .fits, member: "Flareon", pct: 97.2, copyId: "a")
        XCTAssertEqual(LeagueTiles.line(fits, waiting: false), "Flareon")
        XCTAssertEqual(LeagueTiles.line(BoxInsight.Tile(status: .ivsNotRead, member: "Flareon", pct: nil, copyId: nil), waiting: false), "IVs not read")
        XCTAssertEqual(LeagueTiles.line(BoxInsight.Tile(status: .overCap, member: "Pidgeot", pct: nil, copyId: nil), waiting: false), "Over cap")
        XCTAssertEqual(LeagueTiles.line(BoxInsight.Tile(status: .noData, member: "", pct: nil, copyId: nil), waiting: false), "—")
        XCTAssertEqual(LeagueTiles.line(nil, waiting: false), "—", "a failed advice has no tiles: the dash")
        XCTAssertEqual(LeagueTiles.line(nil, waiting: true), "…", "still being worked out")
        XCTAssertEqual(LeagueTiles.line(fits, waiting: true), "Flareon", "an older insight kept on show while the new one is built keeps its values")
    }

    func testTheTilesStackFromTheAccessibilitySizes() {
        for size in DynamicTypeSize.allCases { XCTAssertEqual(LeagueTiles.stacked(size), size >= .accessibility1, "\(size)") }
    }

    func testTheTagWordsForEachWorth() {
        XCTAssertEqual(WorthTag.detail(.ok, bestOf: 6), "OK · best of 6")
        XCTAssertEqual(WorthTag.detail(.strong, bestOf: nil), "Strong")
        XCTAssertEqual(WorthTag.detail(.weak, bestOf: nil), "Weak")
        XCTAssertEqual(WorthTag.detail(nil, bestOf: nil), "Not rated", "a copy with no fit for the area")
    }

    func testAnUnreadCopyGivesTheIVsNotReadTile() {
        let entries = [entry("c", "Eevee", ivs: nil)]
        let insight = BoxInsight.make(advice: advice(["c": ["gl": R(options: [option("flareon", score: 70)])]]), entries: entries)
        let tile = insight.tile(title: "Eevee", league: "gl", pogoAssist: false)
        XCTAssertEqual(tile?.status, .ivsNotRead)
        XCTAssertEqual(LeagueTiles.line(tile, waiting: false), "IVs not read")
        XCTAssertNil(LeagueTiles.percent(tile))
        XCTAssertTrue(LeagueTiles.spoken(title: "Eevee", insight: insight, waiting: false, pogoAssist: false).contains("Great League: IVs not read"))
        XCTAssertTrue(LeagueTiles.spoken(title: "Eevee", insight: nil, waiting: false, pogoAssist: false).contains("Great League: —"))
    }
}
