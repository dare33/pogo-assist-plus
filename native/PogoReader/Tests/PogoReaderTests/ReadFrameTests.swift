import XCTest
@testable import PogoReader

/// readFrame's decisions, on a synthetic screen whose anchors the layout code finds for real, with a
/// fake text reader standing in for Vision.
final class ReadFrameTests: XCTestCase {
    private func read(_ img: RGBAImage, _ text: FakeText) -> FrameReading {
        FrameReader(text: text, names: names).read(img, frame: "f", time: 0, wantBars: false)
    }

    func testAConfidentNameGivesAFullReading() {
        let r = read(cardScreen(), FakeText())
        XCTAssertEqual(r.name, "Zapdos")
        XCTAssertEqual(r.cp, 1234)
        XCTAssertEqual(r.hp, HP(current: 129, max: 129))
        XCTAssertEqual(r.nameWeak, false)
        XCTAssertEqual(r.cpReads, [1234])
    }

    func testAtConfidenceZeroOnlyAnExactWholeNameOfFourLettersIsTakenAndMarkedWeak() {
        let ok = read(cardScreen(), FakeText(name: ("Zapdos", 0)))
        XCTAssertEqual(ok.name, "Zapdos")
        XCTAssertEqual(ok.nameWeak, true)
        for text in ["Zapdo", "x Rattata", "Aloan Rattata", "Mew"] {
            let r = read(cardScreen(), FakeText(name: (text, 0)))
            XCTAssertNil(r.name, text)
            XCTAssertEqual(r.cp, 1234, "\(text): an unnamed frame keeps its CP")
            XCTAssertTrue(r.flags.contains("name-unmatched"), text)
        }
        XCTAssertEqual(read(cardScreen(), FakeText(name: ("Zapdo", 90))).name, "Zapdos")
        // The weak line is the named constant.
        XCTAssertEqual(read(cardScreen(), FakeText(name: ("Zapdos", Tuning.weakNameConfidence - 1))).nameWeak, true)
        XCTAssertEqual(read(cardScreen(), FakeText(name: ("Zapdos", Tuning.weakNameConfidence))).nameWeak, false)
    }

    func testNidoranIsTakenAtAnyConfidenceAndIsNotWeak() {
        let r = read(cardScreen(), FakeText(name: ("Nidorano", 37)))
        XCTAssertEqual(r.name, "Nidoran")
        XCTAssertEqual(r.nameWeak, false)
        XCTAssertEqual(Set(r.speciesIds ?? []), ["nidoran_female", "nidoran_male"])
    }

    /// Fault 1: when Vision really reads the symbol, the sex is taken directly.
    func testANidoranSymbolThatWasReadNarrowsTheSpecies() {
        let f = read(cardScreen(), FakeText(name: ("Nidoran♀", 95)))
        XCTAssertEqual(f.name, "Nidoran")
        XCTAssertEqual(f.speciesIds, ["nidoran_female"])
        XCTAssertEqual(f.baseName, "Nidoran♀")
        XCTAssertEqual(read(cardScreen(), FakeText(name: ("Nidoran♂", 95))).speciesIds, ["nidoran_male"])
        XCTAssertEqual(read(cardScreen(), FakeText(name: ("Nidoran 9", 95))).speciesIds?.count, 2) // a stray character is no evidence
    }

    /// Fault 3: no CP text, but the HP bar sits where a settled card puts it.
    func testAFrameWithNoCpTextIsReadOnlyWhenTheHpBarSitsWhereASettledCardPutsIt() {
        let settled = read(cardScreen(cp: false), FakeText())
        XCTAssertNil(settled.cp)
        XCTAssertEqual(settled.name, "Zapdos")
        XCTAssertEqual(settled.hp, HP(current: 129, max: 129))
        XCTAssertTrue(settled.flags.contains("no-cp-text"))
        let sliding = read(cardScreen(cp: false, barX: 0.5), FakeText())
        XCTAssertNil(sliding.name)
        XCTAssertEqual(sliding.flags, ["no-cp-text"])
        XCTAssertNil(read(cardScreen(cp: false, barX: 0.1), FakeText()).name)
    }

    func testNoHpBarIsNotAReading() {
        var img = cardScreen()
        img.fill(Rect(x: 0, y: 340, w: 400, h: 60), (250, 250, 245))   // wipe the bar
        XCTAssertEqual(read(img, FakeText()).flags, ["no-hp-bar"])
        XCTAssertEqual(read(RGBAImage(width: 400, height: 800), FakeText()).flags, ["no-cp-text"])
    }

    func testAnOffCentreCpIsMidSwipe() {
        var img = cardScreen(cp: false)
        for i in 0..<4 { img.fill(Rect(x: 0.55 * 400 + Double(i) * 18, y: 48, w: 8, h: 20), WHITE) }
        let r = read(img, FakeText())
        XCTAssertEqual(r.flags, ["mid-swipe"])
        XCTAssertNil(r.cp)
    }

    /// Fault 2: a Lucky Pokémon's name sits one line up; only a confident exact whole name counts there.
    func testTheLuckyRetryLooksOneLineUpAndTakesOnlyAConfidentExactName() {
        let lucky = FakeText(name: ("LUCKY POKEMON", 90), above: ("Rayquaza", 92))
        XCTAssertEqual(read(cardScreen(lucky: true), lucky).name, "Rayquaza")
        XCTAssertEqual(lucky.nameCalls, 2)
        XCTAssertNil(read(cardScreen(lucky: true), FakeText(name: ("LUCKY POKEMON", 90), above: ("Rayquaza", 20))).name)
        XCTAssertNil(read(cardScreen(lucky: true), FakeText(name: ("LUCKY POKEMON", 90), above: ("Rayquazo", 92))).name)
        let plain = FakeText()
        _ = read(cardScreen(lucky: true), plain)
        XCTAssertEqual(plain.nameCalls, 1)
    }

    func testFlagsForUnreadCpAndHp() {
        let r = read(cardScreen(), FakeText(cp: "CP", hp: "HP"))
        XCTAssertNil(r.cp)
        XCTAssertTrue(r.flags.contains("cp-unread"))
        XCTAssertTrue(r.flags.contains("hp-unread"))
        // A current above the max is no read (fault 5).
        XCTAssertNil(read(cardScreen(), FakeText(hp: "139 / 13")).hp)
    }

    func testNoBarsIsFlaggedWhenThePanelIsMissingAndReadWhenPresent() {
        let reader = FrameReader(text: FakeText(), names: names)
        XCTAssertTrue(reader.read(cardScreen(), wantBars: true).flags.contains("no-bars"))
        // Paste the synthetic panel into the lower half of a card screen.
        var img = cardScreen()
        let p = appraisalPanel(IVs(atk: 12, def: 10, hp: 11), w: 400, h: 400, unit: 5, gap: 3, barH: 8, top: 80, left: 20, rowGap: 45)
        for y in 0..<400 where y + 400 < 800 {
            for x in 0..<400 {
                let s = p.index(x, y), d = img.index(x, y + 400)
                for c in 0..<4 { img.bytes[d + c] = p.bytes[s + c] }
            }
        }
        let r = reader.read(img, wantBars: true)
        XCTAssertEqual(r.ivs, IVs(atk: 12, def: 10, hp: 11))
        XCTAssertEqual(r.fills?.count, 3)
    }
}
