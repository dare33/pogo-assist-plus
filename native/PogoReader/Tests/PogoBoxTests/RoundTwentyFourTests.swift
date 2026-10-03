import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Round 24: run17 (a Full scan, count 1729, tap paging at 1.2 s). The owner closed the appraisal on Staraptor CP 1999 HP 141 (IVs 14/14/14) while the command kept tapping: each tap covers
/// part of the CP, so the one card reads 1999, 1299, 1099, 199, 1209, 29, ... or no CP, with its name and HP and no bars, for 75 s. The fixture is run17's log from 14 s to 106 s (the
/// stall, its three pause markers, the real reopen at 100.8 s and the cards after it) and from 176 s on (Charizard 1632 / 120 sliding in with bars still animating).
final class RoundTwentyFourTests: XCTestCase {
    private let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
    private func lines(_ name: String) throws -> [ReplayLine] { ReplayLog.lines(in: try Fixture.url(name)) }
    private func readings(_ ls: [ReplayLine]) -> [ReplayReading] { ls.compactMap { if case .reading(let r) = $0 { return r } else { return nil } } }
    private func write(_ ls: [ReplayLine]) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("r24-\(UUID().uuidString).jsonl")
        try (ls.map { String(decoding: ReplayLog.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n").write(to: u, atomically: true, encoding: .utf8)
        return u
    }
    private func rows(_ ls: [ReplayLine]) throws -> [ScanRow] { try ScanPipeline.process(replay: write(ls), engine: sharedEngine, paging: hint).scan.rows }

    /// Item D (pipeline): the stalled Staraptor is ONE row with its bars, not nine; the real cards after the reopen are still their own rows.
    func testTheClosedAppraisalStallIsOneRowInThePipeline() throws {
        let out = try rows(try lines("run17-closed-stall.replay.jsonl"))
        let stalled = out.filter { $0.display == "Staraptor" && $0.hp == 141 }
        XCTAssertEqual(stalled.filter { $0.cp == 1999 }.count, 1, "\(out.map { "\($0.display) \($0.cp)/\($0.hp ?? 0)" })")
        XCTAssertEqual(stalled.first { $0.cp == 1999 }?.ivs, IVs(atk: 14, def: 14, hp: 14))
        XCTAssertTrue(stalled.allSatisfy { $0.cp == 1999 || $0.cp == 1994 }, "no fragment rows (1099, 129, 1129, ...): \(stalled.map { $0.cp })")
        XCTAssertTrue(out.contains { $0.display == "Staraptor" && $0.cp == 1995 && $0.hp == 142 }, "the real next card keeps its row")
        XCTAssertTrue(out.contains { $0.display == "Staraptor" && $0.cp == 1994 && $0.hp == 142 })
        XCTAssertTrue(out.contains { $0.display == "Staraptor" && $0.cp == 1994 && $0.hp == 141 }, "and the one after it")
    }

    /// Item D (controller, as the extension drives it, with the live normaliser): one pause for the stall, a resume only at the real reopen (100.8 s), and the live count does not move.
    func testTheControllerPausesOnceAndResumesOnlyAtTheRealReopen() throws {
        let ls = try lines("run17-closed-stall.replay.jsonl")
        let rs = readings(ls)
        let t0 = try XCTUnwrap(rs.first).t
        var c = ScanEndController(period: 1.2, storageCount: 1729)!
        var g = LiveGrouper(species: try? SpeciesTable.bundled()), norm = StalledCardNormaliser()
        var events = [(Double, String)](), readAtPause: Int?, readBeforeResume: Int?, grewInStall = false
        for r in rs {
            for l in ls { if case .tick(let t) = l, t > r.t - 0.2, t <= r.t { g.swipe(at: t); c.noteSwipe(at: t) } }
            let countBefore = g.rows.count
            g.add(norm.feed(r.frameReading))
            if r.t - t0 + 14 < 73, g.rows.count != countBefore, readAtPause != nil { grewInStall = true }
            switch c.feed(r.frameReading, time: r.t, read: g.rows.count) {
            case .pause(let p): events.append((r.t - t0, "pause")); if readAtPause == nil { readAtPause = p.read }
            case .resume: events.append((r.t - t0, "resume")); readBeforeResume = countBefore
            case .windowRestarted: events.append((r.t - t0, "restart"))
            case .finish: events.append((r.t - t0, "finish"))
            case .none: break
            }
        }
        // t0 is the fixture's first reading, 14 s into the run: the first pause is at 32.3 - 14, the real reopen at 100.8 - 14 (the marker times differ from the readings' by the drops before it)
        let pauses = events.filter { $0.1 == "pause" }, resumes = events.filter { $0.1 == "resume" }
        XCTAssertEqual(pauses.count, 1, "\(events)"); XCTAssertEqual(resumes.count, 1, "\(events)")
        XCTAssertEqual(resumes.first?.0 ?? 0, 100.8 - 14, accuracy: 1.0, "the resume is the reopen: \(events)")
        XCTAssertFalse(events.contains { $0.1 == "restart" || $0.1 == "finish" }, "\(events)")
        // The live count (the pause marker's `read`, the notification, the Scan screen) does not move while the stalled card is read (32 s to 73 s). After an unreadable stretch and a
        // swipe tick (73.8 s and 97.8 s in the log) the live grouper still starts a run of the same card twice before the reopen: two extra live rows at 97 s, none in the pipeline's result.
        XCTAssertFalse(grewInStall, "the live count grew during the stall")
        XCTAssertNotNil(readAtPause); XCTAssertNotNil(readBeforeResume)
    }

    /// Item C: an Add-and-update scan cannot pause; the same stall ends it at the end wait and the stalled card is still ONE row.
    func testAPartScanStalledThisWayEndsWithOneStalledRow() throws {
        let ls = try lines("run17-closed-stall.replay.jsonl")
        var c = ScanEndController(period: 1.2, storageCount: nil, pausesAllowed: false)!
        var g = LiveGrouper(species: try? SpeciesTable.bundled()), norm = StalledCardNormaliser()
        var kept = [ReplayLine](), end: (Double, Double)?
        for l in ls {
            guard case .reading(let r) = l else { if case .tick = l { kept.append(l) }; continue }
            kept.append(l); g.add(norm.feed(r.frameReading))
            if case .finish(let at, let last) = c.feed(r.frameReading, time: r.t, read: g.rows.count) { end = (at, last); break }
        }
        let e = try XCTUnwrap(end, "the scan ends by itself at the end wait")
        let out = try rows(ReplayLog.trimmed(kept + [.end(at: e.0, last: e.1)]))
        XCTAssertEqual(out.filter { $0.display == "Staraptor" && $0.hp == 141 }.map { $0.cp }, [1999], "one stalled row: \(out.map { "\($0.display) \($0.cp)" })")
    }

    /// Item D (Charizard): the first reading of a card sliding in (CP 632 of 1632, HP 120, bars still animating) is not a Pokémon of its own.
    func testACardSlidingInWithAPartReadCPIsOneRow() throws {
        let out = try rows(try lines("run17-charizard-open-slide.replay.jsonl"))
        let ch = out.filter { $0.display == "Charizard" }
        XCTAssertEqual(ch.map { $0.cp }, [1632], "\(ch.map { "\($0.cp) \($0.flags)" })")
        XCTAssertEqual(ch.first?.ivs, IVs(atk: 13, def: 14, hp: 15)); XCTAssertTrue(ch.first?.flags.contains("absorbed-fragment:632") == true)
    }

    // MARK: the normaliser

    private func reading(_ name: String?, hp: Int?, cp: Int?, ivs: IVs? = nil, t: Double = 0) -> FrameReading {
        var f = FrameReading(); f.name = name; f.hp = hp.map { HP(current: $0, max: $0) }; f.cp = cp; f.ivs = ivs; f.time = t
        return f
    }
    func testTheLiveNormaliserGivesTheStalledCardItsOwnCP() {
        var n = StalledCardNormaliser()
        let own = IVs(atk: 14, def: 14, hp: 14)
        XCTAssertEqual(n.feed(reading("Staraptor", hp: 141, cp: 1999, ivs: own)).cp, 1999)
        for cp in [1299, 1099, 199, 29, nil] as [Int?] { XCTAssertEqual(n.feed(reading("Staraptor", hp: 141, cp: cp)).cp, 1999, "\(String(describing: cp))") }
        XCTAssertEqual(n.feed(reading("Staraptor", hp: 142, cp: 1995)).cp, 1995, "another HP is another card")
        XCTAssertEqual(n.feed(reading("Staraptor", hp: 141, cp: 1099)).cp, 1099, "the anchor is gone")
        XCTAssertEqual(n.feed(reading(nil, hp: nil, cp: nil)).cp, nil)
    }
    func testTheBatchNormaliserNeedsAWholeStretch() {
        func log(_ tail: Int) -> [FrameReading] {
            [reading("Staraptor", hp: 141, cp: 1999, ivs: IVs(atk: 14, def: 14, hp: 14))] + (0..<tail).map { reading("Staraptor", hp: 141, cp: $0 % 2 == 0 ? 1999 : 1099) }
        }
        XCTAssertEqual(StalledCardNormaliser.normalise(log(7)).map { $0.cp }, log(7).map { $0.cp }, "seven barless readings: a new card's first readings, left alone")
        XCTAssertTrue(StalledCardNormaliser.normalise(log(8)).allSatisfy { $0.cp == 1999 })
        var withBars = log(8); withBars[4].ivs = IVs(atk: 1, def: 2, hp: 3); withBars[4].cp = 1098
        XCTAssertEqual(StalledCardNormaliser.normalise(withBars)[4].cp, 1098, "a reading with bars is never rewritten")
    }
}
