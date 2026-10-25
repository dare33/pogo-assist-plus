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
        // A stored No (false) is gone: it is as if not marked.
        let no = try XCTUnwrap(blissey(false))
        XCTAssertTrue(hasStep(no)); XCTAssertTrue(hasMax(no))
    }

    private func charmander(gigantamax: Bool?, dynamax: Bool? = nil, lucky: Bool? = nil, shadow: Int? = nil) -> ScanRow {
        ScanRow(index: 1, name: "Charmander", display: "Charmander", form: "", speciesId: "charmander", dex: 4, cp: 400, hp: 60, ivs: IVs(atk: 15, def: 15, hp: 15), ivsRead: IVs(atk: 15, def: 15, hp: 15),
                ivsGuess: nil, level: 15, levelMax: 15, dust: 1000, solveStatus: "exact", flags: [], frames: [], shadow: shadow, dynamax: dynamax, gigantamax: gigantamax, lucky: lucky)
    }
    private func gmaxHits(_ row: ScanRow) throws -> [JSONValue] {
        let report = try sharedEngine.advise(rows: [row])
        let b = try XCTUnwrap(try XCTUnwrap(report["builds"]?.arrayValue).first { $0["targetId"] == .string("charizard") })
        return (b["hits"]?.arrayValue ?? []).filter { $0["area"] == .string("max") && ($0["name"]?.stringValue ?? "").lowercased().contains("gigantamax") }
    }

    func testAGigantamaxMarkedSpareBesideABetterCopyKeepsTheCredit() throws {
        var plain = charmander(gigantamax: nil); plain.index = 1
        var marked = charmander(gigantamax: true); marked.index = 2; marked.ivs = IVs(atk: 1, def: 1, hp: 1); marked.ivsRead = marked.ivs
        let report = try sharedEngine.advise(rows: [plain, marked])
        let builds = try XCTUnwrap(report["builds"]?.arrayValue).filter { $0["targetId"] == .string("charizard") }
        let mine = try XCTUnwrap(builds.first { $0["pokemon"]?["index"] == .number(2) })
        XCTAssertTrue((mine["hits"]?.arrayValue ?? []).contains { ($0["name"]?.stringValue ?? "").lowercased().contains("gigantamax") })
        XCTAssertEqual(mine["needsDynamax"], .bool(false))
    }

    func testTheMaxFitLineDropsTheDynamaxNeedForAMarkedCopy() throws {
        let f = BoxAdvice.Fit(area: "max", tag: .ok, asName: "Snorlax", tier: "A", reason: nil, species: nil, ivPercent: nil)
        XCTAssertEqual(f.line, "Max A as Snorlax (needs a Dynamax copy)")
        var marked = f; marked.dynamaxMarked = true
        XCTAssertEqual(marked.line, "Max A as Snorlax")
        var other = f; other.dynamaxMarked = true
        let raids = BoxAdvice.Fit(area: "raids", tag: .ok, asName: "X", tier: "A", reason: nil, species: nil, ivPercent: nil)
        XCTAssertFalse(raids.line.contains("Dynamax")); _ = other
    }

    func testCoreEnginePassesGigantamaxToTheAdvisor() throws {
        XCTAssertTrue(try gmaxHits(charmander(gigantamax: nil)).isEmpty)
        XCTAssertTrue(try gmaxHits(charmander(gigantamax: nil, dynamax: true)).isEmpty, "a Dynamax copy is not a Gigantamax one")
        let g = try gmaxHits(charmander(gigantamax: true, dynamax: true))
        XCTAssertFalse(g.isEmpty)
        XCTAssertTrue(g.allSatisfy { $0["needsDynamax"] == .bool(false) })
    }

    func testLuckyAndAHandShadowMarkReachTheAdvisor() throws {
        func dust(_ r: ScanRow) throws -> Double {
            let report = try sharedEngine.advise(rows: [r])
            let b = try XCTUnwrap(try XCTUnwrap(report["builds"]?.arrayValue).first { $0["targetId"] == .string("charizard") })
            return try XCTUnwrap(b["cost"]?["dust"]?.numberValue)
        }
        XCTAssertLessThan(try dust(charmander(gigantamax: nil, lucky: true)), try dust(charmander(gigantamax: nil)))
        func species(_ r: ScanRow) throws -> [String] {
            try XCTUnwrap(sharedEngine.advise(rows: [r])["builds"]?.arrayValue).compactMap { $0["speciesId"]?.stringValue }
        }
        XCTAssertTrue(try species(charmander(gigantamax: nil, shadow: 1)).allSatisfy { $0.hasSuffix("_shadow") })
        XCTAssertTrue(try species(charmander(gigantamax: nil, shadow: 0)).allSatisfy { !$0.hasSuffix("_shadow") })
        XCTAssertTrue(try species(charmander(gigantamax: nil, shadow: 2)).allSatisfy { !$0.hasSuffix("_shadow") })
    }
}

private extension JSONValue {
    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var numberValue: Double? { if case .number(let n) = self { return n } else { return nil } }
}
