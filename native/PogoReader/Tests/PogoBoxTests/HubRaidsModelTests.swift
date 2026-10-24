import XCTest
@testable import PogoBox
import PogoReader

/// The Raids and Max screens' derivations, pinned on the fixture report, the bundled `hub.json` and the bundled game master.
final class HubRaidsModelTests: XCTestCase {
    private let today = "2026-10-25"

    private func entries() throws -> [BoxEntry] {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!
        return try Fixture.expected().rows.enumerated().map { i, r in BoxEntry(id: "e\(i)", row: r, firstSeen: date, lastSeen: date) }
    }
    /// The advisor is given the entries with Index = position + 1, which is how the app ties a build back to its Pokémon.
    private func advice(_ es: [BoxEntry]) throws -> BoxAdvice {
        let rows = es.enumerated().map { i, e -> ScanRow in var r = e.row; r.index = i + 1; return r }
        return BoxAdvice.make(from: try sharedEngine.advise(rows: rows), entries: es)
    }
    /// A Blissey and a Xerneas-free addition to the fixture box: the fixture holds no Pokémon the Max table lists by its own species.
    private func withBlissey(_ es: [BoxEntry]) -> [BoxEntry] {
        var b = es[0]; b.id = "bliss"
        b.row.speciesId = "blissey"; b.row.name = "Blissey"; b.row.display = "Blissey"; b.row.form = ""; b.row.cp = 2178; b.row.dynamax = nil
        return es + [b]
    }
    private func row(_ hub: HubData, _ kind: HubData.Kind, from: String) throws -> HubData.RotationRow {
        try XCTUnwrap(hub.rotation.first { $0.kind == kind && $0.from == from })
    }
    /// A build with nothing left to do but the Dynamax requirement.
    private func finished(_ b: BoxAdvice.Build, dynamaxStep: Bool = false) -> BoxAdvice.Build {
        var v = b; v.steps = dynamaxStep ? [.init(kind: "needsDynamaxCopy")] : []; return v
    }

    func testTimelineSplitsNowFromComingUp() throws {
        let hub = try HubData.bundled()
        let raids = HubRaidsModel.timeline(rows: hub.rotation, screen: .raids, today: today)
        XCTAssertEqual(raids.now.map { HubRaidsModel.name($0.row) }, ["Shadow Landorus (Incarnate)", "Palkia", "Mega Charizard X · Mega Charizard Y"], "by first day, then 5-star before Mega")
        XCTAssertTrue(raids.now.allSatisfy(\.isNow))
        XCTAssertFalse(raids.comingUp.contains { $0.isNow })
        XCTAssertEqual(raids.comingUp.first.map { HubRaidsModel.name($0.row) }, "Giratina (Origin)")
        XCTAssertEqual(raids.comingUp.prefix(3).map(\.row.kind), [.fiveStar, .mega, .raidHour], "same day: kind order")
        XCTAssertEqual(raids.comingUp.first?.daysUntil, 3)
        XCTAssertTrue(raids.comingUp.contains { $0.row.kind == .battleDay }, "Super Mega Raid Days are raids")
        XCTAssertFalse((raids.now + raids.comingUp).contains { $0.row.kind == .maxMonday || $0.row.kind == .maxEvent })

        let max = HubRaidsModel.timeline(rows: hub.rotation, screen: .max, today: today)
        XCTAssertTrue(max.now.isEmpty)
        XCTAssertEqual(max.comingUp.map(\.row.from), ["2026-10-26", "2026-11-02", "2026-11-16", "2026-11-16", "2026-11-30"])
        XCTAssertEqual(max.comingUp.map(\.row.kind), [.maxMonday, .maxMonday, .maxMonday, .maxEvent, .maxMonday])
        XCTAssertEqual(max.comingUp.first?.daysUntil, 1)
    }

