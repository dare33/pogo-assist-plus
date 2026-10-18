import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class GrouperDiffTests: XCTestCase {
    private func row(_ i: Int, _ name: String, _ cp: Int, hp: Int = 100, ivs: IVs? = IVs(atk: 1, def: 2, hp: 3), flags: [String] = []) -> ScanRow {
        ScanRow(index: i, name: name, display: name, form: "", speciesId: name.lowercased(), dex: 1, cp: cp, hp: hp, ivs: ivs, ivsRead: ivs, ivsGuess: nil,
                level: 20, levelMax: 20, dust: 0, solveStatus: "exact", flags: flags, frames: [], merged: nil, shadow: nil, clip: nil)
    }
    private func live(_ i: Int, _ name: String, _ cp: Int?, hp: Int? = 100, ivs: IVs? = IVs(atk: 1, def: 2, hp: 3), flags: [String] = []) -> LiveRow {
        // LiveRow has no public initialiser (LiveGrouper.swift is not ours to edit): build it through Codable.
        var o: [String: Any] = ["index": i, "name": name, "frames": 5, "flags": flags]
        if let cp { o["cp"] = cp }
        if let hp { o["hp"] = hp }
        if let ivs { o["ivs"] = ["atk": ivs.atk, "def": ivs.def, "hp": ivs.hp] }
        return try! JSONDecoder().decode(LiveRow.self, from: JSONSerialization.data(withJSONObject: o))
    }

    func testAlignsByNameAndCpAndReportsTheDifferences() {
        let refined = [row(1, "Zapdos", 1000), row(2, "Lucario", 3000), row(3, "Pinsir", 1978, hp: 111), row(4, "Moltres", 996, flags: ["no-level-fits"])]
        let liveRows = [live(1, "Zapdos", 1000), live(2, "Eevee", 500), live(3, "Pinsir", 1978, hp: 110), live(4, "Moltres", 996, ivs: IVs(atk: 9, def: 9, hp: 9), flags: ["short-run"])]
        let d = GrouperDiff.compare(refined: refined, live: liveRows)
        XCTAssertEqual(d.matched.count, 3)
        XCTAssertEqual(d.onlyRefined.map(\.display), ["Lucario"])
        XCTAssertEqual(d.onlyLive.map(\.name), ["Eevee"])
        XCTAssertEqual(d.hpDiffers.map { $0.refined.display }, ["Pinsir"])
        XCTAssertEqual(d.ivsDiffers.map { $0.refined.display }, ["Moltres"])
        XCTAssertEqual(d.flagsDiffer.map { $0.refined.display }, ["Moltres"])
        let text = d.report()
        XCTAssertTrue(text.contains("both (name + CP): 3; only refined: 1; only LiveGrouper: 1"))
        XCTAssertTrue(text.contains("only refined   #2 Lucario CP 3000"))
    }

    func testExtraRowsDoNotShiftTheAlignment() {
        let refined = [row(1, "A", 1), row(2, "A", 1), row(3, "B", 2)]
        let liveRows = [live(1, "A", 1), live(2, "B", 2)]
        let d = GrouperDiff.compare(refined: refined, live: liveRows)
        XCTAssertEqual(d.matched.count, 2)
        XCTAssertEqual(d.onlyRefined.count, 1)
        XCTAssertTrue(d.onlyLive.isEmpty)
    }

    func testEmptySides() {
        XCTAssertEqual(GrouperDiff.compare(refined: [], live: []).matched.count, 0)
        XCTAssertEqual(GrouperDiff.compare(refined: [row(1, "A", 1)], live: []).onlyRefined.count, 1)
        XCTAssertEqual(GrouperDiff.compare(refined: [], live: [live(1, "A", 1)]).onlyLive.count, 1)
    }

    func testRunsLiveGrouperOverTheFixtureReadings() throws {
        let readings = try Fixture.readings()
        let base = try sharedEngine.finish(readings: readings)
        let d = GrouperDiff.compute(refined: base.rows, readings: readings, ticks: [])
        XCTAssertEqual(d.refinedCount, 6)
        XCTAssertGreaterThan(d.liveCount, 0)
        XCTAssertGreaterThan(d.matched.count, 3, d.report())
    }
}
