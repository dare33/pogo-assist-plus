import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class ScanPaceTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
    }

    /// The owner's run3 log: a command meant to be fast that ran at normal pace.
    func testTheRealRunMeasuresAboutTwoPointTwoSeconds() throws {
        let m = try XCTUnwrap(ScanPace.measure(replay: try fixture("run3-fast-swipe-extract.replay")))
        XCTAssertEqual(m.basis, .swipeTicks)
        XCTAssertEqual(m.secondsPerPokemon, 2.2, accuracy: 0.15)
        XCTAssertGreaterThanOrEqual(m.samples, 10)
    }

    func testTheSampleScanMeasuresFromItsTicksToo() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PogoAssist/PogoAssist/Resources/sample-scan.replay.jsonl")
        let m = try XCTUnwrap(ScanPace.measure(replay: url))
        XCTAssertTrue((1.5...2.6).contains(m.secondsPerPokemon), "\(m)")
    }

    func testWithoutTicksItUsesWhereThePokemonChanged() {
        func reading(_ t: Double, _ cp: Int?) -> ReplayLine {
            var f = FrameReading(frame: nil, time: t); f.cp = cp; f.name = cp == nil ? nil : "Pidgey"
            return .reading(ReplayReading(f, time: t, ms: 1))
        }
        // a new Pokémon every 1.2 s, each held for three frames 0.4 s apart; a one-frame misread between them does not count
        var lines = [ReplayLine]()
        for k in 0..<12 {
            let t0 = Double(k) * 1.2
            for j in 0..<3 { lines.append(reading(t0 + Double(j) * 0.4, 100 + k)) }
        }
        lines.insert(reading(3.0, 999), at: 8)
        let m = ScanPace.measure(lines)
        XCTAssertEqual(m?.basis, .readingGaps)
        XCTAssertEqual(m?.secondsPerPokemon ?? 0, 1.2, accuracy: 0.05)
    }

    func testTooLittleToMeasureIsNil() {
        XCTAssertNil(ScanPace.measure([]))
        XCTAssertNil(ScanPace.measure([.tick(1), .tick(3), .tick(5)]))
    }

    func testAMissedTickDoesNotMoveTheMedian() {
        var lines = [ReplayLine]()
        for k in 0..<12 where k != 6 { lines.append(.tick(Double(k) * 2.1)) }   // one tick missing: one 4.2 s gap
        let m = ScanPace.measure(lines)
        XCTAssertEqual(m?.secondsPerPokemon ?? 0, 2.1, accuracy: 0.001)
    }
}
