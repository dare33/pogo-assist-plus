import XCTest
@testable import PogoReader

private let moltres = table.byId["moltres"]!
private let IVS = IVs(atk: 11, def: 14, hp: 11)
private let LEVEL = 25.0
private let CP = cpAt(moltres.baseStats, IVS, LEVEL), HPV = hpAt(moltres.baseStats, IVS, LEVEL)

/// A reading as FrameReader returns it, for a real species so the checks have stats to work with.
private func frame(_ cp: Int?, hp: Int? = HPV, ivs: IVs? = IVS, name: String = "Moltres", n: Int = 0, conf: Double = 0.95, weak: Bool = false) -> FrameReading {
    var r = FrameReading(frame: "f\(n)", time: Double(n) / 5)
    r.name = name; r.nameText = name; r.baseName = name; r.form = ""; r.speciesIds = candidate(name).speciesIds
    r.cp = cp; r.cpReads = cp.map { [$0] } ?? []; r.cpText = cp.map(String.init) ?? ""
    r.hp = hp.map { HP(current: $0, max: $0) }; r.ivs = ivs; r.ivConfidence = ivs == nil ? 0 : conf
    r.nameWeak = weak
    r.flags = cp == nil ? ["no-cp-text"] : []
    return r
}
private func swipe() -> FrameReading { var r = FrameReading(frame: "swipe"); r.flags = ["mid-swipe"]; return r }
/// What a real swipe leaves: a mid-swipe frame then frames with no anchors (3 to 7 of them on the marathon clips).
private func swipes(_ n: Int = 4) -> [FrameReading] { (0..<n).map { _ in swipe() } }

private func groupAll(_ readings: [FrameReading]) -> [LiveRow] {
    var g = LiveGrouper(species: table)
    for r in readings { g.add(r) }
    g.finish()
    return g.rows
}

final class GrouperTests: XCTestCase {
    func testOnePokemonAcrossAnUnreadableFrameAndAGarbledCpIsOneRow() {
        let rows = groupAll([frame(3028, hp: 145, ivs: IVs(atk: 15, def: 14, hp: 15), name: "Xurkitree", n: 1), swipe(),
                        frame(3023, hp: 145, ivs: IVs(atk: 15, def: 14, hp: 15), name: "Xurkitree", n: 3),
                        frame(3028, hp: 145, ivs: IVs(atk: 15, def: 14, hp: 15), name: "Xurkitree", n: 4),
                        frame(2692, hp: 137, ivs: IVs(atk: 13, def: 12, hp: 14), name: "Zamazenta", n: 5)])
        XCTAssertEqual(rows.map(\.name), ["Xurkitree", "Zamazenta"])
        XCTAssertEqual(rows[0].frames, 3)
        XCTAssertEqual(rows[0].cp, 3028)
        XCTAssertEqual(rows.map(\.index), [1, 2])
    }

    func testADifferentHpSplitsEvenWithTheSameNameAndCp() {
        let rows = groupAll([frame(14, hp: 13, ivs: IVs(atk: 12, def: 4, hp: 15), name: "Meltan", n: 1), frame(14, hp: 13, ivs: IVs(atk: 12, def: 4, hp: 15), name: "Meltan", n: 2), frame(14, hp: 13, ivs: IVs(atk: 12, def: 4, hp: 15), name: "Meltan", n: 3),
                          frame(14, hp: 12, ivs: IVs(atk: 1, def: 1, hp: 1), name: "Meltan", n: 4), frame(14, hp: 12, ivs: IVs(atk: 1, def: 1, hp: 1), name: "Meltan", n: 5), frame(14, hp: 12, ivs: IVs(atk: 1, def: 1, hp: 1), name: "Meltan", n: 6)])
        XCTAssertEqual(rows.count, 2)
    }

    func testTwoAdjacentPokemonStayApartWhenBothCpAndSettledBarsDiffer() {
        let a = IVs(atk: 10, def: 5, hp: 12), b = IVs(atk: 12, def: 6, hp: 12)
        let rows = groupAll([frame(135, hp: 49, ivs: a, name: "Pidgey"), frame(135, hp: 49, ivs: a, name: "Pidgey"), frame(135, hp: 49, ivs: a, name: "Pidgey")] + swipes()
                        + [frame(139, hp: 49, ivs: b, name: "Pidgey"), frame(139, hp: 49, ivs: b, name: "Pidgey"), frame(139, hp: 49, ivs: b, name: "Pidgey")])
        XCTAssertEqual(rows.map(\.cp), [135, 139])
    }