    func testPastRowsAreDroppedAndTheLastDayStillCounts() throws {
        let hub = try HubData.bundled()
        let onLastDay = HubRaidsModel.timeline(rows: hub.rotation, screen: .raids, today: "2026-10-27")
        XCTAssertTrue(onLastDay.now.contains { HubRaidsModel.name($0.row) == "Palkia" })
        let after = HubRaidsModel.timeline(rows: hub.rotation, screen: .raids, today: "2026-10-28")
        XCTAssertFalse((after.now + after.comingUp).contains { HubRaidsModel.name($0.row) == "Palkia" })
        XCTAssertEqual(after.now.map { HubRaidsModel.name($0.row) }, ["Shadow Landorus (Incarnate)", "Giratina (Origin)", "Mega Sableye", "Raid Hour"])
        XCTAssertTrue(HubRaidsModel.timeline(rows: hub.rotation, screen: .raids, today: "2026-12-02").now.isEmpty)
        XCTAssertTrue(HubRaidsModel.timeline(rows: hub.rotation, screen: .raids, today: "2026-12-02").comingUp.isEmpty)
        // Across a month end and a leap day the count is calendar days.
        XCTAssertEqual(HubRaidsModel.days(from: "2026-10-30", to: "2026-11-02"), 3)
        XCTAssertEqual(HubRaidsModel.days(from: "2028-02-28", to: "2028-03-01"), 2)
    }

    func testDateColumnAndChips() throws {
        let hub = try HubData.bundled()
        let raids = HubRaidsModel.timeline(rows: hub.rotation, screen: .raids, today: today)
        XCTAssertEqual(HubRaidsModel.dateColumn(raids.now[1]).dates, "21 – 27 OCT")
        XCTAssertEqual(HubRaidsModel.dateColumn(raids.now[1]).when, "now")
        XCTAssertEqual(HubRaidsModel.dateColumn(raids.now[0]).dates, "7 OCT – 3 NOV")
        let giratina = raids.comingUp[0]
        XCTAssertEqual(HubRaidsModel.dateColumn(giratina).dates, "28 OCT – 3 NOV")
        XCTAssertEqual(HubRaidsModel.dateColumn(giratina).when, "in 3 d")
        let day = try XCTUnwrap(raids.comingUp.first { $0.row.kind == .battleDay })
        XCTAssertEqual(HubRaidsModel.dateColumn(day).dates, "31 OCT")
        XCTAssertEqual(HubRaidsModel.dateColumn(day).when, "in 6 d")
        let tomorrow = HubRaidsModel.Entry(row: day.row, isNow: false, daysUntil: 1)
        XCTAssertEqual(HubRaidsModel.dateColumn(tomorrow).when, "in 1 d")
        XCTAssertEqual([HubData.Kind.fiveStar, .mega, .shadow, .battleDay, .raidHour, .maxMonday, .maxEvent, .other].map(HubRaidsModel.kindChip),
                       ["5★", "MEGA", "SHADOW", "BATTLE DAY", "RAID HOUR", "MAX MON", "EVENT", ""])
    }

    func testNames() throws {
        let hub = try HubData.bundled()
        XCTAssertEqual(HubRaidsModel.name(try row(hub, .fiveStar, from: "2026-11-09")), "Cresselia · Darkrai")
        XCTAssertEqual(HubRaidsModel.name(try row(hub, .fiveStar, from: "2026-11-25")), "Deoxys (4 formes)")
        XCTAssertEqual(HubRaidsModel.name(try row(hub, .maxMonday, from: "2026-11-16")), "Max Monday to be announced")
        XCTAssertEqual(HubRaidsModel.name(try row(hub, .battleDay, from: "2026-11-28")), "Super Mega Raid Day to be announced")
        XCTAssertEqual(HubRaidsModel.name(try row(hub, .raidHour, from: "2026-10-28")), "Raid Hour")
    }

