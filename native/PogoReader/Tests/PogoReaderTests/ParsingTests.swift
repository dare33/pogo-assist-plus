import XCTest
@testable import PogoReader

final class ParsingTests: XCTestCase {
    func testParseCpTakesDigitsAfterLastLetterAndMapsO() {
        XCTAssertEqual(parseCp("CP3028"), 3028)
        XCTAssertEqual(parseCp("CP 3028"), 3028)
        XCTAssertEqual(parseCp("P2651"), 2651)
        XCTAssertEqual(parseCp("cp3O28"), 3028)
        XCTAssertEqual(parseCp("711"), 711)
        XCTAssertEqual(parseCp("CP4 262"), 4262)       // Vision puts a space inside the figure
        XCTAssertEqual(parseCp("CP 2 641"), 2641)
        XCTAssertEqual(parseCp("5p2641"), 2641)
        XCTAssertNil(parseCp("7"))
        XCTAssertNil(parseCp(""))
    }

    /// Strings that junk or a garbled label glued onto a CP: each is no read, or the figure alone.
    func testParseCpDoesNotGlueJunkOntoTheFigure() {
        for junk in ["99 O", "66 O", "CP2 OO", "CP1 6", "CP1S 66", "CP1234 5", "CP1A86", "1234dO", "1 2", "CPL", "O", "CP 7",
                     "1A86", "CP 1A86", "2.641", "CP 2,641", "CP²641", "CP0 001", "CP 0 000", "CP O 28", "01", "CP 05"] {
            XCTAssertNil(parseCp(junk), junk)
        }
        // What stays a read.
        XCTAssertEqual(parseCp("CP4 262"), 4262)
        XCTAssertEqual(parseCp("CP2 008"), 2008)
        XCTAssertEqual(parseCp("CP 2 641"), 2641)
        XCTAssertEqual(parseCp("4 262"), 4262)
        XCTAssertEqual(parseCp("ap2621"), 2621)
        XCTAssertEqual(parseCp("5p2641"), 2641)
        XCTAssertEqual(parseCp("SP2614"), 2614)
        XCTAssertEqual(parseCp("cI 2000"), 2000)
        XCTAssertEqual(parseCp("i 5p2641"), 2641)
        XCTAssertEqual(parseCp("CPL 262"), 262)
        XCTAssertEqual(parseCp("cp₴641"), 641)
        XCTAssertEqual(parseCp("cp3O28"), 3028)
        // The frame reader's shape check agrees: "1234dO" has no figure at its end, so it is no read either way.
        XCTAssertNil(parseCp("1234dO"))
    }

    /// Reviewers' findings: more junk that glued onto a figure, and reads that can be taken safely.
    func testParseCpRound6() {
        for junk in ["5pX2641", "CP0123", "CPO28", "1A862", "CP12345", "23028", "CP o 1500", "CP 12 345", "2p641", "1p2641"] {
            XCTAssertNil(parseCp(junk), junk)
        }
        // Safe reads: one label digit (5, 6 or 8, a misread C) then a P, with a figure of two digits or more.
        XCTAssertEqual(parseCp("5p86"), 86)
        XCTAssertEqual(parseCp("8P150"), 150)
        XCTAssertEqual(parseCp("5p2641"), 2641)
        XCTAssertEqual(parseCp("8p2611"), 2611)
        XCTAssertEqual(parseCp("op2614"), 2614)       // the iPad's "op" label: its o is a 0 inside a token with digits
        XCTAssertEqual(parseCp("0r1999"), 1999)
        XCTAssertEqual(parseCp("CP 3028"), 3028)
        XCTAssertEqual(parseCp("cp3O28"), 3028)
    }

    func testParseHpReadsCurrentAndMax() {
        XCTAssertEqual(parseHp("145 / 145 HP"), HP(current: 145, max: 145))
        XCTAssertEqual(parseHp("79/79 1"), HP(current: 79, max: 79))
        XCTAssertNil(parseHp("HP"))
    }

    /// Fault 5: the iPad's team leader covers the end of the text.
    func testParseHpRejectsCurrentAboveMax() {
        XCTAssertNil(parseHp("139 / 13"))
        XCTAssertNil(parseHp("130/13"))
        XCTAssertEqual(parseHp("100 / 139 HP"), HP(current: 100, max: 139)) // a damaged Pokémon is still a read
    }

    func testCpSimilar() {
        XCTAssertTrue(cpSimilar(3028, 3023))
        XCTAssertTrue(cpSimilar(902, 92))
        XCTAssertFalse(cpSimilar(902, 2))
        XCTAssertTrue(cpSimilar(2223, 223))
        XCTAssertTrue(cpSimilar(1969, 1962))
        XCTAssertFalse(cpSimilar(3028, 2592))
        XCTAssertFalse(cpSimilar(22, 2692))
        XCTAssertFalse(cpSimilar(1614, 94))
    }

    func testCpAndHpFormulas() {
        let mewtwo = table.byId["mewtwo"]!.baseStats
        let max = IVs(atk: 15, def: 15, hp: 15)
        XCTAssertEqual(cpAt(mewtwo, max, 40), 4178)
        XCTAssertEqual(cpAt(mewtwo, max, 20), 2387)
        XCTAssertEqual(cpm(25), 0.667934)
        XCTAssertEqual(levels.count, 101)
        XCTAssertEqual(hpAt(BaseStats(atk: 100, def: 100, hp: 100), IVs(atk: 0, def: 0, hp: 0), 1), 10)
    }

    func testJsonShapeMatchesTheJsReading() throws {
        var r = FrameReading(frame: "f0001.png", time: 0.2)
        r.cp = 1234; r.cpText = "CP1234"; r.cpReads = [1234]; r.name = "Zapdos"; r.baseName = "Zapdos"; r.form = ""; r.speciesIds = ["zapdos"]
        r.nameText = "Zapdos"; r.nameConfidence = 92; r.nameDistance = 0; r.nameWeak = false
        r.hp = HP(current: 129, max: 129); r.hpText = "129 / 129 HP"; r.ivs = IVs(atk: 1, def: 2, hp: 3); r.ivConfidence = 0.9; r.fills = [0.1, 0.2, 0.3]; r.sharpness = 5
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as! [String: Any]
        let expected: Set<String> = ["frame", "time", "cp", "cpText", "cpReads", "name", "baseName", "form", "speciesIds", "nameText", "nameConfidence", "nameDistance", "nameWeak", "hp", "hpText", "ivs", "ivConfidence", "fills", "sharpness", "flags"]
        XCTAssertEqual(Set(obj.keys), expected)
        XCTAssertEqual((obj["hp"] as! [String: Int]), ["current": 129, "max": 129])
        XCTAssertEqual((obj["ivs"] as! [String: Int]), ["atk": 1, "def": 2, "hp": 3])
        // A frame that read nothing still writes the fields the JS initialises to null.
        let empty = try JSONSerialization.jsonObject(with: JSONEncoder().encode(FrameReading(frame: "x", time: 0))) as! [String: Any]
        for k in ["cp", "name", "hp", "ivs", "fills"] { XCTAssertTrue(empty[k] is NSNull, k) }
        XCTAssertNil(empty["baseName"])
        // Round trip.
        let back = try JSONDecoder().decode(FrameReading.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }
}
