import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class RefineTests: XCTestCase {
    private func hiddenFixture() throws -> (readings: [FrameReading], base: ScanResult) {
        let readings = try ReplayReadings.load(url: Fixture.url("hidden/readings.json")).readings
        return (readings, try sharedEngine.finish(readings: readings))
    }

    /// The first Pokémon of the fixture (seven readings, 0 to 1.2 s), repeated `copies` times `period` seconds
    /// apart: identical neighbours, which the JavaScript merges into one row.
    private func twins(copies: Int, period: Double) throws -> [FrameReading] {
        let one = Array(try Fixture.readings().prefix(7))
        var out = [FrameReading]()
        for c in 0..<copies {
            for r in one { var x = r; x.frame = "t\(c)-\(r.frame ?? "")"; x.time = (r.time ?? 0) + Double(c) * period; out.append(x) }
        }
        return out
    }

    private func refine(_ readings: [FrameReading], ticks: [Double]) throws -> (base: ScanResult, refined: Refine.Refined) {
        let base = try sharedEngine.finish(readings: readings)
        return (base, try Refine.apply(to: base, readings: readings, ticks: ticks, engine: sharedEngine))
    }

    // MARK: twin split

    func testTwinsAreSplitAtTheTick() throws {
        let readings = try twins(copies: 2, period: 2.0)
        let (base, r) = try refine(readings, ticks: [1.6])
        XCTAssertEqual(base.rows.count, 1, "the JavaScript merges the identical neighbours")
        XCTAssertEqual(r.baseRowCount, 1)
        XCTAssertEqual(r.scan.rows.count, 2)
        let (a, b) = (r.scan.rows[0], r.scan.rows[1])
        XCTAssertEqual([a.index, b.index], [1, 2])
        XCTAssertEqual(RowKey(a).cp, RowKey(b).cp)
        XCTAssertEqual(a.ivs, b.ivs); XCTAssertEqual(a.hp, b.hp); XCTAssertEqual(a.level, b.level)
        XCTAssertFalse(a.flags.contains("same-as-previous"))
        XCTAssertTrue(b.flags.contains("same-as-previous"))
        XCTAssertEqual([a.frames.count, b.frames.count], [7, 7])
        XCTAssertTrue(a.frames.allSatisfy { $0.frame!.hasPrefix("t0-") } && b.frames.allSatisfy { $0.frame!.hasPrefix("t1-") })
        XCTAssertEqual(r.changes.map(\.kind), [.twinSplit])
        XCTAssertEqual(r.changes.map(\.rowIndex), [2])
        XCTAssertEqual(r.scan.review.map(\.index), [2], "review lists the flagged rows, renumbered")
    }

    func testThreeTwinsGiveThreeRows() throws {
        let (base, r) = try refine(try twins(copies: 3, period: 2.0), ticks: [3.6, 1.6])   // unsorted on purpose
        XCTAssertEqual(base.rows.count, 1)
        XCTAssertEqual(r.scan.rows.map(\.index), [1, 2, 3])
        XCTAssertEqual(r.scan.rows.map { $0.flags.contains("same-as-previous") }, [false, true, true])
        XCTAssertEqual(r.scan.rows.map { $0.frames.count }, [7, 7, 7])
        XCTAssertEqual(r.changes.map(\.rowIndex), [2, 3])
    }

    func testNoTicksNoSplit() throws {
        let (base, r) = try refine(try twins(copies: 2, period: 2.0), ticks: [])
        XCTAssertEqual(r.scan, base)
        XCTAssertTrue(r.changes.isEmpty)
    }

    func testTicksThatDoNotQualifyChangeNothing() throws {
        let readings = try twins(copies: 2, period: 2.0)   // frames 0...1.2 and 2.0...3.2
        for ticks in [[5.0], [-1.0], [0.0], [3.2], [0.5], [2.6], [Double.nan], [0.3, 2.9]] as [[Double]] {
            let (base, r) = try refine(readings, ticks: ticks)
            XCTAssertEqual(r.scan, base, "ticks \(ticks): outside the span, on its edge, or inside one stay (readings 0.2 s apart)")
        }
    }

    func testTheGapMustBeAtLeastAswipe() throws {
        // last card reading of the first Pokémon at 1.2 s
        let (_, enough) = try refine(try twins(copies: 2, period: 1.75), ticks: [1.5])      // next reading at 1.75: 0.55 s
        XCTAssertEqual(enough.scan.rows.count, 2)
        let (_, short) = try refine(try twins(copies: 2, period: 1.7), ticks: [1.5])        // next reading at 1.70: 0.50 s
        XCTAssertEqual(short.scan.rows.count, 1)
    }

    func testARowWithoutTimesIsLeftAlone() throws {
        var readings = try twins(copies: 2, period: 2.0)
        for i in readings.indices { readings[i].time = nil }
        let base = try sharedEngine.finish(readings: readings)
        let r = try Refine.apply(to: base, readings: readings, ticks: [1.6], engine: sharedEngine)
        XCTAssertEqual(r.scan.rows.count, base.rows.count)
    }

    func testRefineWithNothingToDoReproducesTheJavaScriptResult() throws {
        let readings = try Fixture.readings()
        let base = try sharedEngine.finish(readings: readings)
        let r = try Refine.apply(to: base, readings: readings, ticks: [], engine: sharedEngine)
        XCTAssertEqual(r.scan, base, "rows, review and unmatched are rebuilt identically")
    }

    // MARK: hidden CP

    func testHiddenCpRowIsAddedInPlace() throws {
        let (readings, base) = try hiddenFixture()
        XCTAssertEqual(base.rows.count, 4)
        XCTAssertEqual(base.unmatched.count, 1)
        let r = try Refine.apply(to: base, readings: readings, ticks: [], engine: sharedEngine)
        XCTAssertEqual(r.scan.rows.map { "\($0.display) \($0.cp)" }, ["Staraptor 1982", "Pinsir 1978", "Zapdos 1977", "Staraptor 1968", "Zapdos 1968"])
        let z = r.scan.rows[2]
        XCTAssertEqual(z.index, 3)
        XCTAssertEqual(z.hp, 129)
        XCTAssertEqual(z.ivs, IVs(atk: 15, def: 12, hp: 10))
        XCTAssertEqual(z.speciesId, "zapdos")
        XCTAssertNotNil(z.level)
        XCTAssertTrue(z.flags.contains("cp-computed:1977"), "\(z.flags)")
        XCTAssertTrue(r.scan.unmatched.isEmpty)
        XCTAssertEqual(r.scan.rows.map(\.index), [1, 2, 3, 4, 5])
        XCTAssertEqual(r.scan.review.map(\.index), [3])
        XCTAssertEqual(r.changes, [Refine.Change(kind: .hiddenCP, rowIndex: 3, detail: "Zapdos CP 1977: computed from HP and bars, was unmatched")])
        // the other rows are the JavaScript's, untouched apart from their numbers
        XCTAssertEqual(r.scan.rows[0].cp, base.rows[0].cp)
        XCTAssertEqual(r.scan.rows[4].cp, base.rows[3].cp)
    }

    func testHiddenCpEntriesThatDoNotQualifyStayUnmatched() throws {
        let (readings, base) = try hiddenFixture()
        let good = base.unmatched[0]
        let variants: [(String, (inout Unmatched) -> Void)] = [
            ("two options", { $0.cpOptions = [1977, 1978] }),
            ("no option", { $0.cpOptions = [] }),
            ("options missing", { $0.cpOptions = nil }),
            ("no name", { $0.name = nil }),
            ("no HP", { $0.hp = nil }),
            ("bars not settled", { $0.ivs = nil }),
            ("another reason", { $0.reason = "name-not-read" }),
            ("an absorbed entry", { $0.reason = "absorbed" }),
            ("unknown frame", { $0.frame = "nowhere.png" }),
            ("no frame", { $0.frame = nil }),
        ]
        for (label, change) in variants {
            var u = good; change(&u)
            let mutated = ScanResult(rows: base.rows, review: base.review, unmatched: [u])
            let r = try Refine.apply(to: mutated, readings: readings, ticks: [], engine: sharedEngine)
            XCTAssertEqual(r.scan.rows.count, 4, label)
            XCTAssertEqual(r.scan.unmatched, [u], label)
            XCTAssertTrue(r.changes.isEmpty, label)
        }
    }

    func testFixtureWithoutHiddenEntriesIsUntouched() throws {
        let readings = try Fixture.readings()
        let base = try sharedEngine.finish(readings: readings)
        XCTAssertTrue(base.unmatched.isEmpty)
        XCTAssertEqual(try Refine.apply(to: base, readings: readings, ticks: [0.5, 1.0], engine: sharedEngine).scan.rows.count, base.rows.count)
    }

    // MARK: reconciliation with LiveGrouper

    func testReconciliationRefusesToSplitWhenTheGrouperDisagreesOnHp() throws {
        let readings = try twins(copies: 2, period: 2.0)
        var base = try sharedEngine.finish(readings: readings)
        XCTAssertEqual(base.rows.count, 1)
        let live = GrouperDiff.liveRows(readings: readings, ticks: [1.6])
        XCTAssertEqual(live.count, 2, "LiveGrouper sees the two Pokemon")
        base.rows[0].hp = 999
        let r = try Refine.apply(to: base, readings: readings, ticks: [1.6], engine: sharedEngine)
        XCTAssertEqual(r.scan.rows.count, 1)
        XCTAssertEqual(r.disagreements.count, 1)
        XCTAssertTrue(r.disagreements[0].hasPrefix("grouper-disagrees"))
        // and the same readings, agreeing, split
        let ok = try Refine.apply(to: try sharedEngine.finish(readings: readings), readings: readings, ticks: [1.6], engine: sharedEngine)
        XCTAssertEqual(ok.scan.rows.count, 2)
        XCTAssertTrue(ok.disagreements.isEmpty)
    }

    func testReconciliationDoesNotSplitWithoutAnyEvidenceOfASwipe() throws {
        // two identical Pokemon back to back with readings every 0.2 s and no tick: LiveGrouper sees one stay too
        let one = Array(try Fixture.readings().prefix(7))
        var readings = one
        for r in one { var x = r; x.frame = "b-\(r.frame ?? "")"; x.time = (r.time ?? 0) + 1.4; readings.append(x) }
        let base = try sharedEngine.finish(readings: readings)
        let r = try Refine.apply(to: base, readings: readings, ticks: [], engine: sharedEngine)
        XCTAssertEqual(r.scan.rows.count, base.rows.count)
    }

    func testTickOnlyRulesStillWork() throws {
        let readings = try twins(copies: 2, period: 2.0)
        let base = try sharedEngine.finish(readings: readings)
        XCTAssertEqual(try Refine.applyTickOnly(to: base, readings: readings, ticks: [1.6], engine: sharedEngine).scan.rows.count, 2)
        XCTAssertEqual(try Refine.applyTickOnly(to: base, readings: readings, ticks: [], engine: sharedEngine).scan.rows.count, 1)
    }

    func testAHiddenEntryBesideTheSamePokemonIsDroppedAsADuplicate() throws {
        let (readings, base) = try hiddenFixture()
        // make the unmatched Zapdos look like the row before it: put a Zapdos row, same HP and bars and the entry's CP, in front
        var twin = base.rows[1]
        twin.display = "Zapdos"; twin.name = "Zapdos"; twin.cp = 1977; twin.hp = 129; twin.ivs = IVs(atk: 15, def: 12, hp: 10)
        let t0 = readings.first { $0.name == "Zapdos" && $0.cp == nil }!.time!
        twin.frames = [FrameLabel(frame: nil, time: t0 - 0.4, cp: 1977, cpText: "1977", name: "Zapdos", hp: "129/129", ivs: nil, ivConfidence: nil, sharpness: nil, clip: nil)]
        var mutated = base
        mutated.rows.insert(twin, at: 2)
        let r = try Refine.apply(to: mutated, readings: readings, ticks: [], engine: sharedEngine)
        XCTAssertEqual(r.scan.rows.count, 5, "no extra row for the entry")
        XCTAssertTrue(r.scan.unmatched.isEmpty)
        XCTAssertEqual(r.changes.map(\.kind), [.duplicateDropped])
    }

    // MARK: real data (opt-in)

    /// marathon-phone: the JavaScript's 45 rows plus the second Staraptor CP 1986 (a twin the grouping merged,
    /// split at a swipe tick) and the hidden-CP Zapdos 1977 make the 47 rows of the phone's real clip.
    func testMarathonPhoneRefinesToFortySevenRows() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["POGO_PARITY"] == "1", "set POGO_PARITY=1 to run the real-data checks")
        let file = URL(fileURLWithPath: (ProcessInfo.processInfo.environment["POGO_FRAMES_OUT"] ?? "/Users/greg-mb/Developer/personal/pogo-frames/_out") + "/marathon-phone.swift.readings.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: file.path), "marathon-phone readings missing")
        let loaded = try ReplayReadings.load(url: file)
        XCTAssertFalse(loaded.ticks.isEmpty)
        let base = try sharedEngine.finish(readings: loaded.readings)
        let r = try Refine.apply(to: base, readings: loaded.readings, ticks: loaded.ticks, engine: sharedEngine)
        print("REFINE marathon-phone: base \(base.rows.count) rows, refined \(r.scan.rows.count) rows, \(loaded.ticks.count) ticks, changes: \(r.changes.map { "\($0.kind.rawValue)#\($0.rowIndex) \($0.detail)" })")
        XCTAssertEqual(base.rows.count, 45)
        XCTAssertEqual(r.scan.rows.count, 47)
        // (another Staraptor 1986, HP 140 13/14/13, is a different Pokémon in the same clip)
        let stars = r.scan.rows.filter { $0.display == "Staraptor" && $0.cp == 1986 && $0.hp == 139 }
        XCTAssertEqual(stars.count, 2)
        XCTAssertTrue(stars.allSatisfy { $0.ivs == IVs(atk: 15, def: 13, hp: 11) })
        XCTAssertEqual(stars.map { $0.flags.contains("same-as-previous") }, [false, true])
        let zap = r.scan.rows.filter { $0.display == "Zapdos" && $0.cp == 1977 }
        XCTAssertEqual(zap.count, 1)
        XCTAssertEqual(zap.first?.hp, 129)
        XCTAssertEqual(zap.first?.ivs, IVs(atk: 15, def: 12, hp: 10))
        XCTAssertTrue(zap.first?.flags.contains("cp-computed:1977") ?? false)
        XCTAssertTrue(r.scan.unmatched.isEmpty)
    }
}
