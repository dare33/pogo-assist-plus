import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The first real device run (2026-10-02, 50 swipes, the owner's phone): the extension's own replay log. The phone listed
/// 51 Pokémon (LiveGrouper's rows). The JavaScript `finish` gives 49 rows plus 2 unmatched; the twin Staraptor 1986 is merged
/// into one row (no swipe tick between the two) and the hidden-CP Zapdos 1977 is unmatched. Refine, reconciled with
/// LiveGrouper, gives exactly the phone's 51.
final class DeviceRunTests: XCTestCase {
    private func load() throws -> ReplayReadings.Loaded { try ReplayReadings.load(url: Fixture.url("device-run-2026-10-02.replay.jsonl")) }
    private func key(_ r: ScanRow) -> String { "\(r.display) \(r.cp)" }

    /// What the phone showed: LiveGrouper over the log (name, CP), in order.
    static let phone: [String] = [
        "Rayquaza 4262",
        "Lucario 3000",
        "Staraptor 2819",
        "Zamazenta 2661",
        "Xerneas 2641",
        "Xerneas 2611",
        "Vaporeon 2480",
        "Blissey 2178",
        "Xurkitree 2173",
        "Zamazenta 2145",
        "Zamazenta 2133",
        "Scyther 2071",
        "Charizard 2017",
        "Lapras 2013",
        "Staraptor 2008",
        "Zapdos 2007",
        "Staraptor 1999",
        "Staraptor 1995",
        "Staraptor 1994",
        "Staraptor 1994",
        "Staraptor 1992",
        "Zapdos 1990",
        "Staraptor 1987",
        "Zapdos 1987",
        "Staraptor 1986",
        "Staraptor 1986",
        "Staraptor 1986",
        "Staraptor 1982",
        "Staraptor 1982",
        "Pinsir 1978",
        "Zapdos 1977",
        "Staraptor 1968",
        "Zapdos 1968",
        "Staraptor 1967",
        "Zapdos 1966",
        "Moltres 1966",
        "Zapdos 1965",
        "Meowscarada 1961",
        "Moltres 1960",
        "Zapdos 1957",
        "Staraptor 1951",
        "Staraptor 1946",
        "Moltres 1927",
        "Heatmor 1920",
        "Moltres 1920",
        "Moltres 1918",
        "Crustle 1913",
        "Moltres 1901",
        "Lapras 1885",
        "Meowscarada 1854",
        "Oricorio 1844"
    ]

    static let javascript: [String] = [
        "Rayquaza 4262",
        "Lucario 3000",
        "Staraptor 2819",
        "Zamazenta 2661",
        "Xerneas 2641",
        "Xerneas 2611",
        "Vaporeon 2480",
        "Blissey 2178",
        "Xurkitree 2173",
        "Zamazenta 2145",
        "Zamazenta 2133",
        "Scyther 2071",
        "Charizard 2017",
        "Lapras 2013",
        "Staraptor 2008",
        "Zapdos 2007",
        "Staraptor 1999",
        "Staraptor 1995",
        "Staraptor 1994",
        "Staraptor 1994",
        "Staraptor 1992",
        "Zapdos 1990",
        "Staraptor 1987",
        "Zapdos 1987",
        "Staraptor 1986",
        "Staraptor 1986",
        "Staraptor 1982",
        "Staraptor 1982",
        "Pinsir 1978",
        "Staraptor 1968",
        "Zapdos 1968",
        "Staraptor 1967",
        "Zapdos 1966",
        "Moltres 1966",
        "Zapdos 1965",
        "Meowscarada 1961",
        "Moltres 1960",
        "Zapdos 1957",
        "Staraptor 1951",
        "Staraptor 1946",
        "Moltres 1927",
        "Heatmor 1920",
        "Moltres 1920",
        "Moltres 1918",
        "Crustle 1913",
        "Moltres 1901",
        "Lapras 1885",
        "Meowscarada 1854",
        "Oricorio 1844"
    ]

    /// Refine's output (reconciled with LiveGrouper): the phone's list.
    static var refined: [String] { phone }

    func testLogLoads() throws {
        let l = try load()
        XCTAssertEqual(l.readings.count, 403)
        XCTAssertEqual(l.ticks.count, 46)
        XCTAssertEqual(l.malformedLines, 0)
        XCTAssertGreaterThan(l.drops, 0)
    }

    func testUnrefinedIsTheJavaScriptsFortyNine() throws {
        let r = try sharedEngine.finish(readings: try load().readings)
        XCTAssertEqual(r.rows.map(key), Self.javascript)
        XCTAssertEqual(r.rows.count, 49)
        XCTAssertEqual(r.unmatched.count, 2)
    }

    func testPhoneListIsLiveGrouperOverTheLog() throws {
        let u = try Fixture.url("device-run-2026-10-02.replay.jsonl")
        let res = ReplayLog.replay(ReplayLog.lines(in: u), species: try SpeciesTable.bundled())
        XCTAssertEqual(res.rows.map { "\($0.name) \($0.cp ?? 0)" }, Self.phone)
        XCTAssertEqual(res.rows.count, 51)
    }

    func testRefinedRows() throws {
        let l = try load()
        let base = try sharedEngine.finish(readings: l.readings)
        let r = try Refine.apply(to: base, readings: l.readings, ticks: l.ticks, engine: sharedEngine)
        XCTAssertEqual(r.scan.rows.map(key), Self.refined)
        // the tick-only rules (no LiveGrouper) get the count right but not the list: no tick lies between the twins, and the
        // unmatched Staraptor 1994 is listed twice
        let t = try Refine.applyTickOnly(to: base, readings: l.readings, ticks: l.ticks, engine: sharedEngine)
        XCTAssertNotEqual(t.scan.rows.map(key), Self.refined)
        XCTAssertEqual(r.scan.rows.count, 51)
        XCTAssertEqual(r.changes.map(\.kind).sorted { $0.rawValue < $1.rawValue }, [.hiddenCP, .twinSplit])
        // The Staraptor 1994 entry is the Pokemon on the row before it, but a mid-swipe reading lies between that row's card
        // reading and the entry (539.7 s), so it is not dropped as a duplicate (swipe evidence); LiveGrouper has no row of its
        // own for it either, so it is not converted: it stays in `unmatched`, which is where a doubt belongs.
        XCTAssertEqual(r.scan.unmatched.map { "\($0.name ?? "?") \($0.cpOptions ?? [])" }, ["Staraptor [1994]"])
        XCTAssertTrue(r.disagreements.isEmpty, "\(r.disagreements)")
        let twins = r.scan.rows.filter { $0.display == "Staraptor" && $0.cp == 1986 && $0.hp == 139 }
        XCTAssertEqual(twins.map { $0.flags.contains("same-as-previous") }, [false, true])
        XCTAssertEqual(twins.map { $0.frames.count }.reduce(0, +), 8, "the 8 frames of the merged row are divided between the two")
        let z = try XCTUnwrap(r.scan.rows.first { $0.display == "Zapdos" && $0.cp == 1977 })
        XCTAssertEqual(z.hp, 129)
        XCTAssertEqual(z.ivs, IVs(atk: 15, def: 12, hp: 10))
        XCTAssertTrue(z.flags.contains("cp-computed:1977"))
    }
}
