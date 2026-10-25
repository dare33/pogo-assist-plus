import XCTest
@testable import PogoBox
import PogoReader

/// Round 1 of the paired review: one test per ruling (F1 to F15), each failing without its fix.
final class ReviewFoldTests: XCTestCase {
    private typealias A = PokemonActivities
    private let gm = P23.gm
    private let hundo = IVs(atk: 15, def: 15, hp: 15)

    // MARK: F1: Gym level read or not is the copy's own

    private var gymTable: TierTable { P23.table([P23.tierEntry("gym", "Tiers", "S", "blissey"), P23.tierEntry("gym", "Tiers", "B", "chansey")]) }

    func testAnUnreadLevelStaysUnreadWhateverTheEnginesBuildSays() {
        // The engine fills `p.level ?? 20` into the build, and a target level of 30: the copy's own level (the entry) is nil.
        let unread = P23.entry("u", "blissey", ivs: hundo, level: nil), read = P23.entry("k", "blissey", ivs: IVs(atk: 0, def: 0, hp: 0), level: 30)
        let ctx = P23.ctx(builds: [P23.build("u", "blissey", areas: ["Gym"], built: false, level: 20, targetLevel: 30), P23.build("k", "blissey", areas: ["Gym"], level: 30)],
                          entries: [unread, read], table: gymTable)
        let rows = HubSquads.gymRows(mode: .available, ctx: ctx)
        XCTAssertEqual(rows.map { $0.build.entryId }, ["k", "u"], "the unread copy ranks after the read one even though its IVs are better")
        XCTAssertEqual(rows[1].bulk, .levelNotRead); XCTAssertTrue(rows[1].levelNotRead); XCTAssertNil(rows[1].level)
        XCTAssertEqual(HubSquads.gymRows(mode: .available, ctx: P23.ctx(builds: [P23.build("u", "blissey", areas: ["Gym"], level: 20)], entries: [unread], table: gymTable))[0].bulk,
                       .levelNotRead, "built, too: the build's level 20 is not the copy's")
        // And it can never be the Pokémon page's top defender.
        let only = P23.ctx(builds: [P23.build("u", "blissey", areas: ["Gym"], built: false, level: 20, targetLevel: 30)], entries: [unread], table: gymTable)
        XCTAssertNil(A.topDefender(ctx: only))
    }

    // MARK: F2: the top defender is a copy

    func testTheUnbuiltTopDefendersOwnCopyReadsAsTheTopAndAnotherCopyDoesNot() {
        let top = P23.entry("t", "blissey", ivs: hundo, level: 30), other = P23.entry("o", "blissey", ivs: hundo, level: 30)
        let ctx = P23.ctx(builds: [P23.build("t", "blissey", areas: ["Gym"], built: false, level: 30, targetLevel: 40), P23.build("o", "blissey", areas: ["Gym"], level: 30)],
                          entries: [top, other], table: gymTable)
        let yardstick = A.topDefender(ctx: ctx)
        XCTAssertEqual(yardstick?.entryId, "t", "the target level 40 ranks the unbuilt copy first on pass 2's screen")
        XCTAssertEqual(yardstick?.bulk, PogoRules.bulk(target: "blissey", ivs: hundo, level: 30, gm: gm).value, "pass 3 works it at the CURRENT level")
        let mine = A.gymCards(copy: top, ctx: ctx, top: yardstick)[0], theirs = A.gymCards(copy: other, ctx: ctx, top: yardstick)[0]
        XCTAssertTrue(mine.isTop); XCTAssertEqual(mine.share, 100)
        XCTAssertFalse(theirs.isTop, "same species, same share, not the top defender's copy"); XCTAssertEqual(theirs.share, 100)
    }

    // MARK: F3: Showcase by dex number

    func testShowcaseHoldsOneCopyPerDexNumberAcrossForms() {
        let box = [P23.entry("a", "pikachu", ivs: hundo, cp: 100), P23.entry("b", "pikachu_libre", ivs: hundo, cp: 200), P23.entry("c", "eevee", ivs: hundo, cp: 50)]
        XCTAssertEqual(HubCollection.showcase(entries: box, gm: gm).map(\.id), ["b", "c"], "Pikachu and Pikachu Libre are dex 25: the higher CP represents it")
    }

