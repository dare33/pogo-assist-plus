import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The hand-set Dynamax flag reaches the advisor through `CoreEngine.advise(rows:)`, which has no CSV column for it.
final class DynamaxAdviceTests: XCTestCase {
    private func chansey(_ dynamax: Bool?) -> ScanRow {
        ScanRow(index: 1, name: "Chansey", display: "Chansey", form: "", speciesId: "chansey", dex: 113, cp: 400, hp: 180, ivs: IVs(atk: 10, def: 11, hp: 12), ivsRead: IVs(atk: 10, def: 11, hp: 12),
                ivsGuess: nil, level: 15, levelMax: 15, dust: 1000, solveStatus: "exact", flags: [], frames: [], dynamax: dynamax)
    }

    private func blissey(_ dynamax: Bool?) throws -> JSONValue? {
        let report = try sharedEngine.advise(rows: [chansey(dynamax)])
        return try XCTUnwrap(report["builds"]?.arrayValue).first { $0["targetId"] == .string("blissey") }
    }

    private func hasStep(_ b: JSONValue) -> Bool { b["steps"]?.arrayValue?.contains { $0["kind"] == .string("needsDynamaxCopy") } == true }
    private func hasMax(_ b: JSONValue) -> Bool { b["areas"]?.arrayValue?.contains(.string("max")) == true }

    func testTheFlagChangesTheAdvice() throws {
        let unset = try XCTUnwrap(blissey(nil))
        XCTAssertTrue(hasStep(unset)); XCTAssertTrue(hasMax(unset))
        let yes = try XCTUnwrap(blissey(true))
        XCTAssertFalse(hasStep(yes)); XCTAssertTrue(hasMax(yes))
        if let no = try blissey(false) { XCTAssertFalse(hasStep(no)); XCTAssertFalse(hasMax(no)) }
    }
}
