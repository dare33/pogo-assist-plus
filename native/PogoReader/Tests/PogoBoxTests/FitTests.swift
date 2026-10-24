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
        // The build marker: carried with its target and cost, on strong, ok and weak copies alike (it is not the tag).
        let builds = all.filter { $0.build }
        XCTAssertFalse(builds.isEmpty, "some fit carries a build")
        for f in builds { XCTAssertNotNil(f.buildAs); XCTAssertNotNil(f.buildCost) }
        for f in all where !f.build { XCTAssertNil(f.buildAs); XCTAssertNil(f.buildCost) }
        XCTAssertTrue(builds.contains { $0.tag == .strong } && builds.contains { $0.tag == .ok } && builds.contains { $0.tag == .weak && $0.reason == .iv })
        // A weak "none" line names the species from the engine, not from the row (these rows are named "?").
        let none = all.filter { $0.reason == BoxAdvice.Fit.Reason.none }
        XCTAssertFalse(none.isEmpty)
        for f in none { XCTAssertNotNil(f.species); XCTAssertFalse(f.line.contains("?"), f.line) }
        for f in all where f.tag != .weak { XCTAssertTrue(f.line.contains(" as \(f.asName ?? "?")"), f.line) }
    }

    private func fit(_ tag: BoxAdvice.Fit.Tag, area: String = "raids", asName: String? = nil, tier: String? = nil, reason: BoxAdvice.Fit.Reason? = nil, ivPercent: Double? = nil) -> BoxAdvice.Fit {
        .init(area: area, tag: tag, asName: asName, tier: tier, reason: reason, species: reason == BoxAdvice.Fit.Reason.none ? "Charmander" : nil, ivPercent: ivPercent)
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
        let weak = try XCTUnwrap(BoxAdvice.Fit.decode(area: "gym", try JSONDecoder().decode(JSONValue.self, from: Data(#"["w",null,null,"iv"]"#.utf8)), ivPercent: 51.1))
        XCTAssertEqual(weak.tag, .weak); XCTAssertEqual(weak.reason, .iv); XCTAssertNil(weak.asName)
        XCTAssertEqual(weak.line, "IVs 51.1%, below 80%")
        let ok = try XCTUnwrap(BoxAdvice.Fit.decode(area: "raids", try JSONDecoder().decode(JSONValue.self, from: Data(#"["o","Mega Delphox","S"]"#.utf8)), ivPercent: 90))
        XCTAssertEqual(ok.line, "Raids S as Mega Delphox")
        XCTAssertFalse(ok.build); XCTAssertNil(ok.buildAs); XCTAssertNil(ok.buildCost)
        // The engine's own one-decimal figure (index 4) wins over the app's recomputation from the IVs.
        let engine = try XCTUnwrap(BoxAdvice.Fit.decode(area: "gym", try JSONDecoder().decode(JSONValue.self, from: Data(#"["w",null,null,"iv",79.9]"#.utf8)), ivPercent: 80.0))
        XCTAssertEqual(engine.line, "IVs 79.9%, below 80%")
        // An unrecognised reason code is not "no table entry".
        let odd = try XCTUnwrap(BoxAdvice.Fit.decode(area: "rocket", try JSONDecoder().decode(JSONValue.self, from: Data(#"["w",null,null,"somethingNew"]"#.utf8)), ivPercent: nil))
        XCTAssertEqual(odd.line, "Weak for Rocket")
        XCTAssertNil(BoxAdvice.Fit.decode(area: "raids", try JSONDecoder().decode(JSONValue.self, from: Data(#"["x"]"#.utf8)), ivPercent: nil), "an unknown tag is skipped")
        func decode(_ json: String) throws -> BoxAdvice.Fit? { BoxAdvice.Fit.decode(area: "raids", try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)), ivPercent: 90) }
        // A Strong or OK array without its build species and tier strings is skipped, not read as Strong.
        XCTAssertNil(try decode(#"["s"]"#)); XCTAssertNil(try decode(#"["s","Mega Delphox"]"#)); XCTAssertNil(try decode(#"["o",null,"S"]"#)); XCTAssertNil(try decode(#"["s",5,6]"#))
        XCTAssertNotNil(try decode(#"["s","Mega Delphox","S"]"#))
        // The build tail goes through the range-checked whole-number reading: a fraction, a huge or a non-finite figure drops the tail, never traps.
        XCTAssertEqual(try decode(#"["s","Mega Delphox","S",true,"Mega Delphox",1000,50,0]"#)?.buildCost, .init(dust: 1000, candy: 50, xl: 0))
        for bad in ["1.5", "1e300", "-1e300", "9e15"] {
            let f = try XCTUnwrap(try decode(#"["s","Mega Delphox","S",true,"Mega Delphox",\#(bad),50,0]"#), bad)
            XCTAssertFalse(f.build, bad); XCTAssertNil(f.buildCost, bad)
        }
    }

    /// The build tail: from index 3 for strong / ok, from 5 for weak (index 4 then holds the extra, or null).
    func testTheBuildMarkerDecodesFromItsTail() throws {
        func decode(_ json: String, _ area: String = "rocket", _ pct: Double? = nil) throws -> BoxAdvice.Fit {
            try XCTUnwrap(BoxAdvice.Fit.decode(area: area, try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)), ivPercent: pct))
        }
        let ok = try decode(#"["o","Charizard","A",true,"Charizard",150000,200,40]"#)
        XCTAssertEqual(ok.tag, .ok); XCTAssertTrue(ok.build); XCTAssertEqual(ok.buildAs, "Charizard")
        XCTAssertEqual(ok.buildCost, BoxAdvice.Fit.BuildCost(dust: 150000, candy: 200, xl: 40))
        XCTAssertEqual(ok.line, "Rocket A as Charizard", "the marker does not change the line")
        let weakIV = try decode(#"["w",null,null,"iv",66.7,true,"Blissey",0,50,0]"#, "gym")
        XCTAssertEqual([weakIV.tag == .weak, weakIV.build, weakIV.buildAs == "Blissey", weakIV.ivPercent == 66.7], [true, true, true, true])
        XCTAssertEqual(weakIV.buildCost, BoxAdvice.Fit.BuildCost(dust: 0, candy: 50, xl: 0))
        XCTAssertEqual(weakIV.line, "IVs 66.7%, below 80%")
        // A weak reason with no extra still carries a build: index 4 is null, the tail starts at 5.
        let weakNoExtra = try decode(#"["w",null,null,"ivUnknown",null,true,"Mewtwo",1,2,3]"#, "raids")
        XCTAssertTrue(weakNoExtra.build); XCTAssertEqual(weakNoExtra.buildCost?.xl, 3); XCTAssertEqual(weakNoExtra.line, "IVs not known")
        // A weak "none" takes the engine's name from index 4, and a build after it.
        let none = try decode(#"["w",null,null,"none","Meowth (Galarian)",true,"Perrserker",10,20,30]"#, "gym")
        XCTAssertEqual(none.species, "Meowth (Galarian)"); XCTAssertEqual(none.buildAs, "Perrserker")
        XCTAssertEqual(none.line, "No table entry for Meowth (Galarian) in Gym")
        // A tail that is not whole is no build.
        XCTAssertFalse(try decode(#"["o","Charizard","A",true,"Charizard",150000]"#).build)
        XCTAssertFalse(try decode(#"["o","Charizard","A",false,"Charizard",1,2,3]"#).build)
    }

    /// End to end on three Charmander: the hundo carries the build (and is OK on worth: Rocket Charizard is A tier), the 66.7% copy reads from its own row,
    /// a copy with no gym entry says so with the engine's species name.
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
        let top = try XCTUnwrap(advice.fit(for: "c0")["rocket"])
        XCTAssertEqual(top.tag, .ok); XCTAssertTrue(top.build); XCTAssertEqual(top.buildAs, "Charizard"); XCTAssertNotNil(top.buildCost)
        XCTAssertEqual(top.line, "Rocket A as Charizard")
        XCTAssertFalse(try XCTUnwrap(advice.fit(for: "c1")["rocket"]).build)
        XCTAssertEqual(advice.fit(for: "c1")["rocket"]?.line, "IVs 66.7%, below 80%")
        XCTAssertEqual(advice.fit(for: "c2")["rocket"]?.line, "Rocket A as Charizard")
        XCTAssertEqual(advice.fit(for: "c2")["rocket"]?.build, false)
        XCTAssertEqual(advice.fit(for: "c2")["gym"]?.line, "No table entry for Charmander in Gym")
    }

    /// The engine's name for a species arrives as it is, whatever the row says ("Galarian" is Poke Genie's spelling of the form, and the row could
    /// be named differently still): no form is composed in Swift.
    func testNoTableEntryUsesTheEnginesNameNotTheRows() throws {
        let json = #"{"pokemon":[{"p":{"index":1},"fit":{"raids":["w",null,null,"none","Meowth (Galarian)"]}},{"p":{"index":2},"fit":{"raids":["w",null,null,"none","Meowth"]}}]}"#
        let report = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        func entry(_ i: Int, _ form: String) -> BoxEntry {
            let row = ScanRow(index: i, name: "Meowth", display: "Meowth", form: form, speciesId: "", dex: nil, cp: 0, hp: nil, ivs: nil, ivsRead: nil, ivsGuess: nil,
                              level: nil, levelMax: nil, dust: nil, solveStatus: "exact", flags: [], frames: [])
            return BoxEntry(id: "m\(i)", row: row, firstSeen: date, lastSeen: date)
        }
        let advice = BoxAdvice.make(from: report, entries: [entry(1, "Galar"), entry(2, "Galar")])
        XCTAssertEqual(advice.fit(for: "m1")["raids"]?.line, "No table entry for Meowth (Galarian) in Raids")
        XCTAssertEqual(advice.fit(for: "m2")["raids"]?.line, "No table entry for Meowth in Raids", "the row's form does not enter")
    }
}
