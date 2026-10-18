import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class HiddenCpTests: XCTestCase {
    /// The hidden-CP Zapdos of marathon-phone (seven readings, HP 129, bars 15/12/10), shifted to start at `t`.
    private func hiddenZapdos(at t: Double) throws -> [FrameReading] {
        let all = try ReplayReadings.load(url: Fixture.url("hidden/readings.json")).readings
        let own = all.filter { $0.name == "Zapdos" && $0.cp == nil }
        let t0 = own[0].time!
        return own.enumerated().map { i, r in var x = r; x.frame = "h\(Int(t * 10))-\(i)"; x.time = t + (r.time! - t0); return x }
    }

    /// The same Pokemon with its CP showing, for 1.2 s, bars settled or not.
    private func visibleZapdos(from t: Double, bars: Bool) throws -> [FrameReading] {
        try hiddenZapdos(at: t).prefix(6).enumerated().map { i, r in
            var x = r; x.frame = "v\(i)"; x.cp = 1977; x.cpText = "1977"; x.cpReads = [1977]; x.flags = []
            if !bars { x.ivs = nil; x.ivConfidence = 0; x.fills = nil }
            return x
        }
    }

    private func blank(_ t: Double, flags: [String] = ["no-cp-text"]) -> FrameReading {
        var r = FrameReading(frame: "b\(Int(t * 10))", time: t); r.flags = flags; return r
    }

    /// Zapdos 1977 on screen for 1.2 s, a swipe (0.8 s of readings with no card, a tick, one mid-swipe reading), then a Zapdos whose
    /// CP the model covers: two Pokemon. LiveGrouper lists both; so must Refine.
    func testAHiddenEntryAfterASwipeIsKeptAsItsOwnRow() throws {
        for bars in [true, false] {
            let readings = try visibleZapdos(from: 0, bars: bars) + [blank(1.2), blank(1.4, flags: ["mid-swipe"]), blank(1.6), blank(1.8)] + (try hiddenZapdos(at: 2.0))
            let base = try sharedEngine.finish(readings: readings)
            XCTAssertEqual(base.rows.filter { $0.cp == 1977 }.count, 1, "bars \(bars): the JavaScript has the first one")
            XCTAssertEqual(base.unmatched.filter { $0.reason == "cp-not-read" }.count, 1, "bars \(bars): and the hidden one unmatched")
            let r = try Refine.apply(to: base, readings: readings, ticks: [1.5], engine: sharedEngine)
            XCTAssertEqual(r.scan.rows.filter { $0.display == "Zapdos" && $0.cp == 1977 }.count, 2, "bars \(bars): \(r.changes) \(r.notices)")
            XCTAssertFalse(r.scan.rows.contains { $0.flags.contains("absorbed-unread") }, "bars \(bars)")
            XCTAssertFalse(r.changes.contains { $0.kind == .duplicateDropped }, "bars \(bars)")
            XCTAssertTrue(r.scan.unmatched.isEmpty, "bars \(bars)")
        }
    }

    /// Bars unread on the first card never justify a drop, even with no swipe between the two stretches.
    func testUnreadBarsNeverJustifyADrop() throws {
        let readings = try visibleZapdos(from: 0, bars: false) + [blank(1.2)] + (try hiddenZapdos(at: 1.4))
        let base = try sharedEngine.finish(readings: readings)
        guard !base.unmatched.isEmpty else { return }   // the JavaScript already treated it as one Pokemon: nothing to decide
        let r = try Refine.apply(to: base, readings: readings, ticks: [], engine: sharedEngine)
        XCTAssertFalse(r.changes.contains { $0.kind == .duplicateDropped })
        XCTAssertFalse(r.scan.rows.contains { $0.flags.contains("absorbed-unread") })
    }

    /// Two hidden-CP entries of one species in a row: each is solved from its own readings, not run together.
    func testAHiddenStretchStopsAtItsOwnFrames() throws {
        let all = try ReplayReadings.load(url: Fixture.url("hidden/readings.json")).readings
        // Zapdos 1968 (HP 131, bars 12/12/13) with the CP hidden, after the first one and 0.6 s of nothing
        let second = all.filter { $0.name == "Zapdos" && $0.hp?.max == 131 }.enumerated().map { i, r -> FrameReading in
            var x = r; x.frame = "s\(i)"; x.time = 3.4 + Double(i) * 0.2; x.cp = nil; x.cpText = ""; x.cpReads = nil; x.flags = ["no-cp-text"]; return x
        }
        XCTAssertGreaterThan(second.count, 1)
        let readings = try hiddenZapdos(at: 0) + [blank(1.4), blank(1.6), blank(1.8), blank(2.0)] + second
        let base = try sharedEngine.finish(readings: readings)
        let entries = base.unmatched.filter { $0.reason == "cp-not-read" }
        XCTAssertEqual(entries.count, 2, "\(base.unmatched)")
        let r = try Refine.apply(to: base, readings: readings, ticks: [1.7], engine: sharedEngine)
        XCTAssertEqual(r.scan.rows.map { "\($0.display) \($0.cp) \($0.hp ?? 0)" }.sorted(), ["Zapdos 1968 131", "Zapdos 1977 129"])
        XCTAssertTrue(r.scan.unmatched.isEmpty, "\(r.scan.unmatched) \(r.notices)")
    }

    /// Readings with no frame labels (what `ReplayLog.frameReading` gives) are handled as well as labelled ones.
    func testUnlabelledReadingsRefineLikeLabelledOnes() throws {
        let u = try Fixture.url("device-run-2026-10-02.replay.jsonl")
        var readings = [FrameReading](), ticks = [Double]()
        for line in ReplayLog.lines(in: u) {
            switch line {
            case .reading(let r): readings.append(r.frameReading)
            case .tick(let t): ticks.append(t)
            case .drop, .end, .pause, .resume, .stoppedByPerson, .pauseTimedOut: break
            }
        }
        XCTAssertTrue(readings.allSatisfy { $0.frame == nil })
        let base = try sharedEngine.finish(readings: readings)
        let r = try Refine.apply(to: base, readings: readings, ticks: ticks, engine: sharedEngine)
        XCTAssertEqual(r.scan.rows.map { "\($0.display) \($0.cp)" }, DeviceRunTests.phone)
    }
}
