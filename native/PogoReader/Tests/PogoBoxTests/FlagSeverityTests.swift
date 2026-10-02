import Foundation
import XCTest
@testable import PogoBox
import PogoReader

final class FlagSeverityTests: XCTestCase {
    func testTheRulesByFlag() {
        func sev(_ f: String, _ status: String = "exact") -> FlagInfo.Severity { FlagInfo.severity(of: f, solveStatus: status) }
        for f in ["ivs-disagree", "bars-unsettled", "cp-chosen-2641-over-641", "cp-recovered:1966-from-966", "cp-outlier-dropped:12", "absorbed-fragment", "ivs-corrected-from-1/2/3", "hp-computed"] {
            XCTAssertEqual(sev(f), .note, "\(f) on an exact row")
            XCTAssertEqual(sev(f, "ambiguous"), .check, "\(f) on a row that is not exact")
            XCTAssertEqual(sev(f, "none"), .check)
        }
        for f in ["form-ambiguous:a|b", "level-ambiguous:20|20.5"] { XCTAssertEqual(sev(f), .note); XCTAssertEqual(sev(f, "none"), .note) }
        for f in ["no-level-fits", "ivs-unread", "ambiguous-ivs:3-fit", "cp-computed:1994", "hp-unread", "name-low-confidence", "same-as-previous", "split-by-timing", "split-by-bars",
                  "absorbed-unread", "mega-when-scanned", "sex-from-stats", "sex-not-read", "single-read", "some-flag-nobody-has-seen-yet"] {
            XCTAssertEqual(sev(f), .check, f); XCTAssertEqual(sev(f, "exact"), .check, f)
        }
        XCTAssertFalse(FlagInfo.explain("split-by-bars").isEmpty); XCTAssertTrue(FlagInfo.explain("split-by-bars").hasPrefix("Two different Pokémon with the same CP"))
        XCTAssertFalse(FlagInfo.explainNote("cp-chosen-1960-over-60").contains("Check"))
        XCTAssertTrue(FlagInfo.explainNote("cp-chosen-1960-over-60").hasPrefix("The CP was read two different ways."))
    }

    /// The owner's 313-Pokémon scan: 72 rows flagged, and the ones that genuinely need a look.
    func testTheRealScanKeepsOnlyTheRowsThatNeedALook() throws {
        struct F: Decodable { var rows: [ScanRow] }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "run8-tap-300.result", withExtension: "json", subdirectory: "Fixtures"))
        let rows = try JSONDecoder().decode(F.self, from: Data(contentsOf: url)).rows
        XCTAssertEqual(rows.count, 313)
        let flagged = rows.filter { !$0.flags.isEmpty }
        XCTAssertEqual(flagged.count, 72)
        let check = rows.filter(\.needsCheck)
        for r in check { print("TOCHECK \(r.title) CP \(r.cp) HP \(r.hp.map(String.init) ?? "-") \(r.solveStatus) \(r.checkFlags)") }
        print("TOCHECK count \(check.count) of \(flagged.count) flagged")
        XCTAssertEqual(check.count, 9)
        XCTAssertTrue(check.allSatisfy { !$0.checkFlags.isEmpty })
        // every flagged row that is not in the list has only notes
        XCTAssertTrue(flagged.filter { !$0.needsCheck }.allSatisfy { $0.checkFlags.isEmpty && !$0.noteFlags.isEmpty })
        // a stored entry follows the same rule
        let e = BoxEntry(row: flagged.first { !$0.needsCheck }!, firstSeen: Date(), lastSeen: Date())
        XCTAssertFalse(e.needsCheck)
    }
}
