import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class BarsSplitTests: XCTestCase {
    private func load(_ name: String) throws -> ReplayReadings.Loaded { try ReplayReadings.load(url: Fixture.url(name)) }

    private func refine(_ readings: [FrameReading], ticks: [Double] = [], paging: PagingHint? = PagingHint(pagedByCommand: true)) throws -> Refine.Refined {
        let base = try sharedEngine.finish(readings: readings)
        return try Refine.apply(to: base, readings: readings, ticks: ticks, engine: sharedEngine, paging: paging)
    }

    private func fidough(_ r: Refine.Refined) -> [ScanRow] { r.scan.rows.filter { $0.display == "Fidough" && $0.cp == 768 } }

    // MARK: a stretch of the 313-Pokemon tap run (two different Fidough, CP 768, HP 89, on consecutive beats)

    func testTwoFidoughWithTheSameCpAndHpAreTwoRows() throws {
        let l = try load("device-run8-fidough-stretch.replay.jsonl")
        let base = try sharedEngine.finish(readings: l.readings)
        XCTAssertEqual(base.rows.filter { $0.display == "Fidough" && $0.cp == 768 }.count, 1, "the JavaScript joins them")
        let r = try refine(l.readings, ticks: l.ticks)
        let f = fidough(r)
        XCTAssertEqual(f.count, 2)
        XCTAssertEqual(f.map(\.hp), [89, 89])
        XCTAssertEqual(f.map(\.ivs), [IVs(atk: 15, def: 4, hp: 10), IVs(atk: 15, def: 11, hp: 12)])
        XCTAssertEqual(f.map { $0.flags.contains("split-by-bars") }, [true, true], "both parts are flagged: either may be the wrong one")
        XCTAssertFalse(f[1].flags.contains("same-as-previous"), "different Pokemon, not a repeat")
        XCTAssertEqual(f.map { $0.frames.count }.reduce(0, +), 6, "the six readings of the joined row are divided")
        XCTAssertEqual(r.changes.filter { $0.kind == .barsSplit }.count, 1)
        XCTAssertTrue(r.scan.review.contains { $0.cp == 768 && $0.flags.contains("split-by-bars") })
    }

    /// The first frame after a page shows the previous Pokemon's bars moving: ONE odd reading must never split a row.
    func testASingleOddFirstReadingDoesNotSplit() throws {
        var readings = try load("device-run8-fidough-stretch.replay.jsonl").readings
        // make the second Fidough's bars one reading only (the rest equal to the first Fidough's)
        let idx = readings.indices.filter { readings[$0].name == "Fidough" && readings[$0].ivs == IVs(atk: 15, def: 11, hp: 12) }
        XCTAssertGreaterThanOrEqual(idx.count, 2)
        for i in idx.dropFirst() { readings[i].ivs = IVs(atk: 15, def: 4, hp: 10) }
        let f = fidough(try refine(readings))
        XCTAssertEqual(f.count, 1)
        XCTAssertFalse(f[0].flags.contains("split-by-bars"))
    }

    func testStatesNeedSettledReadings() throws {
        var readings = try load("device-run8-fidough-stretch.replay.jsonl").readings
        for i in readings.indices where readings[i].name == "Fidough" && readings[i].ivs == IVs(atk: 15, def: 11, hp: 12) { readings[i].ivConfidence = 0.4 }
        XCTAssertEqual(fidough(try refine(readings)).count, 1, "unsettled bars are not a state")
    }

    func testNoSplitWithAnIrregularBeatAndNothingBetween() throws {
        // the same readings with the unreadable frame between the two Fidough removed and the times closed up: no beat, no gap
        var readings = try load("device-run8-fidough-stretch.replay.jsonl").readings
        let fi = readings.indices.filter { readings[$0].name == "Fidough" }
        let first = fi.first!, last = fi.last!
        let gapAt = (first...last).filter { readings[$0].cp == nil && readings[$0].hp == nil }
        for g in gapAt.reversed() { readings.remove(at: g) }
        let fidoughAt = readings.indices.filter { readings[$0].name == "Fidough" }
        // consecutive 0.2 s readings
        for (k, i) in fidoughAt.enumerated() { readings[i].time = readings[fidoughAt[0]].time! + Double(k) * 0.2 }
        let r = try refine(readings, paging: nil)
        XCTAssertEqual(r.changes.filter { $0.kind == .barsSplit }.count, 0)
    }

    // MARK: the fallback branch (no regular beat), fourth review round

    /// Only the two Fidough's readings, evenly spaced `every` seconds: a lone row with no beat around it, so the fallback decides.
    private func loneFidough(every: Double) throws -> [FrameReading] {
        let all = try load("device-run8-fidough-stretch.replay.jsonl").readings
        let t0 = all.filter { $0.name == "Fidough" }.compactMap(\.time).min()!   // the 768 pair is the first Fidough block: six readings
        var rs = all.filter { $0.name == "Fidough" && $0.ivs != nil && $0.time! < t0 + 2.2 }
        for k in rs.indices { rs[k].time = 500 + Double(k) * every }
        return rs
    }

    func testTheFallbackNeedsRealEvidenceNotAShortGap() throws {
        let slow = try loneFidough(every: 0.8)       // each state held for at least 0.6 of a 1.2 s period
        // no period known: the row is not split and keeps its ivs-disagree (a gap of 0.4 s is every gap at the tap reading rate)
        let none = try refine(slow, paging: nil)
        XCTAssertEqual(fidough(none).count, 1)
        XCTAssertTrue(fidough(none)[0].flags.contains("ivs-disagree"))
        // a period known and each state held for at least 0.6 of it: split, and BOTH parts are flagged
        let hinted = try refine(slow, paging: PagingHint(pagedByCommand: true, expectedPeriod: 1.2))
        let f = fidough(hinted)
        XCTAssertEqual(f.count, 2)
        XCTAssertEqual(f.map { $0.flags.contains("split-by-bars") }, [true, true], "the first part can solve exactly on transient bars: it is flagged too")
        // states held for less than 0.6 of the period (reads 0.1 s apart): not split even with the period known
        let quick = try loneFidough(every: 0.1)
        XCTAssertEqual(fidough(try refine(quick, paging: PagingHint(pagedByCommand: true, expectedPeriod: 1.2))).count, 1)
    }

    // MARK: the whole run

    /// 313 Pokemon on a 1.2 s tap beat: 310 rows from the JavaScript plus the second Fidough; three one-Pokemon-read-three-times
    /// fragments (Quaxly 772, Honedge 760, Skarmory 717) are absorbed; every other row with disagreeing bars is one Pokemon
    /// (one odd reading, the previous Pokemon's bars on their way).
    func testTheThreeHundredRunGivesThreeHundredAndEleven() throws {
        let l = try load("device-run8-tap-300.replay.jsonl")
        let r = try refine(l.readings, ticks: l.ticks, paging: PagingHint(pagedByCommand: true, expectedPeriod: 1.2))
        XCTAssertEqual(r.scan.rows.count, 310, "311 until round 24, which also absorbs the Heatmor 64 fragment of 764 (HP 92, fits no level)")
        XCTAssertEqual(r.changes.filter { $0.kind == .barsSplit }.count, 1)
        XCTAssertEqual(r.changes.filter { $0.kind == .fragmentAbsorbed }.map { $0.detail.prefix(14) }.sorted(), ["Heatmor CP 64 ", "Honedge CP 760", "Quaxly CP 772 ", "Skarmory CP 71"])
        XCTAssertEqual(fidough(r).count, 2)
        // each change points at the row it is about (by the kept row's frames, not by the first row that has the same flag text)
        for c in r.changes where c.kind == .fragmentAbsorbed || c.kind == .barsSplit {
            XCTAssertGreaterThan(c.rowIndex, 0, c.detail)
            let row = r.scan.rows[c.rowIndex - 1]
            XCTAssertTrue(c.detail.hasPrefix(row.display), "\(c.detail) belongs to row \(c.rowIndex), \(row.display)")
        }
        // no row left with two states of bars
        for row in r.scan.rows where row.flags.contains("ivs-disagree") {
            var runs = [(String, Int)]()
            for f in row.frames.sorted(by: { $0.time! < $1.time! }) where (f.ivConfidence ?? 0) >= 0.7 && f.ivs != nil {
                if let last = runs.last, last.0 == f.ivs! { runs[runs.count - 1].1 += 1 } else { runs.append((f.ivs!, 1)) }
            }
            XCTAssertLessThan(runs.filter { $0.1 >= 2 }.count, 2, "\(row.display) \(row.cp): \(runs)")
        }
    }

    func testTheKnownRunsAreUnchanged() throws {
        for (name, rows, paging) in [("device-run5-tap-1.2.replay.jsonl", 51, PagingHint(pagedByCommand: true)), ("device-run7-tap-1.2-phantom.replay.jsonl", 51, PagingHint(pagedByCommand: true)),
                                     ("device-run4-fast-swipe-2026-10-02.replay.jsonl", 51, nil), ("device-run-2026-10-02.replay.jsonl", 51, nil), ("device-run3-2026-10-02.replay.jsonl", 49, nil)] as [(String, Int, PagingHint?)] {
            let l = try load(name)
            let r = try refine(l.readings, ticks: l.ticks, paging: paging)
            XCTAssertEqual(r.scan.rows.count, rows, name)
            XCTAssertEqual(r.changes.filter { $0.kind == .barsSplit }.count, 0, name)
        }
    }
}