    func testBringIsTheWeaknessesOfEveryBoss() throws {
        let hub = try HubData.bundled()
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .fiveStar, from: "2026-10-21"), hub: hub), ["dragon", "fairy"], "Palkia, water/dragon")
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .mega, from: "2026-10-28"), hub: hub), ["fairy"], "Mega Sableye")
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .fiveStar, from: "2026-10-28"), hub: hub), ["ice", "ghost", "dragon", "dark"], "Giratina is ghost/dragon, no double weakness: ice, ghost, dragon and dark all at 1.6, in the chart's order")
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .fiveStar, from: "2026-11-09"), hub: hub), ["fighting", "bug", "ghost", "dark"], "Cresselia and Darkrai: any boss counts")
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .mega, from: "2026-10-21"), hub: hub).count, 4, "capped at four")
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .maxMonday, from: "2026-11-16"), hub: hub), [])
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .raidHour, from: "2026-10-28"), hub: hub), [])
    }

    private func with(_ a: BoxAdvice, _ id: String, _ change: (inout BoxAdvice.Build) -> Void) throws -> BoxAdvice {
        var out = a
        let i = try XCTUnwrap(out.builds.firstIndex { $0.targetId == id })
        change(&out.builds[i])
        return out
    }

    func testSubtitlesSpokenDatesAndTheDebugDay() throws {
        let hub = try HubData.bundled()
        XCTAssertEqual(HubRaidsModel.lastDay(rows: hub.rotation, screen: .raids), "1 Dec")
        XCTAssertEqual(HubRaidsModel.lastDay(rows: hub.rotation, screen: .max), "30 Nov")
        XCTAssertNil(HubRaidsModel.lastDay(rows: [], screen: .raids))
        let line = HubRaidsModel.timeline(rows: hub.rotation, screen: .raids, today: today)
        XCTAssertEqual(HubRaidsModel.spokenDates(line.comingUp[0]), "28 October to 3 November, in 3 days")
        XCTAssertEqual(HubRaidsModel.spokenDates(line.now[1]), "21 October to 27 October, now")
        XCTAssertEqual(HubRaidsModel.spokenDates(HubRaidsModel.Entry(row: line.comingUp[0].row, isNow: false, daysUntil: 1)), "28 October to 3 November, in 1 day")
        let day = try XCTUnwrap(line.comingUp.first { $0.row.kind == .battleDay })
        XCTAssertEqual(HubRaidsModel.spokenDates(day), "31 October, in 6 days")
        // `-uitest-today` is honoured by a debug build only, and only as a yyyy-mm-dd day.
        let now = Date(timeIntervalSince1970: 0)
        #if DEBUG
        XCTAssertEqual(HubModel.today(now: now, arguments: ["app", "-uitest-today", "2026-10-25"]), "2026-10-25")
        XCTAssertNotEqual(HubModel.today(now: now, arguments: ["app", "-uitest-today", "tomorrow"]), "tomorrow")
        #endif
        XCTAssertEqual(HubModel.today(now: now, arguments: ["app"]).count, 10)
        XCTAssertTrue(HubModel.today(now: now, arguments: []).hasPrefix("19"), "a Gregorian year, whatever the device calendar")
    }

    func testBringRanksByTheBestMultiplierAcrossBosses() throws {
        let hub = try HubData.bundled()
        // Two bosses: Darkrai (dark) is hit by fighting, bug and fairy at 1.6; Cresselia (psychic) by bug, ghost and dark at 1.6. Nothing is double,
        // so every type is at 1.6 and the chart's order decides: fighting, bug, ghost, dark.
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .fiveStar, from: "2026-11-09"), hub: hub), ["fighting", "bug", "ghost", "dark"])
        // A type that is double against one boss outranks a single weakness against the other: Landorus (ground/flying) ice 2.56.
        var both = try row(hub, .shadow, from: "2026-10-07")
        both.bosses.append(try XCTUnwrap(try row(hub, .fiveStar, from: "2026-11-09").bosses.first))   // + Cresselia (psychic): bug, ghost, dark
        XCTAssertEqual(HubRaidsModel.bring(row: both, hub: hub), ["ice", "water", "bug", "ghost"], "ice 2.56 first, then the 1.6s in chart order, capped at four")
    }

    func testBringKeepsDoubleWeaknessesFirstAndCapsAtFour() throws {
        let hub = try HubData.bundled()
        let landorus = try row(hub, .shadow, from: "2026-10-07")   // ground/flying: ice is 2.56, water 1.6
        XCTAssertEqual(HubRaidsModel.bring(row: landorus, hub: hub), ["ice", "water"])
        XCTAssertEqual(hub.weaknesses(of: ["ground", "flying"]).map(\.type), ["ice", "water"])
        // Charizard X (fire/dragon) and Y (fire/flying): rock is 2.56 against Y; water, electric, ground and dragon are 1.6, and the cap drops dragon (last in the chart's order).
        let charizard = try row(hub, .mega, from: "2026-10-21")
        XCTAssertEqual(HubRaidsModel.bring(row: charizard, hub: hub), ["rock", "water", "electric", "ground"])
        XCTAssertTrue(hub.weaknesses(of: ["fire", "dragon"]).map(\.type).contains("dragon"))
    }

    func testReadinessAndToDoOnTheFixture() throws {
        let hub = try HubData.bundled(), gm = try GameMaster.bundled(), es = try entries(), a = try advice(es)
        let sableye = try row(hub, .mega, from: "2026-10-28"), palkia = try row(hub, .fiveStar, from: "2026-10-21")
        func ready(_ r: HubData.RotationRow, _ a: BoxAdvice) -> (built: Int, needed: Int, missing: [String]) {
            HubRaidsModel.readiness(row: r, advice: a, entries: es, gm: gm, hub: hub, screen: .raids)
        }
        func todo(_ r: HubData.RotationRow, _ a: BoxAdvice) -> String { HubRaidsModel.toDo(row: r, advice: a, entries: es, gm: gm, hub: hub, screen: .raids) }
        // Xerneas (fairy) still has a power-up to do: nothing is built against Mega Sableye.
        let r = ready(sableye, a)
        XCTAssertEqual(r.built, 0); XCTAssertEqual(r.needed, 1); XCTAssertEqual(r.missing, ["fairy"])
        XCTAssertEqual(todo(sableye, a), "Power up Xerneas to level 35 + Second move (if it doesn't have it) + 1 Elite TM (206k dust).")
        // The same build finished: fairy is covered, so Sableye is ready and Palkia still lacks a dragon.
        let done = try with(a, "xerneas") { $0.steps = [] }
        XCTAssertEqual(ready(sableye, done).built, 1); XCTAssertEqual(ready(sableye, done).missing, [])
        XCTAssertEqual(todo(sableye, done), "Ready.")
        XCTAssertEqual(ready(palkia, done).built, 1); XCTAssertEqual(ready(palkia, done).needed, 2); XCTAssertEqual(ready(palkia, done).missing, ["dragon"])
        XCTAssertEqual(todo(palkia, done), "No Dragon counter in your box.")
        // A Dynamax requirement alone does not stop a raid build from counting.
        XCTAssertEqual(ready(sableye, try with(a, "xerneas") { $0.steps = [.init(kind: "needsDynamaxCopy")] }).built, 1)
        // A build read without steps is not built (as HubModel.needsSomething reads it).
        XCTAssertEqual(ready(sableye, try with(a, "xerneas") { $0.steps = nil }).built, 0)
        // A Max-only build does not count for raids.
        XCTAssertEqual(ready(sableye, try with(a, "xerneas") { $0.steps = []; $0.areas = ["Max"] }).built, 0)
    }

    func testARaidCounterCountsForTheTablesSectionsNotTheSpeciesTypes() throws {
        let gm = try GameMaster.bundled(), table = try TierTable.bundled(), a = try advice(try entries())
        func counted(_ id: String, mega: Bool = false) throws -> Set<String> {
            var b = try XCTUnwrap(a.builds.first); b.targetId = id; b.viaMega = mega
            return HubRaidsModel.typesCounted(by: b, screen: .raids, table: table, gm: gm)
        }
        XCTAssertEqual(gm.byId["kartana"]?.types, ["grass", "steel"])
        XCTAssertEqual(try counted("kartana"), ["grass", "fighting"], "listed under Grass and Fighting, not Steel")
        XCTAssertEqual(try counted("lucario"), ["fighting"], "Fighting/Steel, listed under Fighting only")
        XCTAssertEqual(try counted("lucario", mega: true), ["fighting"])
        XCTAssertEqual(try counted("zamazenta_crowned_shield"), ["fighting", "steel"])
        XCTAssertEqual(try counted("moltres"), ["fire", "flying"])
        XCTAssertEqual(try counted("rayquaza", mega: true), ["flying", "dragon"], "the Mega entries of the build's target")
        XCTAssertEqual(try counted("rayquaza"), [], "a target the Raids table does not list counts for nothing")
    }

    func testTheToDoAddressesTheFirstMissingTypeFirst() throws {
        let hub = try HubData.bundled(), gm = try GameMaster.bundled(), es = try entries(), a = try advice(es)
        // Cryogonal brings fire, fighting, rock, steel. Moltres (fire) is later in the advisor's order than Lucario and Zamazenta (fighting), but
        // fire is the first missing type, so Moltres comes first.
        let cryogonal = try row(hub, .maxMonday, from: "2026-11-30")
        XCTAssertEqual(HubRaidsModel.bring(row: cryogonal, hub: hub), ["fire", "fighting", "rock", "steel"])
        XCTAssertEqual(HubRaidsModel.toDo(row: cryogonal, advice: a, entries: es, gm: gm, hub: hub, screen: .raids), "Power up Moltres to level 35 (137k dust).")
        // With fire covered the first missing type is fighting, and Lucario is the first build in advisor order that counts for it.
        let fire = try with(a, "moltres") { $0.steps = [] }
        XCTAssertEqual(HubRaidsModel.toDo(row: cryogonal, advice: fire, entries: es, gm: gm, hub: hub, screen: .raids), "Mega evolve Lucario + Second move (if it doesn't have it) (75k dust).")
    }

    func testRowsWithNoBossSayWhy() throws {
        let hub = try HubData.bundled(), gm = try GameMaster.bundled(), es = try entries(), a = try advice(es)
        func todo(_ r: HubData.RotationRow, _ s: HubRaidsModel.Screen) -> String { HubRaidsModel.toDo(row: r, advice: a, entries: es, gm: gm, hub: hub, screen: s) }
        XCTAssertEqual(todo(try row(hub, .maxMonday, from: "2026-11-16"), .max), "Boss not announced yet.")
        XCTAssertEqual(todo(try row(hub, .battleDay, from: "2026-11-28"), .raids), "Boss not announced yet.")
        XCTAssertEqual(todo(try row(hub, .raidHour, from: "2026-10-28"), .raids), "6:00 pm to 7:00 pm local time")
        // An announced Max boss with no Max attacker marked Dynamax asks for one, not for a box counter.
        XCTAssertEqual(todo(try row(hub, .maxMonday, from: "2026-10-26"), .max), "No Fairy Max attacker marked Dynamax.")
        let none = HubRaidsModel.readiness(row: try row(hub, .raidHour, from: "2026-10-28"), advice: a, entries: es, gm: gm, hub: hub, screen: .raids)
        XCTAssertEqual(none.needed, 0)
    }

    func testMaxReadinessCountsDynamaxYesCopiesOnly() throws {
        let hub = try HubData.bundled(), gm = try GameMaster.bundled()
        var es = try entries(); let a0 = try advice(es)
        let cryogonal = try row(hub, .maxMonday, from: "2026-11-30")   // fire, fighting, rock, steel
        let finished = try with(a0, "zamazenta_crowned_shield") { $0.steps = [.init(kind: "needsDynamaxCopy")] }
        let carrier = try XCTUnwrap(finished.builds.first { $0.targetId == "zamazenta_crowned_shield" }).entryId
        let ei = try XCTUnwrap(es.firstIndex { $0.id == carrier })
        func ready(_ a: BoxAdvice) -> (built: Int, needed: Int, missing: [String]) { HubRaidsModel.readiness(row: cryogonal, advice: a, entries: es, gm: gm, hub: hub, screen: .max) }
        // Finished, but the copy is not marked Dynamax: the requirement is still the person's to set.
        XCTAssertEqual(ready(finished).built, 0); XCTAssertEqual(ready(finished).needed, 4)
        XCTAssertEqual(HubRaidsModel.toDo(row: cryogonal, advice: finished, entries: es, gm: gm, hub: hub, screen: .max), "Mark Zamazenta (Hero) as Dynamax on its page.")
        es[ei].row.dynamax = false
        XCTAssertEqual(ready(finished).built, 0, "a copy marked No is not ready either")
        es[ei].row.dynamax = true
        XCTAssertEqual(ready(finished).built, 2); XCTAssertEqual(ready(finished).missing, ["fire", "rock"], "Zamazenta is fighting and steel")
        XCTAssertEqual(HubRaidsModel.toDo(row: cryogonal, advice: finished, entries: es, gm: gm, hub: hub, screen: .max), "No Fire Max attacker marked Dynamax.")
        // Not yet built: the copy is marked but the build still has steps, so it does not count.
        XCTAssertEqual(ready(a0).built, 0)
    }

    /// Two copies of one species: the advisor gives one build to the better copy and the other is its spare, which has no build of its own.
    func testASpareDynamaxCopyCountsAndAppearsInTheRoster() throws {
        let hub = try HubData.bundled(), gm = try GameMaster.bundled()
        var es = try entries()
        let hero = try XCTUnwrap(es.first { $0.row.speciesId == "zamazenta_hero" || $0.row.title == "Zamazenta (Hero)" })
        var twin = hero; twin.id = "twin"
        es.append(twin)
        let a0 = try advice(es)
        let build = try XCTUnwrap(a0.builds.first { $0.targetId == "zamazenta_crowned_shield" })
        let other = build.entryId == hero.id ? "twin" : hero.id
        XCTAssertEqual(a0.builds.filter { $0.entryId == other }.count, 0, "the spare has no build of its own")
        XCTAssertEqual(build.spares, 1)
        let finished = try with(a0, "zamazenta_crowned_shield") { $0.steps = [.init(kind: "needsDynamaxCopy")] }
        let cryogonal = try row(hub, .maxMonday, from: "2026-11-30")
        func set(_ id: String, _ v: Bool?) { es[es.firstIndex { $0.id == id }!].row.dynamax = v }
        // Only the spare is marked Yes: it counts through the build that serves it, and it is in the roster with the Max entry's role.
        set(other, true)
        XCTAssertEqual(HubRaidsModel.readiness(row: cryogonal, advice: finished, entries: es, gm: gm, hub: hub, screen: .max).missing, ["fire", "rock"])
        var roster = HubRaidsModel.maxRoster(entries: es, advice: finished)
        XCTAssertEqual(roster.tiles.map(\.entryId), [other])
        XCTAssertEqual(roster.tiles[0].line, "S · Tank"); XCTAssertEqual(roster.tiles[0].state, "Built"); XCTAssertTrue(roster.tiles[0].hasUse)
        XCTAssertEqual(roster.unsetCount, 1, "the carrier is still not set")
        // Both marked Yes: two tiles. Before the build is finished both read To build.
        set(build.entryId, true)
        roster = HubRaidsModel.maxRoster(entries: es, advice: a0)
        XCTAssertEqual(roster.tiles.map(\.state), ["To build", "To build"]); XCTAssertEqual(roster.tiles.map(\.line), ["S · Tank", "S · Tank"])
        XCTAssertEqual(Set(roster.tiles.map(\.entryId)), [hero.id, "twin"])
        XCTAssertEqual(HubRaidsModel.maxRoster(entries: es, advice: finished).tiles.map(\.state), ["Built", "Built"])
    }

    func testMaxRosterReadsTheTablesRole() throws {
        var es = withBlissey(try entries()); let a = try advice(es)
        XCTAssertTrue(HubRaidsModel.maxRoster(entries: es, advice: a).tiles.isEmpty)
        let blissey = try XCTUnwrap(es.firstIndex { $0.row.speciesId == "blissey" })
        let xerneas = try XCTUnwrap(es.firstIndex { $0.row.speciesId == "xerneas" })
        XCTAssertEqual(HubRaidsModel.maxRoster(entries: es, advice: a).unsetCount, 2, "Blissey and the Zamazenta both have a Max entry")
        es[blissey].row.dynamax = true; es[xerneas].row.dynamax = true
        let roster = HubRaidsModel.maxRoster(entries: es, advice: try advice(es))
        XCTAssertEqual(roster.tiles.map(\.name), ["Blissey", "Xerneas"], "a copy with a Max entry first")
        XCTAssertEqual(HubRaidsModel.maxRoster(entries: es, advice: try advice(es)).unsetCount, 1, "the Zamazenta is still not set")
        XCTAssertEqual(roster.tiles[0].line, "S · Tank and healer"); XCTAssertEqual(roster.tiles[0].state, "Built")
        XCTAssertEqual(roster.tiles[1].line, "No Max use in the tables"); XCTAssertEqual(roster.tiles[1].state, ""); XCTAssertFalse(roster.tiles[1].hasUse)
        XCTAssertEqual(roster.tiles[1].cp, es[xerneas].row.cp)
    }

    func testGapClosersAreTheUnbuiltBuildsForTheShownBossesTypes() throws {
        let hub = try HubData.bundled(), gm = try GameMaster.bundled(), es = try entries(), a = try advice(es)
        let sableye = try row(hub, .mega, from: "2026-10-28"), palkia = try row(hub, .fiveStar, from: "2026-10-21")
        func closers(_ rows: [HubData.RotationRow], _ a: BoxAdvice) -> [String] {
            HubRaidsModel.gapClosers(rows: rows, advice: a, entries: es, gm: gm, hub: hub, screen: .raids).map(\.targetName)
        }
        XCTAssertEqual(closers([sableye], a), ["Xerneas"], "fairy")
        XCTAssertEqual(closers([palkia], a), ["Xerneas"], "dragon and fairy; nothing in the box is a dragon")
        let cryogonal = try row(hub, .maxMonday, from: "2026-11-30")   // fire, fighting, rock, steel
        XCTAssertEqual(closers([cryogonal], a), ["Lucario", "Zamazenta (Crowned Shield)", "Moltres"], "advisor order")
        XCTAssertEqual(closers([sableye], try with(a, "xerneas") { $0.steps = [] }), [], "built builds close nothing")
        XCTAssertEqual(closers([], a), [])
    }
}