    func testVotesTheCpTheHpAndTheSettledBars() {
        let rows = groupAll([frame(1614, hp: 94, ivs: IVs(atk: 8, def: 4, hp: 8), name: "Hitmonlee", conf: 0.58),
                        frame(1614, hp: 94, ivs: IVs(atk: 8, def: 1, hp: 8), name: "Hitmonlee", conf: 0.92),
                        frame(1641, hp: 94, ivs: IVs(atk: 8, def: 1, hp: 8), name: "Hitmonlee", conf: 0.92),
                        frame(1614, hp: nil, ivs: IVs(atk: 8, def: 1, hp: 8), name: "Hitmonlee", conf: 0.92)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cp, 1614)
        XCTAssertEqual(rows[0].hp, 94)
        XCTAssertEqual(rows[0].ivs, IVs(atk: 8, def: 1, hp: 8))
        XCTAssertEqual(rows[0].frames, 4)
    }

    func testUnsettledBarsAreTheFallbackAndFlagged() {
        let rows = groupAll([frame(1970, hp: 132, ivs: IVs(atk: 6, def: 6, hp: 6), name: "Zapdos", conf: 0.1), frame(1970, hp: 132, ivs: IVs(atk: 11, def: 12, hp: 13), name: "Zapdos", conf: 0.3)])
        XCTAssertEqual(rows[0].ivs, IVs(atk: 11, def: 12, hp: 13))
        XCTAssertTrue(rows[0].flags.contains("bars-unsettled"))
    }

    func testSameCpWithAChanceSettledMidAnimationReadStaysOneRowAndFlagsTheDisagreement() {
        let rows = groupAll([frame(492, hp: 74, ivs: IVs(atk: 13, def: 14, hp: 6), name: "Meltan", conf: 0.9), frame(492, hp: 74, ivs: IVs(atk: 8, def: 14, hp: 1), name: "Meltan", conf: 0.9), frame(492, hp: 74, ivs: IVs(atk: 8, def: 14, hp: 1), name: "Meltan", conf: 0.9)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].ivs, IVs(atk: 8, def: 14, hp: 1))
        XCTAssertTrue(rows[0].flags.contains("ivs-disagree"))
    }

    /// Fault 3: the leading digit is behind the model; the CP is worked out from HP, bars and the digits read.
    func testACpWhoseLeadingDigitIsHiddenIsRecoveredFromHpBarsAndTheTail() {
        let tail = CP % 1000
        XCTAssertTrue(CP >= 1000 && tail >= 100, "the example needs a four-digit CP")
        let rows = groupAll((1...5).map { frame(tail, n: $0) })
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cp, CP)
        XCTAssertEqual(rows[0].ivs, IVS)
        XCTAssertEqual(rows[0].flags, ["cp-recovered:\(CP)-from-\(tail)"])
    }

    func testACpReadInFullThatDoesNotFitIsNeverReplacedByARecoveredOne() {
        let wrong = IVs(atk: IVS.atk + 2, def: IVS.def, hp: IVS.hp)
        let decoy = cpOptions([moltres], hp: HPV, ivs: wrong).options[0]
        XCTAssertNotEqual(decoy, CP)
        let rows = groupAll([frame(CP, ivs: wrong, n: 1), frame(CP, ivs: wrong, n: 2), frame(CP, ivs: wrong, n: 3), frame(decoy % 1000, ivs: wrong, n: 4)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].cp, CP)
        XCTAssertFalse(rows[0].flags.contains { $0.hasPrefix("cp-recovered") })
    }

    func testAnyFullLengthReadBlocksRecoveryEvenOneAgainstSeveralShortOnes() {
        let wrong = IVs(atk: IVS.atk + 2, def: IVS.def, hp: IVS.hp)
        let decoy = cpOptions([moltres], hp: HPV, ivs: wrong).options[0]
        let rows = groupAll([frame(CP, ivs: wrong, n: 1)] + (2...4).map { frame(decoy % 100, ivs: wrong, n: $0) })
        XCTAssertTrue(rows.allSatisfy { !$0.flags.contains { $0.hasPrefix("cp-recovered") } })
    }

