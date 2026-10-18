import XCTest
@testable import PogoBox
import PogoReader

/// The swipe set joins its short gestures every 10 swipes, each join adding about 0.8 s. A log of a swipe scan with a 0.8 s pause added every 10
/// periods must give the same rows as the log itself, told the same hint (the join is in the hint, not mistaken for a repeated Pokémon).
final class SwipeSetJoinTests: XCTestCase {
    private func refine(_ l: ReplayReadings.Loaded) throws -> Refine.Refined {
        let base = try sharedEngine.finish(readings: l.readings)
        let hint = PagingHint(pagedByCommand: true, expectedPeriod: 1.6, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds)
        return try Refine.apply(to: base, readings: l.readings, ticks: l.ticks, engine: sharedEngine, paging: hint)
    }

    func testAJoinEveryTenSwipesDoesNotMakeFalseTwinsOrLoseRows() throws {
        let loaded = try ReplayReadings.load(url: Fixture.url("device-run4-fast-swipe-2026-10-02.replay.jsonl"))
        let t0 = loaded.readings.compactMap { $0.time }.min() ?? 0
        let spacing = Double(VoiceCommandFile.swipeSetBatch) * 1.6
        func shifted(_ t: Double) -> Double { t + VoiceCommandFile.joinExtraSeconds * (floor((t - t0) / spacing)) }
        var joined = loaded
        joined.readings = loaded.readings.map { var r = $0; r.time = r.time.map(shifted); return r }
        joined.ticks = loaded.ticks.map(shifted)
        let plain = try refine(loaded), withJoins = try refine(joined)
        XCTAssertEqual(plain.scan.rows.count, 51)
        XCTAssertEqual(withJoins.scan.rows.map { "\($0.display) \($0.cp)" }, plain.scan.rows.map { "\($0.display) \($0.cp)" })
        XCTAssertEqual(withJoins.changes.filter { $0.kind == .timingSplit }.count, plain.changes.filter { $0.kind == .timingSplit }.count)
    }
}
