import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Twin split must come from a real swipe, not from LiveGrouper's fragments. The cases are cut from real clips
/// (Fixtures/twins: the owner's own recordings, see tools/cut-readings.mjs). Labels were made by looking at the frames:
/// TRUE twins are two Pokemon (a swipe between them), FALSE cases are one Pokemon that LiveGrouper cut in pieces
/// (the menu or the notification centre opened and closed, the team leader covering the CP, a one-frame gap).
final class TwinSplitTests: XCTestCase {
    private func refine(_ name: String) throws -> (base: ScanResult, refined: Refine.Refined) {
        let loaded = try ReplayReadings.load(url: Fixture.url("twins/\(name).json"))
        let base = try sharedEngine.finish(readings: loaded.readings)
        return (base, try Refine.apply(to: base, readings: loaded.readings, ticks: loaded.ticks, engine: sharedEngine))
    }

    /// (fixture, species) of one Pokemon that must stay one row.
    static let falseFragments: [(String, String)] = [
        ("axew-menu", "Axew"), ("charizard-376", "Charizard"), ("charizard-919", "Charizard"), ("hippopotas-745", "Hippopotas"),
        ("ipad-staraptor-1984", "Staraptor"), ("chansey-notifications", "Chansey"), ("zamazenta-menu", "Zamazenta"),
        ("lapras-menu", "Lapras"), ("zubat", "Zubat"),
    ]

    func testFalseFragmentsAreNotSplit() throws {
        for (name, species) in Self.falseFragments {
            let (base, r) = try refine(name)
            XCTAssertEqual(r.scan.rows.map { "\($0.display) \($0.cp)" }, base.rows.map { "\($0.display) \($0.cp)" }, "\(name): rows must be the JavaScript's \(species) rows")
            XCTAssertFalse(r.changes.contains { $0.kind == .twinSplit }, "\(name): \(r.changes)")
        }
    }

    func testTheRealTwinsAreSplit() throws {
        // marathon-phone: Staraptor 1986 (HP 139), a swipe between the two (one mid-swipe reading and a tick in the gap)
        let (base, r) = try refine("phone-twin-staraptor-1986")
        let before = base.rows.filter { $0.display == "Staraptor" && $0.cp == 1986 && $0.hp == 139 }.count
        let after = r.scan.rows.filter { $0.display == "Staraptor" && $0.cp == 1986 && $0.hp == 139 }
        XCTAssertEqual(before, 1)
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after.map { $0.flags.contains("same-as-previous") }, [false, true])
    }
}
