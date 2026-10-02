import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class FragmentTests: XCTestCase {
    /// The known 51 of the tap runs: the phone's list, where the first Staraptor is read as the Mega it is ("Mega Staraptor 3970"; run1
    /// read the same Pokemon as "Staraptor 2819", one place later).
    static let tapTruth: [String] = {
        var l = DeviceRunTests.phone.filter { $0 != "Staraptor 2819" }
        l.insert("Mega Staraptor 3970", at: 1)
        return l
    }()

    // MARK: hand-built rows

    private func frame(_ t: Double, cp: Int?, hp: String? = "100/100", ivs: String? = "1/2/3", conf: Double = 0.9) -> FrameLabel {
        FrameLabel(frame: "f\(Int(t * 100))", time: t, cp: cp, cpText: cp.map(String.init), name: "Mon", hp: hp, ivs: ivs, ivConfidence: conf, sharpness: 1, clip: nil)
    }

    private func row(_ i: Int, _ name: String, cp: Int, hp: Int? = 100, bars: IVs? = IVs(atk: 1, def: 2, hp: 3), times: [Double], conf: Double = 0.9) -> ScanRow {
        ScanRow(index: i, name: name, display: name, form: "", speciesId: name.lowercased(), dex: 1, cp: cp, hp: hp, ivs: bars, ivsRead: bars, ivsGuess: nil, level: 20, levelMax: 20, dust: 0,
                solveStatus: "exact", flags: [], frames: times.map { frame($0, cp: cp, hp: hp.map { "\($0)/\($0)" }, ivs: bars.map { "\($0.atk)/\($0.def)/\($0.hp)" }, conf: conf) })
    }

    /// 1.2 s beat, one row per period, four readings each; `rows[at]` is replaced by the given rows.
    private func beat(_ n: Int = 14, replacing at: Int = 6, with replacement: [ScanRow]) -> ScanResult {
        var rows = [ScanRow]()
        for k in 0..<n {
            if k == at { rows += replacement; continue }
            let t0 = 100 + Double(k) * 1.2
            rows.append(row(0, "Mon\(k)", cp: 500 + k, times: [t0 + 0.1, t0 + 0.4, t0 + 0.7, t0 + 1.0]))
        }
        for i in rows.indices { rows[i].index = i + 1 }
        return ScanResult(rows: rows, review: [], unmatched: [])
    }

    func testAFragmentNextToTheSameSpeciesIsAbsorbed() {
        let t0 = 100 + 6 * 1.2
        // the first frame of Moltres read a different CP; the rest of the stay is the real row
        let frag = row(0, "Moltres", cp: 1910, bars: IVs(atk: 13, def: 10, hp: 10), times: [t0 + 0.1])
        let real = row(0, "Moltres", cp: 1918, bars: IVs(atk: 13, def: 10, hp: 10), times: [t0 + 0.4, t0 + 0.7, t0 + 1.0])
        let s = beat(replacing: 6, with: [frag, real])
        XCTAssertEqual(s.rows.count, 15)
        let r = Refine.absorbFragments(s)
        XCTAssertEqual(r.scan.rows.count, 14)
        let kept = r.scan.rows[6]
        XCTAssertEqual(kept.cp, 1918)
        XCTAssertEqual(kept.ivs, IVs(atk: 13, def: 10, hp: 10), "the fragment does not change the neighbour's values")
        XCTAssertEqual(kept.flags, ["absorbed-fragment:1910"])
        XCTAssertEqual(r.marks.count, 1)
        XCTAssertEqual(r.scan.review.map(\.index), [7])
        XCTAssertEqual(r.scan.rows.map(\.index), Array(1...14))
    }

    func testBarsWithinOneUnitWhenUnsettledAreAbsorbedAndSettledOnesAreNot() {
        let t0 = 100 + 6 * 1.2
        let real = row(0, "Moltres", cp: 1918, bars: IVs(atk: 13, def: 10, hp: 10), times: [t0 + 0.4, t0 + 0.7, t0 + 1.0])
        let unsettled = row(0, "Moltres", cp: 1910, bars: IVs(atk: 12, def: 10, hp: 10), times: [t0 + 0.1], conf: 0.4)
        XCTAssertEqual(Refine.absorbFragments(beat(replacing: 6, with: [unsettled, real])).scan.rows.count, 14)
        let settled = row(0, "Moltres", cp: 1910, bars: IVs(atk: 12, def: 10, hp: 10), times: [t0 + 0.1], conf: 0.9)
        XCTAssertEqual(Refine.absorbFragments(beat(replacing: 6, with: [settled, real])).scan.rows.count, 15, "settled and different bars: not the same Pokemon")
        let far = row(0, "Moltres", cp: 1910, bars: IVs(atk: 9, def: 10, hp: 10), times: [t0 + 0.1], conf: 0.4)
        XCTAssertEqual(Refine.absorbFragments(beat(replacing: 6, with: [far, real])).scan.rows.count, 15, "three units off is not one unit")
        let unread = row(0, "Moltres", cp: 1910, bars: nil, times: [t0 + 0.1])
        XCTAssertEqual(Refine.absorbFragments(beat(replacing: 6, with: [unread, real])).scan.rows.count, 14, "unread bars")
    }

    func testAnotherPokemonIsNeverAbsorbed() {
        let t0 = 100 + 6 * 1.2
        let real = row(0, "Moltres", cp: 1918, hp: 129, bars: IVs(atk: 13, def: 10, hp: 10), times: [t0 + 0.4, t0 + 0.7, t0 + 1.0])
        // settled different bars AND a different HP
        let other = row(0, "Moltres", cp: 1901, hp: 131, bars: IVs(atk: 5, def: 6, hp: 7), times: [t0 + 0.1])
        XCTAssertEqual(Refine.absorbFragments(beat(replacing: 6, with: [other, real])).scan.rows.count, 15)
        // a different species
        let species = row(0, "Zapdos", cp: 1901, hp: 129, bars: IVs(atk: 13, def: 10, hp: 10), times: [t0 + 0.1])
        XCTAssertEqual(Refine.absorbFragments(beat(replacing: 6, with: [species, real])).scan.rows.count, 15)
        // same bars, different HP, bars read (but not settled) equal: HP alone is not equal, so not absorbed
        let hp = row(0, "Moltres", cp: 1901, hp: 131, bars: IVs(atk: 13, def: 10, hp: 10), times: [t0 + 0.1])
        XCTAssertEqual(Refine.absorbFragments(beat(replacing: 6, with: [hp, real])).scan.rows.count, 15)
    }

    func testTwoPokemonOfTheSameSpeciesOnTheBeatAreNotFragments() {
        // two Moltres, each backed by one reading, one period apart: a paging boundary lies between them
        let t0 = 100 + 6 * 1.2
        let a = row(0, "Moltres", cp: 1918, bars: IVs(atk: 13, def: 10, hp: 10), times: [t0 + 0.5])
        let b = row(0, "Moltres", cp: 1918, bars: IVs(atk: 13, def: 10, hp: 10), times: [t0 + 1.7])
        var s = beat(replacing: 6, with: [a, b])
        // make room: the beat around them is steady, the two stays are one period each
        s.rows = Array(s.rows.prefix(7)) + s.rows.suffix(from: 7).map { var r = $0; r.frames = r.frames.map { var f = $0; f.time! += 1.2; return f }; return r }
        XCTAssertEqual(Refine.absorbFragments(s).scan.rows.count, s.rows.count)
    }

    func testWithNoBeatItFallsBackToConsecutiveReadings() {
        let real = row(1, "Moltres", cp: 1918, bars: IVs(atk: 13, def: 10, hp: 10), times: [10.4, 10.6, 10.8])
        let frag = row(2, "Moltres", cp: 1910, bars: IVs(atk: 13, def: 10, hp: 10), times: [10.2])
        let near = ScanResult(rows: [frag, real], review: [], unmatched: [])
        XCTAssertEqual(Refine.absorbFragments(near).scan.rows.count, 1)
        let late = row(2, "Moltres", cp: 1910, bars: IVs(atk: 13, def: 10, hp: 10), times: [9.5])
        XCTAssertEqual(Refine.absorbFragments(ScanResult(rows: [late, real], review: [], unmatched: [])).scan.rows.count, 2, "0.9 s apart")
    }

    // MARK: the device logs

    private func refine(_ fixture: String, paging: PagingHint? = PagingHint(pagedByCommand: true)) throws -> Refine.Refined {
        let l = try ReplayReadings.load(url: Fixture.url(fixture))
        let base = try sharedEngine.finish(readings: l.readings)
        return try Refine.apply(to: base, readings: l.readings, ticks: l.ticks, engine: sharedEngine, paging: paging)
    }

    /// Tap 1.2 s, the Moltres whose first frame read CP1910 (the wing over the last digit; the true CP is 1918).
    func testTheMoltresPhantomIsGone() throws {
        let r = try refine("device-run7-tap-1.2-phantom.replay.jsonl", paging: PagingHint(pagedByCommand: true, expectedPeriod: 1.2))
        XCTAssertEqual(r.scan.rows.map { "\($0.display) \($0.cp)" }, Self.tapTruth)
        XCTAssertFalse(r.scan.rows.contains { $0.display == "Moltres" && $0.cp == 1910 })
        let m = try XCTUnwrap(r.scan.rows.first { $0.display == "Moltres" && $0.cp == 1918 })
        XCTAssertEqual(m.hp, 129)
        XCTAssertEqual(m.ivs, IVs(atk: 13, def: 10, hp: 10))
        XCTAssertTrue(m.flags.contains("cp-outlier-dropped:1910"))
        XCTAssertTrue(r.scan.review.contains { $0.cp == 1918 }, "the change shows in review")
        XCTAssertEqual(r.changes.filter { $0.kind == .cpOutlierDropped }.count, 1)
        let pair = r.scan.rows.filter { $0.display == "Staraptor" && $0.cp == 1986 && $0.hp == 139 }
        XCTAssertEqual(pair.count, 2)
        XCTAssertTrue(pair[1].flags.contains("split-by-timing"))
        XCTAssertTrue(r.scan.unmatched.isEmpty)
    }

    func testTheCleanTapRunStaysFiftyOne() throws {
        let r = try refine("device-run5-tap-1.2.replay.jsonl", paging: PagingHint(pagedByCommand: true, expectedPeriod: 1.2))
        XCTAssertEqual(r.scan.rows.map { "\($0.display) \($0.cp)" }, Self.tapTruth)
        XCTAssertFalse(r.changes.contains { $0.kind == .fragmentAbsorbed || $0.kind == .cpOutlierDropped })
    }

    /// Tap 1.0 s (one reading per Pokemon). What it gives today, pinned so a change is seen: the phantom Scyther 2017 and the
    /// duplicate Charizard 2017 are no longer rows (each came from ONE frame, a hidden CP computed from mid-animation bars, and
    /// stays visible in `unmatched`), but two things are still wrong:
    /// - the Moltres whose CP read only "19" is listed as "Moltres 19" (the true CP is 1960; a PREFIX of the CP was read, and the
    ///   recovery in the JavaScript only knows tails);
    /// - the second Staraptor 1986 (HP 139, the identical pair) is missing: the beat at 1.0 s is not regular enough (regularity 0.20)
    ///   for the timing split.
    func testTheOneSecondTapRunPinned() throws {
        let r = try refine("device-run6-tap-1.0.replay.jsonl")
        let got = r.scan.rows.map { "\($0.display) \($0.cp)" }
        XCTAssertEqual(got.count, 50)
        XCTAssertFalse(got.contains("Scyther 2017"))
        XCTAssertEqual(got.filter { $0 == "Charizard 2017" }.count, 1)
        XCTAssertEqual(Set(Self.tapTruth).subtracting(got), ["Moltres 1960"])
        XCTAssertEqual(Self.tapTruth.filter { $0 == "Staraptor 1986" }.count - got.filter { $0 == "Staraptor 1986" }.count, 1, "one of the identical pair is missing")
        XCTAssertTrue(got.contains("Moltres 19"))
        XCTAssertEqual(r.scan.unmatched.map { "\($0.name ?? "?") \($0.cpOptions ?? [])" }.sorted(), ["Charizard [2017]", "Scyther [2017]"])
    }

    // MARK: real clips (opt-in)

    func testRealClipsRowCountsWithFragmentAbsorption() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["POGO_PARITY"] == "1", "set POGO_PARITY=1 to run the real-data checks")
        let dir = ProcessInfo.processInfo.environment["POGO_FRAMES_OUT"] ?? "/Users/greg-mb/Developer/personal/pogo-frames/_out"
        for (name, rows) in [("marathon-phone", 47), ("v3", 109), ("darentas-01", 449), ("darentas-02", 771), ("darentas-03", 144), ("marathon-ipad-mini", 46)] as [(String, Int)] {
            let url = URL(fileURLWithPath: "\(dir)/\(name).swift.readings.json")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let l = try ReplayReadings.load(url: url)
            let base = try sharedEngine.finish(readings: l.readings)
            let r = try Refine.apply(to: base, readings: l.readings, ticks: l.ticks, engine: sharedEngine)
            print("FRAGMENT \(name): base \(base.rows.count) refined \(r.scan.rows.count) absorbed \(r.changes.filter { $0.kind == .fragmentAbsorbed }.count) outliers \(r.changes.filter { $0.kind == .cpOutlierDropped }.count)")
            XCTAssertEqual(r.scan.rows.count, rows, name)
        }
    }
}
