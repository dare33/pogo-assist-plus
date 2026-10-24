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
    private func advice(_ es: [BoxEntry]) throws -> BoxAdvice { BoxAdvice.make(from: try sharedEngine.advise(rows: es.map(\.row)), entries: es) }
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
                       ["5★", "MEGA", "SHADOW", "RAID DAY", "RAID HOUR", "MAX MON", "EVENT", ""])
    }

    func testNames() throws {
        let hub = try HubData.bundled()
        XCTAssertEqual(HubRaidsModel.name(try row(hub, .fiveStar, from: "2026-11-09")), "Cresselia · Darkrai")
        XCTAssertEqual(HubRaidsModel.name(try row(hub, .maxMonday, from: "2026-11-16")), "Max Monday to be announced")
        XCTAssertEqual(HubRaidsModel.name(try row(hub, .battleDay, from: "2026-11-28")), "Super Mega Raid Day to be announced")
        XCTAssertEqual(HubRaidsModel.name(try row(hub, .raidHour, from: "2026-10-28")), "Raid Hour")
    }

    func testBringIsTheWeaknessesOfEveryBoss() throws {
        let hub = try HubData.bundled()
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .fiveStar, from: "2026-10-21"), hub: hub), ["dragon", "fairy"], "Palkia, water/dragon")
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .mega, from: "2026-10-28"), hub: hub), ["fairy"], "Mega Sableye")
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .fiveStar, from: "2026-10-28"), hub: hub), ["ice", "ghost", "dragon", "dark"], "Giratina: ice and dragon double, then the chart order")
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .fiveStar, from: "2026-11-09"), hub: hub), ["fighting", "bug", "ghost", "dark"], "Cresselia and Darkrai: any boss counts")
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .mega, from: "2026-10-21"), hub: hub).count, 4, "capped at four")
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .maxMonday, from: "2026-11-16"), hub: hub), [])
        XCTAssertEqual(HubRaidsModel.bring(row: try row(hub, .raidHour, from: "2026-10-28"), hub: hub), [])
    }

    func testReadinessAndToDoOnTheFixture() throws {
        let hub = try HubData.bundled(), gm = try GameMaster.bundled(), es = try entries(), a = try advice(es)
        let sableye = try row(hub, .mega, from: "2026-10-28"), palkia = try row(hub, .fiveStar, from: "2026-10-21")
        // Xerneas (fairy) still has a power-up to do: nothing is built against Mega Sableye.
        let r = HubRaidsModel.readiness(row: sableye, builds: a.builds, entries: es, gm: gm, hub: hub, screen: .raids)
        XCTAssertEqual(r.built, 0); XCTAssertEqual(r.needed, 1); XCTAssertEqual(r.missing, ["fairy"])
        XCTAssertEqual(HubRaidsModel.toDo(row: sableye, builds: a.builds, entries: es, gm: gm, hub: hub, screen: .raids),
                       "Power up Xerneas to level 35 (Raids) + Second move (if it doesn't have it) + 1 Elite TM (206k dust).")
        // The same build finished: fairy is covered, so Sableye is ready and Palkia still lacks a dragon.
        let xerneas = try XCTUnwrap(a.builds.firstIndex { $0.targetId == "xerneas" })
        var done = a.builds; done[xerneas] = finished(done[xerneas])
        let ready = HubRaidsModel.readiness(row: sableye, builds: done, entries: es, gm: gm, hub: hub, screen: .raids)
        XCTAssertEqual(ready.built, 1); XCTAssertEqual(ready.missing, [])
        XCTAssertEqual(HubRaidsModel.toDo(row: sableye, builds: done, entries: es, gm: gm, hub: hub, screen: .raids), "Ready.")
        let half = HubRaidsModel.readiness(row: palkia, builds: done, entries: es, gm: gm, hub: hub, screen: .raids)
        XCTAssertEqual(half.built, 1); XCTAssertEqual(half.needed, 2); XCTAssertEqual(half.missing, ["dragon"])
        XCTAssertEqual(HubRaidsModel.toDo(row: palkia, builds: done, entries: es, gm: gm, hub: hub, screen: .raids), "No Dragon counter in your box.")
        // A Dynamax requirement alone does not stop a raid build from counting.
        done[xerneas] = finished(done[xerneas], dynamaxStep: true)
        XCTAssertEqual(HubRaidsModel.readiness(row: sableye, builds: done, entries: es, gm: gm, hub: hub, screen: .raids).built, 1)
        // A Max-only build does not count for raids.
        var maxOnly = done; maxOnly[xerneas].areas = ["Max"]
        XCTAssertEqual(HubRaidsModel.readiness(row: sableye, builds: maxOnly, entries: es, gm: gm, hub: hub, screen: .raids).built, 0)
    }

    func testRowsWithNoBossSayWhy() throws {
        let hub = try HubData.bundled(), gm = try GameMaster.bundled(), es = try entries(), a = try advice(es)
        func todo(_ r: HubData.RotationRow, _ s: HubRaidsModel.Screen) -> String { HubRaidsModel.toDo(row: r, builds: a.builds, entries: es, gm: gm, hub: hub, screen: s) }
        XCTAssertEqual(todo(try row(hub, .maxMonday, from: "2026-11-16"), .max), "Boss not announced yet.")
        XCTAssertEqual(todo(try row(hub, .battleDay, from: "2026-11-28"), .raids), "Boss not announced yet.")
        XCTAssertEqual(todo(try row(hub, .raidHour, from: "2026-10-28"), .raids), "6:00 pm to 7:00 pm local time")
        let none = HubRaidsModel.readiness(row: try row(hub, .raidHour, from: "2026-10-28"), builds: a.builds, entries: es, gm: gm, hub: hub, screen: .raids)
        XCTAssertEqual(none.needed, 0)
    }

    func testMaxReadinessCountsDynamaxYesCopiesOnly() throws {
        let hub = try HubData.bundled(), gm = try GameMaster.bundled()
        var es = try entries(); let a0 = try advice(es)
        let zi = try XCTUnwrap(a0.builds.firstIndex { $0.targetId == "zamazenta_crowned_shield" })
        let zamazenta = a0.builds[zi]
        XCTAssertTrue(zamazenta.areas.contains("Max"))
        let cryogonal = try row(hub, .maxMonday, from: "2026-11-30")   // fire, fighting, rock, steel
        var builds = a0.builds; builds[zi] = finished(zamazenta, dynamaxStep: true)
        // Finished, but the copy is not marked Dynamax: the requirement is still the person's to set.
        var r = HubRaidsModel.readiness(row: cryogonal, builds: builds, entries: es, gm: gm, hub: hub, screen: .max)
        XCTAssertEqual(r.built, 0); XCTAssertEqual(r.needed, 4)
        XCTAssertEqual(HubRaidsModel.toDo(row: cryogonal, builds: builds, entries: es, gm: gm, hub: hub, screen: .max), "Mark Zamazenta (Hero) as Dynamax on its page.")
        // A copy marked No is not ready either.
        let ei = try XCTUnwrap(es.firstIndex { $0.id == zamazenta.entryId })
        es[ei].row.dynamax = false
        XCTAssertEqual(HubRaidsModel.readiness(row: cryogonal, builds: builds, entries: es, gm: gm, hub: hub, screen: .max).built, 0)
        es[ei].row.dynamax = true
        r = HubRaidsModel.readiness(row: cryogonal, builds: builds, entries: es, gm: gm, hub: hub, screen: .max)
        XCTAssertEqual(r.built, 2); XCTAssertEqual(r.missing, ["fire", "rock"], "Zamazenta is fighting and steel")
        XCTAssertEqual(HubRaidsModel.toDo(row: cryogonal, builds: builds, entries: es, gm: gm, hub: hub, screen: .max), "No Fire counter in your box.")
    }

    func testGapClosersAreTheUnbuiltBuildsForTheShownBossesTypes() throws {
        let hub = try HubData.bundled(), gm = try GameMaster.bundled(), es = try entries(), a = try advice(es)
        let sableye = try row(hub, .mega, from: "2026-10-28"), palkia = try row(hub, .fiveStar, from: "2026-10-21")
        func closers(_ rows: [HubData.RotationRow], _ builds: [BoxAdvice.Build]) -> [String] {
            HubRaidsModel.gapClosers(rows: rows, builds: builds, entries: es, gm: gm, hub: hub, screen: .raids).map(\.targetName)
        }
        XCTAssertEqual(closers([sableye], a.builds), ["Xerneas"], "fairy")
        XCTAssertEqual(closers([palkia], a.builds), ["Xerneas"], "dragon and fairy; nothing in the box is a dragon")
        XCTAssertEqual(closers([sableye, try row(hub, .mega, from: "2026-11-16")], a.builds).sorted(), ["Xerneas"], "Banette's ghost and dark: no fixture build has them")
        let fighters = try row(hub, .maxMonday, from: "2026-11-30")   // fire, fighting, rock, steel
        XCTAssertEqual(closers([fighters], a.builds), ["Lucario", "Zamazenta (Crowned Shield)", "Moltres"], "advisor order")
        var done = a.builds; let x = try XCTUnwrap(done.firstIndex { $0.targetId == "xerneas" }); done[x] = finished(done[x])
        XCTAssertEqual(closers([sableye], done), [], "built builds close nothing")
        XCTAssertEqual(closers([], a.builds), [])
    }

    func testMaxRosterListsDynamaxYesCopies() throws {
        var es = try entries(); let a0 = try advice(es)
        XCTAssertTrue(HubRaidsModel.maxRoster(entries: es, builds: a0.builds).tiles.isEmpty)
        XCTAssertEqual(HubRaidsModel.maxRoster(entries: es, builds: a0.builds).unsetCount, 1, "only Zamazenta carries a Max build")
        let z = try XCTUnwrap(a0.builds.first { $0.targetId == "zamazenta_crowned_shield" })
        es[try XCTUnwrap(es.firstIndex { $0.id == z.entryId })].row.dynamax = true
        es[try XCTUnwrap(es.firstIndex { $0.id == "e3" })].row.dynamax = true   // Xerneas: no Max entry in the tables
        es[try XCTUnwrap(es.firstIndex { $0.id == "e5" })].row.dynamax = false
        // The advisor sees the flags, as the app does through `advise(rows:)`.
        let a = try advice(es)
        let roster = HubRaidsModel.maxRoster(entries: es, builds: a.builds)
        XCTAssertEqual(roster.tiles.map(\.name), ["Zamazenta (Hero)", "Xerneas"], "a copy with a Max use first")
        XCTAssertEqual(roster.tiles[0].line, "S · Form change to Zamazenta (Crowned Shield) + Power up to level 35 (Raids) + Second move (if it doesn't have it)")
        XCTAssertTrue(roster.tiles[0].hasUse)
        XCTAssertEqual(roster.tiles[1].line, "No Max use in the tables"); XCTAssertFalse(roster.tiles[1].hasUse)
        XCTAssertEqual(roster.tiles[1].cp, es[3].row.cp)
        XCTAssertEqual(roster.unsetCount, 0)
        // Finished: the line reads "Already built".
        var built = a.builds; let zi = try XCTUnwrap(built.firstIndex { $0.id == z.id }); built[zi] = finished(built[zi])
        XCTAssertEqual(HubRaidsModel.maxRoster(entries: es, builds: built).tiles[0].line, "S · Already built")
    }
}
