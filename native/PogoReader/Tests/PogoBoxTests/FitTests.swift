import Foundation
import XCTest
@testable import PogoBox
import PogoReader

/// The per-copy activity fit as the app receives it: the compact form the bridge carries, decoded from the REAL engine output,
/// and the sentences the app composes from it (the engine's own wording, which the bridge no longer sends).
final class FitTests: XCTestCase {
    private var date: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))! }

    /// The repository's real export (311 Pokémon, `fixtures/` at the repo root; the package's own fixture is four rows and has no OK copy).
    func testTheExportFixtureCarriesStrongAndOkFitsAndBestOf() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let csv = try String(contentsOf: root.appendingPathComponent("fixtures/greg-2026-09-25.pokegenie.csv"), encoding: .utf8)
        let box = try sharedEngine.importPokeGenie(csv: csv)
        let report = try CoreEngine().advise(box: box)
        let es = (try XCTUnwrap(box.arrayValue)).enumerated().map { i, rec -> BoxEntry in
            var name = "?"; if case .string(let n)? = rec["name"] { name = n }
            let row = ScanRow(index: i + 1, name: name, display: name, form: "", speciesId: "", dex: nil, cp: 0, hp: nil, ivs: nil, ivsRead: nil, ivsGuess: nil,
                              level: nil, levelMax: nil, dust: nil, solveStatus: "exact", flags: [], frames: [])
            return BoxEntry(id: "e\(i)", row: row, firstSeen: date, lastSeen: date)
        }
        XCTAssertEqual(es.count, 311)
        let advice = BoxAdvice.make(from: report, entries: es)
        let all = es.flatMap { Array(advice.fit(for: $0.id).values) }
        XCTAssertTrue(all.contains { $0.tag == .strong && $0.asName != nil && $0.tier != nil }, "a strong fit")
        XCTAssertTrue(all.contains { $0.tag == .ok && $0.asName != nil && $0.tier != nil }, "an ok fit")
        XCTAssertTrue(all.contains { $0.tag == .weak && $0.asName == nil && $0.reason != nil }, "a weak fit with its reason")
        XCTAssertEqual(es.filter { !advice.fit(for: $0.id).isEmpty }.count, 311, "every entry carries its fit")
        XCTAssertTrue(es.contains { !advice.bestOf(for: $0.id).isEmpty }, "bestOf reaches the app")
        for f in all where f.tag != .weak { XCTAssertTrue(f.line.contains(" as \(f.asName ?? "?")"), f.line) }
    }

    private func fit(_ tag: BoxAdvice.Fit.Tag, area: String = "raids", asName: String? = nil, tier: String? = nil, reason: BoxAdvice.Fit.Reason? = nil, ivPercent: Double? = nil) -> BoxAdvice.Fit {
        .init(area: area, tag: tag, asName: asName, tier: tier, reason: reason, species: "Charmander", ivPercent: ivPercent)
    }

    func testStrongAndOkLinesNameAreaTierAndEntry() {
        XCTAssertEqual(fit(.strong, asName: "Mega Delphox", tier: "S").line, "Raids S as Mega Delphox")
        XCTAssertEqual(fit(.ok, area: "rocket", asName: "Charizard", tier: "A").line, "Rocket A as Charizard")
        XCTAssertEqual(fit(.ok, area: "max", asName: "Blissey", tier: "S").line, "Max S as Blissey (needs a Dynamax copy)")
        XCTAssertEqual(fit(.strong, area: "max", asName: "Chansey", tier: "B").line, "Max B as Chansey (needs a Dynamax copy)")
    }

    func testEachWeakReasonIsWordedAsTheEngineWordsIt() {
        XCTAssertEqual(fit(.weak, area: "gym", reason: BoxAdvice.Fit.Reason.none).line, "No table entry for Charmander in Gym")
        XCTAssertEqual(fit(.weak, reason: .iv, ivPercent: 200.0 / 3).line, "IVs 66.7%, below 80%")
        XCTAssertEqual(fit(.weak, reason: .iv, ivPercent: 79.9).line, "IVs 79.9%, below 80%")
        XCTAssertEqual(fit(.weak, reason: .iv, ivPercent: 60).line, "IVs 60%, below 80%")
        XCTAssertEqual(fit(.weak, reason: .ivUnknown).line, "IVs not known")
        XCTAssertEqual(fit(.weak, reason: .shadowNoMega).line, "A Shadow copy cannot Mega evolve")
    }

    func testTheCompactFormDecodes() throws {
        let weak = try XCTUnwrap(BoxAdvice.Fit.decode(area: "gym", try JSONDecoder().decode(JSONValue.self, from: Data(#"["w",null,null,"iv"]"#.utf8)), species: "Eevee", ivPercent: 51.1))
        XCTAssertEqual(weak.tag, .weak); XCTAssertEqual(weak.reason, .iv); XCTAssertNil(weak.asName)
        XCTAssertEqual(weak.line, "IVs 51.1%, below 80%")
        let ok = try XCTUnwrap(BoxAdvice.Fit.decode(area: "raids", try JSONDecoder().decode(JSONValue.self, from: Data(#"["o","Mega Delphox","S"]"#.utf8)), species: "Fennekin", ivPercent: 90))
        XCTAssertEqual(ok.line, "Raids S as Mega Delphox")
        XCTAssertNil(BoxAdvice.Fit.decode(area: "raids", try JSONDecoder().decode(JSONValue.self, from: Data(#"["x"]"#.utf8)), species: "", ivPercent: nil), "an unknown tag is skipped")
    }

    /// End to end on three Charmander: the hundo carries the build, the 66.7% copy reads from its own row, a copy with no gym entry says so.
    func testLinesComposedFromARealEngineReport() throws {
        func record(_ index: Int, _ ivs: (Int, Int, Int)) -> JSONValue {
            let json = """
            {"index":\(index),"name":"Charmander","form":"","gender":"","cp":300,"level":20,"levelMin":20,"levelMax":20,"shadow":false,"purified":false,"lucky":false,
             "ivs":{"atk":\(ivs.0),"def":\(ivs.1),"hp":\(ivs.2)},"ivPercent":\(Double(ivs.0 + ivs.1 + ivs.2) / 45 * 100),"moves":[]}
            """
            return try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        }
        let report = try CoreEngine().advise(box: .array([record(1, (15, 15, 15)), record(2, (10, 10, 10)), record(3, (13, 13, 13))]))
        let ivs = [IVs(atk: 15, def: 15, hp: 15), IVs(atk: 10, def: 10, hp: 10), IVs(atk: 13, def: 13, hp: 13)]
        let es = (0..<3).map { i in
            let row = ScanRow(index: i + 1, name: "Charmander", display: "Charmander", form: "", speciesId: "charmander", dex: 4, cp: 300, hp: nil, ivs: ivs[i], ivsRead: nil,
                              ivsGuess: nil, level: 20, levelMax: 20, dust: nil, solveStatus: "exact", flags: [], frames: [])
            return BoxEntry(id: "c\(i)", row: row, firstSeen: date, lastSeen: date)
        }
        let advice = BoxAdvice.make(from: report, entries: es)
        XCTAssertEqual(advice.fit(for: "c0")["rocket"]?.tag, .strong)
        XCTAssertEqual(advice.fit(for: "c1")["rocket"]?.line, "IVs 66.7%, below 80%")
        XCTAssertEqual(advice.fit(for: "c2")["rocket"]?.line, "Rocket A as Charizard")
        XCTAssertEqual(advice.fit(for: "c2")["gym"]?.line, "No table entry for Charmander in Gym")
    }
}
