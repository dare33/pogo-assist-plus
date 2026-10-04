import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// Round 25: a twin read during a pause keeps its readings, the batch normaliser needs the anchor's CP to show in the stretch, a folded-in sliding-in first reading is a check.
final class RoundTwentyFiveTests: XCTestCase {
    private let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.2, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
    private func readings(_ ls: [ReplayLine]) -> [ReplayReading] { ls.compactMap { if case .reading(let r) = $0 { return r } else { return nil } }.sorted { $0.t < $1.t } }

    /// run10 to its pause (driven as the extension does), then a same-name, same-HP twin with CP 4250 on screen until the finish. Returns the readings kept after the trim, the twin's
    /// readings, and the pipeline's rows for the log.
    private func twin(_ bars: (IVs?) -> IVs?) throws -> (kept: Int, shown: Int, rows: [ScanRow], baseRows: Int, timedOut: Bool) {
        let rs = readings(ReplayLog.lines(in: try Fixture.url("device-run10-tap-25-autoend.replay.jsonl")))
        var c = ScanEndController(period: 1.2, storageCount: 1729)!
        var g = LiveGrouper(species: try? SpeciesTable.bundled()); var n = StalledCardNormaliser()
        var lines = [ReplayLine](), pause: ScanEndController.Pause?, at = 0.0, own: IVs?
        for r in rs {
            lines.append(.reading(r)); g.add(n.feed(r.frameReading))
            if r.ivs != nil { own = r.frameReading.ivs }
            if case .pause(let p) = c.feed(r.frameReading, time: r.t, read: g.rows.count) { pause = p; at = r.t; break }
        }
        _ = try XCTUnwrap(pause)
        lines.append(.pause(at: pause!.at, last: pause!.last, read: pause!.read, closed: pause!.closed))
        var tw = rs.last { $0.t <= at && $0.frameReading.name != nil && $0.frameReading.hp != nil }!.frameReading
        tw.cp = 4250; tw.ivs = bars(own); tw.ivConfidence = 0.9
        var t = at, finish: (Double, Double)?, shown = 0
        while t < at + 700, finish == nil {
            t += 0.4; shown += 1
            lines.append(.reading(ReplayReading(tw, time: t, ms: 1))); g.add(n.feed(tw))
            switch c.feed(tw, time: t, read: g.rows.count) { case .finish(let a, let l): finish = (a, l); case .resume: XCTFail("the same name and HP never resumes"); default: break }
        }
        let f = try XCTUnwrap(finish)
        lines += [.pauseTimedOut(at: f.0), .end(at: f.0, last: f.1)]
        let kept = readings(ReplayLog.trimmed(lines)).filter { $0.t > at }.count
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("r25-\(UUID().uuidString).jsonl")
        try (lines.map { String(decoding: ReplayLog.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        let out = try ScanPipeline.process(replay: url, engine: sharedEngine, paging: hint)
        let base = try ScanPipeline.process(replay: Fixture.url("device-run10-tap-25-autoend.replay.jsonl"), engine: sharedEngine, paging: hint)
        return (kept, shown, out.scan.rows, base.scan.rows.count, c.timedOut)
    }

    func testATwinWithAnotherCPKeepsItsReadingsAtATimeout() throws {
        func note(_ label: String, _ r: (kept: Int, shown: Int, rows: [ScanRow], baseRows: Int, timedOut: Bool)) {
            print("TWIN \(label): kept \(r.kept) of \(r.shown); rows \(r.rows.count) (run10 alone \(r.baseRows)); last rows \(r.rows.suffix(2).map { "\($0.display) \($0.cp) frames \($0.frames.count) \($0.flags)" })")
        }
        let variants: [(String, (IVs?) -> IVs?)] = [("no bars", { _ in nil }), ("the card's own bars", { $0 }), ("bars one notch off", { o in o.map { IVs(atk: max(0, $0.atk - 1), def: $0.def, hp: $0.hp) } })]
        for (label, bars) in variants {
            let r = try twin(bars)
            note(label, r)
            XCTAssertTrue(r.timedOut, label)
            XCTAssertEqual(r.kept, r.shown, "\(label): every reading of the twin survives the trim")
        }
    }

    /// run17's real stall keeps showing the card's own CP between its misreads (72 of 129 readings), so it is NOT a twin: nothing is kept, the end is dated at the stall.
    func testARealStalledCardIsNotTreatedAsATwin() throws {
        let ls = ReplayLog.lines(in: try Fixture.url("run17-closed-stall.replay.jsonl"))
        let rs = readings(ls)
        var c = ScanEndController(period: 1.2, storageCount: 1729)!
        var g = LiveGrouper(species: try? SpeciesTable.bundled()); var n = StalledCardNormaliser()
        var pause: ScanEndController.Pause?, lastT = 0.0
        for r in rs where r.t - rs[0].t < 60 {
            g.add(n.feed(r.frameReading)); lastT = r.t
            let e = c.feed(r.frameReading, time: r.t, read: g.rows.count)
            if case .pause(let p) = e { pause = p }
        }
        let p = try XCTUnwrap(pause)
        guard case .finish(_, let last) = c.finishNow(at: lastT) else { return XCTFail("no finish") }
        XCTAssertEqual(last, p.last, accuracy: 0.001, "no evidence of another card: dated at the stall, the repeated card is trimmed")
    }

    // MARK: the batch normaliser

    private func card(_ cp: Int?, bars: Bool = false) -> FrameReading {
        var f = FrameReading(); f.name = "Staraptor"; f.hp = HP(current: 141, max: 141); f.cp = cp; if bars { f.ivs = IVs(atk: 14, def: 14, hp: 14) }
        return f
    }
    // The stretch rule is the most-read CP, the anchor winning a tie (round 24's; round 25's "the anchor must show again" rule was reverted). Both variants below are run17's stall
    // with the readings changed the way the reviewer did.
    private func run17(_ edit: (inout [ReplayReading]) -> Void) throws -> [ScanRow] {
        var ls = ReplayLog.lines(in: try Fixture.url("run17-closed-stall.replay.jsonl"))
        var rs = ls.compactMap { l -> ReplayReading? in if case .reading(let r) = l { return r } else { return nil } }
        edit(&rs)
        var k = 0
        ls = ls.map { l in if case .reading = l { defer { k += 1 }; return .reading(rs[k]) } else { return l } }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("r26-\(UUID().uuidString).jsonl")
        try (ls.map { String(decoding: ReplayLog.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return try ScanPipeline.process(replay: url, engine: sharedEngine, paging: hint).scan.rows
    }

    /// Variant A: the tap always covers part of the stalled card's number, so its own CP 1999 is never readable in the barless readings: one row, not seven phantom ones.
    func testAStalledCardWhoseOwnCPIsNeverReadableIsStillOneRow() throws {
        let rows = try run17 { rs in for i in rs.indices where rs[i].ivs == nil && rs[i].name == "Staraptor" && rs[i].cp == 1999 { rs[i].cp = nil } }
        let st = rows.filter { $0.display == "Staraptor" && $0.hp == 141 && $0.cp != 1994 }
        XCTAssertEqual(st.map { $0.cp }, [1999], "\(rows.map { "\($0.display) \($0.cp)/\($0.hp ?? 0)" })")
    }

    /// Variant B: the anchor's own CP was misread (1099): the most-read value corrects it, with the bars.
    func testAMisreadAnchorIsCorrectedByTheMostReadCP() throws {
        let rows = try run17 { rs in if let i = rs.firstIndex(where: { $0.ivs != nil && $0.name == "Staraptor" && $0.cp == 1999 }) { rs[i].cp = 1099 } }
        let st = rows.filter { $0.display == "Staraptor" && $0.hp == 141 && $0.cp != 1994 }
        XCTAssertEqual(st.map { $0.cp }, [1999]); XCTAssertEqual(st.first?.ivs, IVs(atk: 14, def: 14, hp: 14))
    }

    /// ACCEPTED LIMIT (named as one): a real next card of the same name and HP, read once and then seven readings with no CP and no bars, is taken for the stalled card and gets its CP.
    func testALimitANextCardReadOnceThenUnreadableTakesTheStalledCardsCP() {
        let next = [card(1999, bars: true), card(1995)] + Array(repeating: card(nil), count: 7)
        XCTAssertTrue(StalledCardNormaliser.normalise(next).dropFirst().allSatisfy { $0.cp == 1999 })
    }
}
