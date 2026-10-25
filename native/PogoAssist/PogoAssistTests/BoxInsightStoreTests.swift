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
        XCTAssertTrue(index.sections(query: .none, chip: .activity(.gl), sort: .name, scoring: .none).isEmpty, "no insight: nothing is Top or Good yet")
    }

    // MARK: the species page's cards

    /// Two Eevee copies, both rated for Great League as Flareon; "b" is the better roll. A third is rated as Eevee itself, so its card has nothing to add.
    private func twoCopies() -> (BoxInsight, [BoxEntry]) {
        let es = [entry("a", "Eevee"), entry("b", "Eevee")]
        let adv = advice(["a": ["gl": R(options: [option("flareon", score: 93, pct: 90, rankPct: 80)])], "b": ["gl": R(options: [option("flareon", score: 93, pct: 99, rankPct: 98)])]])
        return (BoxInsight.make(advice: adv, entries: es), es)
    }

    private func gl(_ cards: [BestCard]) -> BestCard? { cards.first(where: { (c: BestCard) in c.activity == BoxInsight.Activity.gl }) }

    func testACardReadsAsTheOtherPokemonOnlyWhenItDiffers() {
        let (insight, es) = twoCopies()
        let cards = BestCard.cards(title: "Eevee", insight: insight, index: BoxIndex(entries: es), pogoAssist: false)
        XCTAssertEqual(gl(cards)?.detail, "as Flareon")
        let same = BoxInsight.make(advice: advice(["a": ["gl": R(options: [option("eevee", score: 93, pct: 99, rankPct: 98)])]]), entries: [es[0]])
        let none = BestCard.cards(title: "Eevee", insight: same, index: BoxIndex(entries: [es[0]]), pogoAssist: false)
        XCTAssertNotNil(gl(none), "the card is there")
        XCTAssertNil(gl(none)?.detail, "\"as Eevee\" on Eevee's page is left out")
        let upper = BestCard.cards(title: "EEVEE", insight: same, index: BoxIndex(entries: [es[0]]), pogoAssist: false)
        XCTAssertNil(gl(upper)?.detail, "compared without regard to case")
        XCTAssertEqual(BestCard(activity: .gl, copyId: "a", cp: 1400, pct: 100, worth: .strong, detail: nil).spoken, "Great League, best: CP 1400, 100 percent, Top")
    }

    func testACardMovesOnWhenItsFirstCopyIsGoneFromTheIndex() {
        let (insight, es) = twoCopies()
        XCTAssertEqual(insight.top(title: "Eevee", .gl, pogoAssist: false).first, "b", "b is the first place")
        let rebuilt = BoxIndex(entries: [es[0]])   // the box has since lost b; the insight on show is still the old one
        let cards = BestCard.cards(title: "Eevee", insight: insight, index: rebuilt, pogoAssist: false)
        XCTAssertEqual(gl(cards)?.copyId, "a", "the card takes the next copy that is still there rather than vanishing")
        XCTAssertTrue(BestCard.cards(title: "Eevee", insight: insight, index: BoxIndex(entries: []), pogoAssist: false).isEmpty, "no copy left: no card")
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

    // MARK: results are kept to the key they were built for

    private func many(_ n: Int, prefix: String) -> [BoxEntry] { (0..<n).map { entry("\(prefix)\($0)", "Eevee") } }

    /// A big box builds its index off the main thread, and that work is not cancelled by the switch: A's result arriving after the switch to B must not replace B's.
    func testADetachedIndexForAccountAArrivingAfterTheSwitchToBIsDiscarded() async {
        let store = BoxIndexStore()
        let a = Task { await store.refresh(key: "A|1", entries: many(2_000, prefix: "a")) }   // not cancelled: only the key can discard it
        await Task.yield()
        await store.refresh(key: "B|1", entries: [entry("b", "Pidgey")])
        XCTAssertEqual(store.indexKey, "B|1")
        await a.value
        XCTAssertEqual(store.indexKey, "B|1", "A's finished index is not published over B's")
        XCTAssertEqual(store.index.count, 1)
        XCTAssertEqual(store.index.items.first?.id, "b")
    }

    func testADetachedInsightForAccountAArrivingAfterTheSwitchToBIsDiscarded() async {
        let store = BoxIndexStore(), (adv, _) = oneCopy()
        let a = Task { await store.refreshInsight(key: InsightKey(account: "A", seq: 1, state: .ready), advice: adv, entries: many(2_000, prefix: "a")) }
        await Task.yield()
        await store.refreshInsight(key: InsightKey(account: "B", seq: 1, state: .waiting), advice: nil, entries: [])
        await a.value
        XCTAssertNil(store.insight, "A's insight is not published once B is the key")
        XCTAssertNil(store.insightBuiltFor)
        XCTAssertNil(store.insight(forAccount: "B"))
        // A box edit of the same account does the same: the build for the older version does not land on the newer one.
        let b = Task { await store.refreshInsight(key: InsightKey(account: "B", seq: 2, state: .ready), advice: adv, entries: many(2_000, prefix: "b")) }
        await Task.yield()
        await store.refreshInsight(key: InsightKey(account: "B", seq: 3, state: .waiting), advice: nil, entries: [])
        await b.value
        XCTAssertNil(store.insight)
    }

    /// A ready, built; B asked for and its build left to be cancelled; then A again: A's insight must be built and published afresh (it was dropped at the switch).
    func testAToBackToAIsRebuiltWhenBsBuildWasCancelled() async {
        let store = BoxIndexStore(), (adv, es) = oneCopy()
        let a = InsightKey(account: "A", seq: 1, state: .ready), b = InsightKey(account: "B", seq: 1, state: .ready)
        await store.refreshInsight(key: a, advice: adv, entries: es)
        XCTAssertEqual(store.insightBuiltFor, a)
        let task = Task { await store.refreshInsight(key: b, advice: adv, entries: many(2_000, prefix: "b")) }
        await Task.yield()
        task.cancel()
        await task.value
        XCTAssertNil(store.insight, "B's build was cancelled and A's insight was dropped at the switch")
        await store.refreshInsight(key: a, advice: adv, entries: es)
        XCTAssertEqual(store.insightBuiltFor, a, "A is built again, not left waiting")
        XCTAssertNotNil(store.insight(forAccount: "A"))
    }

    /// The index path never drops a published index, so A's stays while B is requested (even with B's build cancelled) and A's second request returns early:
    /// this checks that the index is kept and returned without a rebuild, not that it is rebuilt.
    func testTheIndexOfAIsKeptWhileBIsRequestedAndReturnedWithoutARebuild() async {
        let store = BoxIndexStore()
        await store.refresh(key: "A|1", entries: [entry("a", "Eevee")])
        let published = store.index, versionBefore = store.version
        let task = Task { await store.refresh(key: "B|1", entries: many(2_000, prefix: "b")) }
        await Task.yield()
        task.cancel()
        await task.value
        XCTAssertEqual(store.indexKey, "A|1", "B's cancelled build did not publish and A's index was not dropped")
        await store.refresh(key: "A|1", entries: [entry("a", "Eevee")])
        XCTAssertEqual(store.indexKey, "A|1")
        XCTAssertEqual(store.version, versionBefore, "no rebuild: the version is unchanged after the round trip")
        XCTAssertEqual(store.index.items.map(\.id), published.items.map(\.id))
        XCTAssertEqual(store.index.items.first?.id, "a")
    }

    /// An older build for the same key, not cancelled, finishing after a newer request for it: only the newer publishes, and the older is discarded by its generation.
    func testAnOlderBuildOfTheSameKeyFinishingAfterANewerRequestIsDiscarded() async {
        let store = BoxIndexStore(), (adv, _) = oneCopy()
        let key = InsightKey(account: "A", seq: 1, state: .ready)
        let started = expectation(description: "older build started")
        store.onBuildStarted = { started.fulfill() }
        let older = Task { await store.refreshInsight(key: key, advice: adv, entries: many(2_000, prefix: "old")) }
        await fulfillment(of: [started], timeout: 10)   // the older detached build is under way before the newer request is made
        store.onBuildStarted = nil
        await store.refreshInsight(key: key, advice: adv, entries: [entry("new", "Eevee")])
        let versionAfterNewer = store.insightVersion
        await older.value
        XCTAssertEqual(store.insightVersion, versionAfterNewer, "the older build did not publish")
        XCTAssertNotNil(store.insight?.copies["new"], "the newer build is the one on show")
        XCTAssertNil(store.insight?.copies["old0"])
    }

    /// The same key: an older detached build of "A|1" under way, then `install` (which bumps the generation) for "A|1": the older result is discarded.
    func testAnOlderIndexOfTheSameKeyFinishingAfterANewerInstallIsDiscarded() async {
        let store = BoxIndexStore()
        let started = expectation(description: "older build started")
        store.onBuildStarted = { started.fulfill() }
        let older = Task { await store.refresh(key: "A|1", entries: many(2_000, prefix: "old")) }
        await fulfillment(of: [started], timeout: 10)
        store.onBuildStarted = nil
        store.install(BoxIndex(entries: [entry("new", "Eevee")]), key: "A|1")
        let versionAfterNewer = store.version
        await older.value
        XCTAssertEqual(store.version, versionAfterNewer, "the older build did not publish")
        XCTAssertEqual(store.indexKey, "A|1")
        XCTAssertEqual(store.index.items.first?.id, "new")
        XCTAssertEqual(store.index.count, 1)
    }

    /// The same key requested again while the older build is under way: the newer request returns early (the key is not yet published), so it builds too and
    /// publishes first (small box, synchronous); the older, taken before it, is discarded by its generation.
    func testAnOlderIndexOfTheSameKeyFinishingAfterANewerRequestForItIsDiscarded() async {
        let store = BoxIndexStore()
        let started = expectation(description: "older build started")
        store.onBuildStarted = { started.fulfill() }
        let older = Task { await store.refresh(key: "A|1", entries: many(2_000, prefix: "old")) }
        await fulfillment(of: [started], timeout: 10)
        store.onBuildStarted = nil
        await store.refresh(key: "A|1", entries: [entry("new", "Eevee")])
        let versionAfterNewer = store.version
        await older.value
        XCTAssertEqual(store.version, versionAfterNewer, "the older build did not publish")
        XCTAssertEqual(store.index.items.first?.id, "new")
        XCTAssertEqual(store.index.count, 1)
    }

    /// A different key ("A|1" then "A|2"): the older, detached build is discarded.
    func testAnOlderIndexOfAnotherKeyFinishingAfterANewerRequestIsDiscarded() async {
        let store = BoxIndexStore()
        let started = expectation(description: "older build started")
        store.onBuildStarted = { started.fulfill() }
        let older = Task { await store.refresh(key: "A|1", entries: many(2_000, prefix: "old")) }
        await fulfillment(of: [started], timeout: 10)
        store.onBuildStarted = nil
        await store.refresh(key: "A|2", entries: [entry("new", "Eevee")])
        await older.value
        XCTAssertEqual(store.indexKey, "A|2")
        XCTAssertEqual(store.index.items.first?.id, "new")
        XCTAssertEqual(store.index.count, 1)
    }

    func testTheInsightIsReadOnlyForTheAccountItWasBuiltFor() async {
        let store = BoxIndexStore(), (adv, es) = oneCopy()
        await store.refreshInsight(key: InsightKey(account: "A", seq: 1, state: .ready), advice: adv, entries: es)
        XCTAssertNotNil(store.insight(forAccount: "A"))
        XCTAssertNil(store.insight(forAccount: "B"), "the view has switched to B before the store has: B must not read A's tags")
        XCTAssertEqual(store.insightBuiltFor, InsightKey(account: "A", seq: 1, state: .ready))
    }

    /// The sections on a screen are the ones computed for its account and box version; those of the previous account stay in memory but are not shown, while a stale box version of the same account stays visible until the new sections arrive.
    func testSectionsWithAStaleKeyAreNotShown() {
        XCTAssertTrue(BoxView.showsSections(computedFor: "A|1", current: "A|1"))
        XCTAssertFalse(BoxView.showsSections(computedFor: "A|1", current: "B|1"), "another account's")
        XCTAssertTrue(BoxView.showsSections(computedFor: "A|1", current: "A|2"), "an older box version of the same account stays visible")
        XCTAssertFalse(BoxView.showsSections(computedFor: nil, current: "A|1"), "nothing computed yet")
    }

    // MARK: waiting

    /// Cached advice at launch, or after a switch: the key is ready while the insight is not built yet. That is waiting ("…", "Working out…"), not "—".
    func testReadyAdviceWithoutItsInsightIsWaiting() async {
        let ready = InsightKey(account: "A", seq: 1, state: .ready)
        XCTAssertTrue(ready.isWaiting(builtFor: nil), "cached advice at launch")
        XCTAssertTrue(ready.isWaiting(builtFor: InsightKey(account: "A", seq: 0, state: .ready)), "an older version's insight is on show while this one is built")
        XCTAssertTrue(ready.isWaiting(builtFor: InsightKey(account: "B", seq: 1, state: .ready)), "another account's")
        XCTAssertFalse(ready.isWaiting(builtFor: ready), "built for this key")
        XCTAssertTrue(InsightKey(account: "A", seq: 1, state: .waiting).isWaiting(builtFor: nil))
        XCTAssertFalse(InsightKey(account: "A", seq: 1, state: .failed).isWaiting(builtFor: nil), "a failed advice never arrives")
        // Through the store: waiting until the build lands, then not.
        let store = BoxIndexStore(), (adv, es) = oneCopy()
        XCTAssertTrue(ready.isWaiting(builtFor: store.insightBuiltFor))
        await store.refreshInsight(key: ready, advice: adv, entries: es)
        XCTAssertFalse(ready.isWaiting(builtFor: store.insightBuiltFor))
        XCTAssertEqual(LeagueTiles.line(nil, waiting: ready.isWaiting(builtFor: nil)), "…")
    }

    // MARK: the tag lines live in the insight

    /// A hand fix recalculates the advice (`.computing`) while the previous insight stays on show: its tags still have their lines and best-of areas, because they
    /// are kept in the insight, not read from the advice.
    func testATagStillHasItsLineWhileTheAdviceIsRecalculated() async {
        let fit = BoxAdvice.Fit(area: "raids", tag: .ok, asName: "Eevee", tier: "A", reason: nil, species: nil, ivPercent: 98)
        var adv = advice(["a": ["gl": R(options: [option("flareon", score: 93, pct: 97, rankPct: 95)])]])
        adv.fit = ["a": ["raids": fit]]; adv.bestOf = ["a": ["raids"]]
        let store = BoxIndexStore(), es = [entry("a", "Eevee")]
        await store.refreshInsight(key: InsightKey(account: "A", seq: 1, state: .ready), advice: adv, entries: es)
        // The advice for the edited version is being worked out: the key is waiting, the insight is kept.
        let recalculating = InsightKey(account: "A", seq: 2, state: InsightKey.State(.computing))
        await store.refreshInsight(key: recalculating, advice: nil, entries: es)
        let insight = store.insight(forAccount: "A")
        XCTAssertNotNil(insight)
        XCTAssertEqual(insight?.copies["a"]?.line(.raids, pogoAssist: false), fit.line, "the activity tag's line")
        XCTAssertNotNil(insight?.copies["a"]?.line(.gl, pogoAssist: false), "the league tag's line")
        XCTAssertEqual(insight?.bestText(of: "a", title: "Eevee", .raids, pogoAssist: false), "best as Eevee", "the best-of area is kept too")
        XCTAssertEqual(insight?.copies["a"]?.best.map(\.area), ["raids"])
    }
}

