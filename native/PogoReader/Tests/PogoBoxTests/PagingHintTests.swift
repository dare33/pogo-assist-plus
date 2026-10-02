import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class PagingHintTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL { try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")) }
    private func hint(_ p: VoiceCommandFile.Pace) -> PagingHint { PagingHint(pagedByCommand: true, expectedPeriod: p.every, joinExtraSeconds: VoiceCommandFile.joinExtraSeconds) }

    /// The owner's run5 (a Tap command at 1.2 s): with the app's hint it refines to 51 rows, including the Staraptor CP 1986, HP 139 pair.
    func testTheTapRunWithTheCommandHintGivesTheTwinStaraptors() throws {
        let engine = CoreEngine()
        let out = try ScanPipeline.process(replay: try fixture("run5-tap-1.2.replay"), engine: engine, paging: hint(.tapNormal))
        XCTAssertEqual(out.scan.rows.count, 51)
        let twins = out.scan.rows.filter { $0.speciesId == "staraptor" && $0.cp == 1986 && $0.hp == 139 }
        XCTAssertEqual(twins.count, 2, "the pair is split")
        XCTAssertTrue(twins.contains { $0.flags.contains("split-by-timing") }, "and marked as judged from the beat")
        // "by hand": no timing split, so the pair stays one row
        let byHand = try ScanPipeline.process(replay: try fixture("run5-tap-1.2.replay"), engine: engine, paging: PagingHint(pagedByCommand: false))
        XCTAssertLessThan(byHand.scan.rows.count, 51)
        XCTAssertFalse(byHand.scan.rows.contains { $0.flags.contains("split-by-timing") })
        // the pace of the run is the Scan mode's
        XCTAssertEqual(out.pace?.medianPeriod ?? 0, 1.2, accuracy: 0.2)
        XCTAssertNil(PaceCheck.check(measured: out.pace?.medianPeriod ?? 1.2, chosen: .tapNormal))
        XCTAssertTrue(FlagInfo.explain("split-by-timing").hasPrefix("Looked like two identical Pokémon in a row, judged from the paging beat."))
    }

    /// The run3 extract (a command meant to be fast that ran at the 2.1 s pace) measures about 2.2 s from its rows.
    func testTheRun3ExtractMeasuresAboutTwoPointTwoSeconds() throws {
        let out = try ScanPipeline.process(replay: try fixture("run3-fast-swipe-extract.replay"), engine: CoreEngine())
        let pace = try XCTUnwrap(out.pace)
        XCTAssertEqual(pace.medianPeriod, 2.2, accuracy: 0.3)
        XCTAssertNotNil(PaceCheck.check(measured: pace.medianPeriod, chosen: .tapNormal))
    }
}
