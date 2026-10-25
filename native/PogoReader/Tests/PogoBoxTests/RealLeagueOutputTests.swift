import XCTest
@testable import PogoBox

/// Decodes what the bundled JavaScript really returns for league ratings (not a hand-written fixture), so a change in the engine's
/// output shape fails here and not on a phone.
final class RealLeagueOutputTests: XCTestCase {
    private func record(index: Int, name: String, form: String = "", level: Double, ivs: (Int, Int, Int), gender: String = "") -> JSONValue {
        let json = """
        {"index":\(index),"name":"\(name)","form":"\(form)","gender":"\(gender)","cp":500,"level":\(level),"shadow":false,"purified":false,"lucky":false,
         "ivs":{"atk":\(ivs.0),"def":\(ivs.1),"hp":\(ivs.2)},"ivPercent":80,"moves":[]}
        """
        return try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    private func leagues() throws -> [Int: JSONValue] {
        let box = JSONValue.array([
            record(index: 1, name: "Eevee", level: 12, ivs: (6, 7, 12)),
            record(index: 2, name: "Zygarde", form: "10%", level: 20, ivs: (10, 12, 14)),
            record(index: 3, name: "Magnemite", level: 5, ivs: (2, 5, 11)),
            record(index: 4, name: "Kirlia", level: 20, ivs: (10, 12, 14)),
        ])
        let report = try CoreEngine().advise(box: box)
        var out = [Int: JSONValue]()
        for e in report["pokemon"]?.arrayValue ?? [] {
            guard case .number(let i)? = e["p"]?["index"], let l = e["leagues"] else { continue }
            out[Int(i)] = l
        }
        return out
    }

    func testEngineOutputDecodesForEveryLeague() throws {
        let all = try leagues()
        XCTAssertEqual(all.count, 4)
        for (index, l) in all {
            for key in LeaguePanel.keys {
                let rating = try XCTUnwrap(l[key].flatMap(BoxAdvice.LeagueRating.decode), "entry \(index) \(key)")
                XCTAssertFalse(rating.options.isEmpty)
                XCTAssertTrue(["export", "emulated", "ranked", "fallback"].contains(rating.source))
                XCTAssertEqual(l[key]?["options"]?.arrayValue?.count, rating.options.count, "no option was dropped")
            }
        }
    }

    func testEeveeListsEveryEvolutionAndShowsOne() throws {
        let eevee = try XCTUnwrap(try leagues()[1])
        let gl = try XCTUnwrap(BoxAdvice.LeagueRating.decode(try XCTUnwrap(eevee["gl"])))
        XCTAssertEqual(Set(gl.options.map(\.speciesId)), ["eevee", "vaporeon", "jolteon", "flareon", "espeon", "umbreon", "leafeon", "glaceon", "sylveon"])
        XCTAssertEqual(gl.source, "emulated")
        XCTAssertTrue(gl.options.contains { $0.isSelf && $0.speciesId == "eevee" })
        // Ranked members come first, strongest first.
        let scores = gl.options.compactMap { $0.strength?.score }
        XCTAssertEqual(scores, scores.sorted(by: >))
        XCTAssertEqual(gl.options.prefix(scores.count).compactMap { $0.strength }.count, scores.count, "the ranked ones lead")
        // The accessors read the shown member, and the experimental one is a real member too.
        XCTAssertEqual(gl.pick.speciesId, gl.options[gl.pickIndex].speciesId)
        XCTAssertNotNil(gl.options[gl.pickIndex].iv)
        XCTAssertTrue(gl.options.indices.contains(gl.experimentalIndex))
        let card = LeaguePanel.card(gl, shown: gl.pickIndex, key: "gl", level: 17)
        XCTAssertEqual(card.option.speciesId, gl.pick.speciesId)
    }

    func testEveryRankedOptionCarriesItsMoves() throws {
        let eevee = try XCTUnwrap(try leagues()[1])
        for key in LeaguePanel.keys {
            let rating = try XCTUnwrap(BoxAdvice.LeagueRating.decode(try XCTUnwrap(eevee[key])))
            for o in rating.options { XCTAssertEqual(o.moves != nil, o.strength != nil, "\(key) \(o.speciesId): moves exactly where PvPoke ranks it") }
            XCTAssertGreaterThan(rating.options.filter { $0.moves != nil }.count, 2, "\(key): more than the shown and experimental option")
        }
    }

    func testZygardeTenPercentReachesComplete() throws {
        let z = try XCTUnwrap(try leagues()[2])
        let ml = try XCTUnwrap(BoxAdvice.LeagueRating.decode(try XCTUnwrap(z["ml"])))
        XCTAssertTrue(ml.options.contains { $0.speciesId == "zygarde_complete" })
        let complete = try XCTUnwrap(ml.options.first { $0.speciesId == "zygarde_complete" })
        XCTAssertEqual(complete.cost?.evolveCandy, 0, "a form change costs no candy")
    }

    func testGenderLockedOptionIsLabelledWhenSexUnknown() throws {
        let kirlia = try XCTUnwrap(try leagues()[4])
        let ul = try XCTUnwrap(BoxAdvice.LeagueRating.decode(try XCTUnwrap(kirlia["ul"])))
        XCTAssertEqual(ul.options.first { $0.speciesId == "gallade" }?.genderLocked, "male")
    }

    func testOneBadOptionDoesNotDropTheLeagueButABadPickDoes() throws {
        let magnemite = try XCTUnwrap(try leagues()[3])
        let gl = try XCTUnwrap(magnemite["gl"])
        guard case .object(var obj) = gl, case .array(var options)? = obj["options"], case .number(let pick)? = obj["pick"], case .number(let exp)? = obj["experimental"] else { return XCTFail("shape") }
        XCTAssertGreaterThan(options.count, 2)
        let pickIndex = Int(pick), expIndex = Int(exp)
        // The first member that is neither the pick nor the experimental one, so dropping it re-indexes whatever follows it.
        let victim = try XCTUnwrap(options.indices.first { $0 != pickIndex && $0 != expIndex })
        func id(_ o: JSONValue) -> String { if case .string(let s)? = o["speciesId"] { return s } else { return "" } }
        let pickedId = id(options[pickIndex]), experimentalId = id(options[expIndex])
        // Break that member: its strength becomes a string.
        guard case .object(var broken) = options[victim] else { return XCTFail("option") }
        broken["strength"] = .string("oops")
        options[victim] = .object(broken)
        obj["options"] = .array(options)
        let rating = try XCTUnwrap(BoxAdvice.LeagueRating.decode(.object(obj)), "the league survives one bad option")
        XCTAssertEqual(rating.options.count, options.count - 1)
        XCTAssertEqual(rating.shown.speciesId, pickedId, "the pick still points at the same member")
        XCTAssertEqual(rating.experimental.speciesId, experimentalId, "the experimental pick still points at the same member")
        XCTAssertFalse(rating.options.contains { $0.speciesId == id(options[victim]) }, "the bad member is the one dropped")

        // Break the pick itself: there is nothing to show, so the league is dropped (and the others in the box are untouched).
        guard case .object(var brokenPick) = options[pickIndex] else { return XCTFail("option") }
        brokenPick["overCap"] = .string("oops")
        options[pickIndex] = .object(brokenPick)
        obj["options"] = .array(options)
        XCTAssertNil(BoxAdvice.LeagueRating.decode(.object(obj)))
    }
}