/// Colour rules that have no screen of their own: Max is a pink, and the lighter middle rating on the Pokémon page keeps its text readable in both appearances.
final class ListTagColourTests: XCTestCase {
    private func resolve(_ c: Color, _ dark: Bool) -> (r: Double, g: Double, b: Double, a: Double) {
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
    private func lum(_ c: (r: Double, g: Double, b: Double, a: Double)) -> Double {
        func f(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
    }
    private func over(_ top: (r: Double, g: Double, b: Double, a: Double), _ base: (r: Double, g: Double, b: Double, a: Double), opacity: Double = 1) -> (r: Double, g: Double, b: Double, a: Double) {
        let a = top.a * opacity
        return (top.r * a + base.r * (1 - a), top.g * a + base.g * (1 - a), top.b * a + base.b * (1 - a), 1)
    }
    private func ratio(_ a: (r: Double, g: Double, b: Double, a: Double), _ b: (r: Double, g: Double, b: Double, a: Double)) -> Double {
        let (x, y) = (lum(a), lum(b)); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testMaxIsAPinkNotThePurpleItWas() {
        for dark in [false, true] {
            let ink = resolve(ContentType.max.ink(.blue), dark), purple = resolve(Theme.changeInk, dark)
            XCTAssertGreaterThan(ink.r, ink.g, "red over green: pink")
            XCTAssertGreaterThan(ink.r, ink.b - 0.05, "red at least as strong as blue, where the purple's blue led")
            XCTAssertGreaterThan(purple.b, purple.r, "the change purple is still the change purple")
        }
        XCTAssertGreaterThanOrEqual(Theme.contrast(0xFFFFFF, Theme.maxInkLight), 4.5, "white on the Max ink")
        for dark in [false, true] {
            let surface = resolve(Theme.surface, dark)
            let tint = over(resolve(ContentType.max.tint(.blue), dark), surface)
            XCTAssertGreaterThanOrEqual(ratio(resolve(ContentType.max.ink(.blue), dark), tint), 4.5, "Max ink on its tint, dark \(dark)")
        }
    }

    /// The three tags' text on the ground each draws, over the page's surface, both appearances, every activity and every accent the app offers (page, list rows and
    /// species page share `WorthTag`): Top is the ink on the full tint, Good the same ink on the lighter tint, Weak the muted text on no fill. The card's green is checked too.
    /// Good is pinned through `WorthTag.style(for:)`, which the tag and the league card's chip both read: a smaller tint strength than Top's, a border Top lacks, Weak untouched,
    /// so a change to that function fails here. That the views apply it is by their sharing it; the contrast checks below use its tint strength.
    func testTheThreeRatingsKeepFourAndAHalfToOneAndGoodStaysLighter() {
        let activities = BoxInsight.Activity.allCases   // every tag the lists and the page draw, the leagues in their own colours
        let top = WorthTag.style(for: .strong), good = WorthTag.style(for: .ok), weak = WorthTag.style(for: .weak)
        XCTAssertLessThan(good.tintOpacity, top.tintOpacity, "Good's tint is weaker than Top's")
        XCTAssertNotNil(good.borderOpacity, "Good carries a border")
        XCTAssertGreaterThan(good.borderOpacity ?? 0, 0, "Good's border is visible")
        XCTAssertNil(top.borderOpacity, "Top has no border")
        XCTAssertEqual(weak.tintOpacity, 1, "Weak keeps its own fill")
        XCTAssertNil(weak.borderOpacity, "Weak has no faded border")
        // The page's rows and the species page's cards: the same ground under the chip, so a chip reads on a card as it does on a row.
        for (where_, ground) in [("row", Theme.surface), ("card", BestCard.ground)] {
          for dark in [false, true] {
            let surface = resolve(ground, dark)
            XCTAssertGreaterThanOrEqual(ratio(resolve(Theme.muted, dark), surface), 4.5, "Weak: muted text on the \(where_), dark \(dark)")
            for accent in Accent.allCases {
                for a in activities {
                    let ink = resolve(a.ink(accent), dark), full = over(resolve(a.tint(accent), dark), surface)
                    let good = over(resolve(a.tint(accent), dark), surface, opacity: good.tintOpacity)
                    XCTAssertGreaterThanOrEqual(ratio(ink, full), 4.5, "Top on a \(where_): \(a) \(accent) dark \(dark)")
                    XCTAssertGreaterThanOrEqual(ratio(ink, good), 4.5, "Good on a \(where_): \(a) \(accent) dark \(dark)")
                    XCTAssertGreaterThan(ratio(ink, good), ratio(ink, full) - 0.0001, "Good's lighter ground gives the ink no less contrast than Top's: \(a) \(accent) dark \(dark)")
                    // The chip's shape must show against the card: Top's tint is not the ground (the card is no longer tinted), and the outline is the activity's ink.
                    XCTAssertGreaterThanOrEqual(ratio(full, surface), 1.05, "Top's tint is told from the \(where_) ground: \(a) \(accent) dark \(dark)")
                    XCTAssertGreaterThanOrEqual(ratio(ink, surface), 3, "the card's 2 pt outline in the ink shows on the ground: \(a) \(accent) dark \(dark)")
                }
            }
          }
        }
        for dark in [false, true] {
            let surface = resolve(Theme.surface, dark)
            let tint = resolve(Theme.greenTint, dark), base = resolve(Theme.surface2, dark)
            XCTAssertGreaterThanOrEqual(ratio(resolve(Theme.greenInk, dark), over(tint, base)), 4.5, "league card Top, dark \(dark)")
            XCTAssertGreaterThanOrEqual(ratio(resolve(Theme.greenInk, dark), over(tint, base, opacity: good.tintOpacity)), 4.5, "league card Good, dark \(dark)")
        }
    }
}