    // MARK: F4: saved picks and the mode

    func testASavedPickThatIsNotUsableAsItIsIsNotPlacedUnderAvailableAndReturnsUnderBest() {
        let table = P23.table([P23.tierEntry("raids", "Water", "S", "swampert_mega", mega: true), P23.tierEntry("raids", "Water", "A", "swampert")])
        let builds = [P23.build("mega", "swampert", areas: ["Raids"], powerUp: false, viaMega: true), P23.build("plain", "swampert", areas: ["Raids"])]
        let ctx = P23.ctx(builds: builds, entries: [P23.entry("mega", "swampert"), P23.entry("plain", "swampert")], table: table)
        let row = P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("charizard", types: ["fire"])])
        var slots = HubSquads.defaultRaidSlots(); slots[0].pick = "mega"
        func squad(_ mode: SquadMode) -> [FilledSlot] {
            HubSquads.raidSquad(slots: slots, candidates: HubSquads.raidCandidates(row: row, mode: mode, ctx: ctx), placeable: HubSquads.placeable(screen: .raids, mode: mode, ctx: ctx))
        }
        XCTAssertNil(squad(.available)[0].entryId, "Available has no Mega: the slot shows the suggestion (none)")
        XCTAssertEqual(slots[0].pick, "mega", "the pick stays in the store")
        XCTAssertEqual(squad(.best)[0].entryId, "mega"); XCTAssertTrue(squad(.best)[0].chosen)
        XCTAssertEqual(squad(.available)[1...].compactMap(\.entryId), ["plain"], "the plain copy is suggested instead")
        // An evolution-only Gym pick, both ways.
        let gym = P23.ctx(builds: [P23.build("x", "snorlax", areas: ["Gym"], powerUp: false), P23.build("y", "snorlax", areas: ["Gym"])], entries: [P23.entry("x", "snorlax"), P23.entry("y", "snorlax")])
        var g = HubSquads.defaultGymSlots(); g[0].pick = "x"
        func gsq(_ mode: SquadMode) -> [String?] {
            HubSquads.gymSquad(slots: g, rows: HubSquads.gymRows(mode: mode, ctx: gym), placeable: HubSquads.placeable(screen: .gym, mode: mode, ctx: gym)).map(\.entryId)
        }
        XCTAssertEqual(gsq(.available)[0], "y"); XCTAssertEqual(gsq(.best)[0], "x")
    }

    func testAPvpPickMustBeTheCopyItselfUnderAvailable() {
        let l = ["a": ["gl": P23.rating([P23.option("medicham", isSelf: false, score: 95)])], "b": ["gl": P23.rating([P23.option("azumarill", isSelf: true, score: 94)])]]
        let ctx = P23.ctx(leagues: l)
        let ok = HubSquads.placeable(screen: .pvp, mode: .available, league: "gl", ctx: ctx)
        XCTAssertFalse(ok("a", "Lead")); XCTAssertTrue(ok("b", "Lead")); XCTAssertFalse(ok("missing", "Lead"))
        XCTAssertTrue(HubSquads.placeable(screen: .pvp, mode: .best, league: "gl", ctx: ctx)("a", "Lead"))
    }

    // MARK: F5: Max Full strength is per copy

    func testMaxFullStrengthNeedsThisCopyMarkedNotAnotherOfTheSpecies() {
        let marked = P23.entry("m0", "blissey", dynamax: true), unmarked = P23.entry("m1", "blissey", dynamax: nil)
        let b0 = P23.build("m0", "blissey", areas: ["Max"]), b1 = P23.build("m1", "blissey", areas: ["Max"])
        let table = P23.table([P23.tierEntry("max", "Tanks and healers", "S", "blissey", role: "Tank and healer")])
        let ctx = P23.ctx(builds: [b0, b1], entries: [marked, unmarked], table: table)
        XCTAssertTrue(HubSquads.isFullStrength(b0, screen: .max, ctx: ctx))
        XCTAssertFalse(HubSquads.isFullStrength(b1, screen: .max, ctx: ctx))
        XCTAssertTrue(HubRaidsModel.isBuilt(b1, advice: ctx.advice, entries: ctx.entries, screen: .max), "the readiness bar's looser rule is unchanged")
        let card = A.maxCards(copy: unmarked, ctx: ctx).cards[0]
        XCTAssertEqual(card.plan?.built, false); XCTAssertTrue(card.needsDynamax)
        XCTAssertEqual(A.summary(copy: unmarked, ctx: ctx).first { $0.activity == .max }?.verdict, .needsDynamax)
    }

    // MARK: F6: CPM from src/cpm.js

    func testBulkUsesTheCpmValuesOfSrcCpmJs() {
        XCTAssertEqual(PogoRules.cpm(40.5), 0.792803968)
        XCTAssertEqual(PogoRules.cpm(41.5), 0.797803922, "PogoReader's table says 0.797800015")
        XCTAssertEqual(PogoRules.cpm(50.5), 0.842803698)
        XCTAssertEqual(PogoRules.cpm(30), 0.7317); XCTAssertEqual(PogoRules.cpm(1), 0.094); XCTAssertEqual(PogoRules.cpm(51), 0.84529999)
        XCTAssertEqual(PogoRules.bulkCPM.count, 101)
    }

    // MARK: F7: bracketed forms

    func testTheBundledDeoxysRowKeepsItsFormes() throws {
        let rows = P23.hub.rotation
        let deoxys = try XCTUnwrap(rows.first { $0.bosses.filter { $0.name.hasPrefix("Deoxys") }.count == 4 })
        XCTAssertEqual(A.shortName(deoxys, among: rows), "Deoxys · Deoxys (Speed) · Deoxys (Attack) · Deoxys (Defense)")
        let giratina = try XCTUnwrap(rows.first { $0.bosses.map(\.name) == ["Giratina (Origin)"] })
        XCTAssertEqual(A.shortName(giratina, among: rows), "Giratina (Origin)", "the Altered row shares the base name")
    }

    // MARK: F8: Rocket members that only beat a leader option

    func testAMemberThatBeatsOnlyALeaderOptionIsStillListed() {
        let copy = P23.entry("cm", "charmander")
        let ctx = P23.ctx(entries: [copy]) { h in
            h.grunts = [HubData.Grunt(type: "water", quote: "", label: "")]
            h.leaders = [HubData.Leader(name: "L", since: "2026-01-01", slots: [[HubData.Boss(name: "A", speciesId: "a", types: ["grass"], shadow: nil)],
                                                                              [HubData.Boss(name: "B", speciesId: "b", types: ["steel"], shadow: nil)]], source: "")]
        }
        let cards = A.rocketCards(copy: copy, ctx: ctx)
        XCTAssertEqual(cards.map(\.member.name), ["Charizard", "Charmeleon", "Charmander"], "no grunt type; equal options: the later evolution first")
        XCTAssertTrue(cards.allSatisfy { $0.gruntTypes.isEmpty && !$0.leaderSlots.isEmpty })
        let r = A.summary(copy: copy, ctx: ctx).first { $0.activity == .rocket }!
        XCTAssertEqual(r.verdict, .notUsed, "BEATS 0 GRUNTS is never shown")
    }

    // MARK: F9: one Max card per member

    func testSeveralMaxEntriesOfOneMemberMergeIntoOneCard() {
        let table = P23.table([P23.tierEntry("max", "Tanks and healers", "A", "blissey", role: "Tank"), P23.tierEntry("max", "Tanks and healers", "S", "blissey", role: "Healer")])
        let copy = P23.entry("b", "blissey")
        let cards = A.maxCards(copy: copy, ctx: P23.ctx(entries: [copy], table: table)).cards
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].tier, "S"); XCTAssertEqual(cards[0].roles, [.tank, .healer]); XCTAssertEqual(cards[0].roleText, "Tank and healer")
    }

    // MARK: F10 and F11

    func testTheUpgradeLabelNamesTheRemainingWorkWithoutTheDynamaxClause() {
        var max = P23.build("a", "blissey", areas: ["Max"], built: false)
        max.steps = [.init(kind: "powerUp", toLevel: 40, areas: ["max"]), .init(kind: "needsDynamaxCopy")]
        XCTAssertEqual(HubSquads.upgradeLabel(max), "Upgrade available: power up to level 40")
        var two = P23.build("a", "vaporeon", areas: ["Raids"], built: false)
        two.steps = [.init(kind: "powerUp", toLevel: 35, areas: ["raids"]), .init(kind: "secondMove", certain: false)]
        XCTAssertEqual(HubSquads.upgradeLabel(two), "Upgrade available: power up to level 35 + Second move (if it doesn't have it)")
        var only = max; only.steps = [.init(kind: "needsDynamaxCopy")]
        XCTAssertNil(HubSquads.upgradeLabel(only), "nothing but the Dynamax requirement: no upgrade work")
        XCTAssertTrue(HubTeams.isBuilt(only))
    }

    func testGymBulkMissingForUnreadIVsHasItsOwnWording() {
        let copy = P23.entry("ch", "chansey", ivs: nil, level: 30)
        let ctx = P23.ctx(entries: [copy], table: gymTable)
        XCTAssertEqual(A.summary(copy: copy, ctx: ctx).first { $0.activity == .gym }?.lines.map(\.plain).first, "As Blissey, IVs not read")
        XCTAssertEqual(A.bulkWording(.levelNotRead), "level not read"); XCTAssertEqual(A.bulkWording(.ivsNotRead), "IVs not read")
        let rows = HubSquads.gymRows(mode: .best, ctx: P23.ctx(builds: [P23.build("ch", "chansey", areas: ["Gym"])], entries: [copy], table: gymTable))
        XCTAssertTrue(rows[0].ivsNotRead); XCTAssertFalse(rows[0].levelNotRead)
    }

    // MARK: F12: one reading of the tables

    func testRaidCandidatesReadMegaEntriesAndShadowAsTypesCountedDoes() {
        let table = P23.table([P23.tierEntry("raids", "Water", "A", "swampert"), P23.tierEntry("raids", "Water", "S", "swampert_mega", shadow: true, mega: true)])
        let row = P23.row("2026-10-20", "2026-10-30", bosses: [P23.boss("charizard", types: ["fire"])])
        let build = P23.build("c", "swampert", areas: ["Raids"], powerUp: false, viaMega: true)
        let plain = HubSquads.raidCandidates(row: row, mode: .best, ctx: P23.ctx(builds: [build], entries: [P23.entry("c", "swampert")], table: table))
        XCTAssertEqual(plain.map(\.tier), ["A"], "a Shadow Mega entry is not a plain copy's")
        let shadow = HubSquads.raidCandidates(row: row, mode: .best, ctx: P23.ctx(builds: [build], entries: [P23.entry("c", "swampert", shadow: 1)], table: table))
        XCTAssertEqual(shadow.map(\.tier), ["S"])
        // A section that is not a type stands for the species' own types, in the candidates and on the cards alike.
        let tiers = P23.table([P23.tierEntry("raids", "Tiers", "S", "vaporeon")])
        let c = HubSquads.raidCandidates(row: row, mode: .best, ctx: P23.ctx(builds: [P23.build("v", "vaporeon", areas: ["Raids"])], table: tiers))
        XCTAssertEqual(c.map(\.tier), ["S"])
        let v = P23.entry("v", "vaporeon")
        XCTAssertEqual(A.raidCards(copy: v, ctx: P23.ctx(entries: [v], table: tiers, rotation: [row])).map(\.type), ["water"])
    }

    func testTheGruntStripListsTheFitInGruntCountersOrder() {
        let builds = [P23.build("a", "togekiss", areas: ["Raids"], tier: "S", built: false), P23.build("b", "gyarados", areas: ["Rocket"], tier: "B"), P23.build("c", "charizard", areas: ["Raids"], tier: "A")]
        let ctx = P23.ctx(builds: builds)
        let fit = HubTeams.gruntFit(type: "fighting", builds: builds, gm: gm, hub: P23.hub)
        XCTAssertEqual(fit.map(\.entryId), ["b", "a", "c"], "Rocket area, then tier")
        XCTAssertEqual(HubSquads.gruntCounters(type: "fighting", mode: .best, ctx: ctx).builds.map(\.entryId), ["b", "c", "a"], "the same order, built first")
        XCTAssertEqual(HubRaidsModel.isShadow(P23.entry("s", "eevee", shadow: 1)), true)
        XCTAssertEqual(HubRaidsModel.isShadow(P23.entry("s", "eevee")), false)
    }

    // MARK: F13: extended events

    func testAnEventWhoseEndMovedIsKeptAndOneThatLeftTheRotationFallsBackToItsStoredDay() {
        var s = SquadStore()
        let old = P23.row("2026-10-01", "2026-10-10", title: "5-star raid", bosses: [])
        s.saveEventSquad(SquadStore.Saved(slots: HubSquads.defaultRaidSlots(), isSet: true), row: old, screen: .raids)
        var extended = old; extended.to = "2026-10-30"
        let kept = s.pruned(today: "2026-10-20", rotation: [extended])
        XCTAssertNotNil(kept.raids[SquadStore.eventKey(old)], "the row now runs to 30 Oct")
        XCTAssertEqual(kept.raids[SquadStore.eventKey(old)]?.endsOn, "2026-10-30")
        XCTAssertEqual(s.pruned(today: "2026-10-20", rotation: []).raids.count, 0, "gone from the rotation: the stored day decides")
        XCTAssertEqual(s.pruned(today: "2026-10-05", rotation: []).raids.count, 1)
        var shortened = old; shortened.to = "2026-10-15"
        XCTAssertEqual(s.pruned(today: "2026-10-20", rotation: [shortened]).raids.count, 0, "the current row ended earlier")
        XCTAssertEqual(s.refreshed(today: "2026-10-20", rotation: [extended], boxIds: []).raids.count, 1)
    }

    // MARK: F14: owned dex numbers always count

    func testABoxDittoCountsEvenWhereTheGameMasterSaysUnreleased() {
        XCTAssertEqual(gm.byId["ditto"]?.released, false, "the premise: PvPoke flags Ditto unreleased")
        let o = HubCollection.overview(entries: [P23.entry("d", "ditto")], gm: gm)
        XCTAssertEqual(o.owned, 1); XCTAssertEqual(o.released, 952)
        XCTAssertEqual(o.regions.first?.owned, 1); XCTAssertEqual(o.regions.first?.total, 151)
        XCTAssertTrue(o.regions.allSatisfy { $0.owned <= $0.total })
        XCTAssertEqual(HubCollection.overview(entries: [], gm: gm).released, 951, "an empty box keeps the base set")
        XCTAssertFalse(HubCollection.missingSpecies(entries: [P23.entry("d", "ditto")], advice: BoxAdvice(), gm: gm).contains { $0.dex == 132 })
    }

    // MARK: F15

    func testWhereTagMatchesCommunityDayCaseInsensitivelyAndAsAWord() {
        XCTAssertEqual(HubSquads.whereTags(obtain: "Easy. CD move", bossOnNow: false), ["Community Day"])
        XCTAssertEqual(HubSquads.whereTags(obtain: "Easy. Cd only", bossOnNow: false), ["Community Day"])
        XCTAssertEqual(HubSquads.whereTags(obtain: "Cd", bossOnNow: false), ["Community Day"])
        XCTAssertEqual(HubSquads.whereTags(obtain: "Easy. Abcde", bossOnNow: false), ["Easy to get"], "cd inside a word is not a tag")
    }

    func testThePlainSpeciesIsTheOneWithoutAFormInItsNameNotTheOneWithoutAnUnderscore() throws {
        let json = #"{"pokemon":[{"dex":900,"speciesId":"foo_bar_galarian","speciesName":"Foo Bar (Galarian)","released":true,"tags":["galarian"]},"#
            + #"{"dex":900,"speciesId":"foo_bar","speciesName":"Foo Bar","released":true}],"moves":[]}"#
        let g = try GameMaster(data: Data(json.utf8))
        XCTAssertEqual(HubCollection.releasedSpecies(gm: g).map(\.id), ["foo_bar"])
        XCTAssertEqual(HubCollection.releasedSpecies(gm: gm).first { $0.dex == 122 }?.id, "mr_mime")
        XCTAssertEqual(HubCollection.releasedSpecies(gm: gm).first { $0.dex == 250 }?.id, "ho_oh")
    }
}