    func testCpOptionsListsTheCpsThatFitAndWhichPartialReadIsTheirTail() {
        let r = cpOptions([moltres], hp: HPV, ivs: IVS, ivConfidence: 0.95, reads: [CP % 1000, CP % 100])
        XCTAssertTrue(r.options.contains(CP))
        XCTAssertEqual(r.supported, [CP])
        XCTAssertEqual(r.tailOf[CP], CP % 1000)
        XCTAssertEqual(cpOptions([moltres], hp: HPV, ivs: IVS, ivConfidence: 0.3).options, [])   // unsettled bars prove nothing
        XCTAssertEqual(cpOptions([moltres], hp: HPV, ivs: IVS, reads: [CP % 10]).supported, [])  // one digit is not evidence
    }

    func testFramesWithTheCpHiddenNeverSplitARunNextToTheSamePokemon() {
        let rows = groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(nil, n: 3), frame(nil, n: 4)])
        XCTAssertEqual(rows.count, 1)
        let before = groupAll([frame(nil, n: 1), frame(CP, n: 2), frame(CP, n: 3)])
        XCTAssertEqual(before.count, 1)
    }

    func testAHiddenCpPokemonOfItsOwnIsListedAndItsOnlyFittingCpIsWorkedOut() {
        let rows = groupAll([frame(CP + 9, hp: HPV + 1, ivs: nil, n: 1), frame(CP + 9, hp: HPV + 1, ivs: nil, n: 2), frame(CP + 9, hp: HPV + 1, ivs: nil, n: 3)] + swipes()
                            + [frame(nil, n: 4), frame(nil, n: 5), frame(nil, n: 6)] + swipes()
                            + [frame(CP - 9, hp: HPV - 1, ivs: nil, n: 8), frame(CP - 9, hp: HPV - 1, ivs: nil, n: 9), frame(CP - 9, hp: HPV - 1, ivs: nil, n: 10)])
        XCTAssertEqual(rows.map(\.cp), [CP + 9, CP, CP - 9])
        XCTAssertEqual(rows[1].flags, ["cp-computed:\(CP)"])
        XCTAssertEqual(rows.map(\.index), [1, 2, 3])
        // One or two such frames with no HP are a card sliding past, not an entry.
        XCTAssertEqual(groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(CP, n: 3)] + swipes() + [frame(nil, hp: nil, n: 3), frame(nil, hp: nil, n: 4)] + swipes() + [frame(CP - 9, hp: HPV - 1, ivs: nil, n: 6), frame(CP - 9, hp: HPV - 1, ivs: nil, n: 7), frame(CP - 9, hp: HPV - 1, ivs: nil, n: 8)]).count, 2)
        // A hidden Pokémon whose HP and bars allow several CPs stays listed, with the options.
        let ambiguous = cpOptions([moltres], hp: HPV, ivs: IVS).options
        XCTAssertEqual(ambiguous.count, 1)
    }

    /// Two identical Pokémon in a row (marathon-phone Staraptor 1986) are told apart by the swipe between them.
    func testASwipeBetweenTwoIdenticalReadingsMakesTwoRows() {
        let a = (1...4).map { frame(CP, n: $0) }, b = (6...9).map { frame(CP, n: $0) }
        XCTAssertEqual(groupAll(a + swipes() + b).count, 2)
        // A single unreadable frame inside a Pokémon's time on screen does not split it.
        XCTAssertEqual(groupAll(a + [swipe()] + b).count, 1)
        XCTAssertEqual(groupAll(a + swipes(2) + b).count, 1)
    }

    /// iPad junk rows: partial CP reads while a model crosses the CP, and a mid-slide frame, are absorbed.
    func testPartialAndStrayCardsAreAbsorbedIntoTheSamePokemon() {
        let tail = CP % 1000
        // A tail of the real CP (971 of 1971) is the same Pokémon, not a new row.
        let rows = groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(tail, n: 3), frame(CP % 100, n: 4), frame(CP, n: 5)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(cpRelated(1971, 971)); XCTAssertTrue(cpRelated(1971, 197)); XCTAssertTrue(cpRelated(1971, 71))
        XCTAssertFalse(cpRelated(1971, 7)); XCTAssertFalse(cpRelated(1971, 1861))
        // One slide frame with the next card's CP and the last card's HP, bars unsettled, then the next card.
        let slide = frame(CP - 15, hp: HPV + 2, ivs: IVS, n: 5, conf: 0.4)
        let rows2 = groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(CP, n: 3)] + swipes() + [slide, frame(CP - 15, hp: HPV, ivs: IVS, n: 9), frame(CP - 15, hp: HPV, ivs: IVS, n: 10), frame(CP - 15, hp: HPV, ivs: IVS, n: 11)])
        XCTAssertEqual(rows2.map(\.cp), [CP, CP - 15])
        // A one-frame card of another name is not absorbed.
        let other = frame(CP, hp: HPV, ivs: nil, name: "Zapdos", n: 5)
        XCTAssertEqual(groupAll([frame(CP, n: 1), frame(CP, n: 2), frame(CP, n: 3), other, frame(CP, n: 6)]).count, 3)
    }

    func testRowsRememberWhereThePokemonWasOnScreen() {
        let rows = groupAll((1...4).map { frame(CP, n: $0) })
        XCTAssertEqual([rows[0].firstFrame, rows[0].lastFrame], ["f1", "f4"])
        XCTAssertEqual(rows[0].firstTime, 0.2)
    }

    /// Fault 1 in the grouper: a symbol read names the row, and no sex-from-stats flag is needed.
    func testNidoranWithItsSymbolReadHasASexAndWithoutItIsFlagged() {
        func nido(_ ids: [String], n: Int) -> FrameReading { var r = frame(300, hp: 60, ivs: nil, name: "Nidoran", n: n); r.speciesIds = ids; return r }
        let sexed = groupAll([nido(["nidoran_female"], n: 1), nido(["nidoran_female"], n: 2)])
        XCTAssertEqual(sexed[0].name, "Nidoran♀")
        XCTAssertFalse(sexed[0].flags.contains("sex-from-stats"))
        let unsexed = groupAll([nido(["nidoran_female", "nidoran_male"], n: 1)])
        XCTAssertEqual(unsexed[0].name, "Nidoran")
        XCTAssertTrue(unsexed[0].flags.contains("sex-from-stats"))
        // Frames with and without the symbol are still one Pokémon.
        let mixed = groupAll([nido(["nidoran_male"], n: 1), nido(["nidoran_female", "nidoran_male"], n: 2)])
        XCTAssertEqual(mixed.count, 1)
        XCTAssertEqual(mixed[0].name, "Nidoran♂")
    }

    func testAWeakNameOfAnotherSpeciesInsideAPokemonsTimeOnScreenAddsNoRow() {
        func sect(_ n: Int) -> FrameReading { frame(1531, hp: 118, ivs: nil, name: "Parasect", n: n) }
        let rows = groupAll([sect(1), sect(2), frame(1531, hp: 118, ivs: nil, name: "Paras", n: 3, weak: true), sect(4), sect(5)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].frames, 4)
        // A weak read between two other Pokémon is a flagged row of its own.
        let between = groupAll([sect(1), sect(2), frame(700, hp: 50, ivs: nil, name: "Venonat", n: 3, weak: true), swipe(), frame(CP, n: 5), frame(CP, n: 6)])
        XCTAssertEqual(between.map(\.name), ["Parasect", "Venonat", "Moltres"])
        XCTAssertEqual(between[1].flags.contains("name-low-confidence"), true)
    }

    func testRowsAreUpdatedLiveAndMemoryStaysBounded() {
        var g = LiveGrouper(species: table)
        XCTAssertTrue(g.add(frame(CP, n: 1)))
        XCTAssertEqual(g.rows.count, 1)
        XCTAssertFalse(g.add(swipe()))
        // A long run of garbled CPs does not grow the tallies without bound (checked through the row staying one row).
        for n in 2...400 { g.add(frame(CP + (n % 7) - 3, n: n)) }
        XCTAssertEqual(g.rows.count, 1)
        XCTAssertEqual(g.rows[0].frames, 400)
    }

    func testNidorinaRunIsNotInterruptedByANidoranWithALetterStuckToIt() {
        func nidorina(_ n: Int) -> FrameReading { frame(500, hp: 70, ivs: nil, name: "Nidorina", n: n) }
        var stray = frame(500, hp: 70, ivs: nil, name: "Nidoran", n: 3); stray.nameAttached = true
        XCTAssertEqual(groupAll([nidorina(1), nidorina(2), stray, nidorina(4)]).count, 1)
    }
}
